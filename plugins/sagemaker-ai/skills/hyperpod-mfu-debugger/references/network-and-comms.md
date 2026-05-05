# Network and Communication Diagnostics

EFA, NCCL, stack-trace straggler detection, cross-node bandwidth. All
on-node commands run through `hyperpod-ssm`.

## Contents

1. [EFA Health](#1-efa-health)
2. [NCCL Configuration](#2-nccl-configuration)
3. [Cross-Node Bandwidth](#3-cross-node-bandwidth)
4. [Straggler Detection via Stack Traces](#4-straggler-detection)
5. [Common HyperPod Network Issues](#5-common-hyperpod-network-issues)

---

## 1. EFA Health

### Present and functional

```bash
fi_info -p efa
# Expected device count:
#   p5 / p5e / p5en:  32
#   p4d / p4de:        4
#   trn1:              8
#   trn2:             16

lsmod | grep efa                           # kernel module
cat /sys/class/infiniband/*/ports/1/state  # each entry should be "4: ACTIVE"
```

Note: `fi_info -p efa` can return multiple endpoints per physical
card. For a quick card count, compare against the expected physical
count with `ls -d /sys/class/infiniband/*`.

### Error counters

```bash
for dev in /sys/class/infiniband/*/; do
  name=$(basename "$dev")
  rcv_err=$(cat "$dev/ports/1/counters/port_rcv_errors" 2>/dev/null)
  xmit_disc=$(cat "$dev/ports/1/counters/port_xmit_discards" 2>/dev/null)
  if [ "$rcv_err" != "0" ] || [ "$xmit_disc" != "0" ]; then
    echo "PROBLEM: $name rcv_errors=$rcv_err xmit_discards=$xmit_disc"
  fi
done
```

Non-zero counters = packet loss or link issues.

### Firmware version

```bash
cat /sys/class/infiniband/*/fw_ver 2>/dev/null
```

All nodes should match. Mismatches after replacement cause subtle
performance differences.

---

## 2. NCCL Configuration

### Confirm EFA, not TCP

Look in training logs:

```
NCCL INFO NET/OFI Using provider: efa
```

`NET/Socket` = TCP fallback; cross-node bandwidth drops drastically.
To debug, before job start:

```bash
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET
```

### Recommended environment (p5 / p5e / p5en)

These must be set in the launcher before the training process starts;
mid-run changes have no effect. Treat as a starting point and benchmark
with [nccl-tests](https://github.com/NVIDIA/nccl-tests) before
adopting as a standard.

```bash
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export NCCL_PROTO=Simple
export NCCL_ALGO=Ring                 # or Tree; benchmark both
export NCCL_NET_GDR_LEVEL=SYS         # GPU Direct RDMA
export NCCL_NET_GDR_READ=1
export NCCL_BUFFSIZE=8388608          # modern NCCL often auto-tunes well; measure before overriding
export NCCL_P2P_LEVEL=NVL
export NCCL_CROSS_NIC=1
```

Behavior depends on NCCL version. Check with
`python -c "import torch; print(torch.cuda.nccl.version())"` or the
`NCCL version` line in the training log.

### Recommended environment (p4d / p4de)

```bash
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export NCCL_PROTO=Simple
export NCCL_ALGO=Ring
```

### Algorithm selection

| `NCCL_ALGO` | Best for                       | Rationale                          |
| ----------- | ------------------------------ | ---------------------------------- |
| Ring        | Small messages, small clusters | Lower latency                      |
| Tree        | Large messages, large clusters | Better bandwidth via hierarchical  |
| (unset)     | Most workloads                 | NCCL auto-selects per message size |

Benchmark both with nccl-tests for the specific workload.

---

## 3. Cross-Node Bandwidth

### nccl-tests

Build once:

```bash
git clone https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests
make MPI=1 NCCL_HOME=/opt/amazon/nccl CUDA_HOME=/usr/local/cuda
```

Run across two nodes:

```bash
# Slurm
sbatch --nodes=2 --ntasks-per-node=8 --gpus-per-node=8 --wrap \
  "./build/all_reduce_perf -b 1M -e 4G -f 2 -g 1"

# EKS: MPI Operator (kubeflow/mpi-operator) or Volcano + mpirun.
# nccl-tests ships in nvcr.io/nvidia/pytorch:<tag>.
```

Inspect `busbw` at ≥ 1 GB messages:

| Instance        | Expected 2-node `busbw` |
| --------------- | ----------------------- |
| p5 / p5e / p5en | 380–420 GB/s            |
| p4d / p4de      | 35–45 GB/s              |

Significantly below expected: EFA misconfiguration, missing
self-referencing security-group rule, no placement group, EFAv3 driver
drift on p5en, or hardware fault.

### Point-to-point

```bash
# node A
fi_pingpong -p efa -e rdm
# node B
fi_pingpong -p efa -e rdm <node-A-private-IP>
```

---

## 4. Straggler Detection

Training is slow or stuck with no error messages → stack-trace
aggregation identifies the outlier.

### Principle

In synchronized training, healthy nodes execute the same code path at
roughly the same time. A node stuck elsewhere (collective wait, I/O,
slow kernel) stands out.

### Capture stacks simultaneously

[py-spy](https://github.com/benfred/py-spy) is a sampling profiler
that attaches to a running Python process (`pip install py-spy`).

Caveats before running on a live job:

- `py-spy dump` uses `ptrace` to briefly pause the target. Under load
  the pause can stretch to several seconds and may trip the PyTorch
  NCCL watchdog (`TORCH_NCCL_*_TIMEOUT_SEC`), aborting the job.
  Coordinate with the owner.
- `ptrace` requires `CAP_SYS_PTRACE` or a matching UID. With
  `/proc/sys/kernel/yama/ptrace_scope=1` only the same user can
  attach; with `2`, only root can.
- Do not suppress errors on the first attempt; surface missing tools
  and permission issues.

```bash
for pid in $(pgrep -f 'python.*train'); do
  echo "=== PID $pid ==="
  py-spy dump --pid "$pid" --format raw
done
```

For NCCL-level tracing (requires job restart):

```bash
export TORCH_NCCL_ENABLE_MONITORING=1
```

### Group by similarity

- **Majority pattern**: healthy baseline.
- **Minority pattern** (1–3 nodes): suspect.

### Identify the root cause

Not every outlier is the cause. In pipeline parallelism a stuck node
blocks its PP group; blocked nodes show passive waits (`irecv`). The
active outlier (slow kernel, stalled I/O) is the source.

### Fail-slow

When all nodes progress but one is slow, a single snapshot is
inconclusive. Take 5 snapshots at 10-second intervals. The node
appearing in the minority most often is degraded.

### Common patterns

| Stack signature                                      | Meaning                                 |
| ---------------------------------------------------- | --------------------------------------- |
| `ncclKernel_AllReduce → ncclProxyProgress → blocked` | NCCL waiting on network — NIC or switch |
| `isend/irecv → ProcessGroupNCCL → blocked`           | Pipeline P2P stuck                      |
| `DataLoader.__next__ → Queue.get → blocked`          | Data loading stalled                    |
| `torch.save → write → blocked`                       | Synchronous checkpoint blocking on disk |
| `aten::matmul → cudaStreamSynchronize → blocked`     | GPU kernel not completing — hardware    |

### GDB for native hangs

```bash
gdb -p <pid> -batch -ex "thread apply all bt"
```

Reveals CUDA driver and NCCL library state. Same precautions as
`py-spy`: `gdb -p` uses `PTRACE_ATTACH` and stops the target for the
duration of the command. On `kernel.yama.ptrace_scope=1` only same-UID
attach; with `2`, only root.

---

## 5. Common HyperPod Network Issues

### EFA security-group rule missing

EFA requires a self-referencing rule permitting all traffic between
nodes in the same group. Without it, NCCL falls back to TCP.

**Check**: inbound and outbound rules with protocol `All` and
source/destination = the security group itself.

### Placement group missing

All training nodes must share a single cluster placement group for
low-latency networking.

**Check**: verify in the HyperPod cluster configuration.

### OFI NCCL plugin absent after replacement

A replaced node may be missing the AWS OFI NCCL plugin if the
lifecycle script failed to install it.

```bash
# Current HyperPod AMIs:
ls /opt/amazon/ofi-nccl/lib/libnccl-net.so 2>/dev/null || echo "MISSING"

# Legacy layout:
ls /opt/aws-ofi-nccl/lib/libnccl-net.so 2>/dev/null
ls /opt/amazon/efa/lib64/libnccl-net.so 2>/dev/null
```

Per the [HyperPod EKS AMI release notes](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-release-ami-eks.html),
the EFA installer now includes OFI NCCL under `/opt/amazon/ofi-nccl/`
rather than the legacy `/opt/aws-ofi-nccl/`.

**Fix**: ensure lifecycle scripts install the EFA installer and the
NCCL plugin. Compare with `hyperpod-version-checker`.

### `/dev/shm` too small for NCCL

```bash
df -h /dev/shm       # minimum 16 GB; 64 GB+ recommended
```

- Slurm: `#SBATCH --mem=0`.
- EKS: `--shm-size=64g` in the pod spec, or `emptyDir` at `/dev/shm`
  with `medium: Memory`.

---

## References

**EFA / libfabric (§1):**

- EFA user guide:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html
- P5 EFA (3,200 Gbps):
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/p5-efa.html
- libfabric `fi_info`:
  https://ofiwg.github.io/libfabric/main/man/fi_info.1.html
- InfiniBand port counters:
  https://docs.nvidia.com/networking/display/ufmsdnappumv4184/infiniband+port+counters

**NCCL and NCCL-EFA (§2):**

- NCCL environment variables:
  https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html
- AWS libfabric EFA variables:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start-nccl.html
- `aws-ofi-nccl`: https://github.com/aws/aws-ofi-nccl
- HyperPod AMI release notes (OFI NCCL path):
  https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-release-ami-eks.html

**Bandwidth (§3):**

- nccl-tests: https://github.com/NVIDIA/nccl-tests
- HyperPod performance testing:
  https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests
- Kubeflow MPI Operator: https://github.com/kubeflow/mpi-operator
- `fi_pingpong`:
  https://ofiwg.github.io/libfabric/main/man/fi_pingpong.1.html

**Stragglers (§4):**

- py-spy: https://github.com/benfred/py-spy
- `TORCH_NCCL_ENABLE_MONITORING`:
  https://docs.pytorch.org/docs/stable/torch_nccl_environment_variables.html
- Llama 3 §5.1 on straggler detection (Grattafiori et al. 2024):
  https://ai.meta.com/research/publications/the-llama-3-herd-of-models/

**HyperPod networking (§5):**

- EFA security-group requirements:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html
- EC2 placement groups:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-groups.html
- Kubernetes `emptyDir` with `medium: Memory`:
  https://kubernetes.io/docs/concepts/storage/volumes/#emptydir
