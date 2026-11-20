# Results Synthesis

Generate a single summary file after bulk transformations complete.

## Output

Write one file: `~/.aws/atx/custom/atx-agent-session/transformation-summaries/transformation-summary-$SESSION_TS.md`

```bash
mkdir -p ~/.aws/atx/custom/atx-agent-session/transformation-summaries
```

**Important:** Do NOT use heredoc (`cat << EOF`) to write this file — heredoc
blocks can hang in shell environments. Use a command (ex. `printf '%s'`) to write the content.

## Template

```markdown
# AWS Transform Summary

> Completed: <timestamp>
> Repositories: <total> | Succeeded: <count> | Failed: <count>

## Results

| Project | Transformation        | Status           | Notes        |
| ------- | --------------------- | ---------------- | ------------ |
| <name>  | <transformation-name> | Succeeded/Failed | <brief note> |

## Failed Transformations

### <project-name>

- **Transformation definition**: <td-name>
- **Error**: <one-line error summary>
- **Suggested Fix**: <recommendation>

## Next Steps

1. Review changes in each transformed repo
2. Run tests and deploy
```

## Presentation

Tell the user:

```
Results: <succeeded>/<total> succeeded, <failed> failed
Summary: ~/.aws/atx/custom/atx-agent-session/transformation-summaries/transformation-summary-$SESSION_TS.md
```

For remote mode executions, also include each repo's result from
`atx ct remote status` (pull/merge request URL or S3 output path) and the
CloudWatch dashboard link built from `dashboardName` in `atx ct remote detect --mode <batch|ec2> --stack-name <stack> --json`.
