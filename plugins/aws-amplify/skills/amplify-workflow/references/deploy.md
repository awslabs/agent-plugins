# Deploy Phase Instructions

Deploy an AWS Amplify Gen 2 application to sandbox or production.

## Prerequisites Confirmed

Prerequisites (Node.js, npm, AWS credentials) were already validated by the orchestrator workflow. Do not re-validate.

## SOP Parameter Mapping

The SOP uses `deployment_type` with values `sandbox` or `cicd`. Map based on the deployment target specified by the orchestrator:

- "sandbox", "development", "testing" -> deployment_type: **sandbox**
- "production", "prod", "live", "release", "cicd" -> deployment_type: **cicd**

**app_name**: Infer from the project's `package.json` `name` field or existing Amplify configuration. Only ask the user if it cannot be determined.

Do not ask the user for the deployment type -- the orchestrator specifies it.

## Retrieve and Follow the SOP

Use the SOP retrieval tool to get **"amplify-deployment-guide"** and follow it completely.

**All steps in the SOP must be followed** for any type of deployment (sandbox or production). The SOP contains the latest and most accurate deployment procedures. Do not improvise or skip steps.

**If SOP retrieval fails** (empty result, error, or timeout), STOP and inform the user: "I couldn't retrieve the deployment guide. Please verify that the aws-mcp server is active and try again." Do NOT attempt to deploy from general knowledge.

### SOP Overrides

- **Skip the SOP's Step 1** ("Verify Dependencies") -- prerequisites were already validated by the orchestrator.

Follow all applicable SOP steps for the deployment type. Do not improvise or skip them.

### Error Handling

1. If you encounter an error, fix the immediate issue
2. Return to the SOP and continue from where you left off
3. Do NOT abandon the SOP or start improvising
4. If you lose track, retrieve the SOP again, identify your last completed step, and continue

## Phase Complete

After the SOP is fully executed:

1. Confirm deployment succeeded
2. Verify `amplify_outputs.json` exists in the project root
3. Summarize the deployment results

This phase is now complete. Do not read other reference files or proceed to the next phase — return control to the orchestrator workflow (SKILL.md).
