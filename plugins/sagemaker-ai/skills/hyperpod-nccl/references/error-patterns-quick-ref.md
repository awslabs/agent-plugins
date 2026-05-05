# NCCL Error Pattern Reference & Common Fixes

Quick-reference for NCCL error patterns detected by the diagnostic script and
common issues with immediate fixes.

---

## NCCL Error Pattern Reference (38 patterns)

| Log Pattern                                | Code                    | Root Cause                        | Fix                                     |
| ------------------------------------------ | ----------------------- | --------------------------------- | --------------------------------------- |
| **Rendezvous / Connection**                |                         |                                   |                                         |
| `Timeout waiting for`                      | `TIMEOUT_RENDEZVOUS`    | Peers not joining init            | SG self-ref, NetworkPolicy, MASTER_ADDR |
| `Connection refused`                       | `CONN_REFUSED`          | Rank-0 not listening              | Fix MASTER_ADDR + headless service      |
| `Address already in use`                   | `PORT_CONFLICT`         | Port 29500 bound                  | Change MASTER_PORT to 29501             |
| `NCCL WARN Connect to`                     | `CONNECT_FAIL`          | NCCL peer blocked                 | SG self-ref + NetworkPolicy             |
| `network is unreachable`                   | `NET_UNREACHABLE`       | No route to MASTER_ADDR           | DNS + VPC routing + SG                  |
| `Error in Store` / `DistStoreError`        | `STORE_ERR`             | c10d rendezvous timeout           | Fix network first                       |
| `RendezvousConnectionError`                | `RDZV_CONN_ERR`         | Elastic rendezvous failed         | MASTER_ADDR DNS + SG                    |
| `RendezvousTimeout`                        | `RDZV_TIMEOUT`          | Elastic rendezvous timed out      | Peers not reachable                     |
| `Name or service not known`                | `DNS_FAIL`              | DNS resolution failed             | Create headless service                 |
| `getaddrinfo failed`                       | `DNS_FAIL`              | DNS resolution failed             | CoreDNS + headless service              |
| **Runtime / AllReduce**                    |                         |                                   |                                         |
| `Watchdog timeout`                         | `WATCHDOG_TIMEOUT`      | AllReduce timed out               | Increase NCCL_TIMEOUT; find straggler   |
| `unhandled system error`                   | `SYSTEM_ERROR`          | GPU/EFA hardware                  | SSM: dmesg XID errors; reboot node      |
| `unhandled cuda error`                     | `CUDA_ERROR`            | CUDA runtime error                | GPU driver crash or hardware fault      |
| `peer access is not supported`             | `P2P_FAIL`              | GPU P2P blocked by ACS/IOMMU      | Disable ACS; check IOMMU                |
| `NCCL WARN Cuda failure`                   | `CUDA_ERROR`            | CUDA failure inside NCCL          | GPU hardware or driver issue            |
| **EFA / Libfabric**                        |                         |                                   |                                         |
| `fi_getinfo failed`                        | `EFA_INIT_FAIL`         | EFA not available                 | Fix EFA; use gloo on non-EFA            |
| `NCCL_OFI_RDMA`                            | `OFI_ERROR`             | aws-ofi-nccl broken               | Check plugin + EFA version              |
| `Call to ibv_reg_mr failed`                | `RDMA_REG_FAIL`         | memlock=0 blocks EFA RDMA         | `ulimit -l 8388608`                     |
| `NET/OFI Using TCP`                        | `EFA_TCP_FALLBACK`      | Fell back to TCP                  | Fix EFA device plugin + env             |
| `Failed to load NCCL`                      | `NCCL_LOAD_FAIL`        | libnccl.so missing                | Check LD_LIBRARY_PATH                   |
| `libnccl-net.so`                           | `OFI_LOAD_FAIL`         | OFI plugin missing                | Install aws-ofi-nccl                    |
| **OOM / Resource Limits**                  |                         |                                   |                                         |
| `OOMKilled`                                | `OOM_KILL`              | Pod out of memory                 | Reduce batch size; increase limits      |
| `CUDA out of memory` / `cudaMalloc failed` | `CUDA_OOM`              | GPU VRAM exhausted                | Reduce batch size, enable ZeRO          |
| `failed to extend /dev/shm` / `Bus error`  | `SHM_FULL`              | /dev/shm too small                | emptyDir medium:Memory 10Gi             |
| **Version / Config**                       |                         |                                   |                                         |
| `NCCL function not found`                  | `NCCL_VERSION_MISMATCH` | Mixed NCCL versions               | Use identical container images          |
| `Incompatible NCCL version`                | `NCCL_VERSION_MISMATCH` | Mixed NCCL versions               | Use identical container images          |
| `Could not find interface`                 | `IFACE_NOT_FOUND`       | Bad NCCL_SOCKET_IFNAME            | Set `^lo,docker,efa,veth,virbr`         |
| `world_size mismatch`                      | `WORLD_SIZE_MISMATCH`   | WORLD_SIZE ≠ ranks                | WORLD_SIZE = pods × GPUs/pod            |
| `doesn't have NCCL built in`               | `NCCL_NOT_BUILT`        | PyTorch without NCCL              | Use AWS DLC image                       |
| `CUDA_VISIBLE_DEVICES`                     | `CUDA_VIS_DEV`          | GPUs hidden from training         | Remove CUDA_VISIBLE_DEVICES             |
| **Stale State**                            |                         |                                   |                                         |
| `unlink shared memory`                     | `SHM_STALE`             | Stale /dev/shm/nccl-* files       | Set RemoveIPC=no; clean up              |
| **Additional Critical**                    |                         |                                   |                                         |
| `Call to ncclCommAbort`                    | `NCCL_COMM_ABORT`       | Communicator aborted              | Check for straggler or hardware fault   |
| `MNNVL topology`                           | `MNNVL_TOPO_FAIL`       | Topology search stack overflow    | `ulimit -l 8388608 -s 8192`             |
| `ENOMEM`                                   | `ENOMEM`                | Memory alloc/registration failure | Check memlock limits + GPU memory       |
| `invalid alignment`                        | `CUDA_ALIGN_ERR`        | CUDA memory alignment error       | Check driver/NCCL version compat        |

