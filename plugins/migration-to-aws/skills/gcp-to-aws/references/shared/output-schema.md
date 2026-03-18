# Output Schema Reference

Complete JSON schemas for all phase outputs and state files.

**Convention**: Values shown as `X|Y` in examples indicate allowed alternatives — use exactly one value per field, not the literal pipe character. These pipe-separated values are documentation shorthand only and must NOT appear in actual output JSON. Always select one concrete value.

## .phase-status.json

Current phase tracking and status.

```json
{
  "phase": "discover|clarify|design|estimate|execute",
  "status": "in-progress|completed",
  "timestamp": "2026-02-26T14:30:00Z",
  "version": "1.0.0"
}
```

---

## gcp-resource-inventory.json (Phase 1 output)

All discovered GCP resources with full configuration and dependencies.

```json
{
  "timestamp": "2026-02-26T14:30:00Z",
  "metadata": {
    "total_resources": 50,
    "primary_resources": 12,
    "secondary_resources": 38,
    "total_clusters": 6,
    "terraform_available": true
  },
  "resources": [
    {
      "address": "google_sql_database_instance.prod_postgres",
      "type": "google_sql_database_instance",
      "classification": "PRIMARY",
      "secondary_role": null,
      "cluster_id": "database_sql_us-central1_001",
      "config": {
        "database_version": "POSTGRES_13",
        "region": "us-central1",
        "tier": "db-custom-2-7680"
      },
      "dependencies": [],
      "depth": 0,
      "serves": []
    },
    {
      "address": "google_compute_instance.web",
      "type": "google_compute_instance",
      "classification": "PRIMARY",
      "secondary_role": null,
      "cluster_id": "compute_instance_us-central1_001",
      "config": {
        "machine_type": "e2-medium",
        "zone": "us-central1-a",
        "image": "debian-11"
      },
      "dependencies": ["google_compute_network.vpc"],
      "depth": 1,
      "serves": []
    },
    {
      "address": "google_compute_network.vpc",
      "type": "google_compute_network",
      "classification": "PRIMARY",
      "secondary_role": null,
      "cluster_id": "network_vpc_us-central1_001",
      "config": {
        "auto_create_subnetworks": false
      },
      "dependencies": [],
      "depth": 0,
      "serves": []
    }
  ]
}
```

**Schema fields:**

- `metadata`: Summary statistics (total_resources, primary/secondary counts, cluster count, terraform_available)
- `resources`: Array of all discovered resources with fields:
  - `address`: Terraform resource address
  - `type`: Terraform resource type
  - `classification`: PRIMARY or SECONDARY
  - `secondary_role`: Role if SECONDARY (identity, access_control, network_path, configuration, encryption, orchestration); null for PRIMARY
  - `cluster_id`: Assigned cluster identifier
  - `config`: Resource configuration (varies by type)
  - `dependencies`: List of Terraform addresses this resource depends on
  - `depth`: Topological depth (0 = no dependencies, N = depends on depth N-1)
  - `serves`: List of resources this secondary supports (for SECONDARY only)

---

## gcp-resource-clusters.json (Phase 1 output)

Clustered resources by affinity and deployment order.

```json
{
  "clusters": [
    {
      "cluster_id": "network_vpc_us-central1_001",
      "name": "VPC Network",
      "type": "network",
      "description": "Primary: compute_network.vpc, Secondary: firewall.web-allow-http",
      "gcp_region": "us-central1",
      "creation_order_depth": 0,
      "primary_resources": [
        "google_compute_network.vpc"
      ],
      "secondary_resources": [
        "google_compute_firewall.web-allow-http"
      ],
      "network": null,
      "must_migrate_together": true,
      "dependencies": [],
      "edges": []
    },
    {
      "cluster_id": "compute_instance_us-central1_001",
      "name": "Compute Instance",
      "type": "compute",
      "description": "Primary: compute_instance.web",
      "gcp_region": "us-central1",
      "creation_order_depth": 1,
      "primary_resources": [
        "google_compute_instance.web"
      ],
      "secondary_resources": [],
      "network": "network_vpc_us-central1_001",
      "must_migrate_together": true,
      "dependencies": ["network_vpc_us-central1_001"],
      "edges": [
        {
          "from": "google_compute_instance.web",
          "to": "google_compute_network.vpc",
          "relationship_type": "network_path"
        }
      ]
    },
    {
      "cluster_id": "database_sql_us-central1_001",
      "name": "Cloud SQL PostgreSQL",
      "type": "database",
      "description": "Primary: sql_database_instance.prod_postgres",
      "gcp_region": "us-central1",
      "creation_order_depth": 0,
      "primary_resources": [
        "google_sql_database_instance.prod_postgres"
      ],
      "secondary_resources": [],
      "network": null,
      "must_migrate_together": true,
      "dependencies": [],
      "edges": []
    }
  ]
}
```

---

## clarified.json (Phase 2 output)

User answers to clarification questions.

```json
{
  "mode": "A",
  "answers": {
    "q1_timeline": "6-12 months",
    "q2_primary_concern": "cost",
    "q3_team_experience": "novice",
    "q4_traffic_profile": "predictable",
    "q5_database_requirements": "structured",
    "q6_cost_sensitivity": "moderate",
    "q7_multi_cloud": "no",
    "q8_compliance": "none"
  },
  "timestamp": "2026-02-26T14:30:00Z"
}
```

---

## aws-design.json (Phase 3 output)

AWS services mapped from GCP resources, clustered by affinity.

