# Networking Services Design Rubric

**Applies to:** VPC, Firewall, Load Balancing, DNS, Cloud Interconnect

**Quick lookup (no rubric):** Check `fast-path.md` first (VPC → VPC, Firewall → Security Groups, etc.)

## Eliminators (Hard Blockers)

| GCP Service          | AWS            | Blocker                                                  |
| -------------------- | -------------- | -------------------------------------------------------- |
| Cloud Interconnect   | Direct Connect | Dedicated connection (6+ months setup) → use VPN as temp |
| Cloud Load Balancing | ALB            | SSL certificate passthrough → NLB (L4, pass-through)     |
| Cloud Load Balancing | NLB            | IP-based routing → ALB (L7, hostname-based)              |

## Signals (Decision Criteria)

### VPC Network

- Always → AWS VPC (1:1 deterministic)
- Preserve CIDR blocks, subnets, routing tables

### Firewall Rules

- Always → AWS Security Groups (1:1 deterministic)
- Convert direction (ingress/egress) and IP ranges

### Cloud Load Balancing

- **HTTP/HTTPS + hostname/path routing** → ALB (Layer 7)
- **TCP/UDP + high throughput** → NLB (Layer 4)
- **TLS passthrough** → NLB (Layer 4, no termination)

### Cloud DNS

- Always → Route 53 (1:1 deterministic)
- Preserve zone name, record types, TTLs

### Cloud Interconnect

- **Dedicated connection** → AWS Direct Connect
- **Temporary/dev connectivity** → AWS Site-to-Site VPN (quicker, lower cost)

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does GCP config require AWS-unsupported features? If yes: switch
2. **Operational Model**: Managed (ALB, Route 53) vs Custom (VPN, custom routing)?
   - Prefer managed
3. **User Preference**: From `clarified.json`, q2 (primary concern)?
   - If `"compliance"` → use Direct Connect (explicit data path); else VPN fine
4. **Feature Parity**: Does GCP config require AWS-unsupported features?
   - Example: GCP policy-based routing → Custom route table rules (AWS does this)
5. **Cluster Context**: Are other resources in cluster using specific load balancers? Match
6. **Simplicity**: Fewer resources = higher score

## Examples

### Example 1: VPC Network

- GCP: `google_compute_network` (auto_create_subnetworks=false, routing_mode=REGIONAL)
- Signals: Explicit subnets, regional routing
- Criterion 1 (Eliminators): PASS
- → **AWS: VPC (us-east-1 region)**
- Confidence: `deterministic`

### Example 2: Firewall Rules

- GCP: `google_compute_firewall` (allow=[tcp:443], source_ranges=[0.0.0.0/0])
- Signals: HTTPS ingress, public
- → **AWS: Security Group (ingress rule: 443/tcp from 0.0.0.0/0)**
- Confidence: `deterministic`

### Example 3: Cloud Load Balancing (HTTP + path-based)

- GCP: `google_compute_forwarding_rule` + `google_compute_backend_service` (path_matcher=["/api/*" → api-backend])
- Signals: Path-based routing, HTTP/HTTPS
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): ALB (managed, L7)
- → **AWS: ALB with target groups + listener rules (path-based)**
- Confidence: `inferred`

### Example 4: Cloud DNS Zone

- GCP: `google_dns_managed_zone` (dns_name="example.com.")
- Signals: Public DNS zone
- → **AWS: Route 53 Hosted Zone (example.com)**
- Confidence: `deterministic`

## Output Schema

```json
{
  "gcp_type": "google_compute_forwarding_rule",
  "gcp_address": "global-https-lb",
  "gcp_config": {
    "load_balancing_scheme": "EXTERNAL",
    "protocol": "HTTPS"
  },
  "aws_service": "Application Load Balancer",
  "aws_config": {
    "load_balancer_type": "application",
    "scheme": "internet-facing",
    "listener": {
      "protocol": "HTTPS",
      "port": 443
    },
    "region": "us-east-1"
  },
  "confidence": "deterministic",
  "rationale": "GCP global HTTPS LB → AWS ALB (L7, host/path routing)"
}
```
