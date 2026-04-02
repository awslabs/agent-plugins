#!/usr/bin/env bash
# HyperPod Version Checker - Detect software component versions on HyperPod cluster nodes
#
# Checks: NVIDIA driver, CUDA, cuDNN, NCCL, EFA, AWS OFI NCCL, GDRCopy, MPI,
#          Neuron SDK, Python, PyTorch, container runtime
# Works on both EKS and Slurm HyperPod clusters.
#
# Usage: bash hyperpod_check_versions.sh [--json] [--no-color] [--output FILE]

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed" >&2; exit 1; }

# --- Defaults ---
JSON_OUTPUT=false
USE_COLOR=true
OUTPUT_FILE=""

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUTPUT=true; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        --output|-o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash hyperpod_check_versions.sh [--json] [--no-color] [--output FILE]"
            echo "  --json       Output ONLY JSON to stdout (text report still saved to file)"
            echo "  --no-color   Disable color output"
            echo "  --output/-o  Write report to FILE (default: component_versions_<host>_<time>.txt)"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Color setup ---
if [[ "$USE_COLOR" == "true" ]] && [ -t 1 ] && [[ "$JSON_OUTPUT" != "true" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

# --- Output file ---
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="component_versions_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
fi

# --- Helpers ---
# In JSON mode: text goes only to file. Otherwise: both console and file.
log() {
    local stripped
    stripped=$(printf '%b\n' "$@" | sed 's/\x1b\[[0-9;]*m//g')
    echo "$stripped" >> "$OUTPUT_FILE"
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "$@"
    fi
}

section() {
    log "${BLUE}========================================${NC}"
    log "${BLUE}$1${NC}"
    log "${BLUE}========================================${NC}"
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }
cmd_or_path() { command -v "$1" 2>/dev/null || echo "$2"; }

# Detect instance type via IMDS
IMDS_TOKEN=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null) || true
if [[ -z "$IMDS_TOKEN" ]]; then
    echo "Error: Failed to retrieve IMDS token (IMDSv2 endpoint unreachable)" >&2
    INSTANCE_TYPE=""
else
    INSTANCE_TYPE=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null) || true
    if [[ -z "$INSTANCE_TYPE" ]]; then
        echo "Error: Failed to retrieve instance type from IMDS" >&2
    fi
fi
IS_NEURON=false
IS_GPU=false
[[ "$INSTANCE_TYPE" =~ (^|\.)(trn|inf) ]] && IS_NEURON=true
[[ "$INSTANCE_TYPE" =~ (^|\.)(p[0-9]|g[0-9]) ]] && IS_GPU=true

# JSON-safe string escape via jq (handles all special/unicode characters correctly)
json_escape() { jq -rn --arg v "$1" '$v | @json | .[1:-1]'; }

declare -A VERSIONS

# --- System Information ---
: > "$OUTPUT_FILE"
section "System Information"
log "Host: $(hostname)"
log "Date: $(date)"
log "OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
log "Kernel: $(uname -r)"
log "Architecture: $(uname -m)"
log "Instance Type: ${INSTANCE_TYPE:-unknown}"
log ""

# --- NVIDIA Driver & CUDA ---
section "CUDA Information"

