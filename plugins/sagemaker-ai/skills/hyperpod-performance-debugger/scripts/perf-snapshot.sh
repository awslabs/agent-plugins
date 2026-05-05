#!/usr/bin/env bash
# perf-snapshot.sh
#
# One-shot performance classifier for SageMaker HyperPod. Runs the minimal
# diagnostic pass for all three categories (uneven NCCL topology, filesystem
# saturation, GPU health) and prints which section of the parent SKILL.md to
# jump to.
#
# Read-only. Never drains, cordons, replaces, or restarts anything. Never
# prints remediation commands. Only invokes stress tests (dcgmi, gpu_burn) if
# you explicitly run them separately after draining a node.
#
# Usage:
#   bash perf-snapshot.sh --cluster <NAME|ARN> --region <REGION>
#   bash perf-snapshot.sh --cluster <N> --region <R> --node <INSTANCE_ID>
#   bash perf-snapshot.sh --cluster <N> --region <R> --no-color > report.txt
#
# Required IAM (on the calling principal):
#   sagemaker:DescribeCluster, sagemaker:ListClusterNodes
#   ec2:DescribeInstances
#   fsx:DescribeFileSystems
#   cloudwatch:GetMetricStatistics
#   ssm:StartSession, ssm:TerminateSession
#
# Prerequisites on the calling machine:
#   aws CLI v2, jq, session-manager-plugin (for the SSM calls)

set -uo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TARGET_NODE=""
NO_COLOR="${NO_COLOR:-}"

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)   CLUSTER="${2:-}";     shift 2 ;;
    --region)    REGION="${2:-}";      shift 2 ;;
    --node)      TARGET_NODE="${2:-}"; shift 2 ;;
    --no-color)  NO_COLOR=1;           shift 1 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Input validation — these values flow into AWS API calls and SSM payloads.
# ---------------------------------------------------------------------------
[[ -z "$CLUSTER" ]] && { echo "Error: --cluster required" >&2; exit 2; }

# Cluster name or ARN (see AWS SageMaker BatchReplaceClusterNodesRequest pattern)
if ! [[ "$CLUSTER" =~ ^(arn:aws[a-z-]*:sagemaker:[a-z0-9-]*:[0-9]{12}:cluster/[a-z0-9]{12})$|^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}$ ]]; then
  echo "Error: invalid cluster name or ARN: $CLUSTER" >&2
  exit 2
fi

