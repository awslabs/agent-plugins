#!/usr/bin/env bash
# check-node-reachability.sh
#
# Diagnose EFA reachability and inter-node communication health on a single
# HyperPod node. Run this on each node via the hyperpod-ssm skill.
#
# Usage (via ssm-exec.sh):
#   ssm-exec.sh --target <TARGET> --upload scripts/check-node-reachability.sh /tmp/check-node-reachability.sh
#   ssm-exec.sh --target <TARGET> 'bash /tmp/check-node-reachability.sh'
#
# Usage (direct on node):
#   bash check-node-reachability.sh [--json] [--no-color]
#
# Exit codes:
#   0 — all critical checks passed
#   1 — one or more critical checks failed

set -euo pipefail

# Note: this script runs ON the node (via SSM), so aws CLI may not be present.
# Only python3 is checked here; other tools are checked individually per section.

JSON_MODE=false
USE_COLOR=true

usage() {
  cat <<EOF
Usage: bash check-node-reachability.sh [--json] [--no-color]

Read-only on-node diagnostic for EFA reachability and inter-node communication
health. Must be executed on a HyperPod compute node (typically via the
hyperpod-ssm skill). Checks EFA interfaces, /dev/infiniband devices, GPU
count and Neuron device count against the expected counts for the node's
instance type.

Options:
  --json       Emit findings as JSON instead of human-readable output.
  --no-color   Disable ANSI colors.
  -h, --help   Show this message.

Exit codes:
  0  All critical checks passed.
  1  One or more critical checks failed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)     JSON_MODE=true;  shift ;;
    --no-color) USE_COLOR=false; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Colors — auto-disable when stdout isn't a TTY.
if ! [ -t 1 ] || [ "${TERM:-}" = "dumb" ]; then
  USE_COLOR=false
fi
if "$USE_COLOR"; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m';   NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CRITICAL_FAILURES=0
declare -A RESULTS   # associative array: check_name → pass|fail|warn|skip

pass()  { RESULTS["$1"]="pass";  [[ "$JSON_MODE" == false ]] && echo -e "  ${GREEN}[PASS]${NC}  $1${2:+ — $2}"; }
fail()  { RESULTS["$1"]="fail";  CRITICAL_FAILURES=$((CRITICAL_FAILURES+1)); \
           [[ "$JSON_MODE" == false ]] && echo -e "  ${RED}[FAIL]${NC}  $1${2:+ — $2}"; }
warn()  { RESULTS["$1"]="warn";  [[ "$JSON_MODE" == false ]] && echo -e "  ${YELLOW}[WARN]${NC}  $1${2:+ — $2}"; }
skip()  { RESULTS["$1"]="skip";  [[ "$JSON_MODE" == false ]] && echo -e "         [SKIP]  $1${2:+ — $2}"; }
info()  { [[ "$JSON_MODE" == false ]] && echo -e "         $1"; }

if [[ "$JSON_MODE" == false ]]; then
  echo ""
  echo -e "${BOLD}=== HyperPod Node EFA Reachability Check ===${NC}"
  echo -e "Host:      ${BOLD}${HOSTNAME}${NC}"
  echo -e "Timestamp: ${TIMESTAMP}"
  echo ""
fi

if [[ "$JSON_MODE" == false ]]; then echo -e "${BOLD}--- EFA Kernel Module ---${NC}"; fi

EFA_MODULE=$(lsmod 2>/dev/null | grep -E '^efa\b' | awk '{print $1}' || true)
if [[ -n "$EFA_MODULE" ]]; then
  EFA_MODULE_VER=$(modinfo efa 2>/dev/null | grep -E '^version:' | awk '{print $2}' || echo "unknown")
  pass "efa_kernel_module" "loaded (version: ${EFA_MODULE_VER})"
else
  # Read-only invariant: detect only, never `sudo modprobe efa` — loading kernel
  # modules mutates node state, which the hyperpod-ssm skill's approval flow owns.
  fail "efa_kernel_module" "not loaded — see references/node-diagnostics-detail.md § A (EFA / Security Group)"
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- EFA Devices ---${NC}"; fi

# shellcheck disable=SC2010  # /dev/ entries are kernel-named, safe to ls|grep
EFA_DEVICES=$(ls /dev/infiniband/ 2>/dev/null | grep -E 'rdma_cm|uverbs|efa' || true)