```json
{
  "validation_status": {
    "status": "completed|skipped",
    "message": "All services validated for regional availability and feature parity|Validation unavailable (awsknowledge MCP unreachable)"
  },
  "clusters": [
    {
      "cluster_id": "compute_instance_us-central1_001",
      "gcp_region": "us-central1",
      "aws_region": "us-east-1",
      "resources": [
        {
          "gcp_address": "google_compute_instance.web",
          "gcp_type": "google_compute_instance",
          "gcp_config": {
            "machine_type": "n2-standard-2",
            "zone": "us-central1-a",
            "boot_disk_size_gb": 100
          },
          "aws_service": "Fargate",
          "aws_config": {
            "cpu": "0.5",
            "memory": "1024",
            "region": "us-east-1"
          },
          "confidence": "inferred",
          "rationale": "Compute mapping; always-on; Fargate for simplicity",
          "rubric_applied": [
            "Eliminators: PASS",
            "Operational Model: Managed Fargate",
            "User Preference: Cost (q2)",
            "Feature Parity: Full (always-on compute)",
            "Cluster Context: Standalone compute tier",
            "Simplicity: Fargate (managed, no EC2)"
          ]
        }
      ]
    }
  ],
  "warnings": [
    "Service X not available in us-east-1; feature parity check deferred to us-west-2"
  ],
  "timestamp": "2026-02-26T14:30:00Z"
}
```

---

## estimation.json (Phase 4 output)

Monthly operating costs, one-time migration costs, and ROI analysis.

```json
{
  "pricing_source": {
    "status": "live|fallback",
    "message": "Using live AWS pricing API|Using cached rates from 2026-02-24 (±15-25% accuracy due to API unavailability)",
    "fallback_staleness": {
      "last_updated": "2026-02-24",
      "days_old": 3,
      "is_stale": false,
      "staleness_warning": "null|⚠️ Cached pricing data is >60 days old; accuracy may be significantly degraded"
    },
    "services_by_source": {
      "live": ["Fargate", "RDS Aurora", "S3", "ALB"],
      "fallback": ["NAT Gateway"],
      "estimated": []
    },
    "services_with_missing_fallback": []
  },
  "monthly_costs": {
    "premium": {
      "total": 5000,
      "breakdown": {
        "Fargate": 1200,
        "RDS Aurora": 2500,
        "S3": 500,
        "ALB": 200,
        "NAT Gateway": 300,
        "Data Transfer": 300
      }
    },
    "balanced": {
      "total": 3500,
      "breakdown": {
        "Fargate": 800,
        "RDS Aurora Serverless": 1800,
        "S3": 500,
        "ALB": 200,
        "NAT Gateway": 200
      }
    },
    "optimized": {
      "total": 2200,
      "breakdown": {
        "Fargate Spot": 300,
        "RDS Aurora Serverless": 1200,
        "S3": 500,
        "NAT Gateway": 200
      }
    }
  },
  "one_time_costs": {
    "dev_hours": "150 hours @ $150/hr = $22,500",
    "data_transfer": "500 GB @ $0.02/GB = $10",
    "training": "Team AWS training = $5,000",
    "total": 27510
  },
  "roi": {
    "assumed_gcp_monthly": 4500,
    "aws_monthly_balanced": 3500,
    "monthly_savings": 1000,
    "payback_months": 27.51,
    "five_year_savings": 32490
  },
  "assumptions": [
    "24/7 workload operation",
    "us-east-1 region selection",
    "No Reserved Instances purchased",
    "No Spot instances in Balanced tier",
    "GCP monthly cost: user estimate"
  ],
  "timestamp": "2026-02-26T14:30:00Z"
}
```

---

## execution.json (Phase 5 output)

Timeline, risk assessment, and rollback procedures.

```json
{
  "timeline_weeks": 12,
  "critical_path": [
    "VPC setup (Week 1)",
    "PoC deployment (Week 3-5)",
    "Data migration (Week 9-10)",
    "DNS cutover (Week 11)"
  ],
  "risks": [
    {
      "category": "data_loss",
      "probability": "low",
      "impact": "critical",
      "mitigation": "Dual-write replication for 2 weeks; full backup before cutover"
    },
    {
      "category": "performance_regression",
      "probability": "medium",
      "impact": "high",
      "mitigation": "PoC testing (Week 3-5); load testing (Week 6)"
    },
    {
      "category": "team_capacity",
      "probability": "medium",
      "impact": "medium",
      "mitigation": "Allocate 2 FTE engineers; external support if needed"
    }
  ],
  "rollback_window": "Reversible until DNS cutover (Week 11); manual after",
  "gcp_teardown_week": 14,
  "timestamp": "2026-02-26T14:30:00Z"
}
```

---

## Design Resource Schema (aws-design.json resource object)

Template for individual resource mappings in aws-design.json.

```json
{
  "gcp_address": "google_sql_database_instance.prod_postgres",
  "gcp_type": "google_sql_database_instance",
  "gcp_config": {
    "database_version": "POSTGRES_13",
    "region": "us-central1",
    "tier": "db-custom-2-7680"
  },
  "aws_service": "RDS Aurora PostgreSQL",
  "aws_config": {
    "engine_version": "14.7",
    "instance_class": "db.r6g.xlarge",
    "multi_az": true,
    "region": "us-east-1"
  },
  "confidence": "deterministic|inferred",
  "rationale": "1:1 Cloud SQL → RDS Aurora; Multi-AZ for production HA",
  "rubric_applied": [
    "Eliminators: PASS",
    "Operational Model: Managed RDS Aurora",
    "User Preference: Structured (q5)",
    "Feature Parity: Full (binary logs, replication)",
    "Cluster Context: Consistent with app tier",
    "Simplicity: RDS Aurora (managed)"
  ]
}
```