# Region
if ! [[ "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]{1,2}$ ]]; then
  echo "Error: invalid region: $REGION" >&2
  exit 2
fi

# Optional node — EC2 instance ID
if [[ -n "$TARGET_NODE" ]] && ! [[ "$TARGET_NODE" =~ ^i-[a-f0-9]{8,17}$ ]]; then
  echo "Error: invalid --node (expected i-<hex>): $TARGET_NODE" >&2
  exit 2
fi

# Dependency check
for cmd in aws jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required" >&2; exit 2; }
done
if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "Warning: session-manager-plugin not found; on-node probes will fail" >&2
fi

# ---------------------------------------------------------------------------
# Output helpers (TTY-gated; respect NO_COLOR)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "$NO_COLOR" ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BOLD=$'\033[1m';    NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; NC=""
fi

section() { printf "\n${BOLD}${CYAN}== %s ==${NC}\n" "$1"; }
ok()      { printf "  ${GREEN}[OK  ]${NC} %s\n" "$1"; }
warn()    { printf "  ${YELLOW}[WARN]${NC} %s\n" "$1"; }
bad()     { printf "  ${RED}[BAD ]${NC} %s\n" "$1"; }
info()    { printf "         %s\n" "$1"; }

HINTS=()

# ---------------------------------------------------------------------------
# Cluster + node list
# ---------------------------------------------------------------------------
DESC=$(aws sagemaker describe-cluster --cluster-name "$CLUSTER" --region "$REGION" --output json 2>&1) \
  || { echo "Error: describe-cluster failed: $DESC" >&2; exit 3; }
CLUSTER_ID=$(echo "$DESC" | jq -r '.ClusterArn' | awk -F/ '{print $NF}')

NODES=$(aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER" --region "$REGION" --output json 2>&1) \
  || { echo "Error: list-cluster-nodes failed: $NODES" >&2; exit 3; }

# Pick target node
if [[ -n "$TARGET_NODE" ]]; then
  TGT_ID="$TARGET_NODE"
else
  TGT_ID=$(echo "$NODES" | jq -r '
    [.ClusterNodeSummaries[] | select(.InstanceGroupName|test("controller|head";"i")|not)][0].InstanceId
    // .ClusterNodeSummaries[0].InstanceId // empty')
fi
[[ -z "$TGT_ID" ]] && { echo "Error: no nodes found in cluster" >&2; exit 3; }

TGT_GROUP=$(echo "$NODES" | jq -r --arg id "$TGT_ID" \
  '.ClusterNodeSummaries[] | select(.InstanceId==$id) | .InstanceGroupName // empty')
[[ -z "$TGT_GROUP" ]] && { echo "Error: node $TGT_ID not found in cluster" >&2; exit 3; }

SSM_TARGET="sagemaker-cluster:${CLUSTER_ID}_${TGT_GROUP}-${TGT_ID}"

# ---------------------------------------------------------------------------
# SSM helper — injection-safe (commands passed via file-based CLI input).
# Bounded to 60s per call to avoid hangs on unreachable nodes.
# ---------------------------------------------------------------------------
ssm_run() {
  local target="$1"
  local cmd="$2"
  local json_file
  json_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$json_file'" RETURN

  # Use --cli-input-json with a file to avoid shell-escaping the command:
  jq -n --arg t "$target" --arg c "$cmd" '{
    Target: $t,
    DocumentName: "AWS-StartNonInteractiveCommand",
    Parameters: { command: [ $c ] }
  }' > "$json_file"

  timeout 60 aws ssm start-session --region "$REGION" \
    --cli-input-json "file://${json_file}" 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;]*m//g' -e '/Starting session/d' -e '/Exiting session/d'
}

# ---------------------------------------------------------------------------
# Category A: placement / topology
# ---------------------------------------------------------------------------
section "A. NCCL topology & placement"

# Batch describe-instances (up to 100 IDs per call) instead of one-by-one.
# Collect all instance IDs from the cluster node list, then chunk into batches.
mapfile -t ALL_IDS < <(echo "$NODES" | jq -r '.ClusterNodeSummaries[].InstanceId // empty')
if [[ "${#ALL_IDS[@]}" -eq 0 ]]; then
  warn "no instance IDs in cluster node list; skipping placement check"
else
  PLACEMENTS=""
  for ((i = 0; i < ${#ALL_IDS[@]}; i += 100)); do
    batch=( "${ALL_IDS[@]:i:100}" )
    chunk=$(aws ec2 describe-instances --instance-ids "${batch[@]}" --region "$REGION" \
      --query 'Reservations[*].Instances[*].[Placement.AvailabilityZone,Placement.GroupName]' \
      --output text 2>/dev/null) || chunk=""
    PLACEMENTS+="${chunk}"$'\n'
  done
  UNIQ_AZ=$(echo "$PLACEMENTS" | awk 'NF{print $1}' | sort -u | wc -l)
  UNIQ_PG=$(echo "$PLACEMENTS" | awk 'NF{print $2}' | sort -u | wc -l)

  if (( UNIQ_AZ > 1 )); then
    bad "nodes span $UNIQ_AZ AZs - cross-AZ traffic will degrade NCCL"
    HINTS+=("A")
  else
    ok "all nodes in a single AZ"
  fi
  if (( UNIQ_PG > 1 )); then
    bad "nodes span $UNIQ_PG placement groups"
    HINTS+=("A")
  else
    ok "all nodes in a single placement group (or none configured)"
  fi
fi

# EFA version consistency — sample from target node; user should compare across
# nodes with hyperpod-version-checker.
EFA_VER=$(ssm_run "$SSM_TARGET" "cat /opt/amazon/efa/share/VERSION 2>/dev/null || echo unknown" | tr -d '\n\r ')
info "EFA version on $TGT_ID: ${EFA_VER:-unknown} (compare across nodes via hyperpod-version-checker)"

# ---------------------------------------------------------------------------
# Category B: filesystem
# ---------------------------------------------------------------------------
section "B. Filesystem saturation"

# Scope FSx query to filesystems actually mounted on the target node, not every
# FSx in the region. This avoids enumerating unrelated filesystems on shared accounts.
FSIDS_ON_NODE=$(ssm_run "$SSM_TARGET" "mount | awk '/lustre|zfs/ {print \$1}' | grep -oE 'fs-[a-f0-9]+' | sort -u")
FSIDS_ON_NODE=$(echo "$FSIDS_ON_NODE" | tr -d '\r' | tr '\n' ' ' | awk '{$1=$1};1')

if [[ -z "$FSIDS_ON_NODE" ]]; then
  info "no FSx filesystems mounted on $TGT_ID"
else
  # Split into array for safe expansion (no word-splitting on unquoted var)
  read -ra FSID_ARRAY <<< "$FSIDS_ON_NODE"
  FSX_DESC=$(aws fsx describe-file-systems --region "$REGION" \
    --file-system-ids "${FSID_ARRAY[@]}" --output json 2>/dev/null || echo '{}')
  FSINFO=$(echo "$FSX_DESC" | jq -r '.FileSystems[]? | "\(.FileSystemId)|\(.FileSystemType)"')

  if [[ -z "$FSINFO" ]]; then
    warn "FSx filesystems $FSIDS_ON_NODE are mounted but describe-file-systems returned nothing (cross-account?)"
  else
    while IFS='|' read -r fsid fstype; do
      [[ -z "$fsid" ]] && continue
      # Both LUSTRE and OPENZFS expose DataReadBytes (Bytes, Sum) in AWS/FSx.
      val=$(aws cloudwatch get-metric-statistics --region "$REGION" \
        --namespace AWS/FSx --metric-name DataReadBytes \
        --dimensions "Name=FileSystemId,Value=${fsid}" \
        --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
        --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 60 --statistics Maximum --output json 2>/dev/null \
        | jq -r '[.Datapoints[].Maximum] | max // 0')
      info "${fstype} ${fsid}: max 1h DataReadBytes = ${val} bytes/min"

      # For OPENZFS, also report the utilization percent, which is the authoritative saturation signal.
      if [[ "$fstype" == "OPENZFS" ]]; then
        util=$(aws cloudwatch get-metric-statistics --region "$REGION" \
          --namespace AWS/FSx --metric-name FileServerDiskIopsUtilization \
          --dimensions "Name=FileSystemId,Value=${fsid}" \
          --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
          --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
          --period 60 --statistics Maximum --output json 2>/dev/null \
          | jq -r '[.Datapoints[].Maximum] | max // 0')
        info "         max 1h FileServerDiskIopsUtilization = ${util}%"
        # Integer compare only; avoid bc dependency.
        util_int=${util%.*}
        if [[ "$util_int" =~ ^[0-9]+$ ]] && (( util_int >= 80 )); then
          bad "OpenZFS $fsid disk IOPS utilization sustained high (${util}%) - bottleneck likely"
          HINTS+=("B")
        fi
      fi
    done <<< "$FSINFO"
    info "review the FSx dashboards for sustained near-provisioned-limit usage (script prints peaks only)"
  fi
fi

# On-node iowait (via iostat instead of top — avoids locale-sensitive parsing)
IOWAIT=$(ssm_run "$SSM_TARGET" "iostat -c 1 2 2>/dev/null | awk 'END{print \$4}'")
IOWAIT=$(echo "$IOWAIT" | tr -d '\r \n')
if [[ -n "$IOWAIT" ]]; then
  # Strip decimal; use integer comparison (no bc dependency).
  IOWAIT_INT=${IOWAIT%.*}
  if [[ "$IOWAIT_INT" =~ ^[0-9]+$ ]]; then
    info "$TGT_ID iowait: ${IOWAIT}%"
    if (( IOWAIT_INT > 20 )); then
      warn "high iowait on $TGT_ID - filesystem likely a bottleneck"
      HINTS+=("B")
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Category C: GPU health
# ---------------------------------------------------------------------------
section "C. GPU health (node $TGT_ID)"

GPU_OUT=$(ssm_run "$SSM_TARGET" "nvidia-smi --query-gpu=index,temperature.gpu,ecc.errors.uncorrected.volatile.total,ecc.errors.uncorrected.aggregate.total,ecc.errors.corrected.volatile.total --format=csv,noheader,nounits 2>&1 | head -16")

if echo "$GPU_OUT" | grep -qiE 'command not found|no devices|NVIDIA-SMI has failed'; then
  warn "no NVIDIA GPU on $TGT_ID (Trainium? check 'neuron-ls' via hyperpod-node-debugger § G)"
else
  HOT=0; UNCORR_VOL=0; UNCORR_AGG=0; CORR_TOTAL=0; GPUS=0
  while IFS=',' read -r idx temp unc_vol unc_agg corr_vol; do
    idx=$(echo "$idx" | tr -d ' '); [[ -z "$idx" ]] && continue
    temp=$(echo "$temp" | tr -d ' ')
    unc_vol=$(echo "$unc_vol" | tr -d ' ')
    unc_agg=$(echo "$unc_agg" | tr -d ' ')
    corr_vol=$(echo "$corr_vol" | tr -d ' ')

    GPUS=$((GPUS+1))
    [[ "$temp"     =~ ^[0-9]+$ && "$temp"     -ge 85 ]] && HOT=$((HOT+1))
    [[ "$unc_vol"  =~ ^[0-9]+$ && "$unc_vol"  -gt 0  ]] && UNCORR_VOL=$((UNCORR_VOL+1))
    [[ "$unc_agg"  =~ ^[0-9]+$ && "$unc_agg"  -gt 0  ]] && UNCORR_AGG=$((UNCORR_AGG+1))
    [[ "$corr_vol" =~ ^[0-9]+$ ]] && CORR_TOTAL=$((CORR_TOTAL + corr_vol))
  done <<< "$GPU_OUT"

  info "$GPUS GPUs visible on $TGT_ID"

  (( HOT > 0 )) && { bad "$HOT GPU(s) thermal-throttling (>= 85C)"; HINTS+=("C"); }
  (( UNCORR_VOL > 0 )) && { bad "$UNCORR_VOL GPU(s) with UNCORRECTABLE ECC (volatile) - drain & replace"; HINTS+=("C"); }
  (( UNCORR_AGG > 0 )) && { bad "$UNCORR_AGG GPU(s) with UNCORRECTABLE ECC (aggregate/lifetime) - drain & replace"; HINTS+=("C"); }

  # Corrected-ECC threshold: compare against an approximate per-day rate derived
  # from uptime, not a raw cumulative value. Without uptime we skip this check
  # rather than false-positive on long-running nodes.
  UPTIME_DAYS=$(ssm_run "$SSM_TARGET" "awk '{printf \"%d\", \$1/86400}' /proc/uptime 2>/dev/null || echo 0")
  UPTIME_DAYS=$(echo "$UPTIME_DAYS" | tr -d '\r\n ')
  if [[ "$UPTIME_DAYS" =~ ^[1-9][0-9]*$ ]] && [[ "$UPTIME_DAYS" -gt 0 ]]; then
    PER_DAY=$(( CORR_TOTAL / UPTIME_DAYS ))
    info "corrected ECC: $CORR_TOTAL since driver load over ${UPTIME_DAYS}d = ~${PER_DAY}/day"
    (( PER_DAY > 1000 )) && { warn "corrected ECC rate > 1000/day - pre-failure, schedule replacement"; HINTS+=("C"); }
  else
    info "corrected ECC (volatile) total: $CORR_TOTAL (no uptime; compare to aggregate next cycle)"
  fi

  if (( HOT == 0 && UNCORR_VOL == 0 && UNCORR_AGG == 0 )); then
    [[ "${UPTIME_DAYS:-0}" =~ ^[0-9]+$ ]] && [[ "${PER_DAY:-0}" -le 1000 ]] && \
      ok "no thermal or ECC issues on $TGT_ID"
  fi
fi

# Recent Xid errors (dmesg is readable unprivileged on HyperPod DLAMIs
# because kernel.dmesg_restrict=0; no sudo needed).
XID=$(ssm_run "$SSM_TARGET" "dmesg -T 2>/dev/null | grep -i 'Xid' | tail -5")
if [[ -n "$XID" ]]; then
  warn "recent Xid in dmesg on $TGT_ID:"
  echo "$XID" | sed 's/^/         /'
  HINTS+=("C")
else
  ok "no Xid errors in recent dmesg"
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
section "Verdict"
if [[ ${#HINTS[@]} -eq 0 ]]; then
  ok "no obvious issues detected in any category"
  info "if the user still reports slowness, delegate to hyperpod-mfu-debugger for full triage"
else
  # Dedupe
  mapfile -t UNIQ < <(printf '%s\n' "${HINTS[@]}" | sort -u)
  for h in "${UNIQ[@]}"; do
    case "$h" in
      A) printf "  ${BOLD}-> Go to Section A: Uneven NCCL Performance (SKILL.md)${NC}\n" ;;
      B) printf "  ${BOLD}-> Go to Section B: Poor Filesystem Performance (SKILL.md)${NC}\n" ;;
      C) printf "  ${BOLD}-> Go to Section C: Suspected GPU Failure (SKILL.md)${NC}\n" ;;
    esac
  done
fi

printf "\n"
info "sampled one node: $TGT_ID in group $TGT_GROUP"
info "re-run with --node <INSTANCE_ID> to target a specific node"
