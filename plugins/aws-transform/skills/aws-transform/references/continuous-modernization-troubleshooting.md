---
name: troubleshooting
description: Troubleshooting guide for issues that occur during setup and execution of AWS Transform continuous modernization.
---

# Common Errors

## `atx ct` reports `unknown command 'ct'`

This means the shell found and ran an executable named `atx`, but the selected executable does not provide the continuous-modernization commands. Treat it as local command resolution, not an AWS credential or region problem.

Inspect what the shell selected and which alternatives are available:

```bash
command -v atx
type -a atx
atx --version
```

If multiple candidates are listed, test paths returned by `type -a atx` directly with `<discovered-path> ct --version`. Do not assume a fixed installation path, reinstall immediately, or modify PATH automatically. Use the evidence to explain which executable won resolution and which candidate, if any, provides `ct`; then guide the user through the smallest appropriate correction for their shell. After a PATH change, start a new shell or clear its command cache (`hash -r` for Bash, `rehash` for Zsh), then retry plain `atx ct --version`. Install the AWS Transform CLI only if no discovered candidate provides `ct`.

## Error writing files to the `~/.atxct` folder

If attempting to read or write files to the user's `~/.atxct` folder fails due to an error similar to "File access is restricted to the open workspace folders", write a script or find another way to read/write to this directory -- there is no substitute/alternative location for files in `~/.atxct` so be sure to find a way to do it.