---

## Common Issues & Immediate Fixes

### Training hangs immediately (no error, just timeout)

**Most likely: Security Group missing self-reference rule.**

```bash
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION>
# Look for: [FAIL] Inbound self-reference: MISSING
```

For remediation, see `operations.md § Security Groups`.

### NCCL picks wrong interface (hangs silently)

```bash
# Add to job env:
NCCL_SOCKET_IFNAME=^lo,docker,efa,veth,virbr
FI_PROVIDER=efa
FI_EFA_USE_DEVICE_RDMA=1
```

### `failed to extend /dev/shm/nccl-*` / Bus error

```yaml
volumes:
- name: dshm
  emptyDir: {medium: Memory, sizeLimit: "10Gi"}
volumeMounts:
- name: dshm
  mountPath: /dev/shm
```

### Slurm node down after training crash

```bash
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --orchestrator slurm
```

For remediation, see `operations.md § Slurm Node Management`.

### Timeout on large clusters (64+ nodes)

```bash
export NCCL_TIMEOUT=$(( NODE_COUNT * 5 + 600 ))
# 64 nodes → 920s, 128 nodes → 1240s, 256 nodes → 1880s
```

### `Call to ibv_reg_mr failed` — EFA RDMA fails

```bash
# On node via SSM:
ulimit -l  # should be unlimited or ≥8388608
echo "* soft memlock 8388608" >> /etc/security/limits.conf
echo "* hard memlock 8388608" >> /etc/security/limits.conf
```

### Training slow — suspected straggler node

```bash
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --sample-nodes 20
# Look for: [WARN] fi_ping latency >20us, [FAIL] NVLink errors, [FAIL] GPU XID ERRORS
# Then replace: aws sagemaker batch-replace-cluster-nodes --cluster-name <NAME> \
#   --region <REGION> --node-ids '["<INSTANCE_ID>"]'
```
