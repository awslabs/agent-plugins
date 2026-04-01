---
name: aws-health-check
description: Quick health check on the current AWS account — security posture, cost waste, reliability gaps, and operational readiness. Lighter than a full Well-Architected review.
disable-model-invocation: true
argument-hint: [region or "all"]
allowed-tools: Read, Grep, Glob, Bash(aws *)
---

You are running a quick AWS account health assessment. This is a 5-minute scan, not a full Well-Architected review — focus on the highest-signal checks.

## Process

1. Confirm identity: `aws sts get-caller-identity`
2. Determine scope: use $ARGUMENTS for region, or default to the configured region
3. Run the checks below in order
4. Produce a summary report

## Quick Checks

### Security (Critical — check first)

```bash
# GuardDuty enabled?
aws guardduty list-detectors --region $REGION

# CloudTrail multi-region?
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,Multi:IsMultiRegionTrail}'

# Public S3 buckets?
for bucket in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  status=$(aws s3api get-public-access-block --bucket $bucket 2>/dev/null | grep -c "true" || echo "0")
  [ "$status" -lt 4 ] && echo "WARNING: $bucket may have public access"
done

# Security groups with 0.0.0.0/0 on non-HTTP ports
aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]]' \
  --output json | jq -r '.[] | select(.IpPermissions[] | select(.FromPort != 80 and .FromPort != 443 and .FromPort != null)) | .GroupId + " " + .GroupName'

# Public RDS instances
aws rds describe-db-instances --query 'DBInstances[?PubliclyAccessible==`true`].{ID:DBInstanceIdentifier,Engine:Engine}'

# IMDSv2 enforcement
aws ec2 describe-instances --query 'Reservations[].Instances[?MetadataOptions.HttpTokens!=`required`].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],IMDS:MetadataOptions.HttpTokens}'
```

### Cost Waste

```bash
# Unattached EBS volumes
aws ec2 describe-volumes --filters "Name=status,Values=available" --query 'Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType}'

# Unassociated Elastic IPs (charged when idle)
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].{IP:PublicIp}'

# Stopped instances still incurring EBS charges
aws ec2 describe-instances --filters "Name=instance-state-name,Values=stopped" --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],Type:InstanceType}'
```

### Reliability

```bash
# Single-AZ RDS (risky for production)
aws rds describe-db-instances --query 'DBInstances[?MultiAZ==`false`].{ID:DBInstanceIdentifier,Engine:Engine}'

# No auto-scaling groups (static capacity)
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?MinSize==MaxSize].{Name:AutoScalingGroupName,Size:MinSize}'
```

## Output Format

```markdown
# AWS Account Health Check
**Account**: [ID] | **Region**: [region] | **Date**: [today]

## Score: [X/10]

## Findings

### Critical (fix now)
- ...

### Warning (fix soon)
- ...

### Good (keep doing this)
- ...

## Quick Wins
1. [Easiest high-impact fix]
2. [Next easiest]
3. [...]

## SCP Gaps
[If no SCPs detected, recommend baseline guardrails per CLAUDE.md]
```

## Rules

- Every finding must come from an actual CLI command output. Never guess.
- Don't alarm on dev/sandbox accounts — ask about the account purpose first.
- Keep it concise — this is a quick check, not a 50-page audit.
