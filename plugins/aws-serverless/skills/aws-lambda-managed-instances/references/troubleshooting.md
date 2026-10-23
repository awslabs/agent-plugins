# LMI Troubleshooting

## Testing Phase: Monitor and Adjust

After deploying your LMI function with a test workload, check these metrics and adjust:

**Duration increased vs. existing function:**

- This indicates the concurrency estimations used during setup may be off. Investigate by:
  - Checking ExecutionEnvironmentCPUUtilization and ExecutionEnvironmentMemoryUtilization for saturation
  - Reducing PerExecutionEnvironmentMaxConcurrency to see if duration improves
  - Reviewing instance types — switching to larger or more powerful instances may help if resources are constrained
- If reducing concurrency doesn't help, check throttle metrics below

**Low ExecutionEnvironmentCPUUtilization (below 10%):**

- Increase PerExecutionEnvironmentMaxConcurrency to improve utilization
- Or lower MemorySize to reduce vCPUs per execution environment
- If memory utilization is also high, increase ExecutionEnvironmentMemoryGiBPerVCpu ratio instead

**Ongoing CPUThrottles:**

- Switch capacity provider to Manual scaling mode with a lower CPU utilization target (e.g., 25%)

**Ongoing MemoryThrottles:**

- Increase MemorySize
- To maintain the same vCPU count, adjust ratio proportionally (e.g., 4GB/2:1 → 8GB/4:1 keeps 2 vCPUs)

**Ongoing DiskThrottles:**

- Reduce per-invocation /tmp usage or reduce PerExecutionEnvironmentMaxConcurrency

**Ongoing ConcurrencyThrottles:**

- Increase PerExecutionEnvironmentMaxConcurrency (if CPU and memory have headroom)
- Check if MaxExecutionEnvironments or MaxVCpuCount is capping scale-out

## Common Issues

| Issue                          | Cause                                            | Resolution                                                                          |
| ------------------------------ | ------------------------------------------------ | ----------------------------------------------------------------------------------- |
| 429 throttles during scale-up  | Traffic doubled faster than 5-min scaling window | Increase MinExecutionEnvironments or lower TargetResourceUtilization                |
| Function stuck in PENDING      | Capacity provider provisioning instances         | Wait several minutes; verify VPC subnets have IP capacity and IAM roles are correct |
| Architecture mismatch error    | Function architecture ≠ capacity provider        | Align both to arm64 or x86_64                                                       |
| Cannot terminate EC2 instances | LMI instances managed by capacity provider       | Delete capacity provider to destroy instances; cannot use EC2 console               |
| High CPU, low throughput       | Concurrency too high for CPU-bound work          | Reduce PerExecutionEnvironmentMaxConcurrency to 1/vCPU                              |
| Race conditions in production  | Code not thread-safe for multi-concurrency       | Review with checklist in thread-safety.md                                           |
| Function version not ACTIVE    | Fewer than 3 execution environments ready        | Wait for provisioning; check capacity provider status                               |
| Unexpected 500 errors          | Unhandled concurrent access to shared state      | Add thread-safe patterns from migration-patterns.md                                 |
| CloudWatch logs missing        | VPC egress not configured                        | Add NAT Gateway or CloudWatch Logs VPC endpoint                                     |
| High costs despite low traffic | Minimum execution environments always running    | Evaluate if standard Lambda is more cost-effective                                  |

## Debugging Steps

### Function Not Starting

1. Check capacity provider status: `aws lambda get-capacity-provider --capacity-provider-name <name>`
2. Verify subnets span 3+ AZs with available IPs
3. Confirm security group allows necessary egress
4. Check operator role has required permissions (see infrastructure-setup.md for least-privilege policy)
5. Look for `Operator` field in EC2 DescribeInstances or `aws:lambda:capacity-provider` tag

### Performance Issues

1. Check CloudWatch metrics (5-min intervals): CPU utilization, memory, concurrency/env
2. If CPU > 80%: reduce concurrency or add vCPUs (increase memory with appropriate ratio)
3. If throttles > 1%: increase MinExecutionEnvironments
4. If CPU < 20%: increase concurrency — resources are underutilized
5. For Python: verify 4:1 or 8:1 ratio (GIL limits CPU parallelism)

### Cost Issues

1. Verify instance count matches actual need (not over-provisioned)
2. Check if Savings Plans or RIs are applied to these instances
3. Compare actual costs against the 4-column estimate from cost-comparison.md
4. If traffic is lower than expected, consider reducing MaxVCpuCount
5. For dev/test: use ExcludedInstanceTypes to avoid expensive instance families
