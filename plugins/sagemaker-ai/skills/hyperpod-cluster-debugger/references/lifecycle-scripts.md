# Lifecycle Script Reference

Companion to [SKILL.md](../SKILL.md) § C and [cluster-operations.md § 3](cluster-operations.md). Lifecycle scripts run on each node during provisioning. A failure here blocks the node — and often the entire cluster — from reaching `InService`.

---

## Layout

Default AWS-published lifecycle scripts (commonly called "base-config") handle provisioning for Slurm and EKS. Before deep debugging, compare the customer's in-use scripts against the latest published version — upstream fixes often resolve the failure.

### Slurm entry point (typical base-config layout)

`on_create.sh` → `lifecycle_script.py` for orchestration (detects node type from `/opt/ml/config/resource_config.json` and runs per-type steps). Controller nodes provision first; compute / login nodes wait for the controller to write `slurm.conf` to shared storage. Customer-forked pipelines may differ — read `on_create.sh` on the affected node to confirm.

**Controller failure cascades to all compute nodes** — if the controller's lifecycle script fails, compute nodes cannot find `slurm.conf` and also fail.

### EKS entry point

`on_create.sh` → `on_create_main.sh` (configures containerd storage, kubelet, FSx client, EFA).

### S3 URI validation

- `SourceS3Uri` starts with `s3://`
- `OnCreate` filename matches an S3 key in that prefix
- Execution role has `s3:GetObject` and `s3:ListBucket` on the bucket

---

## Common errors

### S3 access

Timeout reaching S3 from the lifecycle script (e.g. `Connect timeout on endpoint URL: s3://...`) → no S3 VPC endpoint; node cannot reach S3 from a private subnet.

### Fix — add an S3 Gateway endpoint

Customer-run. Gateway endpoint type is free; Interface endpoints are billed per-hour.

```bash
aws ec2 create-vpc-endpoint \
  --vpc-id <VPC_ID> \
  --service-name com.amazonaws.<REGION>.s3 \
  --route-table-ids <ROUTE_TABLE_ID> \
  --vpc-endpoint-type Gateway
```

**Caution:** routes S3 traffic for every resource using the listed route tables through the VPC endpoint. Can break workloads that rely on going to S3 via public DNS + NAT with custom endpoint policies. Review the VPC's default endpoint policy (or set `--policy-document`) before creating.

`AccessDenied` / `403 Forbidden` on `GetObject` — add `s3:GetObject` + `s3:ListBucket` on the lifecycle bucket to the execution role.

### Script execution

| Symptom                                     | Cause                                                   | Fix                                                          |
| ------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------ |
| `No such file or directory` on entry script | `OnCreate` name doesn't match S3 key                    | `aws s3 ls s3://<BUCKET>/ \| grep on_create` to verify       |
| `\r: command not found` / CRLF terminators  | Edited on Windows                                       | `dos2unix on_create.sh` or `sed -i 's/\r$//' on_create.sh`   |
| Script hangs (lifecycle timeout)            | Blocking op, infinite loop, waiting for absent resource | Add `set -euo pipefail`, add network timeouts                |
| `provisioning_parameters.json` KeyError     | Instance group name mismatch                            | `InstanceGroupName` in API call must match group key in JSON |

### Slurm

`Compute nodes fail because slurm.conf not found` — controller's lifecycle failed. Fix the controller first.

`slurmctld: error ...` — check `/var/log/slurmctld.log` on controller via SSM. Common causes: wrong `SlurmctldHost`, partition/node definition errors, missing MUNGE key.

### FSx

`mount.lustre: ... Connection timed out` — FSx in different VPC/AZ, or SG doesn't allow Lustre traffic. FSx and HyperPod nodes must share a VPC; SG must allow TCP 988 and 1018-1023 between nodes and FSx. Verify FSx is `AVAILABLE`.

---

## Reading logs

### CloudWatch (from workstation)

```bash
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <NAME> --region <R> \
  --query 'ClusterArn' --output text | cut -d/ -f2)
LOG_GROUP="/aws/sagemaker/Clusters/<CLUSTER_NAME>/${CLUSTER_ID}"

# List lifecycle log streams:
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" --region <R> \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].{Stream:logStreamName,LastEvent:lastEventTimestamp}' \
  --output table

# Read a specific stream:
aws logs get-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "LifecycleConfig/<GROUP>/<INSTANCE_ID>" \
  --region <R> --limit 100 \
  --query 'events[*].message' --output text
```

### On-node (via SSM)

```bash
cat /var/log/provision/provisioning.log      # full provisioning log
cat /opt/ml/config/resource_config.json      # node topology
cat /opt/slurm/etc/slurm.conf                # Slurm config (if generated)
cat /opt/ml/metadata/resource-metadata.json  # node metadata
```

### Test locally

```bash
file on_create.sh         # must not say "with CRLF line terminators"
head -1 on_create.sh      # must start with #!/bin/bash
bash -n on_create.sh      # syntax check
shellcheck on_create.sh   # optional lint
```
