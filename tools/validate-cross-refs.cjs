/**
 * Cross-reference validation for Agent Plugins for AWS
 *
 * Validates relationships between manifest files:
 * - marketplace.json plugins[] -> plugin directories exist
 * - marketplace.json plugins[].name -> plugin.json name
 * - Plugin directories are not symlinks (security)
 * - Warns if plugin has no skills/ directory
 */

"use strict";

const fs = require("fs");
const path = require("path");

const MARKETPLACE_PATH = ".claude-plugin/marketplace.json";
const PLUGINS_ROOT = "plugins";

const BASE_DIR = path.resolve(process.cwd(), PLUGINS_ROOT);

let errors = [];
let warnings = [];

/**
 * Resolve and validate path stays under BASE_DIR (path traversal protection).
 * Returns normalized absolute path, or null if invalid.
 */
function resolvePathUnderBase(relativePath) {
  if (!relativePath || typeof relativePath !== "string") return null;
  const normalized = path.normalize(relativePath.replace(/^\.\//, "").replace(/\/$/, ""));
  if (normalized.startsWith("..") || path.isAbsolute(normalized)) return null;
  const fullPath = path.resolve(process.cwd(), normalized);
  const baseResolved = path.resolve(BASE_DIR);
  if (!fullPath.startsWith(baseResolved)) return null;
  return fullPath;
}

function error(message) {
  errors.push(message);
  console.error(`ERROR: ${message}`);
}

function warn(message) {
  warnings.push(message);
  console.warn(`WARNING: ${message}`);
}

function info(message) {
  console.log(`INFO: ${message}`);
}

function validateMarketplace() {
  // Check marketplace.json exists
  if (!fs.existsSync(MARKETPLACE_PATH)) {
    error(`Marketplace file not found: ${MARKETPLACE_PATH}`);
    return;
  }

  let marketplace;
  try {
    marketplace = JSON.parse(fs.readFileSync(MARKETPLACE_PATH, "utf8"));
  } catch (e) {
    error(`Failed to parse ${MARKETPLACE_PATH}: ${e.message}`);
    return;
  }

  // Check plugins array exists
  if (!marketplace.plugins || !Array.isArray(marketplace.plugins)) {
    error(`${MARKETPLACE_PATH} must have a "plugins" array`);
    return;
  }

  // Empty plugins array is valid
  if (marketplace.plugins.length === 0) {
    info("No plugins defined in marketplace.json");
    return;
  }

  // Validate each plugin
  for (const plugin of marketplace.plugins) {
    validatePlugin(plugin);
  }
}

function validatePlugin(plugin) {
  const pluginName = plugin.name;
  if (!pluginName) {
    error(`Plugin entry missing "name" field`);
    return;
  }

  info(`Validating plugin: ${pluginName}`);

  const source = plugin.source || `${PLUGINS_ROOT}/${pluginName}`;
  const pluginDir = resolvePathUnderBase(source);
  if (pluginDir === null) {
    error(`Invalid or disallowed plugin path (path traversal): ${source}`);
    return;
  }

  // Check 1: Plugin directory exists
  if (!fs.existsSync(pluginDir)) { // nosemgrep: gitlab.eslint.detect-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
    error(`Plugin directory not found: ${pluginDir} (referenced by "${pluginName}" in marketplace.json)`);
    return;
  }

  // Check 2: Directory is not a symlink (security)
  const stats = fs.lstatSync(pluginDir); // nosemgrep: gitlab.eslint.detect-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
  if (stats.isSymbolicLink()) {
    error(`Plugin directory cannot be a symlink: ${pluginDir} (security risk)`);
    return;
  }

  // Check 3: Directory name matches plugin name
  const dirName = path.basename(pluginDir);
  if (dirName !== pluginName) {
    error(`Directory name "${dirName}" doesn't match plugin name "${pluginName}" in marketplace.json`);
  }

  // Check 4: plugin.json exists
  // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
  const pluginJsonPath = path.join(pluginDir, ".claude-plugin", "plugin.json");
  if (!fs.existsSync(pluginJsonPath)) { // nosemgrep: gitlab.eslint.detect-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
    error(`plugin.json not found: ${pluginJsonPath}`);
    return;
  }

  // Check 5: plugin.json name matches marketplace.json name
  let pluginJson;
  try {
    pluginJson = JSON.parse(fs.readFileSync(pluginJsonPath, "utf8")); // nosemgrep: gitlab.eslint.detect-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
  } catch (e) {
    error(`Failed to parse ${pluginJsonPath}: ${e.message}`);
    return;
  }

  if (pluginJson.name !== pluginName) {
    error(`Name mismatch: marketplace.json says "${pluginName}", but ${pluginJsonPath} says "${pluginJson.name}"`);
  }

  // Check 6: skills/ directory exists (warning only)
  // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
  const skillsDir = path.join(pluginDir, "skills");
  if (!fs.existsSync(skillsDir)) { // nosemgrep: gitlab.eslint.detect-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
    warn(`Plugin "${pluginName}" has no skills/ directory`);
  } else if (!fs.statSync(skillsDir).isDirectory()) { // nosemgrep: gitlab.eslint.detect-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
    warn(`Plugin "${pluginName}": skills is not a directory`);
  }
}

// Run validation
console.log("=== Cross-Reference Validation ===\n");
validateMarketplace();

// Summary
console.log("\n=== Summary ===");
console.log(`Errors: ${errors.length}`);
console.log(`Warnings: ${warnings.length}`);

// Exit with error code if any errors
if (errors.length > 0) {
  process.exit(1);
}
