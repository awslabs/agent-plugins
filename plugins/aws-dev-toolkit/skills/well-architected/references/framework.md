# AWS Well-Architected Framework — Official Reference

Source: https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html

## Key Terminology

| Term | Definition |
|---|---|
| **Component** | Code, configuration, and AWS Resources that together deliver against a requirement. Unit of technical ownership. |
| **Workload** | Set of components that together deliver business value. The level business and tech leaders communicate about. |
| **Architecture** | How components work together in a workload. Focus on communication and interaction patterns. |
| **Milestone** | Key changes in architecture as it evolves (design, implementation, testing, go live, production). |
| **Technology Portfolio** | Collection of workloads required for business operation. |
| **Level of Effort** | High (weeks/months), Medium (days/weeks), Low (hours/days). |

## The Six Pillars — Official Definitions

### 1. Operational Excellence
**Definition**: The ability to support development and run workloads effectively, gain insight into their operations, and to continuously improve supporting processes and procedures to deliver business value.

**Design Principles**:
1. **Perform operations as code** — Define entire workload as code, update with code, implement operations procedures as code
2. **Make frequent, small, reversible changes** — Design workloads for components to be updated regularly, make changes in small increments that can be reversed
3. **Refine operations procedures frequently** — Look for opportunities to improve, evolve procedures, perform game days, review and validate procedures
4. **Anticipate failure** — Perform "pre-mortem" exercises, identify potential sources of failure, test failure scenarios, test response procedures
5. **Learn from all operational failures** — Drive improvement from lessons learned, share across teams and the organization

**Best Practice Areas**: Organization, Prepare, Operate, Evolve

### 2. Security
**Definition**: The ability to protect data, systems, and assets to take advantage of cloud technologies to improve your security posture.

**Design Principles**:
1. **Implement a strong identity foundation** — Least privilege, separation of duties, centralized identity management, eliminate long-term static credentials
2. **Enable traceability** — Monitor, alert, and audit actions in real time, integrate log and metric collection
3. **Apply security at all layers** — Defense in depth at every layer (edge, VPC, load balancer, instance, OS, application, code)
4. **Automate security best practices** — Software-based security mechanisms, version controlled templates, manage programmatically
5. **Protect data in transit and at rest** — Classify data by sensitivity, use encryption, tokenization, and access control
6. **Keep people away from data** — Reduce or eliminate need for direct access to data, reduce risk of mishandling
7. **Prepare for security events** — Incident management and investigation, tools and access in place, practice incident response

**Best Practice Areas**: Security foundations, Identity and access management, Detection, Infrastructure protection, Data protection, Incident response, Application security

### 3. Reliability
**Definition**: The ability of a workload to perform its intended function correctly and consistently when it's expected to, including the ability to operate and test the workload through its total lifecycle.

**Design Principles**:
1. **Automatically recover from failure** — Monitor KPIs, trigger automation when thresholds breached, anticipate and remediate before failure
2. **Test recovery procedures** — Validate recovery strategies by testing failure scenarios, use automation to simulate failures
3. **Scale horizontally to increase aggregate workload availability** — Replace single large resources with multiple small ones, distribute requests
4. **Stop guessing capacity** — Monitor demand and utilization, automate addition/removal of resources
5. **Manage change through automation** — All infrastructure changes via automation, tracked and reviewed

**Best Practice Areas**: Foundations, Workload architecture, Change management, Failure management

### 4. Performance Efficiency
**Definition**: The ability to use computing resources efficiently to meet system requirements, and to maintain that efficiency as demand changes and technologies evolve.

**Design Principles**:
1. **Democratize advanced technologies** — Delegate complex tech to cloud vendor, consume as service rather than self-hosting
2. **Go global in minutes** — Deploy in multiple Regions for lower latency at minimal cost
3. **Use serverless architectures** — Remove need for physical server management, lower transactional costs
4. **Experiment more often** — With virtual resources, quickly test different configurations
5. **Consider mechanical sympathy** — Use the technology approach that aligns best with your goals

**Best Practice Areas**: Selection, Review, Monitoring, Tradeoffs