if cmd_exists nvidia-smi; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    if [ $? -ne 0 ] || [ -z "$DRIVER_VER" ] || [[ "$DRIVER_VER" == *"failed"* ]] || [[ "$DRIVER_VER" == *"NVIDIA-SMI"* ]]; then
        DRIVER_VER=""
        if [[ "$IS_NEURON" == "true" ]]; then
            log "${YELLOW}NVIDIA driver: N/A (Trainium/Inferentia instance)${NC}"
        else
            log "${YELLOW}nvidia-smi found but driver not responding${NC}"
        fi
    else
        VERSIONS[NVIDIA_DRIVER]="$DRIVER_VER"
        log "NVIDIA Driver: $DRIVER_VER"
    fi

    MAX_CUDA=$(nvidia-smi 2>/dev/null | grep "CUDA Version" | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' | head -1)
    if [ -n "$MAX_CUDA" ]; then
        VERSIONS[MAX_CUDA]="$MAX_CUDA"
        log "Max Supported CUDA: $MAX_CUDA (driver capability)"
    fi

    log ""
    log "GPUs:"
    nvidia-smi -L 2>/dev/null | while read -r line; do log "  $line"; done
    log ""
else
    log "${YELLOW}nvidia-smi not found - no NVIDIA GPU or driver not installed${NC}"
    log ""
fi

if cmd_exists nvcc; then
    CUDA_VER=$(nvcc --version 2>/dev/null | grep "release" | sed -n 's/.*release \([0-9.]*\).*/\1/p')
    VERSIONS[CUDA_TOOLKIT]="$CUDA_VER"
    log "CUDA Toolkit (nvcc): $CUDA_VER"
elif [ -L /usr/local/cuda ]; then
    CUDA_LINK=$(readlink /usr/local/cuda)
    CUDA_VER=$(echo "$CUDA_LINK" | sed -n 's/.*cuda-\([0-9.]*\).*/\1/p')
    VERSIONS[CUDA_TOOLKIT]="${CUDA_VER} (symlink)"
    log "CUDA Toolkit (symlink): $CUDA_VER"
fi

CUDA_DIRS=$(ls -d /usr/local/cuda-* 2>/dev/null)
if [ -n "$CUDA_DIRS" ]; then
    log "Installed CUDA dirs: $CUDA_DIRS"
    [ -L /usr/local/cuda ] && log "Active symlink: /usr/local/cuda -> $(readlink /usr/local/cuda)"
fi
log ""

# --- cuDNN ---
section "cuDNN Information"

CUDNN_VER=""
# Check header file
CUDNN_HEADER=$(find /usr/local/cuda/include /usr/include -maxdepth 2 -name "cudnn_version.h" 2>/dev/null | head -1)
if [ -z "$CUDNN_HEADER" ]; then
    CUDNN_HEADER=$(find /usr/local/cuda/include /usr/include -maxdepth 2 -name "cudnn.h" 2>/dev/null | head -1)
fi
if [ -n "$CUDNN_HEADER" ]; then
    MAJOR=$(grep "#define CUDNN_MAJOR" "$CUDNN_HEADER" 2>/dev/null | awk '{print $3}')
    MINOR=$(grep "#define CUDNN_MINOR" "$CUDNN_HEADER" 2>/dev/null | awk '{print $3}')
    PATCH=$(grep "#define CUDNN_PATCHLEVEL" "$CUDNN_HEADER" 2>/dev/null | awk '{print $3}')
    [ -n "$MAJOR" ] && [ -n "$MINOR" ] && CUDNN_VER="${MAJOR}.${MINOR}.${PATCH}"
fi
# Package fallback
if [ -z "$CUDNN_VER" ]; then
    if cmd_exists dpkg; then
        CUDNN_VER=$(dpkg -l 2>/dev/null | grep -i "libcudnn[0-9]" | head -1 | awk '{print $3}' | sed 's/-.*//')
    fi
    if [ -z "$CUDNN_VER" ] && cmd_exists rpm; then
        CUDNN_VER=$(rpm -qa 2>/dev/null | grep -i "libcudnn" | head -1 | sed -n 's/.*-\([0-9][0-9.]*\)-.*/\1/p')
    fi
fi

if [ -n "$CUDNN_VER" ]; then
    VERSIONS[CUDNN]="$CUDNN_VER"
    log "cuDNN: v${CUDNN_VER}"
else
    # Check if library exists at all
    CUDNN_LIB=$(find /usr/local/cuda/lib64 /usr/lib -maxdepth 2 -name "libcudnn.so*" 2>/dev/null | head -1)
    if [ -n "$CUDNN_LIB" ]; then
        log "cuDNN library found: $CUDNN_LIB (version unknown)"
    else
        log "${YELLOW}cuDNN not found${NC}"
    fi
fi
log ""

# --- NCCL ---
section "NCCL Information"

NCCL_VER=""
NCCL_LIBS=$(find /usr/local/cuda*/lib* /usr/lib* /usr/local/lib* /opt/nccl/lib -maxdepth 2 -name "libnccl.so*" 2>/dev/null | head -10)
if [ -n "$NCCL_LIBS" ]; then
    log "Libraries found:"
    echo "$NCCL_LIBS" | while read -r lib; do log "  $lib"; done
    while IFS= read -r lib; do
        if [[ $lib =~ libnccl\.so\.([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            NCCL_VER="${BASH_REMATCH[1]}"
            break
        fi
    done <<< "$NCCL_LIBS"
fi

# Fallback to header
if [ -z "$NCCL_VER" ]; then
    NCCL_HEADER=$(find /usr/local/cuda*/include /usr/include /usr/local/include /opt/nccl/include -maxdepth 2 -name "nccl.h" 2>/dev/null | head -1)
    if [ -n "$NCCL_HEADER" ]; then
        MAJOR=$(grep "NCCL_MAJOR" "$NCCL_HEADER" 2>/dev/null | head -1 | awk '{print $3}')
        MINOR=$(grep "NCCL_MINOR" "$NCCL_HEADER" 2>/dev/null | head -1 | awk '{print $3}')
        PATCH=$(grep "NCCL_PATCH" "$NCCL_HEADER" 2>/dev/null | head -1 | awk '{print $3}')
        [ -n "$MAJOR" ] && [ -n "$MINOR" ] && [ -n "$PATCH" ] && NCCL_VER="${MAJOR}.${MINOR}.${PATCH}"
        [ -n "$NCCL_VER" ] && log "Version from header ($NCCL_HEADER): $NCCL_VER"
    fi
fi

if [ -n "$NCCL_VER" ]; then
    VERSIONS[NCCL]="$NCCL_VER"
    log "NCCL version: v${NCCL_VER}"
else
    log "${YELLOW}NCCL not found${NC}"
fi

# Package info
if cmd_exists dpkg; then
    NCCL_PKGS=$(dpkg -l 2>/dev/null | grep -i nccl)
    [ -n "$NCCL_PKGS" ] && { log ""; log "Packages (dpkg):"; echo "$NCCL_PKGS" | while read -r p; do log "  $p"; done; }
fi
if cmd_exists rpm; then
    NCCL_RPMS=$(rpm -qa 2>/dev/null | grep -i nccl)
    [ -n "$NCCL_RPMS" ] && { log ""; log "Packages (rpm):"; echo "$NCCL_RPMS" | while read -r p; do log "  $p"; done; }
fi

# nccl-tests
NCCL_TESTS=$(find /opt /usr/local -maxdepth 4 -name "all_reduce_perf" 2>/dev/null | head -1)
[ -n "$NCCL_TESTS" ] && log "nccl-tests found: $(dirname "$NCCL_TESTS")"
log ""

# --- EFA ---
section "EFA Information"

EFA_VER=""
LIBFABRIC_VER=""

if [ -f /opt/amazon/efa_installed_packages ]; then
    EFA_VER=$(grep "# EFA installer version:" /opt/amazon/efa_installed_packages | sed -n 's/.*version: \([0-9.]*\).*/\1/p')
    LIBFABRIC_VER=$(grep "libfabric-aws-" /opt/amazon/efa_installed_packages | sed -n 's/.*libfabric-aws-\([0-9.]*\)amzn.*/\1/p' | head -1)
    log "EFA installed packages:"
    while read -r line; do log "  $line"; done < /opt/amazon/efa_installed_packages
    log ""
fi

if [ -z "$LIBFABRIC_VER" ]; then
    FI_INFO=""
    cmd_exists fi_info && FI_INFO="fi_info"
    [ -z "$FI_INFO" ] && [ -f /opt/amazon/efa/bin/fi_info ] && FI_INFO="/opt/amazon/efa/bin/fi_info"
    if [ -n "$FI_INFO" ]; then
        LIBFABRIC_VER=$("$FI_INFO" --version 2>&1 | grep "libfabric" | sed -n 's/.*libfabric: \([0-9.]*\).*/\1/p' | head -1)
        log "Libfabric ($FI_INFO): $LIBFABRIC_VER"
    fi
fi

[ -n "$EFA_VER" ] && VERSIONS[EFA_INSTALLER]="$EFA_VER" && log "EFA Installer: $EFA_VER"
[ -n "$LIBFABRIC_VER" ] && VERSIONS[LIBFABRIC]="$LIBFABRIC_VER" && log "Libfabric: $LIBFABRIC_VER"

# EFA provider check
FI_CMD=""
cmd_exists fi_info && FI_CMD="fi_info"
[ -z "$FI_CMD" ] && [ -f /opt/amazon/efa/bin/fi_info ] && FI_CMD="/opt/amazon/efa/bin/fi_info"
if [ -n "$FI_CMD" ]; then
    if "$FI_CMD" -p efa 2>&1 | grep -q "provider: efa"; then
        log "${GREEN}EFA provider available${NC}"
    else
        log "${YELLOW}EFA provider not detected${NC}"
    fi
fi

[ -d /sys/class/infiniband ] && log "InfiniBand devices: $(ls /sys/class/infiniband/ 2>/dev/null | tr '\n' ' ')" || log "${YELLOW}No InfiniBand devices found${NC}"
log ""

# --- AWS OFI NCCL ---
section "AWS OFI NCCL Plugin"

OFI_NCCL_VER=""
if [ -f /opt/amazon/efa_installed_packages ]; then
    OFI_NCCL_VER=$(grep "libnccl-ofi-" /opt/amazon/efa_installed_packages | sed -n 's/.*libnccl-ofi-\([0-9.]*\)-.*/\1/p' | head -1)
fi

if [ -n "$OFI_NCCL_VER" ]; then
    VERSIONS[AWS_OFI_NCCL]="$OFI_NCCL_VER"
    log "AWS OFI NCCL: v${OFI_NCCL_VER}"
else
    OFI_LIB=$(find /opt/amazon/ofi-nccl /usr/lib* -maxdepth 3 -name "libnccl-net.so" 2>/dev/null | head -1)
    if [ -n "$OFI_LIB" ]; then
        log "AWS OFI NCCL library found: $OFI_LIB (version unknown)"
    else
        log "${YELLOW}AWS OFI NCCL not found${NC}"
    fi
fi
log ""

# --- GDRCopy ---
section "GDRCopy Information"

GDRCOPY_VER=""
if cmd_exists rpm; then
    GDRCOPY_VER=$(rpm -qa 2>/dev/null | grep "^gdrcopy-[0-9]" | head -1 | sed -n 's/gdrcopy-\([0-9.]*\)-.*/\1/p')
fi
if [ -z "$GDRCOPY_VER" ] && cmd_exists dpkg; then
    GDRCOPY_VER=$(dpkg -l 2>/dev/null | grep "^ii.*gdrcopy" | head -1 | awk '{print $3}' | sed -n 's/\([0-9.]*\)-.*/\1/p')
fi

if [ -n "$GDRCOPY_VER" ]; then
    VERSIONS[GDRCOPY]="$GDRCOPY_VER"
    log "GDRCopy: v${GDRCOPY_VER}"
else
    GDRCOPY_LIB=$(find /usr /opt -maxdepth 4 -name "libgdrapi.so*" 2>/dev/null | head -1)
    [ -n "$GDRCOPY_LIB" ] && log "GDRCopy library found: $GDRCOPY_LIB (version unknown)" || log "${YELLOW}GDRCopy not found${NC}"
fi

if lsmod 2>/dev/null | grep -q gdrdrv; then
    log "Kernel module: ${GREEN}gdrdrv loaded${NC}"
else
    log "Kernel module: ${YELLOW}gdrdrv not loaded${NC}"
fi
log ""

# --- MPI ---
section "MPI Information"

MPI_VER=""
if cmd_exists mpirun; then
    MPI_VER=$(mpirun --version 2>&1 | head -1)
elif [ -f /opt/amazon/openmpi/bin/mpirun ]; then
    MPI_VER=$(/opt/amazon/openmpi/bin/mpirun --version 2>&1 | head -1)
fi
if [ -n "$MPI_VER" ]; then
    VERSIONS[MPI]="$MPI_VER"
    log "MPI: $MPI_VER"
else
    log "${YELLOW}MPI not found${NC}"
fi
log ""

# --- Neuron SDK (Trainium/Inferentia) ---
section "Neuron SDK Information"

NEURON_DETECTED=false
NEURON_BIN="/opt/aws/neuron/bin"

# Neuron driver (kernel module)
NEURON_DRV_VER=$(modinfo neuron 2>/dev/null | grep "^version:" | awk '{print $2}')
if [ -n "$NEURON_DRV_VER" ]; then
    VERSIONS[NEURON_DRIVER]="$NEURON_DRV_VER"
    log "Neuron Driver: $NEURON_DRV_VER"
    NEURON_DETECTED=true
fi

# Neuron devices
NEURON_DEV_COUNT=$(ls /dev/neuron* 2>/dev/null | wc -l)
if [ "$NEURON_DEV_COUNT" -gt 0 ]; then
    VERSIONS[NEURON_DEVICES]="$NEURON_DEV_COUNT"
    log "Neuron Devices: $NEURON_DEV_COUNT"
    NEURON_DETECTED=true
fi

# Neuron devices listing
NEURON_LS=$(cmd_or_path neuron-ls "$NEURON_BIN/neuron-ls")
if [ -x "$NEURON_LS" ]; then
    NEURON_DETECTED=true
    log "Neuron devices:"
    "$NEURON_LS" 2>/dev/null | while read -r line; do log "  $line"; done
    log ""
fi

# Neuron compiler
NEURON_CC=$(cmd_or_path neuronx-cc "$NEURON_BIN/neuronx-cc")
if [ -x "$NEURON_CC" ]; then
    NEURON_CC_VER=$("$NEURON_CC" --version 2>&1 | head -1)
    VERSIONS[NEURON_COMPILER]="$NEURON_CC_VER"
    log "Neuron Compiler: $NEURON_CC_VER"
    NEURON_DETECTED=true
fi

# Neuron runtime
NEURON_RT_VER=""
if cmd_exists dpkg; then
    NEURON_RT_VER=$(dpkg -l 2>/dev/null | grep "aws-neuronx-runtime-lib" | head -1 | awk '{print $3}')
fi
if [ -z "$NEURON_RT_VER" ] && cmd_exists rpm; then
    NEURON_RT_VER=$(rpm -qa 2>/dev/null | grep "aws-neuronx-runtime" | head -1 | sed -n 's/.*-\([0-9][0-9.]*\)-.*/\1/p')
fi
if [ -n "$NEURON_RT_VER" ]; then
    VERSIONS[NEURON_RUNTIME]="$NEURON_RT_VER"
    log "Neuron Runtime: $NEURON_RT_VER"
    NEURON_DETECTED=true
fi

# torch-neuronx
TORCH_NEURON_VER=$(python3 -c "import torch_neuronx; print(torch_neuronx.__version__)" 2>/dev/null)
if [ -n "$TORCH_NEURON_VER" ]; then
    VERSIONS[TORCH_NEURONX]="$TORCH_NEURON_VER"
    log "torch-neuronx: $TORCH_NEURON_VER"
    NEURON_DETECTED=true
fi

# Neuron tools
NEURON_TOP=$(cmd_or_path neuron-top "$NEURON_BIN/neuron-top")
if [ -x "$NEURON_TOP" ]; then
    NEURON_TOOLS_VER=""
    if cmd_exists dpkg; then
        NEURON_TOOLS_VER=$(dpkg -l 2>/dev/null | grep "aws-neuronx-tools" | head -1 | awk '{print $3}')
    fi
    if [ -z "$NEURON_TOOLS_VER" ] && cmd_exists rpm; then
        NEURON_TOOLS_VER=$(rpm -qa 2>/dev/null | grep "aws-neuronx-tools" | head -1 | sed -n 's/.*-\([0-9][0-9.]*\)-.*/\1/p')
    fi
    [ -n "$NEURON_TOOLS_VER" ] && log "Neuron Tools: $NEURON_TOOLS_VER"
    NEURON_DETECTED=true
fi

if [[ "$NEURON_DETECTED" != "true" ]]; then
    log "${YELLOW}Neuron SDK not found (expected on non-Trainium/Inferentia instances)${NC}"
fi
log ""

# --- Python & PyTorch ---
section "Python / ML Frameworks"

if cmd_exists python3; then
    PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
    VERSIONS[PYTHON]="$PY_VER"
    log "Python: $PY_VER"

    PT_INFO=$(python3 -c "
import torch
print(f'{torch.__version__}')
print(f'cuda_available={torch.cuda.is_available()}')
print(f'cuda_version={torch.version.cuda or \"N/A\"}')
if hasattr(torch, 'xpu') and hasattr(torch.xpu, 'is_available'):
    print(f'xpu_available={torch.xpu.is_available()}')
" 2>/dev/null)
    if [ -n "$PT_INFO" ]; then
        PT_VER=$(echo "$PT_INFO" | head -1)
        VERSIONS[PYTORCH]="$PT_VER"
        log "PyTorch: $PT_VER"
        echo "$PT_INFO" | tail -n +2 | while read -r line; do log "  $line"; done
    fi
else
    log "${YELLOW}python3 not found${NC}"
fi
log ""

# --- Container Runtime ---
section "Container Runtime"
cmd_exists docker && log "Docker: $(docker --version 2>&1)"
cmd_exists containerd && log "Containerd: $(containerd --version 2>&1)"
cmd_exists kubectl && log "kubectl: $(kubectl version --client 2>&1 | head -1)"
# NVIDIA Container Toolkit
if cmd_exists nvidia-ctk; then
    NCTK_VER=$(nvidia-ctk --version 2>&1 | head -1)
    VERSIONS[NVIDIA_CTK]="$NCTK_VER"
    log "NVIDIA Container Toolkit: $NCTK_VER"
elif cmd_exists dpkg && dpkg -l 2>/dev/null | grep -q nvidia-container-toolkit; then
    NCTK_VER=$(dpkg -l 2>/dev/null | grep "nvidia-container-toolkit " | head -1 | awk '{print $3}')
    VERSIONS[NVIDIA_CTK]="$NCTK_VER"
    log "NVIDIA Container Toolkit: $NCTK_VER"
fi
log ""

# --- Environment Variables ---
section "Relevant Environment Variables"
log "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-<not set>}"
log "NCCL vars: $(env | grep -i "^NCCL" 2>/dev/null | tr '\n' ' ')"
log "EFA vars: $(env | grep -i "^FI_\|^EFA_\|^RDMAV" 2>/dev/null | tr '\n' ' ')"
log "NEURON vars: $(env | grep -i "^NEURON" 2>/dev/null | tr '\n' ' ')"
log ""

# --- CUDA/Driver Compatibility Analysis ---
section "CUDA/Driver Compatibility Analysis"

if [ -n "${VERSIONS[NVIDIA_DRIVER]}" ] && [ -n "${VERSIONS[MAX_CUDA]}" ]; then
    DRIVER_MAJOR=$(echo "${VERSIONS[NVIDIA_DRIVER]}" | cut -d'.' -f1)
    log "Driver ${VERSIONS[NVIDIA_DRIVER]} (series $DRIVER_MAJOR):"

    if [ "$DRIVER_MAJOR" -ge 580 ] 2>/dev/null; then
        log "  ${GREEN}✓ Supports CUDA 13.x, 12.x, 11.x${NC}"
    elif [ "$DRIVER_MAJOR" -ge 570 ] 2>/dev/null; then
        log "  ${GREEN}✓ Supports CUDA 12.8+ (Blackwell), 12.x, 11.x${NC}"
    elif [ "$DRIVER_MAJOR" -ge 545 ] 2>/dev/null; then
        log "  ${GREEN}✓ Supports CUDA 12.3-12.7, 11.x${NC}"
        log "  ${YELLOW}⚠ NOT compatible with CUDA 12.8+ (needs driver 570+)${NC}"
    elif [ "$DRIVER_MAJOR" -ge 525 ] 2>/dev/null; then
        log "  ${GREEN}✓ Supports CUDA 12.0-12.2, 11.x${NC}"
        log "  ${YELLOW}⚠ NOT compatible with CUDA 12.3+ (needs driver 545+)${NC}"
    elif [ "$DRIVER_MAJOR" -ge 450 ] 2>/dev/null; then
        log "  ${GREEN}✓ Supports CUDA 11.x${NC}"
        log "  ${YELLOW}⚠ NOT compatible with CUDA 12.x (needs driver 525+)${NC}"
    else
        log "  ${YELLOW}⚠ Driver older than CUDA 11.x baseline${NC}"
    fi
fi
log ""

# --- Version Summary ---
section "Version Summary"

log "NVIDIA_DRIVER: ${VERSIONS[NVIDIA_DRIVER]:-not found}"
log "MAX_CUDA: ${VERSIONS[MAX_CUDA]:-not found}"
log "CUDA_TOOLKIT: ${VERSIONS[CUDA_TOOLKIT]:-not found}"
log "CUDNN: ${VERSIONS[CUDNN]:+v${VERSIONS[CUDNN]}}${VERSIONS[CUDNN]:-not found}"
log "NCCL: ${VERSIONS[NCCL]:+v${VERSIONS[NCCL]}}${VERSIONS[NCCL]:-not found}"
log "EFA_INSTALLER: ${VERSIONS[EFA_INSTALLER]:-not found}"
log "LIBFABRIC: ${VERSIONS[LIBFABRIC]:-not found}"
log "AWS_OFI_NCCL: ${VERSIONS[AWS_OFI_NCCL]:+v${VERSIONS[AWS_OFI_NCCL]}}${VERSIONS[AWS_OFI_NCCL]:-not found}"
log "GDRCOPY: ${VERSIONS[GDRCOPY]:+v${VERSIONS[GDRCOPY]}}${VERSIONS[GDRCOPY]:-not found}"
log "MPI: ${VERSIONS[MPI]:-not found}"
log "NEURON_DRIVER: ${VERSIONS[NEURON_DRIVER]:-not found}"
log "NEURON_DEVICES: ${VERSIONS[NEURON_DEVICES]:-0}"
log "NEURON_COMPILER: ${VERSIONS[NEURON_COMPILER]:-not found}"
log "NEURON_RUNTIME: ${VERSIONS[NEURON_RUNTIME]:-not found}"
log "TORCH_NEURONX: ${VERSIONS[TORCH_NEURONX]:-not found}"
log "PYTHON: ${VERSIONS[PYTHON]:-not found}"
log "PYTORCH: ${VERSIONS[PYTORCH]:-not found}"

log ""
log "Report saved to: $OUTPUT_FILE"

# --- JSON output (stdout only) ---
if [[ "$JSON_OUTPUT" == "true" ]]; then
    cat <<EOF
{
  "hostname": "$(hostname)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "instance_type": "$(json_escape "${INSTANCE_TYPE:-unknown}")",
  "versions": {
    "nvidia_driver": "$(json_escape "${VERSIONS[NVIDIA_DRIVER]:-}")",
    "max_cuda": "$(json_escape "${VERSIONS[MAX_CUDA]:-}")",
    "cuda_toolkit": "$(json_escape "${VERSIONS[CUDA_TOOLKIT]:-}")",
    "cudnn": "$(json_escape "${VERSIONS[CUDNN]:-}")",
    "nccl": "$(json_escape "${VERSIONS[NCCL]:-}")",
    "efa_installer": "$(json_escape "${VERSIONS[EFA_INSTALLER]:-}")",
    "libfabric": "$(json_escape "${VERSIONS[LIBFABRIC]:-}")",
    "aws_ofi_nccl": "$(json_escape "${VERSIONS[AWS_OFI_NCCL]:-}")",
    "gdrcopy": "$(json_escape "${VERSIONS[GDRCOPY]:-}")",
    "mpi": "$(json_escape "${VERSIONS[MPI]:-}")",
    "neuron_driver": "$(json_escape "${VERSIONS[NEURON_DRIVER]:-}")",
    "neuron_devices": "$(json_escape "${VERSIONS[NEURON_DEVICES]:-}")",
    "neuron_compiler": "$(json_escape "${VERSIONS[NEURON_COMPILER]:-}")",
    "neuron_runtime": "$(json_escape "${VERSIONS[NEURON_RUNTIME]:-}")",
    "torch_neuronx": "$(json_escape "${VERSIONS[TORCH_NEURONX]:-}")",
    "nvidia_container_toolkit": "$(json_escape "${VERSIONS[NVIDIA_CTK]:-}")",
    "python": "$(json_escape "${VERSIONS[PYTHON]:-}")",
    "pytorch": "$(json_escape "${VERSIONS[PYTORCH]:-}")"
  }
}
EOF
fi