if [[ -n "$EFA_DEVICES" ]]; then
  pass "efa_devices_present" "found in /dev/infiniband/: $(echo "$EFA_DEVICES" | tr '\n' ' ')"
else
  fail "efa_devices_present" "/dev/infiniband/ is empty or missing — EFA hardware not detected"
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- libfabric EFA Provider ---${NC}"; fi

if command -v fi_info &>/dev/null; then
  # If the previous section found no EFA hardware, fi_info failing is expected —
  # don't emit [FAIL] on top of the hardware [FAIL], which would double-count and
  # conflate "libfabric can't see EFA" with "node has no EFA at all".
  if [[ -z "$EFA_DEVICES" ]]; then
    skip "fi_info_efa_provider" "no EFA devices detected upstream — see efa_devices_present"
  else
    FI_EXIT=0
    FI_OUTPUT=$(fi_info -p efa 2>&1) || FI_EXIT=$?
    if echo "$FI_OUTPUT" | grep -q "provider: efa"; then
      EFA_PROVIDER_COUNT=$(echo "$FI_OUTPUT" | { grep -c "provider: efa" 2>/dev/null; true; })
      pass "fi_info_efa_provider" "EFA provider found (${EFA_PROVIDER_COUNT} endpoint(s))"
      info "$(echo "$FI_OUTPUT" | grep -E 'provider:|fabric:|domain:|version:' | head -8 | sed 's/^/    /')"
    else
      fail "fi_info_efa_provider" "fi_info -p efa returned no EFA provider (exit code ${FI_EXIT}) — libfabric cannot enumerate EFA devices. See references/node-diagnostics-detail.md § A (EFA / Security Group)"
      info "fi_info output: ${FI_OUTPUT:0:200}"
    fi
  fi
else
  warn "fi_info_efa_provider" "fi_info not found — install libfabric to run this check (fi_info comes with EFA installer)"
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- EFA Network Interfaces ---${NC}"; fi

# EFA interfaces typically appear as eth0/ens* for primary + rdmaX or efa* for EFA devices
# EFA ifaces on p5/p5en use regular kernel names (ens*) — filter by driver via ethtool
# rather than by name pattern (the old 'rdma|efa' name grep misses ens* on p5).
EFA_IFACES=""
if command -v ethtool &>/dev/null; then
  while IFS= read -r iface; do
    [[ -z "$iface" ]] && continue
    DRIVER=$(ethtool -i "$iface" 2>/dev/null | awk -F': ' '/^driver:/{print $2}')
    if [[ "$DRIVER" == "efa" ]]; then
      EFA_IFACES+="${iface}"$'\n'
    fi
  done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | awk -F'@' '{print $1}' | grep -v '^lo$')
fi
# Fallback to name-based detection for older kernels / containers without ethtool
if [[ -z "$EFA_IFACES" ]]; then
  EFA_IFACES=$(ip link show 2>/dev/null | grep -E 'rdma|efa' | awk -F': ' '{print $2}' | tr -d '@' || true)
fi
REGULAR_IFACES=$(ip link show 2>/dev/null | grep -E 'state UP' | awk -F': ' '{print $2}' | tr -d '@' || true)

