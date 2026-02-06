# Development Guide

## Security Scanning

### Gitleaks - Secret Detection

This repository uses [gitleaks](https://github.com/gitleaks/gitleaks) to detect secrets and sensitive information in the codebase.

#### Handling False Positives

If gitleaks reports a false positive (e.g., example API keys in documentation, test fixtures), you can add it to the baseline file to suppress future warnings.

1. Run gitleaks locally to generate the baseline:

   ```bash
   gitleaks git --config=.gitleaks.toml --report-format=json . > .gitleaks-baseline.json
   ```

2. Review the generated file to ensure only legitimate false positives are included.

3. Commit the updated `.gitleaks-baseline.json` file.

#### Configuration

Custom rules and allowlists are defined in `.gitleaks.toml`. Common customizations include:

- Excluding paths (vendor directories, generated files)
- Allowlisting specific patterns or files
- Adding custom secret detection rules
