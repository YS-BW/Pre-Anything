# Stage One Implementation Notes

## Architecture

`project.yml` is the source of truth for the Xcode project, bundle identifiers, extension targets, supported UTIs, dependency versions, and embedding relationships.

```text
Pre-Anything.app
└── Contents/PlugIns/
    ├── Markdown Preview.appex  → net.daringfireball.markdown
    ├── JSON Preview.appex      → public.json
    └── YAML Preview.appex      → public.yaml
```

All three extensions statically link `PreviewKit`. No shared writable state or App Group is required.

The public processing boundary is:

```swift
PreviewService.prepare(url:as:) async -> PreviewDocument
```

The service reads only the requested URL, applies size and encoding limits, performs format-specific parsing, and returns plain text plus semantic style spans and an optional diagnostic. AppKit conversion is kept at the final display boundary.

## Fixed behavior

- UTF-8, UTF-8 BOM, and BOM-marked UTF-16 LE/BE are accepted. Other encodings fail explicitly.
- Files through 5 MiB receive full processing.
- Files from 5–25 MiB show a 1 MiB source prefix without full parsing.
- Files over 25 MiB show a 256 KiB source prefix without full parsing.
- Markdown uses `swift-markdown` 0.8.0 and stays fully native. SwiftMath renders inline/block math; BeautifulMermaid renders six common diagram families; a bounded Swift lexer highlights common fenced-code languages. HTML is displayed as text and images are represented by alt-text placeholders.
- JSON uses an internal tokenizer and parser with depth and token limits. Formatting never converts a number to a Swift numeric type; formatter depth drives matching delimiter and same-level text colors.
- YAML uses Yams 6.2.2 only for validation. Displayed content is always the original source, and a line scanner assigns colors from the indentation stack while preserving comments and block scalars.

## Verification record

Validated on 2026-08-13 with macOS 27 beta, Xcode 27 beta (27A5237l), and Swift 6.4:

- Debug unit test suite: 14 tests passed.
- 1 MiB JSON processing baseline: approximately 0.24 seconds in the Debug test process.
- Release build: succeeded using “Sign to Run Locally”.
- Release app size after font pruning and hierarchy highlighting: approximately 39 MiB universal. Heavy native rendering dependencies are linked only into `Markdown Preview.appex`; JSON and YAML remain approximately 5.8 MiB each.
- Code signature deep verification: passed.
- PlugInKit discovery: all three extension identifiers registered from `~/Applications/Pre-Anything.app`.
- `qlmanage` launched the matching Pre-Anything extension process for each Markdown, JSON, and YAML fixture.
- Dark appearance visually checked for the containing App, Markdown preview, and JSON preview.
- Computer Use confirmed that System Settings exposes `JSON Preview`, `Markdown Preview`, and `YAML Preview` as three independent Quick Look switches.
- Computer Use confirmed that the containing App's management button opens the system Quick Look extension manager without changing switch state itself.

The 300 ms number is an initial local baseline, not a cross-device guarantee. Keep the performance test and fixture shape stable when changing parsers or rendering.
