---
name: reporting
description: Generate a self-contained HTML report visualizing the user's continuous modernization journey — sources connected, repos discovered, analyses run, findings, remediations launched. Use when: report, dashboard, show me everything, recap, status report, what have we done.
argument-hint: "[--repo <source>::<slug>]"
---

# Reporting

Generate a single self-contained HTML report that walks through everything AWS Transform - continuous modernization has done in this account: sources connected, repos discovered, analyses run, findings produced, remediations launched (with PR URLs). The agent assembles the HTML from the data it gathered and opens it in the browser.

The report is a **static snapshot**: the HTML has all data baked in as JS consts, so it's portable (emailable, openable offline) and reflects the moment the report was generated.

## Data sources

Populate the report from live `atx ct` reads.

```bash
atx ct source list --json
atx ct repository list --json
atx ct analysis list --json
atx ct findings list --max-items 10000 --json   # exits 2 with a nextToken when there are more; see below
atx ct remediation list --json
```

### Paginate every list to completion (nextToken)

Response shape can vary by CLI version, so don't hard-code it: a list command may return every result at once, a bare array, or an object that wraps the array alongside a top-level `nextToken`. The report is a **static snapshot baked from this data**, so a dropped page silently loses sources, repos, analyses, findings, or remediations. The version-agnostic rule: after each list call, check whether the response carries a non-empty `nextToken`; if it does, call the command again with `--next-token <token>` and repeat until no `nextToken` remains, then concatenate all pages before normalizing. If there is no `nextToken`, the single response is already complete. A truncated `findings` or `remediation` fetch skews every KPI and chart downstream.

`findings list` is the one that pages in practice: it reads about `--max-items` findings per call (1000 by default, at most 10,000). A partial read exits with status 2 — expected, not a failure — and prints `{"findings": [...], "truncated": true, "total_count": N, "nextToken": "..."}` instead of a bare array; take the records from `findings`. If the account has very many findings, use `atx ct findings count --by severity --json` (and `--by analysis-type`, `--by status`) for the KPI and chart numbers instead of paging every finding.

### Raw response shapes

The five commands do NOT return the same envelope, and the exact container can vary by CLI version — `repository list` wraps results in `{"items": [...], "nextToken": null, "total": N}`, `findings list` returns an object only when truncated (above), and the others come back as a bare array. Read the records wherever they live and follow `nextToken` when it's present. The shapes below describe the objects **inside** each list. All field names are snake_case except the source fields shown.

**`source list --json`** → flat array:

```jsonc
[{
  "source": "...",
  "provider": "github",
  "identifier": "...",
  "provider_config": {}, // optional
  "authMode": "PAT|OAUTH", // optional
  "connectedStatus": "CONNECTED|DISCONNECTED"
}] // optional, OAuth sources only
```

**`repository list --json`** → object with `items` array:

```jsonc
{
  "items": [
    {
      "id": "<source>::<slug>",
      "slug": "<source>::<slug>",
      "full_name": "...",
      "default_branch": "main",
      "language": null,
      "private": false,
      "archived": false,
      "assessed": false,
      "source": "...",
      "labels": []
    }
  ],
  "nextToken": null,
  "total": 1
}
```

**`analysis list --json`** → flat array. Note: there is NO `findings` array on an analysis row — the count must be joined from `findings.json`.

```jsonc
[ { "id": "01K...", "status": "complete|running|failed|cancelled|pending|null",
    "analysis_type": "tech-debt-quick|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|graviton-readiness|custom",
    "category": "Security", "display_name": "...",
    "repos": ["<source>::<slug>", ...], "repos_total": 4, "repos_failed": 1,
    "display_status": "complete|complete_with_failures|partially_complete|failed|cancelled|running|pending",
    "started_at": "2026-...", "completed_at": "2026-...",
    "error": null, "repo_errors": { "<source>::<slug>": "..." } } ]
```

`tech-debt-quick` is the stored name of `rapid-techdebt-analysis`; label it "rapid-techdebt-analysis" in the report.