if [[ -n "$EFA_IFACES" ]]; then
  pass "efa_interfaces_up" "EFA interfaces found: $(echo "$EFA_IFACES" | tr '\n' ' ')"
  while IFS= read -r iface; do
    [[ -z "$iface" ]] && continue
    IP=$(ip addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' || true)
    if [[ -n "$IP" ]]; then
      info "  $iface → $IP"
    else
      warn "efa_interface_ip_${iface}" "interface $iface has no IP address — check DHCP/subnet config"
    fi
  done <<< "$EFA_IFACES"
else
  info "No EFA interfaces detected (by driver or name)"
  if [[ -n "$REGULAR_IFACES" ]]; then
    skip "efa_interfaces_up" "no separate EFA interface — primary interfaces: $(echo "$REGULAR_IFACES" | tr '\n' ' ' | head -c 80)"
  else
    warn "efa_interfaces_up" "no UP network interfaces found"
  fi
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- EFA Installation ---${NC}"; fi

EFA_VER_FILE="/opt/amazon/efa_installed_packages"
if [[ -f "$EFA_VER_FILE" ]]; then
  # Format is "EFA installer version: 1.30.0" — grab only the version token.
  EFA_VER=$(grep -iE '^EFA installer version' "$EFA_VER_FILE" 2>/dev/null \
              | head -1 \
              | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' \
              | head -1 || echo "")
  if [[ -z "$EFA_VER" ]]; then
    warn "efa_installer_present" "EFA installer file present but version line not parsed"
  else
    pass "efa_installer_present" "EFA installer version: ${EFA_VER}"
  fi
else
  warn "efa_installer_present" "EFA installer marker not found at ${EFA_VER_FILE} — EFA may not be installed via standard method"
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- NCCL / OFI Configuration ---${NC}"; fi

NCCL_VARS=("FI_PROVIDER" "FI_EFA_USE_DEVICE_RDMA" "NCCL_SOCKET_IFNAME" "NCCL_ALGO" "LD_LIBRARY_PATH")
ANY_NCCL_SET=false
for var in "${NCCL_VARS[@]}"; do
  val="${!var:-}"
  if [[ -n "$val" ]]; then
    info "  ${var}=${val}"
    ANY_NCCL_SET=true
  fi
done

if "$ANY_NCCL_SET"; then
  FI_PROVIDER_VAL="${FI_PROVIDER:-}"
  if [[ -n "$FI_PROVIDER_VAL" && "$FI_PROVIDER_VAL" != "efa" ]]; then
    warn "nccl_fi_provider" "FI_PROVIDER=${FI_PROVIDER_VAL} — for EFA workloads this should be 'efa'"
  elif [[ "$FI_PROVIDER_VAL" == "efa" ]]; then
    pass "nccl_fi_provider" "FI_PROVIDER=efa"
  fi
else
  skip "nccl_env_vars" "no NCCL/OFI env vars set in current shell — may be set in job launcher environment"
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- AWS OFI NCCL Plugin ---${NC}"; fi

OFI_LIB=$(find /opt/amazon/efa /opt/aws-ofi-nccl /usr/local/lib /usr/lib \
  -name "libnccl-net.so*" -o -name "aws-ofi-nccl.so*" 2>/dev/null | head -1 || true)

if [[ -n "$OFI_LIB" ]]; then
  pass "aws_ofi_nccl_plugin" "found: ${OFI_LIB}"
else
  if [[ -f "$EFA_VER_FILE" ]] && grep -q "ofi\|OFI" "$EFA_VER_FILE" 2>/dev/null; then
    pass "aws_ofi_nccl_plugin" "referenced in ${EFA_VER_FILE}"
  else
    warn "aws_ofi_nccl_plugin" "libnccl-net.so not found — required for EFA-accelerated NCCL (distributed training)"
  fi
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- Instance Metadata Reachability ---${NC}"; fi

IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --connect-timeout 3 -m 5 2>/dev/null || true)

if [[ -n "$IMDS_TOKEN" ]]; then
  INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-type --connect-timeout 3 -m 5 2>/dev/null || echo "unknown")
  LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4 --connect-timeout 3 -m 5 2>/dev/null || echo "unknown")
  pass "imds_reachable" "instance-type=${INSTANCE_TYPE}, local-ipv4=${LOCAL_IP}"

  # Static list of EFA-capable families; unknown types fall through to the
  # EC2 API check. aws CLI may not be present on-node, so the static path
  # covers the common case.
  case "$INSTANCE_TYPE" in
    p4de*|p4d*|p5en*|p5e*|p5*|p6*|trn1*|trn2*|inf2*|g5.48xlarge|g6e.48xlarge|g6.48xlarge|hpc6a*|hpc6id*|hpc7a*|hpc7g*|dl1*|dl2q*)
      pass "efa_capable_instance" "${INSTANCE_TYPE} supports EFA" ;;
    *)
      if command -v aws &>/dev/null; then
        EFA_CHECK=$(aws ec2 describe-instance-types \
          --instance-types "${INSTANCE_TYPE}" \
          --query 'InstanceTypes[0].NetworkInfo.EfaSupported' \
          --output text 2>/dev/null || echo "unknown")
        if [[ "$EFA_CHECK" == "True" ]]; then
          pass "efa_capable_instance" "${INSTANCE_TYPE} supports EFA (verified via API)"
        elif [[ "$EFA_CHECK" == "False" ]]; then
          warn "efa_capable_instance" "${INSTANCE_TYPE} does NOT support EFA"
        else
          warn "efa_capable_instance" "${INSTANCE_TYPE} — could not verify EFA support"
        fi
      else
        warn "efa_capable_instance" "${INSTANCE_TYPE} — not in known EFA list; verify with: aws ec2 describe-instance-types --instance-types ${INSTANCE_TYPE} --query 'InstanceTypes[0].NetworkInfo.EfaSupported'"
      fi
      ;;
  esac
  # Multi-EFA validation — counts per EC2 instance-type documentation.
  # NOTE: EFA counts vary between instance families (p5en has fewer than p5/p5e).
  EXPECTED_EFA=0
  case "$INSTANCE_TYPE" in
    p5.48xlarge|p5e.48xlarge)   EXPECTED_EFA=32 ;;
    p5en.48xlarge)              EXPECTED_EFA=16 ;;
    p4d.24xlarge|p4de.24xlarge) EXPECTED_EFA=4 ;;
    trn1.32xlarge)              EXPECTED_EFA=8 ;;
    trn2.48xlarge)              EXPECTED_EFA=16 ;;
    # p6 family and newer: don't hardcode counts; discover via ethtool to avoid false FAILs.
  esac

  if [[ "$EXPECTED_EFA" -gt 0 ]]; then
    # Count actual EFA devices — avoid grep -c pattern that returns "0\n0" fallthrough.
    ACTUAL_EFA=$(find /dev/infiniband -maxdepth 1 -name 'uverbs*' 2>/dev/null | wc -l)
    [[ -z "$ACTUAL_EFA" ]] && ACTUAL_EFA=0
    if [[ "$ACTUAL_EFA" -ge "$EXPECTED_EFA" ]]; then
      pass "multi_efa_interfaces" "${ACTUAL_EFA}/${EXPECTED_EFA} EFA interfaces present for ${INSTANCE_TYPE}"
    elif [[ "$ACTUAL_EFA" -gt 0 ]]; then
      warn "multi_efa_interfaces" "only ${ACTUAL_EFA}/${EXPECTED_EFA} EFA interfaces — some may not be attached or driver issue"
    else
      fail "multi_efa_interfaces" "0/${EXPECTED_EFA} EFA interfaces on ${INSTANCE_TYPE} — EFA driver or attachment issue"
    fi
  fi
