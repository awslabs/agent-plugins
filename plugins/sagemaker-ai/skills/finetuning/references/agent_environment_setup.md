# Agent Environment Setup (MTRL only)

MTRL trains a model by letting it interact with an external agent over many
turns. Before the trainer can run, the user must point it at an **agent
environment**: either a Bedrock AgentCore runtime, or a Lambda function that
forwards rollouts to a customer-hosted agent.

This reference is loaded by `SKILL.md` Section 1A only when the technique is
MTRL. SFT/DPO/RLVR runs skip this entire flow (Property 14 invariant).

The end goal is a single value, **`AGENT_ENV`**, that gets dropped into Cell 3
of `mtrl_example.md`. It is one of:

- A Bedrock AgentCore ARN (e.g.
  `arn:aws:bedrock-agentcore:us-west-2:123456789012:runtime/my-runtime`)
- A bare AgentCore runtime ID (e.g. `myRuntime-aBcDeFgHiJ`)
- A Lambda function ARN (e.g.
  `arn:aws:lambda:us-east-1:123456789012:function:my-fn`)
- A `CustomAgentLambda` Python object (returned by
  `CustomAgentLambda.create(...)`)

All four shapes are accepted verbatim by `MultiTurnRLTrainer`, so the agent
does **not** normalize the value — it captures what the user provides and
inserts it into the notebook.

Validation of the three string shapes is delegated to
`scripts/agent_env_validator.py::validate_agent_env(value) -> (bool, str)`.
The `CustomAgentLambda` object case bypasses string validation because the
SDK constructor produces it directly.

---

## Workflow

### Step 1 — Ask which agent environment to use

Ask the user:

> Which agent environment do you want to use for MTRL training?
>
> - **A) Bedrock AgentCore** — AWS managed agent runtime
> - **B) Custom Lambda agent** — Lambda forwarder bridging to your own
>   agent platform (EKS, Fargate, an HTTP service, an SQS-backed worker, …)

Branch on the user's answer.

---

### Step 2 — Branch A: Bedrock AgentCore

Ask the user:

> Do you already have a Bedrock AgentCore runtime, or would you like me to help you set one up or discover existing ones in your account?
>
> - **1) I already have a runtime ARN or ID** — paste it below
> - **2) Help me discover existing runtimes** — I'll look up what's in your account
> - **3) Help me create a new runtime** — I'll show you how to set one up

Branch on the user's answer.

#### 2a) User already has a runtime

1. Ask the user to paste the value.
2. Validate with `scripts/agent_env_validator.py::validate_agent_env`.
   - On success (`agentcore_arn` or `runtime_id`) → set `AGENT_ENV = value`
     and proceed to Step 4.
   - On failure → quote the user's value back to them, surface the supported
     formats (the validator's failure message lists them), and re-ask.

#### 2b) Discover existing runtimes

1. Use the AWS MCP tool `aws___call_aws` with service `bedrock-agentcore-control` and action `list-agent-runtimes` to discover existing runtimes in the user's account.
2. If runtimes exist, present them to the user and ask them to pick one.
3. If the list is empty, inform the user and offer to help create a new one (fall through to 2c).
4. Once the user picks a runtime, validate with `scripts/agent_env_validator.py::validate_agent_env`.
   - On success → set `AGENT_ENV = value` and proceed to Step 4.
   - On failure → re-ask.

#### 2c) Create a new runtime

1. Show the CLI snippet for creating a new runtime:

   ```bash
   aws bedrock-agentcore-control create-agent-runtime \
     --agent-runtime-name my-mtrl-agent \
     --description "Agent for MTRL training" \
     --agent-runtime-artifact '{"containerConfiguration": {"containerUri": "<ECR_IMAGE_URI>"}}'
   ```

2. Pause until the user provides a runtime ARN or ID.
3. Validate with `scripts/agent_env_validator.py::validate_agent_env`.
   - On success → set `AGENT_ENV = value` and proceed to Step 4.
   - On failure → re-ask.

---

### Step 3 — Branch B: Custom Lambda agent

Ask the user:

> Do you already have a Lambda function for your agent forwarder?

#### 3a) Yes — user has a Lambda

1. Ask the user to paste the Lambda ARN.
2. Run `validate_agent_env(value)` from `scripts/agent_env_validator.py`.
   - On success (`lambda_arn`) → set `AGENT_ENV = value` and proceed to
     Step 4.
   - On failure → quote the user's value back, surface the supported
     formats, and re-ask.

#### 3b) No — user wants a new Lambda from the template

1. Copy `templates/mtrl_lambda_forwarder_template.py` into the project
   directory at `<project-dir>/scripts/agent_lambda_forwarder.py`.
2. Tell the user to customize `_call_agent` (request shape) and
   `_handle_agent_error` (error mapping) in the file before running.
3. Add a notebook cell that creates the Lambda from that source via
   `CustomAgentLambda.create(...)`:

   ```python
   from sagemaker.train.custom_agent_lambda import CustomAgentLambda

   adapter = CustomAgentLambda.create(
       source="../scripts/agent_lambda_forwarder.py",
       function_name="rft-agent-forwarder",
       timeout=900,
       memory_size=1024,
       # role="arn:aws:iam::123456789012:role/LambdaForwarderRole",
       # environment={"AGENT_ENDPOINT": "https://your-agent-loadbalancer-url"},
   )
   AGENT_ENV = adapter
   print(f"Agent: {adapter}")
   ```

4. The resulting `CustomAgentLambda` object is captured directly as
   `AGENT_ENV`. No string validation is needed — the SDK constructor
   produces a value the trainer accepts verbatim.

---

### Step 4 — Validate the resolved value

If the value is a string, run `validate_agent_env(value)` one final time. On
invalid input, surface the supported formats from the validator's failure
message and return to the matching sub-step (2a / 2b / 3a) to collect a new
value.

If the value is a `CustomAgentLambda` object (Step 3b), skip string
validation — the SDK constructor's success implies validity.

---

### Step 5 — Store `AGENT_ENV` for the trainer cell

Set `AGENT_ENV` to the resolved value and keep it for use in **Cell 3** of
`mtrl_example.md`. The agent inserts the value verbatim into one of the
three Cell 3 shapes (3a AgentCore, 3b existing Lambda, 3c new Lambda from
template) and removes the other two before writing the notebook.

After this section completes, return to `SKILL.md` Section 1.2 (template
selection) with `AGENT_ENV` resolved.
