# Capacity Planning for HyperPod Clusters

Deep-dive companion to the main [SKILL.md](../SKILL.md) § B (Capacity & AZ) and the `--validate` pre-create mode. Capacity errors are one of the most common cluster-creation failures. This reference covers how to choose the right capacity strategy, verify availability, and resolve capacity-related failures.

---

## Capacity Acquisition Options

### 1. On-Demand Instances

**Best for:** Small instance types, short-term experiments, development clusters.

- No upfront commitment
- Available immediately for common types (g5, p3)
- **Not guaranteed** for large GPU types (p4d, p5, p5e, trn1, trn2)
- Instances may not be allocated in physical proximity → suboptimal network topology for distributed training
- Higher hourly cost

```bash
# Check where an instance type is available:
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=ml.p5.48xlarge" \
  --region us-west-2 \
  --query 'InstanceTypeOfferings[*].Location' --output table
```

### 2. Flexible Training Plans

**Best for:** Medium to large workloads with predictable schedules.

Query available capacity by instance type, count, and desired schedule. AWS returns available options with pricing.

```bash
# List active training plans:
aws sagemaker list-training-plans \
  --filters Name=Status,Value=Active \
  --region <REGION> \
  --query 'TrainingPlanSummaries[*].{Name:TrainingPlanName,Type:InstanceType,Count:TotalInstanceCount,AZ:AvailabilityZone,Status:Status,Start:StartTime,End:EndTime}' \
  --output table
```

**Using with HyperPod:**

```bash
aws sagemaker create-cluster \
  --cluster-name my-cluster \
  --instance-groups '[{
    "InstanceGroupName": "gpu-workers",
    "InstanceType": "ml.p5.48xlarge",
    "InstanceCount": 4,
    "ExecutionRole": "arn:aws:iam::<ACCT>:role/HyperPodRole",
    "TrainingPlanArn": "arn:aws:sagemaker:<REGION>:<ACCT>:training-plan/<PLAN_NAME>",
    "LifeCycleConfig": {
      "SourceS3Uri": "s3://sagemaker-lifecycle-<guid>/",
      "OnCreate": "on_create.sh"
    }
  }]' \
  --vpc-config '{"SecurityGroupIds":["sg-xxx"],"Subnets":["subnet-xxx"]}' \
  --region <REGION>
```

**Critical:** The subnet must be in the **same AZ** as the training plan's `AvailabilityZone`.

**Training Plan Status Values:** `Pending`, `Active`, `Scheduled`, `Expired`, `Failed`

**Advantages:**

- Guaranteed capacity for reserved period
- Discounted pricing vs on-demand
- Better network topology (co-located instances)

**Disadvantages:**

- Requires advance planning and commitment
- Capacity locked to specific AZ

### 3. Reserved Capacity (ODCR via AWS Account Team)

**Best for:** Large-scale, long-term capacity needs (months+).

- Contact your AWS account team or TAM
- Best pricing for sustained usage
- Guaranteed placement in specific AZ
- Requires longer lead time

**Verification:**

```bash
# Check reserved capacity details:
aws sagemaker list-training-plans \
  --region <REGION> \
  --query 'TrainingPlanSummaries[?ReservedCapacitySummaries]'
```

**ReservedCapacitySummary fields:**

- `ReservedCapacityArn`, `ReservedCapacityType` (UltraServer or Instance)
- `InstanceType`, `TotalInstanceCount`, `AvailabilityZone`
- `DurationHours`, `DurationMinutes`, `StartTime`, `EndTime`, `Status`

---

## AZ Selection Strategy

### The Problem

Instance type availability varies by AZ. A subnet in `us-west-2a` may have capacity, while `us-west-2c` does not. Worse, AZ names (e.g., `us-west-2a`) map to different physical zones per AWS account.

### Use AZ IDs for Consistency

AZ IDs (e.g., `usw2-az1`) are consistent across accounts:

```bash
# Map AZ names to IDs:
aws ec2 describe-availability-zones --region <REGION> \
  --query 'AvailabilityZones[*].{Name:ZoneName,ID:ZoneId,State:State}' --output table
```

When coordinating with AWS Support or account teams about reserved capacity, always use **AZ IDs** (not names).

### Verify Subnet Matches Capacity AZ

```bash
# Your subnet's AZ:
aws ec2 describe-subnets --subnet-ids <SUBNET> --region <REGION> \
  --query 'Subnets[0].{AZ:AvailabilityZone,AZ_ID:AvailabilityZoneId}'

# Instance type availability per AZ:
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone-id \
  --filters "Name=instance-type,Values=<TYPE>" \
  --region <REGION> \
  --query 'InstanceTypeOfferings[*].Location'
```

