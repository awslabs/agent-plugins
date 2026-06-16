# Custom vs continuous modernization Routing

Route customer requests to the correct skill set. continuous modernization supports local, local-parallel,
new EC2, existing EC2, and Fargate + AWS Batch as compute options; Custom supports local
and Fargate + AWS Batch. The compute choice is independent of the Custom-vs-continuous modernization choice;
pick routing first, then surface compute options.

## ⚠️ MANDATORY: Permission Consent After Compute Choice

**When the customer chooses a remote compute option (EC2 or Batch/Fargate), the VERY FIRST response to the customer MUST be the permission consent message from the chosen execution skill. Do NOT ask any setup questions (source, analysis type, region, existing instance, etc.) before showing the consent message. If the customer says no, warn them about potential permission errors but continue anyway.**

## Prerequisite: workload check

This file applies ONLY when the request has cleared SKILL.md Step B. The decision tables below
assume you have already established that the request is not VMware, SQL/database, or mainframe,
and — for .NET — that the user explicitly chose "analyze for tech debt / security" over
"modernize." Do NOT use this file's keyword lists to override SKILL.md Step B:

- VMware → never continuous modernization; use [vmware](vmware.md).
- SQL / Database (SQL Server, Oracle, MySQL, Aurora) → never continuous modernization; use [sql](sql.md).
- Mainframe / COBOL → never continuous modernization; use [mainframe](mainframe.md).
- .NET → ask intent first per SKILL.md Step B (three options: modernize / assessment for modernization / analyze for tech debt or security or CVEs). Only the "analyze for tech debt or security or CVEs" choice routes here. "Modernize" and "Assessment for modernization" both stay in the .NET workload.

The "Routes to continuous modernization (always)" list below means "always relative to Custom" — it does NOT mean
"override the workload identification step."

## Decision 1: Analysis-Time Routing (Starting Work)

| Customer Intent                                                                  | Route To                               | Notes                                                             |
| -------------------------------------------------------------------------------- | -------------------------------------- | ----------------------------------------------------------------- |
| "analyze / analysis / find / what's wrong / where do I start / evaluate my code" | **continuous modernization analysis**  | Default for new customers and ambiguous requests                  |
| "Find security vulnerabilities / CVEs / security check / is my code secure"      | **continuous modernization analysis**  | continuous modernization-exclusive; Custom has no security TD     |
| "Generate report / dashboard / trend / compare"                                  | **continuous modernization reporting** | continuous modernization-exclusive; Custom is stateless           |
| Customer mentions "continuous-modernization" by name                             | **continuous modernization**           | Explicit request; honor the ask                                   |
| Named transformation (e.g., "Upgrade Java 8 to 21"), no prior findings           | **Custom**                             | Greenfield, no audit trail needed                                 |
| "Run our internal/org-specific TD"                                               | **Custom**                             | TD authoring/execution, no portfolio context                      |
| Customer not sure / first-time                                                   | **continuous modernization analysis**  | Adoption bias; continuous modernization is the default front door |

## Decision 2: Remediation-Time Routing (Fixing Existing Findings)

Before answering, check: do the repos in scope have any prior continuous modernization analysis findings?

| State                                                       | Route To                                            | Why                                                                      |
| ----------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------ |
| Prior continuous modernization findings exist               | **continuous modernization remediation** (always)   | Must write to event log; otherwise next analysis can't attribute the fix |
| No prior findings, customer names a specific transformation | **Custom**                                          | Stateless one-shot, no event log needed                                  |
| No prior findings, customer asks "fix what you can find"    | **continuous modernization analysis → remediation** | Run analysis first, then remediate through same surface                  |

