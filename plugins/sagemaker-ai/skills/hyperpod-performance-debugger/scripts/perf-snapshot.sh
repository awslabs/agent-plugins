#!/usr/bin/env bash
# perf-snapshot.sh
#
# Read-only host-side snapshot for the two performance scenarios that
# hyperpod-performance-debugger covers:
#
#   A. Uneven NCCL performance (host-side EFA reachability, NVLink, Fabric
#      Manager, recent dmesg events that contextualize bandwidth variance)
#   B. Poor filesystem performance (FSx CloudWatch utilization for actually
#      mounted filesystems, on-node iowait)
#
#
# Usage:
#   bash perf-snapshot.sh --cluster <NAME|ARN> --region <REGION>
#   bash perf-snapshot.sh --cluster <N> --region <R> --node <INSTANCE_ID>
#   bash perf-snapshot.sh --cluster <N> --region <R> --no-color > report.txt
#
# Required IAM (on the calling principal):
#   sagemaker:DescribeCluster, sagemaker:ListClusterNodes,
#     sagemaker:DescribeClusterNode
#   fsx:DescribeFileSystems
#   cloudwatch:GetMetricStatistics
#   ssm:StartSession, ssm:TerminateSession
#
# Note: HyperPod-managed instances are not reliably addressable via
# ec2:DescribeInstances from the operator role, so this script stays on
# SageMaker HyperPod APIs + IMDS (via SSM) for per-instance metadata.
#
# Prerequisites on the calling machine:
#   aws CLI v2, jq, session-manager-plugin (for the SSM calls),
#   unbuffer (from the `expect` package; works around a session-manager-plugin
#   stdout race — see ssm_run below).

set -uo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TARGET_NODE=""
NO_COLOR="${NO_COLOR:-}"

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
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
if ! command -v unbuffer >/dev/null 2>&1; then
  echo "Warning: 'unbuffer' (from the 'expect' package) not found — SSM calls" >&2
  echo "         can intermittently return empty output. Install with" >&2
  echo "         'sudo yum install expect' / 'sudo apt install expect' / 'brew install expect'." >&2
fi

# ---------------------------------------------------------------------------
# Output helpers (TTY-gated; respect NO_COLOR)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "$NO_COLOR" ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m';  BOLD=$'\033[1m';    NC=$'\033[0m'
else
  GREEN=""; YELLOW=""; CYAN=""; BOLD=""; NC=""
fi

section() { printf "\n${BOLD}${CYAN}== %s ==${NC}\n" "$1"; }
ok()      { printf "  ${GREEN}[OK     ]${NC} %s\n" "$1"; }
concern() { printf "  ${YELLOW}[CONCERN]${NC} %s\n" "$1"; }
info()    { printf "             %s\n" "$1"; }

# Pointers (sibling skill / SKILL.md section to read after a [CONCERN] line)
NEXT=()

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

# Instance type from list-cluster-nodes output (already fetched). No EC2 call.
INSTANCE_TYPE=$(echo "$NODES" | jq -r --arg id "$TGT_ID" \
  '.ClusterNodeSummaries[] | select(.InstanceId==$id) | .InstanceType // empty')
IS_NVL72=0
if [[ "$INSTANCE_TYPE" =~ ^ml\.p6e-gb200|^ml\.p6e-gb300|^p6e-gb200|^p6e-gb300 ]]; then
  IS_NVL72=1
fi

# ---------------------------------------------------------------------------
# SSM helper — injection-safe (commands passed via file-based CLI input).
# Bounded to 60s per call to avoid hangs on unreachable nodes.
# ---------------------------------------------------------------------------
ssm_run() {
  local target="$1"
  local cmd="$2"
  local json_file runner
  json_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$json_file'" RETURN
  jq -n --arg t "$target" --arg c "$cmd" '{
    Target: $t,
    DocumentName: "AWS-StartNonInteractiveCommand",
    Parameters: { command: [ ("bash -c " + ($c | @sh)) ] }
  }' > "$json_file"

  if command -v unbuffer >/dev/null 2>&1; then
    runner=(unbuffer aws)
  else
    runner=(aws)
  fi

  timeout 60 "${runner[@]}" ssm start-session --region "$REGION" \
    --cli-input-json "file://${json_file}" 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;]*m//g' \
          -e '/^Starting session/d' \
          -e '/^Exiting session/d' \
          -e '/^Cannot perform start session: EOF$/d'
}