### 5. Cost Optimization
**Definition**: The ability to run systems to deliver business value at the lowest price point.

**Design Principles**:
1. **Implement Cloud Financial Management** — Invest in FinOps capability, dedicate time and resources to building expertise
2. **Adopt a consumption model** — Pay only for what you consume, scale based on business needs (75% savings by stopping dev/test after hours)
3. **Measure overall efficiency** — Measure business output and delivery costs together, understand gains from optimizations
4. **Stop spending money on undifferentiated heavy lifting** — Use AWS for infrastructure operations, use managed services
5. **Analyze and attribute expenditure** — Identify costs and usage accurately, attribute to workload owners, measure ROI

**Best Practice Areas**: Practice Cloud Financial Management, Expenditure and usage awareness, Cost-effective resources, Manage demand and supply resources, Optimize over time

### 6. Sustainability
**Definition**: The ability to continually improve sustainability impacts by reducing energy consumption and increasing efficiency across all components of a workload.

**Design Principles**:
1. **Understand your impact** — Measure cloud workload impact, model future impact, compare output vs total impact
2. **Establish sustainability goals** — Set long-term goals per workload, model ROI, plan for growth with reduced impact intensity
3. **Maximize utilization** — Right-size for high utilization, eliminate idle resources (two hosts at 30% < one host at 60%)
4. **Anticipate and adopt new, more efficient hardware and software offerings** — Monitor and evaluate, design for flexibility
5. **Use managed services** — Shared services maximize utilization, reduce infrastructure needed (Fargate, S3 lifecycle, Auto Scaling)
6. **Reduce the downstream impact of your cloud workloads** — Reduce energy/resources customers need, eliminate need for device upgrades

**Best Practice Areas**: Region selection, Alignment to demand, Software and architecture, Data, Hardware and services, Process and culture

## Specialty Lenses (Official)

| Lens | Focus Area |
|---|---|
| Serverless Applications | Lambda, API Gateway, Step Functions, DynamoDB workloads |
| SaaS | Multi-tenant SaaS architecture patterns |
| Machine Learning | ML training and inference pipelines |
| Data Analytics | Data lake, warehouse, streaming analytics |
| IoT | Device management and data processing |
| Financial Services | Regulated financial industry workloads |
| Healthcare | HIPAA and healthcare compliance |
| Games | Game servers, real-time multiplayer |
| Container Build | Container-based deployments |
| Hybrid Networking | On-premises to cloud connectivity |
| SAP | SAP workloads on AWS |
| Streaming Media | Media delivery and processing |

## WA Tool — Key Concepts

| Concept | Description |
|---|---|
| **Workload** | Primary unit of review in the WA Tool |
| **Lens** | Set of questions specific to a workload type or industry |
| **Review** | Running a lens against a workload (answering questions) |
| **Risk** | HRI (High Risk Issue), MRI (Medium Risk Issue), identified by unanswered or negatively-answered questions |
| **Milestone** | Snapshot of a workload review at a point in time |
| **Improvement Plan** | Actions to resolve identified risks, auto-generated from review answers |

## WA Tool CLI Commands

```bash
# List workloads
aws wellarchitected list-workloads --query 'WorkloadSummaries[].{Name:WorkloadName,ID:WorkloadId,RiskCounts:RiskCounts}' --output table

# Create a workload
aws wellarchitected create-workload --workload-name "My App" --description "Production API" --environment PRODUCTION --lenses wellarchitected --aws-regions us-east-1

# List available lenses
aws wellarchitected list-lenses --query 'LensSummaries[].{Name:LensName,Alias:LensAlias,Version:LensVersion}' --output table

# Get workload review answers for a pillar
aws wellarchitected list-answers --workload-id WL_ID --lens-alias wellarchitected --pillar-id security

# Create a milestone (snapshot current state)
aws wellarchitected create-milestone --workload-id WL_ID --milestone-name "Q1-2026-review"

# Get improvement plan
aws wellarchitected list-lens-review-improvements --workload-id WL_ID --lens-alias wellarchitected --pillar-id security
```
