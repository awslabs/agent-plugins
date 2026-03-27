# Post-Processing Pipeline

Deterministic fixers run automatically via the `validate-drawio.sh` PostToolUse hook, in this order:

1. **fix_nesting.py** — Sets Region `container=0`, re-parents children to root
2. **fix_icon_colors.py** — Corrects service icon fillColor to match category
3. **fix_step_badges.py** — Nudges overlapping step badges apart
4. **fix_placement.py** — Moves external actors below the title block (y >= 140)
5. **fix_legend_size.py** — Resizes legend panel to match diagram height

All scripts are in `scripts/lib/`. The pipeline is orchestrated by `scripts/lib/post_process_drawio.py`, which chains them in sequence. No manual invocation is needed when using the PostToolUse hook.

The PostToolUse hook fires on all Edit/Write operations but exits immediately (<10ms) for non-.drawio files.

**Dependency**: The pipeline requires `defusedxml` (`pip3 install defusedxml>=0.7.1`). If missing, the hook skips validation and shows an install prompt.