# ssm_json: run a payload that is expected to print a single JSON document on
# stdout. On parse failure (probe missing, jq absent, command timeout) returns
# the empty object so callers can use jq with safe defaults.
ssm_json() {
  local target="$1" cmd="$2" out
  out=$(ssm_run "$target" "$cmd")
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$out"
  else
    printf '{}'
  fi
}

# ---------------------------------------------------------------------------
# A. Uneven NCCL — placement and EFA reachability data points
# ---------------------------------------------------------------------------
section "A. NCCL topology & EFA reachability"

# AZ placement — use sagemaker:DescribeClusterNode which returns
# Placement.AvailabilityZone. No ec2:DescribeInstances needed.
#
# DescribeClusterNode has no batch form, so this is O(N) API calls. Cap the
# sample to keep runtime bounded; a single outlier AZ is enough to surface
# the concern. Customer can run sagemaker list-cluster-nodes for a full audit.
mapfile -t ALL_IDS < <(echo "$NODES" | jq -r '.ClusterNodeSummaries[].InstanceId // empty')
AZ_SAMPLE_CAP=20
if [[ "${#ALL_IDS[@]}" -eq 0 ]]; then
  info "no instance IDs in cluster node list; skipping placement check"
else
  SAMPLE_N=${#ALL_IDS[@]}
  TRUNCATED=0
  if (( SAMPLE_N > AZ_SAMPLE_CAP )); then
    SAMPLE_N=$AZ_SAMPLE_CAP
    TRUNCATED=1
  fi
  AZS=""
  for ((i = 0; i < SAMPLE_N; i++)); do
    id="${ALL_IDS[$i]}"
    az=$(aws sagemaker describe-cluster-node --cluster-name "$CLUSTER" --region "$REGION" \
      --node-id "$id" --query 'NodeDetails.Placement.AvailabilityZone' --output text 2>/dev/null) || az=""
    [[ -n "$az" && "$az" != "None" ]] && AZS+="${az}"$'\n'
  done
  UNIQ_AZ=$(echo "$AZS" | awk 'NF' | sort -u | wc -l)
  if (( UNIQ_AZ > 1 )); then
    concern "sampled nodes span $UNIQ_AZ AZs — cross-AZ placement is a known cause of uneven NCCL"
    info "→ SKILL.md § A (Uneven NCCL); for re-provisioning, → hyperpod-cluster-debugger § B"
    NEXT+=("A")
  elif (( UNIQ_AZ == 1 )); then
    ok "sampled nodes share a single AZ"
  else
    info "no AZ returned by DescribeClusterNode; skipping placement check"
  fi
  (( TRUNCATED )) && info "sampled first $AZ_SAMPLE_CAP of ${#ALL_IDS[@]} nodes; sagemaker list-cluster-nodes for a full audit"
fi

# EFA + container toolkit stack versions — sample from the target node so the
# customer has a starting point. For cross-node comparison, route to
# hyperpod-version-checker rather than re-implementing it here.
STACK_JSON=$(ssm_json "$SSM_TARGET" '
  pkgver() {
    pkg=$1
    if command -v dpkg >/dev/null 2>&1; then
      v=$(dpkg-query -W -f="\${Version}" "$pkg" 2>/dev/null)
    fi
    if [ -z "${v:-}" ] && command -v rpm >/dev/null 2>&1; then
      v=$(rpm -q --qf "%{VERSION}-%{RELEASE}" "$pkg" 2>/dev/null)
      case "$v" in [0-9]*) ;; *) v="" ;; esac
    fi
    printf "%s" "${v:-}"
  }

  efa_inst=$(grep -iE "^EFA[[:space:]]+(installer[[:space:]]+)?version" \
    /opt/amazon/efa_installed_packages 2>/dev/null \
    | head -1 | sed -E "s/.*[:=][[:space:]]*//")
  efa_mod=$(modinfo efa 2>/dev/null | awk "/^version:/ {print \$2; exit}")
  ofi=$(pkgver aws-ofi-nccl)
  libfabric=$(fi_info -v 2>/dev/null | awk -F": " "/libfabric/{print \$2; exit}")
  driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
  nvct=$(pkgver nvidia-container-toolkit)

  jq -n \
    --arg efa_installer "$efa_inst" \
    --arg efa_kmod      "$efa_mod"  \
    --arg ofi_nccl      "$ofi"      \
    --arg libfabric     "$libfabric" \
    --arg driver        "$driver"   \
    --arg nvct          "$nvct"     \
    "{efa_installer:\$efa_installer, efa_kmod:\$efa_kmod, ofi_nccl:\$ofi_nccl, libfabric:\$libfabric, driver:\$driver, nvct:\$nvct}"
