# Administrative Guide

## Updating Pre-commit Hooks

Pre-commit hooks should be updated periodically to get the latest versions and security fixes.

### Update all hooks

```bash
pre-commit autoupdate
```

### Update a specific hook

```bash
pre-commit autoupdate --repo https://github.com/pre-commit/pre-commit-hooks
```

### After updating

1. Review the changes to `.pre-commit-config.yaml`
2. Run hooks against all files to verify compatibility:

   ```bash
   pre-commit run --all-files
   ```

3. Commit the updated configuration

## Gitleaks Baseline Management

To update the gitleaks baseline with current findings:

```bash
gitleaks detect --baseline-path .gitleaks-baseline.json --report-path .gitleaks-baseline.json
```

Note: If an issue is already ignored via inline comments (`# gitleaks:allow`) or `.gitleaksignore`, the baseline won't capture it. The baseline is useful for grandfathering in existing findings without requiring inline comments or ignore file entries.