**Mixed scope** (some repos have findings, some don't): Split the request. Route repos
with findings through continuous modernization. Route others through Custom OR ask if they want unified
continuous modernization flow (recommended for adoption).

## Quick Routing Reference

### Routes to Custom (only if NO prior continuous modernization findings on these repos)

- "Upgrade Java / Java 8 to Java 21"
- "Migrate to Java 21"
- "Migrate to Python 3.13"
- "Bump Node 16 to Node 22"
- "Migrate AWS SDK v1 to v2 / boto2 to boto3 / aws-sdk v2 to v3"
- "Spring Boot 2 to 3 / Angular to React / log4j to slf4j"
- "x86 Java to Graviton"
- "Run our internal/org-specific transformation"
- "Run this exact recipe across N repos"

### Routes to continuous modernization (always)

- "What's the state of our codebase?"
- "Scan our repos for issues"
- "What tech debt do we have?"
- "Find security vulnerabilities / CVEs" (continuous modernization-exclusive)
- "Are our repos ready for AI agents?"
- "Which repos can be modernized?"
- "Generate a modernization plan"
- "Where do I start with these 200 repos?"
- "Tell me what's outdated"
- "Auto-fix whatever you can find"
- "Inventory our GitHub org"
- "Find auto-remediable upgrades"
- "Continuous code health monitoring" (continuous modernization exclusive)
- "Single repo — what should I fix?"
- "Compare repos against best practices"
- "I have a CVE, where else does it appear?"
- "Show me a dashboard of code health" (continuous modernization exclusive)
- "Compare this quarter to last quarter" (continuous modernization-exclusive)
- "Generate a report for leadership" (continuous modernization exclusive)
- "I scanned last week, now fix the findings" (continuous modernization exclusive)
- "Apply the remediation we discussed" (continuous modernization exclusive)
- "I'm not sure what we need"
- "What can AWS Transform do for us?"
- "Audit my repos"
- "Evaluate my code"
- Any prompt mentioning "continuous-modernization" by name

## Edge Cases

| Situation                                                                         | Route To                                                                                                              |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Customer names a transformation AND prior continuous modernization findings exist | **continuous modernization** (audit trail wins over phrasing)                                                         |
| Customer says "analyze and upgrade Java"                                          | **continuous modernization** (analysis surfaces the work, then continuous modernization dispatches Custom)            |
| Customer has clear target but >50 repos                                           | **continuous modernization** (scope discovery first), then continuous modernization remediation                       |
| Customer has clear target, <10 repos, no prior findings                           | **Custom**                                                                                                            |
| Mixed scope (some repos with findings, some without)                              | Split; offer unified continuous modernization flow as default                                                         |
| Cross-type (tech-debt findings exist; customer asks for security scan)            | **continuous modernization** (any continuous modernization history → all subsequent work in continuous modernization) |
| Ambiguous request                                                                 | **continuous modernization** (adoption bias)                                                                          |
| Explicit "use Custom" / "use continuous modernization"                            | Honor the ask                                                                                                         |

## Net Rule

**Named transformation + no prior findings → Custom. Anything else → continuous modernization.** When in doubt, continuous modernization.

## How to Check for Prior Findings

**Prerequisite:** Before running any `atx ct` command, verify it's installed AND up to date:

```bash
INSTALLED=$(atx ct --version 2>/dev/null | head -1)
LATEST=$(curl -fsSL "https://transform-cli.awsstatic.com/index.json" 2>/dev/null | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
echo "Installed: ${INSTALLED:-not found}, Latest: ${LATEST:-unknown}"
```

If `INSTALLED` is empty or `LATEST` is newer, follow [continuous-modernization-setup.md](continuous-modernization-setup.md) to install/update it first.

```bash
atx ct status
```

If this returns sources, repos, or findings → continuous modernization has been used before.
Route through continuous modernization for any remediation work.

If `atx ct` is not configured or returns empty → no prior continuous modernization history. Custom is fine for
named transformations.

## Adoption Nudge (After Custom Completes)

After a Custom transformation completes successfully, present this message:

> "Want to see what else might be worth fixing across your repos? AWS Transform - continuous modernization can scan for
> security, tech debt, and modernization opportunities — and keep a record of every
> remediation so future scans can tell you what got fixed and what didn't."

## continuous modernization Skills Reference

| Skill                                                                                      | When to Use                                                                                            |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| [continuous-modernization-guide.md](continuous-modernization-guide.md)                     | New user onboarding, "how do I start?"                                                                 |
| [continuous-modernization-discovery.md](continuous-modernization-discovery.md)             | Analyze/discover repos from sources                                                                    |
| [continuous-modernization-analysis.md](continuous-modernization-analysis.md)               | Run security, tech-debt, agentic-readiness, modernization-readiness analyses                           |
| [continuous-modernization-findings.md](continuous-modernization-findings.md)               | List/filter/manage findings                                                                            |
| [continuous-modernization-remediation.md](continuous-modernization-remediation.md)         | Create remediation campaigns, auto-fix findings                                                        |
| [continuous-modernization-status.md](continuous-modernization-status.md)                   | System overview and health check                                                                       |
| [continuous-modernization-source.md](continuous-modernization-source.md)                   | Manage source connections                                                                              |
| [continuous-modernization-setup.md](continuous-modernization-setup.md)                     | Infrastructure setup and configuration                                                                 |
| [continuous-modernization-server.md](continuous-modernization-server.md)                   | Start, stop, or restart the AWS Transform - continuous modernization (continuous modernization) server |
| [continuous-modernization-ec2-execution.md](continuous-modernization-ec2-execution.md)     | Run CT analysis/remediation on EC2 (new or existing instance)                                          |
| [continuous-modernization-batch-execution.md](continuous-modernization-batch-execution.md) | Run CT analysis on AWS Batch (Fargate) — single job, AWS-managed compute                               |
| [continuous-modernization-schedule.md](continuous-modernization-schedule.md)               | Schedule recurring analyses on an existing EC2 instance (EventBridge Scheduler + SSM)                  |
| [continuous-modernization-reporting.md](continuous-modernization-reporting.md)             | Generate an HTML report of continuous modernization analyses                                           |
| [continuous-modernization-security-agent.md](continuous-modernization-security-agent.md)   | Security agent setup (admin) and runtime verification (executor)                                       |

## Custom Skills Reference

| Skill                                                              | When to Use                         |
| ------------------------------------------------------------------ | ----------------------------------- |
| [custom.md](custom.md)                                             | Named transformations, TD execution |
| [custom-remote-execution.md](custom-remote-execution.md)           | Batch/Fargate remote execution      |
| [custom-single-transformation.md](custom-single-transformation.md) | Single repo transformation          |
| [custom-multi-transformation.md](custom-multi-transformation.md)   | Multi-repo parallel transformation  |
