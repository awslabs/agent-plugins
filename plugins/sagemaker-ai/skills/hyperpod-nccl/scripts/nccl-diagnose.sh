#!/usr/bin/env bash
# nccl-diagnose.sh — read-only NCCL diagnostic for SageMaker HyperPod.
# Supports both EKS and Slurm orchestrators (auto-detected).
# Hardware checks run on cluster nodes via SSM, not locally.
#
# This script never modifies cluster state. It collects diagnostic signals and
# attaches a reference pointer (→ references/<file>.md § <section>) to each
# finding. The calling skill (hyperpod-nccl) reads this output alongside the
# referenced sections to guide the user through the remediation.
#
# USAGE:
#   bash nccl-diagnose.sh [OPTIONS]
#
# OPTIONS:
#   --cluster       <name>        HyperPod cluster name (required)
#   --region        <region>      AWS region (required)
#   --orchestrator  <eks|slurm>   Force orchestrator (default: auto-detect)
#   --namespace     <ns>          [EKS] K8s namespace to scope (default: all)
#   --job           <job-name>    [EKS] Specific job to diagnose
#   --node          <instance-id> Specific node instance ID for SSM checks
#   --sample-nodes  <N>           How many nodes to SSM into (default: 3)
#   --verbose                     Show extra debug output
#   --no-color                    Disable ANSI colors (also auto-off when not a TTY)
#   --help                        Show this help
#
# ARCHITECTURE:
#   LOCAL checks (run on this machine):
#     - AWS API calls: cluster status, SG rules, cluster events, node list
#     - kubectl calls: K8s node readiness, pod status, logs, NetworkPolicies
#   ON-NODE checks (run via SSM on actual cluster compute nodes):
#     - GPU health (nvidia-smi, XID errors, NVLink)
#     - EFA / libfabric availability
#     - NCCL library presence
#     - Network interfaces and MTU
#     - Memory / /dev/shm / memlock limits
#     - Active training processes
#     - dmesg hardware errors
#   SCALE strategy for 100s of nodes:
#     - AWS API checks cover ALL nodes cheaply via list-cluster-nodes
#     - K8s checks cover ALL nodes cheaply via kubectl
#     - SSM hardware checks sample --sample-nodes (default: 3) compute nodes
#     - CloudWatch log analysis covers ALL nodes at scale (no per-node SSM needed)
#
# EXAMPLES:
#   bash nccl-diagnose.sh --cluster my-cluster --region us-east-1
#   bash nccl-diagnose.sh --cluster my-cluster --region us-east-1 \
#       --namespace nccl-test --job my-job --sample-nodes 5
#   bash nccl-diagnose.sh --cluster my-cluster --region us-east-1 \
#       --node i-0123456789abcdef0
#
# EXIT CODES:
#   0  No critical (P0/P1) issues; P2 informational findings are allowed.
#   1  One or more critical issues, or a fatal prerequisite is missing.
#   2  Invalid argument.

set -euo pipefail

