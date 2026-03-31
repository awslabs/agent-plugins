---
name: hyperpod-version-checker
description: Check and compare software component versions on SageMaker HyperPod cluster nodes - NVIDIA drivers, CUDA toolkit, cuDNN, NCCL, EFA, AWS OFI NCCL, GDRCopy, MPI, Neuron SDK (Trainium/Inferentia), Python, and PyTorch. Use when checking component versions, verifying CUDA/driver compatibility, detecting version mismatches across nodes, planning upgrades, documenting cluster configuration, or troubleshooting version-related issues on HyperPod. Triggers on requests about versions, compatibility, component checks, or upgrade planning for HyperPod clusters.
metadata:
  version: "1.0.0"
---

# HyperPod Version Checker

Upload to cluster nodes via `hyperpod-ssm` skill, then execute.

## Usage

```bash
# Text report to console + file
bash hyperpod_check_versions.sh

# JSON only to stdout (text report still saved to file) — best for piping/parsing
bash hyperpod_check_versions.sh --json

# Custom output file
bash hyperpod_check_versions.sh --output /tmp/versions.txt

# No color (for logging)
bash hyperpod_check_versions.sh --no-color
```

Output file: `component_versions_<hostname>_<timestamp>.txt` (default)

## What It Checks

| Component         | Detection Method                                | Applicable When                               |
| ----------------- | ----------------------------------------------- | --------------------------------------------- |
| NVIDIA Driver     | `nvidia-smi`                                    | GPU instances (p3/p4/p5/g5)                   |
| CUDA Toolkit      | `nvcc`, `/usr/local/cuda` symlink               | GPU instances                                 |
| cuDNN             | Header file, packages                           | GPU instances doing deep learning             |
| NCCL              | Library filename, header, packages              | Distributed GPU training                      |
| EFA               | `/opt/amazon/efa_installed_packages`, `fi_info` | EFA-capable instances (p4d/p4de/p5/trn1/trn2) |
| AWS OFI NCCL      | `efa_installed_packages`, library search        | EFA + NCCL workloads                          |
| GDRCopy           | rpm/dpkg, kernel module                         | GPU instances with RDMA (p4d+/p5)             |
| MPI               | `mpirun`, `/opt/amazon/openmpi`                 | Distributed training                          |
| Neuron SDK        | `neuronx-cc`, `neuron-ls`, packages             | Trainium/Inferentia (trn1/trn2/inf1/inf2)     |
| Python/PyTorch    | `python3`, `torch` import                       | ML workloads                                  |
| Container runtime | `docker`, `containerd`, `kubectl`, `nvidia-ctk` | EKS clusters                                  |

## Multi-Node Comparison

Run on each node individually via the `hyperpod-ssm` skill. With `--json`, stdout is clean JSON for easy diffing.

## Compatibility Reference

The script automatically analyzes CUDA/driver compatibility. For reference:

| Driver Series | Supported CUDA                |
| ------------- | ----------------------------- |
| 580+          | 13.x, 12.x, 11.x              |
| 570+          | 12.8+ (Blackwell), 12.x, 11.x |
| 545+          | 12.3-12.7, 11.x               |
| 525-535       | 12.0-12.2, 11.x               |
| 450+          | 11.x only                     |

NCCL: Use 2.18+ for CUDA 12.x, 2.12+ for CUDA 11.x. Must be consistent across all nodes.

| EFA Installer | AWS OFI NCCL          |
| ------------- | --------------------- |
| 1.29+         | v1.7.3+ (recommended) |
| 1.26-1.28     | v1.7.0-v1.7.2         |
| 1.20-1.25     | v1.6.0+               |