')
# Render to operator output. `// "unknown"` keeps the column non-empty when a
# component is intentionally not on the host.
while IFS=$'\t' read -r k v; do
  info "$TGT_ID host: ${k}=${v}"
done < <(echo "$STACK_JSON" | jq -r '
  def nz(x): if (x // "") == "" then "unknown" else x end;
  . as $s
  | [
      ["EFA",       (nz($s.efa_installer) + " (kmod=" + nz($s.efa_kmod) + ")")],
      ["OFI_NCCL",   nz($s.ofi_nccl)],
      ["LIBFABRIC",  nz($s.libfabric)],
      ["DRIVER",     nz($s.driver)],
      ["NVCT",       nz($s.nvct)]
    ]
  | .[] | @tsv
')
info "values above are host-scope; the workload may use a different EFA/OFI/CUDA stack inside the container — verify via hyperpod-version-checker"
info "for cross-node version comparison, → hyperpod-version-checker"

# EFA fabric reachability — port state and provider visibility. SG-level rules
# are not directly inspectable from this role; route to hyperpod-cluster-debugger
# § A for the cluster-wide EFA SG check.
EFA_JSON=$(ssm_json "$SSM_TARGET" '
  total=0; active=0
  for p in /sys/class/infiniband/*/ports/1/state; do
    [ -e "$p" ] || continue
    total=$((total+1))
    grep -q ACTIVE "$p" 2>/dev/null && active=$((active+1))
  done
  if fi_info -p efa >/dev/null 2>&1; then
    fi_info_ok=true
  else
    fi_info_ok=false
  fi
  jq -n \
    --argjson total       "$total" \
    --argjson active      "$active" \
    --argjson fi_info_ok  "$fi_info_ok" \
    "{ports:{total:\$total, active:\$active}, fi_info_ok:\$fi_info_ok}"
')
EFA_TOTAL=$(echo "$EFA_JSON" | jq -r '.ports.total // 0')
EFA_ACTIVE=$(echo "$EFA_JSON" | jq -r '.ports.active // 0')
EFA_FI_OK=$(echo "$EFA_JSON" | jq -r '.fi_info_ok // false')
if (( EFA_TOTAL == 0 )); then
  concern "no EFA devices visible on $TGT_ID"
  info "→ hyperpod-node-debugger § A (EFA / Security Group)"
  NEXT+=("A")
elif (( EFA_ACTIVE != EFA_TOTAL )); then
  concern "EFA port state on $TGT_ID: ${EFA_ACTIVE}/${EFA_TOTAL} ACTIVE"
  info "→ hyperpod-node-debugger § A (EFA / Security Group)"
  NEXT+=("A")
else
  ok "EFA port state on $TGT_ID: ${EFA_ACTIVE}/${EFA_TOTAL} ACTIVE"
fi
if [[ "$EFA_FI_OK" != "true" ]] && (( EFA_TOTAL > 0 )); then
  concern "libfabric does not see the EFA provider on $TGT_ID — NCCL would fall back to TCP"
  info "→ hyperpod-nccl § 13 (EFA TCP fallback) / hyperpod-cluster-debugger § A"
  NEXT+=("A")
fi
info "EFA self-referencing security-group rule is a cluster-wide check — → hyperpod-cluster-debugger § A"

# GPU/NIC topology snapshot — raw informational print so the operator can see
# how PCIe / NVLink edges connect GPUs to NICs without re-running on the node.
TOPO=$(ssm_run "$SSM_TARGET" "nvidia-smi topo -m 2>/dev/null")
if [[ -n "$TOPO" ]]; then
  info "nvidia-smi topo -m on $TGT_ID:"
  echo "$TOPO" | sed 's/^/             /'
fi

# ---------------------------------------------------------------------------
# B. Filesystem — CloudWatch utilization + on-node iowait
# ---------------------------------------------------------------------------
section "B. Filesystem saturation"

# Scope FSx query to filesystems actually mounted on the target node.
FSIDS_JSON=$(ssm_json "$SSM_TARGET" '
  ids=$(mount | awk "/lustre|zfs/ {print \$1}" | grep -oE "fs-[a-f0-9]+" | sort -u)
  if [ -z "$ids" ]; then
    echo "[]"
  else
    printf "%s\n" "$ids" | jq -R . | jq -s .
  fi
')
mapfile -t FSID_ARRAY < <(echo "$FSIDS_JSON" | jq -r '.[]?')

if [[ ${#FSID_ARRAY[@]} -eq 0 ]]; then
  info "no FSx filesystems mounted on $TGT_ID"
else
  FSX_DESC=$(aws fsx describe-file-systems --region "$REGION" \
    --file-system-ids "${FSID_ARRAY[@]}" --output json 2>/dev/null || echo '{}')
  FSCOUNT=$(echo "$FSX_DESC" | jq '.FileSystems | length // 0')

  if (( FSCOUNT == 0 )); then
    info "FSx filesystems ${FSID_ARRAY[*]} are mounted but describe-file-systems returned nothing (cross-account?)"
  else
    while IFS=$'\t' read -r fsid fstype; do
      [[ -z "$fsid" ]] && continue
      val=$(aws cloudwatch get-metric-statistics --region "$REGION" \
        --namespace AWS/FSx --metric-name DataReadBytes \
        --dimensions "Name=FileSystemId,Value=${fsid}" \
        --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
        --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 60 --statistics Maximum --output json 2>/dev/null \
        | jq -r '[.Datapoints[].Maximum] | max // 0')
      info "${fstype} ${fsid}: max 1h DataReadBytes = ${val} bytes/min"

      if [[ "$fstype" == "OPENZFS" ]]; then
        util=$(aws cloudwatch get-metric-statistics --region "$REGION" \
          --namespace AWS/FSx --metric-name FileServerDiskIopsUtilization \
          --dimensions "Name=FileSystemId,Value=${fsid}" \
          --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
          --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
          --period 60 --statistics Maximum --output json 2>/dev/null \
          | jq -r '[.Datapoints[].Maximum] | max // 0')
        info "         max 1h FileServerDiskIopsUtilization = ${util}%"
        util_int=${util%.*}
        if [[ "$util_int" =~ ^[0-9]+$ ]] && (( util_int >= 80 )); then
          concern "OpenZFS $fsid disk IOPS utilization sustained ≥ 80% (peak ${util}%)"
          info "→ SKILL.md § B (Poor Filesystem Performance)"
          NEXT+=("B")
        fi
      fi
    done < <(echo "$FSX_DESC" | jq -r '.FileSystems[]? | [.FileSystemId, .FileSystemType] | @tsv')
    info "review the FSx dashboards for sustained near-provisioned-limit usage (script reports peaks only)"
  fi
fi

# On-node mount-point capacity — surface usage on FSx / NVMe / SageMaker paths.
# Includes lfs df per Lustre mount so the operator can see OST/MDT fill.
DF_JSON=$(ssm_json "$SSM_TARGET" '
  mounts="[]"
  for p in /fsx /opt/dlami/nvme /opt/sagemaker; do
    [ -e "$p" ] || continue
    line=$(df -h "$p" 2>/dev/null | awk "NR==2") || continue
    [ -z "$line" ] && continue
    fs=$(echo "$line"  | awk "{print \$1}")
    sz=$(echo "$line"  | awk "{print \$2}")
    used=$(echo "$line" | awk "{print \$3}")
    avail=$(echo "$line" | awk "{print \$4}")
    pct=$(echo "$line" | awk "{print \$5}")
    entry=$(jq -n \
      --arg path  "$p"    --arg fs    "$fs"   --arg size "$sz" \
      --arg used  "$used" --arg avail "$avail" --arg pct "$pct" \
      "{path:\$path, fs:\$fs, size:\$size, used:\$used, avail:\$avail, pct:\$pct}")
    mounts=$(jq --argjson e "$entry" ". + [\$e]" <<< "$mounts")
  done

  lustre="[]"
  while IFS= read -r mnt; do
    [ -z "$mnt" ] && continue
    out=$(lfs df -h "$mnt" 2>/dev/null) || continue
    [ -z "$out" ] && continue
    rows=$(printf "%s\n" "$out" | jq -R . | jq -s .)
    entry=$(jq -n --arg mnt "$mnt" --argjson rows "$rows" \
      "{mount:\$mnt, rows:\$rows}")
    lustre=$(jq --argjson e "$entry" ". + [\$e]" <<< "$lustre")
  done < <(mount | awk "/lustre/ {print \$3}")

  jq -n \
    --argjson mounts "$mounts" \
    --argjson lustre "$lustre" \
    "{mounts:\$mounts, lustre:\$lustre}"
')
while IFS=$'\t' read -r path fs size used avail pct; do
  [[ -z "$path" ]] && continue
  info "df ${path}: ${used} used / ${size} (${pct}, ${avail} free) on ${fs}"
done < <(echo "$DF_JSON" | jq -r '.mounts[]? | [.path, .fs, .size, .used, .avail, .pct] | @tsv')

LAST_LFS_MNT=""
while IFS=$'\t' read -r mnt row; do
  [[ -z "$mnt" ]] && continue
  if [[ "$mnt" != "$LAST_LFS_MNT" ]]; then
    info "lfs df -h ${mnt}:"
    LAST_LFS_MNT="$mnt"
  fi
  info "             ${row}"
done < <(echo "$DF_JSON" | jq -r '.lustre[]? | . as $e | $e.rows[] | [$e.mount, .] | @tsv')

# On-node iowait via iostat
IOWAIT=$(ssm_run "$SSM_TARGET" "iostat -c 1 2 2>/dev/null | awk 'END{print \$4}'")
IOWAIT=$(echo "$IOWAIT" | tr -d '\r \n')
if [[ -n "$IOWAIT" ]]; then
  IOWAIT_INT=${IOWAIT%.*}
  if [[ "$IOWAIT_INT" =~ ^[0-9]+$ ]]; then
    info "$TGT_ID iowait: ${IOWAIT}%"
    if (( IOWAIT_INT > 20 )); then
      concern "iowait on $TGT_ID is ${IOWAIT}%"
      info "→ SKILL.md § B (Poor Filesystem Performance)"
      NEXT+=("B")
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Adjacent host data points — out of scope for this skill but commonly relevant.
# Reported as data points only; remediation is owned by sibling skills.
# ---------------------------------------------------------------------------
section "Adjacent data points (out of scope — see sibling skills)"

# GPU thermal / ECC / NVLink / Xid — surface as concerns; routing goes to
# hyperpod-node-debugger § G. Do NOT classify cause from a single reading.
GPU_OUT=$(ssm_run "$SSM_TARGET" "nvidia-smi --query-gpu=index,temperature.gpu,clocks.current.sm,clocks.max.sm,pcie.link.width.current,pcie.link.width.max,ecc.errors.uncorrected.volatile.total,ecc.errors.uncorrected.aggregate.total --format=csv,noheader,nounits 2>&1 | head -16")

if echo "$GPU_OUT" | grep -qiE 'command not found|no devices|NVIDIA-SMI has failed'; then
  info "no NVIDIA GPU detected on $TGT_ID"
else
  HOT=0; UNCORR_VOL=0; UNCORR_AGG=0; GPUS=0; PCIE_DEGRADED=0; SM_THROTTLED=0
  while IFS=',' read -r idx temp sm_cur sm_max pcie_cur pcie_max unc_vol unc_agg; do
    idx=$(echo "$idx" | tr -d ' '); [[ -z "$idx" ]] && continue
    temp=$(echo "$temp" | tr -d ' ')
    sm_cur=$(echo "$sm_cur" | tr -d ' ')
    sm_max=$(echo "$sm_max" | tr -d ' ')
    pcie_cur=$(echo "$pcie_cur" | tr -d ' ')
    pcie_max=$(echo "$pcie_max" | tr -d ' ')
    unc_vol=$(echo "$unc_vol" | tr -d ' ')
    unc_agg=$(echo "$unc_agg" | tr -d ' ')

    GPUS=$((GPUS+1))
    [[ "$temp" =~ ^[0-9]+$ && "$temp" -ge 88 ]] && HOT=$((HOT+1))
    [[ "$unc_vol" =~ ^[0-9]+$ && "$unc_vol" -gt 0 ]] && UNCORR_VOL=$((UNCORR_VOL+1))
    [[ "$unc_agg" =~ ^[0-9]+$ && "$unc_agg" -gt 0 ]] && UNCORR_AGG=$((UNCORR_AGG+1))
    if [[ "$pcie_cur" =~ ^[0-9]+$ && "$pcie_max" =~ ^[0-9]+$ ]] && (( pcie_cur < pcie_max )); then
      PCIE_DEGRADED=$((PCIE_DEGRADED+1))
    fi
    # Workload-time clock check would need correlation; skip silently when idle.
    if [[ "$sm_cur" =~ ^[0-9]+$ && "$sm_max" =~ ^[0-9]+$ ]] && (( sm_max > 0 )) \
       && (( sm_cur * 100 < sm_max * 50 )) && [[ "$temp" =~ ^[0-9]+$ ]] && (( temp >= 80 )); then
      SM_THROTTLED=$((SM_THROTTLED+1))
    fi
  done <<< "$GPU_OUT"

  info "$GPUS GPUs visible on $TGT_ID"
  if (( HOT > 0 )); then
    concern "$HOT GPU(s) at or above the H100 SXM5 software-throttle point (≥ 88°C)"
    info "data point only — correlate with workload before drawing a conclusion"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  fi
  if (( PCIE_DEGRADED > 0 )); then
    concern "$PCIE_DEGRADED GPU(s) report PCIe link width below max"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  fi
  if (( SM_THROTTLED > 0 )); then
    concern "$SM_THROTTLED GPU(s) running SM clock < 50% of max while ≥ 80°C — possible thermal throttling"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  fi
  if (( UNCORR_VOL > 0 )); then
    concern "$UNCORR_VOL GPU(s) report uncorrectable ECC (volatile)"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  fi
  if (( UNCORR_AGG > 0 )); then
    concern "$UNCORR_AGG GPU(s) report uncorrectable ECC (aggregate / lifetime)"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  fi
  if (( HOT == 0 && UNCORR_VOL == 0 && UNCORR_AGG == 0 && PCIE_DEGRADED == 0 && SM_THROTTLED == 0 )); then
    ok "no thermal / ECC / PCIe / clock concerns visible on $TGT_ID"
  fi
fi

# CPU frequency governor — uneven across nodes is a known straggler cause.
GOV=$(ssm_run "$SSM_TARGET" "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null")
GOV=$(echo "$GOV" | tr -d '\r\n ')
if [[ -n "$GOV" ]]; then
  info "CPU governor on $TGT_ID: ${GOV}"
  if [[ "$GOV" != "performance" ]]; then
    concern "CPU governor is '${GOV}' (not 'performance') on $TGT_ID — known cause of uneven NCCL"
    info "→ SKILL.md § A (Uneven NCCL); compare across nodes with hyperpod-version-checker"
    NEXT+=("A")
  fi
fi

# Recent Xid lines — surface, do NOT classify
XID=$(ssm_run "$SSM_TARGET" "dmesg -T 2>/dev/null | grep -i 'Xid' | tail -5")
if [[ -n "$XID" ]]; then
  concern "recent Xid line(s) in dmesg on $TGT_ID — surface only; → hyperpod-node-debugger § G for the catalog"
  echo "$XID" | sed 's/^/             /'
  NEXT+=("G")
else
  ok "no Xid lines in recent dmesg"
fi

# NVLink lane status / errors — concern, don't classify
NVLINK=$(ssm_run "$SSM_TARGET" '
  nvidia-smi nvlink -s 2>/dev/null
  echo "----"
  nvidia-smi nvlink -e 2>/dev/null
')
if echo "$NVLINK" | grep -qiE 'has no supported GPU|command not found|no devices'; then
  info "NVLink: not supported on this instance (skipped)"
else
  INACTIVE=$(echo "$NVLINK" | awk '/^GPU/{gpu=$0; next} /[Ii]nactive/ {print gpu":"$0}' | wc -l)
  ERR_LINES=$(echo "$NVLINK" | awk 'BEGIN{errs=0} /^GPU/{gpu=$0; next} /[Ee]rror/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $i>0) errs++} END{print errs}')
  if (( INACTIVE > 0 )); then
    concern "$INACTIVE NVLink lane(s) report inactive on $TGT_ID"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  elif (( ERR_LINES > 0 )); then
    concern "NVLink error counters non-zero on some lanes on $TGT_ID"
    info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
    NEXT+=("G")
  else
    ok "NVLink lanes active, no error counters"
  fi
fi

# Fabric Manager — required on NVL72 UltraServers
if (( IS_NVL72 )); then
  FM=$(ssm_run "$SSM_TARGET" 'systemctl is-active nvidia-fabricmanager 2>/dev/null || echo missing')
  FM=$(echo "$FM" | tr -d '\r\n ')
  case "$FM" in
    active)
      ok "Fabric Manager active (required for $INSTANCE_TYPE NVLink fabric)"
      ;;
    *)
      concern "Fabric Manager state=${FM:-missing} on $INSTANCE_TYPE"
      info "→ hyperpod-node-debugger § G (GPU / Accelerator)"
      NEXT+=("G")
      ;;
  esac
fi

# /dev/shm and root-volume usage — surface, don't act
HOST_INFO_JSON=$(ssm_json "$SSM_TARGET" '
  shm_present=false
  shm_size_gib=0
  shm_used_gib=0
  if [ -d /dev/shm ]; then
    shm_present=true
    read -r size_k used_k _ < <(df -k /dev/shm 2>/dev/null | awk "NR==2{print \$2, \$3}")
    shm_size_gib=$(awk -v k="${size_k:-0}" "BEGIN{printf \"%.1f\", k/1024/1024}")
    shm_used_gib=$(awk -v k="${used_k:-0}" "BEGIN{printf \"%.1f\", k/1024/1024}")
  fi
  root_pct=$(df / 2>/dev/null | awk "NR==2 {gsub(\"%\",\"\",\$5); print \$5+0}")
  root_avail_k=$(df -k / 2>/dev/null | awk "NR==2 {print \$4}")
  root_avail_gib=$(awk -v k="${root_avail_k:-0}" "BEGIN{printf \"%.1f\", k/1024/1024}")

  jq -n \
    --argjson shm_present   "$shm_present" \
    --argjson shm_size_gib  "$shm_size_gib" \
    --argjson shm_used_gib  "$shm_used_gib" \
    --argjson root_pct      "${root_pct:-0}" \
    --argjson root_avail_gib "$root_avail_gib" \
    "{shm:{present:\$shm_present, size_gib:\$shm_size_gib, used_gib:\$shm_used_gib}, root:{used_pct:\$root_pct, avail_gib:\$root_avail_gib}}"
')
SHM_PRESENT=$(echo "$HOST_INFO_JSON" | jq -r '.shm.present // false')
SHM_SIZE=$(echo "$HOST_INFO_JSON" | jq -r '(.shm.size_gib // 0) | . * 10 | floor / 10 | tostring | if test("\\.") then . else . + ".0" end')
SHM_USED=$(echo "$HOST_INFO_JSON" | jq -r '(.shm.used_gib // 0) | . * 10 | floor / 10 | tostring | if test("\\.") then . else . + ".0" end')
ROOT_PCT=$(echo "$HOST_INFO_JSON" | jq -r '.root.used_pct // 0')
ROOT_AVAIL=$(echo "$HOST_INFO_JSON" | jq -r '(.root.avail_gib // 0) | . * 10 | floor / 10 | tostring | if test("\\.") then . else . + ".0" end')

if [[ "$SHM_PRESENT" != "true" ]]; then
  concern "/dev/shm not present on host"
  info "→ hyperpod-node-debugger § I (Resource Exhaustion) / hyperpod-nccl § 17"
  NEXT+=("I")
else
  info "/dev/shm (host): ${SHM_USED} GiB used of ${SHM_SIZE} GiB"
  SHM_INT=${SHM_SIZE%.*}
  if [[ "$SHM_INT" =~ ^[0-9]+$ ]] && (( SHM_INT < 16 )); then
    concern "/dev/shm (host) is ${SHM_SIZE} GiB"
    info "container view may differ (EKS emptyDir, enroot ipc-unshare); → hyperpod-node-debugger § I"
    NEXT+=("I")
  fi
fi

if [[ "$ROOT_PCT" =~ ^[0-9]+$ ]]; then
  info "/ used: ${ROOT_PCT}% (${ROOT_AVAIL} GiB free of fixed 100 GiB root)"
  if (( ROOT_PCT >= 90 )); then
    concern "/ is ${ROOT_PCT}% full on $TGT_ID"
    info "→ hyperpod-node-debugger § I.2 (Root Volume Exhausted)"
    NEXT+=("I")
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Summary"
if [[ ${#NEXT[@]} -eq 0 ]]; then
  ok "no concerns surfaced for the in-scope perf categories"
  info "if the customer still reports slowness, route to the matching sibling skill (hyperpod-nccl, hyperpod-node-debugger, hyperpod-version-checker)"
else
  mapfile -t UNIQ < <(printf '%s\n' "${NEXT[@]}" | sort -u)
  for h in "${UNIQ[@]}"; do
    case "$h" in
      A) printf "  ${BOLD}see SKILL.md § A (Uneven NCCL Performance)${NC}\n" ;;
      B) printf "  ${BOLD}see SKILL.md § B (Poor Filesystem Performance)${NC}\n" ;;
      G) printf "  ${BOLD}see hyperpod-node-debugger § G (GPU / Accelerator) — adjacent data point${NC}\n" ;;
      I) printf "  ${BOLD}see hyperpod-node-debugger § I (Resource Exhaustion) — adjacent data point${NC}\n" ;;
    esac
  done
fi

printf "\n"
info "sampled one node: $TGT_ID (${INSTANCE_TYPE:-unknown-type}) in group $TGT_GROUP"
info "re-run with --node <INSTANCE_ID> to target a specific node"
info "for continuous coverage of GPU / EFA / multi-node NCCL health, enable HyperPod NodeRecovery (HMA) and OnStartDeepHealthChecks"
