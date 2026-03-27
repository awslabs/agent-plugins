# GCP to AWS: Compute Service Mappings

## Compute Engine → EC2

| Aspect | GCP | AWS |
|---|---|---|
| Instances | Compute Engine | EC2 |
| Preemptible/Spot | Preemptible VMs (24h max) | Spot Instances (no time limit) |
| SSH access | OS Login (automatic via IAM) | Key pairs or SSM Session Manager |
| Disks | Persistent Disks (pd-standard, pd-ssd) | EBS (gp3, io2) |
| Images | Custom images per project | AMIs per region |
| Instance groups | Managed Instance Groups | Auto Scaling Groups |
| Machine types | n2-standard-4 format | m6i.xlarge format |

**Migration path**: Use AWS MGN (Application Migration Service) for rehost. Install replication agent on GCE instances, test in AWS, cutover.

```bash
# GCP: Export instance details
gcloud compute instances describe INSTANCE --zone=ZONE --format=json

# AWS: Find equivalent instance type
aws ec2 describe-instance-types --filters "Name=vcpus-info.default-vcpus,Values=4" "Name=memory-info.size-in-mib,Values=16384" --query 'InstanceTypes[].InstanceType'
```

## GKE → EKS

| Aspect | GCP | AWS |
|---|---|---|
| Control plane cost | Free | $0.10/hr (~$73/month) |
| Auto-provisioning | GKE Autopilot | Karpenter |
| Service mesh | Built-in Istio option | Self-managed Istio or App Mesh |
| Cluster CLI | gcloud container clusters | eksctl or aws eks |
| Node scaling | Cluster autoscaler or Autopilot | Karpenter or Cluster Autoscaler |
| Pod identity | Workload Identity | EKS Pod Identity or IRSA |
| Logging | Cloud Logging (automatic) | CloudWatch Container Insights |

**Gotcha**: GKE workload identity binds Kubernetes service accounts to GCP service accounts. EKS uses IAM Roles for Service Accounts (IRSA) or the newer EKS Pod Identity — you need to recreate all IAM bindings.

```bash
# GCP: List GKE clusters and node pools
gcloud container clusters list --format=json
gcloud container node-pools list --cluster=CLUSTER --zone=ZONE

# AWS: Create EKS cluster
eksctl create cluster --name my-cluster --region us-east-1 --nodegroup-name workers --node-type m6i.xlarge --nodes 3
```

## Cloud Run → Fargate or Lambda

| Factor | Cloud Run | ECS Fargate | Lambda |
|---|---|---|---|
| Scale to zero | Yes | No | Yes |
| Max timeout | 60 minutes | No limit | 15 minutes |
| Container support | Any container | Any container | Container images or zip |
| Cold start | Warm instances kept | No cold start (always running) | Cold start present |
| Pricing | Per request + CPU/memory time | Per vCPU/memory per hour | Per request + duration |
| Min instances | 0 | 1 task minimum | 0 |

**Decision**: Use Lambda for event-driven or short HTTP (<15min). Use Fargate for long-running, always-on, or complex container workloads.

## App Engine → App Runner or Elastic Beanstalk

App Engine Standard → App Runner (simplest path, auto-scaling, managed).
App Engine Flex → Elastic Beanstalk or ECS Fargate (more control).

**Gotcha**: App Engine's traffic splitting between versions has no direct equivalent. Use ALB weighted target groups or CloudFront origin groups for traffic splitting on AWS.
