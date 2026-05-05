# Lifecycle Script Reference for HyperPod Clusters

Deep-dive companion to the main [SKILL.md](../SKILL.md) § C (Lifecycle Scripts) and to [cluster-operations.md § 3 (Lifecycle Script Debugging)](cluster-operations.md). Lifecycle scripts run on each node during provisioning — they configure the software stack (Slurm daemons, filesystem mounts, container runtimes, EFA drivers). A failure here blocks the node (and often the entire cluster) from reaching `InService`.

---

## S3 Structure

### Slurm Lifecycle Scripts

```
s3://sagemaker-lifecycle-<guid>/
  on_create.sh                       # Entry point (REQUIRED) — calls lifecycle_script.py
  lifecycle_script.py                 # Main orchestration — detects node type, runs scripts in order
  config.py                          # Feature toggles (Docker, observability, SSSD, etc.)
  provisioning_parameters.json       # Cluster topology parameters
  start_slurm.sh                     # Starts slurmctld (controller) or slurmd (compute)
  mount_fsx.sh                       # FSx Lustre mount
  mount_fsx_openzfs.sh               # FSx OpenZFS mount (optional)
  add_users.sh                       # Creates users from shared_users.txt
  shared_users.txt                   # username,uid,home per line
  setup_mariadb_accounting.sh        # Local DB for Slurm accounting
  setup_rds_accounting.sh            # RDS-based Slurm accounting (optional)
  setup_user_associations.sh         # Slurm user/account/QOS associations
  apply_hotfix.sh                    # Runs all scripts in hotfix/ directory
  prolog.sh                          # Slurm job prolog (GPU device mapping)
  epilog.sh                          # Slurm job epilog (GPU cleanup)
  setup_sssd.py                      # Active Directory / LDAP integration (optional)
  hotfix/                            # Drop-in hotfix scripts (run alphabetically)
  multi_headnode_setup/              # Multi-head-node Slurm configuration
  observability/                     # Prometheus exporters, OTEL, metrics
  utils/
    install_ansible.sh               # Always first — required by other scripts
    install_docker.sh                # Docker + NVIDIA Container Toolkit
    install_enroot_pyxis.sh          # Enroot + Pyxis for Slurm container jobs
    motd.sh                          # Message of the day
    fsx_ubuntu.sh                    # FSx client for Ubuntu
    fsx_auto_detect.sh               # Auto-detect FSx filesystem
    gen-keypair-ubuntu.sh            # SSH key generation
    ssh-to-compute.sh                # SSH configuration (controller → compute)
    mount-s3.sh                      # Mountpoint for Amazon S3
    enable_slurm_log_rotation.sh     # Slurm log rotation
    slurm_fix_plugstackconf.sh       # SPANK plugin config fix
    pam_adopt_cgroup_wheel.sh        # PAM cgroup adoption for Slurm
```

### EKS Lifecycle Scripts

```
s3://sagemaker-lifecycle-<guid>/
  on_create.sh                       # Entry point — calls on_create_main.sh
  on_create_main.sh                  # Configures containerd, kubelet, FSx client, EFA
```

### S3 URI Validation

The `SourceS3Uri` in the cluster configuration must:

- Start with `s3://`
- The `OnCreate` filename must match an actual S3 key in that prefix
- The execution role must have `s3:GetObject` and `s3:ListBucket` on the bucket

---

## Execution Flow

### Slurm: Detailed Order

```
1. on_create.sh
   ├── Creates /var/log/provision/provisioning.log
   ├── Sleeps 30s (DNS stabilization)
   ├── Reads /opt/ml/config/resource_config.json
   └── Calls: python3 lifecycle_script.py

2. lifecycle_script.py
   ├── install_ansible.sh          ← always first
   ├── mount_fsx.sh                ← if FSx DNS+mountname in config
   ├── mount_fsx_openzfs.sh        ← if enable_fsx_openzfs=True in config.py
   ├── add_users.sh
   ├── [Detect node type via IP matching against resource_config.json]
   │   ├── Controller: matched against controller_group IPs
   │   ├── Login: matched against login_group IPs
   │   └── Compute: everything else
   ├── Wait for slurm.conf to contain controller IPs
   ├── [Controller only] setup_mariadb_accounting.sh OR multi_headnode_setup
   ├── apply_hotfix.sh             ← runs hotfix/*.sh alphabetically
   ├── motd.sh
   ├── fsx_ubuntu.sh / fsx_auto_detect.sh
   ├── start_slurm.sh             ← slurmctld (controller) or slurmd (compute/login)
   ├── [Controller only] setup_user_associations.sh
   ├── gen-keypair-ubuntu.sh
   ├── ssh-to-compute.sh
   ├── [Optional] Docker/Enroot/Pyxis
   ├── [Optional] Observability stack
   ├── [Optional] SSSD
   ├── [Optional] pam_slurm_adopt
   ├── [Optional] mount-s3
   └── [Optional] Slurm log rotation
```

