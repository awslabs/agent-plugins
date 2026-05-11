# Exclusion Patterns

Standard patterns for files and directories to skip during codebase analysis. These are noise — they add no documentation value and waste analysis time.

## Excluded Directories

Skip these directory names at any depth:

| Directory        | Reason                            |
| ---------------- | --------------------------------- |
| `.git`           | Version control internals         |
| `node_modules`   | npm/yarn dependencies             |
| `vendor`         | Go/PHP vendored dependencies      |
| `__pycache__`    | Python bytecode cache             |
| `.venv` / `venv` | Python virtual environments       |
| `dist`           | Build output                      |
| `build`          | Build output                      |
| `out`            | Build output                      |
| `.next`          | Next.js build cache               |
| `.nuxt`          | Nuxt build cache                  |
| `target`         | Rust/Java/Scala build output      |
| `obj`            | .NET intermediate build output    |
| `.idea`          | JetBrains IDE config              |
| `.vs`            | Visual Studio config              |
| `.vscode`        | VS Code config (usually)          |
| `coverage`       | Test coverage reports             |
| `.terraform`     | Terraform provider cache          |
| `cdk.out`        | CDK synthesized output            |
| `.serverless`    | Serverless Framework build output |
| `.aws-sam`       | SAM build output                  |
| `logs`           | Application log files             |
| `tmp` / `temp`   | Temporary files                   |
| `.cache`         | Various tool caches               |

## Excluded Files

Skip these file patterns:

| Pattern                                                     | Reason                    |
| ----------------------------------------------------------- | ------------------------- |
| `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`          | Dependency lock files     |
| `poetry.lock`, `Pipfile.lock`, `Cargo.lock`, `Gemfile.lock` | Dependency lock files     |
| `go.sum`                                                    | Go checksum database      |
| `*.min.js`, `*.min.css`                                     | Minified assets           |
| `*.map`                                                     | Source maps               |
| `*.pyc`, `*.pyo`                                            | Python bytecode           |
| `*.exe`, `*.dll`, `*.so`, `*.dylib`                         | Compiled binaries         |
| `*.wasm`                                                    | WebAssembly binaries      |
| `*.png`, `*.jpg`, `*.gif`, `*.ico`, `*.svg`                 | Image assets              |
| `*.woff`, `*.woff2`, `*.ttf`, `*.eot`                       | Font files                |
| `*.zip`, `*.tar.gz`, `*.jar`, `*.war`                       | Archives                  |
| `*.pb`                                                      | Compiled protocol buffers |
| `.DS_Store`, `Thumbs.db`                                    | OS metadata               |
| `.env` (actual, not `.env.example`)                         | Secrets — do not read     |

## Files to Always Include

Even if they match no code pattern, these files carry high documentation value:

- `README.md` / `README.*`
- `CONTRIBUTING.md`
- `CHANGELOG.md`
- `Dockerfile`, `docker-compose.yml`
- `.env.example`, `.env.template`
- `Makefile`, `Justfile`
- CI/CD configs (`.github/workflows/*.yml`, `buildspec.yml`, `.gitlab-ci.yml`)
- IaC files (`cdk.json`, `*.tf`, `template.yaml`, `serverless.yml`)
- Package manifests (`package.json`, `go.mod`, `Cargo.toml`, `pom.xml`, `requirements.txt`, `pyproject.toml`)

## Applying Exclusions

1. Build the file tree first (full recursive listing)
2. Remove all paths matching excluded directories and files
3. The filtered tree becomes the working set for all subsequent analysis
4. If a `.gitignore` exists, respect its patterns as additional exclusions
