#!/usr/bin/env bash
# slurm-diagnose-fix.sh
#
# Diagnose and (optionally) fix Slurm node-management issues on Amazon SageMaker HyperPod
# Slurm clusters. Covers the three failure modes from the HyperPod Slurm troubleshooting
# guide:
#   A. Node DOWN / not responding
#   B. Node marked DOWN with reason "Node unexpectedly rebooted"
#   C. Jobs stuck PENDING / COMPLETING due to stale slurmctld state
#
# The script is SSM-first: it discovers the controller node from DescribeCluster, runs Slurm
# commands there, and SSMs to any affected compute node to inspect slurmd. Default mode is
# read-only inspection. --fix applies safe remediation (restart slurmd, resume a healthy
# node). Restarting slurmctld always prompts for interactive confirmation first.
#
# Usage:
#   bash slurm-diagnose-fix.sh --cluster <NAME-or-ARN> --region <REGION>
#   bash slurm-diagnose-fix.sh --cluster <N> --region <R> --node <SLURM_NODE>
#   bash slurm-diagnose-fix.sh --cluster <N> --region <R> --fix
#   bash slurm-diagnose-fix.sh --cluster <N> --region <R> --fix --yes   # non-interactive

set -euo pipefail

CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TARGET_NODE=""
APPLY_FIX=false
ASSUME_YES=false
USE_COLOR=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)  CLUSTER="$2";     shift 2 ;;
    --region)   REGION="$2";      shift 2 ;;
    --node)     TARGET_NODE="$2"; shift 2 ;;
    --fix)      APPLY_FIX=true;   shift ;;
    --yes|-y)   ASSUME_YES=true;  shift ;;
    --no-color) USE_COLOR=false;  shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$CLUSTER" ]] && { echo "Error: --cluster is required" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI is required (v2 recommended)." >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "Error: jq is required. Install with your package manager." >&2; exit 1; }

if "$USE_COLOR"; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

section() { echo ""; printf "${BOLD}${CYAN}=== %s ===${NC}\n" "$1"; }
ok()   { printf "  ${GREEN}[PASS]${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}[WARN]${NC} %s\n" "$1"; }
bad()  { printf "  ${RED}[FAIL]${NC} %s\n" "$1"; }
info() { printf "         %s\n" "$1"; }
fix()  { printf "  ${CYAN}[FIX ]${NC} %s\n" "$1"; }