else
  warn "imds_reachable" "IMDS not reachable. If running inside a container: check IMDSv2 HttpPutResponseHopLimit on the instance (default 1 is often too low for container networking — set to 2 or higher). Otherwise: verify the instance metadata service is enabled (HttpEndpoint != disabled) and that no local iptables / nftables rules block 169.254.169.254. Note: SGs do not filter link-local addresses."
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- Network Interface Statistics ---${NC}"; fi

if command -v ip &>/dev/null; then
  IFACE_ERRORS=$(ip -s link show 2>/dev/null | awk '
    BEGIN { rx_err=0; tx_err=0; iface="" }
    /^[0-9]+:/ {
      if (iface != "" && (rx_err > 0 || tx_err > 0))
        print "  " iface ": RX errors=" rx_err " TX errors=" tx_err
      iface=$2; gsub(/:$/, "", iface)
      rx_err=0; tx_err=0
    }
    /RX:/ { getline; rx_err=$3+0 }
    /TX:/ { getline; tx_err=$3+0 }
    END {
      if (iface != "" && (rx_err > 0 || tx_err > 0))
        print "  " iface ": RX errors=" rx_err " TX errors=" tx_err
    }
  ' || true)

  if [[ -n "$IFACE_ERRORS" ]]; then
    warn "network_interface_errors" "interfaces with errors detected:"
    info "$IFACE_ERRORS"
  else
    pass "network_interface_errors" "no RX/TX errors on active interfaces"
  fi
else
  skip "network_interface_errors" "ip command not available"
fi

if [[ "$JSON_MODE" == false ]]; then echo ""; echo -e "${BOLD}--- Neuron Devices (Trainium/Inferentia) ---${NC}"; fi

if command -v neuron-ls &>/dev/null; then
  NEURON_OUTPUT=$(neuron-ls 2>&1 || true)
  NEURON_DEVICE_COUNT=$(echo "$NEURON_OUTPUT" | { grep -c "neuron_device" 2>/dev/null; true; })
  if [[ "$NEURON_DEVICE_COUNT" -gt 0 ]]; then
    pass "neuron_devices" "${NEURON_DEVICE_COUNT} Neuron device(s) detected"
    info "$(echo "$NEURON_OUTPUT" | head -10 | sed 's/^/    /')"
  else
    NEURON_MOD=$(lsmod 2>/dev/null | grep -E '^neuron' || true)
    if [[ -n "$NEURON_MOD" ]]; then
      warn "neuron_devices" "Neuron driver loaded but neuron-ls shows 0 devices → references/node-diagnostics-detail.md § G.2 (Trainium/Inferentia)"
    else
      fail "neuron_devices" "Neuron driver not loaded → references/node-diagnostics-detail.md § G.2 (Trainium/Inferentia)"
    fi
  fi
elif ls /dev/neuron* &>/dev/null 2>&1; then
  NEURON_DEV_COUNT=$(find /dev -maxdepth 1 -name 'neuron*' 2>/dev/null | wc -l)
  NEURON_DEV_COUNT=${NEURON_DEV_COUNT:-0}
  warn "neuron_devices" "${NEURON_DEV_COUNT} /dev/neuron* device(s) found but neuron-ls not installed → references/node-diagnostics-detail.md § G.2 (Trainium/Inferentia)"
else
  skip "neuron_devices" "not a Trainium/Inferentia instance (no Neuron devices)"
fi

if [[ "$JSON_MODE" == false ]]; then
  echo ""
  echo -e "${BOLD}--- Summary ---${NC}"
  TOTAL=${#RESULTS[@]}
  PASSED=$(printf '%s\n' "${RESULTS[@]}" | { grep -c "^pass$" 2>/dev/null; true; })
  WARNED=$(printf '%s\n' "${RESULTS[@]}" | { grep -c "^warn$" 2>/dev/null; true; })
  FAILED=$(printf '%s\n' "${RESULTS[@]}" | { grep -c "^fail$" 2>/dev/null; true; })
  SKIPPED=$(printf '%s\n' "${RESULTS[@]}" | { grep -c "^skip$" 2>/dev/null; true; })
  echo -e "  Host: ${HOSTNAME}"
  echo -e "  Checks: ${TOTAL} total | ${GREEN}${PASSED} passed${NC} | ${YELLOW}${WARNED} warnings${NC} | ${RED}${FAILED} failed${NC} | ${SKIPPED} skipped"

  if [[ $CRITICAL_FAILURES -eq 0 ]]; then
    echo -e "\n  ${GREEN}${BOLD}Node EFA reachability checks PASSED.${NC}"
    echo "  If inter-node communication still fails, verify security group rules with check-efa-sg.sh"
    echo "  and compare EFA versions across nodes with the hyperpod-version-checker skill."
  else
    echo -e "\n  ${RED}${BOLD}Node EFA reachability checks FAILED (${CRITICAL_FAILURES} critical issue(s)).${NC}"
    echo "  See [FAIL] items above. Each finding ends with a pointer of the form"
    echo "  '→ references/node-diagnostics-detail.md § <section>' — open that section"
    echo "  for root cause and remediation. Remediation lives in references, not in scripts."
  fi
  echo ""
else
  CHECKS_JSON=""
  for key in "${!RESULTS[@]}"; do
    val="${RESULTS[$key]}"
    CHECKS_JSON+="\"${key}\": \"${val}\","
  done
  CHECKS_JSON="${CHECKS_JSON%,}"  # remove trailing comma

  cat <<EOF
{
  "hostname": "${HOSTNAME}",
  "timestamp": "${TIMESTAMP}",
  "critical_failures": ${CRITICAL_FAILURES},
  "overall_pass": $([ $CRITICAL_FAILURES -eq 0 ] && echo true || echo false),
  "checks": { ${CHECKS_JSON} }
}
EOF
fi

exit "$([[ $CRITICAL_FAILURES -eq 0 ]] && echo 0 || echo 1)"
