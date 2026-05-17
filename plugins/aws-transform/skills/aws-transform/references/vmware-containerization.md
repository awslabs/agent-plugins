# VMware Containerization

> **Last Updated:** 2026-05-10

## Table of Contents

- [Capabilities](#capabilities)
- [Starting Workflow](#starting-workflow)
- [Agents and Transforms](#agents--transforms)
- [Decision Points](#decision-points)
- [Example Requirements](#example-requirements)
- [Example Tasks](#example-tasks)
- [Known Limitations](#known-limitations)

## Capabilities

Containerize applications from VMware environments for deployment on Amazon ECS or Amazon EKS using AWS Transform's AI-powered agent. Analyzes source code, generates Docker artifacts, builds and publishes container images, and generates Infrastructure as Code for container orchestration platforms.

- Source code analysis → Dockerfiles + configuration files (AI-generated)
- Container image building → Amazon ECR (with automated vulnerability scanning)
- Infrastructure as Code generation → Amazon EKS (Helm charts) or Amazon ECS (Terraform modules)
- Private dependency support → AWS CodeArtifact (Maven, PyPI, npm) + private ECR base images
- Iterative test deployment → validate before production cutover
- Standalone containerization or end-to-end VMware migration with containerize strategy

## Starting Workflow

1. **Review security disclaimer** — accept before proceeding
2. **Clone source code** — Git repository (CodeConnections) or zip upload
3. **Containerize** — AI analyzes source, generates Docker artifacts
4. **Review artifacts** — approve generated Dockerfiles and configuration
5. **Publish images** — build and push to Amazon ECR with vulnerability scanning
6. **Generate IaC** — EKS (Helm charts) or ECS (Terraform modules)
7. **Deploy test** — validate before production
8. **Clean up test** — tear down test resources
9. **Deploy cutover** — production deployment

**Key questions to ask user:**

- "Do you want standalone containerization or end-to-end migration with containerization?"
- "How would you like to provide your source code — Git repository or zip upload?"
- "Where do you want to deploy — Amazon EKS or Amazon ECS?"

## Agents & Transforms

| Agent                                 | How to Discover                            | Purpose                                                                          |
| ------------------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------- |
| VMware Migration Agent (orchestrator) | `list_resources` with `resource: "agents"` | Orchestrates containerization workflow within a VMware migration job             |
| Containerization sub-agent            | _(invoked by orchestrator)_                | Source code analysis, Docker artifact generation, image building, IaC generation |

**Discover the agent dynamically:**

```python
list_resources(resource="agents")
create_job(workspaceId="...", jobName="VMware Containerization",
  objective="Containerize application source code for deployment on ECS/EKS",
  orchestratorAgent="<discovered>")
```

## Decision Points

| Step                 | Question to Ask User                                   | Options                                                         |
| -------------------- | ------------------------------------------------------ | --------------------------------------------------------------- |
| Mode                 | "Standalone containerization or end-to-end migration?" | Standalone / End-to-end migration                               |
| Source code          | "How would you like to provide your source code?"      | Git repository (CodeConnections) / Zip upload                   |
| Artifact review      | "Do the generated Docker artifacts look correct?"      | Approve / Request changes                                       |
| Private dependencies | "Does your application use private dependencies?"      | Configure CodeArtifact / Configure private ECR base images / No |
| Deployment target    | "Where do you want to deploy?"                         | Amazon EKS (Helm charts) / Amazon ECS (Terraform modules)       |
| Test validation      | "Has the test deployment been validated?"              | Proceed to cutover / Re-deploy test / Modify configuration      |
| Cutover              | "Ready to deploy production infrastructure?"           | Deploy cutover / Go back to test                                |

## Example Requirements

```
## Requirement 1: Source Code Containerization

**User Story:** As a platform engineer, I want my VMware-hosted application containerized
so that it can run on Amazon EKS or Amazon ECS.
**Acceptance Criteria:**

1. WHEN containerization completes, a Dockerfile SHALL be generated for each application component
2. WHEN containerization completes, container images SHALL be published to Amazon ECR
3. WHEN containerization completes, vulnerability scanning SHALL report no critical findings
   **Handled by:** AWS Transform VMware Migration Agent (Containerization sub-agent)

## Requirement 2: Infrastructure as Code Generation

**User Story:** As a DevOps engineer, I want deployment infrastructure generated
so that I can deploy containerized applications to my target platform.
**Acceptance Criteria:**

1. WHEN IaC generation completes for EKS, Helm charts SHALL be generated with security scanning passed
2. WHEN IaC generation completes for ECS, Terraform modules SHALL be generated with validation passed
   **Handled by:** AWS Transform VMware Migration Agent (Containerization sub-agent)
```

## Example Tasks

```
- [ ] 1. Setup
  - [ ] 1.1 Create VMware migration job
  - [ ] 1.2 Select containerization mode
  - [ ] 1.3 Review and accept security disclaimer
- [ ] 2. Source code provisioning
  - [ ] 2.1 Provide source code (Git repo or zip upload)
  - [ ] 2.2 Configure private dependencies (if applicable)
- [ ] 3. Containerization
  - [ ] 3.1 AI agent analyzes source code
  - [ ] 3.2 Review generated Docker artifacts
  - [ ] 3.3 Approve code changes
- [ ] 4. Image publishing
  - [ ] 4.1 Build and publish to Amazon ECR
  - [ ] 4.2 Review vulnerability scan results
- [ ] 5. IaC generation
  - [ ] 5.1 Select deployment target (EKS or ECS)
  - [ ] 5.2 Generate and review IaC
- [ ] 6. Test deployment
  - [ ] 6.1 Deploy and validate test infrastructure
  - [ ] 6.2 Clean up test infrastructure
- [ ] 7. Production cutover
  - [ ] 7.1 Deploy cutover infrastructure
  - [ ] 7.2 Confirm migration complete
```

## Known Limitations

- Containerization is accessed through a VMware migration job — cannot be started independently
- Individual source files must not exceed 1 GB; total source code must not exceed 8 GB
- Private dependencies require pre-configured AWS CodeArtifact repositories or private ECR base images
- EKS deployments require an existing cluster or permissions to create one
- AI-generated Dockerfiles may need manual tuning for complex builds
- TOOL_APPROVAL tasks (image publishing, deployments, cleanup) must be approved in the web UI — cannot be completed via API
