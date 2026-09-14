#!/usr/bin/env bash
# install-kiro-scripts.sh
#
# Installs plugin-level scripts into the Kiro skill directory and patches
# ${PLUGIN_ROOT} references in SKILL.md to the actual installed path.
#
# Required because the compound-plugin converter only copies skills/<name>/
# and does not install plugin-level scripts/ that some skills depend on.
#
# Usage (global install):
#   bash plugins/deploy-on-aws/scripts/install-kiro-scripts.sh
#
# Usage (project-scoped install):
#   bash plugins/deploy-on-aws/scripts/install-kiro-scripts.sh --project

set -euo pipefail

# ── resolve install root ──────────────────────────────────────────────────────
PROJECT_SCOPE=false
for arg in "$@"; do
  [[ "$arg" == "--project" ]] && PROJECT_SCOPE=true
done

if [[ "$PROJECT_SCOPE" == "true" ]]; then
  KIRO_ROOT="${PWD}/.kiro"
  SCOPE_LABEL="project"
else
  KIRO_ROOT="${HOME}/.kiro"
  SCOPE_LABEL="global"
fi

SKILL_NAME="aws-architecture-diagram"
KIRO_SKILLS_DIR="${KIRO_ROOT}/skills/${SKILL_NAME}"
SCRIPTS_DEST="${KIRO_SKILLS_DIR}/scripts"
REPO_RAW="https://raw.githubusercontent.com/awslabs/agent-plugins/main/plugins/deploy-on-aws/scripts"

echo ""
echo "📦  Installing scripts for '${SKILL_NAME}' (${SCOPE_LABEL} scope)"
echo "    Target: ${KIRO_SKILLS_DIR}"
echo ""

# ── verify skill is installed ─────────────────────────────────────────────────
if [[ ! -f "${KIRO_SKILLS_DIR}/SKILL.md" ]]; then
  echo "❌  '${SKILL_NAME}' skill not found at ${KIRO_SKILLS_DIR}"
  echo ""
  echo "    Run the compound-plugin install step first:"
  echo ""
  if [[ "$PROJECT_SCOPE" == "true" ]]; then
    echo "    COMPOUND_PLUGIN_GITHUB_SOURCE=https://github.com/awslabs/agent-plugins \\"
    echo "      bunx @every-env/compound-plugin install deploy-on-aws --to kiro"
  else
    echo "    COMPOUND_PLUGIN_GITHUB_SOURCE=https://github.com/awslabs/agent-plugins \\"
    echo "      bunx @every-env/compound-plugin install deploy-on-aws --to kiro --output ~/.kiro"
  fi
  echo ""
  exit 1
fi

# ── download scripts ──────────────────────────────────────────────────────────
mkdir -p "${SCRIPTS_DEST}/lib"

SCRIPTS=(
  "lib/drawio_url.py"
  "lib/fix_step_badges.py"
  "lib/fix_icon_colors.py"
  "lib/fix_nesting.py"
  "lib/post_process_drawio.py"
  "lib/validate_drawio.py"
  "lib/aws4-shapes.json"
  "requirements.txt"
)

for script in "${SCRIPTS[@]}"; do
  dest_dir="${SCRIPTS_DEST}/$(dirname "$script")"
  mkdir -p "$dest_dir"
  curl -fsSL "${REPO_RAW}/${script}" -o "${SCRIPTS_DEST}/${script}"
  echo "    ✅  ${script}"
done

# ── install Python dependencies ───────────────────────────────────────────────
if command -v pip3 &>/dev/null; then
  pip3 install -r "${SCRIPTS_DEST}/requirements.txt" -q
  echo "    ✅  Python dependencies installed (defusedxml)"
elif command -v pip &>/dev/null; then
  pip install -r "${SCRIPTS_DEST}/requirements.txt" -q
  echo "    ✅  Python dependencies installed (defusedxml)"
else
  echo "    ⚠️   pip not found — install dependencies manually:"
  echo "        pip install -r ${SCRIPTS_DEST}/requirements.txt"
fi

# ── patch ${PLUGIN_ROOT} in SKILL.md ─────────────────────────────────────────
# ${PLUGIN_ROOT} is a Claude Code runtime variable with no Kiro equivalent.
# Replace it with the actual installed skill path so script references resolve.
if grep -q '${PLUGIN_ROOT}' "${KIRO_SKILLS_DIR}/SKILL.md"; then
  sed -i.bak "s|\${PLUGIN_ROOT}|${KIRO_SKILLS_DIR}|g" "${KIRO_SKILLS_DIR}/SKILL.md"
  rm -f "${KIRO_SKILLS_DIR}/SKILL.md.bak"
  echo "    ✅  Patched \${PLUGIN_ROOT} → ${KIRO_SKILLS_DIR} in SKILL.md"
else
  echo "    ℹ️   SKILL.md already patched — skipping"
fi

echo ""
echo "✅  Done. The '${SKILL_NAME}' skill is fully installed for Kiro."
echo ""