### EKS: Detailed Order

```
1. on_create.sh → on_create_main.sh
   ├── Configure containerd storage at /opt/sagemaker
   ├── Wait for disk mount (up to 60s)
   ├── Create kubelet symlink: /var/lib/kubelet → /opt/sagemaker
   ├── Install FSx Lustre client (if EFA available)
   ├── Load kernel modules: lnet, lustre
   └── Error handling: wait 60s before exit (ensure log upload)
```

### Node Type Detection (Slurm)

The lifecycle script reads `/opt/ml/config/resource_config.json` and matches the current node's IP against the instance groups to determine if it is a controller, login, or compute node.

**Controller nodes provision first.** Compute and login nodes wait for the controller to be ready (specifically, they wait for `slurm.conf` to contain the controller IPs on the shared filesystem).

If the controller's lifecycle script fails, **all compute nodes will also fail** because they cannot find `slurm.conf`.

---

## config.py Feature Toggles

| Toggle                       | Default | What It Does                                             |
| ---------------------------- | ------- | -------------------------------------------------------- |
| `enable_docker_enroot_pyxis` | `True`  | Installs Docker, NVIDIA Container Toolkit, Enroot, Pyxis |
| `enable_observability`       | `False` | Installs Prometheus exporters, OTEL collector            |
| `enable_pam_slurm_adopt`     | `False` | PAM module for Slurm cgroup enforcement                  |
| `enable_sssd`                | `False` | Active Directory / LDAP integration                      |
| `enable_mount_s3`            | `False` | Mountpoint for Amazon S3                                 |
| `enable_fsx_openzfs`         | `False` | FSx OpenZFS filesystem support                           |
| `enable_slurm_log_rotation`  | `True`  | Rotate Slurm daemon logs                                 |
| `s3_bucket`                  | `""`    | Required if `enable_mount_s3=True`                       |

Modify `config.py` in S3 before cluster creation to enable/disable features.

---

## Common Lifecycle Errors and Fixes

### S3 Access Errors

**Error:** `Connect timeout on endpoint URL: s3://...`
**Cause:** No S3 VPC endpoint; node cannot reach S3 from private subnet.
**Fix:** Add an S3 Gateway VPC endpoint to the subnet's route table:

```bash
aws ec2 create-vpc-endpoint \
  --vpc-id <VPC_ID> \
  --service-name com.amazonaws.<REGION>.s3 \
  --route-table-ids <ROUTE_TABLE_ID> \
  --vpc-endpoint-type Gateway
```

**Error:** `AccessDenied` / `403 Forbidden` on S3 GetObject
**Cause:** Execution role missing S3 permissions.
**Fix:** Add to the execution role's IAM policy:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::sagemaker-lifecycle-*",
    "arn:aws:s3:::sagemaker-lifecycle-*/*"
  ]
}
```

### Script Execution Errors

**Error:** `No such file or directory` for the entry script
**Cause:** `OnCreate` filename doesn't match S3 key.
**Fix:** Verify `on_create.sh` exists at the exact path in S3:

```bash
aws s3 ls s3://<BUCKET>/ | grep on_create
```

**Error:** `CRLF line terminators` or `\r: command not found`
**Cause:** Script edited on Windows has `\r\n` line endings.
**Fix:**

```bash
# Convert before uploading:
dos2unix on_create.sh
# Or via sed:
sed -i 's/\r$//' on_create.sh
# Verify:
file on_create.sh   # Should show "ASCII text" NOT "with CRLF line terminators"
```

**Error:** `Permission denied` when executing script
**Cause:** Script not marked executable.
**Fix:** HyperPod downloads scripts from S3 and should set execute permissions automatically. If this fails:

- Ensure the script has a proper shebang: `#!/bin/bash`
- Upload with correct content type: `aws s3 cp on_create.sh s3://<BUCKET>/ --content-type text/x-shellscript`

