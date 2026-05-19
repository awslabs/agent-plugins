# Capacity Planning

Companion to [SKILL.md](../SKILL.md) § B and `--validate`. Capacity errors are one of the most common creation failures.

---

## Capacity options

### On-demand

Fine for small instance types and short experiments. **Not guaranteed** for large GPU types (p4d, p5, p5e, trn1, trn2). No physical-proximity guarantees — sub-optimal for distributed training.

```bash
# Which AZs have this instance type. The EC2 API uses bare instance-type
# names, so strip the SageMaker `ml.` prefix before filtering.
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=p5.48xlarge" \
  --region us-west-2 \
  --query 'InstanceTypeOfferings[*].Location' --output table
```

### Flexible Training Plans

Guaranteed capacity for a reserved period, discounted pricing, co-located instances. Requires advance planning.

```bash
aws sagemaker list-training-plans \
  --filters Name=Status,Value=Active \
  --region <REGION> \
  --query 'TrainingPlanSummaries[*].{Name:TrainingPlanName,Type:InstanceType,Count:TotalInstanceCount,AZ:AvailabilityZone,Status:Status,Start:StartTime,End:EndTime}' \
  --output table
```

Use in cluster config:

```bash
aws sagemaker create-cluster \
  --cluster-name my-cluster \
  --instance-groups '[{
    "InstanceGroupName": "gpu-workers",
    "InstanceType": "ml.p5.48xlarge",
    "InstanceCount": 4,
    "ExecutionRole": "arn:aws:iam::<ACCT>:role/HyperPodRole",
    "TrainingPlanArn": "arn:aws:sagemaker:<REGION>:<ACCT>:training-plan/<PLAN_NAME>",
    "LifeCycleConfig": {"SourceS3Uri": "s3://sagemaker-lifecycle-<guid>/", "OnCreate": "on_create.sh"}
  }]' \
  --vpc-config '{"SecurityGroupIds":["sg-xxx"],"Subnets":["subnet-xxx"]}' \
  --region <REGION>
```

**Critical:** the subnet must be in the **same AZ** as the training plan's `AvailabilityZone`.

### Reserved capacity (via account team)

For large or long-term capacity. Contact the AWS account team — customized placement and pricing, longer lead time.

---

## AZ selection

Instance-type availability varies by AZ, and AZ names (`us-west-2a`) map to different physical zones per account. When coordinating with AWS Support or the account team about reserved capacity, use **AZ IDs** (`usw2-az1`), not AZ names — they're consistent across accounts.

```bash
# AZ name → ID:
aws ec2 describe-availability-zones --region <REGION> \
  --query 'AvailabilityZones[*].{Name:ZoneName,ID:ZoneId,State:State}' --output table

# Your subnet's AZ:
aws ec2 describe-subnets --subnet-ids <SUBNET> --region <REGION> \
  --query 'Subnets[0].{AZ:AvailabilityZone,AZ_ID:AvailabilityZoneId}'

# Instance-type offerings by AZ-ID:
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone-id \
  --filters "Name=instance-type,Values=<TYPE>" \
  --region <REGION> \
  --query 'InstanceTypeOfferings[*].Location'
```

If your subnet's AZ doesn't appear in the offerings list, create a new subnet in an AZ that does.

---

## Service quotas

Check `ml.<type> for cluster usage` quotas before creating a cluster. EKS on HyperPod also consumes ENIs and subnet IPs — size subnets generously; CIDRs cannot be changed after creation.

```bash
# SageMaker HyperPod quotas:
aws service-quotas list-service-quotas \
  --service-code sagemaker --region <REGION> \
  --query 'Quotas[?contains(QuotaName,`cluster`) || contains(QuotaName,`HyperPod`)].{Name:QuotaName,Value:Value,Code:QuotaCode}' \
  --output table

# Subnet free IPs:
aws ec2 describe-subnets --subnet-ids <SUBNET> --region <REGION> \
  --query 'Subnets[0].{CIDR:CidrBlock,FreeIPs:AvailableIpAddressCount}'
```

Request quota increases proactively — processing time varies by quota and region.

---

## Troubleshooting

### `Insufficient capacity`

1. Check which AZs have the instance type (commands above)
2. Verify your subnet is in one of those AZs
3. If no AZ has capacity: try a different region/type or contact account team
4. Using a Training Plan: verify `TrainingPlanArn` and that the subnet AZ matches the plan AZ

### `No subnets in the capacity AZ`

Cluster specifies subnets, but none are in the AZ where AWS has capacity. Create a subnet in that AZ and add it to the cluster config.

### Stuck in `Creating` with no events

Likely waiting for capacity. Check `list-cluster-events`; if no events after >1 hour, contact AWS Support.

### Partial provisioning

Capacity was available for some instances but not all. With `NodeProvisioningMode=Continuous` the cluster keeps retrying. Check events for the failing instance group; consider reducing `InstanceCount` or using `MinInstanceCount` for elastic scaling.
