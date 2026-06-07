---
name: getting-started
description: SDK installation, setup, and first-run guide for Nova Forge SDK. Use when user is new to Nova Forge or needs help installing/configuring the SDK.
triggers:
  keywords: [install, setup, getting started, new, first time, pip, configure, prerequisites, iam, permissions, quickstart, begin, start]
  task_types: [onboarding, getting-started, installation, setup]
  error_patterns: ["ModuleNotFoundError: No module named 'amzn_nova'", "pip install", "permission denied"]
  methods: []
prerequisites: []
last_verified: 2026-04-13
sdk_version: ">=1.0.0"
---

# Nova Forge SDK Installation Guide

## Steps

### 1. Install the SDK

```bash
pip install amzn-nova-forge
```

- Requires **Python 3.12+**
- Automatically installs the SageMaker Python SDK (v3.x) as a dependency

### 2. Setup IAM Roles and Permissions

The SDK requires IAM permissions and an execution role. See `docs/sdk/reference/iam_setup.md` for the complete IAM policy with per-statement explanations.

Key setup areas:

- **IAM Roles/Policies** — Permissions for the role you use to call the SDK (see `docs/sdk/reference/iam_setup.md`)
- **Execution Role** — The role SageMaker assumes to run jobs on your behalf (including trust policy and RFT-specific permissions)
- **Instances** — Ensure sufficient [Service Quotas](https://docs.aws.amazon.com/servicequotas/latest/userguide/request-quota-increase.html) for your instance types

### 3. Install HyperPod CLI (Required for SMHP Only)

> **Skip this step** if you're only using `SMTJRuntimeManager`, `SMTJServerlessRuntimeManager`, or `BedrockRuntimeManager`. The HyperPod CLI is **only required** when using `SMHPRuntimeManager`.

There are **two installation paths** depending on whether you are a Nova Forge customer:

#### Option A: Forge Customers (Recommended for Nova Forge SDK users)

Forge customers must install a specialized version of the HyperPod CLI with Forge feature support. **Do not** install the standard HyperPod CLI from PyPI — it does not include Forge-specific features.

##### Step 1: Download the Forge-enabled HyperPod CLI from S3

```bash
aws s3 cp s3://nova-forge-c7363-206080352451-us-east-1/v1/ ./ --recursive
```

##### Step 2: Clone the NeMo Framework Launcher (required dependency)

```bash
mkdir -p src/hyperpod_cli/sagemaker_hyperpod_recipes/launcher/nemo
git clone https://github.com/NVIDIA/NeMo-Framework-Launcher.git \
  src/hyperpod_cli/sagemaker_hyperpod_recipes/launcher/nemo/nemo_framework_launcher --recursive
```

##### Step 3: Install Helm (if not already installed)

```bash
# Check if helm is installed
helm --help

# If not installed, run:
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm -f ./get_helm.sh
```

##### Step 4: Install the HyperPod CLI package

```bash
cd <cloned_directory>
pip install .
```

##### Step 5: Verify installation

```bash
hyperpod --help
```

#### Option B: Non-Forge Customers (Standard HyperPod CLI)

If you are using HyperPod **without** Forge-specific features (e.g., running non-Forge workloads on an existing HyperPod cluster), install the standard HyperPod CLI from the public repository:

##### Step 1: Clone the HyperPod CLI release branch

```bash
git clone -b release_v2 https://github.com/aws/sagemaker-hyperpod-cli.git
```

##### Step 2: Install Helm (if not already installed)

```bash
# Check if helm is installed
helm --help

# If not installed, run:
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm -f ./get_helm.sh
```

##### Step 3: Install the HyperPod CLI package

```bash
cd sagemaker-hyperpod-cli
pip install .
```

##### Step 4: Verify installation

```bash
hyperpod --help
```

> **Reference:** See the [HyperPod CLI README](https://github.com/aws/sagemaker-hyperpod-cli/tree/release_v2?tab=readme-ov-file#installation) for the latest standard installation instructions.

#### Grant EKS Cluster Access (Both Options)

After installing the CLI (either Option A or B), grant your execution role access to the HyperPod cluster's EKS cluster. See the "EKS Cluster Access (HyperPod Only)" section in `iam-setup.md` for the commands.

### 4. Verify Installation

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMTJRuntimeManager

print("Nova Forge SDK installed successfully!")
```

---

_References the [Nova Forge SDK README](https://github.com/aws/nova-forge-sdk/blob/main/README.md) for detailed setup. If you encounter discrepancies, check the SDK repo for the latest instructions._
