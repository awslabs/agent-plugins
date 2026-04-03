# Collection Details

## What Gets Collected

### Common (Both EKS and Slurm)

- `nvidia_smi.txt` — GPU status, utilization, memory, temperature
- `resource_config.json` — HyperPod resource config from `/opt/ml/config/resource_config.json`
- `cluster_logs/` — Contents of `/var/log/aws/clusters/`
- `systemd_services.txt` — All systemd service statuses
- `disk_usage.txt` — `df` output
- `hostname.txt`, `instance_group.txt`, `instance_id.txt`, `cluster_type.txt`, `timestamp.txt`

### EKS-Specific (Per-Node)

- `containerd_status.txt` — `systemctl status containerd`
- `kubelet_status.txt` — `systemctl status kubelet`
- `eks-log-collector-output.txt` — EKS log collector execution log
- `eks-logs/` — EKS log collector output subdirectories:
  - `cni/` — CNI plugin logs and config
  - `containerd/` — Runtime logs, config, version, images, containers, tasks, plugins
  - `docker/` — Docker logs (if present)
  - `gpu/` — GPU diagnostics
  - `ipamd/` — AWS VPC CNI IPAMD logs
  - `kernel/` — dmesg output, uname info
  - `kubelet/` — Kubelet logs and config
  - `modinfo/` — Kernel module info (lustre, ip_vs, etc.)
  - `networking/` — Network config, iptables, routes, interfaces
  - `nodeadm/` — Node administration logs
  - `sandbox-image/` — Sandbox image info
  - `storage/` — Mounts, inodes, lsblk, LVM, fstab, XFS, pod local storage
  - `sysctls/` — Kernel parameters
  - `system/` — Services, systemd-analyze, top, ps, netstat, CPU/IO throttling
  - `var_log/` — System logs from /var/log

### EKS-Specific (kubectl — Collected Locally)

Packaged as `kubectl_resources.tar.gz`, collected from the local machine (not from nodes).

**High Priority:**

- `nodes_describe.txt` — Detailed node descriptions (capacity, conditions, running pods)
- `pods_all_namespaces.txt` / `pods_describe_all_namespaces.txt` — All pods with details
- `events_all_namespaces.txt` — Cluster events sorted by timestamp
- `pvcs_all_namespaces.txt` / `pvcs_describe_all_namespaces.txt` — PersistentVolumeClaims
- `services_all_namespaces.txt` / `services_describe_all_namespaces.txt` — Network endpoints

**Medium Priority:**

- `deployments_all_namespaces.txt`, `statefulsets_all_namespaces.txt`, `daemonsets_all_namespaces.txt`
- `configmaps_all_namespaces.txt`, `secrets_all_namespaces.txt` (metadata only)
- `resourcequotas_all_namespaces.txt`, `networkpolicies_all_namespaces.txt`

### Slurm-Specific

- `sinfo.txt` — Node and partition information
- `sinfo_R.txt` — Reasons for node down/drain states
- `slurmctld_status.txt` — Slurm controller daemon status
- `slurmd_status.txt` — Slurm compute node daemon status
- `opt_slurm_etc/` — Slurm configuration from `/opt/slurm/etc/`
- `nvidia-bug-report.log.gz` — NVIDIA bug report (compressed)
- `syslog`, `kern.log` — System logs
- `dmesg_T.txt` — Kernel ring buffer with timestamps
- `var_log_slurm/` — Slurm logs from `/var/log/slurm/`

### Custom Commands

User-specified commands are saved as `command_01_<sanitized_name>.txt`, `command_02_...`, etc.

## Report Output Structure

```
s3://bucket/prefix/cluster-name/YYYYMMDD_HHMMSS/
├── collector_script.sh
├── summary.json
├── kubectl_resources.tar.gz      # EKS only
└── instances/
    ├── worker1_i-abc123.tar.gz
    └── worker2_i-abc124.tar.gz
```

Tarball filename format: `{instance-group}_{instance-id}.tar.gz`

## Summary JSON Format

```json
{
  "cluster_name": "my-cluster",
  "cluster_id": "abc123",
  "report_id": "20260126_143022",
  "timestamp": "2026-01-26T14:30:22.123456",
  "total_nodes": 8,
  "successful": 7,
  "failed": 1,
  "results": [
    {
      "InstanceId": "i-0123456789abcdef0",
      "NodeGroup": "worker-group",
      "Success": true,
      "Output": "...",
      "ElapsedTime": 45.2
    }
  ]
}
```