**`findings list --json`** → flat array (or the truncated object above):

```jsonc
[ { "id": "01K...", "analysis_id": "01K..." | "manual:01K...",
    "repo": "<source>::<slug>", "analysis_type": "...", "severity": "high|medium|low",
    "category": "...", "title": "...", "description": "...",
    "status": "open|dismissed|obsolete|change_ready",
    "metadata": { "status": "ACTIVE|RESOLVED|..." },     // security: the Security Agent's own state
    "file_refs": ["path/to/file.java#L1-L10"],
    "fix": { "kind": "atx-transform", "transform_name": "AWS/...", "effort": "Low" }
         | { "kind": "security-agent", ... } | null } ]
```

**`remediation list --json`** → flat array. `repos` is an OBJECT keyed by slug, NOT an array. Statuses are lowercase. The PR URL is `repos[<slug>].execution_artifacts.transform_pr_url` (transformation runs) or `.pull_request_link` (security runs); a diff-only security result has `.code_diff_link`.

```jsonc
[ { "id": "01K...", "name": "...", "transform_name": "...",
    "status": "pending|running|completed|partial|failed|cancelled",   // lowercase
    "display_status": "complete|complete_with_failures|partially_complete|failed|cancelled|running|pending",
    "started_at": "...", "completed_at": "...", "finding_ids": [...],
    "repos": {
      "<source>::<slug>": {
        "status": "pr_open|diff_ready|no_changes|already_applied|pr_exists|skipped|failed|blocked|cancelled|pending|running",
        "transform_name": "...", "finding_id": "...",
        "execution_artifacts": { "transform_pr_url": "https://...", "pull_request_link": "https://...", "code_diff_link": "https://..." },
        "error": "..." }
    } } ]
```

### Normalization

**Findings.** `findingId=id`, `repositoryId=repo`, `severity`, `analysisType=analysis_type`, `category`, `title`, `fileRefs=file_refs`, `fix={kind: fix.kind, transformName: fix.transform_name}` (only if `fix` is non-null; a `security-agent` fix has `transform_name: null`). Status: use the top-level `status` for every analysis type, security included (default `open` if missing) — it is what `findings list --status` filters on and what dismissing changes; `metadata.status` is the Security Agent's own state, not the finding's.

**Analyses.** `id`, `analysisType=analysis_type`, `status`, `repos`, `startedAt=started_at`, `completedAt=completed_at`, `failureReason=error` (fall back to the first `repo_errors` value). To compute `findingsCount`, build a map first: `findingsByAnalysisId = groupBy(findings, f => f.analysis_id)`. Manual findings carry `analysis_id` of the form `"manual:<id>"` — also key by the unprefixed `<id>` so manual analyses match. Then `findingsCount = (findingsByAnalysisId[analysis.id] || []).length`. **Drop analyses with status `null`** (the literal string) — these are integ-test artifacts that don't belong in the report.

**Remediations.** Convert `repos` (object) to `repoStatuses` (array):

```js
// raw:        r.repos = { "<slug>": { status, execution_artifacts: { transform_pr_url | pull_request_link }, error } }
// normalized: r.repoStatuses = [{ slug, status, executionRefs: { prUrl }, error }, ...]
const repoStatuses = Object.entries(r.repos || {}).map(([slug, rs]) => ({
  slug,
  status: rs.status,
  executionRefs: { prUrl: rs.execution_artifacts?.transform_pr_url ?? rs.execution_artifacts?.pull_request_link },
  error: rs.error,
}));
```

Top-level fields: `id`, `name`, `transformName=transform_name`, `status` (lowercase), `repos = Object.keys(raw.repos)`, `findingIds=finding_ids`, `startedAt=started_at`, `completedAt=completed_at`.

### Scoping with `--repo <source>::<slug>`

If `--repo <source>::<slug>` was passed, scope the report to that repo:

