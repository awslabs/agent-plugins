# Frontend & Testing Phase Instructions

Connect the frontend application to the Amplify Gen 2 backend and verify everything works.

## Prerequisites Confirmed

Prerequisites (Node.js, npm, AWS credentials) were already validated by the orchestrator workflow. Do not re-validate.

**Required:** `amplify_outputs.json` must exist in the project root. If it does not exist, inform the user that sandbox deployment (Phase 2) must be completed first. Do NOT proceed without it.

## Retrieve and Follow the SOP

**Do NOT write any code until you have retrieved and read the SOP.**

Use the SOP retrieval tool to get **"amplify-frontend-integration"** and follow it completely.

**If SOP retrieval fails** (empty result, error, or timeout), STOP and inform the user: "I couldn't retrieve the frontend integration guide. Please verify that the aws-mcp server is active and try again." Do NOT attempt to write integration code from general knowledge.

### SOP Overrides

- **Skip the SOP's Step 12** ("Determine Next SOP Requirements") -- phase sequencing is controlled by the orchestrator workflow, not the SOP.

Follow all other SOP steps completely. Do not improvise or skip them.

### Error Handling

1. If you encounter an error, fix the immediate issue
2. Return to the SOP and continue from where you left off
3. Do NOT abandon the SOP or start improvising
4. If you lose track, retrieve the SOP again, identify your last completed step, and continue

## Local Testing

After the SOP is fully executed, present the testing instructions to the user:

```
## Time to test!

### Start your dev server
[framework-specific command, e.g., npm run dev, npx next dev, etc.]

### Try these features
[list all features that were implemented in this session]

Let me know how it goes -- or if anything needs changes!
```

**Wait for the user to test and respond.**

- If the user reports issues, fix them within this phase. Use the SOP's troubleshooting section and documentation tools as needed. After fixing, ask the user to test again.
- If the user confirms everything works (or has no further changes), proceed to phase completion below.

## Phase Complete

Once the user confirms testing is successful (or has no changes needed), summarize the frontend integration and testing results.

This phase is now complete. Do not read other reference files or proceed to the next phase — return control to the orchestrator workflow (SKILL.md).
