#!/usr/bin/env bash
# check-efa-sg.sh
#
# Identify and diagnose EFA security group rules for a HyperPod cluster.
# Automatically extracts the cluster's exact VPC, subnets, and security groups
# from the cluster ARN — works correctly even in accounts with 1000s of resources.
#
# Usage (preferred — cluster-centric, auto-discovers resources):
#   bash check-efa-sg.sh --cluster <cluster-name-or-arn> --region <region>
#
# Usage (direct SG mode — when SG is already known):
#   bash check-efa-sg.sh --sg-id <sg-id> --region <region>
#
# Exit codes:
#   0 — all required rules in place
#   1 — one or more required rules missing

set -euo pipefail

for cmd in aws python3; do
  command -v "$cmd" &>/dev/null || {
    echo "ERROR: '$cmd' is required but not found. Install it and retry."
    exit 1
  }
done

CLUSTER=""
SG_ID=""
REGION="${AWS_DEFAULT_REGION:-}"
USE_COLOR=true

usage() {
  cat <<EOF
Usage:
  $0 --cluster <cluster-name-or-arn> --region <region> [--no-color]
  $0 --sg-id   <sg-id>               --region <region> [--no-color]

Read-only diagnostic for EFA-related security group rules on a HyperPod
cluster. Reports inbound/outbound self-referencing rules and warns on
0.0.0.0/0 outbound (which the HyperPod docs advise against on the EFA SG).
On any [FAIL] the script ends with a pointer to
"references/node-diagnostics-detail.md § A (EFA / Security Group)".

Options:
  --cluster   Auto-discovers SGs, subnets, VPC from the cluster (preferred).
  --sg-id     Check a specific security group directly.
  --region    AWS region (required unless \$AWS_DEFAULT_REGION is set).
  --no-color  Disable ANSI colors.
  -h, --help  Show this message.

Exit codes:
  0  All required rules present.
  1  One or more required rules missing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)  CLUSTER="$2";    shift 2 ;;
    --sg-id)    SG_ID="$2";      shift 2 ;;
    --region)   REGION="$2";     shift 2 ;;
    --no-color) USE_COLOR=false; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$CLUSTER" && -z "$SG_ID" ]]; then
  usage >&2
  exit 1
fi

if [[ -z "$REGION" ]]; then
  echo "ERROR: --region is required (or set AWS_DEFAULT_REGION before running)." >&2
  exit 2
fi

# Mutually exclusive: --cluster auto-discovers SGs, --sg-id targets one specific SG.
# Passing both was silently ignoring --sg-id — error instead so the caller notices.
if [[ -n "$CLUSTER" && -n "$SG_ID" ]]; then
  echo "ERROR: --cluster and --sg-id are mutually exclusive (pick one)" >&2
  exit 2
fi

if [[ -n "$SG_ID" && ! "$SG_ID" =~ ^sg-[a-fA-F0-9]{8,17}$ ]]; then
  echo "ERROR: Invalid security group ID format: '$SG_ID' (expected sg-<hex>, e.g. sg-0abc1234def56789a)"
  exit 1
fi

if ! [ -t 1 ] || [ "${TERM:-}" = "dumb" ]; then
  USE_COLOR=false
fi
if "$USE_COLOR"; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

