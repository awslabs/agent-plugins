# GCP to AWS: Networking Mappings

## VPC: Global vs Regional (CRITICAL DIFFERENCE)

| Aspect | GCP VPC | AWS VPC |
|---|---|---|
| Scope | **Global** (all regions) | **Regional** (single region) |
| Subnets | Regional (span all AZs in region) | AZ-specific (one AZ per subnet) |
| Firewall | Project-level rules with target tags | Security groups per ENI |
| Firewall model | Stateless (default) | Stateful (return traffic auto-allowed) |
| Cross-region | Automatic within VPC | VPC peering or Transit Gateway required |
| Default VPC | Auto-mode creates subnets in all regions | Default VPC exists per region |

**Impact**: A single GCP VPC might become 3-5 AWS VPCs connected via Transit Gateway. Plan CIDR allocation carefully — AWS subnets cannot overlap within a Transit Gateway.

```bash
# GCP: Map current VPC topology
gcloud compute networks list --format=json
gcloud compute networks subnets list --format="table(name, region, ipCidrRange, network)"
gcloud compute firewall-rules list --format="table(name, network, direction, allowed)"

# AWS: Create equivalent VPC structure
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=prod-vpc}]'
```

## Load Balancing: Single Global LB vs Regional + CDN

| GCP | AWS | Notes |
|---|---|---|
| Global HTTP(S) LB | CloudFront + ALB | GCP's anycast IP has no direct AWS equivalent |
| Regional HTTP LB | ALB | 1:1 mapping |
| TCP Proxy LB | NLB | Layer 4 load balancing |
| Internal HTTP LB | Internal ALB | 1:1 mapping |
| SSL Proxy LB | NLB with TLS termination | Similar capability |

**Gotcha**: GCP's global load balancer provides a single anycast IP that routes to the nearest region. AWS requires CloudFront (CDN) + regional ALBs to achieve similar global distribution.

## Cloud DNS → Route 53

Nearly 1:1. Both support hosted zones, routing policies, health checks. Route 53 adds geoproximity and latency-based routing policies. Route 53 also serves as domain registrar.

## Cloud Armor → WAF

Both are web application firewalls. Cloud Armor integrates with Cloud LB; WAF integrates with ALB, CloudFront, API Gateway. WAF has more managed rule groups. Cloud Armor's adaptive protection (ML-based) → WAF Bot Control and Account Takeover Prevention.

## Cloud NAT → NAT Gateway

Both provide outbound NAT. Pricing differs: AWS NAT Gateway charges per GB processed ($0.045/GB); GCP Cloud NAT charges per VM using it. For high-throughput workloads, compare costs carefully.

**Cost tip**: Use VPC endpoints for S3 and DynamoDB to avoid NAT Gateway data processing charges.

## Cloud Interconnect → Direct Connect

| GCP | AWS |
|---|---|
| Dedicated Interconnect | Direct Connect dedicated |
| Partner Interconnect | Direct Connect via partners |
| 10 Gbps / 100 Gbps | 1 / 10 / 100 Gbps |

Both provide dedicated private connectivity to cloud. Plan for at least 2 connections for redundancy.
