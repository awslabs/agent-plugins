/**
 * Custom markdownlint rule: skill-length
 * Validates SKILL.md files don't exceed length limits.
 *
 * Philosophy: SKILL.md is loaded into the agent's context window on every
 * invocation. Keep it lean — big ideas and routing only. Push detailed
 * instructions, examples, and reference material into sub-files under
 * references/ so the agent loads them on demand.
 *
 * Limits:
 * - Hard error at 500 lines / 8000 words (blocks CI)
 * - Warning at 300 lines / 5000 words (informational, does not block CI)
 */

"use strict";

const MAX_LINES = 500;
const MAX_WORDS = 8000;
const WARNING_LINES = 300;
const WARNING_WORDS = 5000;

module.exports = {
  names: ["skill-length", "SKILL001"],
  description: "SKILL.md files should be concise for progressive disclosure",
  tags: ["skill", "length"],
  parser: "none",
  function: function skillLength(params, onError) {
    // Only apply to SKILL.md files
    if (!params.name.endsWith("SKILL.md")) {
      return;
    }

    // params.lines excludes frontmatter when frontMatter config is set
    const lines = params.lines;

    // Calculate total lines (frontmatter + content)
    const frontMatterLines = params.frontMatterLines || [];
    const totalLines = frontMatterLines.length + lines.length;

    // Calculate word count from content (excluding frontmatter)
    const content = lines.join("\n");
    const wordCount = content.split(/\s+/).filter(Boolean).length;

    // Check line count — only hard limit blocks CI
    if (totalLines > MAX_LINES) {
      onError({
        lineNumber: 1,
        detail: `Line count: ${totalLines} (max: ${MAX_LINES}). Move detailed content to references/ subdirectory.`,
        context: `${totalLines} lines (error)`,
      });
    } else if (totalLines > WARNING_LINES) {
      // Advisory only — does not block CI. Aim to stay under 300 lines by
      // keeping only big ideas and routing in SKILL.md and pushing details
      // into reference files.
      console.warn(
        `  ⚠️  ${params.name}: ${totalLines} lines (target: <${WARNING_LINES}). ` +
        `Consider moving detailed content to references/.`
      );
    }

    // Check word count — only hard limit blocks CI
    if (wordCount > MAX_WORDS) {
      onError({
        lineNumber: 1,
        detail: `Word count: ${wordCount} (max: ${MAX_WORDS}). Move detailed content to references/ subdirectory.`,
        context: `${wordCount} words (error)`,
      });
    } else if (wordCount > WARNING_WORDS) {
      console.warn(
        `  ⚠️  ${params.name}: ${wordCount} words (target: <${WARNING_WORDS}). ` +
        `Consider moving detailed content to references/.`
      );
    }
  },
};
