# draw.io CLI Export Reference

The draw.io desktop app includes a CLI for exporting diagrams to PNG, SVG, or PDF.

## Locating the CLI

Try `drawio` first (works if on PATH), then fall back to platform-specific path:

- **macOS**: `/Applications/draw.io.app/Contents/MacOS/draw.io`
- **Linux**: `drawio` (typically on PATH via snap/apt/flatpak)
- **Windows**: `"C:\Program Files\draw.io\draw.io.exe"`

Use `which drawio` (or `where drawio` on Windows) to check PATH first.

## Export Command

```bash
drawio -x -f <format> -e -b 10 -o <output> <input.drawio>
```

Key flags:

- `-x` / `--export`: export mode (required)
- `-f` / `--format`: output format (png, svg, pdf)
- `-e` / `--embed-diagram`: embed diagram XML in the output (remains editable in draw.io)
- `-o` / `--output`: output file path
- `-b` / `--border`: border width (default: 0, use 10)
- `-t` / `--transparent`: transparent background (PNG only)
- `-s` / `--scale`: scale the diagram size
- `--width` / `--height`: fit into specified dimensions (preserves aspect ratio)
- `-a` / `--all-pages`: export all pages (PDF only)
- `-p` / `--page-index`: select a specific page (0-based)

## Supported Formats

| Format | Embed XML  | Notes                                    |
| ------ | ---------- | ---------------------------------------- |
| `png`  | Yes (`-e`) | Viewable everywhere, editable in draw.io |
| `svg`  | Yes (`-e`) | Scalable, editable in draw.io            |
| `pdf`  | Yes (`-e`) | Printable, editable in draw.io           |

## File Naming

Use double extensions: `architecture.drawio.png`, `architecture.drawio.svg`, `architecture.drawio.pdf`. This signals the file contains embedded diagram XML. Opening in draw.io recovers the editable diagram. After a successful export, delete the intermediate `.drawio` file since the exported file contains the full diagram.

## Opening the Result

- **macOS**: `open <file>`
- **Linux**: `xdg-open <file>`
- **Windows**: `start <file>`
