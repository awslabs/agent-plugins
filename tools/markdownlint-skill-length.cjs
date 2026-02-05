/**
 * Custom markdownlint rule: skill-length
 * Validates SKILL.md files don't exceed length limits.
 *
 * Limits:
 * - Max 500 lines (error)
 * - Max 8000 words (error)
 * - Recommended 300 lines (warning via info)
 * - Recommended 5000 words (warning via info)
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

    // Check line count
    if (totalLines > MAX_LINES) {
      onError({
        lineNumber: 1,
        detail: `Line count: ${totalLines} (max: ${MAX_LINES}). Move detailed content to references/ subdirectory.`,
        context: `${totalLines} lines`,
      });
    } else if (totalLines > WARNING_LINES) {
      onError({
        lineNumber: 1,
        detail: `Line count: ${totalLines} (recommended: <${WARNING_LINES}). Consider moving content to references/.`,
        context: `${totalLines} lines (warning)`,
      });
    }

    // Check word count
    if (wordCount > MAX_WORDS) {
      onError({
        lineNumber: 1,
        detail: `Word count: ${wordCount} (max: ${MAX_WORDS}). Move detailed content to references/ subdirectory.`,
        context: `${wordCount} words`,
      });
    } else if (wordCount > WARNING_WORDS) {
      onError({
        lineNumber: 1,
        detail: `Word count: ${wordCount} (recommended: <${WARNING_WORDS}). Consider moving content to references/.`,
        context: `${wordCount} words (warning)`,
      });
    }
  },
};
