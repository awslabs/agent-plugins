#!/usr/bin/env bash
# slurm-diagnose.sh
#
# Read-only diagnostic for Slurm node-management issues on Amazon SageMaker HyperPod
# Slurm clusters. Covers the scenarios documented in the HyperPod troubleshooting guide:
#
#   A. Node DOWN / not responding
#   B. Node DOWN with reason "Node unexpectedly rebooted"
#   C. Controller state — slurmctld desync, plus the two folded triggers:
#      C (slurmdbd): accounting daemon connectivity
#      C (config):   pending slurm.conf reconfiguration
#   D. Auto-recovery reason-string mismatches (Action:Reboot / Action:Replace)
#   E. HyperPod --auto-resume support and recent missed-resume detection
#
# Security model:
#   - All CLI inputs are validated against strict regexes at parse time.
#   - All AWS-derived values (instance IDs, group names, node names) are validated before
#     they reach any shell context — invalid values cause an immediate exit.
#   - Remote SSM payloads are base64-encoded literals; server-derived values are
#     prepended to the remote script as `export VAR='<jq @sh-quoted VALUE>'` lines so
#     they are never string-interpolated into shell commands.
#   - Local printf calls use `%s` with the data as a separate argument; format-string
#     attacks via server values are not possible.
#
# The script never mutates cluster state.
#
# Usage:
#   bash slurm-diagnose.sh --cluster <NAME-or-ARN> --region <REGION>
#   bash slurm-diagnose.sh --cluster <N> --region <R> --node <SLURM_NODE>
#   bash slurm-diagnose.sh --cluster <N> --region <R> --controller-group <NAME>
#
# Optional flags:
#   --node <SLURM_NODE>       Scope inspection to a single Slurm node.
#   --controller-group <N>    Override controller-group discovery (for self-managed
#                             Slurm clusters where SlurmConfig is not set).
#   --no-color                Plain output (no ANSI colors).

set -euo pipefail

CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TARGET_NODE=""
CONTROLLER_GROUP_OVERRIDE=""
USE_COLOR=true

# --- Input-validation helpers -------------------------------------------------
# Each validator prints the value if valid, exits non-zero if not. All callsites
# capture into a local variable; failure aborts the script via `set -e`.

# AWS region: lowercase letters, digits, dashes only.
validate_region() {
  local v="${1-}"
  [[ "$v" =~ ^[a-z]{2,3}-[a-z]+-[0-9]+$ ]] || { echo "Error: invalid region: $v" >&2; exit 2; }
  printf '%s' "$v"
}

# HyperPod cluster name OR ARN. Names are 1-63 chars of [a-zA-Z0-9_-]; ARNs match the
# documented SageMaker cluster ARN shape.
validate_cluster() {
  local v="${1-}"
  if [[ "$v" =~ ^arn:aws[a-zA-Z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:cluster/[a-zA-Z0-9-]+$ ]]; then
    printf '%s' "$v"
  elif [[ "$v" =~ ^[a-zA-Z0-9_-]{1,63}$ ]]; then
    printf '%s' "$v"
  else
    echo "Error: invalid cluster name/ARN: $v" >&2
    exit 2
  fi
}

# Slurm node names on HyperPod follow the `ip-x-x-x-x` form, but admins may rename.
# Allow [a-zA-Z0-9._-]+ with length 1..253; reject anything that could escape a shell.
validate_node_name() {
  local v="${1-}"
  [[ "$v" =~ ^[a-zA-Z0-9._-]{1,253}$ ]] || { echo "Error: invalid node name: $v" >&2; exit 2; }
  printf '%s' "$v"
}

# EC2 instance IDs: i- followed by 8 or 17 hex characters. Documented and stable.
validate_instance_id() {
  local v="${1-}"
  [[ "$v" =~ ^i-[a-f0-9]{8}([a-f0-9]{9})?$ ]] || { echo "Error: invalid instance ID: $v" >&2; exit 2; }
  printf '%s' "$v"
}

# Cluster ID (from ARN): lowercase alphanumeric, currently 12 chars (e.g.
# qrmv6xhralg4). Allow 4..32 to be future-tolerant.
validate_cluster_id() {
  local v="${1-}"
  [[ "$v" =~ ^[a-z0-9]{4,32}$ ]] || { echo "Error: invalid cluster ID: $v" >&2; exit 2; }
  printf '%s' "$v"
}

# Instance group name: SageMaker allows 1..63 chars [a-zA-Z0-9_-] per the
# CreateCluster API.
validate_group_name() {
  local v="${1-}"
  [[ "$v" =~ ^[a-zA-Z0-9_-]{1,63}$ ]] || { echo "Error: invalid instance group name: $v" >&2; exit 2; }
  printf '%s' "$v"
}

# --- Argument parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      [[ $# -lt 2 ]] && { echo "Error: --cluster requires a value" >&2; exit 2; }
      CLUSTER=$(validate_cluster "$2"); shift 2 ;;
    --region)
      [[ $# -lt 2 ]] && { echo "Error: --region requires a value" >&2; exit 2; }
      REGION=$(validate_region "$2"); shift 2 ;;
    --node)
      [[ $# -lt 2 ]] && { echo "Error: --node requires a value" >&2; exit 2; }
      TARGET_NODE=$(validate_node_name "$2"); shift 2 ;;
    --controller-group)
      [[ $# -lt 2 ]] && { echo "Error: --controller-group requires a value" >&2; exit 2; }
      CONTROLLER_GROUP_OVERRIDE=$(validate_group_name "$2"); shift 2 ;;
    --no-color) USE_COLOR=false;  shift ;;
    -h|--help)
      # Print every leading-comment line at the top of this file (lines 2..N until the
      # first non-comment line). Robust against future header edits.
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    --*) echo "Error: unknown flag: $1" >&2; exit 2 ;;
    *)   echo "Error: unexpected positional argument: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$CLUSTER" ]] && { echo "Error: --cluster is required" >&2; exit 2; }
