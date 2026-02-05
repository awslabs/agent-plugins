/**
 * Custom markdownlint rule: skill-frontmatter
 * Validates SKILL.md files have required frontmatter fields.
 *
 * Required:
 * - name: skill identifier (kebab-case)
 * - description: when to use this skill (min 20 chars)
 */

"use strict";

const path = require("path");

module.exports = {
  names: ["skill-frontmatter", "SKILL002"],
  description: "SKILL.md files must have required frontmatter fields",
  tags: ["skill", "frontmatter"],
  parser: "none",
  function: function skillFrontmatter(params, onError) {
    // Only apply to SKILL.md files
    if (!params.name.endsWith("SKILL.md")) {
      return;
    }

    // Access frontmatter lines (markdownlint strips frontmatter from params.lines)
    const frontMatterLines = params.frontMatterLines || [];

    // Check for frontmatter presence
    if (frontMatterLines.length === 0) {
      onError({
        lineNumber: 1,
        detail: "SKILL.md must have YAML frontmatter (---)",
        context: "Missing frontmatter",
      });
      return;
    }

    // Join frontmatter lines (excluding the --- delimiters)
    const frontmatter = frontMatterLines
      .filter((line) => line !== "---")
      .join("\n");

    // Check for name field
    const nameMatch = frontmatter.match(/^name:\s*(.+)$/m);
    if (!nameMatch) {
      onError({
        lineNumber: 2,
        detail: 'Frontmatter must include "name" field',
        context: "Missing name",
      });
    } else {
      const name = nameMatch[1].trim().replace(/^["']|["']$/g, "");
      // Validate kebab-case
      if (!/^[a-z][a-z0-9-]*$/.test(name)) {
        onError({
          lineNumber: 2,
          detail: `Skill name must be kebab-case: "${name}"`,
          context: "Invalid name format",
        });
      }
      // Validate max length (64 chars per Anthropic spec)
      if (name.length > 64) {
        onError({
          lineNumber: 2,
          detail: `Skill name exceeds 64 characters (current: ${name.length})`,
          context: "Name too long",
        });
      }
      // Check for reserved words (anthropic, claude)
      if (/\b(anthropic|claude)\b/i.test(name)) {
        onError({
          lineNumber: 2,
          detail: `Skill name cannot contain reserved words "anthropic" or "claude": "${name}"`,
          context: "Reserved word in name",
        });
      }
      // Check for consecutive hyphens
      if (/--/.test(name)) {
        onError({
          lineNumber: 2,
          detail: `Skill name cannot contain consecutive hyphens: "${name}"`,
          context: "Consecutive hyphens",
        });
      }
      // Check for XML tags in name
      if (/<[^>]+>/.test(name)) {
        onError({
          lineNumber: 2,
          detail: `Skill name cannot contain XML tags: "${name}"`,
          context: "XML tag in name",
        });
      }
      // Check that name matches parent directory (AgentSkills.io spec)
      const dirName = path.basename(path.dirname(params.name));
      if (name !== dirName) {
        onError({
          lineNumber: 2,
          detail: `Skill name "${name}" must match directory name "${dirName}"`,
          context: "Name/directory mismatch",
        });
      }
    }

    // Check for description field
    const descMatch = frontmatter.match(/^description:\s*(.+)$/m);
    // Also check for multiline description with >
    const descMultilineMatch = frontmatter.match(
      /^description:\s*>\s*\n([\s\S]*?)(?=\n[a-z-]+:|$)/m
    );

    if (!descMatch && !descMultilineMatch) {
      onError({
        lineNumber: 2,
        detail: 'Frontmatter must include "description" field',
        context: "Missing description",
      });
    } else {
      let description = "";
      if (descMultilineMatch) {
        description = descMultilineMatch[1].replace(/\n\s*/g, " ").trim();
      } else if (descMatch) {
        description = descMatch[1].trim().replace(/^["']|["']$/g, "");
      }

      if (description.length < 20) {
        onError({
          lineNumber: 2,
          detail: `Description should be at least 20 characters (current: ${description.length})`,
          context: "Description too short",
        });
      }
      // Validate max length (1024 chars per Anthropic spec)
      if (description.length > 1024) {
        onError({
          lineNumber: 2,
          detail: `Description exceeds 1024 characters (current: ${description.length})`,
          context: "Description too long",
        });
      }
      // Check for XML tags in description
      if (/<[^>]+>/.test(description)) {
        onError({
          lineNumber: 2,
          detail: "Description cannot contain XML tags",
          context: "XML tag in description",
        });
      }
    }
  },
};
