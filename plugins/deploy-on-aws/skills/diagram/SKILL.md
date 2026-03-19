---
name: diagram
description: "Generate architecture diagrams as code using the Python diagrams DSL. Triggers on phrases like: architecture diagram, system design diagram, draw architecture, generate diagram, infrastructure diagram, AWS diagram, Kubernetes diagram, network diagram, visualize architecture."
---

# Architecture Diagram Generation

Generate architecture diagrams using the Python [diagrams](https://diagrams.mingrammer.com/) package. Write a Python script, run it, and produce an image (PNG by default).

Supports AWS (26 service categories), Kubernetes, on-premises, GCP, SaaS, and custom icons via the `diagrams` DSL.

## When to Load Reference Files

Load the appropriate reference file based on what the user is building:

- **Any diagram** -> ALWAYS load [references/dsl-syntax.md](references/dsl-syntax.md) first for DSL syntax, constructor options, connections, clusters, and edge styles
- **AWS architecture**, **cloud infrastructure**, or **AWS services** -> load [references/aws-services.md](references/aws-services.md) for AWS import paths, common icons, and 5 AWS examples
- **Kubernetes**, **on-premises**, **SaaS**, **flowcharts**, **process flows**, **custom icons**, or **non-AWS diagrams** -> load [references/non-aws-providers.md](references/non-aws-providers.md) for K8s, on-prem, flowchart, and custom icon examples

## Workflow

1. Load [references/dsl-syntax.md](references/dsl-syntax.md)
2. Load the relevant provider reference (AWS or non-AWS)
3. Write a Python script using the `diagrams` DSL
4. Run: `mkdir -p generated-diagrams && python3 diagram.py`
5. Verify the output file was created in `generated-diagrams/`

## Critical Rules

- ALWAYS set `show=False` in `Diagram()` constructor
- ALWAYS set `filename="generated-diagrams/<name>"` (no `.png` extension)
- ALWAYS use explicit imports: `from diagrams.aws.compute import EC2`
- ALWAYS run `mkdir -p generated-diagrams` before executing
- Add `generated-diagrams/` to `.gitignore` to avoid committing output artifacts
- Use `Cluster()` to group related resources (VPCs, subnets, namespaces)
- Use `Edge(label="HTTPS", color="darkgreen", style="dashed")` for labeled or styled connections
- **SVG sanitization**: When using `outformat="svg"`, sanitize all diagram titles, node labels, and edge labels — strip HTML tags and special characters (`<`, `>`, `&`, `"`, `'`) before passing them to the `diagrams` DSL. Unsanitized input rendered as SVG can become an XSS vector if served on a web page.

## Defaults

Default output format: PNG
Skill convention layout direction: TB (top-to-bottom) — the library default is LR, but this skill uses TB for more readable top-down diagrams

Override syntax:

- "left to right" -> Use `direction="LR"`
- "SVG format" -> Use `outformat="svg"`

When not specified, ALWAYS use `direction="TB"` and `outformat="png"`.

## Prerequisites

Requires two dependencies installed locally:

1. **GraphViz** (system package providing `dot`):
   - macOS: `brew install graphviz`
   - Ubuntu/Debian: `sudo apt-get install graphviz`
   - Amazon Linux/RHEL: `sudo yum install graphviz`
2. **Python diagrams package**: `python3 -m pip install diagrams`

**Verify:** `dot -V && python3 -c "import diagrams; print('OK')"`

### Missing Dependencies

If `dot` command not found:

- Inform user: "GraphViz is not installed. Required for diagram rendering."
- Show install command for detected OS
- DO NOT attempt to generate diagrams without GraphViz

If `import diagrams` fails:

- Inform user: "Python diagrams package not installed."
- Show: `python3 -m pip install diagrams`
- DO NOT proceed without the package

## References

- [DSL syntax and patterns](references/dsl-syntax.md)
- [AWS services and examples](references/aws-services.md)
- [Non-AWS providers and examples](references/non-aws-providers.md)
- [diagrams documentation](https://diagrams.mingrammer.com/)
