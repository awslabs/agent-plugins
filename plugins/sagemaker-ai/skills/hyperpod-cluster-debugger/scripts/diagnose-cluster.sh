#!/usr/bin/env bash
# diagnose-cluster.sh — read-only HyperPod cluster-level diagnostic.
# See SKILL.md and references/cluster-diagnostics-detail.md for remediation.
#
# Exit codes:
#   0  No critical (P0/P1) failures; P2 warnings are informational-only.
#   1  One or more critical failures, or a fatal prerequisite.
#   2  Invalid argument.

set -euo pipefail

for cmd in aws jq python3; do
  command -v "$cmd" &>/dev/null || {
    echo "ERROR: '$cmd' is required but not found. Install it and retry."
    exit 1
  }
done
# unbuffer is only needed if the Slurm-controller SSM probe runs
# (activated when the cluster's orchestrator is Slurm). Warn at startup
# but don't exit — EKS-only users shouldn't be blocked.
if ! command -v unbuffer &>/dev/null; then
  echo "WARN: 'unbuffer' not found. Required for the Slurm-controller SSM probe." >&2
  echo "      Install via 'yum install expect' / 'apt install expect' / 'brew install expect'." >&2
  echo "      EKS diagnostics will continue; Slurm-controller-only checks will be skipped." >&2
fi

CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-}"
USE_COLOR=true
VALIDATE_MODE=false
VALIDATE_SG_IDS=""
VALIDATE_SUBNET_IDS=""
VALIDATE_IAM_ROLE=""
VALIDATE_S3_URI=""
VALIDATE_INSTANCE_TYPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)    [[ $# -lt 2 ]] && { echo "ERROR: --cluster needs a value"; exit 2; }
                  [[ ! "$2" =~ ^(arn:aws[a-z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:cluster/[a-z0-9]{12}|[a-zA-Z0-9]([-a-zA-Z0-9]{0,62}))$ ]] && { echo "ERROR: --cluster must be a valid HyperPod cluster name or ARN (got '$2')"; exit 2; }
                  CLUSTER="$2"; shift 2 ;;
    --region)     [[ $# -lt 2 ]] && { echo "ERROR: --region needs a value"; exit 2; }
                  [[ ! "$2" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]] && { echo "ERROR: --region must be a valid AWS region (got '$2')"; exit 2; }
                  REGION="$2"; shift 2 ;;
    --sg-ids)        [[ $# -lt 2 ]] && { echo "ERROR: --sg-ids needs a value";        exit 2; }; VALIDATE_SG_IDS="$2";        shift 2 ;;
    --subnet-ids)    [[ $# -lt 2 ]] && { echo "ERROR: --subnet-ids needs a value";    exit 2; }; VALIDATE_SUBNET_IDS="$2";    shift 2 ;;
    --iam-role)      [[ $# -lt 2 ]] && { echo "ERROR: --iam-role needs a value";      exit 2; }; VALIDATE_IAM_ROLE="$2";      shift 2 ;;
    --s3-uri)        [[ $# -lt 2 ]] && { echo "ERROR: --s3-uri needs a value";        exit 2; }; VALIDATE_S3_URI="$2";        shift 2 ;;
    --instance-type) [[ $# -lt 2 ]] && { echo "ERROR: --instance-type needs a value"; exit 2; }; VALIDATE_INSTANCE_TYPE="$2"; shift 2 ;;
    --no-color)   USE_COLOR=false;           shift ;;
    --validate)   VALIDATE_MODE=true;        shift ;;
    -h|--help)
      cat <<'EOF'
Usage: diagnose-cluster.sh --cluster <name-or-arn> --region <region> [--no-color]
       diagnose-cluster.sh --validate --region <region> \
         --sg-ids <sg-1,sg-2> --subnet-ids <sub-1,sub-2> [--iam-role <role-arn>] \
         [--s3-uri s3://bucket/path/] [--instance-type ml.p5.48xlarge]

Read-only diagnostic for HyperPod cluster-level issues: provisioning, access,
node replacement, VPC/SG, EKS config + add-ons, SSM, CloudWatch logs. Each
[FAIL] line in the summary includes a pointer of the form
  "→ references/cluster-diagnostics-detail.md § <section>"
so the hyperpod-cluster-debugger skill can look up the remediation runbook.

The script never modifies cluster state and never prints remediation commands.

Modes:
  (default)   Diagnose an existing cluster.
  --validate  Pre-flight config validation (validates SGs / subnets / IAM /
              VPC endpoints / optional S3 lifecycle scripts / optional per-AZ
              instance-type capacity before creating a cluster; no cluster
              needed).

See references/cluster-diagnostics-detail.md for full remediation runbooks.
See references/capacity-planning.md, lifecycle-scripts.md, cloudformation-errors.md
for deep-dive companions to sections B / C / H.
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 2 ;;
  esac
done

if [[ -z "$REGION" ]]; then
  echo "ERROR: --region is required (or set AWS_DEFAULT_REGION before running)." >&2
  exit 2
fi

if ! "$VALIDATE_MODE"; then
  [[ -z "$CLUSTER" ]] && echo "Usage: $0 --cluster <name-or-arn> --region <region>" && exit 1
fi

if ! [ -t 1 ] || [ "${TERM:-}" = "dumb" ]; then
  USE_COLOR=false
fi
if "$USE_COLOR"; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1) || {
  echo -e "${RED}ERROR: AWS credentials not configured or expired.${NC}"
  echo "$CALLER_IDENTITY"
  echo ""
  echo "→ references/cluster-diagnostics-detail.md § D (EKS Access / kubectl) for credential setup"
  exit 1
}
CALLER_ARN=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Arn','unknown'))" 2>/dev/null || echo "unknown")

CRITICAL_FAILURES=0
WARNINGS=0
ISSUES_FOUND=()

pass()    { echo -e "  ${GREEN}[PASS]${NC}  $1${2:+ — $2}"; }
fail()    { CRITICAL_FAILURES=$((CRITICAL_FAILURES+1)); echo -e "  ${RED}[FAIL]${NC}  $1${2:+ — $2}"; }
warn()    { WARNINGS=$((WARNINGS+1)); echo -e "  ${YELLOW}[WARN]${NC}  $1${2:+ — $2}"; }
info()    { echo -e "  ${CYAN}[INFO]${NC}  $1${2:+ — $2}"; }
header()  { echo ""; echo -e "${BOLD}--- $1 ---${NC}"; }
section() { echo ""; echo -e "${BOLD}=== $1 ===${NC}"; }

add_issue() {
  local priority="${2:-P1}"
  ISSUES_FOUND+=("${priority}|$1")
}

_CD_TEMP_FILES=()
trap '[[ ${#_CD_TEMP_FILES[@]} -gt 0 ]] && rm -f "${_CD_TEMP_FILES[@]}" 2>/dev/null || true' EXIT

# Run a shell command on a HyperPod instance via SSM. Payload is base64-encoded
# so shell metacharacters in the command are safely passed through argv.
ssm_run_on_node() {
  local iid="$1" grp="$2" cmd="$3"
  [[ -z "$iid" || -z "$grp" || -z "$cmd" ]] && return 1
  [[ ! "$iid" =~ ^i-[0-9a-f]{8,17}$ ]] && return 1
  [[ -z "${CLUSTER_ID:-}" ]] && return 1
  [[ ! "$grp" =~ ^[A-Za-z0-9._-]+$ ]] && return 1

  local target="sagemaker-cluster:${CLUSTER_ID}_${grp}-${iid}"
  local tmp; tmp=$(mktemp 2>/dev/null) || return 1
  chmod 600 "$tmp" 2>/dev/null || true
  _CD_TEMP_FILES+=("$tmp")
  local cmd_b64
  cmd_b64=$(printf '%s' "$cmd" | base64 | tr -d '\n') || return 1
  local remote="bash -c \"echo $cmd_b64 | base64 -d | bash\""
  python3 -c "import json,sys; print(json.dumps({'command':[sys.argv[1]]}))" "$remote" > "$tmp" || return 1

  # unbuffer avoids the session-manager-plugin "Cannot perform start session:
  # EOF" race. Only required on Slurm clusters (controller probe); guard at
  # call site so EKS-only users aren't blocked if unbuffer is absent.
  local _ssm_wrap=""
  command -v unbuffer >/dev/null 2>&1 && _ssm_wrap="unbuffer"

  local attempt=0 out rc
  while (( attempt < 5 )); do
    out=$($_ssm_wrap timeout 180 aws ssm start-session \
      --target "$target" \
      --document-name AWS-StartNonInteractiveCommand \
      --parameters "file://$tmp" \
      --region "$REGION" 2>&1)
    rc=$?
    # Retry transient SSM transport errors (rc=0 with EOF/plugin/timeout in stdout).
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
    echo "$out" >&2
    return 1
  done
  return 1
}

# Check SG self-referencing rules. Reads SG JSON from stdin, outputs PASS/FAIL/WARN lines.
check_sg_self_ref() {
  local sg_id="$1"
  SG_CHECK_ID="$sg_id" python3 -c "
import sys, json, os
sg_id = os.environ['SG_CHECK_ID']
sgs = json.load(sys.stdin).get('SecurityGroups', [])
if not sgs:
    print(f'SKIP:Could not describe {sg_id}')
    sys.exit(0)
sg = sgs[0]
inbound_self = any(
    any(p.get('GroupId') == sg_id for p in r.get('UserIdGroupPairs', []))
    for r in sg.get('IpPermissions', [])
)
outbound_self = any(
    any(p.get('GroupId') == sg_id for p in r.get('UserIdGroupPairs', []))
    for r in sg.get('IpPermissionsEgress', [])
)
outbound_all = any(
    any(r2.get('CidrIp') == '0.0.0.0/0' for r2 in r.get('IpRanges', []))
    for r in sg.get('IpPermissionsEgress', [])
)
if inbound_self:  print(f'PASS:inbound:SG {sg_id}: Inbound self-ref present')
else:             print(f'FAIL:inbound:SG {sg_id}: Inbound self-ref MISSING — required for inter-node communication')
if outbound_self: print(f'PASS:outbound:SG {sg_id}: Outbound self-ref present')
else:             print(f'FAIL:outbound:SG {sg_id}: Outbound self-ref MISSING — required for EFA RDMA traffic')
if outbound_all:  print(f'PASS:internet:SG {sg_id}: Outbound 0.0.0.0/0 present')
else:             print(f'WARN:internet:SG {sg_id}: Outbound 0.0.0.0/0 missing — may be needed for AWS API calls')
" 2>/dev/null || echo ""
}

# AWS API wrapper that detects permission failures
aws_check() {
  local api_label="$1"; shift
  local result
  result=$("$@" 2>&1)
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    if echo "$result" | grep -qiE "AccessDenied|UnauthorizedOperation|not authorized|AuthorizationError"; then
      warn "$api_label" "IAM permission denied — results may be incomplete"
      add_issue "Missing IAM permission for $api_label → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)" "P1"
      echo ""
      return 1
    fi
    echo "$result"
    return "$rc"
  fi
  echo "$result"
}

if "$VALIDATE_MODE"; then
  section "HyperPod Pre-Creation Validation"
  echo -e "Region:  ${BOLD}${REGION}${NC}"
  echo -e "Caller:  ${BOLD}${CALLER_ARN}${NC}"
  echo -e "Time:    $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ -n "$VALIDATE_SG_IDS" ]]; then
    header "V1. Security Group Rules"
    for SG in $(echo "$VALIDATE_SG_IDS" | tr ',' ' '); do
      SG_JSON=$(aws_check "describe-sg-$SG" aws ec2 describe-security-groups \
        --group-ids "$SG" --region "$REGION" --output json) || continue

      _SG_CHECK_OUT=$(echo "$SG_JSON" | check_sg_self_ref "$SG")
      while IFS=: read -r level check msg; do
        [[ -z "$level" ]] && continue
        case "$level" in
          PASS) pass "$msg" ;;
          FAIL)
            fail "$msg"
            add_issue "SG $SG missing $check self-ref → references/cluster-diagnostics-detail.md § A (EFA Health Checks)" "P0"
            ;;
          WARN) warn "$msg" ;;
        esac
      done <<< "$_SG_CHECK_OUT"
    done
  fi

  if [[ -n "$VALIDATE_SUBNET_IDS" ]]; then
    header "V2. Subnet Configuration"
    IFS=',' read -ra _subnet_ids <<< "$VALIDATE_SUBNET_IDS"
    SUB_JSON=$(aws_check "describe-subnets" aws ec2 describe-subnets \
      --subnet-ids "${_subnet_ids[@]}" \
      --region "$REGION" --output json) || SUB_JSON='{"Subnets":[]}'

    echo "$SUB_JSON" | python3 -c "
import sys, json
subnets = json.load(sys.stdin).get('Subnets', [])
vpcs = set()
azs = set()
for s in subnets:
    sid = s.get('SubnetId', '?')
    vpc = s.get('VpcId', '?')
    az = s.get('AvailabilityZone', '?')
    free = s.get('AvailableIpAddressCount', 0)
    vpcs.add(vpc)
    azs.add(az)
    status = 'LOW' if free < 10 else 'OK'
    print(f'SUBNET:{sid}:{vpc}:{az}:{free}:{status}')
print(f'VPC_COUNT:{len(vpcs)}')
print(f'AZ_COUNT:{len(azs)}')
" 2>/dev/null | while IFS=: read -r tag rest; do
      case "$tag" in
        SUBNET)
          IFS=: read -r sid _vpc az free status <<< "$rest"
          if [[ "$status" == "LOW" ]]; then
            warn "Subnet $sid (AZ=$az) — only $free IPs available"
          else
            pass "Subnet $sid" "AZ=$az FreeIPs=$free"
          fi
          ;;
        VPC_COUNT)
          if [[ "$rest" -gt 1 ]]; then
            fail "Subnets are in DIFFERENT VPCs — all must be in same VPC"
            add_issue "Subnets in different VPCs → references/cluster-diagnostics-detail.md § B (Capacity & AZ)" "P0"
          else
            pass "All subnets in same VPC"
          fi
          ;;
        AZ_COUNT)
          info "Subnets span $rest availability zone(s)"
          ;;
      esac
    done
  fi

  if [[ -n "$VALIDATE_IAM_ROLE" ]]; then
    header "V3. IAM Execution Role"
    ROLE_NAME=$(echo "$VALIDATE_IAM_ROLE" | awk -F/ '{print $NF}')
    ROLE_INFO=$(aws_check "get-role" aws iam get-role --role-name "$ROLE_NAME" --output json) || ROLE_INFO=""
    if [[ -n "$ROLE_INFO" ]]; then
      pass "IAM role exists" "$ROLE_NAME"
      TRUST_SM=$(echo "$ROLE_INFO" | python3 -c "
import sys,json
doc=json.load(sys.stdin).get('Role',{}).get('AssumeRolePolicyDocument',{})
stmts=doc.get('Statement',[])
for s in stmts:
    p=s.get('Principal',{})
    svc=p.get('Service',[]) if isinstance(p.get('Service'), list) else [p.get('Service','')]
    if 'sagemaker.amazonaws.com' in svc:
        print('true')
        break
else:
    print('false')
" 2>/dev/null)
      if [[ "$TRUST_SM" == "true" ]]; then
        pass "Trust policy" "allows sagemaker.amazonaws.com"
      else
        fail "Trust policy" "missing sagemaker.amazonaws.com — cluster creation will fail"
        add_issue "IAM execution role trust policy missing sagemaker.amazonaws.com → references/cluster-diagnostics-detail.md § H (CloudFormation Errors / SLR)" "P0"
      fi

      POLICIES=$(aws_check "list-attached-role-policies-$ROLE_NAME" \
        aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
        --query 'AttachedPolicies[*].PolicyArn' --output text) || POLICIES=""
      if [[ -n "$POLICIES" ]]; then
        if echo "$POLICIES" | grep -q "AmazonSageMakerClusterInstanceRolePolicy"; then
          pass "Managed policy" "AmazonSageMakerClusterInstanceRolePolicy attached"
        else
          warn "Managed policy" "AmazonSageMakerClusterInstanceRolePolicy not attached — cluster bootstrap will fail"
          add_issue "IAM execution role missing AmazonSageMakerClusterInstanceRolePolicy → references/cluster-diagnostics-detail.md § H (CloudFormation Errors / SLR)" "P0"
        fi
        if echo "$POLICIES" | grep -q "AmazonSSMManagedInstanceCore"; then
          pass "Managed policy" "AmazonSSMManagedInstanceCore attached (SSM access)"
        else
          warn "Managed policy" "AmazonSSMManagedInstanceCore not attached — SSM node access will not work"
          add_issue "IAM execution role missing AmazonSSMManagedInstanceCore → references/cluster-diagnostics-detail.md § F (SSM Connectivity)" "P1"
        fi
      fi
    else
      fail "IAM role" "cannot find role '$ROLE_NAME'"
      add_issue "IAM execution role not found → references/cluster-diagnostics-detail.md § H (CloudFormation Errors / SLR)" "P0"
    fi
  fi

  if [[ -n "$VALIDATE_SUBNET_IDS" ]]; then
    header "V4. VPC Endpoints"
    FIRST_SUBNET=$(echo "$VALIDATE_SUBNET_IDS" | cut -d, -f1)
    VPC_FOR_EP=$(aws ec2 describe-subnets --subnet-ids "$FIRST_SUBNET" \
      --region "$REGION" --query 'Subnets[0].VpcId' --output text 2>/dev/null || echo "")
    if [[ -n "$VPC_FOR_EP" && "$VPC_FOR_EP" != "None" ]]; then
      ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$VPC_FOR_EP" \
        --region "$REGION" \
        --query "VpcEndpoints[?State==\`available\`].ServiceName" \
        --output text 2>/dev/null || echo "")
      for SVC in s3 ssm ssmmessages ec2messages; do
        if echo "$ENDPOINTS" | grep -qE "(^|[.])${SVC}($|[[:space:]])"; then
          pass "VPC endpoint: $SVC"
        else
          warn "VPC endpoint: $SVC" "not found — needed for private VPC clusters"
          add_issue "Missing VPC endpoint for $SVC → references/cluster-diagnostics-detail.md § C (Lifecycle Scripts)" "P2"
        fi
      done
    fi
  fi

  if [[ -n "$VALIDATE_INSTANCE_TYPE" && -n "$VALIDATE_SUBNET_IDS" ]]; then
    header "V5. Instance-Type Capacity per AZ"
    # EC2 API takes the bare type, not the ml. prefix.
    EC2_TYPE="${VALIDATE_INSTANCE_TYPE#ml.}"

    AZ_OFFERINGS=$(aws_check "describe-instance-type-offerings-$EC2_TYPE" \
      aws ec2 describe-instance-type-offerings \
      --location-type availability-zone \
      --filters "Name=instance-type,Values=${EC2_TYPE}" \
      --region "$REGION" \
      --query 'InstanceTypeOfferings[*].Location' --output text) || AZ_OFFERINGS=""

    if [[ -z "$AZ_OFFERINGS" ]]; then
      fail "Instance type $VALIDATE_INSTANCE_TYPE" "not offered in region $REGION"
      add_issue "$VALIDATE_INSTANCE_TYPE is not offered in any AZ in $REGION → references/capacity-planning.md" "P0"
    else
      info "$VALIDATE_INSTANCE_TYPE available in AZ(s): $AZ_OFFERINGS"

      IFS=',' read -ra _subnet_ids <<< "$VALIDATE_SUBNET_IDS"
      SUB_AZ_JSON=$(aws_check "describe-subnets-validate" aws ec2 describe-subnets \
        --subnet-ids "${_subnet_ids[@]}" \
        --region "$REGION" \
        --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone}' --output json) || SUB_AZ_JSON="[]"

      MATCHED=0
      while IFS=$'\t' read -r sid az; do
        [[ -z "$sid" ]] && continue
        if echo "$AZ_OFFERINGS" | tr '\t' '\n' | grep -qx "$az"; then
          pass "Subnet $sid (AZ=$az)" "$VALIDATE_INSTANCE_TYPE is available"
          MATCHED=$((MATCHED+1))
        else
          fail "Subnet $sid (AZ=$az)" "$VALIDATE_INSTANCE_TYPE NOT offered here"
          add_issue "Subnet $sid AZ=$az does not offer $VALIDATE_INSTANCE_TYPE → references/capacity-planning.md" "P0"
        fi
      done < <(echo "$SUB_AZ_JSON" | python3 -c "
import sys, json
for s in json.load(sys.stdin):
    print(f\"{s.get('SubnetId','')}\t{s.get('AZ','')}\")
" 2>/dev/null)

      if [[ $MATCHED -eq 0 ]]; then
        warn "No provided subnet is in an AZ that offers $VALIDATE_INSTANCE_TYPE — cluster creation will fail with Insufficient capacity / No subnets in the capacity AZ"
      fi
    fi
  fi

  if [[ -n "$VALIDATE_S3_URI" ]]; then
    header "V6. S3 Lifecycle Scripts"
    if [[ ! "$VALIDATE_S3_URI" =~ ^s3:// ]]; then
      fail "S3 URI" "must start with s3:// (got '$VALIDATE_S3_URI')"
      add_issue "S3 URI is not a valid s3:// URI → references/lifecycle-scripts.md" "P0"
    else
      S3_URI_NORM="${VALIDATE_S3_URI%/}/"
      info "S3 URI: $S3_URI_NORM"

      S3_LIST=$(aws_check "s3-ls-$S3_URI_NORM" \
        aws s3 ls "$S3_URI_NORM" --region "$REGION") || S3_LIST=""

      if [[ -z "$S3_LIST" ]]; then
        fail "S3 access" "cannot list $S3_URI_NORM — bucket missing, permissions denied, or empty prefix"
        add_issue "S3 URI not accessible or empty: $S3_URI_NORM → references/lifecycle-scripts.md" "P0"
      else
        pass "S3 access" "prefix is listable"

        if echo "$S3_LIST" | grep -q "on_create.sh"; then
          pass "on_create.sh" "entry script present"

          TMPFILE=$(mktemp)
          if aws s3 cp "${S3_URI_NORM}on_create.sh" "$TMPFILE" \
               --region "$REGION" --only-show-errors 2>/dev/null; then
            if file "$TMPFILE" | grep -q "CRLF"; then
              fail "on_create.sh" "has Windows CRLF line endings — will fail on Linux"
              add_issue "on_create.sh has CRLF line endings → references/lifecycle-scripts.md" "P0"
            else
              pass "on_create.sh" "Unix line endings"
            fi
            if head -1 "$TMPFILE" | grep -q "^#!"; then
              pass "on_create.sh" "shebang present"
            else
              warn "on_create.sh" "missing shebang (#!/bin/bash)"
              add_issue "on_create.sh missing shebang → references/lifecycle-scripts.md" "P1"
            fi
          else
            warn "on_create.sh" "could not download for inspection"
          fi
          rm -f "$TMPFILE"
        else
          fail "on_create.sh" "entry script NOT FOUND at $S3_URI_NORM — cluster creation will fail"
          add_issue "Missing on_create.sh at $S3_URI_NORM → references/lifecycle-scripts.md" "P0"
        fi

        if   echo "$S3_LIST" | grep -q "lifecycle_script.py"; then
          pass "Orchestrator script" "lifecycle_script.py present (Slurm)"
        elif echo "$S3_LIST" | grep -q "on_create_main.sh"; then
          pass "Orchestrator script" "on_create_main.sh present (EKS)"
        else
          warn "Orchestrator script" "neither lifecycle_script.py (Slurm) nor on_create_main.sh (EKS) found at $S3_URI_NORM"
          add_issue "Missing orchestrator-specific lifecycle script at $S3_URI_NORM → references/lifecycle-scripts.md" "P1"
        fi
      fi
    fi
  fi

  echo ""
  echo -e "${BOLD}========================================${NC}"
  echo -e "${BOLD}       VALIDATION SUMMARY               ${NC}"
  echo -e "${BOLD}========================================${NC}"
  echo ""
  echo -e "  Results: ${RED}${CRITICAL_FAILURES} critical${NC} | ${YELLOW}${WARNINGS} warnings${NC}"
  echo -e "  Mode:    READ-ONLY (no changes made; each [FAIL] points to a references section)"
  echo ""
  if [[ ${#ISSUES_FOUND[@]} -gt 0 ]]; then
    echo -e "${BOLD}  Issues:${NC}"
    for priority in P0 P1 P2; do
      for issue in "${ISSUES_FOUND[@]}"; do
        if [[ "$issue" == "${priority}|"* ]]; then
          desc="${issue#*|}"
          case "$priority" in
            P0) echo -e "    ${RED}[${priority}]${NC} $desc" ;;
            P1) echo -e "    ${YELLOW}[${priority}]${NC} $desc" ;;
            P2) echo -e "    [${priority}] $desc" ;;
          esac
        fi
      done
    done
    echo ""
  fi
  if [[ $CRITICAL_FAILURES -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}Pre-flight validation passed. Safe to create cluster.${NC}"
  else
    echo -e "  ${RED}${BOLD}Fix P0 issues above before creating the cluster.${NC}"
  fi
  echo ""
  exit "$([[ $CRITICAL_FAILURES -eq 0 ]] && echo 0 || echo 1)"
fi

section "HyperPod Cluster Diagnostics (read-only)"
echo -e "Cluster: ${BOLD}${CLUSTER}${NC}"
echo -e "Region:  ${BOLD}${REGION}${NC}"
echo -e "Time:    $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo -e "${CYAN}   No cluster state will be modified. Each issue line below includes a${NC}"
echo -e "${CYAN}   pointer to references/cluster-diagnostics-detail.md for remediation.${NC}"

header "1. Cluster Identity & Status"

CLUSTER_JSON=$(aws sagemaker describe-cluster \
  --cluster-name "$CLUSTER" \
  --region "$REGION" \
  --cli-read-timeout 30 \
  --output json 2>&1) || {
  echo -e "${RED}ERROR: Could not describe cluster '$CLUSTER' in region '$REGION'${NC}"
  echo "$CLUSTER_JSON" | head -3
  echo ""
  if echo "$CLUSTER_JSON" | grep -qiE "ResourceNotFound|Cluster with name .* not found"; then
    echo "Available clusters in $REGION:"
    aws sagemaker list-clusters --region "$REGION" \
      --query 'ClusterSummaries[*].{Name:ClusterName,Status:ClusterStatus}' \
      --output table 2>/dev/null || echo "  (unable to list clusters — check IAM)"
  else
    echo "Verify:"
    echo "  1. Cluster name is correct (use: aws sagemaker list-clusters --region $REGION)"
    echo "  2. Region is correct"
    echo "  3. IAM permissions include sagemaker:DescribeCluster"
  fi
  exit 1
}

CLUSTER_ARN=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ClusterArn',''))" 2>/dev/null)
CLUSTER_ID=$(echo "$CLUSTER_ARN" | awk -F'/' '{print $NF}')
if [[ -z "$CLUSTER_ID" ]]; then
  echo "ERROR: Could not extract cluster ID from ARN '$CLUSTER_ARN'. Verify the cluster name/ARN."
  exit 1
fi
CLUSTER_STATUS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ClusterStatus','unknown'))" 2>/dev/null)
ORCHESTRATOR=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); o=d.get('Orchestrator',{}); print('EKS' if 'Eks' in o else 'Slurm')" 2>/dev/null)
NODE_RECOVERY=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
# Prefer cluster-level NodeRecovery (the API's canonical location); fall back to
# per-InstanceGroup only when top-level is absent. Reading only per-group yields
# 'Unknown' on every cluster because the field is null at group level when set
# cluster-wide.
top=d.get('NodeRecovery')
if top:
    print(top)
else:
    groups=d.get('InstanceGroups',[])
    recoveries={g.get('NodeRecovery') for g in groups if g.get('NodeRecovery')}
    print(','.join(sorted(recoveries)) if recoveries else 'Unknown')
" 2>/dev/null || echo "Unknown")

info "ARN:          $CLUSTER_ARN"
info "Cluster ID:   $CLUSTER_ID"
info "Status:       $CLUSTER_STATUS"
info "Orchestrator: $ORCHESTRATOR"
info "NodeRecovery: $NODE_RECOVERY"

# Flag auto-recovery disabled regardless of orchestrator.
if [[ "$NODE_RECOVERY" == *"None"* && "$NODE_RECOVERY" == *"Automatic"* ]]; then
  warn "NodeRecovery" "mixed settings — some instance groups have recovery disabled"
  add_issue "NodeRecovery disabled on some instance groups → references/cluster-diagnostics-detail.md § G (Node Replacement)" "P2"
elif [[ "$NODE_RECOVERY" == *"None"* ]]; then
  warn "NodeRecovery" "disabled on all instance groups — auto-replacement won't trigger"
  add_issue "NodeRecovery disabled → references/cluster-diagnostics-detail.md § G (Node Replacement)" "P2"
fi

CREATION_TIME=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ct=d.get('CreationTime','')
print(ct if ct else '')
" 2>/dev/null || echo "")

LAST_MODIFIED_TIME=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
lm=d.get('LastModifiedTime','')
print(lm if lm else '')
" 2>/dev/null || echo "")

STUCK_THRESHOLD_SECONDS=3600

is_stuck() {
  local creation_time="$1"
  if [[ -z "$creation_time" ]]; then echo "false"; return; fi
  CREATION_TS="$creation_time" THRESHOLD="$STUCK_THRESHOLD_SECONDS" python3 -c "
import os
from datetime import datetime, timezone
ct = os.environ['CREATION_TS']
threshold = int(os.environ['THRESHOLD'])
try:
    ct=ct.replace('+00:00','Z').rstrip('Z')
    if '.' in ct: ct=ct[:ct.index('.')+7]
    created=datetime.fromisoformat(ct).replace(tzinfo=timezone.utc)
    elapsed=(datetime.now(timezone.utc)-created).total_seconds()
    print('true' if elapsed > threshold else 'false')
except (ValueError, TypeError):
    # Unparseable timestamp — assume not stuck rather than abort the whole run.
    print('false')
" 2>/dev/null || echo "false"
}

case "$CLUSTER_STATUS" in
  InService)    pass "Cluster status" "InService" ;;
  Creating)
    STUCK=$(is_stuck "$CREATION_TIME")
    if [[ "$STUCK" == "true" ]]; then
      fail "Cluster status" "Creating for over 1 hour — likely stuck"
      add_issue "Cluster stuck in Creating > 1hr → references/cluster-diagnostics-detail.md § E (Cluster Provisioning), § H (CloudFormation)" "P0"
    else
      warn "Cluster status" "Creating — cluster is still being provisioned"
      add_issue "Cluster still creating → references/cluster-diagnostics-detail.md § E (Cluster Provisioning)" "P1"
    fi ;;
  Updating)
    STUCK=$(is_stuck "${LAST_MODIFIED_TIME:-$CREATION_TIME}")
    if [[ "$STUCK" == "true" ]]; then
      fail "Cluster status" "Updating — check if operation is stuck"
      add_issue "Cluster may be stuck Updating → references/cluster-diagnostics-detail.md § E (Cluster Provisioning), § H (CloudFormation)" "P1"
    else
      warn "Cluster status" "Updating — cluster operation in progress"
    fi ;;
  Failed)       fail "Cluster status" "Failed — check events and CloudFormation"; add_issue "Cluster FAILED → references/cluster-diagnostics-detail.md § E (Cluster Provisioning), § H (CloudFormation)" "P0" ;;
  Deleting)
    STUCK=$(is_stuck "${LAST_MODIFIED_TIME:-$CREATION_TIME}")
    if [[ "$STUCK" == "true" ]]; then
      warn "Cluster status" "Deleting for extended time — may be blocked by VPC ENI dependencies"
      add_issue "Cluster stuck Deleting → references/cluster-diagnostics-detail.md § E (Cluster Provisioning)" "P1"
    else
      warn "Cluster status" "Deleting"
    fi ;;
  RollingBack)  warn "Cluster status" "RollingBack — update is being rolled back"; add_issue "Cluster RollingBack → references/cluster-diagnostics-detail.md § J (AMI & Cluster Updates)" "P1" ;;
  *RollbackFailed*|*MaintenanceFailed*)
    fail "Cluster status" "$CLUSTER_STATUS — cluster is stuck in a non-recoverable state"
    add_issue "Cluster stuck in $CLUSTER_STATUS → references/cluster-diagnostics-detail.md § J (AMI & Cluster Updates)" "P0" ;;
  *)            warn "Cluster status" "$CLUSTER_STATUS" ;;
esac

EKS_NAME=""
if [[ "$ORCHESTRATOR" == "EKS" ]]; then
  EKS_NAME=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
arn=d.get('Orchestrator',{}).get('Eks',{}).get('ClusterArn','')
print(arn.split('/')[-1] if arn else '')
" 2>/dev/null || echo "")
  if [[ -n "$EKS_NAME" ]]; then
    info "EKS Cluster:  $EKS_NAME"
  fi
fi

header "2. Instance Groups & Node Health"

echo "$CLUSTER_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
groups = d.get('InstanceGroups', [])
if not groups:
    print('  No instance groups found')
else:
    for g in groups:
        name = g.get('InstanceGroupName', '?')
        itype = g.get('InstanceType', '?')
        target = g.get('TargetCount', 0)
        current = g.get('CurrentCount', 0)
        status = g.get('Status', g.get('InstanceGroupStatus', '?'))
        threads = g.get('ThreadsPerCore', '?')
        # TargetStateCount is the count the service is working toward when a
        # resize is in flight; print when it differs from TargetCount.
        tstate = g.get('TargetStateCount', None)
        # Note: NodeRecovery is a cluster-level field in the DescribeCluster
        # response, not per-group; shown on the cluster header line above.
        print(f'  {name}: type={itype} target={target} current={current} status={status} threads/core={threads}')
        if tstate is not None and tstate != target:
            print(f'    TargetStateCount={tstate} (resize in progress)')
        if current < target:
            print(f'    Current count ({current}) < target ({target}) — instances may still be provisioning or failed')
" 2>/dev/null

# Check node-level details. Paginate — default page is small and large clusters
# silently truncate, which would break dangling-node reconciliation below.
fetch_all_cluster_nodes_cd() {
  local merged='[]' token='' page_json combined i=0
  local max_pages=200  # 200 × 100 = 20 000 nodes, supports 7k+ clusters
  while (( i < max_pages )); do
    if [[ -n "$token" ]]; then
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
    if echo "$page_json" | grep -qiE "AccessDenied|not authorized|UnauthorizedAccess"; then
      echo "__AUTH_DENIED__"
      return 1
    fi
    # Merge via stdin (NUL-delimited blobs) instead of argv — argv is capped at
    # ARG_MAX (~128KB on Linux), which fails at ~500 nodes of accumulated JSON.
    # Large clusters (7k+) need this path to avoid silent truncation.
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
print(page.get('NextToken', ''))
" 2>/dev/null) || break
    merged=$(printf '%s\n' "$combined" | sed -n '1p')
    token=$(printf '%s\n'  "$combined" | sed -n '2p')
    i=$((i+1))
    [[ -z "$token" ]] && break
  done
  if (( i == max_pages )) && [[ -n "$token" ]]; then
    # Surface truncation via a marker file — this function runs inside $(...)
    # (command substitution subshell), so add_issue would be lost. The parent
    # shell checks for the marker after the call returns.
    echo "WARN: list-cluster-nodes truncated at ${max_pages} pages (~$((max_pages*100)) nodes). Diagnostic sample is incomplete for very large clusters." >&2
    : > "${_NODE_TRUNC_MARKER:-/dev/null}" 2>/dev/null || true
  fi
  printf '%s' "$merged" | python3 -c "
import sys, json
try:
    print(json.dumps({'ClusterNodeSummaries': json.loads(sys.stdin.read())}))
except json.JSONDecodeError:
    print('{\"ClusterNodeSummaries\":[]}')
" 2>/dev/null || echo '{"ClusterNodeSummaries":[]}'
}

_NODE_TRUNC_MARKER=$(mktemp 2>/dev/null) && _CD_TEMP_FILES+=("$_NODE_TRUNC_MARKER") || _NODE_TRUNC_MARKER=""
export _NODE_TRUNC_MARKER
rm -f "$_NODE_TRUNC_MARKER" 2>/dev/null || true

NODE_LIST=$(fetch_all_cluster_nodes_cd)
if [[ "$NODE_LIST" == "__AUTH_DENIED__" ]]; then
  warn "list-cluster-nodes" "IAM permission denied — add sagemaker:ListClusterNodes to your role"
  add_issue "Missing IAM permission for sagemaker:ListClusterNodes → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)" "P1"
  NODE_LIST='{"ClusterNodeSummaries":[]}'
fi

# Parent-shell follow-up for the truncation marker set inside the subshell.
if [[ -n "$_NODE_TRUNC_MARKER" && -e "$_NODE_TRUNC_MARKER" ]]; then
  add_issue "Node list truncated at 200 pages (~20000 nodes); diagnostic sample incomplete → references/cluster-diagnostics-detail.md § E (Cluster Provisioning)" "P2"
fi

TOTAL_NODES=$(echo "$NODE_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('ClusterNodeSummaries',[])))" 2>/dev/null || echo 0)
info "Total nodes reported: $TOTAL_NODES"

UNHEALTHY_NODES=$(echo "$NODE_LIST" | python3 -c "
import sys, json
nodes = json.load(sys.stdin).get('ClusterNodeSummaries', [])
unhealthy = [n for n in nodes if n.get('InstanceStatus', {}).get('Status', '') not in ('Running', 'Pending')]
if unhealthy:
    for n in unhealthy:
        nid = n.get('InstanceId', '?')
        group = n.get('InstanceGroupName', '?')
        status = n.get('InstanceStatus', {}).get('Status', '?')
        msg = n.get('InstanceStatus', {}).get('Message', '')
        print(f'  {nid} ({group}): {status} {msg}')
    print(f'UNHEALTHY_COUNT={len(unhealthy)}')
else:
    print('UNHEALTHY_COUNT=0')
" 2>/dev/null || echo "UNHEALTHY_COUNT=0")

UNHEALTHY_COUNT=$(echo "$UNHEALTHY_NODES" | grep "^UNHEALTHY_COUNT=" | cut -d= -f2)
[[ -z "$UNHEALTHY_COUNT" ]] && UNHEALTHY_COUNT=0
echo "$UNHEALTHY_NODES" | grep -v "^UNHEALTHY_COUNT=" || true

if [[ "$UNHEALTHY_COUNT" -gt 0 ]]; then
  warn "Node health" "$UNHEALTHY_COUNT unhealthy node(s)"
  add_issue "$UNHEALTHY_COUNT unhealthy node(s) → references/cluster-diagnostics-detail.md § G (Node Replacement); delegate to hyperpod-node-debugger" "P1"

  echo "$NODE_LIST" | python3 -c "
import sys, json
from collections import defaultdict
nodes = json.load(sys.stdin).get('ClusterNodeSummaries', [])
groups = defaultdict(lambda: {'total': 0, 'unhealthy': 0})
for n in nodes:
    g = n.get('InstanceGroupName', 'unknown')
    groups[g]['total'] += 1
    st = n.get('InstanceStatus', {}).get('Status', '')
    if st not in ('Running', 'Pending', ''):
        groups[g]['unhealthy'] += 1
for g, c in groups.items():
    if c['unhealthy'] > 0:
        pct = int(c['unhealthy'] / c['total'] * 100) if c['total'] > 0 else 0
        print(f'  [WARN] Group {g}: {c[\"unhealthy\"]}/{c[\"total\"]} unhealthy ({pct}%)')
" 2>/dev/null

elif [[ "$TOTAL_NODES" -eq 0 && "$CLUSTER_STATUS" == "InService" ]]; then
  warn "Node health" "Cluster InService but 0 nodes reported"
  add_issue "Cluster InService but no nodes → references/cluster-diagnostics-detail.md § E (Cluster Provisioning)" "P1"
else
  pass "Node health" "$TOTAL_NODES node(s), $UNHEALTHY_COUNT unhealthy"
fi

header "3. Cluster Events (Recent)"

# Paginate up to 5 pages (500 events) so the event scan covers incident windows
# longer than the default page. Long-lived clusters with rolling replacements
# regularly generate >100 events.
fetch_cluster_events_cd() {
  local merged='[]' token='' page_json combined i=0 denied=0
  while (( i < 5 )); do
    if [[ -n "$token" ]]; then
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
    if echo "$page_json" | grep -qi "AccessDenied\|not authorized"; then
      denied=1
      break
    fi
    combined=$(python3 -c "
import sys, json
try:
    prev = json.loads(sys.argv[1])
    page = json.loads(sys.argv[2])
except json.JSONDecodeError:
    # Malformed page response — stop paginating; caller falls through on break.
    sys.exit(2)
prev.extend(page.get('ClusterEventSummaries', []))
print(json.dumps(prev))
print(page.get('NextToken',''))
" "$merged" "$page_json" 2>/dev/null) || break

    merged=$(printf '%s\n' "$combined" | sed -n '1p')

    token=$(printf '%s\n'  "$combined" | sed -n '2p')
    i=$((i+1))
    [[ -z "$token" ]] && break
  done
  if (( denied )); then
    echo "__AUTH_DENIED__"
    return 1
  fi
  python3 -c "import sys, json; print(json.dumps({'ClusterEventSummaries': json.loads(sys.argv[1])}))" "$merged" \
    2>/dev/null || echo '{"ClusterEventSummaries":[]}'
}

EVENTS_JSON=$(fetch_cluster_events_cd)
if [[ "$EVENTS_JSON" == "__AUTH_DENIED__" ]]; then
  warn "list-cluster-events" "IAM permission denied — add sagemaker:ListClusterEvents to your role"
  EVENTS_JSON='{"ClusterEventSummaries":[]}'
fi

EVENT_COUNT=$(echo "$EVENTS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('ClusterEventSummaries',[])))" 2>/dev/null || echo 0)

if [[ "$EVENT_COUNT" -eq 0 ]]; then
  info "No cluster events found"
  if [[ "$ORCHESTRATOR" == "Slurm" ]]; then
    info "(Cluster events may not be available for HyperPod Slurm clusters)"
  fi
else
  echo "$EVENTS_JSON" | python3 -c "
import sys, json
events = json.load(sys.stdin).get('ClusterEventSummaries', [])

# Issue pattern mapping
ISSUE_PATTERNS = {
    'EFA health checks': 'EFA health check failure → references/cluster-diagnostics-detail.md § A',
    'Insufficient capacity': 'Capacity error → references/cluster-diagnostics-detail.md § B',
    'No subnets in the capacity': 'AZ/subnet mismatch → references/cluster-diagnostics-detail.md § B',
    'Lifecycle scripts did not run': 'Lifecycle script failure → references/cluster-diagnostics-detail.md § C',
    'Lifecycle scripts execution timed out': 'Lifecycle script timeout → references/cluster-diagnostics-detail.md § C',
    'network misconfiguration': 'Network misconfiguration → references/cluster-diagnostics-detail.md § A + § B',
    'hardware failure': 'Hardware failure → delegate to node-debugger',
    'Failed to provision': 'Provisioning failure → references/cluster-diagnostics-detail.md § B or § E',
    'replace': 'Node replacement activity → references/cluster-diagnostics-detail.md § G',
    'reboot': 'Node reboot activity → references/cluster-diagnostics-detail.md § G',
}

for e in events[:20]:
    ts = str(e.get('EventTime', '?'))[:19]
    etype = e.get('EventType', '?')
    msg = e.get('Message', '?')[:120]
    print(f'  [{ts}] {etype}: {msg}')

    msg_lower = (e.get('Message','') or '').lower()
    for pattern, hint in ISSUE_PATTERNS.items():
        if pattern.lower() in msg_lower:
            print(f'    [ISSUE] {hint}')
            break
" 2>/dev/null
fi

header "4. VPC & Security Group Configuration"

SUBNET_IDS=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' '.join(d.get('VpcConfig',{}).get('Subnets',[])))
" 2>/dev/null || echo "")

SG_IDS=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' '.join(d.get('VpcConfig',{}).get('SecurityGroupIds',[])))
" 2>/dev/null || echo "")

if [[ -z "$SUBNET_IDS" ]]; then
  warn "VpcConfig" "No VpcConfig found in cluster"
else
  info "Subnets: $SUBNET_IDS"
  info "Security Groups: $SG_IDS"

  IFS=' ' read -ra _subnet_ids_arr <<< "$SUBNET_IDS"
  SUBNET_JSON=$(aws ec2 describe-subnets \
    --subnet-ids "${_subnet_ids_arr[@]}" \
    --region "$REGION" \
    --cli-read-timeout 30 \
    --output json 2>&1) || {
    SUB_ERR="$SUBNET_JSON"
    if echo "$SUB_ERR" | grep -qi "AccessDenied\|UnauthorizedOperation\|not authorized"; then
      warn "describe-subnets" "IAM permission denied — add ec2:DescribeSubnets to your role"
    fi
    SUBNET_JSON='{"Subnets":[]}'
  }

  _SUBNET_CHECK=$(echo "$SUBNET_JSON" | python3 -c "
import sys, json
subnets = json.load(sys.stdin).get('Subnets', [])
vpcs = set()
for s in subnets:
    sid = s.get('SubnetId', '?')
    vpc = s.get('VpcId', '?')
    az = s.get('AvailabilityZone', '?')
    free = s.get('AvailableIpAddressCount', 0)
    flag = ' LOW IPs' if free < 10 else ''
    print(f'  {sid}: VPC={vpc} AZ={az} FreeIPs={free}{flag}')
    vpcs.add(vpc)
if len(vpcs) > 1:
    print('MULTI_VPC=true')
    print('VPC_LIST=' + ','.join(vpcs))
else:
    print('MULTI_VPC=false')
    v = vpcs.pop() if vpcs else '?'
    print('VPC_ID=' + v)
" 2>/dev/null || echo "")

  while IFS= read -r line; do
    if [[ "$line" == "MULTI_VPC=true" ]]; then
      fail "Subnet VPC alignment" "Subnets are in DIFFERENT VPCs — all must be in the same VPC"
      add_issue "Subnets in different VPCs → references/cluster-diagnostics-detail.md § B (Capacity & AZ)" "P0"
    fi
    if [[ "$line" != MULTI_VPC=* && "$line" != VPC_ID=* && "$line" != VPC_LIST=* ]]; then
      echo "$line"
    fi
  done <<< "$_SUBNET_CHECK"

  # SG self-referencing rules are an EFA requirement.
  # shellcheck disable=SC2086  # intentional word-split on space-separated SG IDs
  for SG in $SG_IDS; do
    SG_RESULT=$(aws ec2 describe-security-groups \
      --group-ids "$SG" \
      --region "$REGION" \
      --cli-read-timeout 30 \
      --output json 2>&1)
    if echo "$SG_RESULT" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
      warn "describe-security-groups" "IAM permission denied for $SG — SG check skipped"
      continue
    fi
    SG_JSON="${SG_RESULT}"
    [[ -z "$SG_JSON" || "$SG_JSON" == *"error"* ]] && SG_JSON='{"SecurityGroups":[]}'

    _SG_CHECK=$(echo "$SG_JSON" | check_sg_self_ref "$SG")

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      level=$(echo "$line" | cut -d: -f1)
      msg=$(echo "$line" | cut -d: -f2-)
      case "$level" in
        PASS) pass "$msg" ;;
        FAIL) fail "$msg"
              if echo "$msg" | grep -q "Inbound self-ref MISSING"; then
                add_issue "Security group $SG inbound self-ref MISSING → references/cluster-diagnostics-detail.md § A (EFA Health Checks)" "P0"
              elif echo "$msg" | grep -q "Outbound self-ref MISSING"; then
                add_issue "Security group $SG outbound self-ref MISSING → references/cluster-diagnostics-detail.md § A (EFA Health Checks)" "P0"
              elif echo "$msg" | grep -q "Outbound 0.0.0.0/0 missing"; then
                add_issue "Security group $SG outbound 0.0.0.0/0 MISSING → references/cluster-diagnostics-detail.md § A (EFA Health Checks)" "P0"
              else
                add_issue "Security group $SG rule missing → references/cluster-diagnostics-detail.md § A (EFA Health Checks)" "P0"
              fi
              ;;
        WARN) warn "$msg" ;;
        SKIP) info "$msg" ;;
      esac
    done <<< "$_SG_CHECK"
  done
fi

header "4b. Instance Quotas"

INSTANCE_TYPES=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
types=set(g.get('InstanceType','') for g in d.get('InstanceGroups',[]))
print(' '.join(t for t in types if t))
" 2>/dev/null || echo "")

if [[ -n "$INSTANCE_TYPES" ]]; then
  # One paginated list-service-quotas call, cached across all instance types.
  # The API is account/region rate-limited and throttles if called per-type.
  QUOTA_ALL=""
  QUOTA_ERR=""
  _next=""
  for _pg in 1 2 3 4 5; do
    if [[ -n "$_next" ]]; then
      _raw=$(aws service-quotas list-service-quotas \
        --service-code sagemaker --region "$REGION" \
        --cli-read-timeout 15 --starting-token "$_next" \
        --output json 2>&1 || true)
    else
      _raw=$(aws service-quotas list-service-quotas \
        --service-code sagemaker --region "$REGION" \
        --cli-read-timeout 15 \
        --output json 2>&1 || true)
    fi
    # Order matters: test for specific errors first, then fall through to
    # generic "not JSON" check, so throttled responses don't get misclassified.
    if echo "$_raw" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
      QUOTA_ERR="denied"; break
    elif echo "$_raw" | grep -qiE "TooManyRequestsException|ThrottlingException|RequestLimitExceeded|exceeded the rate"; then
      QUOTA_ERR="throttled"; break
    elif ! echo "$_raw" | head -c 1 | grep -q '{'; then
      QUOTA_ERR="api-error"; break
    fi
    _pg_quotas=$(echo "$_raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('Quotas',[])))" 2>/dev/null || echo "[]")
    if [[ "$_pg_quotas" != "[]" ]]; then
      if [[ -z "$QUOTA_ALL" ]]; then
        QUOTA_ALL="$_pg_quotas"
      else
        QUOTA_ALL=$(python3 -c "import sys,json; a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2]); print(json.dumps(a+b))" "$QUOTA_ALL" "$_pg_quotas")
      fi
    fi
    _next=$(echo "$_raw" | python3 -c "import sys,json; print(json.load(sys.stdin).get('NextToken','') or '')" 2>/dev/null || echo "")
    [[ -z "$_next" ]] && break
  done

  case "$QUOTA_ERR" in
    denied)    warn "list-service-quotas" "IAM permission denied — quota check skipped" ;;
    throttled) warn "list-service-quotas" "Throttled — quota check skipped (retry later)" ;;
    api-error) warn "list-service-quotas" "API call failed — quota check skipped" ;;
  esac

  if [[ -n "$QUOTA_ALL" && -z "$QUOTA_ERR" ]]; then
    for ITYPE in $INSTANCE_TYPES; do
      QUOTA_VAL=$(python3 -c "
import sys, json
quotas = json.loads(sys.argv[1])
itype = sys.argv[2]
# Match quotas that reference the instance type AND HyperPod
matches = [q for q in quotas if itype in q.get('QuotaName','') and 'HyperPod' in q.get('QuotaName','')]
if matches:
    q = matches[0]
    print(f\"{q.get('QuotaName','?')}: {int(q.get('Value',0))}\")
else:
    print('NOT_FOUND')
" "$QUOTA_ALL" "$ITYPE" 2>/dev/null || echo "NOT_FOUND")
      if [[ "$QUOTA_VAL" == "NOT_FOUND" ]]; then
        info "Quota for $ITYPE: not found in the SageMaker quota list (check Service Quotas console)"
      else
        info "Quota: $QUOTA_VAL"
      fi
    done
  fi
else
  info "No instance types found in cluster config"
fi

if [[ "$ORCHESTRATOR" == "EKS" && -n "$EKS_NAME" ]]; then
  header "5. EKS Configuration"

  EKS_AUTH=$(aws eks describe-cluster \
    --name "$EKS_NAME" \
    --region "$REGION" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "unknown")

  if [[ "$EKS_AUTH" == "CONFIG_MAP" ]]; then
    warn "EKS auth mode" "CONFIG_MAP-only — access entries require API or API_AND_CONFIG_MAP"
    add_issue "EKS auth mode is CONFIG_MAP — access entries unavailable until switched (see EKS access-entries docs) → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)" "P2"
  elif [[ "$EKS_AUTH" == "API" || "$EKS_AUTH" == "API_AND_CONFIG_MAP" ]]; then
    pass "EKS auth mode" "$EKS_AUTH"
  else
    warn "EKS auth mode" "Could not determine ($EKS_AUTH)"
  fi

  # Check access entries for current identity. AWS CLI paginates JSON output by
  # token, so paginate explicitly to handle accounts with many principals.
  info "Current IAM identity: $CALLER_ARN"

  fetch_all_access_entries() {
    local merged='[]' token='' page_json combined i=0
    while (( i < 20 )); do
      if [[ -n "$token" ]]; then
        page_json=$(aws eks list-access-entries --cluster-name "$EKS_NAME" --region "$REGION" \
          --next-token "$token" --output json 2>/dev/null) || break
      else
        page_json=$(aws eks list-access-entries --cluster-name "$EKS_NAME" --region "$REGION" \
          --output json 2>/dev/null) || break
      fi
      combined=$(python3 -c "
import sys, json
prev = json.loads(sys.argv[1])
page = json.loads(sys.argv[2])
prev.extend(page.get('accessEntries', []))
print(json.dumps(prev))
print(page.get('nextToken',''))
" "$merged" "$page_json" 2>/dev/null) || break

      merged=$(printf '%s\n' "$combined" | sed -n '1p')

      token=$(printf '%s\n'  "$combined" | sed -n '2p')
      i=$((i+1))
      [[ -z "$token" ]] && break
    done
    echo "$merged"
  }
  ACCESS_ENTRIES=$(fetch_all_access_entries)
  [[ -z "$ACCESS_ENTRIES" ]] && ACCESS_ENTRIES='[]'

  ENTRY_COUNT=$(echo "$ACCESS_ENTRIES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  info "Access entries: $ENTRY_COUNT configured"

  # Strip session name for role-based ARNs
  CALLER_BASE=$(echo "$CALLER_ARN" | python3 -c "
import sys
arn = sys.stdin.read().strip()
# Convert assumed-role ARN to role ARN for matching
# arn:aws:sts::ACCOUNT:assumed-role/ROLE/SESSION -> arn:aws:iam::ACCOUNT:role/ROLE
if ':assumed-role/' in arn:
    parts = arn.split(':')
    role_path = parts[-1].replace('assumed-role/', 'role/')
    role_path = '/'.join(role_path.split('/')[:2])  # remove session name
    parts[-1] = role_path
    parts[2] = 'iam'
    parts[3] = ''  # IAM ARNs have no region
    print(':'.join(parts))
else:
    print(arn)
" 2>/dev/null || echo "$CALLER_ARN")

  HAS_ACCESS=$(echo "$ACCESS_ENTRIES" | CALLER_BASE_ENV="$CALLER_BASE" python3 -c "
import sys, json, os
entries = json.load(sys.stdin)
caller = os.environ['CALLER_BASE_ENV']
found = any(caller in str(e) for e in entries)
print('true' if found else 'false')
" 2>/dev/null || echo "false")

  if [[ "$HAS_ACCESS" == "true" ]]; then
    pass "EKS access entry" "current identity has an access entry"
  else
    warn "EKS access entry" "current identity ($CALLER_BASE) may not have an access entry — kubectl may fail"
    add_issue "Current IAM identity may lack EKS access → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)" "P1"
  fi

  if command -v kubectl &>/dev/null; then
    KUBECTL_TEST=$(kubectl cluster-info 2>&1 || true)
    if echo "$KUBECTL_TEST" | grep -q "Kubernetes control plane\|running at"; then
      pass "kubectl connectivity" "can reach EKS API server"

      if kubectl get namespace aws-hyperpod &>/dev/null 2>&1; then
        pass "aws-hyperpod namespace" "exists"
      else
        warn "aws-hyperpod namespace" "missing → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)"
      fi

      # Node count. Note: `wc -l` never fails; avoid `|| echo 0` which would produce "0\n0".
      K8S_NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
      K8S_NODE_COUNT=${K8S_NODE_COUNT:-0}
      info "Kubernetes nodes visible: $K8S_NODE_COUNT"

      if [[ "$K8S_NODE_COUNT" -eq 0 && "$TOTAL_NODES" -gt 0 ]]; then
        warn "K8s nodes" "0 K8s nodes but $TOTAL_NODES HyperPod nodes — nodes may not have registered with EKS"
        add_issue "Nodes not visible in kubectl → references/cluster-diagnostics-detail.md § E (Cluster Provisioning)" "P1"
      fi

      HEALTH_LABELS=$(kubectl get nodes -o custom-columns='NODE:.metadata.name,HEALTH:.metadata.labels.sagemaker\.amazonaws\.com/node-health-status' --no-headers 2>/dev/null || true)
      if [[ -n "$HEALTH_LABELS" ]]; then
        UNHEALTHY_K8S=$(echo "$HEALTH_LABELS" | grep -v "<none>" | grep -viE "Schedulable$" || true)
        if [[ -n "$UNHEALTHY_K8S" ]]; then
          warn "EKS node health labels" "non-schedulable nodes detected:"
          echo "$UNHEALTHY_K8S" | while IFS= read -r line; do info "  $line"; done
          add_issue "EKS nodes with health issues → delegate to hyperpod-node-debugger skill; references/cluster-diagnostics-detail.md § G (Node Replacement)" "P1"
        else
          pass "EKS node health labels" "all nodes schedulable"
        fi
      fi

      # Dangling node detection — nodes visible in EKS but not in HyperPod list
      # (or vice versa). Happens after failed scale-up, rollback, or orphaned
      # kubelet registrations.
      if [[ "$K8S_NODE_COUNT" -gt 0 && "$TOTAL_NODES" -gt 0 ]]; then
        HP_INSTANCES=$(echo "$NODE_LIST" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    iid=n.get('InstanceId','')
    if iid: print(iid)
" 2>/dev/null | sort -u)
        EKS_INSTANCES=$(kubectl get nodes -l sagemaker.amazonaws.com/compute-type=hyperpod \
          -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}' 2>/dev/null \
          | awk -F/ '{print $NF}' | grep -E '^i-' | sort -u || true)
        if [[ -n "$HP_INSTANCES" && -n "$EKS_INSTANCES" ]]; then
          DANGLING=$(comm -13 <(echo "$HP_INSTANCES") <(echo "$EKS_INSTANCES"))
          ORPHANED=$(comm -23 <(echo "$HP_INSTANCES") <(echo "$EKS_INSTANCES"))
          if [[ -n "$DANGLING" ]]; then
            warn "Dangling nodes" "visible in EKS but not in HyperPod ($(echo "$DANGLING" | wc -l))"
            echo "$DANGLING" | head -5 | while IFS= read -r iid; do info "  EKS-only: $iid"; done
            add_issue "Dangling EKS nodes (present in kubectl, absent from list-cluster-nodes) → references/cluster-diagnostics-detail.md § K (Dangling Nodes & Cleanup)" "P1"
          fi
          if [[ -n "$ORPHANED" ]]; then
            warn "Orphaned HyperPod nodes" "visible in HyperPod but not in EKS ($(echo "$ORPHANED" | wc -l))"
            echo "$ORPHANED" | head -5 | while IFS= read -r iid; do info "  HyperPod-only: $iid"; done
            add_issue "HyperPod nodes not registered in EKS → references/cluster-diagnostics-detail.md § E (Cluster Provisioning); delegate to hyperpod-node-debugger" "P1"
          fi
          [[ -z "$DANGLING" && -z "$ORPHANED" ]] && pass "Node reconciliation" "EKS and HyperPod views match"
        fi
      fi

      # EKS add-on health — VPC CNI, CoreDNS, kube-proxy failures break pod networking.
      # Add-on count is small in practice (<10) so a single page of 100 is always sufficient.
      if [[ -n "$EKS_NAME" ]]; then
        ADDON_JSON=$(aws eks list-addons --cluster-name "$EKS_NAME" --region "$REGION" \
          --max-results 100 --output json 2>/dev/null || echo '{"addons":[]}')
        ADDON_NAMES=$(echo "$ADDON_JSON" | python3 -c "
import sys,json
print('\n'.join(json.load(sys.stdin).get('addons',[])))
" 2>/dev/null)
        DEGRADED_ADDONS=""
        while IFS= read -r addon; do
          [[ -z "$addon" ]] && continue
          A_STATUS=$(aws eks describe-addon --cluster-name "$EKS_NAME" --addon-name "$addon" \
            --region "$REGION" --query 'addon.status' --output text 2>/dev/null || echo "UNKNOWN")
          if [[ "$A_STATUS" != "ACTIVE" && "$A_STATUS" != "UPDATING" ]]; then
            DEGRADED_ADDONS+="$addon($A_STATUS) "
          fi
        done <<< "$ADDON_NAMES"
        if [[ -n "$DEGRADED_ADDONS" ]]; then
          warn "EKS add-ons" "not ACTIVE: $DEGRADED_ADDONS"
          add_issue "EKS add-on(s) degraded: $DEGRADED_ADDONS → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)" "P1"
        else
          [[ -n "$ADDON_NAMES" ]] && pass "EKS add-ons" "$(echo "$ADDON_NAMES" | wc -l) add-on(s) ACTIVE"
        fi
      fi

      # aws-auth ConfigMap legacy check — deprecated but still load-bearing if cluster auth mode
      # is API_AND_CONFIG_MAP or CONFIG_MAP. Misconfigured entries here can shadow access entries.
      if [[ -n "$EKS_NAME" ]]; then
        AUTH_MODE=$(aws eks describe-cluster --name "$EKS_NAME" --region "$REGION" \
          --query 'cluster.accessConfig.authenticationMode' --output text 2>/dev/null || echo "")
        if [[ "$AUTH_MODE" == "CONFIG_MAP" || "$AUTH_MODE" == "API_AND_CONFIG_MAP" ]]; then
          if kubectl -n kube-system get configmap aws-auth >/dev/null 2>&1; then
            AUTH_ENTRIES=$(kubectl -n kube-system get configmap aws-auth -o jsonpath='{.data.mapRoles}' 2>/dev/null | grep -c "^" || true)
            AUTH_ENTRIES=${AUTH_ENTRIES:-0}
            info "aws-auth ConfigMap: $AUTH_ENTRIES mapRoles entries (auth mode: $AUTH_MODE)"
            if [[ "$AUTH_MODE" == "API_AND_CONFIG_MAP" ]]; then
              warn "aws-auth ConfigMap" "both ConfigMap and access entries in use — ConfigMap entries can shadow access entries; recommend migrating to API-only mode"
            fi
          fi
        fi
      fi
    else
      warn "kubectl connectivity" "cannot reach EKS API — check kubeconfig and access entries"
      add_issue "kubectl cannot reach EKS → references/cluster-diagnostics-detail.md § D (EKS Access / kubectl)" "P1"
    fi
  else
    info "kubectl not installed — skipping Kubernetes checks"
  fi
else
  header "5. Slurm Checks"
  info "Orchestrator: Slurm"

  # Warn/issue emitted in section 1; this branch is the PASS-only confirmation.
  if [[ "$NODE_RECOVERY" == *"Automatic"* ]] && [[ "$NODE_RECOVERY" != *"None"* ]]; then
    pass "NodeRecovery" "enabled on all instance groups"
  fi

  if command -v session-manager-plugin &>/dev/null && [[ -n "$CLUSTER_ID" ]]; then
    header "5b. Slurm Controller Health (via SSM)"
    HEAD_NODE_ID=$(echo "$NODE_LIST" | python3 -c "
import sys,json
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    g=n.get('InstanceGroupName','').lower()
    if any(x in g for x in ['controller','head','master','login']):
        print(n.get('InstanceId',''))
        break
else:
    if nodes:
        print(nodes[0].get('InstanceId',''))
" 2>/dev/null || echo "")

    if [[ -n "$HEAD_NODE_ID" ]]; then
      HEAD_GROUP=$(echo "$NODE_LIST" | HEAD_NODE_ID_ENV="$HEAD_NODE_ID" python3 -c "
import sys,json,os
target_id = os.environ['HEAD_NODE_ID_ENV']
nodes=json.load(sys.stdin).get('ClusterNodeSummaries',[])
for n in nodes:
    if n.get('InstanceId','') == target_id:
        print(n.get('InstanceGroupName',''))
        break
" 2>/dev/null || echo "")
      if [[ -z "$HEAD_GROUP" ]]; then
        warn "Controller node" "could not resolve instance-group name — SSM check skipped"
        HEAD_NODE_ID=""
      fi
    fi
    if [[ -n "$HEAD_NODE_ID" ]]; then
      SSM_TARGET="sagemaker-cluster:${CLUSTER_ID}_${HEAD_GROUP}-${HEAD_NODE_ID}"
      info "Controller node: $HEAD_NODE_ID ($HEAD_GROUP)"
      info "SSM target: $SSM_TARGET"

      _slurm_nonce=$(date +%s%N 2>/dev/null || echo "$RANDOM")
      # Validate nonce is numeric to prevent injection in remote command
      if [[ ! "$_slurm_nonce" =~ ^[0-9]+$ ]]; then
        _slurm_nonce="$$"
      fi
      SLURM_SH=$(cat <<EOF
scontrol show config >/dev/null 2>&1
if [ \$? -eq 0 ]; then echo SLURM_OK_${_slurm_nonce}; else echo SLURM_DOWN_${_slurm_nonce}; fi
echo NODES_START_${_slurm_nonce}
sinfo -o '%N %T %30E' --noheader 2>/dev/null | head -20
echo NODES_END_${_slurm_nonce}
echo JOBS_START_${_slurm_nonce}
squeue -o '%i %j %T %R' --noheader 2>/dev/null | grep -iE 'COMPLETING|CONFIGURING|PENDING' | head -10 || true
echo JOBS_END_${_slurm_nonce}
echo MUNGE_${_slurm_nonce}
systemctl is-active munge 2>/dev/null || echo munge_inactive
echo END_${_slurm_nonce}
EOF
)
      STDOUT=$(ssm_run_on_node "$HEAD_NODE_ID" "$HEAD_GROUP" "$SLURM_SH" || echo "")

      if [[ -n "$STDOUT" ]]; then
        if echo "$STDOUT" | grep -q "SLURM_OK_${_slurm_nonce}"; then
          pass "slurmctld" "responsive"
        elif echo "$STDOUT" | grep -q "SLURM_DOWN_${_slurm_nonce}"; then
          fail "slurmctld" "not responding — all Slurm operations blocked"
          add_issue "slurmctld down on controller → references/cluster-operations.md § 8 Slurm — controller operations" "P0"
        fi

        SLURM_DOWN_NODES=$(echo "$STDOUT" | sed -n "/^NODES_START_${_slurm_nonce}\$/,/^NODES_END_${_slurm_nonce}\$/p" | grep -v "^NODES_" | grep -iE "down|drain|fail" || true)
        if [[ -n "$SLURM_DOWN_NODES" ]]; then
          warn "Slurm nodes with issues:"
          echo "$SLURM_DOWN_NODES" | while IFS= read -r line; do info "  $line"; done
          S_DOWN_COUNT=$(echo "$SLURM_DOWN_NODES" | grep -c . ; :)
          S_DOWN_COUNT=${S_DOWN_COUNT:-0}
          add_issue "$S_DOWN_COUNT Slurm node(s) down/drained → references/cluster-diagnostics-detail.md § G (Node Replacement); delegate to hyperpod-node-debugger" "P1"
        else
          pass "Slurm nodes" "all idle/alloc/mixed"
        fi

        STUCK_JOBS=$(echo "$STDOUT" | sed -n "/^JOBS_START_${_slurm_nonce}\$/,/^JOBS_END_${_slurm_nonce}\$/p" | grep -v "^JOBS_" || true)
        if [[ -n "$STUCK_JOBS" ]]; then
          warn "Stuck Slurm jobs detected:"
          echo "$STUCK_JOBS" | while IFS= read -r line; do info "  $line"; done
          add_issue "Stuck Slurm jobs → references/cluster-operations.md § 8 Slurm — controller operations" "P1"
        fi

        if echo "$STDOUT" | sed -n "/^MUNGE_${_slurm_nonce}\$/,/^END_${_slurm_nonce}\$/p" | grep -q "munge_inactive"; then
          fail "munge" "authentication service not running — Slurm auth will fail"
          add_issue "munge service inactive on controller → references/cluster-operations.md § 8 Slurm — controller operations" "P0"
        fi
      else
        info "Could not get output from SSM on controller — check ssm:StartSession permission, session-manager-plugin, or node reachability"
      fi
    else
      info "Could not identify controller node from node list"
    fi
  else
    info "SSM plugin not available — Slurm checks require SSM access to controller"
    info "Install SSM plugin to enable Slurm health checks"
  fi
fi

header "6. SSM Readiness"

if command -v session-manager-plugin &>/dev/null; then
  if SSM_VERSION=$(session-manager-plugin --version 2>/dev/null); then
    pass "SSM plugin installed" "version: $SSM_VERSION"
  else
    warn "SSM plugin" "installed but --version failed — plugin may be corrupt"
    add_issue "SSM plugin installed but broken → references/cluster-diagnostics-detail.md § F (SSM Connectivity)" "P1"
  fi
else
  warn "SSM plugin" "not installed — required for node access (install session-manager-plugin)"
  add_issue "SSM plugin not installed → references/cluster-diagnostics-detail.md § F (SSM Connectivity)" "P2"
fi

if [[ -n "$CLUSTER_ID" && "$TOTAL_NODES" -gt 0 ]]; then
  FIRST_NODE=$(echo "$NODE_LIST" | python3 -c "
import sys, json
nodes = json.load(sys.stdin).get('ClusterNodeSummaries', [])
if nodes:
    n = nodes[0]
    nid = n.get('InstanceId', '?')
    group = n.get('InstanceGroupName', '?')
    print(f'{group}-{nid}')
" 2>/dev/null || echo "")

  if [[ -n "$FIRST_NODE" ]]; then
    info "SSM target format: sagemaker-cluster:${CLUSTER_ID}_${FIRST_NODE}"
    info "To connect: aws ssm start-session --target sagemaker-cluster:${CLUSTER_ID}_${FIRST_NODE} --region $REGION"
  fi
fi

if [[ -n "$SUBNET_IDS" ]]; then
  header "6b. VPC Endpoints"

  FIRST_SUBNET=$(echo "$SUBNET_IDS" | awk '{print $1}')
  VPC_FOR_ENDPOINTS=$(aws ec2 describe-subnets \
    --subnet-ids "$FIRST_SUBNET" \
    --region "$REGION" \
    --cli-read-timeout 15 \
    --query 'Subnets[0].VpcId' \
    --output text 2>/dev/null || echo "")

  if [[ -n "$VPC_FOR_ENDPOINTS" && "$VPC_FOR_ENDPOINTS" != "None" ]]; then
    EP_RESULT=$(aws ec2 describe-vpc-endpoints \
      --filters "Name=vpc-id,Values=$VPC_FOR_ENDPOINTS" \
      --region "$REGION" \
      --cli-read-timeout 15 \
      --query "VpcEndpoints[?State==\`available\`].ServiceName" \
      --output text 2>&1)
    if echo "$EP_RESULT" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
      warn "describe-vpc-endpoints" "IAM permission denied — VPC endpoint check skipped"
      EP_RESULT=""
    fi
    ENDPOINTS="${EP_RESULT}"

    # s3 → Lifecycle scripts (S3 bucket download path)
    # ssm/ssmmessages/ec2messages → SSM connectivity (§ F)
    for SVC in s3 ssm ssmmessages ec2messages; do
      if echo "$ENDPOINTS" | grep -qE "(^|[.])${SVC}($|[[:space:]])"; then
        pass "VPC endpoint: $SVC"
      else
        warn "VPC endpoint: $SVC" "not found — required only if the cluster subnet has no NAT/IGW path out"
        case "$SVC" in
          s3)   add_issue "VPC endpoint not found for s3 → references/cluster-diagnostics-detail.md § C (Lifecycle Scripts)" "P2" ;;
          ssm|ssmmessages|ec2messages)
                add_issue "VPC endpoint not found for $SVC → references/cluster-diagnostics-detail.md § F (SSM Connectivity)" "P2" ;;
        esac
      fi
    done
  else
    info "Could not determine VPC ID for endpoint check"
  fi
fi

header "7. CloudWatch Logs"

if [[ -n "$CLUSTER_ID" ]]; then
  # CW log groups follow /aws/sagemaker/Clusters/<CLUSTER_NAME>/<CLUSTER_ID>,
  # where <CLUSTER_NAME> is the human-readable name (not the ARN short-id).
  CLUSTER_NAME_FOR_LOGS=$(echo "$CLUSTER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    n = d.get('ClusterName', '')
    print(n if n else '')
except Exception:
    print('')
" 2>/dev/null)
  # Fall back to the value the caller supplied, unless it looks like an ARN.
  if [[ -z "$CLUSTER_NAME_FOR_LOGS" ]]; then
    if [[ "$CLUSTER" == arn:aws:* ]]; then
      CLUSTER_NAME_FOR_LOGS="$CLUSTER_ID"  # best-effort; will probe the prefix below
    else
      CLUSTER_NAME_FOR_LOGS="$CLUSTER"
    fi
  fi

  LOG_GROUP="/aws/sagemaker/Clusters/${CLUSTER_NAME_FOR_LOGS}/${CLUSTER_ID}"

  LOG_RESULT=$(aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region "$REGION" \
    --query 'logGroups[0].logGroupName' \
    --output text 2>&1)
  if echo "$LOG_RESULT" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
    warn "describe-log-groups" "IAM permission denied — CloudWatch log check skipped"
    LOG_RESULT="None"
  fi
  LOG_EXISTS="${LOG_RESULT:-None}"

  if [[ "$LOG_EXISTS" != "None" && -n "$LOG_EXISTS" ]]; then
    pass "CloudWatch log group" "$LOG_GROUP"

    # Use the server-side prefix filter; clusters with hundreds of nodes have
    # hundreds of streams and the default first-page result truncates.
    count_log_streams_by_prefix() {
      local prefix="$1"
      local merged='[]' token='' page_json combined i=0
      while (( i < 20 )); do
        if [[ -n "$token" ]]; then
          page_json=$(aws logs describe-log-streams \
            --log-group-name "$LOG_GROUP" --region "$REGION" \
            --log-stream-name-prefix "$prefix" --limit 50 --next-token "$token" \
            --output json 2>/dev/null) || break
        else
          page_json=$(aws logs describe-log-streams \
            --log-group-name "$LOG_GROUP" --region "$REGION" \
            --log-stream-name-prefix "$prefix" --limit 50 \
            --output json 2>/dev/null) || break
        fi
        combined=$(python3 -c "
import sys, json
prev = json.loads(sys.argv[1])
page = json.loads(sys.argv[2])
prev.extend(s.get('logStreamName','') for s in page.get('logStreams', []))
print(json.dumps(prev))
print(page.get('nextToken',''))
" "$merged" "$page_json" 2>/dev/null) || break

        merged=$(printf '%s\n' "$combined" | sed -n '1p')

        token=$(printf '%s\n'  "$combined" | sed -n '2p')
        i=$((i+1))
        [[ -z "$token" ]] && break
      done
      echo "$merged" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0
    }

    LC_COUNT=$(count_log_streams_by_prefix "LifecycleConfig")
    HM_COUNT=$(count_log_streams_by_prefix "SagemakerHealthMonitoringAgent")

    info "Lifecycle log streams: $LC_COUNT"
    info "Health monitoring log streams: $HM_COUNT"

    if [[ "$LC_COUNT" -eq 0 && "$CLUSTER_STATUS" != "Creating" ]]; then
      warn "Lifecycle logs" "no lifecycle log streams found — scripts may not have run"
    fi
  else
    warn "CloudWatch log group" "not found: $LOG_GROUP"
    info "Logs may not be available if cluster creation failed early"
    info "Check IAM execution role has CloudWatch Logs write permissions"
    add_issue "CloudWatch log group not found → references/cluster-diagnostics-detail.md § C (Lifecycle Scripts)" "P2"
  fi
fi

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}          DIAGNOSTIC SUMMARY            ${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

echo -e "  Cluster:  ${BOLD}${CLUSTER}${NC} (${ORCHESTRATOR})"
echo -e "  Status:   ${CLUSTER_STATUS}"
echo -e "  Results:  ${RED}${CRITICAL_FAILURES} critical${NC} | ${YELLOW}${WARNINGS} warnings${NC}"
echo -e "  Mode:     READ-ONLY (no changes made; each [FAIL] points to a references section)"
echo ""

if [[ ${#ISSUES_FOUND[@]} -gt 0 ]]; then
  echo -e "${BOLD}  Issues Found (prioritized):${NC}"
  for priority in P0 P1 P2; do
    has_priority=false
    for issue in "${ISSUES_FOUND[@]}"; do
      if [[ "$issue" == "${priority}|"* ]]; then
        if ! "$has_priority"; then
          case "$priority" in
            P0) echo -e "    ${RED}${BOLD}[$priority — Fix Immediately]${NC}" ;;
            P1) echo -e "    ${YELLOW}${BOLD}[$priority — Fix Soon]${NC}" ;;
            P2) echo -e "    ${BOLD}[$priority — Informational]${NC}" ;;
          esac
          has_priority=true
        fi
        echo -e "      → ${issue#*|}"
      fi
    done
  done
  echo ""
fi

if [[ $CRITICAL_FAILURES -eq 0 && $WARNINGS -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All cluster-level checks passed.${NC}"
  echo "  If issues persist, try:"
  echo "    - hyperpod-node-debugger skill for per-node issues"
  echo "    - hyperpod-nccl skill for NCCL/training issues"
elif [[ $CRITICAL_FAILURES -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}No critical issues, but $WARNINGS warning(s) found.${NC}"
  echo "  Review [WARN] items above."
else
  echo -e "  ${RED}${BOLD}$CRITICAL_FAILURES critical issue(s) found.${NC}"
  echo "  Fix [FAIL] items above. See SKILL.md for detailed resolution steps."
fi
echo ""

exit "$([[ $CRITICAL_FAILURES -eq 0 ]] && echo 0 || echo 1)"