REGION=$(validate_region "$REGION")  # validate even when sourced from env default

# --- Prerequisite checks ------------------------------------------------------
command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI is required (v2 recommended)." >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "Error: jq is required. Install with your package manager." >&2; exit 1; }

# `unbuffer` (from the `expect` package) attaches a PTY to aws ssm start-session, which
# avoids a known race where session-manager-plugin closes stdout before flushing and the
# caller sees "Cannot perform start session: EOF" with empty output. Without it, every
# SSM command silently returns empty, causing every downstream check to misreport.
command -v unbuffer >/dev/null 2>&1 || {
  echo "Error: unbuffer (from the 'expect' package) is required." >&2
  echo "       Install: sudo yum install expect | sudo apt install expect | brew install expect" >&2
  exit 1
}

# --- Output formatting --------------------------------------------------------
if "$USE_COLOR"; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

# All status helpers use %s with the message as a separate arg — never embed message
# text into the format string. Strip ANSI escape sequences from incoming server data
# so a malicious or buggy upstream cannot rewrite the operator's terminal.
_sanitize() {
  # Drop ANSI CSI sequences and bell, but leave printable UTF-8 alone.
  sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x07//g' -e 's/\r$//' <<< "${1-}"
}
section() { printf '\n%s%s=== %s ===%s\n' "$BOLD" "$CYAN" "$(_sanitize "$1")" "$NC"; }
ok()    { printf '  %s[PASS]%s %s\n' "$GREEN"  "$NC" "$(_sanitize "$1")"; }
warn()  { printf '  %s[WARN]%s %s\n' "$YELLOW" "$NC" "$(_sanitize "$1")"; }
bad()   { printf '  %s[FAIL]%s %s\n' "$RED"    "$NC" "$(_sanitize "$1")"; }
info()  { printf '         %s\n' "$(_sanitize "$1")"; }
hint()  { printf '  %s[NEXT]%s %s\n' "$CYAN"   "$NC" "$(_sanitize "$1")"; }

ISSUES=()
NEXT_STEPS=()

# --- Verify cluster + orchestrator --------------------------------------------
section "1. Cluster identity"
DESC=$(aws sagemaker describe-cluster --cluster-name "$CLUSTER" --region "$REGION" \
  --output json 2>&1) || { bad "cannot describe cluster: $DESC"; exit 1; }

ORCH=$(jq -r '.Orchestrator // {} | keys[0] // "Slurm"' <<< "$DESC")
if [[ "$ORCH" == "Eks" ]]; then
  bad "cluster uses EKS orchestrator - this skill is for Slurm only"
  info "use hyperpod-node-debugger or hyperpod-nccl instead"
  exit 1
fi

