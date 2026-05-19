#!/usr/bin/env bash
# triage-cluster.sh — read-only HyperPod node triage.
#
# Collects signals to route node issues to the right reference section:
#   - Cluster status, orchestrator, NodeRecovery
#   - Cluster events (root-cause signal for provisioning failures)
#   - Per-node health (HyperPod + EKS labels, Slurm state)
#   - VPC / SG config
#   - SSM reachability to compute nodes (hardware checks)
#
# Read-only: never modifies cluster state, never prints remediation commands.
# Each [FAIL] / added issue carries a pointer of the form
#   "... → references/node-diagnostics-detail.md § <section>"
# which the hyperpod-node-debugger skill uses to look up remediation.
#
# Usage:
#   bash triage-cluster.sh --cluster <name-or-arn> --region <region>
#   bash triage-cluster.sh --cluster <name-or-arn> --region <region> --node <instance-id>
#
# Exit codes:
#   0  No critical (P0/P1) issues; P2 informational findings are allowed.
#   1  One or more critical issues, or a fatal prerequisite / cluster-not-found.
#   2  Invalid argument.

set -euo pipefail

for cmd in aws python3; do
  command -v "$cmd" &>/dev/null || {
    echo "ERROR: '$cmd' is required but not found." >&2
    exit 1
  }
done

HAS_UNBUFFER=true
if ! command -v unbuffer &>/dev/null; then
  HAS_UNBUFFER=false
fi

CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-}"
TARGET_NODE=""
USE_COLOR=true