# Interactive confirmation for high-risk actions. Returns 0 on yes, 1 on anything else.
# --yes / -y flag bypasses. When stdin is not a TTY and --yes is not set, refuses the action.
confirm() {
  local prompt="$1"
  if "$ASSUME_YES"; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "not a TTY — refusing high-risk action (pass --yes to proceed non-interactively)"
    return 1
  fi
  printf "${YELLOW}%s${NC} [y/N] " "$prompt"
  local answer
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ISSUES=()
FIXES=()
SKIPPED=()

# --- Verify cluster + orchestrator --------------------------------------------
section "1. Cluster identity"
DESC=$(aws sagemaker describe-cluster --cluster-name "$CLUSTER" --region "$REGION" \
  --output json 2>&1) || { bad "cannot describe cluster: $DESC"; exit 1; }

ORCH=$(echo "$DESC" | jq -r '.Orchestrator | keys[0] // "slurm"')
if [[ "$ORCH" == "Eks" ]]; then
  bad "cluster uses EKS orchestrator - this skill is for Slurm only"
  info "use hyperpod-node-debugger or hyperpod-nccl instead"
  exit 1
fi
ok "Slurm cluster: $(echo "$DESC" | jq -r '.ClusterName')  status=$(echo "$DESC" | jq -r '.ClusterStatus')"

# --- Find controller node -----------------------------------------------------
NODES_JSON=$(aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER" --region "$REGION" \
  --output json 2>&1) || { bad "list-cluster-nodes failed: $NODES_JSON"; exit 1; }

CONTROLLER_ID=$(echo "$NODES_JSON" | jq -r '
  .ClusterNodeSummaries[]
  | select(.InstanceGroupName|test("controller|head";"i"))
  | .InstanceId' | head -1)

if [[ -z "$CONTROLLER_ID" ]]; then
  # Fallback: use the first instance group. Rare on Slurm clusters, but better than exiting.
  CONTROLLER_ID=$(echo "$NODES_JSON" | jq -r '.ClusterNodeSummaries[0].InstanceId')
  warn "no controller/head group found - using first node $CONTROLLER_ID as head"
else
  ok "controller node: $CONTROLLER_ID"
fi

CLUSTER_ID=$(echo "$DESC" | jq -r '.ClusterArn' | awk -F'/' '{print $NF}')
CONTROLLER_GROUP=$(echo "$NODES_JSON" | jq -r --arg id "$CONTROLLER_ID" \
  '.ClusterNodeSummaries[] | select(.InstanceId==$id) | .InstanceGroupName')
SSM_HEAD="sagemaker-cluster:${CLUSTER_ID}_${CONTROLLER_GROUP}-${CONTROLLER_ID}"

# Run a command on a HyperPod node via SSM; prints stdout, returns SSM exit code.
# The command is passed to SSM as a JSON array built by jq — never string-interpolated into
# the CLI payload — so embedded quotes / shell metacharacters in $cmd cannot break the JSON
# or turn into an injection vector.
ssm_run() {
  local target="$1"; shift
  local cmd="$*"
  local params
  params=$(jq -nc --arg c "$cmd" '{command: [$c]}')
  aws ssm start-session --region "$REGION" --target "$target" \
    --document-name AWS-StartNonInteractiveCommand \
    --parameters "$params" 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;]*m//g' -e '/Starting session/d' -e '/Exiting session/d' || true
}

# --- Collect Slurm state from head node ---------------------------------------
section "2. Slurm cluster state (from head node)"
SINFO_OUT=$(ssm_run "$SSM_HEAD" "sinfo -h -o '%N|%T|%E' 2>&1 | head -200") || true
if [[ -z "$SINFO_OUT" ]] || echo "$SINFO_OUT" | grep -qi 'command not found\|cannot connect'; then
  bad "cannot run sinfo on head node - SSM or Slurm not ready"
  info "try:  aws ssm start-session --target $SSM_HEAD --region $REGION"
  info "then: sinfo  (install session-manager-plugin if SSM start-session fails)"
  exit 1
fi

DOWN_NODES=()
REBOOT_NODES=()
while IFS='|' read -r node state reason; do
  [[ -z "$node" ]] && continue
  if echo "$state" | grep -qiE 'down|drain'; then
    if echo "$reason" | grep -qi 'unexpectedly rebooted'; then
      REBOOT_NODES+=("$node")
    else
      DOWN_NODES+=("$node|$reason")
    fi
  fi
done <<< "$SINFO_OUT"

if [[ ${#DOWN_NODES[@]} -eq 0 && ${#REBOOT_NODES[@]} -eq 0 ]]; then
  ok "all nodes in healthy Slurm states"
else
  [[ ${#DOWN_NODES[@]} -gt 0 ]]   && bad "${#DOWN_NODES[@]} node(s) DOWN/DRAIN (Section A)"
  [[ ${#REBOOT_NODES[@]} -gt 0 ]] && bad "${#REBOOT_NODES[@]} node(s) with 'unexpectedly rebooted' (Section B)"
fi

# --- Check controller health --------------------------------------------------
section "3. slurmctld health"
PING_OUT=$(ssm_run "$SSM_HEAD" "scontrol ping 2>&1")
if echo "$PING_OUT" | grep -qi 'UP'; then
  ok "slurmctld responding: $(echo "$PING_OUT" | tr '\n' ' ')"
else
  bad "slurmctld not responding: $PING_OUT"
  ISSUES+=("controller-hung")
fi

# --- Check for stuck jobs -----------------------------------------------------
section "4. Job queue health"
SQUEUE_OUT=$(ssm_run "$SSM_HEAD" "squeue -h -o '%i|%T|%r' 2>&1 | head -200")
STUCK_PENDING=0
STUCK_COMPLETING=0
while IFS='|' read -r jobid state reason; do
  [[ -z "$jobid" ]] && continue
  [[ "$state" == "PD" && "$reason" == "Resources" ]] && STUCK_PENDING=$((STUCK_PENDING+1))
  [[ "$state" == "CG" ]] && STUCK_COMPLETING=$((STUCK_COMPLETING+1))
done <<< "$SQUEUE_OUT"

if [[ $STUCK_PENDING -gt 0 ]]; then
  warn "$STUCK_PENDING job(s) PENDING with REASON=Resources"
  [[ ${#DOWN_NODES[@]} -eq 0 ]] && ISSUES+=("stuck-pending-with-idle-nodes")
fi
[[ $STUCK_COMPLETING -gt 0 ]] && { bad "$STUCK_COMPLETING job(s) stuck in COMPLETING"; ISSUES+=("stuck-completing"); }
[[ $STUCK_PENDING -eq 0 && $STUCK_COMPLETING -eq 0 ]] && ok "no stuck jobs"

# --- Detect in-progress HyperPod replacements ---------------------------------
# AWS docs: "Avoid changing the node state or restarting the Slurm controller during the
# [replacement] operation." Refuse any controller restart while any node is in `fail` with
# an Action:* reason, regardless of --yes.
REPLACING_NODES=()
while IFS='|' read -r node state reason; do
  [[ -z "$node" ]] && continue
  if echo "$state" | grep -qi 'fail' && echo "$reason" | grep -qi 'Action:'; then
    REPLACING_NODES+=("$node")
  fi
done <<< "$SINFO_OUT"

if [[ ${#REPLACING_NODES[@]} -gt 0 ]]; then
  warn "HyperPod replacement/reboot in progress on: ${REPLACING_NODES[*]}"
  info "controller restart will be refused until these nodes finish (per AWS docs)"
fi

# --- Per-node inspection ------------------------------------------------------
inspect_node() {
  local slurm_node="$1"
  local instance_id group ssm_target
  instance_id=$(echo "$NODES_JSON" | jq -r --arg dns "$slurm_node" '
    .ClusterNodeSummaries[] | select(.PrivateDnsName|startswith($dns)) | .InstanceId' | head -1)
  [[ -z "$instance_id" ]] && { warn "$slurm_node: cannot map to instance ID"; return; }
  group=$(echo "$NODES_JSON" | jq -r --arg id "$instance_id" \
    '.ClusterNodeSummaries[] | select(.InstanceId==$id) | .InstanceGroupName')
  ssm_target="sagemaker-cluster:${CLUSTER_ID}_${group}-${instance_id}"

  local slurmd_status disk mem
  slurmd_status=$(ssm_run "$ssm_target" "systemctl is-active slurmd 2>&1" | tr -d '\n')
  disk=$(ssm_run "$ssm_target" "df -h / | awk 'NR==2 {print \$5}'" | tr -d '\n')
  mem=$(ssm_run "$ssm_target" "free -h | awk '/Mem:/ {print \$3\"/\"\$2}'" | tr -d '\n')

  info "$slurm_node ($instance_id): slurmd=$slurmd_status disk=$disk mem=$mem"
  echo "$slurm_node|$instance_id|$ssm_target|$slurmd_status|$disk"
}

NODE_DETAILS=()
if [[ -n "$TARGET_NODE" ]]; then
  section "5. Inspecting node: $TARGET_NODE"
  d=$(inspect_node "$TARGET_NODE" | tail -1)
  [[ -n "$d" ]] && NODE_DETAILS+=("$d")
elif [[ ${#DOWN_NODES[@]} -gt 0 || ${#REBOOT_NODES[@]} -gt 0 ]]; then
  section "5. Inspecting affected nodes"
  for entry in "${DOWN_NODES[@]-}"; do
    [[ -z "$entry" ]] && continue
    d=$(inspect_node "${entry%%|*}" | tail -1)
    [[ -n "$d" ]] && NODE_DETAILS+=("$d")
  done
  for n in "${REBOOT_NODES[@]-}"; do
    [[ -z "$n" ]] && continue
    d=$(inspect_node "$n" | tail -1)
    [[ -n "$d" ]] && NODE_DETAILS+=("$d")
  done
fi

# --- Apply fixes --------------------------------------------------------------
section "6. Remediation"

if ! "$APPLY_FIX"; then
  info "(dry-run - re-run with --fix to apply safe remediation;"
  info " --fix always prompts before the highest-risk actions)"
fi

# Section B: unexpectedly rebooted — this is the low-risk, routine recovery path.
for n in "${REBOOT_NODES[@]-}"; do
  [[ -z "$n" ]] && continue
  fix "Section B: $n - ensure slurmd is running, then 'scontrol update state=resume'"
  if "$APPLY_FIX"; then
    # Find this node's SSM target
    for d in "${NODE_DETAILS[@]-}"; do
      [[ -z "$d" ]] && continue
      IFS='|' read -r sn _ tgt sstatus _ <<< "$d"
      [[ "$sn" == "$n" ]] || continue
      if [[ "$sstatus" != "active" ]]; then
        ssm_run "$tgt" "sudo systemctl enable slurmd && sudo systemctl start slurmd" >/dev/null
      fi
      ssm_run "$SSM_HEAD" "sudo scontrol update nodename=$n state=resume"
      FIXES+=("resumed $n")
      break
    done
  fi
done

# Section A: DOWN nodes — restart slurmd and resume if it comes back healthy.
for entry in "${DOWN_NODES[@]-}"; do
  [[ -z "$entry" ]] && continue
  node="${entry%%|*}"; reason="${entry##*|}"
  # Skip if disk is full - that needs human cleanup first
  for d in "${NODE_DETAILS[@]-}"; do
    [[ -z "$d" ]] && continue
    IFS='|' read -r sn _ tgt sstatus disk_pct <<< "$d"
    [[ "$sn" == "$node" ]] || continue
    disk_num=$(echo "$disk_pct" | tr -d '%')
    if [[ -n "$disk_num" && "$disk_num" -ge 95 ]]; then
      warn "$node: disk $disk_pct - cleanup required before fix (see references/slurm-details.md)"
      ISSUES+=("disk-full-$node")
      SKIPPED+=("$node (disk $disk_pct full)")
      continue 2
    fi
    if [[ "$sstatus" != "active" ]]; then
      fix "Section A: $node - slurmd is '$sstatus', restart + resume"
      if "$APPLY_FIX"; then
        ssm_run "$tgt" "sudo systemctl restart slurmd" >/dev/null
        sleep 3
        new_status=$(ssm_run "$tgt" "systemctl is-active slurmd" | tr -d '\n')
        if [[ "$new_status" == "active" ]]; then
          ssm_run "$SSM_HEAD" "sudo scontrol update nodename=$node state=resume"
          FIXES+=("restarted slurmd + resumed $node")
        else
          warn "$node: slurmd still not active after restart - escalate to hyperpod-node-debugger"
        fi
      fi
    else
      warn "$node: slurmd is active but Slurm shows DOWN (reason: $reason) - try resume"
      fix "Section A: $node - 'scontrol update state=resume'"
      if "$APPLY_FIX"; then
        ssm_run "$SSM_HEAD" "sudo scontrol update nodename=$node state=resume"
        FIXES+=("resumed $node")
      fi
    fi
  done
done

# Section C: controller restart — high-risk, always prompts.
CTRL_RESTART_REASON=""
ISSUES_STR=" ${ISSUES[*]-} "
if [[ "$ISSUES_STR" == *" controller-hung "* ]];               then CTRL_RESTART_REASON="scontrol ping failed"; fi
if [[ "$ISSUES_STR" == *" stuck-completing "* ]];              then CTRL_RESTART_REASON="jobs stuck COMPLETING"; fi
if [[ "$ISSUES_STR" == *" stuck-pending-with-idle-nodes "* ]]; then CTRL_RESTART_REASON="jobs PENDING with idle nodes"; fi

if [[ -n "$CTRL_RESTART_REASON" ]]; then
  fix "Section C: restart slurmctld suggested ($CTRL_RESTART_REASON)"
  info "A restart is expected to preserve running jobs, pending queue, and node states"
  info "(all read back from StateSaveLocation on disk)."

  if [[ ${#REPLACING_NODES[@]} -gt 0 ]]; then
    warn "REFUSING to restart slurmctld — ${#REPLACING_NODES[@]} node(s) mid-replace"
    info "per AWS docs: 'Avoid ... restarting the Slurm controller during the operation'"
    info "wait for replacement to finish, then re-run this script"
    SKIPPED+=("slurmctld restart (replacement in progress)")
  elif "$APPLY_FIX"; then
    if confirm "Restart slurmctld on $CONTROLLER_ID now?"; then
      ssm_run "$SSM_HEAD" "sudo systemctl restart slurmctld"
      sleep 5
      new_ping=$(ssm_run "$SSM_HEAD" "scontrol ping 2>&1" | tr '\n' ' ')
      if echo "$new_ping" | grep -qi 'UP'; then
        FIXES+=("restarted slurmctld")
        ok "slurmctld back up: $new_ping"
      else
        warn "slurmctld still not responding: $new_ping"
        info "verify StateSaveLocation, then try: sudo pkill -9 slurmctld && sudo systemctl start slurmctld"
        info "if that also fails, collect hyperpod-issue-report and contact AWS Support"
      fi
    else
      info "skipped — run manually on $CONTROLLER_ID when ready:"
      info "  sudo systemctl restart slurmctld"
      SKIPPED+=("slurmctld restart (user declined)")
    fi
  fi
fi

# --- Summary ------------------------------------------------------------------
section "Summary"
echo "  Issues detected: ${#ISSUES[@]-0}"
echo "  Fixes applied:   ${#FIXES[@]-0}"
echo "  Skipped:         ${#SKIPPED[@]-0}"
if [[ ${#ISSUES[@]-0} -eq 0 ]]; then
  ok "cluster Slurm state is healthy"
fi

if [[ ${#FIXES[@]-0} -gt 0 ]]; then
  echo ""
  echo "  Applied:"
  printf "    - %s\n" "${FIXES[@]-}"
  echo ""
  info "re-run without --fix to confirm issues are cleared"
fi

if [[ ${#SKIPPED[@]-0} -gt 0 ]]; then
  echo ""
  echo "  Skipped:"
  printf "    - %s\n" "${SKIPPED[@]-}"
fi

if ! "$APPLY_FIX" && [[ ${#ISSUES[@]-0} -gt 0 ]]; then
  echo ""
  info "run with --fix to apply safe remediation (controller restart still prompts)"
fi