_TEMP_FILES=()
cleanup() {
    # Guard against empty-array + set -u on older bash (4.2 on AL2).
    [[ ${#_TEMP_FILES[@]} -gt 0 ]] && rm -f "${_TEMP_FILES[@]}" 2>/dev/null || true
}
trap cleanup EXIT

# Auto-disable colors when stdout is not a TTY or TERM=dumb (agent-piped output).
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[PASS]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[FAIL]${RESET} $*"; }
header()  { echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════${RESET}"
            echo -e "${BOLD}${BLUE}  $*${RESET}"
            echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════${RESET}"; }
section() { echo -e "\n${BOLD}-- $* --${RESET}"; }
debug()   { $VERBOSE && echo -e "[DEBUG] $*" >&2 || true; }

CLUSTER_NAME=""
REGION="${AWS_DEFAULT_REGION:-}"
ORCHESTRATOR=""
NAMESPACE=""
JOB_NAME=""
NODE_ID=""
SAMPLE_NODES=3
VERBOSE=false
ISSUES_FOUND=0
ISSUE_DETAILS=()
add_issue_detail() {
    local priority="${2:-P1}"
    ISSUE_DETAILS+=("${priority}|$1")
}
K8S_CONNECTED=false
SSM_CLUSTER_ID=""
SSM_NODES=()

usage() {
    # --help exits 0; invalid invocation exits 2 via usage 2.
    grep "^# USAGE:" -A 40 "$0" | grep "^#" | sed 's/^# \?//' | head -25
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cluster)       [[ $# -lt 2 ]] && { error "--cluster needs a value"; exit 2; }
                         [[ ! "$2" =~ ^(arn:aws[a-z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:cluster/[a-z0-9]{12}|[a-zA-Z0-9]([-a-zA-Z0-9]{0,62}))$ ]] && { error "--cluster must be a valid HyperPod cluster name or ARN (got '$2')"; exit 2; }
                         CLUSTER_NAME="$2"; shift 2 ;;
        --region)        [[ $# -lt 2 ]] && { error "--region needs a value"; exit 2; }
                         [[ ! "$2" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]] && { error "--region must be a valid AWS region (got '$2')"; exit 2; }
                         REGION="$2"; shift 2 ;;
        --orchestrator)  [[ $# -lt 2 ]] && { error "--orchestrator needs a value"; exit 2; }
                         [[ "$2" != "eks" && "$2" != "slurm" ]] && { error "--orchestrator must be 'eks' or 'slurm' (got '$2')"; exit 2; }
                         ORCHESTRATOR="$2"; shift 2 ;;
        --namespace)     [[ $# -lt 2 ]] && { error "--namespace needs a value"; exit 2; }
                         [[ ! "$2" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] && { error "--namespace must be a valid K8s namespace (got '$2')"; exit 2; }
                         NAMESPACE="$2"; shift 2 ;;
        --job)           [[ $# -lt 2 ]] && { error "--job needs a value"; exit 2; }
                         [[ ! "$2" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] && { error "--job must be a valid K8s name (got '$2')"; exit 2; }
                         JOB_NAME="$2"; shift 2 ;;
        --node)          [[ $# -lt 2 ]] && { error "--node needs a value"; exit 2; }
                         [[ ! "$2" =~ ^i-[0-9a-f]{8,17}$ ]] && { error "--node must be an EC2 instance ID (got '$2')"; exit 2; }
                         NODE_ID="$2"; shift 2 ;;
        --sample-nodes)  [[ $# -lt 2 ]] && { error "--sample-nodes needs a value"; exit 2; }; SAMPLE_NODES="$2"; shift 2 ;;
        --verbose)       VERBOSE=true; shift ;;
        --no-color)      RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''; shift ;;
        --help|-h)       usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

[[ -z "$CLUSTER_NAME" ]] && { error "Missing required: --cluster"; exit 1; }
[[ -z "$REGION" ]] && { error "--region is required (or set AWS_DEFAULT_REGION before running)"; exit 2; }

if ! [[ "$SAMPLE_NODES" =~ ^[0-9]+$ ]] || [[ "$SAMPLE_NODES" -lt 1 ]]; then
    error "--sample-nodes must be a positive integer (got: '$SAMPLE_NODES')"
    exit 1
fi
if [[ "$SAMPLE_NODES" -gt 50 ]]; then
    warn "--sample-nodes=$SAMPLE_NODES is very high (max recommended: 50). Capping at 50."
    SAMPLE_NODES=50
fi

# Paginate a sagemaker list-* call. Usage:
#   sagemaker_list_paginated list-cluster-nodes ClusterNodeSummaries [extra args...]
# Returns {"<SummaryKey>": [...]} on stdout. Caps at 20 000 items; emits a
# stderr warning if truncated. Returns an empty result on AccessDenied.
sagemaker_list_paginated() {
    local api="$1" summary_key="$2"
    shift 2
    local merged='[]' token='' page_json combined i=0
    local max_pages=200
    while (( i < max_pages )); do
        local page_args=(--cluster-name "$CLUSTER_NAME" --region "$REGION" \
                         --max-results 100 --cli-read-timeout 30 --output json "$@")
        # Validate token format before sending — avoid BadRequest on garbage.
        if [[ -n "$token" ]]; then
            if [[ "$token" =~ ^[a-zA-Z0-9/+]*={0,2}$ ]] && [[ -n "$token" ]]; then
                page_args+=(--next-token "$token")
            else
                break
            fi
        fi
        page_json=$(aws sagemaker "$api" "${page_args[@]}" 2>&1) || break
        if echo "$page_json" | grep -qiE "AccessDenied|UnauthorizedOperation|not authorized"; then
            break
        fi
        # Merge via stdin (NUL-delimited) to avoid ARG_MAX truncation at ~500
        # entries. summary_key stays in argv since it's small.
        combined=$(printf '%s\0%s' "$merged" "$page_json" | python3 -c "
import sys, json
blob = sys.stdin.buffer.read()
try:
    a, b = blob.split(b'\0', 1)
    prev = json.loads(a)
    page = json.loads(b)
except (json.JSONDecodeError, ValueError):
    sys.exit(2)
prev.extend(page.get(sys.argv[1], []))
print(json.dumps(prev))
print(page.get('NextToken', ''))
" "$summary_key" 2>/dev/null) || break
        merged=$(printf '%s\n' "$combined" | sed -n '1p')
        token=$(printf '%s\n'  "$combined" | sed -n '2p')
        i=$((i+1))
        [[ -z "$token" ]] && break
    done
    if (( i == max_pages )) && [[ -n "$token" ]]; then
        echo "WARN: sagemaker_list_paginated($api): truncated at ${max_pages} pages (~$((max_pages*100)) items). Result may be incomplete for very large clusters." >&2
    fi
    printf '%s' "$merged" | python3 -c "
import sys, json
try:
    print(json.dumps({sys.argv[1]: json.loads(sys.stdin.read())}))
except json.JSONDecodeError:
    print('{\"%s\":[]}' % sys.argv[1])
" "$summary_key" 2>/dev/null || echo "{\"$summary_key\":[]}"
}

detect_orchestrator() {
    if [[ -n "$ORCHESTRATOR" ]]; then
        info "Orchestrator forced: $ORCHESTRATOR"; return
    fi

    header "Detecting Orchestrator Type"
    local orch_type
    orch_type=$(aws sagemaker describe-cluster \
        --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --query 'Orchestrator' --output text 2>/dev/null || echo "")

    if echo "$orch_type" | grep -qi "eks\|kubernetes"; then
        ORCHESTRATOR="eks"
    elif echo "$orch_type" | grep -qi "slurm"; then
        ORCHESTRATOR="slurm"
    elif kubectl cluster-info &>/dev/null 2>&1; then
        ORCHESTRATOR="eks"; info "Auto-detected: EKS (kubectl responds)"
    elif command -v sinfo &>/dev/null && sinfo &>/dev/null 2>&1; then
        ORCHESTRATOR="slurm"; info "Auto-detected: Slurm (sinfo responds)"
    elif command -v squeue &>/dev/null; then
        ORCHESTRATOR="slurm"; info "Auto-detected: Slurm (squeue found)"
    else
        ORCHESTRATOR="eks"
        warn "Could not auto-detect orchestrator — defaulting to 'eks'"
        warn "Override with: --orchestrator slurm"
    fi
    success "Orchestrator: ${ORCHESTRATOR^^}"
}

check_prerequisites() {
    header "Checking Prerequisites"

    local missing=()
    local tool_path
    for tool in aws jq python3 unbuffer; do
        if tool_path=$(command -v "$tool" 2>/dev/null) && [[ -n "$tool_path" ]]; then
            success "$tool: $tool_path"
        else
            error "$tool NOT found — required"
            missing+=("$tool")
        fi
    done

    if [[ "$ORCHESTRATOR" == "eks" ]]; then
        if tool_path=$(command -v kubectl 2>/dev/null) && [[ -n "$tool_path" ]]; then
            success "kubectl: $tool_path"
        else
            error "kubectl NOT found — required for EKS"
            missing+=("kubectl")
        fi
    elif [[ "$ORCHESTRATOR" == "slurm" ]]; then
        local slurm_ok=false
        for t in sinfo squeue scontrol; do
            command -v "$t" &>/dev/null && { success "$t found (Slurm CLI OK)"; slurm_ok=true; break; }
        done
        $slurm_ok || warn "Slurm CLI not found locally — will use SSM for Slurm commands"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Install: ${missing[*]}"
        # unbuffer ships in the `expect` package.
        if printf '%s\n' "${missing[@]}" | grep -qx unbuffer; then
            error "  unbuffer: 'yum install expect' / 'apt install expect' / 'brew install expect'"
        fi
        exit 1
    fi

    if aws sts get-caller-identity --region "$REGION" &>/dev/null; then
        local id
        id=$(aws sts get-caller-identity --region "$REGION" --query 'Arn' --output text)
        success "AWS credentials: $id"
    else
        error "AWS credentials invalid or expired"; exit 1
    fi

    # Inspect both stdout (node list) and stderr (error message).
    # Empty stdout with non-zero exit is an auth / transport failure, not
    # a healthy cluster with zero nodes.
    if [[ "$ORCHESTRATOR" == "eks" ]]; then
        local kubectl_out kubectl_err tmpfile
        tmpfile=$(mktemp /tmp/kubectl-check-XXXXXX.err)
        _TEMP_FILES+=("$tmpfile")
        kubectl_out=$(kubectl get nodes --no-headers 2>"$tmpfile" || true)
        kubectl_err=$(cat "$tmpfile" 2>/dev/null || echo "")
        rm -f "$tmpfile"

        debug "kubectl stdout: '$kubectl_out'"
        debug "kubectl stderr: '$kubectl_err'"

        if echo "$kubectl_err" | grep -qiE \
            "Unauthorized|forbidden|You must be logged in|certificate|no configuration|Unable to connect|server.*refused"; then
            error "kubectl NOT authenticated to EKS cluster"
            error "  $(echo "$kubectl_err" | head -1)"
            warn  "  K8s checks (2, 2b, 5, 5b, 6, 7, 9) will be SKIPPED"
            K8S_CONNECTED=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "kubectl not authenticated to EKS cluster → references/operations.md § 3 SSM target format (HyperPod)" "P1"
        elif echo "$kubectl_err" | grep -qiE \
            "connection refused|no such host|dial tcp|context deadline exceeded|EOF"; then
            error "kubectl cannot reach EKS API server → references/operations.md § 1 Getting cluster names (kubeconfig setup)"
            error "  $(echo "$kubectl_err" | head -1)"
            warn  "  K8s checks (2, 2b, 5, 5b, 6, 7, 9) will be SKIPPED — check VPN/network connectivity"
            K8S_CONNECTED=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "kubectl cannot reach EKS API server → references/operations.md § 1 Getting cluster names (kubeconfig setup)" "P1"
        elif [[ -z "$kubectl_out" && -z "$kubectl_err" ]]; then
            warn "kubectl returned no output — kubeconfig may point to wrong cluster"
            warn "  → references/operations.md § 1 Getting cluster names"
            K8S_CONNECTED=true   # Allow K8s checks — cluster may simply have no nodes yet
        elif [[ -n "$kubectl_err" && -z "$kubectl_out" ]]; then

            error "kubectl error: $(echo "$kubectl_err" | head -1)"
            warn  "  K8s checks (2, 2b, 5, 5b, 6, 7, 9) will be SKIPPED"
            K8S_CONNECTED=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "kubectl error — K8s checks skipped → references/operations.md § 1 Getting cluster names (kubeconfig setup)" "P1"
        else
            local node_count
            node_count=$(echo "$kubectl_out" | wc -l | tr -d ' ')
            success "kubectl authenticated — $node_count node(s) visible"
            K8S_CONNECTED=true
        fi
    fi
}

check_cluster_health() {
    header "Check 1: HyperPod Cluster Health"

    local cluster_json
    cluster_json=$(aws sagemaker describe-cluster \
        --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --output json 2>&1) || {
        if echo "$cluster_json" | grep -qiE "ResourceNotFound|Cluster with name .* not found|ValidationException"; then
            error "Cluster '$CLUSTER_NAME' not found in region '$REGION'"
            echo "$cluster_json" | head -3
            echo ""
            echo "Available clusters in $REGION:"
            aws sagemaker list-clusters --region "$REGION" \
                --query 'ClusterSummaries[*].{Name:ClusterName,Status:ClusterStatus}' \
                --output table 2>/dev/null || echo "  (unable to list clusters — check IAM)"
            exit 1
        fi
        if echo "$cluster_json" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
            warn "Permission denied: sagemaker:DescribeCluster — check IAM policy"
        fi
        cluster_json="{}"
    }

    local cluster_state
    cluster_state=$(echo "$cluster_json" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('ClusterStatus','UNKNOWN'))" 2>/dev/null \
        || echo "UNKNOWN")

    case "$cluster_state" in
        InService)
            success "Cluster status: $cluster_state" ;;
        UNKNOWN|None|"")
            warn "Cluster status: could not retrieve"
            warn "  Ensure --cluster is the HyperPod cluster name and IAM has sagemaker:DescribeCluster" ;;
        Creating|Updating|RollingBack|SystemUpdating)
            warn "Cluster status: $cluster_state (operation in progress — NCCL checks may be partial)"
            add_issue_detail "Cluster in transient state $cluster_state — rerun after it completes → hyperpod-cluster-debugger skill if it stays stuck" "P2" ;;
        Deleting|DeleteFailed)
            error "Cluster status: $cluster_state (cluster is being torn down)"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "Cluster is ${cluster_state} → hyperpod-cluster-debugger skill" "P0" ;;
        Failed|ClusterMaintenanceRollbackFailed)
            error "Cluster status: $cluster_state (expected: InService)"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "Cluster status ${cluster_state} → hyperpod-cluster-debugger skill" "P0" ;;
        *)
            warn "Cluster status: $cluster_state (unrecognized state)"
            add_issue_detail "Unrecognized cluster state '${cluster_state}' → hyperpod-cluster-debugger skill" "P1" ;;
    esac

    # NodeRecovery — affects whether failed nodes are auto-replaced.
    # Prefer top-level NodeRecovery (the canonical location); InstanceGroups[*].NodeRecovery
    # is null when cluster-level setting is applied, so per-group-only reads always return 'Unknown'.
    local node_recovery
    node_recovery=$(echo "$cluster_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
top=d.get('NodeRecovery')
if top:
    print(top)
else:
    igs = d.get('InstanceGroups',[])
    modes = sorted({ig.get('NodeRecovery') for ig in igs if ig.get('NodeRecovery')})
    print(','.join(modes) if modes else 'Unknown')
" 2>/dev/null || echo "Unknown")

    if echo "$node_recovery" | grep -q "Automatic"; then
        success "NodeRecovery: $node_recovery (auto-repair enabled)"
    elif echo "$node_recovery" | grep -qi "^Unknown$"; then
        info "NodeRecovery: could not retrieve (needs sagemaker:DescribeCluster)"
    elif echo "$node_recovery" | grep -qi "^None$"; then
        warn "NodeRecovery: None — failed nodes won't auto-replace → references/operations.md § 6 HyperPod node health labels (EKS)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "NodeRecovery disabled (set to 'None') — failed nodes won't auto-replace → references/operations.md § 6 HyperPod node health labels (EKS)" "P2"
    else
        warn "NodeRecovery: $node_recovery — failed nodes won't auto-replace → references/operations.md § 6 HyperPod node health labels (EKS)"
    fi

    # All instance groups — count nodes per group, surface any unhealthy count.
    # Paginated because clusters >50 nodes would otherwise be diagnosed on a partial sample.
    local node_summary
    node_summary=$(sagemaker_list_paginated list-cluster-nodes ClusterNodeSummaries)

    local node_output
    node_output=$(echo "$node_summary" | python3 -c "
import sys,json
nodes = json.load(sys.stdin).get('ClusterNodeSummaries',[])
total = len(nodes)
by_status = {}
for n in nodes:
    s = n.get('InstanceStatus',{}).get('Status','Unknown')
    by_status[s] = by_status.get(s,0) + 1
print(f'  Total nodes: {total}')
for s,c in sorted(by_status.items()):
    tag = '[PASS]' if s == 'Running' else '[FAIL]'
    print(f'  {tag} {s}: {c}')
failed = [n for n in nodes if n.get('InstanceStatus',{}).get('Status') not in ('Running','Pending')]
for n in failed[:10]:
    msg = n.get('InstanceStatus',{}).get('Message','')
    print(f'    -> {n[\"InstanceId\"]} ({n[\"InstanceGroupName\"]}): {msg[:120]}')
print(f'FAILED_COUNT={len(failed)}')
" 2>/dev/null || echo "FAILED_COUNT=0")

    local fc
    fc=$(echo "$node_output" | grep "^FAILED_COUNT=" | cut -d= -f2 || echo 0)
    # `|| true` on grep — no-match returns 1 and pipefail aborts the function.
    echo "$node_output" | { grep -v "^FAILED_COUNT=" || true; } | while IFS= read -r line; do
        if echo "$line" | grep -q "\[FAIL\]"; then
            error "$line"
        else
            echo "$line"
        fi
    done
    if [[ "${fc:-0}" -gt 0 ]]; then
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "${fc} node(s) in failed/non-Running state → hyperpod-node-debugger skill" "P1"
    fi

    # Pre-flight: if the cluster has no GPU/EFA-capable instance groups, NCCL
    # diagnostics don't apply — exit clearly instead of emitting mixed INFO/SKIP.
    local gpu_groups
    gpu_groups=$(echo "$cluster_json" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
igs = d.get('InstanceGroups', [])
gpu_efa_re = re.compile(r'^ml\.(p4d|p4de|p5|p5e|p5en|p6|trn1|trn2|g5\.48xlarge|g6\.48xlarge|g6e\.48xlarge)', re.I)
matches = [ig.get('InstanceGroupName','?') + ':' + ig.get('InstanceType','?')
           for ig in igs if gpu_efa_re.match(ig.get('InstanceType',''))]
print('|'.join(matches))
" 2>/dev/null || echo "")
    if [[ -z "$gpu_groups" ]] && [[ "$(echo "$cluster_json" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("InstanceGroups",[])))' 2>/dev/null)" -gt 0 ]]; then
        warn "No GPU/EFA-capable instance groups in this cluster — NCCL is not applicable"
        warn "  NCCL is only meaningful on multi-GPU instances with EFA (p4d/p4de/p5/p5e/p5en/p6/trn1/trn2/g5.48xlarge/g6.48xlarge/g6e.48xlarge)"
        warn "  The rest of the diagnostic will still run, but most checks will return INFO/SKIP on CPU-only fleets"
    fi
}

check_cluster_events() {
    header "Check 3: Cluster Events (infrastructure signals)"

    # HyperPod cluster events report infrastructure-level state only:
    # lifecycle, bootstrap, EFA health-check, capacity, replacement, reboot,
    # software update. They do NOT carry NCCL / GPU / training-level signals —
    # those come from pod logs, CloudWatch, and on-node probes (checks 6–8).
    # ListClusterEvents response shape: array under `Events` with fields
    # EventId / ClusterArn / ClusterName / InstanceGroupName / ResourceType /
    # EventTime / Description (verified live; no Severity field).
    local events_json
    events_json=$(sagemaker_list_paginated list-cluster-events Events)
    local events
    events=$(echo "$events_json" | python3 -c "
import sys, json
summaries = json.load(sys.stdin).get('Events', [])
proj = [{'Time': e.get('EventTime',''),
         'Grp':  e.get('InstanceGroupName','') or e.get('ResourceType',''),
         'Msg':  e.get('Description','') or ''} for e in summaries]
print(json.dumps(proj))
" 2>/dev/null || echo "[]")

    local infra_events
    infra_events=$(echo "$events" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# Match real HyperPod event messages that could block or degrade distributed training.
keywords = [
    'efa health checks',         # 'EFA health checks did not run successfully'
    'lifecycle script',          # 'Lifecycle scripts did not run successfully' / 'execution timed out'
    'bootstrap failed',          # 'Instance bootstrap failed likely because of customer network misconfiguration'
    'network misconfiguration',  # appears in bootstrap-failed events
    'insufficient capacity',     # 'Insufficient capacity' / 'No subnets in the capacity AZ'
    'failed to provision',       # provisioning events
    'hardware failure',          # rare; surfaces via events when SMHP detects
    'replacement',               # node replacement activity
    'reboot',                    # node reboot activity
    'rollback',                  # AMI upgrade rollback
]
found = [e for e in data if any(k in e.get('Msg','').lower() for k in keywords)]
for e in found[:20]:
    print(f\"[{e.get('Grp','?')}] {str(e.get('Time','?'))[:19]} | {e.get('Msg','?')[:140]}\")
print(f'COUNT={len(found)}')
" 2>/dev/null || echo "COUNT=0")

    local count
    count=$(echo "$infra_events" | grep "^COUNT=" | cut -d= -f2 || echo 0)
    local lines
    lines=$(echo "$infra_events" | grep -v "^COUNT=" || true)

    if [[ -z "$lines" || "${count:-0}" -eq 0 ]]; then
        success "No infrastructure events that would block NCCL"
        if [[ "$ORCHESTRATOR" == "slurm" ]]; then
            info "(Cluster events may not be populated for HyperPod Slurm clusters — rely on pod-/job-log checks instead.)"
        fi
    else
        warn "Infrastructure events potentially affecting NCCL (last 100):"
        echo "$lines" | while IFS= read -r line; do
            if echo "$line" | grep -qiE "error|fail|timeout|rollback"; then
                error "  $line"
            else
                warn "  $line"
            fi
        done
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "Infrastructure-level events found — review and cross-reference with cluster-debugger if root-cause is cluster-wide → references/debugging-guide.md (match event text to section)" "P1"
    fi
}

check_security_groups() {
    header "Check 4: Security Group Rules (EFA / NCCL Communication)"

    local cluster_json
    cluster_json=$(aws sagemaker describe-cluster \
        --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --output json 2>/dev/null || echo "{}")

    # DescribeCluster.VpcConfig returns SecurityGroupIds + Subnets (not SubnetIds).
    # VpcId is not on VpcConfig; derive from a subnet if needed downstream.
    local sgs subnets
    sgs=$(echo "$cluster_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(','.join(d.get('VpcConfig',{}).get('SecurityGroupIds',[])))
" 2>/dev/null || echo "")
    subnets=$(echo "$cluster_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(','.join(d.get('VpcConfig',{}).get('Subnets',[])))
" 2>/dev/null || echo "")

    info "SGs: ${sgs:-none}  |  Subnets: ${subnets:-none}"

    if [[ -z "$sgs" ]]; then
        warn "No security groups in cluster VPC config — cannot verify NCCL rules"
        warn "  (DescribeCluster may need sagemaker:DescribeCluster permission)"
        return
    fi

    IFS=',' read -ra sg_list <<< "$sgs"
    for sg in "${sg_list[@]}"; do
        [[ -z "$sg" ]] && continue
        section "SG: $sg"

        local sg_json
        sg_json=$(aws ec2 describe-security-groups \
            --group-ids "$sg" --region "$REGION" \
            --query 'SecurityGroups[0]' --output json 2>&1) || {
            if echo "$sg_json" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
                warn "Permission denied: ec2:DescribeSecurityGroups — check IAM policy"
            fi
            sg_json="{}"
        }

        local self_in self_out all_out
        read -r self_in self_out all_out < <(echo "$sg_json" | python3 -c "
import sys,json
sg=json.load(sys.stdin)
gid=sg.get('GroupId','')
def has_self(rules):
    return any(any(p.get('GroupId')==gid for p in r.get('UserIdGroupPairs',[])) for r in rules)
def has_all_out(rules):
    return any(r.get('IpProtocol')=='-1' and any(x.get('CidrIp')=='0.0.0.0/0' for x in r.get('IpRanges',[])) for r in rules)
print('YES' if has_self(sg.get('IpPermissions',[])) else 'NO',
      'YES' if has_self(sg.get('IpPermissionsEgress',[])) else 'NO',
      'YES' if has_all_out(sg.get('IpPermissionsEgress',[])) else 'NO')
" 2>/dev/null || echo "UNKNOWN UNKNOWN UNKNOWN")

        if [[ "$self_in" == "YES" ]]; then
            success "  Inbound self-reference: PRESENT (inter-node communication OK)"
        else
            error "  Inbound self-reference: MISSING — NCCL inter-node comm WILL FAIL"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "SG $sg missing inbound self-referencing rule → references/operations.md § 8 NCCL-specific remediations (Security group self-reference)" "P0"
        fi

        if [[ "$self_out" == "YES" ]]; then
            success "  Outbound self-reference: PRESENT (EFA traffic OK)"
        else
            error "  Outbound self-reference: MISSING — EFA traffic WILL FAIL"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "SG $sg missing outbound self-referencing rule → references/operations.md § 8 NCCL-specific remediations (Security group self-reference)" "P0"
        fi

        if [[ "$all_out" == "YES" ]]; then
            success "  Outbound 0.0.0.0/0: PRESENT (API/internet OK)"
        else
            warn    "  Outbound 0.0.0.0/0: MISSING — may block SageMaker/S3 API calls"
        fi
    done
}

check_k8s_nodes() {
    header "Check 2: Kubernetes Node Readiness"

    local raw_nodes total not_ready
    raw_nodes=$(kubectl get nodes --no-headers 2>/dev/null || true)
    total=$(echo "$raw_nodes" | awk 'NF{c++} END{print c+0}')
    not_ready=$(echo "$raw_nodes" | { grep -vE " Ready" || true; } | awk 'NF{c++} END{print c+0}')

    info "Total K8s nodes: $total"

    if [[ "$not_ready" -eq 0 ]]; then
        success "All $total nodes are Ready"
    else
        error "$not_ready/$total nodes NOT Ready"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "$not_ready/$total K8s nodes not Ready → hyperpod-node-debugger skill" "P1"
        echo "$raw_nodes" | { grep -vE " Ready" || true; } | while read -r line; do
            error "  Not Ready: $line"
        done
    fi

    section "HyperPod Health Labels (all nodes)"
    # Uses the 4 documented node-health-status values plus deep-health-check-status
    local health_output
    health_output=$(kubectl get nodes -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
issues = 0
for node in data.get('items', []):
    name = node['metadata']['name']
    labels = node['metadata'].get('labels', {})
    health       = labels.get('sagemaker.amazonaws.com/node-health-status', '')
    deep         = labels.get('sagemaker.amazonaws.com/deep-health-check-status', '')
    fault_type   = labels.get('sagemaker.amazonaws.com/fault-types', '')
    fault_reason = labels.get('sagemaker.amazonaws.com/fault-reasons', '')

    ok = health in ('', 'Schedulable') and deep in ('', 'Passed') and not fault_type
    tag = '[PASS]' if ok else '[FAIL]'
    if not ok:
        issues += 1
    line = f'  {tag} {name}: health={health or \"(none)\"}'
    if deep:       line += f'  deep={deep}'
    if fault_type: line += f'  fault={fault_type}'
    print(line)
    if health == 'Unschedulable':
        print('         -> Running deep health checks (~2h), temporarily unavailable')
    elif health == 'UnschedulablePendingReplacement':
        print('         -> Failed health checks — needs replacement (NodeRecovery=Automatic will auto-replace)')
    elif health == 'UnschedulablePendingReboot':
        print('         -> Unhealthy — rebooting to re-run health checks')
    if deep == 'InProgress': print('         -> Deep health check in progress')
    elif deep == 'Failed':   print('         -> Deep health check FAILED — node will be replaced')
    if fault_type: print(f'         -> Fault: {fault_type} | {fault_reason}')
print(f'ISSUES={issues}')
" 2>/dev/null || echo "ISSUES=0")

    local health_issues
    health_issues=$(echo "$health_output" | grep "^ISSUES=" | cut -d= -f2 || echo 0)
    echo "$health_output" | { grep -v "^ISSUES=" || true; } | while IFS= read -r line; do
        echo -e "$line"
    done
    # Using `if` instead of `[[ ... ]] && ...` — the short-circuit form returns
    # non-zero when the test is false, which aborts the script under `set -e`
    # and silently skips every remaining check (pods, env vars, hardware).
    if [[ "${health_issues:-0}" -gt 0 ]]; then
        ISSUES_FOUND=$((ISSUES_FOUND + health_issues))
    fi
}

check_pod_status() {
    local ns_flag ns_label
    if [[ -n "$NAMESPACE" ]]; then
        ns_flag=(-n "$NAMESPACE")
        ns_label="'$NAMESPACE'"
    else
        ns_flag=(-A)
        ns_label="all namespaces"
    fi
    header "Check 5: Pod / Job Status ($ns_label)"

    local job_filter=()
    [[ -n "$JOB_NAME" ]] && job_filter=(-l "job-name=$JOB_NAME")

    # `${arr[@]+"${arr[@]}"}` — expand only if defined; plain `${arr[@]}`
    # trips `set -u` on empty arrays under bash 4.2 (AL2 default).
    local pods_json
    pods_json=$(kubectl get pods "${ns_flag[@]}" ${job_filter[@]+"${job_filter[@]}"} -o json 2>/dev/null \
                || echo '{"items":[]}')

    local pod_output
    pod_output=$(python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d['items']
total   = len(items)
failed  = [p for p in items if p.get('status',{}).get('phase') in ('Failed','Unknown')]
pending = [p for p in items if p.get('status',{}).get('phase') == 'Pending']
crashes = []
for p in items:
    for cs in p.get('status',{}).get('containerStatuses',[]):
        if cs.get('restartCount',0)>2 or cs.get('state',{}).get('waiting',{}).get('reason') \
           in ('CrashLoopBackOff','OOMKilled','Error'):
            crashes.append(p)
            break

print(f'TOTAL={total}')
print(f'FAILED={len(failed)}')
print(f'PENDING={len(pending)}')
print(f'CRASH={len(crashes)}')

for p in failed[:5]:
    name = p['metadata']['name']
    ns   = p['metadata']['namespace']
    msg  = p.get('status',{}).get('message','')[:150]
    print(f'FAILED_POD={ns}/{name}: {msg}')
for p in pending[:5]:
    name = p['metadata']['name']
    ns   = p['metadata']['namespace']
    for c in p.get('status',{}).get('conditions',[]):
        if c.get('status')=='False':
            print(f'PENDING_POD={ns}/{name}: {c.get(\"message\",\"\")[:120]}')
for p in crashes[:5]:
    name = p['metadata']['name']
    ns   = p['metadata']['namespace']
    for cs in p.get('status',{}).get('containerStatuses',[]):
        r = cs.get('state',{}).get('waiting',{}).get('reason','CrashLoop')
        print(f'CRASH_POD={ns}/{name}: {r} restarts={cs.get(\"restartCount\",0)}')
        break
" <<< "$pods_json" 2>/dev/null || echo "TOTAL=0
FAILED=0
PENDING=0
CRASH=0")

    # Parse counts outside of pipe to avoid subshell variable loss
    local p_total p_failed p_pending p_crash
    p_total=$(echo "$pod_output" | grep "^TOTAL=" | cut -d= -f2 || echo 0)
    p_failed=$(echo "$pod_output" | grep "^FAILED=" | cut -d= -f2 || echo 0)
    p_pending=$(echo "$pod_output" | grep "^PENDING=" | cut -d= -f2 || echo 0)
    p_crash=$(echo "$pod_output" | grep "^CRASH=" | cut -d= -f2 || echo 0)

    info "  Total pods: ${p_total:-0}"

    if [[ "${p_failed:-0}" -gt 0 ]]; then
        error "  Failed/Unknown pods: $p_failed"; ISSUES_FOUND=$((ISSUES_FOUND+1)); add_issue_detail "$p_failed Failed/Unknown pod(s) → references/debugging-guide.md § 20 Pending / CrashLoopBackOff / Init-Container Failures" "P1"
    else
        success "  No failed pods"
    fi
    if [[ "${p_pending:-0}" -gt 0 ]]; then
        warn "  Pending pods: $p_pending"; ISSUES_FOUND=$((ISSUES_FOUND+1)); add_issue_detail "$p_pending Pending pod(s) → references/debugging-guide.md § 20 Pending / CrashLoopBackOff / Init-Container Failures" "P1"
    else
        success "  No pending pods"
    fi
    if [[ "${p_crash:-0}" -gt 0 ]]; then
        error "  CrashLoop/OOM pods: $p_crash"; ISSUES_FOUND=$((ISSUES_FOUND+1)); add_issue_detail "$p_crash CrashLoopBackOff/OOM pod(s) → references/debugging-guide.md § 20 Pending / CrashLoopBackOff / Init-Container Failures" "P1"
    else
        success "  No crashloop pods"
    fi

    # `|| true` — grep returns 1 on no-match; with `pipefail` that kills the
    # whole function, silently skipping the rest of the diagnostic.
    echo "$pod_output" | { grep "^FAILED_POD=" || true; } | while IFS= read -r line; do error "    ${line#FAILED_POD=}"; done
    echo "$pod_output" | { grep "^PENDING_POD=" || true; } | while IFS= read -r line; do warn  "    ${line#PENDING_POD=}"; done
    echo "$pod_output" | { grep "^CRASH_POD="   || true; } | while IFS= read -r line; do error "    ${line#CRASH_POD=}"; done
}

# Checks EKS-specific prerequisites that cause NCCL failures before training starts:
#   - Headless service for MASTER_ADDR DNS resolution
#   - Init container failures blocking training containers
#   - /dev/shm volume mount (K8s default 64MB is too small for NCCL)
check_nccl_infra_prereqs() {
    header "Check 5b: NCCL Infrastructure Prerequisites"

    local ns_flag ns_label
    if [[ -n "$NAMESPACE" ]]; then
        ns_flag=(-n "$NAMESPACE")
        ns_label="'$NAMESPACE'"
    else
        ns_flag=(-A)
        ns_label="all namespaces"
    fi

    local job_filter=()
    [[ -n "$JOB_NAME" ]] && job_filter=(-l "job-name=$JOB_NAME")

    # MASTER_ADDR DNS resolution requires a headless service (ClusterIP: None)
    # Without it, pods get DNS like "10-0-1-5.default.pod.cluster.local" which
    # doesn't resolve from other pods → rendezvous timeout
    section "Headless Service (MASTER_ADDR DNS)"
    local headless_svcs
    headless_svcs=$(kubectl get svc "${ns_flag[@]}" -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = []
for svc in data.get('items', []):
    spec = svc.get('spec', {})
    if spec.get('clusterIP') == 'None':
        name = svc['metadata']['name']
        ns = svc['metadata']['namespace']
        sel = spec.get('selector', {})
        found.append(f'{ns}/{name} selector={sel}')
print(f'COUNT={len(found)}')
for f in found[:10]:
    print(f)
" 2>/dev/null || echo "COUNT=0")

    local hl_count
    hl_count=$(echo "$headless_svcs" | grep "^COUNT=" | cut -d= -f2 || echo 0)
    if [[ "${hl_count:-0}" -gt 0 ]]; then
        success "Headless service(s) found (${hl_count}) — MASTER_ADDR DNS can resolve"
        echo "$headless_svcs" | { grep -v "^COUNT=" || true; } | while IFS= read -r line; do
            [[ -n "$line" ]] && info "  $line"
        done
    else
        warn "No headless services found in $ns_label"
        warn "  If MASTER_ADDR uses a hostname, DNS resolution will fail"
        warn "  Example: spec.clusterIP: None, spec.selector: {app: my-training-job}"
    fi

    # Init containers must complete before training container starts.
    # Common failures: S3 data download, config fetch, health check wait
    section "Init Container Status"
    local init_issues
    init_issues=$(kubectl get pods "${ns_flag[@]}" ${job_filter[@]+"${job_filter[@]}"} -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
issues = 0
for pod in data.get('items', []):
    name = pod['metadata']['name']
    ns = pod['metadata']['namespace']
    for ics in pod.get('status', {}).get('initContainerStatuses', []):
        state = ics.get('state', {})
        if 'waiting' in state:
            reason = state['waiting'].get('reason', '')
            msg = state['waiting'].get('message', '')[:100]
            if reason in ('CrashLoopBackOff', 'Error', 'ImagePullBackOff', 'ErrImagePull'):
                print(f'FAIL:{ns}/{name}: init container \"{ics[\"name\"]}\" {reason}: {msg}')
                issues += 1
        elif 'terminated' in state and state['terminated'].get('exitCode', 0) != 0:
            reason = state['terminated'].get('reason', 'Error')
            print(f'FAIL:{ns}/{name}: init container \"{ics[\"name\"]}\" exited {state[\"terminated\"][\"exitCode\"]}: {reason}')
            issues += 1
print(f'ISSUES={issues}')
" 2>/dev/null || echo "ISSUES=0")

    local init_count
    init_count=$(echo "$init_issues" | grep "^ISSUES=" | cut -d= -f2 || echo 0)
    if [[ "${init_count:-0}" -gt 0 ]]; then
        error "  $init_count init container failure(s) — training containers cannot start"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "$init_count failed init container(s) blocking training → references/debugging-guide.md § 20 Pending / CrashLoopBackOff / Init-Container Failures" "P1"
        echo "$init_issues" | { grep "^FAIL:" || true; } | while IFS= read -r line; do
            error "    ${line#FAIL:}"
        done
    else
        success "No init container failures"
    fi

    # K8s default /dev/shm = 64MB. NCCL needs ≥1GB. Without emptyDir mount,
    # training gets "failed to extend /dev/shm/nccl-*" or SIGBUS.
    section "/dev/shm Volume Mount"
    if [[ -n "$JOB_NAME" ]]; then
        local ns="${NAMESPACE:-default}"
        local shm_check
        shm_check=$(kubectl get pods -n "$ns" -l "job-name=$JOB_NAME" -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
pods = data.get('items', [])
if not pods:
    print('NO_PODS')
else:
    pod = pods[0]
    vols = pod.get('spec', {}).get('volumes', [])
    has_dshm = any(
        v.get('emptyDir', {}).get('medium') == 'Memory'
        for v in vols
        if any(vm.get('mountPath') == '/dev/shm'
               for c in pod.get('spec', {}).get('containers', [])
               for vm in c.get('volumeMounts', [])
               if vm.get('name') == v.get('name'))
    )
    if has_dshm:
        print('OK')
    else:
        print('MISSING')
" 2>/dev/null || echo "UNKNOWN")

        case "$shm_check" in
            OK)      success "/dev/shm mounted as emptyDir Memory — NCCL shared memory OK" ;;
            MISSING) warn "/dev/shm NOT mounted as emptyDir Memory (K8s default = 64MB)"
                     warn "  NCCL will fail with 'failed to extend /dev/shm/nccl-*' or Bus error"
                     warn "    volumes: [{name: dshm, emptyDir: {medium: Memory, sizeLimit: '10Gi'}}]"
                     warn "    volumeMounts: [{name: dshm, mountPath: /dev/shm}]"
                     ISSUES_FOUND=$((ISSUES_FOUND + 1))
                     add_issue_detail "/dev/shm not mounted as emptyDir Memory → references/debugging-guide.md § 17 RDMA Memory Registration Failure" "P1" ;;
            NO_PODS) info "No pods found for job '$JOB_NAME' — /dev/shm check skipped" ;;
            *)       info "/dev/shm mount status unknown" ;;
        esac
    else
        info "/dev/shm check requires --job flag (skipped)"
    fi
}

analyze_nccl_logs() {
    header "Check 6: NCCL Log Pattern Analysis"

    local job_filter=()
    [[ -n "$JOB_NAME" ]] && job_filter=(-l "job-name=$JOB_NAME")

    local pod_entries
    if [[ -n "$NAMESPACE" ]]; then
        pod_entries=$(kubectl get pods -n "$NAMESPACE" ${job_filter[@]+"${job_filter[@]}"} --no-headers 2>/dev/null \
            | awk -v ns="$NAMESPACE" '{print ns"/"$1}' || echo "")
    else
        pod_entries=$(kubectl get pods -A ${job_filter[@]+"${job_filter[@]}"} --no-headers 2>/dev/null \
            | awk '{print $1"/"$2}' \
            | grep -vE "^(kube-system|kube-public|kube-node-lease|aws-hyperpod)/" || true)
    fi

    if [[ -z "$pod_entries" ]]; then
        info "No workload pods found to analyze logs"
        return
    fi

    declare -A NCCL_PATTERNS=(
        ["Timeout waiting for"]="TIMEOUT_RENDEZVOUS:Rendezvous timed out — peer ranks not responding"
        ["Connection refused"]="CONN_REFUSED:TCP refused — check MASTER_ADDR/MASTER_PORT"
        ["Address already in use"]="PORT_CONFLICT:Port already in use — change MASTER_PORT"
        ["NCCL WARN Connect to"]="CONNECT_FAIL:NCCL peer connection failed — check SG/NetworkPolicy"
        ["network is unreachable"]="NET_UNREACHABLE:Network unreachable — VPC/routing issue"
        ["Error in Store"]="STORE_ERR:Distributed store error — usually rendezvous timeout"
        ["DistStoreError"]="STORE_ERR:Distributed store error (PyTorch 2.x) — usually rendezvous timeout"
        ["RendezvousConnectionError"]="RDZV_CONN_ERR:Torch elastic rendezvous connection failed — check MASTER_ADDR DNS + SG"
        ["RendezvousTimeout"]="RDZV_TIMEOUT:Torch elastic rendezvous timed out — peers not reachable"
        ["Name or service not known"]="DNS_FAIL:DNS resolution failed for MASTER_ADDR — check headless service or /etc/hosts"
        ["getaddrinfo failed"]="DNS_FAIL:DNS resolution failed — headless service missing or CoreDNS issue"
        ["Watchdog timeout"]="WATCHDOG_TIMEOUT:AllReduce watchdog expired — straggler or OOM"
        ["unhandled system error"]="SYSTEM_ERROR:NCCL system error — GPU/EFA hardware issue"
        ["unhandled cuda error"]="CUDA_ERROR:CUDA runtime error — GPU driver crash or hardware fault"
        ["peer access is not supported"]="P2P_FAIL:GPU peer access blocked — ACS enabled or IOMMU misconfigured"
        ["NCCL WARN Cuda failure"]="CUDA_ERROR:CUDA failure inside NCCL — GPU hardware or driver issue"
        ["fi_getinfo failed"]="EFA_INIT_FAIL:EFA libfabric init failed — EFA not available or wrong NCCL_SOCKET_IFNAME"
        ["NCCL_OFI_RDMA"]="OFI_ERROR:aws-ofi-nccl plugin error — check EFA driver and OFI NCCL version"
        ["Call to ibv_reg_mr failed"]="RDMA_REG_FAIL:EFA/RDMA memory registration failed — memlock limit too low"
        ["NET/OFI Using TCP"]="EFA_TCP_FALLBACK:NCCL fell back to TCP instead of EFA — 10-100x slower than expected"
        ["Failed to load NCCL"]="NCCL_LOAD_FAIL:Failed to load NCCL library — libnccl.so missing or LD_LIBRARY_PATH wrong"
        ["libnccl-net.so"]="OFI_LOAD_FAIL:Failed to load aws-ofi-nccl plugin — libnccl-net.so not found"
        ["OOMKilled"]="OOM_KILL:Container killed (OOM) — reduce batch size or increase memory limit"
        ["CUDA out of memory"]="CUDA_OOM:GPU out of memory — reduce batch size or model size"
        ["cudaMalloc failed"]="CUDA_OOM:GPU cudaMalloc failed — reduce batch size or model size"
        ["failed to extend /dev/shm"]="SHM_FULL:NCCL shared memory /dev/shm full — mount emptyDir with 10Gi sizeLimit"
        ["Bus error"]="SHM_FULL:/dev/shm too small or SIGBUS — mount emptyDir with 10Gi sizeLimit"
        ["NCCL function not found"]="NCCL_VERSION_MISMATCH:NCCL version mismatch across nodes — mixed container images"
        ["Incompatible NCCL version"]="NCCL_VERSION_MISMATCH:NCCL version mismatch across nodes — mixed container images"
        ["Could not find interface"]="IFACE_NOT_FOUND:NCCL_SOCKET_IFNAME points to missing interface"
        ["world_size mismatch"]="WORLD_SIZE_MISMATCH:WORLD_SIZE doesn't match running process count"
        ["doesn't have NCCL built in"]="NCCL_NOT_BUILT:PyTorch compiled without NCCL — rebuild with USE_NCCL=1 or use AWS DLC image"
        ["CUDA_VISIBLE_DEVICES"]="CUDA_VIS_DEV:CUDA_VISIBLE_DEVICES misconfigured — GPUs not visible to training process"
        ["unlink shared memory"]="SHM_STALE:Stale NCCL shared memory from previous run — systemd RemoveIPC=yes or manual cleanup"
        ["Call to ncclCommAbort"]="NCCL_COMM_ABORT:NCCL communicator aborted — check for straggler node or hardware fault"
        ["MNNVL topology"]="MNNVL_TOPO_FAIL:NCCL MNNVL topology search failed — memlock=unlimited + stack=unlimited causes 2MB thread stack; fix: ulimit -l 8388608 -s 8192"
        ["ENOMEM"]="ENOMEM:Memory registration/allocation failed — check memlock limits and available GPU memory"
        ["invalid alignment"]="CUDA_ALIGN_ERR:CUDA memory alignment error — possible driver/NCCL version incompatibility"
    )

    local issues_in_logs=false

    while IFS= read -r entry; do
        local ns pod
        ns="${entry%%/*}"; pod="${entry#*/}"
        section "Logs: $ns/$pod"

        local logs
        # Use --tail=500 to catch patterns even in longer outputs.
        # For Failed/Error pods, also check --previous (logs from the crashed container instance).
        local pod_phase
        pod_phase=$(kubectl get pod -n "$ns" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        logs=$(kubectl logs -n "$ns" "$pod" --tail=500 2>/dev/null || echo "")
        if [[ -z "$logs" ]]; then
            logs=$(kubectl logs -n "$ns" "$pod" --previous --tail=500 2>/dev/null || echo "")
        elif [[ "$pod_phase" == "Failed" ]]; then
            local prev_logs
            prev_logs=$(kubectl logs -n "$ns" "$pod" --previous --tail=500 2>/dev/null || echo "")
            [[ -n "$prev_logs" ]] && logs="${logs}"$'\n'"${prev_logs}"
        fi

        if [[ -z "$logs" ]]; then
            info "  No logs available"
            continue
        fi

        for pattern in "${!NCCL_PATTERNS[@]}"; do
            if echo "$logs" | grep -qi "$pattern"; then
                local meaning="${NCCL_PATTERNS[$pattern]}"
                local code="${meaning%%:*}"
                local desc="${meaning#*:}"
                error "  DETECTED [$code]: $desc"
                echo "$logs" | { grep -i "$pattern" || true; } | tail -3 | while IFS= read -r logline; do
                    echo -e "    ${YELLOW}> $logline${RESET}"
                done
                issues_in_logs=true
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                add_issue_detail "NCCL log pattern [$code] in pod $pod: $desc → references/error-patterns-quick-ref.md" "P1"
            fi
        done

        if echo "$logs" | grep -qiE "BASELINE TEST PASSED|AllReduce SUCCESS|Training complete"; then
            success "  Pod $pod: completed successfully"
        fi
    done <<< "$pod_entries"

    $issues_in_logs || success "No NCCL error patterns found in pod logs"
}

check_nccl_env_vars() {
    header "Check 7: NCCL Environment Variable Audit"

    local job_filter=()
    [[ -n "$JOB_NAME" ]] && job_filter=(-l "job-name=$JOB_NAME")

    local ns="${NAMESPACE:-default}"
    local first_pod
    first_pod=$(kubectl get pods -n "$ns" ${job_filter[@]+"${job_filter[@]}"} --no-headers 2>/dev/null \
        | grep -E " Running " | head -1 | awk '{print $1}' || echo "")

    if [[ -z "$first_pod" ]]; then
        info "No Running pods found for env var audit (only meaningful during active training)"
        return
    fi

    info "Checking env vars in Running pod: $ns/$first_pod"
    local pod_env
    pod_env=$(kubectl exec -n "$ns" "$first_pod" -- env 2>/dev/null || echo "")

    if [[ -z "$pod_env" ]]; then
        warn "Could not exec into $first_pod"
        return
    fi

    # Capture Python output; the sentinel line feeds issue accounting below.
    local env_audit_out env_warn_count
    env_audit_out=$(python3 - <<'PYEOF' "$pod_env"
import sys
pod_env = sys.argv[1] if len(sys.argv) > 1 else ""
env_map = {}
for line in pod_env.strip().split('\n'):
    if '=' in line:
        k, _, v = line.partition('=')
        env_map[k.strip()] = v.strip()

# (rec_value, severity, description)
# severity WARN = counts as issue; INFO = advisory only
checks = {
    'MASTER_ADDR':            (None,          'WARN', 'Must be rank-0 pod hostname/IP'),
    'MASTER_PORT':            ('29500',       'WARN', 'Must match across all ranks'),
    'WORLD_SIZE':             (None,          'WARN', 'Must equal total processes'),
    'RANK':                   (None,          'WARN', 'Must be unique 0..WORLD_SIZE-1'),
    'NCCL_SOCKET_IFNAME':     ('^lo,docker,efa,veth,virbr', 'WARN', 'Exclude non-VPC interfaces (loopback/docker/EFA control/veth)'),
    'NCCL_TIMEOUT':           ('1200',        'WARN', 'Default 600s too short for large clusters'),
    'FI_PROVIDER':            ('efa',         'INFO', 'Set to efa on EFA instances; omit for CPU-only'),
    'FI_EFA_USE_DEVICE_RDMA': ('1',           'INFO', 'Required for full EFA RDMA performance'),
    'NCCL_DEBUG':             ('WARN',        'INFO', 'Enable for diagnostics (use WARN not INFO in prod)'),
}

print("  {:<28} {:<22} {}".format('Variable','Value','Status'))
print("  " + "-"*68)
warn_count = 0
for var,(rec,sev,desc) in checks.items():
    val = env_map.get(var)
    if val:
        print(f"  [SET]  {var:<26} {val:<22}")
    elif sev == 'WARN':
        warn_count += 1
        print(f"  [WARN] {var:<26} {'(not set)':<22}  <- {desc}")
    else:
        print(f"  [INFO] {var:<26} {'(not set)':<22}  <- {desc}")

nccl_debug = env_map.get('NCCL_DEBUG', '')
if nccl_debug.upper() == 'INFO':
    warn_count += 1
    print("\n  [WARN] NCCL_DEBUG=INFO detected in production job — verbose logging adds runtime overhead; set to WARN for production")
elif nccl_debug.upper() == 'TRACE':
    warn_count += 1
    print("\n  [WARN] NCCL_DEBUG=TRACE detected — TRACE prints replayable trace info on every NCCL call (per the NCCL env-var doc); large overhead and gigabytes of logs per rank, set to WARN immediately")

# NCCL_TIMEOUT value validation (formula: nodes * 5 + 600)
nccl_timeout_str = env_map.get('NCCL_TIMEOUT', '')
world_size_str = env_map.get('WORLD_SIZE', '0')
try:
    world_size = int(world_size_str)
except ValueError:
    world_size = 0
if nccl_timeout_str and world_size > 0:
    try:
        nccl_timeout = int(nccl_timeout_str)
        recommended = world_size * 5 + 600
        if nccl_timeout < recommended:
            warn_count += 1
            print(f"\n  [WARN] NCCL_TIMEOUT={nccl_timeout}s may be too low for {world_size} ranks (recommended >= {recommended}s)")
    except ValueError:
        pass

# Large cluster checks (256+ nodes)
if world_size > 256:
    warn_count += 1
    print(f"\n  [WARN] WORLD_SIZE={world_size} (large cluster) — verify memlock and stack ulimits")

if warn_count == 0:
    print("\n  [PASS] All critical NCCL env vars configured")
else:
    print(f"\n  [WARN] {warn_count} critical NCCL env var(s) not set or misconfigured")

# Sentinel line consumed by the caller — DO NOT remove.
print(f"__WARN_COUNT__={warn_count}")
PYEOF
)
    echo "$env_audit_out" | grep -v '^__WARN_COUNT__='
    env_warn_count=$(echo "$env_audit_out" | grep '^__WARN_COUNT__=' | cut -d= -f2)
    if [[ "${env_warn_count:-0}" =~ ^[0-9]+$ ]] && (( env_warn_count > 0 )); then
        ISSUES_FOUND=$((ISSUES_FOUND + env_warn_count))
        add_issue_detail "${env_warn_count} NCCL env var issue(s) in pod ${ns}/${first_pod} → references/operations.md § 5 NCCL environment variable reference" "P1"
    fi
}

# EFA device plugin + NCCL version consistency. kubectl-only, no active job needed.
check_efa_k8s() {
    header "Check 2b: EFA K8s Device Plugin & NCCL Version Consistency"

    # Without this DaemonSet, pods can't request vpc.amazonaws.com/efa resources
    # and EFA interfaces won't be mounted into training containers.
    local efa_ds
    efa_ds=$(kubectl get daemonset -A 2>/dev/null | grep -iE "efa|aws-efa" | head -3 || echo "")

    if [[ -n "$efa_ds" ]]; then
        success "EFA device plugin DaemonSet found:"
        echo "$efa_ds" | while IFS= read -r line; do info "  $line"; done
    else
        # Missing plugin is a FAIL only if any pod requests vpc.amazonaws.com/efa.
        local ns_flag=(); if [[ -n "$NAMESPACE" ]]; then ns_flag=(-n "$NAMESPACE"); else ns_flag=(-A); fi
        local efa_requested
        efa_requested=$(kubectl get pods "${ns_flag[@]}" -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for pod in data.get('items', []):
    for c in pod.get('spec', {}).get('containers', []):
        lims = c.get('resources', {}).get('limits', {})
        if 'vpc.amazonaws.com/efa' in lims:
            ns = pod['metadata']['namespace']
            name = pod['metadata']['name']
            count = lims['vpc.amazonaws.com/efa']
            print(f'  {ns}/{name}: requests {count} EFA interface(s)')
" 2>/dev/null || echo "")

        if [[ -n "$efa_requested" ]]; then
            error "Pods request EFA resources but EFA device plugin DaemonSet NOT found!"
            error "  EFA interfaces will NOT be mounted into training containers"
            echo "$efa_requested"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "EFA device plugin DaemonSet missing → references/operations.md § 5 NCCL environment variable reference / references/debugging-guide.md § 6 EFA Configuration" "P0"
        else
            info "EFA device plugin not detected (OK if no pods request vpc.amazonaws.com/efa)"
        fi
    fi

    # Mixed NCCL versions across nodes → 'NCCL function not found' at init.
    # Two independent probes:
    #   - torch.cuda.nccl.version(): works only if PyTorch is installed.
    #   - libnccl.so on disk: authoritative — this is what actually loads at
    #     runtime, works for any image (PyTorch, JAX, raw NCCL, custom).
    if [[ -n "$JOB_NAME" ]]; then
        section "NCCL Version Consistency (job: $JOB_NAME)"
        local ns="${NAMESPACE:-default}"
        local job_pods
        job_pods=$(kubectl get pods -n "$ns" -l "job-name=$JOB_NAME" --no-headers 2>/dev/null \
            | grep -E " Running " | awk '{print $1}' | head -4 || echo "")

        if [[ -z "$job_pods" ]]; then
            info "No Running pods in job '$JOB_NAME' — version check skipped"
        else
            # Read-only probe: find libnccl.so*, extract embedded version string,
            # fall back to SONAME filename parsing when `strings` is unavailable.
            # Variables below are expanded inside the remote pod via `kubectl exec
            # sh -c`, NOT locally — the quoted heredoc prevents local expansion.
            local lib_probe
            lib_probe=$(cat <<'REMOTE_PROBE'
NCCL_LIB=$(find /usr/local/cuda/lib64 /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /opt/nccl/lib /opt/amazon/ofi-nccl/lib -maxdepth 3 -name "libnccl.so*" -type f 2>/dev/null | head -1)
if [ -z "$NCCL_LIB" ]; then echo "not-found"; exit 0; fi
VER=$(strings "$NCCL_LIB" 2>/dev/null | grep -oE "NCCL version [0-9]+\.[0-9]+\.[0-9]+" | head -1 | sed "s/NCCL version //")
[ -z "$VER" ] && VER=$(basename "$(readlink -f "$NCCL_LIB")" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
[ -z "$VER" ] && VER="present-no-version"
echo "$VER"
REMOTE_PROBE
)
            local torch_versions=()
            local lib_versions=()
            for pod in $job_pods; do
                local tver lver
                tver=$(kubectl exec -n "$ns" "$pod" -- \
                    python3 -c "import torch; print(torch.cuda.nccl.version())" 2>/dev/null \
                    || echo "unavailable")
                lver=$(kubectl exec -n "$ns" "$pod" -- sh -c "$lib_probe" 2>/dev/null \
                    || echo "unavailable")
                info "  $pod: torch.nccl=$tver  libnccl.so=$lver"
                torch_versions+=("$tver")
                lib_versions+=("$lver")
            done

            local unique_torch unique_lib
            unique_torch=$(printf '%s\n' "${torch_versions[@]}" | grep -v unavailable | sort -u | wc -l | tr -d ' ')
            unique_lib=$(printf '%s\n' "${lib_versions[@]}" \
                | grep -vE "unavailable|not-found|present-no-version" | sort -u | wc -l | tr -d ' ')

            if [[ "$unique_torch" -gt 1 ]]; then
                error "NCCL VERSION MISMATCH (torch.cuda.nccl.version) across pods — will cause 'NCCL function not found' at init!"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                add_issue_detail "NCCL version mismatch across pods (torch) → references/debugging-guide.md § 10 NCCL Version Mismatch" "P1"
            fi
            if [[ "$unique_lib" -gt 1 ]]; then
                error "libnccl.so VERSION MISMATCH across pods — mixed NCCL libraries will cause symbol errors at init!"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                add_issue_detail "libnccl.so version mismatch across pods → references/debugging-guide.md § 10 NCCL Version Mismatch" "P1"
            fi
            if [[ "$unique_torch" -le 1 ]] && [[ "$unique_lib" -le 1 ]]; then
                if [[ "$unique_torch" -eq 1 ]] || [[ "$unique_lib" -eq 1 ]]; then
                    success "NCCL version consistent across ${#lib_versions[@]} pod(s)"
                else
                    info "NCCL version unavailable (neither torch nor libnccl.so could be probed)"
                fi
            fi
        fi
    fi
}

check_network_policies() {
    header "Check 9: Kubernetes NetworkPolicy Scan"

    local np_flag np_label
    if [[ -n "$NAMESPACE" ]]; then
        np_flag=(-n "$NAMESPACE")
        np_label="'$NAMESPACE'"
    else
        np_flag=(-A)
        np_label="all namespaces"
    fi

    local policies
    policies=$(kubectl get networkpolicy "${np_flag[@]}" 2>/dev/null || echo "")

    if [[ -z "$policies" ]] || echo "$policies" | grep -q "No resources found"; then
        success "No NetworkPolicies in $np_label — all traffic allowed"
        return
    fi

    # Informational — only raise a finding when the per-policy scan below
    # identifies one that actually blocks all ingress/egress. Narrow allow-list
    # policies (e.g. operator-scoped ingress) are common and not a defect.
    info "NetworkPolicies found in $np_label — review each for NCCL impact:"
    echo "$policies"

    local scope_flag
    local scope_flag=()
    if [[ -n "$NAMESPACE" ]]; then scope_flag=(-n "$NAMESPACE"); else scope_flag=(-A); fi
    kubectl get networkpolicy "${scope_flag[@]}" -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for pol in data.get('items', []):
    name = pol['metadata']['name']
    ns   = pol['metadata']['namespace']
    spec = pol.get('spec', {})
    types   = spec.get('policyTypes', [])
    ingress = spec.get('ingress', [])
    egress  = spec.get('egress', [])
    print(f'  Policy: {ns}/{name}  |  Types: {types}')
    if 'Ingress' in types and not ingress:
        print(f'    [FAIL] BLOCKS ALL INBOUND — will break NCCL rendezvous and AllReduce!')
    if 'Egress' in types and not egress:
        print(f'    [FAIL] BLOCKS ALL OUTBOUND — will break NCCL communication!')
    if ('Ingress' not in types) and ('Egress' not in types):
        print(f'    [INFO] Policy has no policyTypes — acts as allow-all')
" 2>/dev/null

    local scope_flag2
    local scope_flag2=()
    if [[ -n "$NAMESPACE" ]]; then
        scope_flag2=(-n "$NAMESPACE")
    else
        scope_flag2=(-A)
    fi
    local blocking_list
    blocking_list=$(kubectl get networkpolicy "${scope_flag2[@]}" -o json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    # kubectl returned non-JSON (empty stdin, error text, or version-skew output).
    # Skip this check rather than aborting the overall diagnostic run.
    sys.exit(0)
for pol in data.get('items', []):
    name = pol['metadata']['name']
    ns   = pol['metadata']['namespace']
    spec = pol.get('spec', {})
    types   = spec.get('policyTypes', [])
    ingress = spec.get('ingress', [])
    egress  = spec.get('egress', [])
    blocks = ('Ingress' in types and not ingress) or ('Egress' in types and not egress)
    if blocks:
        print(f'{ns}/{name}')
" 2>/dev/null || echo "")

    if [[ -n "$blocking_list" ]]; then
        while IFS= read -r bp; do
            [[ -z "$bp" ]] && continue
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "Blocking NetworkPolicy $bp may prevent NCCL traffic → references/operations.md § 8 NCCL-specific remediations (NetworkPolicy)" "P1"
        done <<< "$blocking_list"
    fi
}

# Populates SSM_CLUSTER_ID and SSM_NODES array (up to SAMPLE_NODES entries).
# Each entry is "INSTANCE_ID GROUP_NAME".
# Prefers worker/compute nodes over controller/head nodes.
# Respects --node <INSTANCE_ID> if provided.
resolve_cluster_nodes_for_ssm() {
    SSM_CLUSTER_ID=""
    SSM_NODES=()

    local cluster_arn
    cluster_arn=$(aws sagemaker describe-cluster \
        --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --query 'ClusterArn' --output text 2>/dev/null || echo "")

    if [[ -z "$cluster_arn" || "$cluster_arn" == "None" ]]; then
        debug "resolve_cluster_nodes_for_ssm: describe-cluster returned empty ARN"
        return 1
    fi

    SSM_CLUSTER_ID=$(echo "$cluster_arn" | awk -F'/' '{print $NF}')

    local nodes_json
    nodes_json=$(sagemaker_list_paginated list-cluster-nodes ClusterNodeSummaries)

    if [[ -n "$NODE_ID" ]]; then
        local grp
        grp=$(echo "$nodes_json" | python3 -c "
import sys, json
target = sys.argv[1]
nodes = json.load(sys.stdin).get('ClusterNodeSummaries', [])
for n in nodes:
    if n.get('InstanceId') == target:
        print(n.get('InstanceGroupName','worker'))
        break
" "$NODE_ID" 2>/dev/null | head -1)
        [[ -z "$grp" ]] && grp="worker"
        SSM_NODES=("$NODE_ID $grp")
        return 0
    fi

    local all_nodes
    all_nodes=$(echo "$nodes_json" | python3 -c "
import sys, json
print(json.dumps(json.load(sys.stdin).get('ClusterNodeSummaries', [])))
" 2>/dev/null || echo '[]')

    # For NCCL diagnostics, hardware probes (nvidia-smi, fi_info -p efa,
    # neuron-ls) only produce meaningful signal on GPU / accelerator nodes.
    # Prioritize by type: GPU/Neuron first, other Running compute next, then
    # fall back to any Running node so the script still reports on a cluster
    # that has only CPU nodes.
    local picked
    picked=$(echo "$all_nodes" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
sample = $SAMPLE_NODES

# Instance-type prefixes that carry NVIDIA GPUs or AWS Trainium/Inferentia.
# A node's instance type shows up in ClusterNodeSummaries as e.g. 'ml.p5.48xlarge'.
GPU_PREFIXES = ('ml.p3', 'ml.p3dn', 'ml.p4d', 'ml.p4de', 'ml.p5', 'ml.p5e',
                'ml.p5en', 'ml.p6', 'ml.g4dn', 'ml.g5', 'ml.g6', 'ml.g6e', 'ml.g7e')
NEURON_PREFIXES = ('ml.trn1', 'ml.trn2', 'ml.inf2')
ACCEL_PREFIXES = GPU_PREFIXES + NEURON_PREFIXES

def is_utility_group(name):
    n = (name or '').lower()
    return any(x in n for x in ('controller', 'head', 'master'))

def itype(n):
    return n.get('InstanceType', '') or ''

running = [n for n in nodes if n.get('InstanceStatus', {}).get('Status', '') == 'Running']

# Tier 1: running + accelerator type + not a controller group
tier1 = [n for n in running if itype(n).startswith(ACCEL_PREFIXES) and not is_utility_group(n.get('InstanceGroupName', ''))]
# Tier 2: running + non-controller (may be CPU-only compute)
tier2 = [n for n in running if n not in tier1 and not is_utility_group(n.get('InstanceGroupName', ''))]
# Tier 3: anything else running (utility / controller nodes, last resort)
tier3 = [n for n in running if n not in tier1 and n not in tier2]

results = []
for n in tier1 + tier2 + tier3:
    if len(results) >= sample:
        break
    results.append(n['InstanceId'] + ' ' + n['InstanceGroupName'])
for r in results:
    print(r)
" 2>/dev/null || echo "")

    if [[ -z "$picked" ]]; then
        debug "resolve_cluster_nodes_for_ssm: no Running nodes found"
        return 1
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] && SSM_NODES+=("$line")
    done <<< "$picked"

    return 0
}

# Usage: _ssm_run INSTANCE_ID GROUP_NAME CLUSTER_ID SCRIPT_BODY
# Returns the stdout of the remote script, or empty on failure.
_ssm_run() {
    local instance_id="$1"
    local group_name="$2"
    local cluster_id="$3"
    local script_body="$4"

    # Validate inputs before interpolating into the SSM target string.
    [[ -z "$instance_id" || -z "$group_name" || -z "$cluster_id" || -z "$script_body" ]] && return 1
    [[ ! "$instance_id" =~ ^i-[0-9a-f]{8,17}$ ]] && return 1
    [[ ! "$group_name"  =~ ^[A-Za-z0-9._-]+$ ]] && return 1
    [[ ! "$cluster_id"  =~ ^[A-Za-z0-9._-]+$ ]] && return 1

    local target="sagemaker-cluster:${cluster_id}_${group_name}-${instance_id}"

    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/nccl-ssm-XXXXXX.json") || return 1
    chmod 600 "$tmpfile" 2>/dev/null || true
    _TEMP_FILES+=("$tmpfile")
    # AWS-StartNonInteractiveCommand collapses newlines in a single command
    # element, so embed the multi-line script as a base64 payload.
    local cmd_b64
    cmd_b64=$(printf '%s' "$script_body" | base64 | tr -d '\n') || { rm -f "$tmpfile"; return 1; }
    local remote="bash -c \"echo $cmd_b64 | base64 -d | bash\""
    python3 -c "import json,sys; print(json.dumps({'command':[sys.argv[1]]}))" "$remote" > "$tmpfile" 2>/dev/null || { rm -f "$tmpfile"; return 1; }

    # session-manager-plugin races to close before flushing its last stdout
    # block; `unbuffer` (from the `expect` package) gives it a PTY and avoids
    # the resulting "Cannot perform start session: EOF". Required — see the
    # prerequisite check at script startup.

    # Retry transient SSM session errors (EOF, throttling, i/o timeout).
    # Do not retry AccessDenied / UnauthorizedOperation — permanent IAM denials.
    local out attempt=0
    while (( attempt < 5 )); do
        out=$(unbuffer timeout 180 aws ssm start-session \
            --target "$target" \
            --region "$REGION" \
            --document-name AWS-StartNonInteractiveCommand \
            --parameters "file://$tmpfile" 2>&1 || echo "")
        # Fatal (don't retry) — permanent IAM or agent state.
        if echo "$out" | grep -qiE "AccessDenied|UnauthorizedOperation|not authorized to perform|TargetNotConnected"; then
            break
        fi
        if ! echo "$out" | grep -qiE "Cannot perform start session|EOF$|SessionManagerPlugin is not found|i/o timeout|ThrottlingException|RequestLimitExceeded|InternalFailure|ServiceUnavailable"; then
            break
        fi
        attempt=$((attempt + 1))
        sleep $((attempt * 3))
    done
    rm -f "$tmpfile"
    # Strip SSM session banners and the echoed base64 command line.
    echo "$out" | grep -vE '^(Starting session with SessionId:|Exiting session with sessionId:|\s*$)' \
                | grep -vE "^(bash -c \"echo [A-Za-z0-9+/=]+ \| base64 -d \| bash\"|echo '[A-Za-z0-9+/=]+'|[A-Za-z0-9+/=]{40,}={0,2})[[:space:]]*\|?[[:space:]]*base64?[[:space:]]*-?d?[[:space:]]*\|?[[:space:]]*bash\"?\$" || true
}

# Self-contained bash script executed on each HyperPod compute node via SSM.
# Covers GPU, EFA, NCCL library, network, memory, and process health.
_NODE_DIAG_SCRIPT=$(cat <<'NODE_SCRIPT'
#!/bin/bash
# HyperPod NCCL Node Hardware Diagnostics
# Runs ON the compute node via SSM — NOT on the local machine.
export PATH="/opt/amazon/efa/bin:/usr/local/cuda/bin:$PATH"

echo "=== NODE DIAGNOSTICS ==="
echo "Host: $(hostname)"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Kernel: $(uname -r)"

# Instance type via IMDS (v2)
IMDS_TOKEN=$(curl -sf -m 3 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || echo "")
if [ -n "$IMDS_TOKEN" ]; then
    INSTANCE_TYPE=$(curl -sf -m 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        "http://169.254.169.254/latest/meta-data/instance-type" 2>/dev/null || echo "unknown")
    AZ=$(curl -sf -m 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        "http://169.254.169.254/latest/meta-data/placement/availability-zone" 2>/dev/null || echo "unknown")
else
    INSTANCE_TYPE="unknown"
    AZ="unknown"
fi
echo "Instance: ${INSTANCE_TYPE} | AZ: ${AZ}"
echo ""

echo "--- GPU ---"
# Require both the binary AND at least one GPU visible. nvidia-smi is preinstalled
# on some non-GPU instance types (t3/c5) but returns "No devices were found" —
# reporting that as [FAIL] would be a false positive on controllers/logins.
if command -v nvidia-smi &>/dev/null && nvidia-smi -L 2>/dev/null | grep -q "^GPU"; then
    nvidia-smi --query-gpu=index,name,driver_version,memory.used,memory.total,temperature.gpu,utilization.gpu \
        --format=csv,noheader 2>/dev/null \
        && echo "" \
        || echo "[FAIL] nvidia-smi query failed"

    # XID errors indicate hardware faults that will cause NCCL to abort.
    # Modern A100/H100 drivers log XIDs to dmesg but NOT to nvidia-smi -q,
    # so check both sources — verified on-hardware with A100 driver 580.126
    # where an injected XID 31 appeared in dmesg but was invisible to -q.
    XID_DMESG=$(dmesg 2>/dev/null | grep -E 'NVRM: Xid' | tail -5)
    XID_SMI=$(nvidia-smi -q 2>/dev/null | grep -E '^[[:space:]]*Xid' | head -5)
    if [ -n "$XID_DMESG" ] || [ -n "$XID_SMI" ]; then
        echo "[FAIL] GPU XID ERRORS DETECTED (hardware fault — NCCL will abort):"
        [ -n "$XID_DMESG" ] && echo "$XID_DMESG"
        [ -n "$XID_SMI" ] && echo "$XID_SMI"
    else
        echo "[PASS] No GPU XID errors"
    fi

    # Only surface nonzero ECC counts. 'ECC Errors' section header and
    # 'Uncorrectable ... : 0' lines fire on every healthy GPU.
    ECC=$(nvidia-smi -q 2>/dev/null | awk '
        /Uncorrectable/ { if ($NF ~ /^[0-9]+$/ && $NF+0 > 0) print }
    ' | head -5)
    [ -n "$ECC" ] && echo "[FAIL] GPU uncorrectable ECC errors detected: $ECC" || echo "[PASS] No ECC errors"

    # Row-remap state — marginal GPU memory. Pending rows need a reset to finalize;
    # Failed means exceeded remap capacity (bad memory). Silent degrader that
    # default DCGM medium + memtest in some driver versions miss entirely.
    REMAP=$(nvidia-smi --query-remapped-rows=gpu_bus_id,remapped_rows.pending,remapped_rows.failure \
        --format=csv,noheader 2>/dev/null)
    if [ -n "$REMAP" ]; then
        PENDING_SUM=$(echo "$REMAP" | awk -F, '{gsub(/ /,""); s+=$2} END {print s+0}')
        FAILED_COUNT=$(echo "$REMAP" | awk -F, '{gsub(/ /,""); if ($3=="Yes" || $3=="1") c++} END {print c+0}')
        if [ "$FAILED_COUNT" -gt 0 ]; then
            echo "[FAIL] GPU row-remap FAILED on $FAILED_COUNT device(s) — bad memory, replace GPU"
        elif [ "$PENDING_SUM" -gt 0 ]; then
            echo "[FAIL] GPU row-remap PENDING ($PENDING_SUM row(s)) — marginal memory; reset/reboot to finalize"
            echo "       If pending persists across reboots, firmware may be stuck — replace GPU"
        else
            echo "[PASS] GPU row-remap: no pending or failed rows"
        fi
    fi

    # DCGM health — complements XID/ECC above. Parse Fail/Warn verdicts only
    # (Pass is not authoritative on DCGM <= 3.3.9 due to memtest bug).
    if command -v dcgmi >/dev/null 2>&1; then
        DCGM_OUT=$(dcgmi health --check -j 2>/dev/null || dcgmi health --check 2>/dev/null || echo "")
        if echo "$DCGM_OUT" | grep -qiE '"overall_health"\s*:\s*"(Fail|Warn)"|HEALTH_RESULT_FAIL|HEALTH_RESULT_WARN|Health Monitor Report.*(Fail|Warn)'; then
            echo "[FAIL] DCGM health check reports Fail/Warn — inspect with 'dcgmi health --check'"
        fi
    fi

    # DCGM nvvs log presence — HyperPod deep-health-check writes here.
    if [ -d /var/log/nvidia-dcgm ]; then
        NVVS_LATEST=$(find /var/log/nvidia-dcgm -maxdepth 1 -name 'nvvs*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')
        if [ -n "$NVVS_LATEST" ]; then
            if tail -n 200 "$NVVS_LATEST" 2>/dev/null | grep -qiE 'row ?remap.*(pending|fail)|FAIL: |Error: '; then
                echo "[FAIL] DCGM nvvs log contains failure / row-remap signals: $NVVS_LATEST"
            fi
        fi
    fi

    # NVLink — important for p4d/p5 multi-GPU NCCL bandwidth.
    # Output format across driver versions:
    #   - 'Link N: X GB/s'   (active, driver 470+)
    #   - 'Link N: Active'   (older drivers)
    #   - 'error'/'fail'/'inactive' keywords when degraded
    NVLINK=$(nvidia-smi nvlink --status 2>/dev/null | head -200)
    if echo "$NVLINK" | grep -qiE "error|fail|inactive"; then
        echo "[FAIL] NVLink errors/inactive links detected (replace node):"
        echo "$NVLINK" | grep -iE "error|fail|inactive"
    else
        ACTIVE_COUNT=$(echo "$NVLINK" | grep -cE "Link [0-9]+:[[:space:]]+([0-9]+ GB/s|Active)" || true)
        if [ "${ACTIVE_COUNT:-0}" -gt 0 ]; then
            echo "[PASS] NVLink: $ACTIVE_COUNT active link(s)"
        else
            echo "[INFO] NVLink not available (expected on single-GPU or non-NVLink instances)"
        fi
    fi

    # GPU P2P topology — critical for intra-node NCCL AllReduce performance
    echo ""
    echo "--- GPU P2P Topology (nvidia-smi topo) ---"
    nvidia-smi topo -m 2>/dev/null | head -25 | while IFS= read -r line; do
        if echo "$line" | grep -qiE "NV[0-9]|NVLink"; then
            echo "  [PASS] $line"
        elif echo "$line" | grep -qiE "PIX|PXB|PHB|SOC"; then
            echo "  [WARN] $line  <- PCIe path (slower than NVLink)"
        else
            echo "  [INFO] $line"
        fi
    done

    # PCI ACS — intercepts GPU Direct P2P → 10-50x slower intra-node AllReduce or hang
    echo ""
    echo "--- PCI ACS (Access Control Services) ---"
    if command -v lspci &>/dev/null; then
        ACS_ENABLED=$(lspci -vvv 2>/dev/null | grep -A20 "PCI bridge\|Root Port\|Upstream Port" \
            | grep "ACSCtl:" | { grep -c "SrcValid+" 2>/dev/null; true; })
        if [ "$ACS_ENABLED" -gt 0 ] 2>/dev/null; then
            echo "[FAIL] ACS enabled on $ACS_ENABLED PCI bridge(s) — GPU Direct P2P blocked!"
            echo "       Symptom: 'NCCL WARN P2P not supported between dev X and dev Y'"
            echo "       Impact:  10-50x slower intra-node AllReduce"
        else
            echo "[PASS] ACS not enabled on PCI bridges — GPU Direct P2P unobstructed"
        fi
    else
        echo "[INFO] lspci not available — install pciutils to check ACS"
    fi

    IOMMU=$(dmesg 2>/dev/null | grep -iE "iommu.*enabled|dmar.*enabled" | head -2 || \
            grep -oE "intel_iommu=[^ ]+|iommu=[^ ]+" /proc/cmdline 2>/dev/null | head -1 || echo "")
    if [ -n "$IOMMU" ]; then
        echo "[WARN] IOMMU may be enabled: $IOMMU"
        echo "       On baremetal: disable VT-d/IOMMU in BIOS for best GPU Direct P2P"
        echo "       In VMs: normal — use ATS on network adapters"
    else
        echo "[PASS] IOMMU: not detected as enabled"
    fi

    [ "${NCCL_P2P_DISABLE:-0}" = "1" ] && \
        echo "[WARN] NCCL_P2P_DISABLE=1 set — workaround active, performance degraded" || true

    # nvidia-peermem — GPU Direct RDMA to NIC (required for EFA↔GPU on p4d/p5)
    echo ""
    echo "--- nvidia-peermem (GPU Direct RDMA) ---"
    if lsmod 2>/dev/null | grep -q "nvidia_peermem\|nv_peer_mem"; then
        echo "[PASS] nvidia-peermem loaded — GPU Direct RDMA to EFA/NIC enabled"
    else
        # Kernel 5.12+ uses DMA-BUF instead of nvidia-peermem.
        KVER_MAJOR=$(uname -r | cut -d. -f1)
        KVER_MINOR=$(uname -r | cut -d. -f2)
        if [ "$KVER_MAJOR" -gt 5 ] || { [ "$KVER_MAJOR" -eq 5 ] && [ "$KVER_MINOR" -ge 12 ]; } 2>/dev/null; then
            echo "[INFO] nvidia-peermem not loaded; kernel $(uname -r) supports DMA-BUF (auto-detected)"
        else
            echo "[WARN] nvidia-peermem NOT loaded — EFA↔GPU copies go through CPU"
        fi
    fi
else
    if command -v nvidia-smi &>/dev/null; then
        echo "[INFO] nvidia-smi installed but no GPU devices visible — likely a CPU-only node (controller/login)"
    else
        echo "[INFO] nvidia-smi not found — CPU-only node or GPU driver not installed"
    fi
fi
echo ""

echo "--- EFA ---"

if lsmod 2>/dev/null | grep -q "^efa "; then
    EFA_MOD_VER=$(modinfo efa 2>/dev/null | grep "^version:" | awk '{print $2}' || echo "unknown")
    echo "[PASS] EFA kernel module loaded (version: ${EFA_MOD_VER})"
else
    EFA_DEVS=$(ls /dev/infiniband/uverbs* 2>/dev/null || echo "")
    EFA_IFACES=$(ip -br link show 2>/dev/null | grep -cE "^efa" || echo 0)
    if [ -n "$EFA_DEVS" ] || [ "$EFA_IFACES" -gt 0 ] 2>/dev/null; then
        echo "[FAIL] EFA devices present but kernel module NOT loaded — NCCL EFA will fail"
    else
        echo "[INFO] EFA kernel module not loaded (expected on non-EFA instances)"
    fi
fi

FI_CMD=""
command -v fi_info &>/dev/null && FI_CMD="fi_info"
[ -z "$FI_CMD" ] && [ -f /opt/amazon/efa/bin/fi_info ] && FI_CMD="/opt/amazon/efa/bin/fi_info"

if [ -n "$FI_CMD" ]; then
    EFA_OUTPUT=$($FI_CMD -p efa 2>&1)
    if echo "$EFA_OUTPUT" | grep -q "provider: efa"; then
        EFA_COUNT=$(echo "$EFA_OUTPUT" | { grep -c "provider: efa" 2>/dev/null; true; })
        echo "[PASS] EFA provider available: $EFA_COUNT interface(s)"
        echo "$EFA_OUTPUT" | grep "device:" | head -5

        # Validate EFA count against expected per-instance-type counts. A subset
        # of NICs silently failing to attach is a top NCCL failure mode (training
        # runs at reduced bandwidth with no error). Counts per AWS EC2 docs.
        IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --connect-timeout 2 2>/dev/null || echo "")
        if [ -n "$IMDS_TOKEN" ]; then
            INST_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
                http://169.254.169.254/latest/meta-data/instance-type --connect-timeout 2 2>/dev/null || echo "")
            # Counts only included where AWS publishes them in the EC2 EFA
            # docs (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-acc-inst-types.html).
            # For other types the doc lists bandwidth but not card count, so we
            # skip the check rather than guess.
            case "$INST_TYPE" in
                p5.48xlarge|p5e.48xlarge)   EXPECTED_EFA=32 ;;
                p5en.48xlarge)              EXPECTED_EFA=16 ;;
                p4d.24xlarge)               EXPECTED_EFA=4 ;;
                p6-b200.48xlarge)           EXPECTED_EFA=8 ;;
                p6-b300.48xlarge)           EXPECTED_EFA=17 ;;
                p6e-gb200.36xlarge)         EXPECTED_EFA=17 ;;
                *)                          EXPECTED_EFA=0 ;;
            esac
            if [ "$EXPECTED_EFA" -gt 0 ] 2>/dev/null; then
                if [ "$EFA_COUNT" -lt "$EXPECTED_EFA" ] 2>/dev/null; then
                    echo "[FAIL] EFA count mismatch on ${INST_TYPE}: got ${EFA_COUNT}, expected ${EXPECTED_EFA}"
                    echo "       A subset of NICs failed to attach — NCCL will run at reduced bandwidth"
                else
                    echo "[PASS] EFA count matches ${INST_TYPE} expected value (${EXPECTED_EFA})"
                fi
            else
                echo "[INFO] EFA count validation skipped — no expected value for ${INST_TYPE:-unknown}"
            fi
        fi
    else
        # Determine whether EFA is expected — absence on non-EFA instance types
        # (t3, c5, controllers) is normal, not a failure.
        INST_TYPE_CHECK="${INST_TYPE:-}"
        case "$INST_TYPE_CHECK" in
            p4d.*|p4de.*|p5.*|p5e.*|p5en.*|p6*|trn1.*|trn2.*)
                echo "[FAIL] EFA provider NOT available on ${INST_TYPE_CHECK}"
                echo "  fi_info -p efa returned no results"
                echo "  Required for NCCL on this instance type — training will fall back to TCP (very slow)"
                ;;
            *)
                echo "[INFO] EFA provider not available — expected on non-EFA instance type (${INST_TYPE_CHECK:-unknown})"
                ;;
        esac
    fi
    TCP_COUNT=$($FI_CMD -p tcp 2>/dev/null | { grep -c "provider: tcp" 2>/dev/null; true; })
    LF_VER=$($FI_CMD --version 2>&1 | grep libfabric | sed 's/.*: //' | head -1)
    echo "  libfabric: ${LF_VER:-unknown}  |  TCP fallback endpoints: $TCP_COUNT"
else
    echo "[INFO] fi_info not found — EFA tools not installed (OK for non-EFA instances)"
fi

[ -f /opt/amazon/efa_installed_packages ] && \
    grep "# EFA installer version" /opt/amazon/efa_installed_packages | head -1 \
    || echo "[INFO] /opt/amazon/efa_installed_packages not found"

# aws-ofi-nccl — bridges NCCL and EFA, required for GPU training on EFA instances
OFI_LIB=$(find /opt/amazon/ofi-nccl /usr/local/lib /usr/lib /opt/aws-ofi-nccl/lib \
    -maxdepth 4 -name "libnccl-net.so" 2>/dev/null | head -1)
NCCL_NET_PLUGIN_ENV="${NCCL_NET_PLUGIN:-}"
if [ -n "$NCCL_NET_PLUGIN_ENV" ]; then
    [ -f "$NCCL_NET_PLUGIN_ENV" ] && \
        echo "[PASS] NCCL_NET_PLUGIN=$NCCL_NET_PLUGIN_ENV (file exists)" || \
        echo "[FAIL] NCCL_NET_PLUGIN=$NCCL_NET_PLUGIN_ENV — FILE NOT FOUND! NCCL EFA will fail"
elif [ -n "$OFI_LIB" ]; then
    echo "[PASS] aws-ofi-nccl plugin: $OFI_LIB"
else
    # FAIL only if FI_PROVIDER=efa is set; otherwise informational.
    [ "${FI_PROVIDER:-}" = "efa" ] && \
        echo "[FAIL] FI_PROVIDER=efa but aws-ofi-nccl plugin not found — NCCL EFA will fail" || \
        echo "[INFO] aws-ofi-nccl not found (required for EFA+NCCL; not needed for CPU-only)"
fi

# Hugepages — improve EFA/RDMA memory registration performance
HP_2M=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo 0)
HP_1G=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo 0)
if [ "$HP_2M" -gt 0 ] 2>/dev/null; then
    HP_FREE=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo 0)
    echo "[PASS] 2MB hugepages: ${HP_2M} total, ${HP_FREE} free"
    [ "$HP_FREE" -eq 0 ] && echo "[WARN] All hugepages in use — RDMA may have reduced performance"
elif [ "$HP_1G" -gt 0 ] 2>/dev/null; then
    echo "[PASS] 1GB hugepages: ${HP_1G} allocated"
else
    echo "[INFO] No hugepages configured (set vm.nr_hugepages=512 for optimal EFA RDMA)"
fi
echo ""

echo "--- NCCL ---"
NCCL_LIB=$(find /usr/local/cuda*/lib* /usr/lib /opt/nccl/lib 2>/dev/null \
    -maxdepth 4 -name "libnccl.so*" 2>/dev/null | head -3)
if [ -n "$NCCL_LIB" ]; then
    echo "[PASS] NCCL library found:"
    echo "$NCCL_LIB" | while read -r l; do echo "  $l"; done
else
    echo "[INFO] NCCL library not found (install NCCL for distributed GPU training)"
fi

NCCL_HDR=$(find /usr/local/cuda*/include /usr/include /opt/nccl/include 2>/dev/null \
    -maxdepth 3 -name "nccl.h" 2>/dev/null | head -1)
if [ -n "$NCCL_HDR" ]; then
    NCCL_VER=$(grep -E "NCCL_MAJOR|NCCL_MINOR|NCCL_PATCH" "$NCCL_HDR" 2>/dev/null \
        | awk '{print $3}' | tr '\n' '.' | sed 's/\.$//')
    [ -n "$NCCL_VER" ] && echo "  NCCL version: $NCCL_VER"
fi

CUDA_DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "")
if [ -n "$CUDA_DRV" ] && [ -n "$NCCL_VER" ]; then
    DRV_MAJOR=$(echo "$CUDA_DRV" | cut -d. -f1)
    NCCL_MAJOR=$(echo "$NCCL_VER" | cut -d. -f1)
    NCCL_MINOR=$(echo "$NCCL_VER" | cut -d. -f2)
    # NCCL 2.20+ requires CUDA driver >= 525
    if { [ "$NCCL_MAJOR" -gt 2 ] || { [ "$NCCL_MAJOR" -eq 2 ] && [ "${NCCL_MINOR:-0}" -ge 20 ]; }; } && [ "$DRV_MAJOR" -gt 0 ] && [ "$DRV_MAJOR" -lt 525 ] 2>/dev/null; then
        echo "[WARN] NCCL $NCCL_VER may require CUDA driver >= 525; found $CUDA_DRV"
        echo "       Symptom: 'NCCL function not found' on mixed-version nodes"
    fi
fi
echo ""

echo "--- Network Interfaces ---"
ip -br addr show 2>/dev/null | while IFS= read -r line; do
    IFACE=$(echo "$line" | awk '{print $1}')
    STATE=$(echo "$line" | awk '{print $2}')
    ADDR=$(echo "$line" | awk '{print $3}')
    if   echo "$IFACE" | grep -q "^lo";                       then TYPE="loopback"
    elif echo "$IFACE" | grep -qE "^efa|^rdma";               then TYPE="EFA device"
    elif echo "$IFACE" | grep -qE "^ib[0-9]";                 then TYPE="InfiniBand"
    elif echo "$IFACE" | grep -qE "^eth|^ens|^enp|^en[0-9]"; then TYPE="VPC ENI"
    elif echo "$IFACE" | grep -qE "^docker|^br-|^veth";       then TYPE="container bridge"
    else TYPE="other"; fi
    printf "  %-18s %-8s %-20s (%s)\n" "$IFACE" "$STATE" "${ADDR:--}" "$TYPE"
done
echo ""

echo "--- MTU ---"
ip -br link show 2>/dev/null | grep -v "^lo" | while IFS= read -r line; do
    IFACE=$(echo "$line" | awk '{print $1}')
    MTU=$(ip link show "$IFACE" 2>/dev/null | grep -o "mtu [0-9]*" | awk '{print $2}')
    [ -z "$MTU" ] && continue
    if   echo "$IFACE" | grep -qE "docker|br-|veth"; then echo "  [INFO] $IFACE: MTU=$MTU (container bridge — OK)"
    elif [ "$MTU" -ge 9000 ] 2>/dev/null;             then echo "  [PASS] $IFACE: MTU=$MTU (jumbo frames — optimal for EFA)"
    else echo "  [WARN] $IFACE: MTU=$MTU — expected 9001 for EFA/RDMA (fragmentation risk for large tensors)"; fi
done
echo ""

echo "--- Memory & Limits ---"
free -h
echo ""

SHM_SIZE=$(df -BG /dev/shm 2>/dev/null | tail -1 | awk '{print $2}' | tr -d 'G')
SHM_FS=$(df -T /dev/shm 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
if [ -n "$SHM_SIZE" ] && [ "$SHM_SIZE" -ge 1 ] 2>/dev/null; then
    echo "[PASS] /dev/shm: ${SHM_SIZE}GB (fs: ${SHM_FS})"
    [ "$SHM_SIZE" -lt 4 ] 2>/dev/null && \
        echo "[WARN] /dev/shm ${SHM_SIZE}GB < 4GB — consider 4GB+ for large model training"
else
    echo "[FAIL] /dev/shm: ${SHM_SIZE:-0}GB — NCCL needs ≥1GB (K8s default=64MB)"
    echo "       Symptom: 'failed to extend /dev/shm/nccl-*' or Bus error"
fi
[ "$SHM_FS" != "tmpfs" ] && [ "$SHM_FS" != "unknown" ] && \
    echo "[WARN] /dev/shm fs type: $SHM_FS (expected tmpfs)"

MEMLOCK=$(ulimit -l 2>/dev/null || echo "unknown")
if [ "$MEMLOCK" = "0" ]; then
    echo "[FAIL] memlock=0 — InfiniBand/EFA RDMA memory registration WILL FAIL"
    echo "       Symptom: 'NCCL WARN Call to ibv_reg_mr failed'"
elif [ -n "$MEMLOCK" ] && [ "$MEMLOCK" != "unlimited" ] && [ "$MEMLOCK" -ge 8388608 ] 2>/dev/null; then
    echo "[PASS] memlock=${MEMLOCK}KB (≥8GB — OK)"
elif [ "$MEMLOCK" = "unlimited" ]; then
    echo "[INFO] memlock=unlimited (OK for RDMA; see stack check below for libc quirk)"
else
    echo "[INFO] memlock=${MEMLOCK}KB"
fi

# Stack size — GNU libc quirk: when memlock=unlimited, thread stack is reduced to 2MB.
# NCCL topology graph search (especially MNNVL on 256+ nodes) needs 8MB+ stack.
STACK=$(ulimit -s 2>/dev/null || echo "unknown")
if [ "$MEMLOCK" = "unlimited" ] && [ "$STACK" = "unlimited" ]; then
    echo "[WARN] memlock=unlimited + stack=unlimited — GNU libc reduces NCCL thread stack to 2MB"
    echo "       NCCL MNNVL/large topology graph search needs 8MB+ and will fail"
elif [ "$STACK" = "unlimited" ]; then
    echo "[PASS] stack=unlimited (memlock is bounded, so libc quirk does not apply)"
elif [ "$STACK" != "unknown" ] && [ "$STACK" -lt 4096 ] 2>/dev/null; then
    echo "[FAIL] stack=${STACK}KB — too small for NCCL topology search (need ≥4096KB)"
else
    echo "[PASS] stack=${STACK:-unknown}KB"
fi

# systemd RemoveIPC — deletes NCCL shm files when session ends (Slurm nodes)
# Strip comment lines first; many distros ship logind.conf with `#RemoveIPC=yes`
# as the documented default, which would false-WARN on a substring match.
if [ -f /etc/systemd/logind.conf ]; then
    REMOVEIPC=$(grep -v '^[[:space:]]*#' /etc/systemd/logind.conf 2>/dev/null \
                  | grep -i "RemoveIPC" | tail -1 || echo "")
    if [ -z "$REMOVEIPC" ]; then
        echo "[WARN] RemoveIPC unset in /etc/systemd/logind.conf — defaults to 'yes' on RHEL/Amazon Linux"
        echo "       Symptom: 'unlink shared memory /dev/shm/nccl-* failed: No such file'"
    elif echo "$REMOVEIPC" | grep -qi "yes\|true\|1"; then
        echo "[WARN] systemd RemoveIPC=yes — NCCL shm files will be deleted at session end"
        echo "       Symptom: 'unlink shared memory /dev/shm/nccl-* failed: No such file'"
    else
        echo "[PASS] systemd RemoveIPC=no — NCCL shm files will not be deleted"
    fi
fi

# cuMem NUMA (NCCL 2.23+)
NUMA_NODES=$(ls /sys/devices/system/node/ 2>/dev/null | { grep -c "^node[0-9]" 2>/dev/null; true; })
if [ "$NUMA_NODES" -gt 0 ] 2>/dev/null; then
    echo "[PASS] NUMA topology: $NUMA_NODES node(s) visible (cuMem host alloc OK)"
else
    echo "[WARN] NUMA topology not visible — cuMem host allocations may fail"
fi
echo ""

echo "--- NCCL RAS ---"
# RAS port is configurable via NCCL_RAS_ADDR. Probe whatever is in the
# training process's environment; skip if no candidate is found rather than
# hard-coding a port that may not match every NCCL build.
NC_CMD=$(command -v nc 2>/dev/null || command -v ncat 2>/dev/null || echo "")
if [ -n "$NC_CMD" ]; then
    RAS_PID=$(pgrep -f "python|torchrun|mpirun" 2>/dev/null | head -1)
    RAS_ADDR=""
    if [ -n "$RAS_PID" ] && [ -r "/proc/$RAS_PID/environ" ]; then
        RAS_ADDR=$(tr '\0' '\n' < "/proc/$RAS_PID/environ" 2>/dev/null \
                   | awk -F= '/^NCCL_RAS_ADDR=/{print $2}' | head -1)
    fi
    RAS_HOST="${RAS_ADDR%:*}"; RAS_PORT="${RAS_ADDR##*:}"
    if [ -n "$RAS_PORT" ] && [ "$RAS_PORT" != "$RAS_ADDR" ]; then
        RAS=$(echo "status" | timeout 3 $NC_CMD -w 2 "${RAS_HOST:-localhost}" "$RAS_PORT" 2>/dev/null || echo "")
        if [ -n "$RAS" ]; then
            echo "[PASS] NCCL RAS responding at ${RAS_HOST:-localhost}:${RAS_PORT}:"
            echo "$RAS" | head -10
        else
            echo "[INFO] NCCL RAS port ${RAS_PORT} not responding — training job may not be using RAS, or RAS is disabled (NCCL_RAS_ENABLE=0)"
        fi
    else
        echo "[INFO] NCCL_RAS_ADDR not set in any training process — skipping RAS probe (set NCCL_RAS_ADDR=<host>:<port> and re-run during training to enable)"
    fi
else
    echo "[INFO] nc/ncat not found — cannot probe NCCL RAS"
fi
echo ""

echo "--- Active Training Processes ---"
PROCS=$(ps aux 2>/dev/null | grep -E "python|torchrun|mpirun|nccl_test" | grep -v grep | head -10)
if [ -n "$PROCS" ]; then
    echo "$PROCS"
else
    echo "[INFO] No active training processes"
fi
echo ""

echo "--- Recent Hardware Errors (dmesg) ---"
DMESG=$(dmesg 2>/dev/null | grep -iE "xid|nvrm|efa|ib_core|rdma|correctable|uncorrectable|acs|iommu" \
    | tail -20 || echo "")
if [ -n "$DMESG" ]; then
    echo "$DMESG"
else
    echo "[PASS] No hardware errors in dmesg"
fi

# iptables / nftables — host-level firewall rules that block NCCL
echo "--- Host Firewall (iptables/nftables) ---"
IPT_DROP=0
if command -v iptables &>/dev/null; then
    IPT_DROP=$(iptables -L -n 2>/dev/null | grep -cE "DROP|REJECT" || echo 0)
    if [ "$IPT_DROP" -gt 0 ] 2>/dev/null; then
        echo "[WARN] iptables has $IPT_DROP DROP/REJECT rules — may block NCCL traffic"
        iptables -L -n 2>/dev/null | grep -E "DROP|REJECT" | head -5
        echo "       Verify NCCL ports (29400-29500, RDMA) are not blocked"
    else
        echo "[PASS] iptables: no DROP/REJECT rules"
    fi
elif command -v nft &>/dev/null; then
    NFT_DROP=$(nft list ruleset 2>/dev/null | grep -cE "drop|reject" || echo 0)
    if [ "$NFT_DROP" -gt 0 ] 2>/dev/null; then
        echo "[WARN] nftables has $NFT_DROP drop/reject rules — may block NCCL traffic"
    else
        echo "[PASS] nftables: no drop/reject rules"
    fi
else
    echo "[INFO] iptables/nftables not found"
fi
echo ""

echo "--- Stale NCCL Shared Memory ---"
STALE_SHM=$(ls /dev/shm/nccl-* 2>/dev/null || echo "")
if [ -n "$STALE_SHM" ]; then
    STALE_COUNT=$(echo "$STALE_SHM" | wc -l)
    echo "[WARN] $STALE_COUNT stale NCCL shared memory file(s) found:"
    echo "$STALE_SHM" | head -5
    echo "       From a previous training run — may cause 'file exists' errors"
else
    echo "[PASS] No stale NCCL shared memory files"
fi
echo ""

# EFA Latency Check (fi_ping) — catches degraded EFA ports (straggler #1 cause)
echo "--- EFA Latency (fi_ping self-test) ---"
FI_PING_CMD=""
command -v fi_ping &>/dev/null && FI_PING_CMD="fi_ping"
[ -z "$FI_PING_CMD" ] && [ -f /opt/amazon/efa/bin/fi_ping ] && FI_PING_CMD="/opt/amazon/efa/bin/fi_ping"

if [ -n "$FI_PING_CMD" ]; then
    # Self-ping on loopback — tests EFA stack without needing a second node
    # A degraded EFA port shows high latency (>20us) even on self-ping
    # Validate FI_PING_CMD is a known safe EFA binary path (not user-controlled)
    if [[ ! "$FI_PING_CMD" =~ ^(/opt/amazon/efa/bin/fi_ping|fi_ping)$ ]]; then
        echo "[SKIP] fi_ping path not recognised: $FI_PING_CMD"
    else
        # Try EFA provider first; if it succeeds, the result reflects EFA. If
        # EFA isn't reachable on loopback (some kernels), fall back to TCP — but
        # label it explicitly so a TCP latency isn't reported as if it were EFA.
        # nosemgrep: ai.ai-best-practices.hooks-dns-exfiltration.hooks-dns-exfiltration.hooks-dns-exfiltration-generic -- FI_PING_CMD validated to known EFA binary path above; targets loopback 127.0.0.1
        PING_OUT=$($FI_PING_CMD -p efa -I 10 127.0.0.1 2>/dev/null || echo "")
        PROVIDER="efa"
        if [ -z "$PING_OUT" ]; then
            # nosemgrep: ai.ai-best-practices.hooks-dns-exfiltration.hooks-dns-exfiltration.hooks-dns-exfiltration-generic -- FI_PING_CMD validated above; loopback only
            PING_OUT=$($FI_PING_CMD -p tcp -I 10 127.0.0.1 2>/dev/null || echo "")
            PROVIDER="tcp"
        fi
        if [ -n "$PING_OUT" ]; then
            LATENCY=$(echo "$PING_OUT" | grep -oE "[0-9]+\.[0-9]+ us" | tail -1 || echo "")
            LAT_VAL=$(echo "$LATENCY" | grep -oE "[0-9]+" | head -1 || echo 0)
            if [ "$PROVIDER" = "tcp" ]; then
                # TCP loopback latency does NOT reflect EFA path health; an EFA
                # straggler will not be visible here. Surface as INFO, not PASS/WARN.
                echo "[INFO] fi_ping fell back to provider=tcp (EFA loopback unreachable) — latency=${LATENCY:-?}; this does NOT measure EFA path health"
                echo "       For EFA latency, run fi_ping/fi_pingpong between two real nodes (not loopback) — see references/performance-testing.md"
            elif [ -n "$LATENCY" ]; then
                if [ "$LAT_VAL" -gt 20 ] 2>/dev/null; then
                    echo "[WARN] fi_ping latency (provider=efa): $LATENCY (>20us — EFA port may be degraded; normal is 1-5us)"
                    echo "       Impact: straggler AllReduce, training much slower than expected"
                    echo "       Action: drain this node and replace via HyperPod API"
                else
                    echo "[PASS] fi_ping latency (provider=efa): $LATENCY"
                fi
            else
                echo "[INFO] fi_ping (provider=efa) ran but no latency value extracted"
                echo "$PING_OUT" | tail -3
            fi
        else
            echo "[INFO] fi_ping self-test skipped (no EFA/TCP provider reachable)"
        fi
    fi
else
    echo "[INFO] fi_ping not found (install EFA tools for latency testing)"
fi
echo ""

echo "=== END NODE DIAGNOSTICS ==="
NODE_SCRIPT
)

# Strategy for 100s of nodes:
#   1. Resolve all Running compute nodes via HyperPod API (paginated)
#   2. Sample --sample-nodes (default 3) for SSM hardware checks
#   3. Each SSM call has a 60s timeout
#   4. Results show per-node summary; failures are highlighted
#   5. This check does NOT increment ISSUES_FOUND (hardware checks are advisory)
#      unless a critical hardware fault is detected (XID errors, EFA fail on GPU instance)
check_node_hardware_via_ssm() {
    header "Check 8: Node Hardware Checks (via SSM — runs ON cluster nodes)"

    info "Resolving cluster nodes for SSM..."
    if ! resolve_cluster_nodes_for_ssm; then
        info "Could not resolve cluster nodes via HyperPod API"
        info "  (DescribeCluster needs sagemaker:DescribeCluster on this cluster)"
        info "  To check a specific node: --node <INSTANCE_ID>"
        return
    fi

    if [[ ${#SSM_NODES[@]} -eq 0 ]]; then
        info "No Running compute nodes found in cluster"
        return
    fi

    local total_nodes
    total_nodes="${#SSM_NODES[@]}"
    info "Sampling $total_nodes node(s) for hardware checks (use --sample-nodes N for more)"
    info "Cluster ID: $SSM_CLUSTER_ID"

    local node_pass=0 node_warn=0 node_fail=0

    for entry in "${SSM_NODES[@]}"; do
        local instance_id group_name
        instance_id=$(echo "$entry" | awk '{print $1}')
        group_name=$(echo "$entry" | awk '{print $2}')
        local target="sagemaker-cluster:${SSM_CLUSTER_ID}_${group_name}-${instance_id}"

        section "Node: $instance_id ($group_name)"
        info "  SSM target: $target"
        info "  Connecting (timeout 60s)..."

        local output
        output=$(_ssm_run "$instance_id" "$group_name" "$SSM_CLUSTER_ID" "$_NODE_DIAG_SCRIPT")

        # Detect SSM transport failures. Letting error text fall through as
        # diagnostic output produces a misleading "0 [PASS]" finding.
        if [[ -z "$output" ]] || echo "$output" | grep -qiE "SessionManagerPlugin|error.*session|not authorized|AccessDenied|Could not connect|^Cannot perform start session|EOF$|ThrottlingException|RequestLimitExceeded|InternalFailure|ServiceUnavailable|TargetNotConnected"; then
            warn "  SSM connection failed for $instance_id → references/operations.md § 3 SSM target format (HyperPod)"
            node_warn=$((node_warn + 1))
            continue
        fi

        echo "$output"

        local passes fails
        passes=$(echo "$output" | { grep -c "\[PASS\]" 2>/dev/null; true; })
        fails=$(echo "$output" | { grep -c "\[FAIL\]" 2>/dev/null; true; })

        # Non-GPU / non-EFA nodes (controllers, logins, CPU families) sampled
        # as a fallback. Flag as SKIP rather than PASS — a PASS on a node
        # without GPU/EFA is meaningless for NCCL.
        local is_non_gpu=false
        if echo "$output" | grep -qE "^\[INFO\].*(CPU-only node|non-EFA instance|no GPU devices visible|nvidia-smi not found)"; then
            if ! echo "$output" | grep -qE "^\[PASS\] EFA provider available|^\[PASS\] GPU row-remap"; then
                is_non_gpu=true
            fi
        fi

        if [[ "$fails" -gt 0 ]]; then
            error "  Node $instance_id: $fails hardware issue(s) detected — see above"
            node_fail=$((node_fail + 1))
            # XID errors or EFA fail on a GPU instance = cluster-level issue
            if echo "$output" | grep -q "\[FAIL\] GPU XID"; then
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                add_issue_detail "XID errors on GPU hardware ($instance_id) → references/operations.md § 8 NCCL-specific remediations (Node reboot / replacement); hyperpod-node-debugger skill" "P0"
            elif echo "$output" | grep -q "\[FAIL\] EFA provider NOT"; then
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                add_issue_detail "EFA provider failure on $instance_id → references/debugging-guide.md § 6 EFA Configuration / § 13 EFA TCP Fallback" "P0"
            fi
        elif $is_non_gpu; then
            info "  Node $instance_id: no GPU/EFA present — skipping (NCCL checks apply only to GPU/EFA compute nodes)"
            node_warn=$((node_warn + 1))
        else
            success "  Node $instance_id: hardware checks passed ($passes [PASS])"
            node_pass=$((node_pass + 1))
        fi
    done

    echo ""
    info "Hardware check summary: $node_pass PASS | $node_warn UNREACHABLE | $node_fail FAIL"
    if [[ "$node_fail" -gt 0 ]]; then
        warn "  $node_fail node(s) have hardware issues — check above for details"
        warn "  For ALL nodes: re-run with --sample-nodes <total> to check every node"
    fi
    if [[ "$node_warn" -gt 0 ]]; then
        warn "  $node_warn node(s) unreachable via SSM — verify SSM agent and IAM permissions"
    fi
}

# CloudWatch covers ALL nodes at once without per-node SSM calls.
# This runs for EKS when K8S_CONNECTED=false (can't use kubectl logs).
check_cloudwatch_nccl_logs() {
    header "Check 6b: NCCL Pattern Analysis via CloudWatch"

    local cluster_arn cluster_id
    cluster_arn=$(aws sagemaker describe-cluster \
        --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --query 'ClusterArn' --output text 2>/dev/null || echo "")
    cluster_id=$(echo "$cluster_arn" | awk -F'/' '{print $NF}')

    if [[ -z "$cluster_id" || "$cluster_id" == "None" ]]; then
        info "Cluster ID unavailable — skipping CloudWatch log analysis"
        return
    fi

    local log_group="/aws/sagemaker/Clusters/${CLUSTER_NAME}/${cluster_id}"
    info "CloudWatch log group: $log_group"

    local lg_exists
    lg_exists=$(aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" --region "$REGION" \
        --query 'logGroups[0].logGroupName' --output text 2>&1) || {
        if echo "$lg_exists" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
            warn "Permission denied: logs:DescribeLogGroups — check IAM policy"
        fi
        lg_exists=""
    }

    if [[ -z "$lg_exists" || "$lg_exists" == "None" ]]; then
        info "CloudWatch log group not found — CloudWatch agent may not be configured"
        info "  Enable the CloudWatch agent in the cluster's lifecycle script (see operations.md § 4)"
        return
    fi

    local start_time=$(( ($(date +%s) - 7200) * 1000 ))
    local patterns=(
        "NCCL WARN" "Watchdog timeout" "Timeout waiting for"
        "fi_getinfo failed" "unhandled system error" "nccl error"
        "Connection refused" "NCCL_OFI_RDMA"
    )

    local found_any=false
    for pattern in "${patterns[@]}"; do
        local matches
        matches=$(aws logs filter-log-events \
            --log-group-name "$log_group" \
            --filter-pattern "\"$pattern\"" \
            --start-time "$start_time" \
            --region "$REGION" \
            --query 'events[*].{t:timestamp,s:logStreamName,m:message}' \
            --output json 2>/dev/null || echo "[]")

        local count
        count=$(echo "$matches" | python3 -c \
            "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

        if [[ "$count" -gt 0 ]]; then
            error "CloudWatch: '$pattern' found $count time(s) in last 2h:"
            echo "$matches" | python3 -c "
import sys,json,datetime
events=json.load(sys.stdin)[:5]
for e in events:
    ts=datetime.datetime.utcfromtimestamp(e['t']//1000).strftime('%H:%M:%S')
    stream=e['s'][:30]
    msg=e['m'][:120].strip()
    print(f'  [{ts}] {stream}: {msg}')
" 2>/dev/null
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "CloudWatch pattern '$pattern' found ${count} time(s) → references/error-patterns-quick-ref.md" "P1"
            found_any=true
        fi
    done

    $found_any || success "No NCCL error patterns in CloudWatch logs (last 2h)"
}

# Slurm: run command on head node via SSM (start-session, not send-command)
run_slurm_cmd_via_ssm() {
    local cmd="$1"

    if ! resolve_cluster_nodes_for_ssm; then
        return 1
    fi

    # Paginate list-cluster-nodes so controller/head nodes in the last page
    # of a large cluster aren't missed.
    local all_nodes
    all_nodes=$(sagemaker_list_paginated list-cluster-nodes ClusterNodeSummaries)

    local head_entry
    head_entry=$(echo "$all_nodes" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    g=n.get('InstanceGroupName','').lower()
    if any(x in g for x in ['controller','head','master']):
        print(n['InstanceId'] + ' ' + n['InstanceGroupName'])
        break
else:
    for n in nodes:
        if n.get('InstanceStatus',{}).get('Status') == 'Running':
            print(n['InstanceId'] + ' ' + n['InstanceGroupName'])
            break
" 2>/dev/null || echo "")

    [[ -z "$head_entry" ]] && return 1

    local iid grp
    iid=$(echo "$head_entry" | awk '{print $1}')
    grp=$(echo "$head_entry" | awk '{print $2}')

    _ssm_run "$iid" "$grp" "$SSM_CLUSTER_ID" "$cmd"
}

check_slurm_nodes() {
    header "Check 2 [Slurm]: Node States"

    local sinfo_output=""
    if command -v sinfo &>/dev/null; then
        sinfo_output=$(sinfo -o "%N %T %30E" --noheader 2>/dev/null || echo "")
    else
        sinfo_output=$(run_slurm_cmd_via_ssm "sinfo -o '%N %T %30E' --noheader" || echo "")
    fi

    # Treat SSM transport errors as retrieval failures, not as healthy state.
    # Without this, "Cannot perform start session: EOF" is non-empty and falls
    # through the empty-check below → grep finds no "down" → misleading [PASS].
    if echo "$sinfo_output" | grep -qiE "^(Cannot perform start session|SessionManagerPlugin is not found)|EOF$|TargetNotConnected|ThrottlingException|RequestLimitExceeded|InternalFailure|ServiceUnavailable|AccessDenied|UnauthorizedOperation|not authorized to perform"; then
        warn "Could not retrieve Slurm node states — SSM transient error after retries"
        info "  Rerun the diagnostic; if persistent, delegate to hyperpod-ssm skill for manual probe."
        return
    fi

    if [[ -z "$sinfo_output" ]]; then
        warn "Could not retrieve Slurm node states"
        return
    fi

    local down drained
    down=$(echo "$sinfo_output" | grep -E "\bdown\b|\bdraining\b" | awk '{print $1}' || echo "")
    drained=$(echo "$sinfo_output" | grep -E "\bdrained\b" | awk '{print $1}' || echo "")

    if [[ -z "$down" && -z "$drained" ]]; then
        success "All Slurm nodes: UP/IDLE/ALLOC — no NCCL-impacting states"
    else
        if [[ -n "$down" ]]; then
            error "DOWN/DRAINING nodes: $down"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "Slurm nodes DOWN/DRAINING: $down → references/operations.md § 7 Slurm — NCCL-specific operations" "P1"
            while IFS= read -r node; do
                [[ -z "$node" ]] && continue
            done <<< "$(echo "$down" | tr ',' '\n')"
        fi
        [[ -n "$drained" ]] && warn "DRAINED nodes (not available): $drained"
    fi

    section "Slurm Job Queue"
    local q=""
    if command -v squeue &>/dev/null; then
        q=$(squeue -o "%i %j %T %R %N" --noheader 2>/dev/null || echo "")
    fi
    if [[ -z "$q" ]]; then
        q=$(run_slurm_cmd_via_ssm "squeue -o '%i %j %T %R %N' --noheader" 2>/dev/null || echo "")
    fi

    # Same SSM-error detection as above — without this, the error string is
    # parsed as a job list and produces false "stuck" rows.
    if echo "$q" | grep -qiE "^(Cannot perform start session|SessionManagerPlugin is not found)|EOF$|TargetNotConnected|ThrottlingException|RequestLimitExceeded|InternalFailure|ServiceUnavailable|AccessDenied|UnauthorizedOperation|not authorized to perform"; then
        warn "Could not retrieve Slurm job queue — SSM transient error after retries"
        q=""
    fi

    if [[ -z "$q" ]]; then
        info "No jobs in queue"
    else
        local stuck
        stuck=$(echo "$q" | grep -E "PENDING|COMPLETING" | head -10 || echo "")
        if [[ -n "$stuck" ]]; then
            warn "Stuck PENDING/COMPLETING jobs:"
            echo "$stuck"
            ISSUES_FOUND=$((ISSUES_FOUND+1))
            add_issue_detail "Stuck PENDING/COMPLETING Slurm jobs → references/operations.md § 7 Slurm — NCCL-specific operations" "P1"
        else
            success "No stuck jobs in queue"
        fi
        info "Queue (top 10):"; echo "$q" | head -10
    fi
}

check_slurm_nccl_logs() {
    header "Check 6 [Slurm]: NCCL Log Pattern Analysis"
    check_cloudwatch_nccl_logs
}

check_slurm_nccl_env() {
    header "Check 7 [Slurm]: NCCL Environment Variable Audit (via SSM)"

    local env_check
    env_check=$(run_slurm_cmd_via_ssm \
        "{ cat /etc/profile.d/nccl.sh /opt/ml/config/nccl.conf /etc/slurm/prolog.d/*.sh 2>/dev/null; env; } \
         | grep -E '^(NCCL_|FI_|MASTER_)' | sort -u | head -30 || echo '(none)'" \
        2>/dev/null || echo "")

    # If SSM returned a transport error, don't interpret it as the controller's
    # env output — that produces false "FI_PROVIDER=efa not set" warnings.
    if echo "$env_check" | grep -qiE "^(Cannot perform start session|SessionManagerPlugin is not found)|EOF$|TargetNotConnected|ThrottlingException|RequestLimitExceeded|InternalFailure|ServiceUnavailable|AccessDenied|UnauthorizedOperation|not authorized to perform"; then
        warn "Could not retrieve NCCL env vars from controller — SSM transient error after retries"
        info "  Rerun the diagnostic; if persistent, delegate to hyperpod-ssm skill."
        return
    fi

    if [[ -n "$env_check" && "$env_check" != "(none)" ]]; then
        info "NCCL/EFA env vars on head node:"
        echo "$env_check" | while IFS= read -r line; do info "  $line"; done

        local warn_count=0
        if echo "$env_check" | grep -q "NCCL_DEBUG=INFO"; then
            warn "NCCL_DEBUG=INFO detected — verbose logging adds runtime overhead. Set NCCL_DEBUG=WARN for production."
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "NCCL_DEBUG=INFO in Slurm env (set NCCL_DEBUG=WARN in production) → references/operations.md § 5 NCCL environment variable reference" "P1"
            warn_count=$((warn_count + 1))
        fi
        if echo "$env_check" | grep -q "NCCL_DEBUG=TRACE"; then
            warn "NCCL_DEBUG=TRACE detected — TRACE prints replayable trace info on every NCCL call (large overhead and verbose logs). Set NCCL_DEBUG=WARN immediately."
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            add_issue_detail "NCCL_DEBUG=TRACE in Slurm env (set NCCL_DEBUG=WARN immediately) → references/operations.md § 5 NCCL environment variable reference" "P0"
            warn_count=$((warn_count + 1))
        fi
        if ! echo "$env_check" | grep -q "FI_PROVIDER=efa"; then
            warn "FI_PROVIDER=efa not set — EFA may not be used for NCCL transport"
            warn_count=$((warn_count + 1))
        fi
        if ! echo "$env_check" | grep -q "NCCL_SOCKET_IFNAME"; then
            warn "NCCL_SOCKET_IFNAME not set — NCCL may pick wrong interface. Recommend: ^lo,docker,efa,veth"
            warn_count=$((warn_count + 1))
        fi
        if [[ "$warn_count" -eq 0 ]]; then
            success "System-level NCCL env vars look correct"
        fi
    else
        info "No NCCL env vars found in system config on head node"
        info "  (Expected — NCCL vars are typically set in job scripts, not system-wide)"
    fi
}

check_slurm_controller_health() {
    # Slurm controller health — retry up to 3× before declaring it down, because
    # SSM cold-start / session-service EOF errors are common on the first call.
    header "Check 0 [Slurm]: Controller Health"
    local ping_result=""
    for _ in 1 2 3; do
        ping_result=$(run_slurm_cmd_via_ssm "scontrol ping 2>/dev/null" || echo "")
        [[ -n "$ping_result" ]] && echo "$ping_result" | grep -qi "is UP\|slurmctld.*UP" && break
        sleep 3
    done
    if echo "$ping_result" | grep -qi "is UP\|slurmctld.*UP"; then
        success "slurmctld is responsive"
    elif echo "$ping_result" | grep -qiE "AccessDenied|UnauthorizedOperation|not authorized to perform"; then
        # IAM denial ≠ Slurm failure. Reporting "slurmctld down" would be wrong
        # and would send the customer down a Slurm-rescue path for an IAM issue.
        warn "Could not check slurmctld — caller lacks ssm:StartSession on this cluster"
        info "  Grant ssm:StartSession on the HyperPod cluster ARN and rerun."
    elif echo "$ping_result" | grep -qiE "Cannot perform start session|SessionManager|EOF$|TargetNotConnected|ConnectTimeout|ServiceError|ThrottlingException|RequestLimitExceeded|InternalFailure|ServiceUnavailable"; then
        # Transport-level SSM errors — not a Slurm failure. Downgrade to WARN.
        warn "Could not reach controller via SSM (transient): $(echo "$ping_result" | head -1)"
        info "  Rerun the diagnostic; if the error persists, delegate to hyperpod-ssm skill."
    elif [[ -n "$ping_result" ]]; then
        error "slurmctld not responding — all Slurm operations blocked"
        local _diag_line
        _diag_line="$(echo "$ping_result" | head -1)"
        info "  Controller response: $_diag_line"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "slurmctld down on controller → references/operations.md § 7 Slurm — NCCL-specific operations" "P0"
    else
        info "Could not reach controller via SSM — slurmctld status unknown"
    fi

    local munge_result
    munge_result=$(run_slurm_cmd_via_ssm "systemctl is-active munge 2>/dev/null || echo munge_inactive" || echo "")
    if echo "$munge_result" | grep -q "^active"; then
        success "munge authentication service active"
    elif echo "$munge_result" | grep -q "munge_inactive"; then
        error "munge service inactive — Slurm auth will fail"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        add_issue_detail "munge service inactive → references/operations.md § 7 Slurm — NCCL-specific operations" "P0"
    fi
}

run_slurm_checks() {
    check_slurm_controller_health
    check_cluster_health
    check_slurm_nodes
    check_cluster_events
    check_security_groups
    check_slurm_nccl_logs
    check_slurm_nccl_env
    check_node_hardware_via_ssm
}

print_summary() {
    header "NCCL Diagnostic Summary"
    echo ""
    echo -e "  Cluster:      ${BOLD}$CLUSTER_NAME${RESET}"
    echo -e "  Region:       ${BOLD}$REGION${RESET}"
    echo -e "  Orchestrator: ${BOLD}${ORCHESTRATOR^^}${RESET}"
    [[ "$ORCHESTRATOR" == "eks" ]] && \
        echo -e "  Namespace:    ${BOLD}${NAMESPACE:-all}${RESET}"
    [[ -n "$JOB_NAME" ]]  && echo -e "  Job:          ${BOLD}$JOB_NAME${RESET}"
    [[ -n "$NODE_ID" ]]   && echo -e "  Node:         ${BOLD}$NODE_ID${RESET}"
    echo -e "  Mode:         ${BOLD}READ-ONLY${RESET} (no changes applied)"
    echo ""
    echo -e "  ┌──────────────────────────────────┐"
    echo -e "  │  Issues Found:  ${RED}${BOLD}$ISSUES_FOUND${RESET}                │"
    echo -e "  └──────────────────────────────────┘"

    if [[ ${#ISSUE_DETAILS[@]} -gt 0 ]]; then
        echo ""
        echo "  Issue Details (prioritized):"
        for priority in P0 P1 P2; do
            local has_items=false
            for detail in "${ISSUE_DETAILS[@]}"; do
                if [[ "$detail" == "${priority}|"* ]]; then
                    if ! $has_items; then
                        case "$priority" in
                            P0) echo -e "    ${RED}${BOLD}[$priority — Fix Immediately]${RESET}" ;;
                            P1) echo -e "    ${YELLOW}${BOLD}[$priority — Fix Soon]${RESET}" ;;
                            P2) echo -e "    ${BOLD}[$priority — Advisory]${RESET}" ;;
                        esac
                        has_items=true
                    fi
                    echo "      → ${detail#*|}"
                fi
            done
        done
    fi
    echo ""

    if [[ "$ISSUES_FOUND" -eq 0 ]]; then
        success "No actionable NCCL issues detected — cluster looks healthy"
        echo ""
        info "If training is still hanging, check:"
        echo "  1. CloudWatch: aws logs filter-log-events --log-group-name /aws/sagemaker/Clusters/$CLUSTER_NAME/..."
        echo "  2. Version check: hyperpod-version-checker skill"
        echo "  3. Full diagnostics: hyperpod-issue-report skill"
    else
        warn "$ISSUES_FOUND issue(s) found — see the Issue Details list above."
        warn "Each issue line includes a reference pointer (→ references/<file>.md § <section>)."
        warn "The hyperpod-nccl skill will read these findings, look up the matching section,"
        warn "and guide you through remediation. This script does not modify cluster state."
    fi
    echo ""
    echo -e "${BOLD}References:${RESET}"
    echo "  Debugging guide:  references/debugging-guide.md"
    echo "  Operations:       references/operations.md"
    echo "  Performance test: references/performance-testing.md"
    echo ""
}

main() {
    header "NCCL Diagnostic — SageMaker HyperPod (read-only)"

    detect_orchestrator

    echo -e "  Cluster:      ${BOLD}$CLUSTER_NAME${RESET}"
    echo -e "  Region:       ${BOLD}$REGION${RESET}"
    echo -e "  Orchestrator: ${BOLD}${ORCHESTRATOR^^}${RESET}"
    [[ "$ORCHESTRATOR" == "eks" ]] && echo -e "  Namespace:    ${BOLD}${NAMESPACE:-all}${RESET}"
    info "READ-ONLY DIAGNOSTIC — no cluster state will be modified."
    info "This script collects signals only. The hyperpod-nccl skill interprets findings"
    info "and looks up remediation in references/*.md."
    echo ""

    check_prerequisites

    if [[ "$ORCHESTRATOR" == "slurm" ]]; then
        info "Running Slurm NCCL diagnostics..."
        run_slurm_checks
    else
        info "Running EKS NCCL diagnostics..."

        check_cluster_health
        check_cluster_events
        check_security_groups

        if $K8S_CONNECTED; then
            check_k8s_nodes
            check_efa_k8s
            check_pod_status
            check_nccl_infra_prereqs
            analyze_nccl_logs
            check_nccl_env_vars
            check_network_policies
        else
            warn "K8s checks skipped (2, 2b, 5, 5b, 6, 7, 9) — kubectl not authenticated"
            # CloudWatch analysis doesn't need kubectl.
            check_cloudwatch_nccl_logs
        fi

        check_node_hardware_via_ssm
    fi

    print_summary
    # Exit 1 only on P0/P1 findings; P2 are informational.
    local _critical=0
    for _issue in "${ISSUE_DETAILS[@]:-}"; do
        [[ -z "$_issue" ]] && continue
        case "${_issue%%|*}" in P0|P1) _critical=$((_critical+1)) ;; esac
    done
    [[ "$_critical" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
