# AxdbAgentPluginsStaging

Private staging mirror for the complete `awslabs/agent-plugins` monorepo.

## Source of truth

AWS CodeCommit is writable. GitFarm is populated by one-way PicaPica reverse
replication. Do not push developer changes directly to GitFarm.

## Builds

`brazil-build release` verifies and packages the source without network access.
The required CRUX `APLCruxAnalyzer` runs the authoritative full validation:

```bash
mise install
mise run build
```

## Public promotion

Promotion to GitHub is always manual. Follow
`docs/MANUAL_GITHUB_PROMOTION.md`. Never push `Config`, `build-tools/`,
`STAGING.md`, or internal documentation to GitHub.
