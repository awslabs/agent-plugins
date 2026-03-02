---
name: code-review
description: Automated code review for pull requests using multiple specialized review passes with confidence-based scoring to filter false positives. Use when reviewing a pull request, performing code review, checking PR quality, or when the user says "review this PR" or "code review".
license: Apache-2.0
metadata:
  author: Anthropic
  version: "1.0"
  origin: code-review@claude-plugins-official
allowed-tools: Bash(gh:*)
---

# Code Review

Provide a comprehensive code review for a given pull request.

## Workflow

Follow these steps precisely:

### Step 1: Eligibility Check

Check if the pull request:

- Is closed
- Is a draft
- Does not need a code review (e.g., automated PR or trivially simple)
- Already has a code review from you

If any of these conditions are true, do not proceed. Inform the user why.

### Step 2: Gather Project Guidelines

Find all relevant project guideline files from the codebase:

- The root `CLAUDE.md` or `AGENTS.md` file (if one exists)
- Any guideline files in directories whose files the pull request modified
- Any `.kiro/steering/` files that may contain project standards

Only collect file paths at this stage, not full contents.

### Step 3: Summarize the Change

View the pull request and produce a brief summary of what it changes.

Use: `gh pr view <PR_NUMBER>` and `gh pr diff <PR_NUMBER>`

### Step 4: Parallel Review Passes

Perform 5 independent review passes, each from a different angle:

**Pass 1 - Guideline Compliance**: Audit the changes against the project guidelines found in Step 2. Note that guidelines are guidance for the AI as it writes code, so not all instructions will be applicable during code review.

**Pass 2 - Bug Scan**: Read the file changes and do a shallow scan for obvious bugs. Focus just on the changes themselves. Focus on large bugs, avoid small issues and nitpicks. Ignore likely false positives.

**Pass 3 - Historical Context**: Read the git blame and history of the modified code to identify any bugs in light of that historical context.

**Pass 4 - Previous PR Context**: Read previous pull requests that touched these files and check for any comments on those PRs that may also apply to the current pull request.

**Pass 5 - Code Comment Compliance**: Read code comments in the modified files and make sure the PR changes comply with any guidance in the comments.

### Step 5: Confidence Scoring

For each issue found in Step 4, score it on a scale from 0-100 indicating confidence that the issue is real vs. a false positive:

- **0**: Not confident at all. False positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
- **25**: Somewhat confident. Might be a real issue, but may also be a false positive. If stylistic, not explicitly called out in project guidelines.
- **50**: Moderately confident. Verified as real, but might be a nitpick or rare in practice.
- **75**: Highly confident. Double-checked and verified as very likely real and impactful. For guideline issues, verified the guideline explicitly mentions it.
- **100**: Absolutely certain. Confirmed as definitely real and frequent in practice.

For issues flagged due to project guideline instructions, double check that the guideline actually calls out that issue specifically.

### Step 6: Filter

Filter out any issues with a score less than 80. If no issues meet this criteria, proceed to Step 8 with "no issues found."

### Step 7: Re-check Eligibility

Re-verify the PR is still eligible for review (not closed, merged, or already reviewed since Step 1).

### Step 8: Post Comment

Use `gh pr comment` to post the review on the pull request.

**Format when issues are found:**

```markdown
### Code review

Found N issues:

1. <brief description of issue> (CLAUDE.md says "<...>")

https://github.com/OWNER/REPO/blob/FULL_SHA/path/file.ext#L[start]-L[end]

2. <brief description of issue> (bug due to <explanation>)

https://github.com/OWNER/REPO/blob/FULL_SHA/path/file.ext#L[start]-L[end]
```

**Format when no issues are found:**

```markdown
### Code review

No issues found. Checked for bugs and project guideline compliance.
```

## Important Notes

- Keep output brief
- Avoid emojis
- Link and cite relevant code, files, and URLs
- Use `gh` to interact with GitHub (view PRs, create comments)
- You must cite and link each issue
- Code links must use the full git SHA (not abbreviated)
- Code links must include `#L[start]-L[end]` line range with at least 1 line of context
- Do not check build signal or attempt to build/typecheck the app
