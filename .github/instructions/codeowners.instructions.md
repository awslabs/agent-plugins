---
applyTo: ".github/CODEOWNERS"
---

# CODEOWNERS file rules

Please verify this checklist to keep the `.github/CODEOWNERS` file following all five of these rules:

1. [ ] ONLY teams are used (no users)
2. [ ] Teams MUST be vertically aligned across all lines with spaces (no tabs)
3. [ ] Each section, "## section", MUST be alphabetically sorted (keep file patterns in order)
4. [ ] Admins or maintainers must be first (if both separated by one space) - others follow with two spaces
5. [ ] The file MUST follow this regular expression `^.github/CODEOWNERS *@awslabs/agent-plugins-admins$`

EXAMPLE:

```.github/CODEOWNERS
README.md                  @awslabs/agent-plugins-admins @awslabs/agent-plugins-maintainers  @awslabs/otherteams

## Plugins (alphabetically listed)

plugins/a                  @awslabs/agent-plugins-maintainers  @awslabs/a-team
plugins/d                  @awslabs/agent-plugins-maintainers  @awslabs/a-d-group
plugins/z                  @awslabs/agent-plugins-maintainers  @awslabs/the-z-team

## File must end with CODEOWNERS file

.github/CODEOWNERS         @awslabs/agent-plugins-admins
```
