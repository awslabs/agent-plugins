# Azure to AWS: Compute Service Mappings

## Azure VMs → EC2

| Aspect | Azure | AWS |
|---|---|---|
| Instance sizing | Standard_D4s_v3 | m6i.xlarge |
| Spot | Azure Spot VMs | EC2 Spot Instances |
| Scale sets | VM Scale Sets | Auto Scaling Groups |
| Bastion | Azure Bastion | SSM Session Manager (recommended) |
| Managed disks | Managed Disks (Premium SSD, Standard SSD) | EBS (gp3, io2) |
| Availability | Availability Sets / Zones | Placement Groups / AZs |
| Ephemeral storage | Temp disk (varies by size) | Instance Store (NVMe, size-specific) |

**Gotcha**: Azure has no equivalent to EC2 instance store (direct-attached NVMe). Azure temp disks are not the same — they persist across reboots but not deallocations.

```bash
# Azure: List VMs with details
az vm list --show-details --output table

# AWS: Find equivalent instance type
aws ec2 describe-instance-types --filters "Name=vcpus-info.default-vcpus,Values=4" --query 'InstanceTypes[].{Type:InstanceType,vCPUs:VCpuInfo.DefaultVCpus,Memory:MemoryInfo.SizeInMiB}'
```

## AKS → EKS

| Aspect | AKS | EKS |
|---|---|---|
| Control plane | Free | $0.10/hr (~$73/month) |
| Identity | Azure AD integration (native) | IRSA or EKS Pod Identity |
| Serverless nodes | Virtual Nodes (ACI-backed) | Fargate profiles |
| CLI | az aks | eksctl or aws eks |
| Monitoring | Azure Monitor Container Insights | CloudWatch Container Insights |
| Node autoscaling | Cluster Autoscaler or KEDA | Karpenter (recommended) or Cluster Autoscaler |

**Migration path**: Export Kubernetes manifests, update cloud-specific annotations (identity, storage classes, ingress), deploy to EKS. Use Velero for stateful migration.

## App Service → App Runner / Elastic Beanstalk / ECS

| App Service Feature | AWS Equivalent |
|---|---|
| Basic web app (PaaS) | App Runner (simplest) |
| Full control + extensions | Elastic Beanstalk |
| Containers | ECS Fargate |
| Deployment slots | Beanstalk URL swap or CodeDeploy blue/green |
| Easy Auth | Cognito + ALB authentication |
| Custom domains + SSL | ACM + ALB or CloudFront |
| Auto-scaling | Built into App Runner; ASG for Beanstalk/ECS |

## Azure Functions → Lambda

| Aspect | Azure Functions | Lambda |
|---|---|---|
| Consumption pricing | Per execution + GB-s | Per request + GB-s |
| Premium (pre-warmed) | Premium plan | Provisioned concurrency |
| Bindings (I/O) | Declarative bindings | Explicit SDK calls required |
| Durable orchestration | Durable Functions | Step Functions |
| Timer triggers | Timer trigger (cron) | EventBridge Scheduler + Lambda |
| K8s hosting | KEDA scaling | EKS + KEDA (self-managed) |

**Gotcha**: Azure Functions bindings are the biggest code change. Every `[BlobInput]`, `[QueueOutput]`, `[CosmosDBInput]` binding becomes explicit SDK calls in Lambda.

## Azure Container Instances → Fargate

ACI is closest to running a single Fargate task without ECS service overhead. For simple container execution (batch jobs, sidecar containers), use Fargate tasks directly. For orchestrated workloads, use ECS services.
