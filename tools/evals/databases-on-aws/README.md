# Evaluation Suite for databases-on-aws

Automated evaluation harnesses for various skills, created using the skill-creator.
Currently exists for the DSQL skill.

> **Note:** Evals live under `tools/evals/`, not inside the plugin directory, so they aren't
> shipped to users when the plugin is installed.

## Tier 1: Triggering Evals

Tests whether the skill description triggers correctly for relevant vs irrelevant prompts.

**Requires:** [skill-creator](https://github.com/anthropics/skills) plugin installed.

```bash
# Install the skill-creator via plugin
/plugin install example-skills@anthropic-agent-skills

# From repo root
PYTHONPATH="<skill-creator-path>:$PYTHONPATH" python -m scripts.run_eval \
  --eval-set tools/evals/databases-on-aws/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --num-workers 5 \
  --runs-per-query 3 \
  --verbose
```

**What it checks:**

- 10 should-trigger prompts (Aurora DSQL, distributed SQL, DSQL migrations, etc.)
- 10 should-not-trigger prompts (DynamoDB, Aurora PostgreSQL, Redshift, generic SQL, etc.)

## Tier 2: Functional Evals

Tests simple skill correctness: MCP delegation, DSQL-specific guidance, and reference file routing.

```bash
python tools/evals/databases-on-aws/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-eval-results \
  --verbose
```

**What it checks** (5 eval prompts, 20 assertions total):

| Eval                   | Focus                 | Key assertions                                                             |
| ---------------------- | --------------------- | -------------------------------------------------------------------------- |
| 1. Transaction limits  | MCP delegation        | Calls `awsknowledge`, cites 3,000 row limit, recommends batching           |
| 2. Multi-tenant schema | Correctness           | Uses `tenant_id`, `CREATE INDEX ASYNC`, no foreign keys, separate DDL txns |
| 3. Index limits        | MCP delegation        | Calls `awsknowledge`, cites 24 index limit, suggests alternatives          |
| 4. Python connection   | Language routing      | Recommends DSQL Python Connector, IAM auth, 15-min token expiry, SSL       |
| 5. Column type change  | DDL migration routing | Table Recreation Pattern, DROP TABLE warning, batching, user confirmation  |

## Description Optimization

To optimize the skill description for better triggering:

```bash
PYTHONPATH="<skill-creator-path>:$PYTHONPATH" python -m scripts.run_loop \
  --eval-set tools/evals/databases-on-aws/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --model <model-id> \
  --max-iterations 5 \
  --verbose
```