If your subnet's AZ doesn't appear in the instance type offerings list, create a new subnet in an AZ that does.

---

## Subnet IP Capacity

GPU instances consume many network interfaces (and IPs) per instance:

| Instance Type    | ENIs | IPs per ENI              | Total IPs (Slurm) | Total IPs (EKS) |
| ---------------- | ---- | ------------------------ | ----------------- | --------------- |
| ml.p5.48xlarge   | 32   | 1 primary + 49 secondary | ~32               | ~81             |
| ml.p5e.48xlarge  | 32   | same                     | ~32               | ~81             |
| ml.p4d.24xlarge  | 4    | 1 primary + 49 secondary | ~4                | ~51             |
| ml.p4de.24xlarge | 4    | same                     | ~4                | ~51             |
| ml.trn1.32xlarge | 8    | 1 primary + 49 secondary | ~8                | ~57             |
| ml.trn2.48xlarge | 16   | same                     | ~16               | ~65             |
| ml.g5.48xlarge   | 2    | 1 primary + 14 secondary | ~2                | ~15             |

### Calculate Required IPs

```
Required IPs = Instance Count × IPs per Instance
```

For example: 16 × ml.p5.48xlarge on EKS = 16 × 81 = 1,296 IPs → requires at least a /21 subnet (2,048 IPs).

### Recommended Subnet Sizes

| Cluster Size (p5) | Orchestrator | Min Subnet CIDR              |
| ----------------- | ------------ | ---------------------------- |
| 4 instances       | Slurm        | /25 (128 IPs)                |
| 4 instances       | EKS          | /24 (256 IPs, plus overhead) |
| 16 instances      | Slurm        | /23 (512 IPs)                |
| 16 instances      | EKS          | /21 (2,048 IPs)              |
| 64 instances      | Slurm        | /21 (2,048 IPs)              |
| 64 instances      | EKS          | /19 (8,192 IPs)              |

**Subnet CIDRs cannot be changed after creation.** Plan for growth.

```bash
# Check current availability:
aws ec2 describe-subnets --subnet-ids <SUBNET> --region <REGION> \
  --query 'Subnets[0].{CIDR:CidrBlock,TotalIPs:CidrBlock,FreeIPs:AvailableIpAddressCount}'
```

---

## Service Quotas

Check these **before** creating a cluster:

```bash
# List SageMaker quotas (search for "cluster"):
aws service-quotas list-service-quotas \
  --service-code sagemaker --region <REGION> \
  --query 'Quotas[?contains(QuotaName,`cluster`) || contains(QuotaName,`Cluster`)].{Name:QuotaName,Value:Value,Code:QuotaCode}' \
  --output table
```

| Quota                            | Default          | What Happens If Exceeded                |
| -------------------------------- | ---------------- | --------------------------------------- |
| `ml.<type> for cluster usage`    | Varies           | `CreateCluster` fails with quota error  |
| Max instances per cluster        | Account-specific | Cannot add more instance groups         |
| Total instances across clusters  | Account-specific | Must delete existing clusters first     |
| Max EBS volume size per instance | 16,384 GB        | `CreateCluster` fails if config exceeds |
| VPCs per region                  | 5                | CFN VPC creation fails                  |
| Network interfaces per region    | 5,000            | Instance provisioning fails silently    |
| Elastic IPs per region           | 5                | NAT Gateway creation fails              |

**Request quota increases proactively** — increases can take 1-3 business days.

---

## Troubleshooting Capacity Failures

### "Insufficient capacity" Error

1. Check which AZs have the instance type available (see commands above)
2. Verify your subnet is in one of those AZs
3. If no AZ has capacity: try a different region, instance type, or contact account team
4. If using Training Plan: verify `TrainingPlanArn` and subnet AZ match

### "No subnets in the capacity AZ" Error

The cluster configuration specifies subnets, but none of them are in the AZ where AWS has capacity.

Fix: Create a new subnet in the AZ where capacity exists and add it to the cluster configuration.

### Cluster Stuck in "Creating" (No Progress)

1. Check `list-cluster-events` for error messages
2. If no events: likely waiting for capacity
3. If events show failures: fix the indicated issue
4. If stuck >1 hour with no events: contact AWS Support

### Partial Provisioning (Some Nodes Running, Others Failing)

This typically means capacity was available for some instances but not all.

- The cluster will keep retrying if `NodeProvisioningMode=Continuous`
- Check events for the specific instance group that's failing
- Consider reducing `InstanceCount` or using `MinInstanceCount` for elastic scaling