- Replace the `findings list` call with `findings list --repo <source>::<slug> --max-items 10000 --json`.
- Filter analyses client-side to those whose `repos[]` includes the slug.
- Filter remediations client-side to those whose `repos` include the slug.

If a list is empty (no remediations yet, no analyses yet), **skip that section entirely** — don't render an empty placeholder.

## Flow

### Step 1: Gather data

Run the CLI calls above to load the five entity arrays (`sources`, `repositories`, `analyses`, `findings`, `remediations`); there is no server to start or health-check. If a read fails (auth, connection), stop and surface the error rather than rendering a report with an empty section. Normalize per the shape rules above so the renderer can stay simple.

### Step 2: Assemble the HTML

**Generation runs in a subagent — never inline in the main loop.** Producing this report is iterative: write a Python generator, run it, hit a JSON-shape mismatch or a Chart.js misconfig, fix, rerun. When that work happens inline, every Write/Edit/Bash retry is visible to the user and the run reads as broken. Delegating to a single subagent keeps all of it private — the user only sees the API calls (Step 1) and the final HTML (Step 3).

**Save the raw JSON before dispatching.** Persist the five Step 1 outputs to `~/.atxct/shared/reports/raw/<UNIX-TIMESTAMP>/` as `sources.json`, `repositories.json`, `analyses.json`, `findings.json`, `remediations.json` (`mkdir -p` first). The subagent reads them off disk, not from the prompt — JSON for a real account is too large to pass inline.

**Dispatch one subagent.** Inputs:

- The five JSON paths above.
- Output path: `~/.atxct/shared/reports/continuous-modernization-report-<UNIX-TIMESTAMP>.html` (`mkdir -p` first).
- A pointer to this skill — it reads "Raw response shapes," "Normalization," and "Sections" as its spec.
- Approach hint: write a Python generator (more reliable HTML escaping than inline JS templates), run it, validate the HTML file is non-empty and opens, then return.

The subagent's return value is ONE of:

- `{"path": "<absolute path>", "summary": "<one line worth highlighting, e.g. '1 analysis failed', '3 PRs ready for review'>"}`
- `{"error": "<one sentence reason>"}` — only after exhausting reasonable retries (3–4).

Anything else it learned mid-run — intermediate errors, retry counts, scripts written and discarded, JSON-shape surprises — is dropped on the floor and never relayed to the parent or the user.

**HTML output requirements (the subagent must satisfy these):**

