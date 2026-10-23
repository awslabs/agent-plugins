#!/usr/bin/env bash
# check-vpc-config.sh
#
# Diagnose VPC, subnet, and EKS configuration for a HyperPod cluster.
# Automatically extracts ALL resources (VPC, subnets, SGs) from the cluster —
# no need to know resource IDs in advance, even in accounts with 1000s of resources.
#
# Checks: VPC alignment, subnet AZ, IP availability, ENI limits,
#         EKS auth mode, HyperPod namespace, VPC endpoints.
#
# Usage (cluster-centric — preferred):
#   bash check-vpc-config.sh --cluster <name-or-arn> --region <region>
#   bash check-vpc-config.sh --cluster <name-or-arn> --region <region> --eks-name <eks-cluster>
#
# Exit codes:
#   0 — all checks passed (warnings may still be present)
#   1 — one or more critical checks failed

set -euo pipefail

for cmd in aws python3; do
  command -v "$cmd" &>/dev/null || {
    echo "ERROR: '$cmd' is required but not found. Install it and retry."
    exit 1
  }
done

CLUSTER=""
REGION="${AWS_DEFAULT_REGION:-}"
EKS_NAME=""
USE_COLOR=true

usage() {
  cat <<EOF
Usage: $0 --cluster <name-or-arn> --region <region> [options]

Read-only diagnostic for VPC / subnet / EKS configuration on a HyperPod
cluster. Reports VPC alignment, subnet AZ, IP availability, ENI limits,
EKS auth mode, HyperPod namespace presence, and VPC endpoint presence.
Each [FAIL] line includes a pointer of the form
"→ references/node-diagnostics-detail.md § B (VPC / Routing)".

Options:
  --cluster     HyperPod cluster name or ARN (required).
  --region      AWS region (required unless \$AWS_DEFAULT_REGION is set).
  --eks-name    EKS cluster name if different from the HyperPod cluster name.
  --no-color    Disable ANSI colors.
  -h, --help    Show this message.

Exit codes:
  0  All checks passed (warnings may still be present).
  1  One or more critical checks failed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)   CLUSTER="$2";   shift 2 ;;
    --region)    REGION="$2";    shift 2 ;;
    --eks-name)  EKS_NAME="$2";  shift 2 ;;
    --no-color)  USE_COLOR=false; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$CLUSTER" ]]; then
  usage >&2
  exit 1
fi

if [[ -z "$REGION" ]]; then
  echo "ERROR: --region is required (or set AWS_DEFAULT_REGION before running)." >&2
  exit 2
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

ENI_QUOTA_CODE="L-DF5E4CA3"   # AWS Service Quotas code for "Network interfaces per Region"

CRITICAL_FAILURES=0

pass()  { echo -e "  ${GREEN}[PASS]${NC}  $1${2:+ — $2}"; }
fail()  { CRITICAL_FAILURES=$((CRITICAL_FAILURES+1)); echo -e "  ${RED}[FAIL]${NC}  $1${2:+ — $2}"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}  $1${2:+ — $2}"; }
info()  { echo -e "         $1"; }
header(){ echo ""; echo -e "${BOLD}--- $1 ---${NC}"; }

echo ""
echo -e "${BOLD}=== HyperPod VPC Configuration Check ===${NC}"
echo -e "Cluster: ${BOLD}${CLUSTER}${NC}"
echo -e "Region:  ${BOLD}${REGION}${NC}"

header "1. Cluster VPC Configuration"

CLUSTER_JSON=$(aws sagemaker describe-cluster \
  --cluster-name "$CLUSTER" \
  --region "$REGION" \
  --cli-read-timeout 30 \
  --output json 2>&1) || {
  echo -e "${RED}ERROR: Could not describe cluster '$CLUSTER' in region '$REGION'${NC}"
  echo "$CLUSTER_JSON"
  exit 1
}

CLUSTER_STATUS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ClusterStatus','unknown'))" 2>/dev/null || echo "unknown")
ORCHESTRATOR=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); o=d.get('Orchestrator',{}); print('EKS' if 'Eks' in o else 'Slurm')" 2>/dev/null || echo "unknown")
NODE_RECOVERY=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('NodeRecovery','Unknown'))" 2>/dev/null || echo "Unknown")