usage() {
  cat <<EOF
Usage: $0 --cluster <name-or-arn> --region <region> [options]

Options:
  --cluster <name-or-arn>   HyperPod cluster name or ARN (required)
  --region <region>         AWS region (required unless \$AWS_DEFAULT_REGION is set)
  --node <instance-id>      Focus on a single instance ID
  --no-color                Disable ANSI colors
  -h, --help                This message

Read-only diagnostic. Every [FAIL] line carries a pointer like
"→ references/node-diagnostics-detail.md § <section>" which the
hyperpod-node-debugger skill uses to look up remediation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)  [[ $# -lt 2 ]] && { echo "ERROR: --cluster needs a value"; exit 2; }
                [[ ! "$2" =~ ^(arn:aws[a-z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:cluster/[a-z0-9]{12}|[a-zA-Z0-9]([-a-zA-Z0-9]{0,62}))$ ]] && { echo "ERROR: --cluster must be a valid HyperPod cluster name or ARN (got '$2')"; exit 2; }
                CLUSTER="$2"; shift 2 ;;
    --region)   [[ $# -lt 2 ]] && { echo "ERROR: --region needs a value"; exit 2; }
                [[ ! "$2" =~ ^[a-z]{2}(-[a-z]+){1,2}-[0-9]+$ ]] && { echo "ERROR: --region must be a valid AWS region (got '$2')"; exit 2; }
                REGION="$2"; shift 2 ;;
    --node)     [[ $# -lt 2 ]] && { echo "ERROR: --node needs a value"; exit 2; }
                [[ ! "$2" =~ ^i-[0-9a-f]{8,17}$ ]] && { echo "ERROR: --node must be an EC2 instance ID (i-xxxxxxxx...)"; exit 2; }
                TARGET_NODE="$2"; shift 2 ;;
    --no-color) USE_COLOR=false; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ -z "$CLUSTER" ]] && {
  echo "Usage: $0 --cluster <name-or-arn> --region <region> [--node <instance-id>]"
  exit 1
}

if [[ -z "$REGION" ]]; then
  echo "ERROR: --region is required (or set AWS_DEFAULT_REGION before running)." >&2
  exit 2
fi

_CREDS=$(aws sts get-caller-identity --output json 2>&1) || {
  echo "ERROR: AWS credentials not configured or expired."
  echo "$_CREDS"
  echo ""
  echo "→ references/node-diagnostics-detail.md § K (Node Access via SSM) for credential setup"
  exit 1
}

# Auto-disable colors when stdout is not a TTY (agent-piped / redirected).
if ! [ -t 1 ] || [ "${TERM:-}" = "dumb" ]; then
  USE_COLOR=false
fi
if "$USE_COLOR"; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

section() { echo ""; echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}"; }
ok()      { echo -e "  ${GREEN}[PASS]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
bad()     { echo -e "  ${RED}[FAIL]${NC} $1"; }
info()    { echo -e "  ${BOLD}[INFO]${NC} $1"; }

ISSUES_FOUND=()
add_issue() {
  local priority="${2:-P1}"
  ISSUES_FOUND+=("${priority}|$1")
}

aws_check_perms() {
  local result="$1" api_name="$2"
  if echo "$result" | grep -qiE "AccessDenied|UnauthorizedOperation|not authorized|AuthorizationError"; then
    warn "Permission denied: $api_name — results may be incomplete"
    add_issue "Missing IAM permission for $api_name → references/node-diagnostics-detail.md § K (Node Access via SSM)" "P1"
    return 0
  fi
  return 1
}

_TEMP_FILES=()
cleanup_temp() {
  [[ ${#_TEMP_FILES[@]} -gt 0 ]] && rm -f "${_TEMP_FILES[@]}" 2>/dev/null || true
}
trap cleanup_temp EXIT

# Run a shell command on a HyperPod node via SSM.
#
# HyperPod uses a SageMaker-managed instance fleet, so `aws ssm send-command`
# with a bare instance-id is not supported. The supported path is
# `aws ssm start-session` with target `sagemaker-cluster:<cluster-id>_<group>-<iid>`
# and document `AWS-StartNonInteractiveCommand`.
#
# Usage: ssm_run_on_node <instance-id> <instance-group-name> "<shell command>"
# Returns remote stdout. start-session does not propagate the remote exit code.
ssm_run_on_node() {
  local iid="$1" grp="$2" cmd="$3"
  [[ -z "$iid" || -z "$grp" || -z "$cmd" ]] && return 1
  [[ ! "$iid" =~ ^i-[0-9a-f]{8,17}$ ]] && return 1
  [[ -z "${CLUSTER_ID:-}" ]] && return 1
  [[ ! "$grp" =~ ^[A-Za-z0-9._-]+$ ]] && return 1

  if [[ "${HAS_UNBUFFER:-true}" != "true" ]]; then
    echo "  [SKIP] on-node SSM probe skipped — install 'unbuffer' (expect package) to enable" >&2
    return 1
  fi

  local target="sagemaker-cluster:${CLUSTER_ID}_${grp}-${iid}"
  local tmp; tmp=$(mktemp 2>/dev/null) || return 1
  chmod 600 "$tmp" 2>/dev/null || true
  _TEMP_FILES+=("$tmp")
  # Embed the command as base64 because AWS-StartNonInteractiveCommand
  # collapses newlines in a single command element.
  local cmd_b64
  cmd_b64=$(printf '%s' "$cmd" | base64 | tr -d '\n') || return 1
  local remote="bash -c \"echo $cmd_b64 | base64 -d | bash\""
  python3 -c "import json,sys; print(json.dumps({'command':[sys.argv[1]]}))" "$remote" > "$tmp" || return 1

  local attempt=0 out rc
  while (( attempt < 5 )); do
    out=$(unbuffer timeout 180 aws ssm start-session \
      --target "$target" \
      --document-name AWS-StartNonInteractiveCommand \
      --parameters "file://$tmp" \
      --region "$REGION" 2>&1)
    rc=$?
    # SSM sometimes returns rc=0 with a transport error baked into stdout —
    # retry those (EOF, SessionManagerPlugin not found, i/o timeout).
    if (( rc == 0 )) && ! echo "$out" | grep -qiE "Cannot perform start session|EOF$|SessionManagerPlugin is not found|ERROR: Unable to|i/o timeout"; then
      # Strip SSM session banners and the echoed base64 command line.
      echo "$out" | grep -vE '^(Starting session with SessionId:|Exiting session with sessionId:|\s*$)' \
                  | grep -vE "^(bash -c \"echo [A-Za-z0-9+/=]+ \| base64 -d \| bash\"|echo '[A-Za-z0-9+/=]+'|[A-Za-z0-9+/=]{40,}={0,2})[[:space:]]*\|?[[:space:]]*base64?[[:space:]]*-?d?[[:space:]]*\|?[[:space:]]*bash\"?\$" || true
      return 0
    fi
    if echo "$out" | grep -qiE "ThrottlingException|RequestLimitExceeded|InternalFailure|InternalError|ServiceUnavailable|TooManyUpdates|Cannot perform start session|EOF$|SessionManagerPlugin is not found|i/o timeout"; then
      attempt=$((attempt + 1))
      sleep $((attempt * 3))
      continue
    fi
    # Non-transient error; surface stderr so callers can diagnose.
    echo "$out" >&2
    return 1
  done
  return 1
}

echo ""
echo -e "${CYAN}${BOLD}HyperPod Node Triage — READ-ONLY${NC}"
echo -e "${CYAN}   No cluster state will be modified. Each issue line below includes a${NC}"
echo -e "${CYAN}   pointer to references/node-diagnostics-detail.md for remediation.${NC}"

section "1. Cluster Identity"

CLUSTER_JSON=$(aws sagemaker describe-cluster \
  --cluster-name "$CLUSTER" \
  --region "$REGION" \
  --cli-read-timeout 30 \
  --output json 2>&1) || {
  echo -e "${RED}ERROR: Cannot find cluster '$CLUSTER' in region '$REGION'${NC}"
  echo ""
  echo "Available clusters in $REGION:"
  aws sagemaker list-clusters --region "$REGION" \
    --query 'ClusterSummaries[*].{Name:ClusterName,Status:ClusterStatus,ARN:ClusterArn}' \
    --output table 2>/dev/null || echo "  (unable to list)"
  exit 1
}

CLUSTER_ARN=$(echo "$CLUSTER_JSON"    | python3 -c "import sys,json; print(json.load(sys.stdin).get('ClusterArn',''))"                2>/dev/null || echo "")
CLUSTER_STATUS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ClusterStatus',''))"             2>/dev/null || echo "")
ORCHESTRATOR=$(echo "$CLUSTER_JSON"   | python3 -c "import sys,json; d=json.load(sys.stdin); print('EKS' if 'Eks' in d.get('Orchestrator',{}) else 'Slurm')" 2>/dev/null || echo "Unknown")
NODE_RECOVERY=$(echo "$CLUSTER_JSON"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('NodeRecovery','Unknown'))"       2>/dev/null || echo "Unknown")
CLUSTER_ID=$(echo "$CLUSTER_ARN" | cut -d/ -f2 2>/dev/null || echo "")

echo -e "  ARN:          ${CLUSTER_ARN}"
echo -e "  Status:       ${BOLD}${CLUSTER_STATUS}${NC}"
echo -e "  Orchestrator: ${ORCHESTRATOR}"
echo -e "  NodeRecovery: ${NODE_RECOVERY}"
echo -e "  ClusterId:    ${CLUSTER_ID}"

[[ "$NODE_RECOVERY" == "None" || "$NODE_RECOVERY" == "Unknown" ]] && \
  warn "NodeRecovery is '$NODE_RECOVERY' — auto-replacement disabled. Manual intervention required for hardware failures."

section "2. Cluster Events (Root Cause Signals)"

# Fetch multiple pages and merge into a single JSON blob. Cap at 500 events to
# bound memory and runtime on long-lived clusters (each page is up to 100).
fetch_cluster_events() {
  local merged='[]' token='' page_json i=0
  while (( i < 5 )); do
    # Only pass --next-token if the token parses as a non-empty, strictly
    # base64/URL-safe string. Sending garbage (e.g. an error message that
    # leaked into $token) would cause ValidationException / BadRequest.
    if [[ -n "$token" && "$token" =~ ^[a-zA-Z0-9/+]*={0,2}$ ]]; then
      page_json=$(aws sagemaker list-cluster-events \
        --cluster-name "$CLUSTER" --region "$REGION" \
        --max-results 100 --next-token "$token" \
        --cli-read-timeout 30 --output json 2>&1) || break
    else
      page_json=$(aws sagemaker list-cluster-events \
        --cluster-name "$CLUSTER" --region "$REGION" \
        --max-results 100 \
        --cli-read-timeout 30 --output json 2>&1) || break
    fi
    local combined
    combined=$(printf '%s\0%s' "$merged" "$page_json" | python3 -c "
import sys, json
blob = sys.stdin.buffer.read()
try:
    a, b = blob.split(b'\0', 1)
    merged = json.loads(a)
    page = json.loads(b)
except (json.JSONDecodeError, ValueError):
    sys.exit(2)
merged.extend(page.get('Events', []))
print(json.dumps(merged))
print(page.get('NextToken','') or '')
" 2>/dev/null) || break
    merged=$(printf '%s\n' "$combined" | sed -n '1p')
    token=$(printf '%s\n'  "$combined" | sed -n '2p')
    i=$((i+1))
    [[ -z "$token" ]] && break
  done
  printf '%s' "$merged" | python3 -c "
import sys, json
try:
    print(json.dumps({'Events': json.loads(sys.stdin.read())}))
except json.JSONDecodeError:
    print('{\"Events\":[]}')
" 2>/dev/null || echo '{"Events":[]}'
}

EVENTS=$(fetch_cluster_events)
if [[ -z "$EVENTS" ]] || echo "$EVENTS" | grep -qE "AccessDenied|not authorized"; then
  aws_check_perms "$EVENTS" "sagemaker:ListClusterEvents"
  EVENTS='{"Events":[]}'
fi

EVENT_COUNT=$(echo "$EVENTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Events',[])))" 2>/dev/null || echo "0")

if [[ "$EVENT_COUNT" -gt 0 ]]; then
  echo -e "  Found ${BOLD}${EVENT_COUNT}${NC} cluster events. Recent events:"
  echo ""

  echo "$EVENTS" | python3 -c "
import sys, json
events = json.load(sys.stdin).get('Events', [])
for e in events[:20]:
    ts = e.get('EventTime','?')
    msg = e.get('Description','') or ''
    grp = e.get('InstanceGroupName','') or ''
    rt = e.get('ResourceType','') or ''
    tag = ''
    low = msg.lower()
    if 'EFA health checks did not run' in msg:
        tag = ' ← [GO TO SECTION A: EFA/SG FIX]'
    elif 'bootstrap failed' in low and 'network' in low:
        tag = ' ← [GO TO SECTION A+B: VPC/EKS FIX]'
    elif 'Lifecycle scripts' in msg or 'lifecycle script' in low:
        tag = ' ← [GO TO SECTION D: LIFECYCLE FIX]'
    elif 'hardware failure' in low:
        tag = ' ← [GO TO SECTION F: HARDWARE]'
    elif 'insufficient capacity' in low or 'sufficient capacity' in low:
        tag = ' ← [GO TO SECTION C: CAPACITY]'
    elif 'failed to provision' in low:
        tag = ' ← [CHECK SECTION C or F]'
    elif 'successfully' in low and 'failed' not in low:
        tag = ' [OK]'
    label = (grp or rt or '?')
    print(f'  [{label}] {ts}')
    print(f'    {msg[:120]}{\"...\" if len(msg) > 120 else \"\"}{tag}')
    print()
" 2>/dev/null

  FAILURE_EVENTS=$(echo "$EVENTS" | python3 -c "
import sys,json
events=json.load(sys.stdin).get('Events',[])
fails=[(e.get('Description','') or '') for e in events if any(k in (e.get('Description','') or '').lower() for k in ['failed','error','timeout','fault','unhealthy'])]
for f in fails[:5]:
    print(f)
" 2>/dev/null || echo "")

  if echo "$FAILURE_EVENTS" | grep -qi "efa health"; then
    add_issue "EFA health check failure → references/node-diagnostics-detail.md § A (EFA / Security Group)" "P0"
  fi
  if echo "$FAILURE_EVENTS" | grep -qi "network misconfiguration\|bootstrap failed"; then
    add_issue "K8s bootstrap network error → references/node-diagnostics-detail.md § A (EFA / Security Group) + § B (VPC / Routing)" "P1"
  fi
  if echo "$FAILURE_EVENTS" | grep -qi "lifecycle script"; then
    add_issue "Lifecycle script failure → references/node-diagnostics-detail.md § D (Lifecycle Scripts)" "P1"
  fi
  if echo "$FAILURE_EVENTS" | grep -qi "hardware failure"; then
    add_issue "Hardware failure detected → references/node-diagnostics-detail.md § F (Hardware / Auto-Repair)" "P1"
  fi
  if echo "$FAILURE_EVENTS" | grep -qi "insufficient capacity"; then
    add_issue "Insufficient capacity → references/node-diagnostics-detail.md § C (Capacity / AZ)" "P1"
  fi
else
  warn "No cluster events available (may be Slurm cluster or no events yet)"
fi

section "3. Node Health Status"

# Paginate list-cluster-nodes — default page is only 10 nodes, so large clusters
# would otherwise be diagnosed on a tiny sample.
fetch_all_cluster_nodes() {
  local merged='[]' token='' page_json combined i=0
  local max_pages=200  # 200 × 100 = 20 000 nodes, supports 7k+ clusters
  while (( i < max_pages )); do
    # Validate token format before sending — avoid BadRequest on garbage.
    if [[ -n "$token" && "$token" =~ ^[a-zA-Z0-9/+]*={0,2}$ ]]; then
      page_json=$(aws sagemaker list-cluster-nodes \
        --cluster-name "$CLUSTER" --region "$REGION" \
        --max-results 100 --next-token "$token" \
        --cli-read-timeout 30 --output json 2>&1) || break
    else
      page_json=$(aws sagemaker list-cluster-nodes \
        --cluster-name "$CLUSTER" --region "$REGION" \
        --max-results 100 \
        --cli-read-timeout 30 --output json 2>&1) || break
    fi
    # Merge via stdin (NUL-delimited) to avoid ARG_MAX truncation at ~500 nodes.
    combined=$(printf '%s\0%s' "$merged" "$page_json" | python3 -c "
import sys, json
blob = sys.stdin.buffer.read()
try:
    a, b = blob.split(b'\0', 1)
    merged = json.loads(a)
    page = json.loads(b)
except (json.JSONDecodeError, ValueError):
    sys.exit(2)
merged.extend(page.get('ClusterNodeSummaries', []))
print(json.dumps(merged))
print(page.get('NextToken','') or '')
" 2>/dev/null) || break
    merged=$(printf '%s\n' "$combined" | sed -n '1p')
    token=$(printf '%s\n'  "$combined" | sed -n '2p')
    i=$((i+1))
    [[ -z "$token" ]] && break
  done
  if (( i == max_pages )) && [[ -n "$token" ]]; then
    echo "WARN: list-cluster-nodes truncated at ${max_pages} pages (~$((max_pages*100)) nodes). Diagnostic sample is incomplete for very large clusters." >&2
  fi
  printf '%s' "$merged" | python3 -c "
import sys, json
try:
    print(json.dumps({'ClusterNodeSummaries': json.loads(sys.stdin.read())}))
except json.JSONDecodeError:
    print('{\"ClusterNodeSummaries\":[]}')
" 2>/dev/null || echo '{"ClusterNodeSummaries":[]}'
}

NODES_JSON=$(fetch_all_cluster_nodes)
if [[ -z "$NODES_JSON" ]] || echo "$NODES_JSON" | grep -qE "AccessDenied|not authorized"; then
  aws_check_perms "$NODES_JSON" "sagemaker:ListClusterNodes"
  NODES_JSON='{"ClusterNodeSummaries":[]}'
fi

TOTAL_NODES=$(echo "$NODES_JSON"   | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('ClusterNodeSummaries',[])))" 2>/dev/null || echo "0")
RUNNING_NODES=$(echo "$NODES_JSON" | python3 -c "import sys,json; print(sum(1 for n in json.load(sys.stdin).get('ClusterNodeSummaries',[]) if n.get('InstanceStatus',{}).get('Status')=='Running'))" 2>/dev/null || echo "0")
BAD_NODES=$(echo "$NODES_JSON"     | python3 -c "import sys,json; print(sum(1 for n in json.load(sys.stdin).get('ClusterNodeSummaries',[]) if n.get('InstanceStatus',{}).get('Status') not in ('Running','')))" 2>/dev/null || echo "0")

echo -e "  Total: ${TOTAL_NODES}  Running: ${GREEN}${RUNNING_NODES}${NC}  Problems: ${RED}${BAD_NODES}${NC}"

if [[ "$BAD_NODES" -gt 0 ]]; then
  echo ""
  echo -e "  ${RED}Non-Running nodes:${NC}"
  echo "$NODES_JSON" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    status=n.get('InstanceStatus',{})
    st=status.get('Status','?')
    if st not in ('Running',''):
        iid=n.get('InstanceId','?')
        grp=n.get('InstanceGroupName','?')
        itype=n.get('InstanceType','?')
        msg=status.get('Message','')
        print(f'  [FAIL] {iid} ({grp} / {itype})')
        print(f'    Status: {st}')
        if msg:
            print(f'    Message: {msg[:100]}')
        print()
" 2>/dev/null
  add_issue "$BAD_NODES node(s) not Running → references/node-diagnostics-detail.md § F (Hardware / Auto-Repair)" "P1"
else
  ok "All $TOTAL_NODES nodes are Running"
fi

if [[ -n "$TARGET_NODE" ]]; then
  echo ""
  echo -e "  ${BOLD}Targeted node: ${TARGET_NODE}${NC}"
  NODE_DETAIL=$(aws sagemaker describe-cluster-node \
    --cluster-name "$CLUSTER" \
    --node-id "$TARGET_NODE" \
    --region "$REGION" \
    --cli-read-timeout 30 \
    --output json 2>&1 || true)
  if echo "$NODE_DETAIL" | grep -qiE "ResourceNotFound|not found|ValidationException"; then
    bad "Node '$TARGET_NODE' not found in cluster '$CLUSTER'"
    info "Verify the instance ID belongs to this cluster:"
    info "  aws sagemaker list-cluster-nodes --cluster-name $CLUSTER --region $REGION --query 'ClusterNodeSummaries[*].InstanceId' --output text"
    add_issue "Node $TARGET_NODE not found in cluster $CLUSTER → verify --cluster and --node arguments" "P0"
    TARGET_NODE=""  # clear so downstream SSM probe doesn't retry on nonexistent node
  elif echo "$NODE_DETAIL" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
    warn "Permission denied: sagemaker:DescribeClusterNode — check IAM policy"
  else
    echo "$NODE_DETAIL" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin).get('NodeDetails',{})
    st=d.get('InstanceStatus',{})
    print(f'  Status: {st.get(\"Status\",\"?\")}')
    print(f'  Launch: {d.get(\"LaunchTime\",\"?\")}')
    print(f'  Message: {st.get(\"Message\",\"\")}')
    print(f'  Type: {d.get(\"InstanceType\",\"?\")}')
    print(f'  Group: {d.get(\"InstanceGroupName\",\"?\")}')
except Exception:
    pass
" 2>/dev/null
  fi
fi

if [[ "$ORCHESTRATOR" == "EKS" ]]; then
  section "4. EKS Node Health Labels"

  if command -v kubectl &>/dev/null; then
    UNHEALTHY_LABELS=$(kubectl get nodes \
      -l 'sagemaker.amazonaws.com/node-health-status notin (Schedulable)' \
      -o custom-columns='NODE:.metadata.name,HEALTH:.metadata.labels.sagemaker\.amazonaws\.com/node-health-status,FAULT:.metadata.labels.sagemaker\.amazonaws\.com/fault-types,DHC:.metadata.labels.sagemaker\.amazonaws\.com/deep-health-check-status' \
      --no-headers 2>/dev/null || echo "")

    if [[ -n "$UNHEALTHY_LABELS" ]]; then
      bad "Nodes with health issues:"
      while IFS= read -r line; do
        echo "    $line"
        if echo "$line" | grep -q "PendingReplacement"; then
          add_issue "Node pending replacement (UnschedulablePendingReplacement) → references/node-diagnostics-detail.md § F (Hardware / Auto-Repair)" "P1"
        elif echo "$line" | grep -q "PendingReboot"; then
          add_issue "Node pending reboot (UnschedulablePendingReboot) → references/node-diagnostics-detail.md § F (Hardware / Auto-Repair)" "P1"
        fi
      done <<< "$UNHEALTHY_LABELS"
    else
      ok "All EKS nodes have healthy labels (Schedulable)"
    fi

    # Check deep health check status. Under `set -o pipefail`, a failed kubectl
    # with `| wc -l || echo 0` yields "0\n0". Count safely via a tmp var.
    DHC_FAILED_OUT=$(kubectl get nodes \
      -l 'sagemaker.amazonaws.com/deep-health-check-status=Failed' \
      -o name 2>/dev/null || true)
    DHC_FAILED=$(echo -n "$DHC_FAILED_OUT" | grep -c . || true)
    [[ -z "$DHC_FAILED" ]] && DHC_FAILED=0
    [[ "$DHC_FAILED" -gt 0 ]] && bad "$DHC_FAILED node(s) have deep-health-check-status=Failed → references/node-diagnostics-detail.md § G (GPU/Accelerator) + § F (Hardware / Auto-Repair)"
  else
    warn "kubectl not available — cannot check EKS node labels (install kubectl to enable this check)"
  fi
fi

if [[ "$ORCHESTRATOR" == "EKS" ]] && command -v kubectl &>/dev/null; then
  section "4a. EKS CNI & System Pod Health"

  CNI_ISSUES=0
  # aws-node (VPC CNI plugin) — if this crashes, no pods can get IPs
  AWS_NODE_DS=$(kubectl get ds -n kube-system aws-node -o json 2>/dev/null || echo "")
  if [[ -n "$AWS_NODE_DS" && "$AWS_NODE_DS" != "" ]]; then
    AWS_NODE_STATUS=$(echo "$AWS_NODE_DS" | python3 -c "
import sys, json
ds = json.load(sys.stdin)
desired = ds.get('status',{}).get('desiredNumberScheduled', 0)
ready = ds.get('status',{}).get('numberReady', 0)
unavail = ds.get('status',{}).get('numberUnavailable', 0)
if unavail > 0:
    print(f'FAIL:{unavail} of {desired} aws-node pods not ready — pod networking broken on those nodes')
elif ready == desired and desired > 0:
    print(f'PASS:aws-node DaemonSet healthy ({ready}/{desired} ready)')
elif desired == 0:
    print('WARN:aws-node DaemonSet has 0 desired pods')
else:
    print(f'WARN:aws-node DaemonSet {ready}/{desired} ready')
" 2>/dev/null || echo "")
    if [[ -n "$AWS_NODE_STATUS" ]]; then
      _level="${AWS_NODE_STATUS%%:*}"
      _msg="${AWS_NODE_STATUS#*:}"
      case "$_level" in
        PASS) ok "$_msg" ;;
        FAIL) bad "$_msg"
              add_issue "aws-node (VPC CNI) pods failing → references/node-diagnostics-detail.md § O (CNI / Pod Networking)" "P0"
              CNI_ISSUES=$((CNI_ISSUES + 1))
              ;;
        WARN) warn "$_msg" ;;
      esac
    fi

    CNI_CRASHES=$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers 2>/dev/null \
      | grep -iE "CrashLoopBackOff|Error|ImagePullBackOff" || true)
    if [[ -n "$CNI_CRASHES" ]]; then
      bad "aws-node pods in crash state:"
      echo "$CNI_CRASHES" | while IFS= read -r line; do echo "    $line"; done
      add_issue "aws-node CrashLoopBackOff — pod networking broken → references/node-diagnostics-detail.md § O (CNI / Pod Networking)" "P0"
      CNI_ISSUES=$((CNI_ISSUES + 1))

      CNI_LOGS=$(kubectl logs -n kube-system -l k8s-app=aws-node --tail=20 2>/dev/null | \
        grep -iE "error|failed|refused|timeout|fatal|gRPC|ipamd|eni" | tail -5 || true)
      if [[ -n "$CNI_LOGS" ]]; then
        info "Recent aws-node error logs:"
        echo "$CNI_LOGS" | while IFS= read -r line; do info "  $line"; done
      fi
    fi
  else
    info "aws-node DaemonSet not found in kube-system (may use alternate CNI)"
  fi

  # kube-proxy — if down, service networking breaks
  KP_CRASHES=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null \
    | grep -iE "CrashLoopBackOff|Error|ImagePullBackOff" || true)
  if [[ -n "$KP_CRASHES" ]]; then
    bad "kube-proxy pods in crash state:"
    echo "$KP_CRASHES" | while IFS= read -r line; do echo "    $line"; done
    add_issue "kube-proxy crash — service networking broken → references/node-diagnostics-detail.md § O (CNI / Pod Networking)" "P0"
    CNI_ISSUES=$((CNI_ISSUES + 1))
  fi

  # CoreDNS — if down, DNS resolution fails (NCCL MASTER_ADDR, service discovery)
  COREDNS_CRASHES=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null \
    | grep -iE "CrashLoopBackOff|Error|ImagePullBackOff" || true)
  if [[ -n "$COREDNS_CRASHES" ]]; then
    bad "CoreDNS pods in crash state — DNS resolution will fail:"
    echo "$COREDNS_CRASHES" | while IFS= read -r line; do echo "    $line"; done
    add_issue "CoreDNS crash — DNS broken → references/node-diagnostics-detail.md § O (CNI / Pod Networking)" "P0"
    CNI_ISSUES=$((CNI_ISSUES + 1))
  fi

  [[ "$CNI_ISSUES" -eq 0 ]] && ok "kube-system networking pods healthy (aws-node, kube-proxy, CoreDNS)"
fi

if [[ "$ORCHESTRATOR" == "Slurm" ]]; then
  section "4b. Slurm Node States"

  if command -v sinfo &>/dev/null; then
    SLURM_DOWN=$(sinfo -o "%N %T %30E" --noheader 2>/dev/null | grep -iE "down|drain|fail" || true)
    if [[ -n "$SLURM_DOWN" ]]; then
      bad "Slurm nodes with issues:"
      echo "$SLURM_DOWN" | while IFS= read -r line; do
        echo "    $line"
      done
      DOWN_COUNT=$(echo "$SLURM_DOWN" | grep -c .)
      add_issue "$DOWN_COUNT Slurm node(s) down/drained → references/node-diagnostics-detail.md § H (Slurm Node Management)" "P1"
    else
      ok "All Slurm nodes show idle/alloc/mixed state"
    fi

    STUCK_JOBS=$(squeue -o "%i %j %T %R %N" --noheader 2>/dev/null | grep -iE "COMPLETING|CONFIGURING" || true)
    if [[ -n "$STUCK_JOBS" ]]; then
      warn "Stuck jobs detected (COMPLETING/CONFIGURING):"
      echo "$STUCK_JOBS" | head -5 | while IFS= read -r line; do echo "    $line"; done
      add_issue "Stuck Slurm jobs → references/node-diagnostics-detail.md § H (Slurm Node Management)" "P1"
    fi
  else
    info "Slurm CLI not available locally — to check Slurm node states, SSM into the head node:"
    info "  sinfo -o '%N %T %30E'"
    info "  squeue -o '%i %j %T %R %N'"
    info ""
    info "Or use SSM to run remotely:"
    if [[ -n "$CLUSTER_ID" ]]; then
      HEAD_NODE=$(echo "$NODES_JSON" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    g=n.get('InstanceGroupName','').lower()
    if any(x in g for x in ['controller','head','master']):
        print(n.get('InstanceId','') + ' ' + n.get('InstanceGroupName',''))
        break
else:
    for n in nodes:
        if n.get('InstanceStatus',{}).get('Status')=='Running':
            print(n.get('InstanceId','') + ' ' + n.get('InstanceGroupName',''))
            break
" 2>/dev/null || echo "")
      if [[ -n "$HEAD_NODE" ]]; then
        H_IID=$(echo "$HEAD_NODE" | awk '{print $1}')
        H_GRP=$(echo "$HEAD_NODE" | awk '{print $2}')
        info "  aws ssm start-session --target sagemaker-cluster:${CLUSTER_ID}_${H_GRP}-${H_IID} --region $REGION"
      fi
    fi
    if command -v session-manager-plugin &>/dev/null && [[ -n "$HEAD_NODE" ]]; then
      H_IID=$(echo "$HEAD_NODE" | awk '{print $1}')
      # Validate instance ID format — defense-in-depth against unexpected input.
      if [[ "$H_IID" =~ ^i-[0-9a-f]{8,17}$ ]]; then
        info ""
        info "Running Slurm checks via SSM on controller ${H_IID}..."
        # Unique delimiter prevents false matches if check output happens to contain marker text.
        local_nonce=$(date +%s%N 2>/dev/null || echo "$RANDOM")
        SLURM_CHECK_SH=$(cat <<EOF
echo SLURM_CHECK_START_${local_nonce}
scontrol show config >/dev/null 2>&1 || echo SLURMCTLD_DOWN_${local_nonce}
echo DOWN_NODES_${local_nonce}
sinfo -o '%20N %10T %30E' --noheader 2>/dev/null | grep -iE 'down|drain|fail' | head -10
echo END_DOWN_${local_nonce}
echo STUCK_COUNT_${local_nonce}
squeue -o '%i %T' --noheader 2>/dev/null | grep -cE 'COMPLETING|CONFIGURING' || echo 0
echo MUNGE_${local_nonce}
systemctl is-active munge 2>/dev/null || echo inactive
echo SLURM_CHECK_END_${local_nonce}
EOF
)
        SSM_STDOUT=$(ssm_run_on_node "$H_IID" "$H_GRP" "$SLURM_CHECK_SH" || echo "")
        if [[ -z "$SSM_STDOUT" ]] || ! echo "$SSM_STDOUT" | grep -q "SLURM_CHECK_START_${local_nonce}"; then
          warn "Slurm SSM probe returned no usable output — controller may be unreachable or SSM agent not responding"
          add_issue "Slurm controller SSM probe failed → references/node-diagnostics-detail.md § K (Node Access via SSM) + § H (Slurm Node Management)" "P1"
        fi
        if echo "$SSM_STDOUT" | grep -q "SLURM_CHECK_START_${local_nonce}"; then
          if echo "$SSM_STDOUT" | grep -q "SLURMCTLD_DOWN_${local_nonce}"; then
            bad "slurmctld not responding on controller — all Slurm operations blocked"
            add_issue "slurmctld down → references/node-diagnostics-detail.md § H (Slurm Node Management)" "P0"
          else
            ok "slurmctld responding"
          fi
          SSM_DOWN_LINES=$(echo "$SSM_STDOUT" | sed -n "/^DOWN_NODES_${local_nonce}\$/,/^END_DOWN_${local_nonce}\$/p" | grep -v "^DOWN_NODES_\|^END_DOWN_" | grep -v "^$" || true)
          if [[ -n "$SSM_DOWN_LINES" ]]; then
            bad "Slurm nodes with issues (via SSM):"
            echo "$SSM_DOWN_LINES" | while IFS= read -r line; do info "  $line"; done
            SSM_DOWN_COUNT=$(echo "$SSM_DOWN_LINES" | grep -c .)
            add_issue "$SSM_DOWN_COUNT Slurm node(s) down/drained → references/node-diagnostics-detail.md § H (Slurm Node Management)" "P1"
          else
            ok "All Slurm nodes healthy (via SSM)"
          fi
          STUCK_COUNT=$(echo "$SSM_STDOUT" | sed -n "/^STUCK_COUNT_${local_nonce}\$/{n;p;}" | tr -d '[:space:]')
          [[ "${STUCK_COUNT:-0}" =~ ^[0-9]+$ ]] && [[ "${STUCK_COUNT:-0}" -gt 0 ]] && \
            add_issue "$STUCK_COUNT stuck Slurm jobs → references/node-diagnostics-detail.md § H (Slurm Node Management)" "P1"
          if echo "$SSM_STDOUT" | sed -n "/^MUNGE_${local_nonce}\$/{n;p;}" | grep -q inactive; then
            bad "munge authentication service inactive on controller"
            add_issue "munge service inactive → references/node-diagnostics-detail.md § H (Slurm Node Management)" "P0"
          fi
        fi
      fi
    fi
  fi
fi

section "5. Cluster VPC Resources"

RESOURCES=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
vpc=d.get('VpcConfig',{})
sgs=vpc.get('SecurityGroupIds',[])
subnets=vpc.get('Subnets',[])
print('SGs=' + ','.join(sgs))
print('Subnets=' + ','.join(subnets))
" 2>/dev/null || echo "")

CLUSTER_SGS=$(echo "$RESOURCES"     | grep "^SGs="     | cut -d= -f2)
CLUSTER_SUBNETS=$(echo "$RESOURCES" | grep "^Subnets=" | cut -d= -f2)

if [[ -n "$CLUSTER_SGS" ]]; then
  echo -e "  Security Groups: ${BOLD}${CLUSTER_SGS}${NC}"
  echo -e "  Subnets:         ${BOLD}${CLUSTER_SUBNETS}${NC}"

  for SG in $(echo "$CLUSTER_SGS" | tr ',' ' '); do
    # Nested JMESPath filter `UserIdGroupPairs[?GroupId=='...']` inside an
    # already-filtered projection returns empty under AWS CLI even when the
    # rule is present — false-flags healthy SGs as a P0. Flatten the array
    # and match in bash instead.
    _SG_RESULT=$(aws ec2 describe-security-groups \
      --group-ids "$SG" --region "$REGION" \
      --cli-read-timeout 15 \
      --query "SecurityGroups[0].IpPermissionsEgress[?IpProtocol=='-1'].UserIdGroupPairs[].GroupId" \
      --output text 2>&1)
    if aws_check_perms "$_SG_RESULT" "ec2:DescribeSecurityGroups"; then
      info "SG check skipped for $SG (permission denied)"
      continue
    fi
    if echo "$_SG_RESULT" | tr '\t' '\n' | grep -qxF "$SG"; then
      ok "SG ${SG} has outbound self-referencing rule (EFA ready)"
    else
      bad "SG ${SG} missing outbound self-referencing rule → EFA will fail"
      add_issue "Missing SG outbound self-ref rule on ${SG} → references/node-diagnostics-detail.md § A (EFA / Security Group)" "P0"
    fi
  done

  if [[ -n "$CLUSTER_SUBNETS" ]]; then
    echo ""
    # shellcheck disable=SC2046  # intentional word splitting for multiple subnet IDs
    IFS=',' read -ra _subnet_arr <<< "$CLUSTER_SUBNETS"
    _SUB_RESULT=$(aws ec2 describe-subnets \
      --subnet-ids "${_subnet_arr[@]}" \
      --region "$REGION" \
      --cli-read-timeout 15 \
      --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,FreeIPs:AvailableIpAddressCount}' \
      --output table 2>&1)
    if ! aws_check_perms "$_SUB_RESULT" "ec2:DescribeSubnets"; then
      echo "$_SUB_RESULT"
    fi
  fi
else
  warn "No VpcConfig found in cluster — cluster may not have customer VPC"
fi

section "6. CloudWatch Logs"

if [[ -n "$CLUSTER_ID" ]]; then
  CLUSTER_NAME_ONLY=$(echo "$CLUSTER" | awk -F/ '{print $NF}')
  LOG_GROUP="/aws/sagemaker/Clusters/${CLUSTER_NAME_ONLY}/${CLUSTER_ID}"
  echo -e "  Log group: ${LOG_GROUP}"

  _LOG_RESULT=$(aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region "$REGION" \
    --cli-read-timeout 15 \
    --query 'logGroups[0].logGroupName' \
    --output text 2>&1)
  if aws_check_perms "$_LOG_RESULT" "logs:DescribeLogGroups"; then
    LOG_EXISTS="None"
  else
    LOG_EXISTS="$_LOG_RESULT"
  fi

  if [[ "$LOG_EXISTS" == "None" || -z "$LOG_EXISTS" ]]; then
    warn "No CloudWatch log group found — logs may not be configured or cluster is new"
    info "Expected: $LOG_GROUP"
  else
    ok "Log group exists: $LOG_EXISTS"

    # Count recent log streams — paginate so the count reflects all streams,
    # not just the first 50 (default CloudWatch page size).
    STREAM_COUNT=0
    _LS_TOKEN=""; _LS_I=0
    while (( _LS_I < 20 )); do
      # Validate token format before sending — avoid BadRequest on garbage.
      if [[ -n "$_LS_TOKEN" && "$_LS_TOKEN" =~ ^[a-zA-Z0-9/+]*={0,2}$ ]]; then
        _LS_PAGE=$(aws logs describe-log-streams --log-group-name "$LOG_GROUP" \
          --region "$REGION" --cli-read-timeout 15 --limit 50 --next-token "$_LS_TOKEN" \
          --output json 2>/dev/null) || break
      else
        _LS_PAGE=$(aws logs describe-log-streams --log-group-name "$LOG_GROUP" \
          --region "$REGION" --cli-read-timeout 15 --limit 50 \
          --output json 2>/dev/null) || break
      fi
      _LS_INC=$(echo "$_LS_PAGE" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('logStreams',[])))" 2>/dev/null || echo 0)
      STREAM_COUNT=$((STREAM_COUNT + _LS_INC))
      _LS_TOKEN=$(echo "$_LS_PAGE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextToken',''))" 2>/dev/null || echo "")
      _LS_I=$((_LS_I + 1))
      [[ -z "$_LS_TOKEN" ]] && break
    done
    info "$STREAM_COUNT log stream(s) available"
    info "To view: aws logs describe-log-streams --log-group-name \"$LOG_GROUP\" --region $REGION --output table"
  fi
fi

section "7. SSM Connectivity"

if command -v session-manager-plugin &>/dev/null; then
  # `command -v` only verifies the binary exists — run --version to confirm it
  # actually works (permissions, broken install, etc.).
  if SSM_VER=$(session-manager-plugin --version 2>/dev/null); then
    ok "SSM Session Manager plugin installed (${SSM_VER})"
  else
    warn "SSM Session Manager plugin installed but --version failed — plugin may be corrupt or missing libs"
    add_issue "SSM plugin installed but broken → references/node-diagnostics-detail.md § K (Node Access via SSM)" "P1"
  fi
else
  warn "SSM Session Manager plugin NOT found"
  info "Install session-manager-plugin (see AWS Systems Manager documentation)"
  add_issue "SSM plugin missing → references/node-diagnostics-detail.md § K (Node Access via SSM)" "P2"
fi

RUNNING_IDS=$(echo "$NODES_JSON" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
ids=[n.get('InstanceId') for n in nodes if n.get('InstanceStatus',{}).get('Status')=='Running']
print(','.join(ids[:3]))
" 2>/dev/null || echo "")

if [[ -n "$RUNNING_IDS" ]]; then
  ok "Running nodes available for SSM (examples: ${RUNNING_IDS})"
  info "Use hyperpod-ssm skill with cluster ID: ${CLUSTER_ID}"
else
  warn "No Running nodes found — SSM access not possible until nodes are healthy"
fi

# 8: On-Node Resource Checks (Memory / Storage / Utilities)
# Runs via SSM on the target node (or first running node) to detect resource
# exhaustion issues that only show up on-node: disk full, /dev/shm too small,
# huge pages misconfigured, OOM signals.

NODE_TO_PROBE="${TARGET_NODE}"
NODE_TO_PROBE_GROUP=""

if [[ -z "$NODE_TO_PROBE" ]]; then
  # Prefer GPU / accelerator nodes: a node probe on a CPU-only utility node
  # produces empty GPU / EFA sections and the user can't tell whether the
  # result is "no hardware" or "hardware is broken." Three-tier fallback
  # so the script still returns something on a CPU-only cluster.
  NODE_TO_PROBE=$(echo "$NODES_JSON" | python3 -c "
import sys, json
nodes = json.load(sys.stdin).get('ClusterNodeSummaries', [])

GPU_PREFIXES = ('ml.p3', 'ml.p3dn', 'ml.p4d', 'ml.p4de', 'ml.p5', 'ml.p5e',
                'ml.p5en', 'ml.p6', 'ml.g4dn', 'ml.g5', 'ml.g6', 'ml.g6e', 'ml.g7e')
NEURON_PREFIXES = ('ml.trn1', 'ml.trn2', 'ml.inf2')
ACCEL_PREFIXES = GPU_PREFIXES + NEURON_PREFIXES

def is_utility(n):
    g = (n.get('InstanceGroupName','') or '').lower()
    return any(x in g for x in ('controller', 'head', 'master'))

running = [n for n in nodes if n.get('InstanceStatus', {}).get('Status','') == 'Running']
tier1 = [n for n in running if (n.get('InstanceType','') or '').startswith(ACCEL_PREFIXES) and not is_utility(n)]
tier2 = [n for n in running if n not in tier1 and not is_utility(n)]
tier3 = [n for n in running if n not in tier1 and n not in tier2]

for n in tier1 + tier2 + tier3:
    print(n.get('InstanceId', ''))
    break
" 2>/dev/null || echo "")
fi

if [[ -n "$NODE_TO_PROBE" ]]; then
  NODE_TO_PROBE_GROUP=$(echo "$NODES_JSON" | NODE_ID_ENV="$NODE_TO_PROBE" python3 -c "
import sys,json,os
target=os.environ['NODE_ID_ENV']
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    if n.get('InstanceId','')==target:
        print(n.get('InstanceGroupName',''))
        break
" 2>/dev/null || echo "")
fi

if [[ -n "$NODE_TO_PROBE" ]] \
    && [[ "$NODE_TO_PROBE" =~ ^i-[0-9a-f]{8,17}$ ]] \
    && [[ -n "$NODE_TO_PROBE_GROUP" ]] \
    && command -v session-manager-plugin &>/dev/null; then
  section "8. On-Node Resource Checks (via SSM)"
  info "Probing node: $NODE_TO_PROBE (group: ${NODE_TO_PROBE_GROUP})"

  resource_nonce=$(date +%s%N 2>/dev/null || echo "$RANDOM")
  RESOURCE_SH=$(cat <<EOF
echo RESOURCE_CHECK_START_${resource_nonce}
echo DISK_ROOT_${resource_nonce}
df -h / 2>/dev/null | tail -1
echo DISK_OPT_${resource_nonce}
df -h /opt/sagemaker 2>/dev/null | tail -1 || echo NOT_MOUNTED
echo DISK_NVME_${resource_nonce}
df -h /opt/dlami/nvme 2>/dev/null | tail -1 || echo NOT_MOUNTED
echo SHM_SIZE_${resource_nonce}
df -h /dev/shm 2>/dev/null | tail -1
echo MEMORY_INFO_${resource_nonce}
free -h | grep Mem
echo HUGEPAGES_${resource_nonce}
cat /proc/meminfo 2>/dev/null | grep -i huge | head -5
echo EFA_HUGE_PAGE_${resource_nonce}
env 2>/dev/null | grep FI_EFA_USE_HUGE_PAGE || echo NOT_SET
echo OOM_RECENT_${resource_nonce}
dmesg 2>/dev/null | grep -iE 'oom|out of memory|cannot allocate' | tail -5 || echo NONE
echo INODE_CHECK_${resource_nonce}
df -i / 2>/dev/null | tail -1
echo TIME_SYNC_${resource_nonce}
chronyc tracking 2>/dev/null | grep -E 'System time|Leap status' || timedatectl status 2>/dev/null | grep -E 'synchronized|NTP service' || echo UNKNOWN
echo SSM_AGENT_${resource_nonce}
systemctl is-active amazon-ssm-agent 2>/dev/null || echo inactive
echo NVME_MOUNTS_${resource_nonce}
lsblk -nr -o NAME,MOUNTPOINT 2>/dev/null | grep -E 'nvme[0-9]+n[0-9]+\$' | head -10 || echo NONE
echo GPU_XID_${resource_nonce}
if command -v nvidia-smi >/dev/null 2>&1; then
  _gpu_xid_out=\$(
    dmesg 2>/dev/null | grep -E 'NVRM: Xid' | tail -10
    nvidia-smi -q 2>/dev/null | awk '
      /Uncorrectable/                                                { if (\$NF ~ /^[0-9]+\$/ && \$NF+0 > 0) print; next }
      /Pending Page (Blacklist|Blocklist|Retirement)/                { if (\$NF ~ /^[0-9]+\$/ && \$NF+0 > 0) print; next }
    '
  )
  if [[ -z "\$_gpu_xid_out" ]]; then echo NONE; else echo "\$_gpu_xid_out" | head -20; fi
else
  echo NO_NVIDIA_SMI
fi
echo GPU_REMAP_${resource_nonce}
# Row-remap state: 'Pending' rows indicate marginal GPU memory that needs a reset
# to finalize the remap. If remap is reported Failed, the GPU is bad.
# A stuck 'Pending' state across reboots is a known firmware edge case that can
# silently degrade training without NCCL/DCGM flagging it — capture explicitly.
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-remapped-rows=gpu_bus_id,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
    --format=csv,noheader 2>/dev/null | head -16 || echo UNSUPPORTED
else
  echo NO_NVIDIA_SMI
fi
echo GPU_DCGM_${resource_nonce}
# DCGM health summary. Presence of 'Health Monitor Report' + 'PASS'/'Warn'/'Fail'
# tells us DCGM has run recently. Absence is informational, not an error.
# Row-remap errors surface here on drivers where nvidia-smi lags the firmware.
if command -v dcgmi >/dev/null 2>&1; then
  dcgmi health --check -j 2>/dev/null | head -40 || dcgmi health --check 2>/dev/null | head -20 || echo DCGM_UNAVAILABLE
else
  echo NO_DCGMI
fi
echo GPU_DCGM_LOGS_${resource_nonce}
# DCGM nvvs log presence — SageMaker HyperPod runs DCGM medium/memtest as part
# of deep-health-check. If this log is present the node has been health-checked
# recently; tail captures last run result.
if [ -d /var/log/nvidia-dcgm ] 2>/dev/null; then
  find /var/log/nvidia-dcgm -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | head -5
  # \$ escapes are required: this heredoc is <<EOF (not <<'EOF'), so unescaped
  # shell variables would expand locally. Keep \$ to defer to the remote shell.
  NVVS_LATEST=\$(find /var/log/nvidia-dcgm -maxdepth 1 -name 'nvvs*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | awk '{print \$2}')
  if [ -n "\$NVVS_LATEST" ]; then
    echo "--- tail of \$NVVS_LATEST ---"
    tail -n 5 "\$NVVS_LATEST" 2>/dev/null || true
  fi
else
  echo NO_DCGM_LOG_DIR
fi
echo KERNEL_PANIC_${resource_nonce}
dmesg 2>/dev/null | grep -iE 'Kernel panic - not syncing|watchdog: BUG|soft lockup|hard lockup|hung_task: blocked|BUG: unable to handle|BUG: kernel NULL|NMI watchdog' | tail -10 || echo NONE
echo CONTAINERD_${resource_nonce}
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active containerd 2>/dev/null || echo inactive
else
  echo UNKNOWN
fi
echo RESOURCE_CHECK_END_${resource_nonce}
EOF
)
  RES_STDOUT=$(ssm_run_on_node "$NODE_TO_PROBE" "$NODE_TO_PROBE_GROUP" "$RESOURCE_SH" || echo "")

  extract_section() {
    local start="$1" end="$2"
    # grep -v returns 1 when every line is filtered out; under pipefail this
    # kills the pipeline even though the EMPTY output is legitimate. Force 0.
    { echo "$RES_STDOUT" | sed -n "/^${start}_${resource_nonce}\$/,/^${end}_${resource_nonce}\$/p" \
      | grep -v "^${start}_${resource_nonce}\$\|^${end}_${resource_nonce}\$" || true; }
  }

  if echo "$RES_STDOUT" | grep -q "RESOURCE_CHECK_START_${resource_nonce}"; then
    echo ""
    echo -e "  ${BOLD}Storage:${NC}"
    ROOT_LINE=$(extract_section DISK_ROOT DISK_OPT | head -1)
    if [[ -n "$ROOT_LINE" ]]; then
      ROOT_USE_PCT=$(echo "$ROOT_LINE" | awk '{print $5}' | tr -d '%')
      if [[ "$ROOT_USE_PCT" =~ ^[0-9]+$ ]] && [[ "$ROOT_USE_PCT" -gt 90 ]]; then
        bad "Root volume: ${ROOT_USE_PCT}% used — CRITICALLY FULL (100GB fixed, cannot expand)"
        add_issue "Root volume ${ROOT_USE_PCT}% full → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P0"
      elif [[ "$ROOT_USE_PCT" =~ ^[0-9]+$ ]] && [[ "$ROOT_USE_PCT" -gt 80 ]]; then
        warn "Root volume: ${ROOT_USE_PCT}% used — approaching full"
        add_issue "Root volume ${ROOT_USE_PCT}% used → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
      else
        ok "Root volume: ${ROOT_USE_PCT:-?}% used"
      fi
    fi

    OPT_LINE=$(extract_section DISK_OPT DISK_NVME | head -1)
    if [[ "$OPT_LINE" != "NOT_MOUNTED" && -n "$OPT_LINE" ]]; then
      OPT_USE=$(echo "$OPT_LINE" | awk '{print $5}' | tr -d '%')
      if [[ "$OPT_USE" =~ ^[0-9]+$ ]] && [[ "$OPT_USE" -gt 90 ]]; then
        warn "/opt/sagemaker: ${OPT_USE}% used — secondary EBS nearing full"
        add_issue "/opt/sagemaker ${OPT_USE}% full → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
      else
        ok "/opt/sagemaker: ${OPT_USE:-?}% used"
      fi
    fi

    NVME_LINE=$(extract_section DISK_NVME SHM_SIZE | head -1)
    if [[ "$NVME_LINE" != "NOT_MOUNTED" && -n "$NVME_LINE" ]]; then
      ok "NVMe instance store: mounted at /opt/dlami/nvme"
    else
      # On GPU training instances NVMe is expected — flag if not mounted
      INSTANCE_TYPE_LOC=$(echo "$NODES_JSON" | NODE_ID_ENV="$NODE_TO_PROBE" python3 -c "
import sys,json,os
target=os.environ['NODE_ID_ENV']
for n in json.load(sys.stdin).get('ClusterNodeSummaries',[]):
    if n.get('InstanceId','')==target:
        print(n.get('InstanceType',''))
        break
" 2>/dev/null || echo "")
      if [[ "$INSTANCE_TYPE_LOC" =~ ^ml\.(p5|p5e|p5en|p4d|p4de|p6|trn1|trn2)\. ]]; then
        warn "/opt/dlami/nvme not mounted on $INSTANCE_TYPE_LOC — instance store expected"
        add_issue "NVMe instance store not mounted on $NODE_TO_PROBE ($INSTANCE_TYPE_LOC) → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
      fi
    fi

    INODE_LINE=$(extract_section INODE_CHECK TIME_SYNC | head -1)
    if [[ -n "$INODE_LINE" ]]; then
      INODE_PCT=$(echo "$INODE_LINE" | awk '{print $5}' | tr -d '%')
      if [[ "$INODE_PCT" =~ ^[0-9]+$ ]] && [[ "$INODE_PCT" -gt 90 ]]; then
        bad "Inode usage: ${INODE_PCT}% — filesystem running out of inodes"
        add_issue "Inode exhaustion ${INODE_PCT}% → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
      fi
    fi

    echo ""
    echo -e "  ${BOLD}Memory:${NC}"
    MEM_LINE=$(extract_section MEMORY_INFO HUGEPAGES | head -1)
    [[ -n "$MEM_LINE" ]] && info "RAM: $MEM_LINE"

    SHM_LINE=$(extract_section SHM_SIZE MEMORY_INFO | head -1)
    if [[ -n "$SHM_LINE" ]]; then
      SHM_SIZE=$(echo "$SHM_LINE" | awk '{print $2}')
      SHM_USE_PCT=$(echo "$SHM_LINE" | awk '{print $5}' | tr -d '%')
      if [[ "$SHM_USE_PCT" =~ ^[0-9]+$ ]] && [[ "$SHM_USE_PCT" -gt 80 ]]; then
        warn "/dev/shm: ${SHM_USE_PCT}% used (size: $SHM_SIZE) — NCCL may fail with 'Bus error'"
        add_issue "/dev/shm ${SHM_USE_PCT}% full → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
      else
        ok "/dev/shm: ${SHM_USE_PCT:-?}% used (size: ${SHM_SIZE:-?})"
      fi
    fi

    EFA_HP=$(extract_section EFA_HUGE_PAGE OOM_RECENT | head -1)
    if [[ "$EFA_HP" == "NOT_SET" ]]; then
      HUGEPAGES_TOTAL=$(extract_section HUGEPAGES EFA_HUGE_PAGE | { grep "HugePages_Total" || true; } | awk '{print $2}')
      if [[ "${HUGEPAGES_TOTAL:-0}" == "0" ]]; then
        warn "FI_EFA_USE_HUGE_PAGE not set and HugePages_Total=0"
        add_issue "FI_EFA_USE_HUGE_PAGE not configured → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P2"
      fi
    elif echo "$EFA_HP" | grep -q "=0"; then
      ok "FI_EFA_USE_HUGE_PAGE=0 (huge pages disabled for EFA — os.fork() safe)"
    fi

    OOM_LINES=$(extract_section OOM_RECENT INODE_CHECK | { grep -v "^NONE$" || true; } | head -3)
    if [[ -n "$OOM_LINES" ]]; then
      echo ""
      bad "Recent OOM events detected on node:"
      echo "$OOM_LINES" | while IFS= read -r line; do info "  $line"; done
      add_issue "OOM events on node $NODE_TO_PROBE → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
    else
      echo ""
      ok "No recent OOM events"
    fi

    # Time sync health — clock drift breaks TLS/SigV4 and Slurm accounting.
    TIME_STATUS=$(extract_section TIME_SYNC SSM_AGENT | head -3)
    if echo "$TIME_STATUS" | grep -qiE "synchronized: no|Not synchronised|UNKNOWN"; then
      warn "Time sync unhealthy — chronyc/timedatectl reports not synchronised"
      info "Clock drift breaks TLS/IAM (SigV4) and Slurm accounting"
      add_issue "Node $NODE_TO_PROBE time sync not healthy → references/node-diagnostics-detail.md § I (Resource Exhaustion)" "P1"
    elif [[ -n "$TIME_STATUS" ]]; then
      ok "Time sync healthy"
    fi

    # SSM agent health — if we got here it's mostly working, but flag if systemd says otherwise.
    SSM_AGENT_STATUS=$(extract_section SSM_AGENT NVME_MOUNTS | head -1)
    if [[ "$SSM_AGENT_STATUS" == "inactive" ]]; then
      warn "amazon-ssm-agent reported inactive — may be restarting or broken"
      add_issue "amazon-ssm-agent inactive on $NODE_TO_PROBE → references/node-diagnostics-detail.md § K (Node Access via SSM)" "P1"
    fi

    # GPU XID / ECC / page-retirement — hardware faults visible via nvidia-smi query.
    GPU_XID_LINES=$(extract_section GPU_XID GPU_REMAP | { grep -v "^NONE$" || true; } | { grep -v "^NO_NVIDIA_SMI$" || true; } | head -5)
    if [[ -n "$GPU_XID_LINES" ]]; then
      echo ""
      bad "GPU XID / ECC / page-retirement signals on node $NODE_TO_PROBE:"
      echo "$GPU_XID_LINES" | while IFS= read -r line; do info "  $line"; done
      add_issue "GPU XID / ECC / page-retirement on $NODE_TO_PROBE → references/node-diagnostics-detail.md § G (GPU/Accelerator) + § F (Hardware / Auto-Repair)" "P0"
    fi

    # GPU row-remapping — marginal GPU memory. Pending rows that never clear
    # indicate a firmware edge case where the remap is stuck; Failed rows mean
    # the GPU is bad and must be replaced. Silent degrader — NCCL and DCGM's
    # default checks can miss this.
    GPU_REMAP_LINES=$(extract_section GPU_REMAP GPU_DCGM | { grep -v "^NO_NVIDIA_SMI$" || true; } | { grep -v "^UNSUPPORTED$" || true; })
    if [[ -n "$GPU_REMAP_LINES" ]]; then
      # Columns (csv,noheader): gpu_bus_id, correctable, uncorrectable, pending, failure
      REMAP_PENDING_TOTAL=0
      REMAP_FAILED_TOTAL=0
      REMAP_UNCORRECT_TOTAL=0
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _p=$(echo "$line" | awk -F, '{gsub(/ /,""); print $4}')
        _f=$(echo "$line" | awk -F, '{gsub(/ /,""); print $5}')
        _u=$(echo "$line" | awk -F, '{gsub(/ /,""); print $3}')
        [[ "$_p" =~ ^[0-9]+$ ]] && REMAP_PENDING_TOTAL=$((REMAP_PENDING_TOTAL + _p))
        [[ "$_u" =~ ^[0-9]+$ ]] && REMAP_UNCORRECT_TOTAL=$((REMAP_UNCORRECT_TOTAL + _u))
        [[ "$_f" == "Yes" || "$_f" == "1" ]] && REMAP_FAILED_TOTAL=$((REMAP_FAILED_TOTAL + 1))
      done <<< "$GPU_REMAP_LINES"
      if [[ "$REMAP_FAILED_TOTAL" -gt 0 ]]; then
        bad "GPU row-remap FAILED on $REMAP_FAILED_TOTAL device(s) — GPU has exceeded remap capacity"
        add_issue "GPU row-remap failure on $NODE_TO_PROBE (bad memory, replace GPU) → references/node-diagnostics-detail.md § G (GPU/Accelerator) + § F (Hardware / Auto-Repair)" "P0"
      elif [[ "$REMAP_PENDING_TOTAL" -gt 0 ]]; then
        bad "GPU row-remap PENDING — $REMAP_PENDING_TOTAL row(s) awaiting reset"
        info "  Pending remaps indicate marginal memory that a GPU reset/reboot should finalize."
        info "  If pending persists across reboots, the firmware may be stuck (known edge case) — escalate."
        add_issue "GPU row-remap pending on $NODE_TO_PROBE (reset/reboot to finalize; if stuck, marginal memory) → references/node-diagnostics-detail.md § G (GPU/Accelerator) + § F (Hardware / Auto-Repair)" "P1"
      elif [[ "$REMAP_UNCORRECT_TOTAL" -gt 0 ]]; then
        warn "GPU has $REMAP_UNCORRECT_TOTAL uncorrectable remapped rows (healthy now, but history of faults)"
      fi
    fi

    GPU_DCGM_LINES=$(extract_section GPU_DCGM GPU_DCGM_LOGS | { grep -v "^NO_DCGMI$" || true; } | { grep -v "^DCGM_UNAVAILABLE$" || true; })
    if [[ -n "$GPU_DCGM_LINES" ]]; then
      if echo "$GPU_DCGM_LINES" | grep -qiE '"overall_health"\s*:\s*"(Fail|Warn)"|HEALTH_RESULT_FAIL|HEALTH_RESULT_WARN|Health Monitor Report.*(Fail|Warn)'; then
        bad "DCGM health check reported Fail/Warn on $NODE_TO_PROBE"
        add_issue "DCGM health Fail/Warn on $NODE_TO_PROBE → references/node-diagnostics-detail.md § G (GPU/Accelerator)" "P0"
      fi
    fi

    # DCGM log presence — informational. Confirms deep-health-check history.
    GPU_DCGM_LOG_LINES=$(extract_section GPU_DCGM_LOGS KERNEL_PANIC)
    if echo "$GPU_DCGM_LOG_LINES" | grep -qi "nvvs"; then
      ok "DCGM nvvs logs present on $NODE_TO_PROBE (/var/log/nvidia-dcgm/)"
      if echo "$GPU_DCGM_LOG_LINES" | grep -qE "^--- tail"; then
        DCGM_TAIL=$(echo "$GPU_DCGM_LOG_LINES" | sed -n '/^--- tail/,$p' | head -20)
        if echo "$DCGM_TAIL" | grep -qiE 'FAIL|Error:|row ?remap.*(pending|fail)'; then
          warn "DCGM nvvs log tail contains failure/row-remap signals — inspect on node:"
          echo "$DCGM_TAIL" | while IFS= read -r line; do info "  $line"; done
          add_issue "DCGM nvvs log shows failure/row-remap signals on $NODE_TO_PROBE → references/node-diagnostics-detail.md § G (GPU/Accelerator)" "P0"
        fi
      fi
    fi

    # Kernel panic / watchdog / hung task signals — indicate node-level instability.
    KERNEL_PANIC_LINES=$(extract_section KERNEL_PANIC CONTAINERD | { grep -v "^NONE$" || true; } | head -5)
    if [[ -n "$KERNEL_PANIC_LINES" ]]; then
      echo ""
      bad "Kernel panic / watchdog / hung_task signals on node $NODE_TO_PROBE:"
      echo "$KERNEL_PANIC_LINES" | while IFS= read -r line; do info "  $line"; done
      add_issue "Kernel panic / watchdog on $NODE_TO_PROBE → references/node-diagnostics-detail.md § N (Kernel & System)" "P0"
    fi

    # containerd health — if the runtime is inactive, every pod on this node fails.
    CONTAINERD_STATUS=$(extract_section CONTAINERD RESOURCE_CHECK_END | head -1)
    if [[ "$CONTAINERD_STATUS" == "inactive" ]]; then
      warn "containerd is inactive on $NODE_TO_PROBE — all pods on this node will fail"
      add_issue "containerd inactive on $NODE_TO_PROBE → references/node-diagnostics-detail.md § M (Container Runtime)" "P0"
    fi

  else
    warn "SSM command returned no output — node may not be reachable"
    add_issue "Cannot reach node $NODE_TO_PROBE via SSM → references/node-diagnostics-detail.md § K (Node Access via SSM)" "P1"
  fi
else
  if [[ -z "$NODE_TO_PROBE" ]]; then
    info "No running nodes to probe for resource checks"
  else
    info "SSM plugin not installed — skipping on-node resource checks → references/node-diagnostics-detail.md § K (Node Access via SSM)"
  fi
fi

if [[ "$ORCHESTRATOR" == "Slurm" && "$TOTAL_NODES" -gt 0 ]]; then
  section "8b. Slurm Node Mapping"
  info "Slurm node name → HyperPod instance ID mapping:"
  info "(PrivateDnsHostname is not in list-cluster-nodes; use 'describe-cluster-node --node-id <i-...>' to retrieve it for a specific instance.)"
  echo ""
  echo "$NODES_JSON" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
print(f'  {\"Instance ID\":<22} {\"Group\":<20} {\"Type\":<22} {\"Status\"}')
print(f'  {\"─\"*22} {\"─\"*20} {\"─\"*22} {\"─\"*10}')
for n in nodes[:20]:
    iid=n.get('InstanceId','?')
    grp=n.get('InstanceGroupName','?')
    itype=n.get('InstanceType','?')
    st=n.get('InstanceStatus',{}).get('Status','?')
    print(f'  {iid:<22} {grp:<20} {itype:<22} {st}')
if len(nodes) > 20:
    print(f'  ... and {len(nodes)-20} more nodes')
" 2>/dev/null
  echo ""
  info "To get PrivateDnsHostname for a specific instance: aws sagemaker describe-cluster-node --cluster-name $CLUSTER --region $REGION --node-id <i-...> --query 'NodeDetails.PrivateDnsHostname' --output text"
fi

section "9. Triage Summary"

echo ""
if [[ ${#ISSUES_FOUND[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}No critical issues detected from available signals.${NC}"
  echo ""
  echo "  Next steps:"
  echo "  • If cluster is still failing: check cluster events above for error details"
  echo "  • For node-level issues: use hyperpod-ssm skill to inspect nodes directly"
  echo "  • For EFA issues: bash scripts/check-efa-sg.sh --cluster ${CLUSTER} --region ${REGION}"
else
  echo -e "  ${RED}${BOLD}Issues found (${#ISSUES_FOUND[@]}):${NC}"
  echo ""
  for priority in P0 P1 P2; do
    has_items=false
    for issue in "${ISSUES_FOUND[@]}"; do
      if [[ "$issue" == "${priority}|"* ]]; then
        if ! "$has_items"; then
          case "$priority" in
            P0) echo -e "  ${RED}${BOLD}[$priority — Fix Immediately]${NC}" ;;
            P1) echo -e "  ${YELLOW}${BOLD}[$priority — Fix Soon]${NC}" ;;
            P2) echo -e "  ${BOLD}[$priority — Informational]${NC}" ;;
          esac
          has_items=true
        fi
        echo -e "    → ${issue#*|}"
      fi
    done
  done
  echo ""
  echo -e "  ${BOLD}Recommended next steps:${NC}"
  echo "  1. Address P0 issues first, then P1. Each issue above includes a"
  echo "     pointer of the form '→ references/node-diagnostics-detail.md § X'."
  echo "  2. The hyperpod-node-debugger skill will open the referenced section"
  echo "     and guide you through the fix with explicit approval."
  echo "  3. After fixing, re-run: bash scripts/triage-cluster.sh --cluster ${CLUSTER} --region ${REGION}"
  echo "  4. For shell access on nodes, use the hyperpod-ssm skill."
fi

echo ""
echo -e "${BOLD}Cluster: ${CLUSTER}  |  Region: ${REGION}  |  Orchestrator: ${ORCHESTRATOR}${NC}"
echo ""

# Exit 1 only on critical (P0/P1) issues so CI / retry loops don't fail on
# P2 informational findings. Fatal prerequisite failures exit 1 earlier at
# argument-validation time.
_critical=0
for _issue in "${ISSUES_FOUND[@]}"; do
  case "${_issue%%|*}" in P0|P1) _critical=$((_critical+1)) ;; esac
done
[[ "$_critical" -eq 0 ]] && exit 0 || exit 1