- The `<title>` element and the main `<h1>` MUST both be exactly `AWS Transform - continuous modernization Report` — note "continuous modernization" is lowercase, "AWS Transform" stays capitalized. Do not paraphrase or substitute the product name.
- Chart.js loaded via CDN: `<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>`
- All CSS inlined in a `<style>` block
- All data inlined as JS `const` declarations (`SOURCES`, `REPOSITORIES`, `ANALYSES`, `FINDINGS`, `REMEDIATIONS`) — JSON-stringified, then safe-escaped before embedding: replace `</` with `<\/` (a finding's text containing literal `</script>` will otherwise close the data block and break the page) and strip U+2028 / U+2029 (valid in JSON, illegal as JS string literals). Verify by counting `</script>` in the output — expected exactly 2 (Chart.js CDN closer + inline data closer); more means a payload broke containment.
- No `fetch()` calls — the report must open offline

Use a clean modern look: light theme, system font stack, generous whitespace, ~1100px max-width centered. Severity colors: high `#dc2626`, medium `#f59e0b`, low `#10b981`.

### Step 3: Open the report

```bash
open ~/.atxct/shared/reports/continuous-modernization-report-<timestamp>.html
```

Tell the user the path and what's in the report.

### Step 4: Clean up the raw JSON dir

The HTML report has all data baked in — once Step 3 succeeds, the raw JSON files at `~/.atxct/shared/reports/raw/<UNIX-TIMESTAMP>/` are no longer needed:

```bash
rm -rf ~/.atxct/shared/reports/raw/<UNIX-TIMESTAMP>/
```

## Sections (top to bottom)

Each section renders only if its data is non-empty.

### Snapshot header

KPI cards across the top, one number per entity:

```
[ N sources ]  [ N repos ]  [ N analyses ]  [ N open findings ]  [ N remediations ]
```

No chart. Counts pulled from the lengths of each list (open findings = `findings.filter(f => f.status === 'open').length`).

### Sources

Chart: horizontal bar — repos per source. **Cap the chart at top 15 sources by repo count**

Drilldown table — **top 25 sources by repo count**, not all of them. Note the total count above the table and link to `atx ct source list` for the full set.

| Name | Provider | Identifier | Repos |
| ---- | -------- | ---------- | ----- |

Fields (normalized): `name` (raw: `source`), `provider`, `identifier`, `repos_count` (computed from repository list).

### Repositories

Chart: doughnut — language distribution (group by `language`, count repos). **Cap at top 12 languages**; bucket the tail under "other" if needed. Treat missing `language` as `"unknown"`.

No table by default — repo lists get too long. Mention that `atx ct repository list` shows the full table.

Fields (raw → normalized): `slug`, `language`, `default_branch` → `defaultBranch`, `source`.

### Analyses

**Drop analyses with `status === "null"` (literal string) before charting or counting.** These are integ-test artifacts and would dominate the chart.

Chart: stacked bar by `analysis_type`, segments = status (`complete`, `running`, `failed`, `cancelled`, `pending`).

**Tooltip configuration is mandatory:** stacked bars in this chart can have segments that are pixel-thin (e.g., `agentic-readiness` with 3 entries next to `tech-debt` with 7,000). Default Chart.js hover requires the cursor to land inside the segment, which is unusable at that scale. Apply:

```js
options: {
  interaction: { mode: 'index', intersect: false },
  plugins: {
    tooltip: {
      mode: 'index',
      intersect: false,
      filter: (item) => item.parsed.y > 0,           // hide zero-count rows
      itemSort: (a, b) => b.parsed.y - a.parsed.y,    // largest first
    },
  },
  scales: { x: { stacked: true }, y: { stacked: true, beginAtZero: true } },
}
```

Hovering anywhere over a column then surfaces every non-zero segment, sorted by count.

Drilldown table — most recent 10 by `startedAt` desc:

| ID (short) | Type | Status | Repos | Findings | Duration |
| ---------- | ---- | ------ | ----- | -------- | -------- |

- Short ID: first 8 chars of `id`.
- Findings count: looked up from the precomputed `findingsByAnalysisId` map (NOT a field on the analysis row).
- Duration: `completedAt - startedAt` formatted (e.g. "2m 14s"). Blank if still running.
- For `failed` rows, render `failureReason` as a tooltip or expandable row.

Fields (raw → normalized): `id`, `analysis_type` → `analysisType`, `status`, `repos`, `started_at` → `startedAt`, `completed_at` → `completedAt`, `failure_reason` → `failureReason`. `findingsCount` is computed via the join described in Normalization.

### Findings

Two charts side-by-side:

1. Bar — severity counts. Use `status === 'open'` only. **Only include severity buckets that have at least one finding** — don't render zero-count columns. Iterate `['high','medium','low']` in that order, filter to non-zero, then plot.
2. Doughnut — analysis-type split (`rapid-techdebt-analysis` (raw `tech-debt-quick`), `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `graviton-readiness`, `custom`, `manual`). Same rule: only include types with at least one finding.

**Severity enum is `high | medium | low`. There is no `critical`.**

Two drilldown tables:

**Top risks** — group open findings by `title`, sort by repo count desc, take top 10:

| Title | Severity | Repos affected | Auto-fix? |
| ----- | -------- | -------------- | --------- |

Auto-fix? = whether any finding in the group has a non-null `fix` (a `security-agent` fix counts, though it has no `transformName`).

**Top auto-fix transforms** — group findings whose `fix.transformName` is set, by transform name:

| Transform | Findings | Repos | Auto Remediable |
| --------- | -------- | ----- | --------------- |

Built-in? = whether the transform name starts with `AWS/`. Customer-namespace transforms (anything else) render as ❌.

Fields: `findingId`, `repositoryId`, `severity`, `status`, `analysisType`, `category`, `title`, `fileRefs`, `fix.transformName`.

### Remediations

**Statuses are lowercase** — top level `pending`, `running`, `completed` (older records may say `complete`), `partial`, `failed`, `cancelled`; per repo see the shape above — never pattern-match against uppercase.

#### Trends chart (cumulative line)

Replace any "by aggregate status" bar with a **cumulative line chart over time**. Three series:

1. **Total created** — every remediation, keyed by `startedAt` date.
2. **Succeeded with PR** — remediations whose top-level `status` is in `{complete, completed, partial}` AND at least one repo has a non-null `executionRefs.prUrl`. Keyed by `completedAt` date (fall back to `startedAt` if missing). This is the strict definition of success — a transform can be marked `completed` without producing a PR (e.g., target version already met, or PR-publish step failed after a clean run). `partial` counts because it means some repositories finished and others never started, so its finished repositories can carry pull requests. Only "with PR" represents real code in flight, so it's the only success line worth charting.
3. **Failed** — remediations with top-level `status === "failed"`. Keyed by `completedAt` date (fall back to `startedAt`).

Bucket by ISO date (`startedAt.slice(0, 10)`), accumulate day by day, sort labels ascending.

```js
const SUCCESS = new Set(['complete', 'completed', 'partial']);
const hasPR = r => (r.repoStatuses || []).some(rs => rs.executionRefs?.prUrl);
// per-day buckets: { created, succeededWithPR, failed }
// then cumulative running totals across sorted days
```

Chart configuration:

- `type: 'line'`, three datasets in this order: Total created (blue, filled area), Succeeded with PR (green), Failed (red).
- `interaction: { mode: 'index', intersect: false }` and matching tooltip mode so a single hover surfaces all three series for that day.
- Y-axis: `beginAtZero: true`, ticks formatted with `Number.toLocaleString()`.
- X-axis: ISO date strings, `maxRotation: 0`, `autoSkip: true`.
- Legend at bottom.

Below the chart, render a one-line summary: date range, succeeded-with-PR count and rate, failed count.

#### Recent remediations with PRs

Cap at **15 most recent** (by `startedAt` desc) where at least one repo has a PR URL. Note the total remediation count below.

Drilldown — one card per remediation:

```
<Name>  ·  <transformName>  ·  <aggregate status>
N repos: X succeeded · Y failed · Z in progress

PRs:
  • <repo-slug> → <prUrl>
  • <repo-slug> → <prUrl>
  ...
Failures:
  • <repo-slug>: <error>
```

Per-repo buckets: succeeded = `pr_open`, `diff_ready`, `no_changes`, `already_applied`, `pr_exists`, `skipped`; failed = `failed`, `blocked`; in progress = `pending`, `running`; `cancelled` is its own count.

PR URLs come from `repoStatuses[<repoSlug>].executionRefs.prUrl` (raw `execution_artifacts.transform_pr_url`, or `pull_request_link` for security runs). Render as `<a href="...">` so they're clickable.

Fields: `id`, `name`, `transformName`, `status` (aggregate), `repos`, `repoStatuses` (per-repo: `status`, `executionRefs.prUrl`, `error`, `startedAt`, `completedAt`), `findingIds`.

## Tone

Data-driven. The HTML is the deliverable. After Step 3, your reply is ONLY:

1. The output path.
2. A 1–2 sentence summary, sourced from the subagent's `summary` field (e.g. "1 analysis failed", "3 PRs ready for review").

**Never relay subagent iteration state to the user.** No retry counts, no "I fixed an issue with X," no narration of intermediate scripts or errors. The visible surface across the whole run is: the Step 1 API calls, the Step 3 `open` command, and these one or two sentences. Nothing in between.

If the subagent returned `{"error": ...}`, surface that one sentence — don't try to redo the work inline (that would re-leak every retry).