**Error:** Script hangs indefinitely (lifecycle timeout)
**Cause:** Blocking operation without timeout, infinite loop, or waiting for a resource that never becomes available.
**Fix:**

- Add `set -euo pipefail` at the top of scripts
- Add timeouts to network operations
- Test scripts locally before uploading
- Check if compute nodes are waiting for controller (controller lifecycle must succeed first)

### provisioning_parameters.json Errors

**Error:** `provisioning_parameters.json` parsing failure or `KeyError`
**Cause:** Instance group names in `provisioning_parameters.json` don't match the names in the `create-cluster` API call.
**Fix:** Ensure exact match between:

- `InstanceGroupName` in the `create-cluster` API call
- `controller_group`, `login_group`, `worker_group_<N>` in `provisioning_parameters.json`

### Slurm-Specific Errors

**Error:** Compute nodes fail because `slurm.conf` not found
**Cause:** Controller node's lifecycle script failed, so `slurm.conf` was never written to shared storage.
**Fix:** Fix the controller node's lifecycle script first. Controller errors cascade to all compute nodes.

**Error:** `slurmctld: error: ...`
**Cause:** Slurm configuration error.
**Fix:** Check `/var/log/slurmctld.log` on the controller node (via SSM). Common issues:

- Wrong `SlurmctldHost` in `slurm.conf`
- Incorrect partition/node definitions
- Missing MUNGE key

### FSx Mount Errors

**Error:** `mount.lustre: ... Connection timed out`
**Cause:** FSx filesystem in different VPC/AZ or security group doesn't allow traffic.
**Fix:**

- FSx and HyperPod nodes must be in the same VPC
- Security group must allow traffic between nodes and FSx (TCP 988, 1018-1023)
- Verify FSx filesystem is in `AVAILABLE` state

---

## Debugging Procedures

### Read Lifecycle Logs from CloudWatch

```bash
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <NAME> --region <R> \
  --query 'ClusterArn' --output text | cut -d/ -f2)
LOG_GROUP="/aws/sagemaker/Clusters/<CLUSTER_NAME>/${CLUSTER_ID}"

# List all lifecycle log streams:
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" --region <R> \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].{Stream:logStreamName,LastEvent:lastEventTimestamp}' \
  --output table

# Read last 100 events from a specific stream:
aws logs get-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "LifecycleConfig/<GROUP>/<INSTANCE_ID>" \
  --region <R> --limit 100 \
  --query 'events[*].message' --output text
```

### Read Lifecycle Logs On-Node (via SSM)

If the node reached a state where SSM is available:

```bash
# Full provisioning log:
cat /var/log/provision/provisioning.log

# Resource config (node topology):
cat /opt/ml/config/resource_config.json

# Slurm config (if generated):
cat /opt/slurm/etc/slurm.conf

# Node metadata:
cat /opt/ml/metadata/resource-metadata.json
```

### Test Scripts Locally

Before deploying to a cluster, test lifecycle scripts on a compatible EC2 instance:

1. Launch an instance with the same AMI and instance type
2. Install the same IAM role
3. Create a mock `/opt/ml/config/resource_config.json`
4. Run the scripts manually and check for errors

### Compare Against Reference Scripts

Always diff your scripts against the latest upstream versions:

- **Slurm:** https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config
- **EKS:** https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/7.sagemaker-hyperpod-eks/LifecycleScripts/base-config

Check the commit history for recent bug fixes — upstream fixes often resolve lifecycle failures.

---

## IAM Permissions for Lifecycle Scripts

The execution role attached to the instance group needs:

**S3 access (lifecycle script download):**

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::<BUCKET_NAME>",
    "arn:aws:s3:::<BUCKET_NAME>/*"
  ]
}
```

**CloudWatch logs (script output):**

```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "arn:aws:logs:<REGION>:<ACCOUNT>:log-group:/aws/sagemaker/Clusters/*"
}
```

**VPC operations:**

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateNetworkInterface",
    "ec2:CreateNetworkInterfacePermission",
    "ec2:DeleteNetworkInterface",
    "ec2:DeleteNetworkInterfacePermission",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeVpcs",
    "ec2:DescribeDhcpOptions",
    "ec2:DescribeSubnets",
    "ec2:DescribeSecurityGroups",
    "ec2:DetachNetworkInterface",
    "ec2:CreateTags"
  ],
  "Resource": "*"
}
```
