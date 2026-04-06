# CIDR Planning for AWS VPCs

Strategies and worked examples for VPC and subnet CIDR allocation.

## CIDR Fundamentals

| CIDR | IPs | Usable IPs (AWS) | Typical Use |
|---|---|---|---|
| /16 | 65,536 | 65,531 | VPC (large) |
| /17 | 32,768 | 32,763 | VPC (medium) |
| /18 | 16,384 | 16,379 | VPC (medium) |
| /19 | 8,192 | 8,187 | Large subnet |
| /20 | 4,096 | 4,091 | Large subnet |
| /21 | 2,048 | 2,043 | Medium subnet |
| /22 | 1,024 | 1,019 | Medium subnet |
| /23 | 512 | 507 | Small subnet |
| /24 | 256 | 251 | Small subnet |
| /25 | 128 | 123 | Minimal subnet |
| /26 | 64 | 59 | Minimal subnet |
| /27 | 32 | 27 | Tiny subnet |
| /28 | 16 | 11 | Smallest AWS subnet |

AWS reserves 5 IPs per subnet: network address, VPC router, DNS, future use, broadcast.

## Strategy 1: Standard Three-Tier, Three-AZ VPC

The default starting point for most production workloads.

**VPC CIDR:** `10.0.0.0/16` (65,531 usable IPs)

| Tier | AZ-a | AZ-b | AZ-c | IPs per Subnet |
|---|---|---|---|---|
| Public | 10.0.0.0/20 | 10.0.16.0/20 | 10.0.32.0/20 | 4,091 |
| Private | 10.0.48.0/20 | 10.0.64.0/20 | 10.0.80.0/20 | 4,091 |
| Isolated (DB) | 10.0.96.0/20 | 10.0.112.0/20 | 10.0.128.0/20 | 4,091 |
| **Reserved** | 10.0.144.0/20 through 10.0.240.0/20 | | | ~7 more /20s |

**Key points:**
- Each subnet has 4,091 usable IPs, enough for most workloads
- Reserved space (10.0.144.0 - 10.0.255.255) for future tiers (e.g., caching layer, additional AZs)
- Total used: 9 subnets, ~36,819 IPs. Remaining: ~28,700 IPs.

## Strategy 2: Compact VPC for Dev/Test

Smaller allocation to conserve address space. Suitable for non-production environments.

**VPC CIDR:** `10.1.0.0/20` (4,091 usable IPs)

| Tier | AZ-a | AZ-b | IPs per Subnet |
|---|---|---|---|
| Public | 10.1.0.0/24 | 10.1.1.0/24 | 251 |
| Private | 10.1.2.0/24 | 10.1.3.0/24 | 251 |
| Isolated | 10.1.4.0/24 | 10.1.5.0/24 | 251 |
| **Reserved** | 10.1.6.0/24 through 10.1.15.0/24 | | ~10 more /24s |

**Key points:**
- 2 AZs for dev/test (cost savings)
- 251 IPs per subnet is sufficient for most non-production workloads
- Fits inside a /20, leaving room for many dev VPCs in the 10.1.0.0/16 range

## Strategy 3: Multi-Account CIDR Allocation

When using AWS Organizations with multiple accounts, plan CIDR ranges at the organization level to avoid overlap.

```
Organization supernet: 10.0.0.0/8

Account Allocation:
  Production    : 10.0.0.0/16   (65K IPs)
  Staging       : 10.1.0.0/16   (65K IPs)
  Development   : 10.2.0.0/16   (65K IPs)
  Shared Svcs   : 10.3.0.0/16   (65K IPs)
  Security      : 10.4.0.0/16   (65K IPs)
  Sandbox       : 10.5.0.0/16   (65K IPs)
  Reserved      : 10.6.0.0/15 through 10.255.0.0/16
```

**Within each account:**

```
10.0.0.0/16 (Production Account)
  ├── us-east-1 VPC  : 10.0.0.0/18   (16K IPs)
  ├── us-west-2 VPC  : 10.0.64.0/18  (16K IPs)
  ├── eu-west-1 VPC  : 10.0.128.0/18 (16K IPs)
  └── Reserved       : 10.0.192.0/18 (16K IPs)
```

