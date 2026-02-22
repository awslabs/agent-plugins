# Orchestration and Workflows Guide

## Choosing an Orchestration Approach

| Approach                     | Best For                                                                                                                                                                                      | Runtime                        |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| **Lambda durable functions** | Multi-step business logic and AI/ML pipelines expressed as sequential code, with checkpointing and human-in-the-loop — see the [durable-functions skill](../../aws-lambda-durable-functions/) | Python 3.13+, Node.js 22+      |
| **Step Functions Standard**  | Cross-service orchestration, long-running auditable workflows, non-idempotent operations                                                                                                      | Any (JSON/YAML ASL definition) |
| **Step Functions Express**   | High-volume, short-lived event processing, idempotent operations (100k+ exec/sec)                                                                                                             | Any                            |
| **EventBridge + Lambda**     | Loosely coupled event-driven choreography with no central coordinator — see [event-driven-architecture.md](event-driven-architecture.md)                                                      | Any                            |

**Key distinction:** Lambda durable functions keep the workflow logic inside your Lambda code using standard language constructs. Step Functions define the workflow as a separate graph-based state machine that calls Lambda (and 9,000+ API actions across 200+ AWS services). Use durable functions when the workflow is tightly coupled to business logic written in Python or Node.js. Use Step Functions when you need visual design, cross-service coordination, or native service integrations without Lambda as an intermediary.

---

## Lambda durable functions

Lambda Durable Functions enable resilient multi-step applications that execute for up to one year, with automatic checkpointing, replay, and suspension — without consuming compute charges during wait periods.

### Durable functions vs Step Functions

|                          | Durable functions                                        | Step Functions                                                        |
| ------------------------ | -------------------------------------------------------- | --------------------------------------------------------------------- |
| **Programming model**    | Sequential code with `context.step()`                    | Graph-based state machine (ASL JSON/YAML)                             |
| **Runtimes**             | Python 3.13+, Node.js 22+                                | Any (runtime-agnostic)                                                |
| **Workflow definition**  | Inside your Lambda function code                         | Separate `.asl.json` file                                             |
| **AWS integrations**     | Via SDK calls inside steps                               | 9,000+ native API actions (no Lambda needed)                          |
| **Execution visibility** | CloudWatch Logs + `get-durable-execution-history`        | Step Functions console, execution history API                         |
| **Max duration**         | Up to 1 year                                             | Standard: 1 year, Express: 5 minutes                                  |
| **Execution semantics**  | At-least-once with checkpointing                         | Standard: exactly-once, Express: at-least-once                        |
| **Billing**              | Active compute time only (free during waits)             | Per state transition (Standard) or per execution + duration (Express) |
| **Best for**             | Business logic workflows, AI pipelines, code-first teams | Cross-service orchestration, visual workflows, polyglot teams         |

**For comprehensive durable functions guidance** — including the SDK, programming model, replay rules, testing, error handling, and deployment patterns — see the [durable-functions skill](../../aws-lambda-durable-functions/) in this plugin.

---

## AWS Step Functions

For comprehensive Step Functions guidance — Standard vs Express workflows, ASL definitions, JSONata, SDK integrations, Distributed Map, testing, and best practices — see [step-functions.md](step-functions.md).
