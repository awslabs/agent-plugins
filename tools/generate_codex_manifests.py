#!/usr/bin/env python3
"""Generate Codex plugin manifests and a Codex marketplace from Claude manifests."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
CLAUDE_MARKETPLACE = ROOT / ".claude-plugin" / "marketplace.json"
CODEX_MARKETPLACE = ROOT / ".agents" / "plugins" / "marketplace.json"

AWS_AGENT_EMAIL = "aws-agent-plugins@amazon.com"
AWS_REPO_URL = "https://github.com/awslabs/agent-plugins"
AWS_PRIVACY_URL = "https://aws.amazon.com/privacy/"
AWS_TERMS_URL = "https://aws.amazon.com/service-terms/"
AWS_BRAND_COLOR = "#FF9900"
CATEGORY_LABELS = {
    "ai": "AI",
    "fullstack": "Full Stack",
}

INTERFACE_METADATA = {
    "amazon-location-service": {
        "displayName": "Amazon Location Service",
        "shortDescription": "Build maps, routing, geocoding, and places workflows on AWS.",
        "longDescription": "Guided AWS expertise for maps, routing, geocoding, and places features built with Amazon Location Service.",
        "defaultPrompt": [
            "Add Amazon Location Service to this app.",
            "Plan a geocoding and places search workflow.",
            "Review this map integration for AWS best practices.",
        ],
    },
    "aws-amplify": {
        "displayName": "AWS Amplify",
        "shortDescription": "Build and deploy Amplify Gen 2 applications with guided workflows.",
        "longDescription": "Amplify Gen 2 guidance for authentication, data, storage, functions, and deployment workflows.",
        "defaultPrompt": [
            "Plan an Amplify Gen 2 architecture for this app.",
            "Add Amplify auth and data to this project.",
            "Set up an Amplify deployment workflow.",
        ],
    },
    "aws-serverless": {
        "displayName": "AWS Serverless",
        "shortDescription": "Build Lambda, API Gateway, Step Functions, and SAM or CDK workflows.",
        "longDescription": "AWS serverless expertise for Lambda, API Gateway, durable functions, and deployment workflows with SAM or CDK.",
        "defaultPrompt": [
            "Add a Lambda-backed AWS feature to this app.",
            "Generate CDK for a serverless workflow.",
            "Review this repo for AWS serverless best practices.",
        ],
    },
    "databases-on-aws": {
        "displayName": "Databases on AWS",
        "shortDescription": "Design schemas, query data, and choose the right AWS database path.",
        "longDescription": "AWS database guidance for schema design, queries, migrations, and database selection, starting with Aurora DSQL workflows.",
        "defaultPrompt": [
            "Review this schema for Aurora DSQL fit.",
            "Plan a migration path to AWS databases.",
            "Help me use Aurora DSQL safely in this repo.",
        ],
    },
    "deploy-on-aws": {
        "displayName": "Deploy on AWS",
        "shortDescription": "Pick AWS services, estimate cost, and generate infrastructure.",
        "longDescription": "Deployment guidance that recommends AWS architectures, estimates costs, and generates infrastructure as code.",
        "defaultPrompt": [
            "Recommend an AWS architecture for this repo.",
            "Estimate monthly AWS cost before generating IaC.",
            "Generate CDK to deploy this app on AWS.",
        ],
    },
    "migration-to-aws": {
        "displayName": "Migration to AWS",
        "shortDescription": "Discover GCP workloads and plan a migration path to AWS.",
        "longDescription": "Migration guidance for discovering GCP infrastructure, comparing AWS services and pricing, and planning an execution path.",
        "defaultPrompt": [
            "Assess this GCP repo for migration to AWS.",
            "Compare AWS pricing for this workload.",
            "Draft a migration execution plan to AWS.",
        ],
    },
    "sagemaker-ai": {
        "displayName": "SageMaker AI",
        "shortDescription": "Build, tune, evaluate, and deploy AI workloads on SageMaker AI.",
        "longDescription": "Amazon SageMaker AI workflows for planning, fine-tuning, evaluation, deployment, and HyperPod operations.",
        "defaultPrompt": [
            "Plan a SageMaker AI workflow for this project.",
            "Help me fine-tune and deploy a model on AWS.",
            "Review this ML setup for SageMaker best practices.",
        ],
    },
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def codex_category(value: str) -> str:
    return CATEGORY_LABELS.get(value, value.replace("-", " ").title())


def require_manifest_value(
    plugin_manifest: dict[str, Any],
    plugin_name: str,
    field: str,
) -> Any:
    value = plugin_manifest.get(field)
    if value is None:
        raise ValueError(
            f"Missing required field '{field}' in Claude plugin manifest for "
            f"'{plugin_name}' at plugins/{plugin_name}/.claude-plugin/plugin.json. "
            "Add the missing field to the Claude manifest or update "
            "tools/generate_codex_manifests.py to provide an explicit fallback."
        )
    return value


def get_author_name(plugin_manifest: dict[str, Any], plugin_name: str) -> str:
    author = plugin_manifest.get("author")
    if not isinstance(author, dict) or not author.get("name"):
        raise ValueError(
            f"Missing required field 'author.name' in Claude plugin manifest for "
            f"'{plugin_name}' at plugins/{plugin_name}/.claude-plugin/plugin.json. "
            "Add author.name to the Claude manifest or update "
            "tools/generate_codex_manifests.py to provide an explicit fallback."
        )
    return author["name"]


def get_interface_metadata(plugin_name: str) -> dict[str, Any]:
    if plugin_name not in INTERFACE_METADATA:
        raise ValueError(
            "Missing interface metadata for plugin "
            f"'{plugin_name}'. This plugin appears in the Claude marketplace "
            "but does not have a corresponding INTERFACE_METADATA entry in "
            "tools/generate_codex_manifests.py. Add interface metadata for this "
            "plugin or derive the required interface fields from the existing "
            "manifest fields before continuing."
        )

    return INTERFACE_METADATA[plugin_name]


def build_codex_manifest(
    plugin_dir: Path,
    plugin_manifest: dict[str, Any],
    marketplace_entry: dict[str, Any],
) -> dict[str, Any]:
    plugin_name = require_manifest_value(plugin_manifest, "<unknown>", "name")
    interface = get_interface_metadata(plugin_name)
    author_name = get_author_name(plugin_manifest, plugin_name)

    codex_manifest: dict[str, Any] = {
        "name": plugin_name,
        "version": require_manifest_value(plugin_manifest, plugin_name, "version"),
        "description": require_manifest_value(plugin_manifest, plugin_name, "description"),
        "author": {
            "name": author_name,
            "email": AWS_AGENT_EMAIL,
            "url": AWS_REPO_URL,
        },
        "homepage": plugin_manifest.get("homepage", AWS_REPO_URL),
        "repository": plugin_manifest.get("repository", AWS_REPO_URL),
        "license": require_manifest_value(plugin_manifest, plugin_name, "license"),
        "keywords": plugin_manifest.get("keywords", []),
        "skills": "./skills/",
        "mcpServers": "./.mcp.json",
        "interface": {
            **interface,
            "developerName": author_name,
            "category": codex_category(marketplace_entry["category"]),
            "capabilities": ["Read", "Write"],
            "websiteURL": plugin_manifest.get("homepage", AWS_REPO_URL),
            "privacyPolicyURL": AWS_PRIVACY_URL,
            "termsOfServiceURL": AWS_TERMS_URL,
            "brandColor": AWS_BRAND_COLOR,
        },
    }

    hooks_path = plugin_dir / "hooks" / "hooks.json"
    if hooks_path.exists() and "CLAUDE_PLUGIN_ROOT" not in hooks_path.read_text():
        codex_manifest["hooks"] = "./hooks/hooks.json"

    return codex_manifest


def main() -> None:
    claude_marketplace = read_json(CLAUDE_MARKETPLACE)

    codex_marketplace = {
        "name": claude_marketplace["name"],
        "interface": {"displayName": "Agent Plugins for AWS"},
        "plugins": [],
    }

    for marketplace_entry in claude_marketplace["plugins"]:
        plugin_name = marketplace_entry["name"]
        plugin_dir = ROOT / "plugins" / plugin_name
        plugin_manifest = read_json(plugin_dir / ".claude-plugin" / "plugin.json")

        codex_marketplace["plugins"].append(
            {
                "name": plugin_name,
                "source": {
                    "source": "local",
                    "path": f"./plugins/{plugin_name}",
                },
                "policy": {
                    "installation": "AVAILABLE",
                    "authentication": "ON_INSTALL",
                },
                "category": codex_category(marketplace_entry["category"]),
            }
        )

        write_json(
            plugin_dir / ".codex-plugin" / "plugin.json",
            build_codex_manifest(plugin_dir, plugin_manifest, marketplace_entry),
        )

    write_json(CODEX_MARKETPLACE, codex_marketplace)


if __name__ == "__main__":
    main()