**Rules:**
- No CIDR overlap across any account or region
- Each VPC gets a /18 within its account's /16
- Transit Gateway or VPC peering works without conflicts
- Document the allocation in a central IPAM or spreadsheet

## Strategy 4: AWS VPC IPAM

For organizations with 10+ VPCs, use AWS VPC IPAM (IP Address Manager) instead of spreadsheets.

**IPAM hierarchy:**
```
IPAM Pool (Organization level): 10.0.0.0/8
  ├── Regional Pool (us-east-1): 10.0.0.0/12
  │     ├── Production Pool: 10.0.0.0/14
  │     ├── Non-Prod Pool:   10.4.0.0/14
  │     └── Reserved:        10.8.0.0/13
  └── Regional Pool (eu-west-1): 10.16.0.0/12
        ├── Production Pool: 10.16.0.0/14
        └── Non-Prod Pool:   10.20.0.0/14
```

**Benefits:**
- Automatic CIDR allocation (no manual tracking)
- Prevents overlapping allocations
- Integrates with AWS Organizations and RAM
- Compliance rules enforce minimum/maximum CIDR sizes

## EKS-Specific CIDR Considerations

EKS consumes IPs aggressively. Each pod gets its own IP from the subnet by default (VPC CNI plugin).

**IP consumption calculation:**
```
IPs needed = (max pods per node) x (max nodes) + (node IPs) + (overhead)

Example:
  30 pods/node x 50 nodes = 1,500 pod IPs
  + 50 node IPs
  + services, DaemonSets, buffer
  ≈ 2,000 IPs minimum → /21 per AZ (2,043 usable)
```

**Mitigation strategies when IPs are limited:**
- **Secondary CIDR:** Add a 100.64.0.0/16 (CGNAT range) secondary CIDR to the VPC for pod networking
- **Prefix delegation:** Assign /28 prefixes to ENIs instead of individual IPs (increases pod density per node)
- **Custom networking:** Use a separate subnet CIDR for pods vs. nodes
- **IPv6:** Dual-stack VPC eliminates IPv4 address exhaustion entirely

## Lambda-Specific CIDR Considerations

Lambda functions in a VPC consume ENIs (and thus IPs) from your subnets. Since 2019, Lambda uses Hyperplane ENIs that are shared across invocations, but you still need adequate capacity.

**Rule of thumb:** Allocate at least a /24 per AZ for Lambda-heavy workloads. Monitor ENI usage.

## Common Mistakes

| Mistake | Consequence | Prevention |
|---|---|---|
| Using /24 for the VPC | Only 251 IPs total, cannot grow | Start with /16 or /18 minimum |
| Overlapping CIDRs across VPCs | Cannot peer or use Transit Gateway | Central CIDR registry or IPAM |
| No reserved space | Adding subnets later requires secondary CIDRs | Always leave 30-50% unused |
| Using public IP ranges (e.g., 8.8.0.0/16) | Routing conflicts with internet destinations | Use RFC 1918 ranges only |
| Too many small subnets (/28) | Frequent IP exhaustion, high management overhead | Use /20 to /24 per subnet |
| Not accounting for EKS pod IPs | Subnet exhaustion under load | Plan for pod density upfront |

## Secondary CIDR Blocks

If you run out of IPs in your primary CIDR, you can add secondary CIDR blocks to a VPC.

**Constraints:**
- Up to 5 IPv4 CIDRs per VPC (adjustable)
- The secondary CIDR must not overlap with the primary or any peered VPC CIDRs
- 100.64.0.0/10 (CGNAT range) is commonly used for secondary CIDRs, especially for EKS pod networking
- Secondary CIDRs can be from different RFC 1918 ranges than the primary

```bash
# Add secondary CIDR
aws ec2 associate-vpc-cidr-block --vpc-id vpc-xxx --cidr-block 100.64.0.0/16

# Create subnets in the secondary CIDR
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 100.64.0.0/20 --availability-zone us-east-1a
```