info "Status: $CLUSTER_STATUS | Orchestrator: $ORCHESTRATOR | NodeRecovery: $NODE_RECOVERY"

SUBNET_IDS=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
subnets=d.get('VpcConfig',{}).get('Subnets',[])
print(' '.join(subnets))
" 2>/dev/null || echo "")

SG_IDS=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
sgs=d.get('VpcConfig',{}).get('SecurityGroupIds',[])
print(' '.join(sgs))
" 2>/dev/null || echo "")

if [[ -n "$SUBNET_IDS" ]]; then
  pass "VpcConfig found"
  info "Subnets: $SUBNET_IDS"
  info "SecurityGroups: $SG_IDS"
else
  warn "VpcConfig" "no VpcConfig found in cluster"
fi

if [[ "$ORCHESTRATOR" == "EKS" && -z "$EKS_NAME" ]]; then
  EKS_NAME=$(echo "$CLUSTER_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
arn=d.get('Orchestrator',{}).get('Eks',{}).get('ClusterArn','')
print(arn.split('/')[-1] if arn else '')
" 2>/dev/null || echo "")
fi

if [[ -n "$SUBNET_IDS" ]]; then
  header "2. Subnet VPC Alignment"

  read -ra _subnet_arr <<< "$SUBNET_IDS"
  SUBNET_JSON=$(aws ec2 describe-subnets \
    --subnet-ids "${_subnet_arr[@]}" \
    --region "$REGION" \
    --cli-read-timeout 30 \
    --output json 2>/dev/null || echo '{"Subnets":[]}')

  VPC_IDS=$(echo "$SUBNET_JSON" | python3 -c "
import sys,json
subnets=json.load(sys.stdin).get('Subnets',[])
vpc_ids=set(s.get('VpcId','?') for s in subnets)
for s in subnets:
    free=s.get('AvailableIpAddressCount',0)
    az=s.get('AvailabilityZone','?')
    sid=s.get('SubnetId','?')
    vpc=s.get('VpcId','?')
    flag='LOW IPs' if free < 10 else ''
    print(f'  {sid}: VPC={vpc} AZ={az} FreeIPs={free} {flag}')
print('VPCS=' + ','.join(vpc_ids))
" 2>/dev/null || echo "")

  echo "$VPC_IDS" | grep -v "^VPCS=" || true

  UNIQUE_VPCS=$(echo "$VPC_IDS" | grep "^VPCS=" | cut -d= -f2 | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
  VPC_COUNT=$(echo "$UNIQUE_VPCS" | tr ',' '\n' | { grep -c . 2>/dev/null; true; })

  if [[ "$VPC_COUNT" -gt 1 ]]; then
    fail "Subnet VPC alignment" "Subnets are in DIFFERENT VPCs: $UNIQUE_VPCS — all must be in the same VPC → references/node-diagnostics-detail.md § B (VPC / Routing)"
  elif [[ "$VPC_COUNT" -eq 1 ]]; then
    pass "Subnet VPC alignment" "All subnets in VPC: $UNIQUE_VPCS"
  else
    # VPC_COUNT=0 means describe-subnets returned empty — usually an IAM denial
    # on ec2:DescribeSubnets or a stale subnet ID. Without this branch the
    # check would silently fall through and the customer sees no line at all.
    warn "Subnet VPC alignment" "Unable to determine VPC — describe-subnets returned no data (check IAM ec2:DescribeSubnets) → references/node-diagnostics-detail.md § B (VPC / Routing)"
  fi

  if [[ -n "$SG_IDS" ]]; then
    read -ra _sg_arr <<< "$SG_IDS"
    SG_JSON=$(aws ec2 describe-security-groups \
      --group-ids "${_sg_arr[@]}" \
      --region "$REGION" \
      --output json 2>/dev/null || echo '{"SecurityGroups":[]}')

    SG_VPC_CHECK=$(echo "$SG_JSON" | SUBNET_VPC="$UNIQUE_VPCS" python3 -c "
import sys, json, os
sgs=json.load(sys.stdin).get('SecurityGroups',[])
subnet_vpc=os.environ.get('SUBNET_VPC','')
subnet_vpc_set=set(subnet_vpc.split(',')) if subnet_vpc else set()
all_ok=True
for sg in sgs:
    sgid=sg.get('GroupId','?')
    vpc=sg.get('VpcId','?')
    if vpc not in subnet_vpc_set:
        print(f'MISMATCH:{sgid} is in VPC {vpc} but subnets are in {subnet_vpc}')
        all_ok=False
    else:
        print(f'OK:{sgid} in {vpc}')
print('RESULT=' + ('PASS' if all_ok else 'FAIL'))
" 2>/dev/null || echo "RESULT=SKIP")

    echo "$SG_VPC_CHECK" | grep -v "^RESULT=" | sed 's/^OK:/  [OK]   SG /;s/^MISMATCH:/  [FAIL] SG /' || true
    SG_RESULT=$(echo "$SG_VPC_CHECK" | grep "^RESULT=" | cut -d= -f2)
    if [[ "$SG_RESULT" == "PASS" ]]; then
      pass "SecurityGroup VPC alignment"
    elif [[ "$SG_RESULT" == "FAIL" ]]; then
      fail "SecurityGroup VPC alignment" "SG and subnet must be in the same VPC → references/node-diagnostics-detail.md § B (VPC / Routing)"
    else
      # SG_RESULT is "SKIP" (json parse error) or empty (describe-security-groups
      # returned nothing). Either way the check did not run — say so, don't
      # leave the customer staring at a missing line.
      warn "SecurityGroup VPC alignment" "Unable to verify — describe-security-groups returned no usable data (check IAM ec2:DescribeSecurityGroups) → references/node-diagnostics-detail.md § B (VPC / Routing)"
    fi
  fi
fi

header "2a. VPC DNS Support & Hostnames"

# HyperPod requires enableDnsSupport + enableDnsHostnames on the VPC so that
# EKS service DNS and node internal hostnames resolve correctly.
if [[ -n "$UNIQUE_VPCS" && "$UNIQUE_VPCS" != *,* ]]; then
  DNS_SUPPORT=$(aws ec2 describe-vpc-attribute \
    --vpc-id "$UNIQUE_VPCS" --attribute enableDnsSupport \
    --region "$REGION" \
    --query 'EnableDnsSupport.Value' --output text 2>/dev/null || echo "unknown")
  DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute \
    --vpc-id "$UNIQUE_VPCS" --attribute enableDnsHostnames \
    --region "$REGION" \
    --query 'EnableDnsHostnames.Value' --output text 2>/dev/null || echo "unknown")

  if [[ "$DNS_SUPPORT" == "True" ]]; then
    pass "VPC enableDnsSupport" "enabled"
  else
    fail "VPC enableDnsSupport" "must be True — EKS internal DNS and node hostname resolution will fail. → references/node-diagnostics-detail.md § B (VPC / Routing)"
  fi
  if [[ "$DNS_HOSTNAMES" == "True" ]]; then
    pass "VPC enableDnsHostnames" "enabled"
  else
    fail "VPC enableDnsHostnames" "must be True — EKS internal DNS and node hostname resolution will fail. → references/node-diagnostics-detail.md § B (VPC / Routing)"
  fi
else
  warn "VPC DNS attributes" "skipped — subnets span multiple VPCs or no VPC resolved"
fi

header "2b. Private Subnet / Routing"

# HyperPod requires private subnets — a subnet is "public" if its route table has
# a default route (0.0.0.0/0) pointing at an internet gateway. For outbound
# access from a private subnet, the default route must point at a NAT gateway
# (or be absent in a fully air-gapped VPC that relies on VPC endpoints).
if [[ -n "$SUBNET_IDS" ]]; then
  PRIVATE_CHECK=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$(echo "$SUBNET_IDS" | tr ' ' ',')" \
    --region "$REGION" \
    --query "RouteTables[*].{SubnetAssoc:Associations[?SubnetId!=\`null\`].SubnetId,Routes:Routes[?DestinationCidrBlock==\`0.0.0.0/0\`].{Target:GatewayId,NatGw:NatGatewayId}}" \
    --output json 2>/dev/null || echo '[]')

  echo "$PRIVATE_CHECK" | python3 -c "
import sys, json
rts = json.load(sys.stdin)
if not rts:
    print('INFO:no route tables associated — subnets likely use the main route table')
    sys.exit(0)
for rt in rts:
    subs = rt.get('SubnetAssoc', []) or []
    routes = rt.get('Routes', []) or []
    for r in routes:
        tgt = (r.get('Target') or '') or ''
        nat = (r.get('NatGw') or '') or ''
        subs_str = ','.join(subs) if subs else '(main)'
        if tgt.startswith('igw-'):
            print(f'FAIL:Subnet(s) {subs_str} route 0.0.0.0/0 -> Internet Gateway ({tgt}). HyperPod requires PRIVATE subnets; use a NAT gateway instead.')
        elif nat.startswith('nat-'):
            print(f'PASS:Subnet(s) {subs_str} route 0.0.0.0/0 -> NAT Gateway ({nat}) — private subnet, outbound via NAT.')
        elif tgt.startswith('vpce-'):
            print(f'INFO:Subnet(s) {subs_str} route 0.0.0.0/0 -> VPC endpoint ({tgt})')
        else:
            print(f'INFO:Subnet(s) {subs_str} route 0.0.0.0/0 -> {tgt or nat or \"unknown\"}')
" 2>/dev/null | while IFS=: read -r level msg; do
    case "$level" in
      PASS) pass "Private subnet routing" "$msg" ;;
      FAIL) fail "Private subnet routing" "$msg → references/node-diagnostics-detail.md § B (VPC / Routing)" ;;
      WARN) warn "Private subnet routing" "$msg" ;;
      INFO) info "$msg" ;;
    esac
  done
fi

header "3. IP Address Availability"

if [[ -n "$SUBNET_IDS" ]]; then
  _IP_CHECK=$(echo "$SUBNET_JSON" | python3 -c "
import sys,json
subnets=json.load(sys.stdin).get('Subnets',[])
for s in subnets:
    free=s.get('AvailableIpAddressCount',0)
    sid=s.get('SubnetId','?')
    if free < 5:
        print(f'FAIL:{sid} only {free} free IPs — CRITICALLY LOW')
    elif free < 50:
        print(f'WARN:{sid} only {free} free IPs — consider expanding CIDR')
    else:
        print(f'PASS:{sid} has {free} free IPs')
" 2>/dev/null || echo "")

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    level=$(echo "$line" | cut -d: -f1)
    msg=$(echo "$line" | cut -d: -f2-)
    case "$level" in
      FAIL) fail "IP availability" "$msg → references/node-diagnostics-detail.md § B (VPC / Routing)" ;;
      WARN) warn "IP availability" "$msg" ;;
      PASS) pass "IP availability" "$msg" ;;
    esac
  done <<< "$_IP_CHECK"
fi

header "4. ENI Limits"

if [[ -n "$UNIQUE_VPCS" ]]; then
  VPC_ID=$(echo "$UNIQUE_VPCS" | tr ',' '\n' | head -1)
  ENI_COUNT=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region "$REGION" \
    --query 'length(NetworkInterfaces)' \
    --output text 2>/dev/null || echo "unknown")

  ENI_QUOTA=$(aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code "$ENI_QUOTA_CODE" \
    --region "$REGION" \
    --query 'Quota.Value' \
    --output text 2>/dev/null || echo "unknown")

  info "Current ENI count in VPC $VPC_ID: $ENI_COUNT"
  info "ENI quota for region: $ENI_QUOTA"

  if [[ "$ENI_COUNT" != "unknown" && "$ENI_QUOTA" != "unknown" ]]; then
    USAGE_PCT=$(python3 -c "q=int(${ENI_QUOTA}); print(int(${ENI_COUNT}/q*100) if q > 0 else '?')" 2>/dev/null || echo "?")
    if [[ "$USAGE_PCT" != "?" && "$USAGE_PCT" -gt 80 ]]; then
      warn "ENI limits" "${USAGE_PCT}% of quota used — request increase via Service Quotas if provisioning fails → references/node-diagnostics-detail.md § B (VPC / Routing)"
    else
      pass "ENI limits" "${ENI_COUNT}/${ENI_QUOTA} ENIs used (${USAGE_PCT}%)"
    fi
  else
    warn "ENI limits" "Could not determine ENI usage — verify manually → references/node-diagnostics-detail.md § B (VPC / Routing)"
  fi
fi

if [[ "$ORCHESTRATOR" == "EKS" && -n "$EKS_NAME" ]]; then
  header "5. EKS Prerequisites"

  EKS_DESC=$(aws eks describe-cluster \
    --name "$EKS_NAME" \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{}')

  # VPC alignment — the EKS cluster's VPC must match the HyperPod cluster's VPC.
  EKS_VPC=$(echo "$EKS_DESC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster',{}).get('resourcesVpcConfig',{}).get('vpcId',''))" 2>/dev/null || echo "")
  if [[ -n "$EKS_VPC" && -n "$UNIQUE_VPCS" ]]; then
    if [[ ",$UNIQUE_VPCS," == *",$EKS_VPC,"* ]]; then
      pass "EKS VPC alignment" "EKS cluster in same VPC as HyperPod ($EKS_VPC)"
    else
      fail "EKS VPC alignment" "EKS cluster is in VPC $EKS_VPC but HyperPod subnets are in $UNIQUE_VPCS — they must match → references/node-diagnostics-detail.md § B (VPC / Routing)"
    fi
  fi

  # SG cross-reference — the HyperPod cluster SG must either be attached to the
  # EKS cluster, OR the EKS cluster SG must allow inbound from the HyperPod SG.
  EKS_SGS=$(echo "$EKS_DESC" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('cluster',{}).get('resourcesVpcConfig',{})
all_sgs = set(d.get('securityGroupIds',[]) or [])
csg = d.get('clusterSecurityGroupId','')
if csg: all_sgs.add(csg)
print(' '.join(sorted(all_sgs)))
" 2>/dev/null || echo "")

  if [[ -n "$EKS_SGS" && -n "$SG_IDS" ]]; then
    HP_SG_SET=$(echo "$SG_IDS" | tr ',' ' ')
    SG_ATTACHED=false
    for hp in $HP_SG_SET; do
      for eks in $EKS_SGS; do
        [[ "$hp" == "$eks" ]] && { SG_ATTACHED=true; break 2; }
      done
    done
    if "$SG_ATTACHED"; then
      pass "HyperPod SG on EKS" "HyperPod SG is attached to the EKS cluster"
    else
      EKS_SG_LIST=$(echo "$EKS_SGS" | tr ' ' ',' | sed 's/,$//')
      read -r -a EKS_SG_ARR <<< "$EKS_SGS"
      EKS_INGRESS=$(aws ec2 describe-security-groups \
        --group-ids "${EKS_SG_ARR[@]}" \
        --region "$REGION" --output json 2>/dev/null || echo '{"SecurityGroups":[]}')
      CROSS_OK=$(echo "$EKS_INGRESS" | HP_SGS="$SG_IDS" python3 -c "
import sys,json,os
hp=set(os.environ.get('HP_SGS','').replace(',', ' ').split())
sgs=json.load(sys.stdin).get('SecurityGroups',[])
for sg in sgs:
    for rule in sg.get('IpPermissions',[]):
        for pair in rule.get('UserIdGroupPairs',[]):
            if pair.get('GroupId','') in hp:
                print('YES'); sys.exit(0)
print('NO')
" 2>/dev/null || echo "UNKNOWN")
      if [[ "$CROSS_OK" == "YES" ]]; then
        pass "HyperPod<->EKS SG" "EKS cluster SG ($EKS_SG_LIST) allows inbound from HyperPod SG"
      else
        fail "HyperPod<->EKS SG" "HyperPod SG is NOT attached to EKS and EKS SG ($EKS_SG_LIST) does not allow inbound from HyperPod SG → references/node-diagnostics-detail.md § A (EFA / Security Group)"
      fi
    fi
  fi

  EKS_AUTH=$(echo "$EKS_DESC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster',{}).get('accessConfig',{}).get('authenticationMode','unknown'))" 2>/dev/null || echo "unknown")

  if [[ "$EKS_AUTH" == "CONFIG_MAP" ]]; then
    warn "EKS auth mode" "CONFIG_MAP-only; access entries require API or API_AND_CONFIG_MAP — see the EKS access-entries documentation for the switching procedure"
  elif [[ "$EKS_AUTH" == "API" || "$EKS_AUTH" == "API_AND_CONFIG_MAP" ]]; then
    pass "EKS auth mode" "$EKS_AUTH"
  else
    warn "EKS auth mode" "Could not determine ($EKS_AUTH) — verify manually"
  fi

  # EKS endpoint accessibility (reuses $EKS_DESC captured above).
  PUB=$(echo "$EKS_DESC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster',{}).get('resourcesVpcConfig',{}).get('endpointPublicAccess',False))" 2>/dev/null || echo "false")
  PRIV=$(echo "$EKS_DESC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster',{}).get('resourcesVpcConfig',{}).get('endpointPrivateAccess',False))" 2>/dev/null || echo "false")

  info "EKS endpoint: public=$PUB, private=$PRIV"
  if [[ "$PUB" == "False" && "$PRIV" == "True" ]]; then
    warn "EKS endpoint" "Private-only endpoint — ensure worker subnets can reach EKS API (port 443), create EKS VPC endpoint if needed"
  elif [[ "$PUB" == "True" ]]; then
    pass "EKS endpoint" "Public access enabled"
  fi

  if command -v kubectl &>/dev/null; then
    if kubectl get namespace aws-hyperpod &>/dev/null 2>&1; then
      pass "aws-hyperpod namespace" "exists"
    else
      fail "aws-hyperpod namespace" "Missing → references/node-diagnostics-detail.md § B (VPC / Routing)"
    fi
  else
    warn "aws-hyperpod namespace" "kubectl not found — check skipped"
  fi
fi

header "6. VPC Endpoints"

if [[ -n "$UNIQUE_VPCS" ]]; then
  VPC_ID=$(echo "$UNIQUE_VPCS" | tr ',' '\n' | head -1)
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region "$REGION" \
    --query "VpcEndpoints[?State==\`available\`].ServiceName" \
    --output text 2>/dev/null || echo "")

  # Required for private/air-gapped VPCs. Port 443 is the default for every
  # interface endpoint below; S3 uses a Gateway endpoint over the route table.
  # FSx users additionally need com.amazonaws.<region>.fsx if using FSx on Lustre/OpenZFS.
  REQUIRED_ENDPOINTS=("s3" "ecr.api" "ecr.dkr" "sts" "ssm" "ssmmessages" "ec2messages" "ec2" "sagemaker.api" "sagemaker.runtime" "logs")
  for svc in "${REQUIRED_ENDPOINTS[@]}"; do

    if echo "$ENDPOINTS" | grep -qE "\.${svc}$|\.${svc}[^a-z]"; then
      pass "VPC endpoint: $svc"
    else
      warn "VPC endpoint: $svc" "not found — required for internet-disabled (private) VPCs; skip if outbound 0.0.0.0/0 via NAT is available → references/node-diagnostics-detail.md § B (VPC / Routing)"
    fi
  done

  if [[ "$ORCHESTRATOR" == "EKS" ]]; then
    if echo "$ENDPOINTS" | grep -qE "\.eks$|\.eks[^a-z]"; then
      pass "VPC endpoint: eks"
    else
      warn "VPC endpoint: eks" "not found — needed if EKS endpoint is private-only → references/node-diagnostics-detail.md § B (VPC / Routing)"
    fi
  fi

  if ! echo "$ENDPOINTS" | grep -qE "\.fsx"; then
    info "VPC endpoint: fsx — not present (only required if this cluster uses FSx for Lustre or OpenZFS in a private/air-gapped VPC)"
  fi
fi

echo ""
echo -e "${BOLD}--- Summary ---${NC}"

if [[ $CRITICAL_FAILURES -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}VPC configuration checks PASSED (${CRITICAL_FAILURES} critical issues).${NC}"
  echo "  If cluster creation still fails, check EFA security group rules:"
  echo "  bash check-efa-sg.sh --sg-id <SG_ID> --region $REGION"
else
  echo -e "  ${RED}${BOLD}VPC configuration checks FAILED (${CRITICAL_FAILURES} critical issue(s)).${NC}"
  echo "  Fix the [FAIL] items above and retry cluster creation."
fi
echo ""

exit "$([[ $CRITICAL_FAILURES -eq 0 ]] && echo 0 || echo 1)"
