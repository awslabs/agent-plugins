---
name: directory-management
description: Manages project directory setup and artifact organization. Use when starting a new project, resuming an existing one, or when a PLAN.md needs to be associated with a project directory. Creates the project folder structure (specs/, scripts/, notebooks/) and resolves project naming.
metadata:
  version: "1.0.0"
---

# Directory Management

## Project Setup

Before any work begins, resolve the project name:

1. If the project name is already known from conversation context, use it.
2. Otherwise, scan for existing `*/PLAN.md` files in the current directory. If found, ask the user if they are resuming an existing project and load that `PLAN.md` into context.
3. If no existing projects are found, recommend a ≤64-char lowercase slug based on what you know from the conversation (only `[a-z0-9-]`), or ask directly if there isn't enough context. Present the recommended name and wait for user confirmation.

Once project name is resolved:

1. Create and/or use the `<experiment-name>/` directory using the confirmed name for storing all the artifacts

## Directory Structure

When working with the agent, all generated files are organized under an project directory.

```
<project-name>/
├── specs/  
│   ├── PLAN.md             # Your customization plan
├── scripts/                # Generated Python scripts
│   ├── <project-name>_transform_fn.py
└── notebooks/              # Generated Jupyter notebooks
    ├── <project-name>.ipynb
```
