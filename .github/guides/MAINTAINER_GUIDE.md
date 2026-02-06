# Maintainer Guide

## Pull Request Reviews

- Review PRs for code quality, security, and adherence to project standards
- Ensure CI checks pass before merging
- Use squash merges to keep history clean

## Release Management

### Creating a Release

1. Ensure all intended changes are merged to `main`
2. Update version numbers and changelog
3. Create a GitHub release with semantic versioning (e.g., `v1.2.0`)
4. Tag the release with release notes summarizing changes

## Issue Triage

- Label new issues appropriately (`bug`, `enhancement`, `question`, etc.)
- Close duplicates with a reference to the original issue
- Add `help wanted` or `good first issue` labels to encourage contributions

## Branch Protection

- Maintain branch protection rules on `main`
- Require PR reviews and passing CI before merge
- Do not bypass protections except in emergencies