check_single_sg() {
  local sg_id="$1"
  local region="$2"
  local issues=0

  echo ""
  echo -e "${BOLD}=== EFA Security Group Diagnostic ===${NC}"
  echo -e "Security Group: ${BOLD}${sg_id}${NC}  Region: ${BOLD}${region}${NC}"
  echo ""

  local sg_json
  sg_json=$(aws ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --region "$region" \
    --cli-read-timeout 30 \
    --output json 2>&1) || {
    echo -e "${RED}ERROR: Cannot describe security group '$sg_id' in region '$region'${NC}"
    echo "$sg_json"
    return 1
  }

  # Distinguish "API succeeded but returned empty" (auth-denied or malformed JSON
  # still yielding exit 0) from "SG genuinely has no rules". Without this, the
  # three rule checks below would each emit [FAIL], misleading the customer
  # into thinking rules are missing when the check itself could not run.
  local sg_count
  sg_count=$(echo "$sg_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('SecurityGroups',[])))" 2>/dev/null || echo 0)
  if [[ "$sg_count" -eq 0 ]]; then
    echo -e "  ${YELLOW}[WARN]${NC} Unable to check SG rules — describe-security-groups returned no data for '$sg_id' (possible IAM denial or stale ID)"
    echo -e "         → references/node-diagnostics-detail.md § A (EFA / Security Group)"
    return 0
  fi

  local sg_name vpc_id
  sg_name=$(echo "$sg_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['SecurityGroups'][0].get('GroupName','unknown'))" 2>/dev/null || echo "unknown")
  vpc_id=$(echo "$sg_json"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['SecurityGroups'][0].get('VpcId','unknown'))"   2>/dev/null || echo "unknown")
  echo -e "Name: ${sg_name}  |  VPC: ${vpc_id}"
  echo ""

  echo -e "${BOLD}--- Inbound Rules ---${NC}"
  echo "$sg_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)['SecurityGroups'][0]
rules = d.get('IpPermissions', [])
if not rules:
    print('  (none)')
for r in rules:
    proto = r.get('IpProtocol', '?')
    srcs  = [g.get('GroupId','') for g in r.get('UserIdGroupPairs', [])]
    cidrs = [c.get('CidrIp','') for c in r.get('IpRanges', [])]
    for s in srcs:  print(f'  proto={proto} source=sg:{s}')
    for c in cidrs: print(f'  proto={proto} source={c}')
" 2>/dev/null

  echo ""
  echo -e "${BOLD}--- Outbound Rules ---${NC}"
  echo "$sg_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)['SecurityGroups'][0]
rules = d.get('IpPermissionsEgress', [])
if not rules:
    print('  (none)')
for r in rules:
    proto = r.get('IpProtocol', '?')
    dests = [g.get('GroupId','') for g in r.get('UserIdGroupPairs', [])]
    cidrs = [c.get('CidrIp','') for c in r.get('IpRanges', [])]
    for s in dests: print(f'  proto={proto} dest=sg:{s}')
    for c in cidrs: print(f'  proto={proto} dest={c}')
" 2>/dev/null

  echo ""
  echo -e "${BOLD}--- Rule Check Results ---${NC}"

  local inbound_self outbound_self outbound_inet
  inbound_self=$(echo "$sg_json" | SG_CHECK_ID="$sg_id" python3 -c "
import sys, json, os
sg=os.environ['SG_CHECK_ID']
d = json.load(sys.stdin)['SecurityGroups'][0]
for r in d.get('IpPermissions', []):
    if r.get('IpProtocol') == '-1':
        if any(g.get('GroupId') == sg for g in r.get('UserIdGroupPairs', [])):
            print('found'); exit(0)
" 2>/dev/null || echo "")

  outbound_self=$(echo "$sg_json" | SG_CHECK_ID="$sg_id" python3 -c "
import sys, json, os
sg=os.environ['SG_CHECK_ID']
d = json.load(sys.stdin)['SecurityGroups'][0]
for r in d.get('IpPermissionsEgress', []):
    if r.get('IpProtocol') == '-1':
        if any(g.get('GroupId') == sg for g in r.get('UserIdGroupPairs', [])):
            print('found'); exit(0)
" 2>/dev/null || echo "")

  outbound_inet=$(echo "$sg_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)['SecurityGroups'][0]
for r in d.get('IpPermissionsEgress', []):
    if r.get('IpProtocol') == '-1':
        if any(c.get('CidrIp') == '0.0.0.0/0' for c in r.get('IpRanges', [])):
            print('found'); exit(0)
" 2>/dev/null || echo "")

  if [[ "$inbound_self" == "found" ]]; then
    echo -e "  ${GREEN}[PASS]${NC} Inbound self-referencing rule (all traffic from ${sg_id})"
  else
    echo -e "  ${RED}[FAIL]${NC} Missing inbound self-referencing rule (all traffic from ${sg_id})"
    issues=$((issues+1))
  fi

  if [[ "$outbound_self" == "found" ]]; then
    echo -e "  ${GREEN}[PASS]${NC} Outbound self-referencing rule (all traffic to ${sg_id}) ← required for EFA"
  else
    echo -e "  ${RED}[FAIL]${NC} Missing outbound self-referencing rule ← ${BOLD}PRIMARY cause of EFA health check failure${NC}"
    issues=$((issues+1))
  fi

  if [[ "$outbound_inet" == "found" ]]; then
    echo -e "  ${YELLOW}[WARN]${NC} Outbound 0.0.0.0/0 rule present — HyperPod docs advise against this on the EFA SG (can cause EFA health check failures). Move internet egress to the subnet (NAT or VPC endpoints)."
  else
    echo -e "  ${GREEN}[PASS]${NC} No outbound 0.0.0.0/0 on EFA SG (correct per HyperPod prerequisites)"
  fi

  if [[ $issues -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}→ See references/node-diagnostics-detail.md § A (EFA / Security Group) for remediation.${NC}"
  fi

  return "$issues"
}

if [[ -n "$CLUSTER" ]]; then
  echo ""
  echo -e "${BOLD}=== HyperPod Cluster Resource Discovery ===${NC}"
  echo -e "Cluster: ${BOLD}${CLUSTER}${NC}"
  echo -e "Region:  ${BOLD}${REGION}${NC}"
  echo ""

  CLUSTER_JSON=$(aws sagemaker describe-cluster \
    --cluster-name "$CLUSTER" \
    --region "$REGION" \
    --cli-read-timeout 30 \
    --output json 2>&1) || {
    echo -e "${RED}ERROR: Cannot find cluster '$CLUSTER' in region '$REGION'${NC}"
    echo ""
    echo "Available clusters in this region:"
    aws sagemaker list-clusters --region "$REGION" \
      --query 'ClusterSummaries[*].{Name:ClusterName,Status:ClusterStatus,ARN:ClusterArn}' \
      --output table 2>/dev/null || echo "  (unable to list clusters)"
    echo "$CLUSTER_JSON"
    exit 1
  }

  CLUSTER_ARN=$(echo "$CLUSTER_JSON"    | python3 -c "import sys,json; print(json.load(sys.stdin).get('ClusterArn',''))"    2>/dev/null || echo "")
  CLUSTER_STATUS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ClusterStatus',''))" 2>/dev/null || echo "")
  ORCHESTRATOR=$(echo "$CLUSTER_JSON"   | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('EKS' if 'Eks' in d.get('Orchestrator',{}) else 'Slurm')
" 2>/dev/null || echo "Unknown")

  echo -e "  ARN:          ${CLUSTER_ARN}"
  echo -e "  Status:       ${CLUSTER_STATUS}"
  echo -e "  Orchestrator: ${ORCHESTRATOR}"

  RESOURCES=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
vpc=d.get('VpcConfig',{})
sgs=vpc.get('SecurityGroupIds',[])
subnets=vpc.get('Subnets',[])
print('SGs='     + ','.join(sgs))
print('Subnets=' + ','.join(subnets))
" 2>/dev/null || echo "")

  CLUSTER_SGS=$(echo "$RESOURCES"     | grep "^SGs="     | cut -d= -f2)
  CLUSTER_SUBNETS=$(echo "$RESOURCES" | grep "^Subnets=" | cut -d= -f2)

  if [[ -z "$CLUSTER_SGS" ]]; then
    echo -e "${YELLOW}[WARN]${NC} No SecurityGroupIds in cluster VpcConfig — cluster may not have customer VPC"
    exit 0
  fi

  VPC_ID="unknown"
  if [[ -n "$CLUSTER_SUBNETS" ]]; then
    FIRST_SUBNET=$(echo "$CLUSTER_SUBNETS" | tr ',' '\n' | head -1)
    VPC_ID=$(aws ec2 describe-subnets \
      --subnet-ids "$FIRST_SUBNET" \
      --region "$REGION" \
      --query 'Subnets[0].VpcId' \
      --output text 2>/dev/null || echo "unknown")
  fi

  echo ""
  echo -e "${BOLD}  Resources owned by cluster '${CLUSTER}':${NC}"
  echo -e "  VPC:              ${VPC_ID}"
  echo -e "  Security Groups:  ${CLUSTER_SGS}"
  echo -e "  Subnets:          ${CLUSTER_SUBNETS}"

  if [[ -n "$CLUSTER_SUBNETS" ]]; then
    echo ""
    echo -e "${BOLD}  Subnet details:${NC}"
    IFS=',' read -ra _subnet_arr <<< "$CLUSTER_SUBNETS"
    aws ec2 describe-subnets \
      --subnet-ids "${_subnet_arr[@]}" \
      --region "$REGION" \
      --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,FreeIPs:AvailableIpAddressCount,VpcId:VpcId}' \
      --output table 2>/dev/null || echo "  (unable to describe subnets)"
  fi

  echo ""
  TOTAL_ISSUES=0
  # CLUSTER_SGS is guaranteed non-empty at the -z guard above, but defend anyway.
  # grep -c returns exit 1 on zero matches under pipefail, so suppress and then
  # explicitly branch on the count rather than letting 0 silently fall through.
  SG_COUNT=$(echo "$CLUSTER_SGS" | tr ',' '\n' | grep -c . || true)
  if [[ "${SG_COUNT:-0}" -eq 0 ]]; then
    echo -e "  ${YELLOW}[WARN]${NC} No security groups resolved from CLUSTER_SGS — cannot run EFA rule check"
    echo -e "         → references/node-diagnostics-detail.md § A (EFA / Security Group)"
    exit 0
  fi
  echo -e "${BOLD}Checking ${SG_COUNT} security group(s) for cluster '${CLUSTER}'...${NC}"

  for SG in $(echo "$CLUSTER_SGS" | tr ',' ' '); do
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    # Capture rc in a subshell pattern that survives `set -e` — otherwise
    # the first SG with issues aborts the loop and later SGs are never checked.
    sg_rc=0
    check_single_sg "$SG" "$REGION" || sg_rc=$?
    TOTAL_ISSUES=$((TOTAL_ISSUES + sg_rc))
  done

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  if [[ $TOTAL_ISSUES -gt 0 ]]; then
    echo -e "${RED}${BOLD}RESULT: ${TOTAL_ISSUES} security group rule issue(s) found for cluster '${CLUSTER}'${NC}"
    echo "Fix the [FAIL] rules above (see references/node-diagnostics-detail.md § A for the Suggested-command block); if cluster creation was failing on EFA health checks, retry creation after fixing."
    echo ""
    echo "Verify after fixing:"
    echo "  bash check-efa-sg.sh --cluster ${CLUSTER} --region ${REGION}"
    exit 1
  else
    echo -e "${GREEN}${BOLD}RESULT: All EFA security group rules correctly configured for cluster '${CLUSTER}'${NC}"
    echo ""
    echo "If EFA health checks still fail:"
    echo "  1. Verify all instance groups use one of these SGs: ${CLUSTER_SGS}"
    echo "  2. Run check-node-reachability.sh on affected nodes via hyperpod-ssm skill"
    exit 0
  fi
fi

if [[ -n "$SG_ID" ]]; then
  check_single_sg "$SG_ID" "$REGION"
  exit $?
fi
