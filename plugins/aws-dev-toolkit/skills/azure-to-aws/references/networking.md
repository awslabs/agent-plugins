# Azure to AWS: Networking Mappings

## VNet → VPC

| Aspect | Azure VNet | AWS VPC |
|---|---|---|
| Scope | Regional | Regional |
| Subnets | Can span all AZs in region | AZ-specific (one AZ per subnet) |
| Security | NSGs (subnet or NIC level) | Security Groups (ENI level) |
| App Security Groups | ASGs simplify NSG rules | Security group references |
| Peering | VNet Peering | VPC Peering |
| Hub-spoke | Azure Virtual WAN / Hub | Transit Gateway |
| Private DNS | Private DNS Zones | Route 53 Private Hosted Zones |

**Key difference**: Azure subnets span AZs; AWS subnets are locked to one AZ. You need 2-3 subnets per tier (public, private, data) across AZs for HA.

```bash
# Azure: Map VNet topology
az network vnet list --output table
az network vnet subnet list --vnet-name VNET --resource-group RG --output table
az network nsg list --output table

# AWS: Create equivalent structure
aws ec2 create-vpc --cidr-block 10.0.0.0/16
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.2.0/24 --availability-zone us-east-1b
```

## Azure Front Door → CloudFront + WAF + Route 53

Azure Front Door combines CDN, WAF, global load balancing, and SSL offload in one service. AWS requires three:
- **CloudFront** for CDN and edge caching
- **WAF** for web application firewall rules
- **Route 53** with latency-based routing for global load balancing

Front Door Rules Engine → CloudFront Functions + Lambda@Edge.
Front Door session affinity → CloudFront sticky sessions.

## Application Gateway → ALB

1:1 conceptually. Both are Layer 7 load balancers.
- AG WAF → ALB + WAF
- AG URL path-based routing → ALB path-based routing
- AG rewrite rules → ALB actions
- AG private link → ALB + VPC endpoint service

## Azure DNS → Route 53

1:1 mapping. Private DNS zones → Route 53 private hosted zones. Alias records supported by both.

## ExpressRoute → Direct Connect

| Aspect | ExpressRoute | Direct Connect |
|---|---|---|
| Dedicated connection | ExpressRoute Direct | Direct Connect dedicated |
| Partner connection | ExpressRoute via partner | Direct Connect via partner |
| Global reach | Connect on-prem sites via Azure backbone | No equivalent (use Transit Gateway) |
| Cross-region | ExpressRoute Premium add-on | Direct Connect Gateway |

**Gotcha**: ExpressRoute Global Reach (connecting two on-prem sites through Azure) has no Direct Connect equivalent. Use Transit Gateway + multiple Direct Connect connections instead.

## Azure Monitor → CloudWatch

| Azure | AWS |
|---|---|
| Azure Monitor Metrics | CloudWatch Metrics |
| Log Analytics | CloudWatch Logs Insights |
| Application Insights | CloudWatch Application Signals or X-Ray |
| Azure Alerts | CloudWatch Alarms |
| Azure Workbooks | CloudWatch Dashboards |
| Azure Diagnostics | CloudWatch agent + VPC Flow Logs |

**Gotcha**: Application Insights auto-instrumentation is easier to set up than X-Ray. For .NET and Java apps, consider using AWS Distro for OpenTelemetry (ADOT) for a smoother transition.
