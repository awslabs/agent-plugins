---
name: amplify-workflow
description: Orchestrates AWS Amplify Gen 2 workflows for building full-stack apps with React, Next.js, Vue, Angular, React Native, Flutter, Swift, or Android. Use when user wants to BUILD, CREATE, or DEPLOY Amplify projects, add authentication, data models, storage, GraphQL APIs, Lambda functions, or deploy to sandbox/production. Do NOT invoke for conceptual questions, comparisons, or troubleshooting unrelated to active development.
---

# Amplify Workflow

Orchestrated workflow for AWS Amplify Gen 2 development.

## Available references

- **`references/backend.md`** -- Backend phase: SOP retrieval, constraints, error handling
- **`references/frontend.md`** -- Frontend & testing phase: SOP retrieval, local testing
- **`references/deploy.md`** -- Deploy phase: SOP retrieval, deployment type mapping

## Available scripts

- **`scripts/prereq-check.sh`** -- Validates Node.js, npm, AWS CLI, and AWS credentials

## Defaults

- **Phase ordering**: Backend → Sandbox → Frontend → Production (only applicable phases are included)
- **Deployment target**: `sandbox` for development/testing, `cicd` for production

---

## Step 1: Validate Prerequisites

Run the prerequisite check script:

```bash
bash scripts/prereq-check.sh
```

The script checks Node.js >= 18, npm, and AWS credentials in one pass and reports a clear PASS/FAIL summary.

If the AWS credentials check fails, **STOP** and present this message to the user:

```
## AWS Credentials Required

I can't proceed without AWS credentials configured. Please set up your credentials first:

**Setup Guide:** https://docs.amplify.aws/react/start/account-setup/

**Quick options:**
- Run `aws configure` to set up access keys
- Run `aws sso login` if using AWS IAM Identity Center

Once your credentials are configured, let me know and I'll re-run the prerequisite check to verify.
```

**Do NOT proceed with Amplify work until credentials are configured.** After the user confirms credentials are set up, re-run `scripts/prereq-check.sh` to verify before continuing.

---

## Step 2: Understand the Project

Once all prerequisites pass:

1. Read all necessary project files (e.g., `amplify/`, `package.json`, existing code) to understand the current state
2. If unsure about Amplify capabilities or best practices, use documentation tools to search and read AWS Amplify docs

Do this BEFORE proposing a plan.

---

## Step 3: Determine Applicable Phases

Based on the user's request and project state, determine which phases apply:

| Phase              | Applies when                                             | Reference                |
| ------------------ | -------------------------------------------------------- | ------------------------ |
| 1: Backend         | User needs to create or modify Amplify backend resources | `references/backend.md`  |
| 2: Sandbox         | Deploy to sandbox for testing                            | `references/deploy.md`   |
| 3: Frontend & Test | Frontend needs to connect to Amplify backend             | `references/frontend.md` |
| 4: Production      | Deploy to production                                     | `references/deploy.md`   |

Common patterns:

- **New full-stack app:** 1 -> 2 -> 3 -> 4
- **Backend only (no frontend):** 1 -> 2
- **Add feature to existing backend:** 1 -> 2
- **Redeploy after changes:** 2 only
- **Connect existing frontend:** 3 only
- **Deploy to production:** 4 only

**IMPORTANT: Only include phases that the user actually needs.** If the user asks for backend work only (e.g., "add auth", "create a data model", "add storage"), do NOT include Phase 3 (Frontend & Test). Frontend phases should only be included when the user explicitly asks for frontend work, a full-stack app, or to connect a frontend to Amplify.

---

## Step 4: Present Plan and Confirm

Present to the user:

```
## Plan

### What I understood
- [Brief summary of what the user wants]

### Features
[list features if applicable]

### Framework
[framework if known]

### Phases I'll execute
1. [Phase name] - [one-line description] -> SOP: [sop-name]
2. [Phase name] - [one-line description] -> SOP: [sop-name]
...
(Include SOP name for phases 1 and 3. Phases 2 and 4 use the amplify-deployment-guide SOP.)

Ready to get started?
```

**WAIT for user confirmation before proceeding.**

**Once the user approves the plan, you MUST stick to it. Do not deviate from the planned phases or SOPs unless the user explicitly asks for changes.**

---

## Step 5: Execute Phases

After the user confirms the plan, read **ONLY the first phase's reference file** (from the table in Step 3).

**Do NOT read any other phase reference files yet.**

### Phase Execution

When starting a phase, announce it as a header:

```
## Phase 1: Backend
[Next: Phase 2: Sandbox Deployment]
```

Omit "[Next: ...]" if it's the last phase in your plan.

### Resuming After a Phase Completes

When a phase completes (the reference file will indicate the phase is done), the orchestrator takes over:

1. Summarize what the phase accomplished
2. If there are more phases in the plan, ask: "Phase [N] complete. Ready to proceed to Phase [N+1]: [next phase name]?"
3. **WAIT for the user to confirm before proceeding.**
4. After the user confirms, read the next phase's reference file.

Do NOT re-run prerequisites or re-present the plan. Simply execute the next phase.

---

### Phase 1: Backend

Read [references/backend.md](references/backend.md) and follow its instructions completely.

---

### Phase 2: Sandbox Deployment

Read [references/deploy.md](references/deploy.md) and follow its instructions. The deployment type is **sandbox** (deployment_type: `sandbox`).

---

### Phase 3: Frontend & Test

**Prerequisite:** `amplify_outputs.json` must exist. If not, run Phase 2 first.

Read [references/frontend.md](references/frontend.md) and follow its instructions completely.

---

### Phase 4: Production Deployment

Read [references/deploy.md](references/deploy.md) and follow its instructions. The deployment type is **production** (deployment_type: `cicd`).

**After completion:**

```
## You're live!

### Production URL
[url from deployment output]

### Amplify Console
https://console.aws.amazon.com/amplify/home

Your app is now deployed! Future updates: just push to your repo and it auto-deploys.
```

This is the final phase. The workflow is complete.

---

## Critical Rules

1. **Always follow SOPs completely** -- Do not improvise or skip steps
2. **Never use Gen 1 patterns** -- This is for Amplify Gen 2 only (TypeScript code-first, `defineAuth`/`defineData`/`defineStorage`/`defineFunction`)
3. **Wait for confirmation between phases** -- After each phase completes, ask the user to confirm before executing the next phase. Do not proceed until the user confirms.
4. **If you encounter an error or get sidetracked:**
   - Fix the immediate issue
   - Return to the SOP and continue from where you left off
   - Do NOT abandon the SOP or start improvising
5. **If you lose track of where you were in the SOP:**
   - Use the SOP retrieval tool to get the SOP again
   - Identify which step you completed last
   - Continue from the next step

---

## Troubleshooting

If issues occur during any phase:

1. Check the SOP's troubleshooting section first
2. Use documentation tools to search AWS Amplify docs for the error message
3. Read the relevant documentation page

**After resolving the issue, immediately return to the SOP and continue from where you left off. Do not abandon the workflow.**
