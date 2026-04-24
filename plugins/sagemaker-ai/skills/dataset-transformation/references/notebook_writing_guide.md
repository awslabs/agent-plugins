# Guide: Writing Jupyter Notebooks

## Critical Differences from Regular Files

Jupyter notebooks (.ipynb) are JSON files with a specific structure. Writing to them is fundamentally different from writing regular Python files.

## The Problem

When you write Python code to a regular .py file, you write it as plain text with newlines:

```python
import os
x = 5
print(x)
```

But in a Jupyter notebook, each line must be a separate string in a JSON array:

```json
{
  "source": [
    "import os\n",
    "x = 5\n",
    "print(x)"
  ]
}
```

## The Solution: Write as JSON Structure

### Correct Notebook Structure (Pretty-Print Format)

Use **2-space indentation** (pretty-print format) for consistent, readable formatting:

```json
{
  "cells": [
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "outputs": [],
      "source": [
        "# This is line 1\n",
        "import os\n",
        "x = 5\n",
        "print(x)"
      ]
    }
  ],
  "metadata": {
    "kernelspec": {
      "display_name": "Python 3",
      "language": "python",
      "name": "python3"
    },
    "language_info": {
      "name": "python",
      "version": "3.9.0"
    }
  },
  "nbformat": 4,
  "nbformat_minor": 4
}
```

**CRITICAL**: Use exactly 2 spaces for each indentation level (standard pretty-print format).

### Key Points

1. **Each line ends with `\n`** - This is how newlines are represented in JSON strings
2. **Lines are separate array elements** - Each line is a string in the `source` array
3. **Use proper JSON escaping** - Quotes inside strings must be escaped: `\"text\"`
4. **No trailing comma** - Last element in arrays/objects should not have a comma

## Common Mistakes to Avoid

❌ **DON'T** use bash commands to generate JSON and pipe to file
❌ **DON'T** write code as a single string without line breaks
❌ **DON'T** forget to escape quotes in strings
❌ **DON'T** add trailing commas to last array elements

✅ **DO** use your standard file write tool to write the complete notebook JSON, or notebook MCP tools (e.g., `create_notebook`, `add_cell`) if available
✅ **DO** add `\n` to end of each line in source arrays
✅ **DO** validate JSON structure before writing
✅ **DO** use proper escaping for special characters

## Validation Checklist

Before writing the notebook, verify:

- [ ] Each cell has proper structure (cell_type, execution_count, metadata, outputs, source)
- [ ] Source arrays have each line as a separate string ending in `\n`
- [ ] Quotes are properly escaped
- [ ] No trailing commas
- [ ] Metadata section is complete
- [ ] nbformat and nbformat_minor are set