# Managed Slurm vs self-managed Slurm:
#   - Managed: DescribeCluster.Orchestrator.Slurm is present AND the cluster was created
#     with the SlurmConfig API parameter — InstanceGroups[].SlurmConfig.NodeType identifies
#     controllers, login nodes, workers. AWS docs treat this as the authoritative source.
#   - Self-managed: anything else. The customer brought their own Slurm setup via the
#     lifecycle scripts and InstanceGroups[].SlurmConfig is empty. The controller-group
#     name lives in /opt/ml/config/provisioning_parameters.json on every node, or the
#     customer can pass --controller-group <NAME>.
HAS_SLURM_CONFIG=$(jq -r '
  any(.InstanceGroups[]?; (.SlurmConfig // {}) != {})
' <<< "$DESC")
CLUSTER_NAME=$(jq -r '.ClusterName // "unknown"' <<< "$DESC")
CLUSTER_STATUS=$(jq -r '.ClusterStatus // "unknown"' <<< "$DESC")
if [[ "$HAS_SLURM_CONFIG" == "true" ]]; then
  ok "Managed Slurm cluster: $CLUSTER_NAME  status=$CLUSTER_STATUS"
else
  ok "Self-managed Slurm cluster: $CLUSTER_NAME  status=$CLUSTER_STATUS"
fi

# Cluster ID from ARN. Validate before it gets embedded into SSM target strings.
CLUSTER_ID=$(jq -r '.ClusterArn // "" | split("/") | last' <<< "$DESC")
[[ -n "$CLUSTER_ID" ]] || { bad "cannot extract cluster ID from ARN"; exit 1; }
CLUSTER_ID=$(validate_cluster_id "$CLUSTER_ID")

# --- SSM remote-execution helper ----------------------------------------------
#
# `ssm_run` runs a command on a HyperPod node via SSM (read-only).
#
# Design notes:
#   1. The remote script is base64-encoded locally and decoded remotely. The agent's
#      command parameter is a fixed `sh -c "echo <BASE64> | base64 -d | bash"`; the
#      base64 string contains only [A-Za-z0-9+/=] and is safe inside double quotes.
#      Nothing from the script's caller appears unescaped in the SSM-agent's argv.
#   2. Server-derived values that need to be visible to the remote script are passed
#      as named environment variables (`VAR=VALUE` trailing args). Each value is run
#      through `jq @sh` (single-quoted shell-safe encoding with `'\''` escapes) and
#      prepended to the remote script as `export VAR='<safely-quoted>'; ...`. The remote
#      shell reads them as `$NODE`, `$NODELIST`, etc. — values never reach a remote
#      shell-eval context as raw interpolated text.
#   3. `unbuffer` is required to defeat the SSM "Cannot perform start session: EOF"
#      race; the prerequisite check above guarantees it's present.
#   4. Returns the underlying aws-cli exit code so callers can distinguish transport
#      failures from successful empty output.
#
# Usage:
#   ssm_run TARGET REMOTE_SCRIPT [VAR=VALUE ...]
ssm_run() {
  local target="$1"; shift
  local script="$1"; shift
  local export_block="" raw_kv key val safe_val
  for raw_kv in "$@"; do
    [[ "$raw_kv" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || {
      echo "ssm_run: invalid VAR=VALUE: $raw_kv" >&2
      return 2
    }
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # jq's @sh produces single-quoted shell-safe text with embedded `'\''` escapes.
    safe_val=$(jq -nr --arg v "$val" '$v | @sh')
    export_block+="export ${key}=${safe_val}; "
  done
  local full_script="${export_block}${script}"
  local b64
  if base64 --help 2>&1 | grep -q '\-w'; then
    b64=$(printf '%s' "$full_script" | base64 -w0)
  else
    b64=$(printf '%s' "$full_script" | base64 -b0)
  fi
  local wrapper="sh -c \"echo $b64 | base64 -d | bash\""
  local params
  params=$(jq -nc --arg c "$wrapper" '{command: [$c]}')
  local out rc=0
  out=$(unbuffer aws ssm start-session --region "$REGION" --target "$target" \
        --document-name AWS-StartNonInteractiveCommand \
        --parameters "$params" 2>&1) || rc=$?
  # NOTE: do NOT strip 'Cannot perform start session' here — that line is the
  # SSM transport-failure signal that ssm_transport_failed() detects. Only filter
  # benign session chrome ('Starting session' / 'Exiting session') and ANSI escapes.
  printf '%s' "$out" \
    | sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
          -e '/^Starting session/d' \
          -e '/^Exiting session/d'
  return "$rc"
}

# Returns 0 if the SSM raw output indicates a transport-layer failure (no command
# output, session refused, EOF before flush) — distinct from "command ran and returned
# nothing." Used to bail out early rather than misreport every downstream check.
ssm_transport_failed() {
  local raw="${1-}"
  grep -qiE 'Cannot perform start session|TargetNotConnected|InvalidTarget|AccessDeniedException|UnauthorizedOperation' <<< "$raw"
}

# --- Find controller node -----------------------------------------------------
NODES_JSON=$(aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER" --region "$REGION" \
  --output json 2>&1) || { bad "list-cluster-nodes failed: $NODES_JSON"; exit 1; }

# Discovery priority:
#   1. --controller-group <NAME>          (operator override — always wins)
#   2. InstanceGroups[].SlurmConfig.NodeType == "Controller"   (managed-Slurm authoritative)
#   3. /opt/ml/config/provisioning_parameters.json on a probe node   (self-managed fallback)
#   4. Refuse to guess — print available groups and exit.
# We never guess based on instance-group naming — that's a lifecycle-script convention,
# not a guarantee, and getting it wrong sends every command to a non-controller.
CONTROLLER_GROUP=""
CONTROLLER_DISCOVERY_METHOD=""

# (1) Operator override — always wins.
if [[ -n "$CONTROLLER_GROUP_OVERRIDE" ]]; then
  CONTROLLER_GROUP="$CONTROLLER_GROUP_OVERRIDE"
  CONTROLLER_DISCOVERY_METHOD="--controller-group flag"
fi

# (2) Managed-Slurm authoritative source.
if [[ -z "$CONTROLLER_GROUP" && "$HAS_SLURM_CONFIG" == "true" ]]; then
  CONTROLLER_GROUP=$(jq -r '
    .InstanceGroups[]?
    | select((.SlurmConfig.NodeType // "") == "Controller")
    | .InstanceGroupName' <<< "$DESC" | head -1)
  if [[ -n "$CONTROLLER_GROUP" ]]; then
    CONTROLLER_DISCOVERY_METHOD="DescribeCluster.SlurmConfig"
  fi
fi

# (3) Self-managed: read provisioning_parameters.json from any node.
# The lifecycle-script convention is that this file is dropped at the same path on every
# node, so we pick any node arbitrarily, SSM in, and read the controller_group field.
if [[ -z "$CONTROLLER_GROUP" ]]; then
  PROBE_ID=$(jq -r '.ClusterNodeSummaries[0].InstanceId // ""' <<< "$NODES_JSON")
  PROBE_GROUP=$(jq -r '.ClusterNodeSummaries[0].InstanceGroupName // ""' <<< "$NODES_JSON")
  if [[ -n "$PROBE_ID" && -n "$PROBE_GROUP" ]]; then
    PROBE_ID_V=$(validate_instance_id "$PROBE_ID")
    PROBE_GROUP_V=$(validate_group_name "$PROBE_GROUP")
    PROBE_TARGET="sagemaker-cluster:${CLUSTER_ID}_${PROBE_GROUP_V}-${PROBE_ID_V}"
    # Field name varies between lifecycle-script generations — try both.
    PROV_GROUP=$(ssm_run "$PROBE_TARGET" \
      'jq -r ".controller_group // .ControllerGroup // empty" /opt/ml/config/provisioning_parameters.json 2>/dev/null' \
      2>/dev/null | tr -d '\r\n' || true)
    if [[ -n "$PROV_GROUP" ]]; then
      MATCHED=$(jq -r --arg g "$PROV_GROUP" \
        '[.ClusterNodeSummaries[]? | select(.InstanceGroupName == $g)] | length' <<< "$NODES_JSON")
      if [[ "$MATCHED" -gt 0 ]]; then
        CONTROLLER_GROUP="$PROV_GROUP"
        CONTROLLER_DISCOVERY_METHOD="provisioning_parameters.json on $PROBE_ID_V"
      fi
    fi
  fi
fi

# (4) Out of options — refuse to guess. Tell the operator how to unblock.
if [[ -z "$CONTROLLER_GROUP" ]]; then
  bad "cannot identify the Slurm controller instance group"
  if [[ "$HAS_SLURM_CONFIG" == "true" ]]; then
    info "no InstanceGroup has SlurmConfig.NodeType=Controller in DescribeCluster output"
    info "this is unexpected for a managed-Slurm cluster — verify the cluster was"
    info "created with the SlurmConfig parameter, or pass --controller-group <NAME>."
  else
    info "self-managed Slurm cluster — provisioning_parameters.json was not readable"
    info "from a probe node, and no --controller-group flag was provided."
    info ""
    info "Resolve by either:"
    info "  1. inspecting the head node manually:"
    info "       aws ssm start-session --target $PROBE_TARGET --region $REGION"
    info "       cat /opt/ml/config/provisioning_parameters.json | jq ."
    info "  2. re-running with the controller group's name:"
    info "       --controller-group <INSTANCE_GROUP_NAME>"
    info ""
    info "Available instance groups in this cluster:"
    jq -r '.ClusterNodeSummaries[] | "  - " + .InstanceGroupName + "  (" + .InstanceId + ")"' \
      <<< "$NODES_JSON" | sort -u
  fi
  exit 1
fi
CONTROLLER_GROUP=$(validate_group_name "$CONTROLLER_GROUP")

# Pick the first node from the controller group.
CONTROLLER_ID=$(jq -r --arg g "$CONTROLLER_GROUP" \
  '.ClusterNodeSummaries[]? | select(.InstanceGroupName == $g) | .InstanceId' <<< "$NODES_JSON" | head -1)
[[ -n "$CONTROLLER_ID" ]] || { bad "controller group $CONTROLLER_GROUP has no nodes"; exit 1; }
CONTROLLER_ID=$(validate_instance_id "$CONTROLLER_ID")

ok "controller node: $CONTROLLER_ID (group=$CONTROLLER_GROUP, source=$CONTROLLER_DISCOVERY_METHOD)"

SSM_HEAD="sagemaker-cluster:${CLUSTER_ID}_${CONTROLLER_GROUP}-${CONTROLLER_ID}"

# --- Collect Slurm state from head node ---------------------------------------
section "2. Slurm cluster state (from head node)"
SSM_PROBE=$(ssm_run "$SSM_HEAD" 'echo SSM_OK' || true)
if ! grep -q '^SSM_OK$' <<< "$SSM_PROBE"; then
  bad "cannot reach head node via SSM — every downstream check would be unreliable"
  if ssm_transport_failed "$SSM_PROBE"; then
    info "  transport error detected (TargetNotConnected, AccessDenied, or EOF race)"
  fi
  info "  reproduce manually with the same target and region:"
  info "    aws ssm start-session --target $SSM_HEAD --region $REGION"
  info "  if that fails, route to the hyperpod-ssm skill before retrying."
  exit 1
fi
ok "SSM transport to head node working"

SINFO_OUT=$(ssm_run "$SSM_HEAD" 'sinfo -h -o "%N|%T|%E" 2>&1 | head -200' || true)
if [[ $(printf '%s\n' "$SINFO_OUT" | wc -l) -ge 200 ]]; then
  warn "sinfo output reached the 200-line cap — node-state results may be truncated on this large cluster"
fi
if grep -qi 'command not found' <<< "$SINFO_OUT"; then
  bad "sinfo not installed on head node — Slurm lifecycle script may not have run"
  info "verify on the node:  systemctl status slurmctld; ls /opt/slurm*/etc /etc/slurm 2>/dev/null"
  exit 1
fi
if [[ -z "$SINFO_OUT" ]]; then
  warn "sinfo returned no rows — empty cluster, or controller not yet responding"
fi

# Parse sinfo lines. Node names from sinfo are server-controlled; validate before they
# can be embedded into any later command. Values that fail validation are dropped, not
# trusted; we report the count of skipped entries so the operator notices.
DOWN_NODES=()
REBOOT_NODES=()
FAIL_NODES=()
BAD_REASON_NODES=()
SKIPPED_INVALID=0
while IFS='|' read -r node state reason; do
  [[ -z "$node" ]] && continue
  if ! [[ "$node" =~ ^[a-zA-Z0-9._-]{1,253}$ ]]; then
    SKIPPED_INVALID=$((SKIPPED_INVALID+1))
    continue
  fi
  # Reasons can contain spaces and punctuation; allow them but strip ANSI/control chars.
  reason="$(_sanitize "$reason")"
  if grep -qi 'fail' <<< "$state"; then
    if [[ "$reason" =~ ^Action:(Reboot|Replace)$ ]]; then
      FAIL_NODES+=("$node|$reason")
    elif grep -qiE 'action[ :_-]*re(boot|place)|reboot|replace' <<< "$reason"; then
      BAD_REASON_NODES+=("$node|$reason")
    fi
  fi
  if grep -qiE 'down|drain' <<< "$state"; then
    if grep -qi 'unexpectedly rebooted' <<< "$reason"; then
      REBOOT_NODES+=("$node")
    else
      DOWN_NODES+=("$node|$reason")
    fi
  fi
done <<< "$SINFO_OUT"
[[ "$SKIPPED_INVALID" -gt 0 ]] && warn "$SKIPPED_INVALID sinfo row(s) had invalid node names and were ignored"

if [[ ${#DOWN_NODES[@]} -eq 0 && ${#REBOOT_NODES[@]} -eq 0 && ${#FAIL_NODES[@]} -eq 0 && ${#BAD_REASON_NODES[@]} -eq 0 ]]; then
  ok "all nodes in healthy Slurm states"
else
  [[ ${#DOWN_NODES[@]}       -gt 0 ]] && bad   "${#DOWN_NODES[@]} node(s) DOWN/DRAIN (Section A)"
  [[ ${#REBOOT_NODES[@]}     -gt 0 ]] && bad   "${#REBOOT_NODES[@]} node(s) with 'unexpectedly rebooted' (Section B)"
  [[ ${#FAIL_NODES[@]}       -gt 0 ]] && warn  "${#FAIL_NODES[@]} node(s) in fail state with valid Action:* reason (HyperPod recovery in progress)"
  [[ ${#BAD_REASON_NODES[@]} -gt 0 ]] && bad   "${#BAD_REASON_NODES[@]} node(s) in fail state with non-matching reason (Section D)"
fi

# --- Section D: Action:* reason-string validation -----------------------------
if [[ ${#BAD_REASON_NODES[@]} -gt 0 ]]; then
  section "D. Reason-string mismatch — HyperPod auto-recovery will NOT trigger"
  for entry in "${BAD_REASON_NODES[@]}"; do
    n="${entry%%|*}"; r="${entry#*|}"
    bad "$n: reason='$r'"
  done
  info "the reason field must match exactly: Action:Reboot  or  Action:Replace"
  info "(case-sensitive, no spaces, no trailing punctuation)"
  hint "for re-issue procedure, see:"
  info "  https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-replace-faulty-instance.html"
  info "  references/slurm-details.md#action-reason-string-validation"
  ISSUES+=("bad-action-reason")
  NEXT_STEPS+=("see AWS replace-faulty-instance docs (link above)")
fi

# --- Detect in-progress HyperPod replacements (informational) -----------------
if [[ ${#FAIL_NODES[@]} -gt 0 ]]; then
  section "  HyperPod recovery in progress (do not interfere)"
  for entry in "${FAIL_NODES[@]}"; do
    n="${entry%%|*}"; r="${entry#*|}"
    info "$n ($r)"
  done
  info "AWS docs: do NOT change node state or restart slurmctld until this completes."
  info "If a replacement seems stuck > 30 min, see:"
  info "  https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-replace-faulty-instance.html"
fi

# --- Check controller health --------------------------------------------------
section "3. slurmctld health"
PING_OUT=$(ssm_run "$SSM_HEAD" 'scontrol ping 2>&1' || true)
PING_FIRST_LINE=$(head -1 <<< "$PING_OUT" | tr -d '\r')
if grep -qi 'UP' <<< "$PING_OUT"; then
  ok "slurmctld responding: $(tr '\n' ' ' <<< "$PING_OUT")"
elif [[ -z "$PING_OUT" ]] || ssm_transport_failed "$PING_OUT"; then
  warn "could not get a response from scontrol ping — cannot determine controller health"
  info "this is most likely an SSM transport problem, not a hung controller"
  info "do NOT restart slurmctld based on this finding alone"
elif grep -qi 'DOWN' <<< "$PING_OUT"; then
  bad "slurmctld reports DOWN: $PING_FIRST_LINE"
  ISSUES+=("controller-hung")
  NEXT_STEPS+=("controller restart — see references/slurm-details.md#-c-controller-state--diagnostic-context")
else
  bad "slurmctld responded with an unrecognized status: $PING_FIRST_LINE"
  ISSUES+=("controller-hung")
  NEXT_STEPS+=("inspect logs first; controller restart only if logs confirm a hang")
fi

# --- Section C-1: slurmdbd connectivity (controller-state restart trigger) ---
section "C (slurmdbd): accounting daemon connectivity"
DBD_OUT=$(ssm_run "$SSM_HEAD" 'sacctmgr -i show stats 2>&1 | head -20' || true)
if grep -qiE 'unable to contact|connection refused|cannot connect|no slurmdbd' <<< "$DBD_OUT"; then
  bad "slurmctld cannot reach slurmdbd"
  info "$(head -3 <<< "$DBD_OUT")"
  hint "diagnostic and recovery procedure:"
  info "  https://slurm.schedmd.com/accounting.html"
  info "  references/slurm-details.md#slurmdbd-connectivity"
  ISSUES+=("slurmdbd-disconnected")
  NEXT_STEPS+=("restore slurmdbd connectivity (see AWS / Slurm docs linked above)")
elif grep -qiE 'rollup|rpc' <<< "$DBD_OUT"; then
  ok "slurmdbd reachable"
else
  warn "could not determine slurmdbd state from sacctmgr output"
  info "if accounting is configured, run on the head node: sacctmgr show stats"
fi

# --- Section C-2: pending slurm.conf reconfiguration (controller-state restart trigger) ---
# HyperPod's slurm.conf lives at /opt/slurm-<version>/etc/slurm.conf rather than the
# upstream /etc/slurm/slurm.conf, so the remote script asks scontrol where the live
# config is. The output is a `<conf-mtime>|<ctld-start>|<conf-path>` line that we
# match strictly with a regex before parsing.
section "C (config): slurm.conf freshness"
read -r -d '' F_REMOTE <<'REMOTE_F' || true
set -e
# nosemgrep: bash.lang.correctness.unquoted-expansion.unquoted-variable-expansion-in-command
_CONF="$(scontrol show config 2>/dev/null | awk -F= '/^SLURM_CONF/ {gsub(/ /,"",$2); print $2; exit}')"
CONF_MTIME=0
if [ -n "$_CONF" ] && [ -r "$_CONF" ]; then
  CONF_MTIME=$(stat -c %Y "$_CONF" 2>/dev/null || echo 0)
fi
CTLD_TS=$(systemctl show slurmctld -p ActiveEnterTimestamp --value 2>/dev/null || true)
CTLD_START=0
if [ -n "$CTLD_TS" ]; then
  CTLD_START=$(date -d "$CTLD_TS" +%s 2>/dev/null || echo 0)
fi
printf 'F_RESULT|%s|%s|%s\n' "${CONF_MTIME}" "${CTLD_START}" "${_CONF}"
REMOTE_F
F_LINE=$(ssm_run "$SSM_HEAD" "$F_REMOTE" 2>/dev/null | grep -E '^F_RESULT\|[0-9]+\|[0-9]+\|' | head -1 || true)
if [[ "$F_LINE" =~ ^F_RESULT\|([0-9]+)\|([0-9]+)\|(.*)$ ]]; then
  CONF_MTIME="${BASH_REMATCH[1]}"
  CTLD_START="${BASH_REMATCH[2]}"
  CONF_PATH="${BASH_REMATCH[3]}"
  # CONF_PATH must be a real-looking absolute path before we put it into operator-
  # facing recommendations. Reject anything that has shell-active characters.
  if ! [[ "$CONF_PATH" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    warn "slurm.conf path returned by remote did not validate; skipping freshness check"
  elif [[ "$CONF_MTIME" -gt "$CTLD_START" && "$CTLD_START" -gt 0 ]]; then
    DELTA=$((CONF_MTIME - CTLD_START))
    warn "$CONF_PATH modified ${DELTA}s after slurmctld last started — config may be stale in memory"
    hint "for the reload-vs-restart decision and procedure, see:"
    info "  https://slurm.schedmd.com/scontrol.html"
    info "  https://slurm.schedmd.com/slurm.conf.html"
    info "  references/slurm-details.md#scontrol-reconfigure-vs-restart"
    ISSUES+=("stale-conf")
    NEXT_STEPS+=("review reload procedure in linked docs")
  else
    ok "slurm.conf older than slurmctld start time — no pending reconfigure"
  fi
else
  warn "could not determine slurm.conf vs slurmctld timestamps"
fi

# --- Check for stuck jobs -----------------------------------------------------
section "4. Job queue health"
SQUEUE_OUT=$(ssm_run "$SSM_HEAD" 'squeue -h -o "%i|%T|%r" 2>&1 | head -200' || true)
if [[ $(printf '%s\n' "$SQUEUE_OUT" | wc -l) -ge 200 ]]; then
  warn "squeue output reached the 200-line cap — stuck-job counts below may underreport on this large cluster"
fi
STUCK_PENDING=0
STUCK_COMPLETING=0
while IFS='|' read -r jobid state reason; do
  [[ -z "$jobid" ]] && continue
  [[ "$state" == "PENDING" && "$reason" == "Resources" ]] && STUCK_PENDING=$((STUCK_PENDING+1))
  [[ "$state" == "COMPLETING" ]] && STUCK_COMPLETING=$((STUCK_COMPLETING+1))
done <<< "$SQUEUE_OUT"

if [[ $STUCK_PENDING -gt 0 ]]; then
  warn "$STUCK_PENDING job(s) PENDING with Reason=Resources"
  if [[ ${#DOWN_NODES[@]} -eq 0 ]]; then
    ISSUES+=("stuck-pending-with-idle-nodes")
    NEXT_STEPS+=("controller restart — Section C")
  fi
fi
if [[ $STUCK_COMPLETING -gt 0 ]]; then
  bad "$STUCK_COMPLETING job(s) stuck in COMPLETING"
  ISSUES+=("stuck-completing")
  NEXT_STEPS+=("controller restart — Section C")
fi
[[ $STUCK_PENDING -eq 0 && $STUCK_COMPLETING -eq 0 ]] && ok "no stuck jobs"

# --- Per-node inspection (read-only) ------------------------------------------
inspect_node() {
  local slurm_node="$1"
  # Defense-in-depth: validate again at the boundary even though all upstream paths
  # validate. Cheap, and catches future refactors that miss a callsite.
  slurm_node=$(validate_node_name "$slurm_node")

  local instance_id group ssm_target
  # PrivateDnsName looks like `ip-10-1-2-3.us-west-2.compute.internal`. The strict
  # `<name>.` match handles the default `ip-x-x-x-x` form and rejects the false
  # positive where node `ip-10-1-2-3` would otherwise also match
  # `ip-10-1-2-30.<region>.compute.internal`.
  instance_id=$(jq -r --arg dns "$slurm_node" '
    .ClusterNodeSummaries[]?
    | select((.PrivateDnsName // "") | startswith($dns + "."))
    | .InstanceId' <<< "$NODES_JSON" | head -1)
  if [[ -z "$instance_id" ]]; then
    if [[ ! "$slurm_node" =~ ^ip-[0-9]+-[0-9]+-[0-9]+-[0-9]+$ ]]; then
      warn "$slurm_node: not in the default ip-X-X-X-X form — Slurm-node-name → instance-ID auto-mapping needs DNS lookup or scontrol show node, neither cheap from here. Pass --target-instance-id <i-xxx> if you have it, or look up via 'scontrol show node $slurm_node | grep NodeAddr' on the controller."
    else
      warn "$slurm_node: cannot map to instance ID (PrivateDnsName mismatch — verify node is in this cluster)"
    fi
    return
  fi
  instance_id=$(validate_instance_id "$instance_id")

  group=$(jq -r --arg id "$instance_id" \
    '.ClusterNodeSummaries[] | select(.InstanceId==$id) | .InstanceGroupName // ""' <<< "$NODES_JSON")
  group=$(validate_group_name "$group")
  ssm_target="sagemaker-cluster:${CLUSTER_ID}_${group}-${instance_id}"

  local slurmd_status disk mem rpc_check
  slurmd_status=$(ssm_run "$ssm_target" 'systemctl is-active slurmd 2>&1' | tr -d '\r\n' || true)
  disk=$(ssm_run         "$ssm_target" 'df -h / | awk "NR==2 {print \$5}"' | tr -d '\r\n' || true)
  mem=$(ssm_run          "$ssm_target" 'free -h | awk "/Mem:/ {print \$3\"/\"\$2}"' | tr -d '\r\n' || true)

  # Slurm-RPC reachability: srun -w "$NODE" hostname. The remote script reads $NODE
  # from the environment, so the slurm node name is never string-interpolated into
  # the remote shell — it lives in env-var space the whole way.
  rpc_check=$(ssm_run "$SSM_HEAD" 'timeout 10 srun --immediate=5 -w "$NODE" hostname 2>&1 | tail -1' \
              "NODE=$slurm_node" | tr -d '\r\n' || true)

  info "$slurm_node ($instance_id): slurmd=$slurmd_status disk=$disk mem=$mem"
  info "  srun RPC: ${rpc_check:-<no output>}"

  local disk_num="${disk%\%}"
  if [[ "$disk_num" =~ ^[0-9]+$ && "$disk_num" -ge 95 ]]; then
    bad "  $slurm_node: root volume ${disk} — clean up before any restart"
    info "  HyperPod storage layout: https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md"
    ISSUES+=("disk-full-$slurm_node")
    NEXT_STEPS+=("clean disk on $slurm_node before recovery")
  fi
  if [[ "$slurmd_status" != "active" ]]; then
    bad "  $slurm_node: slurmd is '$slurmd_status'"
    info "  for recovery procedure, see:"
    info "    https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md"
  fi
  if [[ -n "$rpc_check" ]] && grep -qiE 'auth|munge|invalid' <<< "$rpc_check"; then
    bad "  $slurm_node: srun reports auth/munge error — slurmd-controller trust broken"
    info "  for munge troubleshooting, see Slurm authentication docs:"
    info "    https://slurm.schedmd.com/authentication.html"
  fi
}

if [[ -n "$TARGET_NODE" ]]; then
  section "5. Inspecting node: $TARGET_NODE"
  inspect_node "$TARGET_NODE"
elif [[ ${#DOWN_NODES[@]} -gt 0 || ${#REBOOT_NODES[@]} -gt 0 ]]; then
  section "5. Inspecting affected nodes"
  for entry in "${DOWN_NODES[@]-}"; do
    [[ -z "$entry" ]] && continue
    inspect_node "${entry%%|*}"
  done
  for n in "${REBOOT_NODES[@]-}"; do
    [[ -z "$n" ]] && continue
    inspect_node "$n"
  done
fi

# --- Section E: HyperPod auto-resume support + recent missed-resume detection ---
section "E. Auto-resume support"

AR_HELP=$(ssm_run "$SSM_HEAD" 'srun --help 2>&1 | grep -i auto-resume | head -3' || true)
if [[ -n "$AR_HELP" ]]; then
  ok "srun --auto-resume is available on this cluster"
else
  warn "srun --auto-resume not found in srun --help output"
  info "this AMI / Slurm build may predate HyperPod auto-resume support"
  info "see: references/slurm-details.md#hyperpod-auto-resume"
  ISSUES+=("auto-resume-unsupported")
  NEXT_STEPS+=("upgrade the cluster AMI / Slurm package to enable --auto-resume")
fi

read -r -d '' G_FAILS <<'REMOTE_G' || true
sacct -X -n --starttime=now-6hours \
  -o JobID,State,ExitCode,NodeList \
  --state=NODE_FAIL,FAILED 2>/dev/null \
  | awk 'NF>=4 && $4!~/None/ {print $1"|"$2"|"$4}' | head -50
REMOTE_G
RECENT_FAILS=$(ssm_run "$SSM_HEAD" "$G_FAILS" 2>/dev/null || true)

MISSED_AR=()
NOW_EPOCH=$(date +%s)
while IFS='|' read -r jobid state nodelist; do
  [[ -z "$jobid" ]] && continue
  # Only single-node failures — multi-node lists need a real range expander.
  [[ "$nodelist" == *,* || "$nodelist" == *\[* ]] && continue
  # Validate before passing to remote.
  if ! [[ "$nodelist" =~ ^[a-zA-Z0-9._-]{1,253}$ ]]; then
    continue
  fi
  # A successful HyperPod replace clears the node's Reason field once the new instance
  # registers, so grepping for "Action:Replace" is unreliable. Detect a recent replace
  # by comparing scontrol show node's BootTime to wall-clock: a fresh BootTime within
  # the last 6h that's later than the failed-job's End time strongly suggests the node
  # was replaced (or rebooted) after the job died.
  BOOT_LINE=$(ssm_run "$SSM_HEAD" 'scontrol show node "$NODE" 2>/dev/null | tr " " "\n" | grep "^BootTime="' \
              "NODE=$nodelist" | head -1 | tr -d '\r\n' || true)
  BOOT_STR="${BOOT_LINE#BootTime=}"
  [[ -z "$BOOT_STR" || "$BOOT_STR" == "Unknown" ]] && continue
  BOOT_EPOCH=$(date -d "$BOOT_STR" +%s 2>/dev/null || echo 0)
  [[ "$BOOT_EPOCH" =~ ^[0-9]+$ && "$BOOT_EPOCH" -gt 0 ]] || continue
  AGE=$((NOW_EPOCH - BOOT_EPOCH))
  if [[ $AGE -ge 0 && $AGE -le 21600 ]]; then  # 6h window
    MISSED_AR+=("$jobid|$state|$nodelist|$BOOT_STR")
  fi
done <<< "$RECENT_FAILS"

if [[ ${#MISSED_AR[@]} -gt 0 ]]; then
  bad "${#MISSED_AR[@]} recent job(s) failed on a node that was rebooted/replaced shortly after — possible missed auto-resume:"
  for entry in "${MISSED_AR[@]}"; do
    IFS='|' read -r jobid state nodelist boot <<< "$entry"
    info "  job $jobid ($state) on $nodelist (node BootTime=$boot)"
  done
  info "(heuristic: node BootTime is within the last 6h, suggesting a replace or reboot)"
  hint "verify the launch command used srun --auto-resume=1 (NOT just sbatch):"
  info "  sacct -j <JOBID> -o JobID,JobName,Submit,Start,End,State,ExitCode,NodeList -X"
  info "  scontrol show job <JOBID>   # only if still in the controller's recent history"
  info "see: references/slurm-details.md#hyperpod-auto-resume"
  ISSUES+=("missed-auto-resume")
  NEXT_STEPS+=("verify --auto-resume=1 is on the srun line, not just sbatch")
elif [[ -n "$RECENT_FAILS" ]]; then
  ok "recent failed jobs do not match the missed-auto-resume pattern"
else
  ok "no recent NODE_FAIL / FAILED jobs in the last 6h"
fi

# --- Findings → documentation links ------------------------------------------
# This skill is diagnostic-only. It never prints a remediation command. For each
# finding, point the user at the authoritative doc and let them act.
section "Where to read next"

if [[ ${#REBOOT_NODES[@]} -gt 0 ]]; then
  hint "Section B — nodes flagged 'unexpectedly rebooted':"
  for n in "${REBOOT_NODES[@]}"; do
    info "  $n"
  done
  info "  HyperPod Slurm troubleshooting:"
  info "    https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md"
  info "  diagnostic context: references/slurm-details.md#-b-unexpected-reboot--diagnostic-context"
fi

if [[ ${#DOWN_NODES[@]} -gt 0 ]]; then
  hint "Section A — nodes DOWN/DRAIN:"
  for entry in "${DOWN_NODES[@]}"; do
    n="${entry%%|*}"; r="${entry#*|}"
    info "  $n  (reason: $r)"
  done
  info "  HyperPod Slurm troubleshooting:"
  info "    https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md"
  info "  if the node flaps after a manual recovery → route to hyperpod-node-debugger"
fi

CTRL_RESTART_REASON=""
ISSUES_STR=" ${ISSUES[*]-} "
[[ "$ISSUES_STR" == *" controller-hung "* ]]               && CTRL_RESTART_REASON="scontrol ping failed"
[[ "$ISSUES_STR" == *" stuck-completing "* ]]              && CTRL_RESTART_REASON="${CTRL_RESTART_REASON:+$CTRL_RESTART_REASON, }jobs stuck COMPLETING"
[[ "$ISSUES_STR" == *" stuck-pending-with-idle-nodes "* ]] && CTRL_RESTART_REASON="${CTRL_RESTART_REASON:+$CTRL_RESTART_REASON, }jobs PENDING with idle nodes"

if [[ -n "$CTRL_RESTART_REASON" ]]; then
  hint "Section C — controller-state issue ($CTRL_RESTART_REASON):"
  info "  Slurm slurmctld(8) — for what is preserved across a controller restart:"
  info "    https://slurm.schedmd.com/slurmctld.html"
  info "  HyperPod Slurm troubleshooting:"
  info "    https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md"
  if [[ ${#FAIL_NODES[@]} -gt 0 ]]; then
    warn "HyperPod recovery is in progress on:"
    for entry in "${FAIL_NODES[@]}"; do
      n="${entry%%|*}"
      info "  $n"
    done
    info "AWS docs warn against changing node state or restarting slurmctld during a"
    info "replacement; wait for it to complete, then re-run this script."
  fi
  info "  diagnostic context: references/slurm-details.md#-c-controller-state--diagnostic-context"
fi

if [[ "$ISSUES_STR" == *" missed-auto-resume "* ]]; then
  hint "Section E — recent job failed on a node that was later replaced:"
  info "  the most common cause is --auto-resume on sbatch instead of srun."
  info "  Use SageMaker HyperPod auto-resume:"
  info "    https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-auto-resume.html"
  info "  diagnostic context: references/slurm-details.md#hyperpod-auto-resume"
fi

# --- Summary ------------------------------------------------------------------
section "Summary"
printf '  Issues detected: %d\n' "${#ISSUES[@]-0}"
if [[ ${#ISSUES[@]-0} -eq 0 ]]; then
  ok "cluster Slurm state is healthy"
else
  echo ""
  echo "  Findings:"
  for i in "${ISSUES[@]}"; do
    info "- $i"
  done
fi

if [[ ${#NEXT_STEPS[@]-0} -gt 0 ]]; then
  echo ""
  echo "  Where to read next:"
  for s in "${NEXT_STEPS[@]}"; do
    info "- $s"
  done
fi

