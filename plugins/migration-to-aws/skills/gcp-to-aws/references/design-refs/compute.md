# Compute Services Design Rubric

**Applies to:** Cloud Run, Cloud Functions, Compute Engine, GKE, App Engine

**Quick lookup (no rubric):** Check `fast-path.md` first (Cloud Run → Fargate, Cloud Functions → Lambda, etc.)

## Eliminators (Hard Blockers)

| GCP Service     | AWS     | Blocker                                                                              |
| --------------- | ------- | ------------------------------------------------------------------------------------ |
| Cloud Run       | Lambda  | Execution time >15 min → use Fargate                                                 |
| Cloud Run       | Fargate | GPU workload or >16 vCPU or >120 GB memory → use EC2                                 |
| Cloud Functions | Lambda  | Python version not supported (e.g., Python 2.7) → consider custom runtime on Fargate |
| GKE             | EKS     | Custom CRI incompatible → manual workaround or ECS                                   |

## Signals (Decision Criteria)

### Cloud Run / App Engine

- **Always-on** or **cold-start sensitive** → Fargate (not Lambda)
- **Stateless microservice** + **<15 min execution** → Lambda
- **HTTP-only** + **container-native** → Fargate preferred (better dev/prod parity)

### Cloud Functions

- **Event-driven** + **<15 min** + **Python/Node/Go** → Lambda
- **Always-on or long** → run as Container on Fargate or ECS

### Compute Engine (VMs)

- **Always-on workload** → EC2 (reserved or on-demand based on cost sensitivity)
- **Batch/periodic jobs** → EC2 with Auto Scaling (scale to 0 in dev)
- **Windows-only workload** → EC2 (Lambda/Fargate support limited)

### GKE

- **Kubernetes orchestration** required → EKS
- **No K8s requirement** + **microservices** → Fargate (simpler, no cluster overhead)

## 6-Criteria Rubric

Apply in order; first match wins:

1. **Eliminators**: Does GCP config violate AWS constraints? If yes: switch to alternative
2. **Operational Model**: Managed (Lambda, Fargate) vs Self-Hosted (EC2, EKS)?
   - Prefer managed unless: Always-on + high baseline cost → EC2
3. **User Preference**: From `clarified.json`, q3 (team experience) or q2 (primary concern)?
   - If `team_experience = "expert"` + `primary_concern = "control"` → EC2
   - If `team_experience = "novice"` + `primary_concern = "cost"` → Fargate
4. **Feature Parity**: Does GCP config require AWS-unsupported features?
   - Example: GCP auto-scaling to zero + cold-start-sensitive → Fargate (not Lambda)
5. **Cluster Context**: Are other resources in this cluster using EKS/EC2/Fargate?
   - Prefer same platform (affinity)
6. **Simplicity**: Fewer resources = higher score
   - Fargate (1 service) > EC2 (N services for ASG + monitoring)

## Examples

### Example 1: Cloud Run (stateless API)

- GCP: `google_cloud_run_service` (memory=512MB, timeout=60s, min_instances=1)
- Signals: HTTP, stateless, always-on
- Criterion 1 (Eliminators): PASS (60s < 15min doesn't apply; stateless OK)
- Criterion 2 (Operational Model): FARGATE preferred
- → **AWS: Fargate (0.5 CPU, 1 GB memory)**
- Confidence: `deterministic` (or `inferred` if variant from fast-path)

### Example 2a: Cloud Functions (event processor, short-running)

- GCP: `google_cloudfunctions_function` (runtime=python39, timeout=540s)
- Signals: Event-driven, 540s = 9 minutes (< 15min limit)
- Criterion 1 (Eliminators): PASS on timeout (540s < 900s)
- Criterion 2 (Operational Model): Lambda preferred for event-driven + short-running
- → **AWS: Lambda with EventBridge trigger**
- Confidence: `inferred`

### Example 2b: Cloud Functions (long-running batch processor)

- GCP: `google_cloudfunctions_function` (runtime=python39, timeout=1200s)
- Signals: Event-driven but 1200s = 20 minutes (> 15min limit)
- Criterion 1 (Eliminators): FAIL on timeout (1200s > 900s) → **cannot use Lambda**
- Criterion 2 (Operational Model): Fargate (managed + can handle longer execution)
- → **AWS: Fargate (0.5 CPU, 1 GB memory) with EventBridge trigger**
- Confidence: `inferred`

### Example 3: Compute Engine (background job)

- GCP: `google_compute_instance` (machine_type=e2-medium, region=us-central1, startup_script=...)
- Signals: Periodic batch job (inferred from startup script), always-on
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): EC2 (explicit compute control)
- Criterion 3 (User Preference): If q2=`cost`, prefer auto-scaling → EC2 + ASG (scale to 0)
- → **AWS: EC2 t3.medium + Auto Scaling Group (min=0 in dev)**
- Confidence: `inferred`

## Output Schema

```json
{
  "gcp_type": "google_cloud_run_service",
  "gcp_address": "example-service",
  "gcp_config": {
    "memory_mb": 512,
    "timeout_seconds": 60
  },
  "aws_service": "Fargate",
  "aws_config": {
    "cpu": "0.5",
    "memory_mb": 1024,
    "region": "us-east-1"
  },
  "confidence": "deterministic",
  "rationale": "1:1 mapping; Cloud Run (stateless, <15min) → Fargate (always-on)",
  "rubric_applied": [
    "Eliminators: PASS",
    "Operational Model: Managed preferred",
    "User Preference: N/A",
    "Feature Parity: Full",
    "Cluster Context: Fargate affinity",
    "Simplicity: Fargate (1 service)"
  ]
}
```
