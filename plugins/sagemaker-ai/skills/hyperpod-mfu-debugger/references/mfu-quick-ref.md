# MFU Quick Reference

```
MFU = (tokens_per_sec × 6 × num_params) / (num_accelerators × peak_tflops)
```

`6N` = forward (2N) + backward (4N). For Trainium, substitute
`num_chips` and per-chip BF16 TFLOPS.

| Instance      | Accelerator | Per node | BF16 TFLOPS/chip | EFA                |
| ------------- | ----------- | -------- | ---------------- | ------------------ |
| p4d.24xlarge  | A100 40 GB  | 8        | 312              | 400 Gbps (4×100)   |
| p4de.24xlarge | A100 80 GB  | 8        | 312              | 400 Gbps (4×100)   |
| p5.48xlarge   | H100 80 GB  | 8        | 989              | 3,200 Gbps (EFAv2) |
| p5e.48xlarge  | H200 141 GB | 8        | 989              | 3,200 Gbps (EFAv2) |
| p5en.48xlarge | H200 141 GB | 8        | 989              | 3,200 Gbps (EFAv3) |
| trn1.32xlarge | Trainium    | 16       | 190              | 800 Gbps           |
| trn2.48xlarge | Trainium2   | 16       | 667              | 3,200 Gbps         |

H100 and H200 have identical dense compute; H200 differs in HBM
(141 GB HBM3e @ 4.8 TB/s vs 80 GB HBM3 @ 3.35 TB/s). p5en EFAv3 on
Nitro v5 reduces collective latency up to 35% vs p5/p5e.

NVLink: 900 GB/s per GPU (H100/H200; 3.6 TB/s bisectional across the
8-GPU NVSwitch fabric); 600 GB/s per GPU (A100).

Use `neuron-top` / `neuron-monitor` on Trainium. Formula unchanged.

---

## References

**Instance specifications:**

- EC2 P5 family (H100/H200, 3,200 Gbps EFA):
  https://aws.amazon.com/ec2/instance-types/p5/
- p5en EFAv3 on Nitro v5 (up to 35% lower latency):
  https://aws.amazon.com/blogs/aws/new-amazon-ec2-p5en-instances-with-nvidia-h200-tensor-core-gpus-and-efav3-networking/
- H100/H200 BF16 Tensor Core TFLOPS (989 dense, 1,979 sparse):
  https://docs.nvidia.com/dgx/dgxh100-user-guide/introduction-to-dgxh100.html
- A100 BF16 Tensor Core (312 dense):
  https://developer.nvidia.com/blog/nvidia-ampere-architecture-in-depth/
- Trainium2 per-chip (667 BF16/FP16/TF32, 1,299 FP8; 16 chips):
  https://awsdocs-neuron.readthedocs-hosted.com/en/latest/general/arch/neuron-hardware/trainium2.html
- Trainium v1 per-chip (190 BF16/FP16; 16 chips; 800 Gbps EFA):
  https://aws.amazon.com/machine-learning/trainium/,
  https://aws.amazon.com/about-aws/whats-new/2022/10/ec2-trn1-instances-high-performance-cost-effective-deep-learning-training/
- EC2 P4 family (A100, 400 Gbps EFA):
  https://aws.amazon.com/ec2/instance-types/p4/
- NVLink 4 on H100/H200 (900 GB/s per GPU, 3.6 TB/s bisectional):
  https://docs.nvidia.com/dgx/dgxh100-user-guide/introduction-to-dgxh100.html
- NVLink 3 on A100 (600 GB/s per GPU):
  https://www.nvidia.com/en-us/data-center/nvlink/

**MFU formula and baselines:**

- `6N` approximation (Kaplan et al. 2020; Chowdhery et al. 2022 / PaLM):
  https://arxiv.org/abs/2001.08361, https://arxiv.org/abs/2204.02311
- MegaScale 55.2% MFU at 175B / 12,288 GPUs (Jiang et al., NSDI 2024):
  https://www.usenix.org/conference/nsdi24/presentation/jiang-ziheng
- PyTorch FSDP 57% MFU at 7B / 512 GPUs:
  https://pytorch.org/blog/maximizing-training/

**Monitoring:**

- DCGM and dcgm-exporter:
  https://github.com/NVIDIA/DCGM, https://github.com/NVIDIA/dcgm-exporter
