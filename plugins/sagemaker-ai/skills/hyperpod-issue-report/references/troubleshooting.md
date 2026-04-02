# Troubleshooting

## Error Handling

| Issue                                         | Cause                                                         | Fix                                                                                                                                                                                |
| --------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubectl not found in PATH`                   | kubectl not installed                                         | Install kubectl for the current platform, then re-run                                                                                                                              |
| `kubectl must be configured for EKS clusters` | kubectl missing or wrong context                              | Run `aws eks update-kubeconfig --name <eks-cluster-name> --region <region>`. Get the EKS cluster name from `aws sagemaker describe-cluster` output (`Orchestrator.Eks.ClusterArn`) |
| Cluster name from ARN not found               | ARN contains cluster ID, not name                             | Pass the full ARN to `--cluster` instead of extracting the ID portion. Alternatively, use `aws sagemaker list-clusters` to find the cluster name                                   |
| No instance reports in S3                     | Node IAM role missing S3 permissions                          | Add `s3:GetObject`/`s3:PutObject` to node role for the report bucket                                                                                                               |
| SSM connectivity failed                       | SSM agent down, missing IAM, or network                       | Check `systemctl status amazon-ssm-agent`, verify `AmazonSSMManagedInstanceCore` policy                                                                                            |
| "Failed to detect shell prompt"               | Custom SSM session config (custom `.bashrc`, SSM preferences) | Not compatible without modifying prompt detection; use manual SSM sessions as workaround                                                                                           |
| SSM throttling                                | Too many concurrent sessions                                  | Reduce `--max-workers`; automatic retry handles transient throttling                                                                                                               |
| Nodes unresponsive                            | Node completely down                                          | Noted in report; other nodes' diagnostics may reveal pattern                                                                                                                       |
| EKS log collector fails                       | Script download or execution error                            | Check `eks-log-collector-output.txt`; verify disk space in `/var/log/` and `/tmp/`                                                                                                 |

## Large Cluster Handling

- Default `--max-workers 16` tested up to 130 nodes (99.2% success rate, ~15 min)
- If throttled (`ThrottlingException`): reduce to `--max-workers 8`
- For 200+ nodes: batch by instance group or increase to `--max-workers 32` if no throttling
- kubectl collection may take 20-30 minutes for 1000+ node clusters
