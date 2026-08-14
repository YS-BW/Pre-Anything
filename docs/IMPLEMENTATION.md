# Stage One Implementation Notes

## Architecture

`project.yml` is the source of truth for the Xcode project, bundle identifiers, extension targets, supported UTIs, dependency versions, and embedding relationships.

```text
Pre-Anything.app
└── Contents/PlugIns/
    ├── Markdown Preview.appex  → net.daringfireball.markdown
    ├── JSON Preview.appex      → public.json
    ├── YAML Preview.appex      → public.yaml
    ├── Config Preview.appex    → TOML, JSONC/JSON5, dotenv, INI/properties
    ├── Table Preview.appex     → CSV, TSV
    ├── XML Preview.appex       → public.xml
    ├── Notebook Preview.appex  → .ipynb
    └── Source Code Preview.appex
        → concrete system language UTIs, public.source-code,
          public.css, com.lixinlv.preanything.source-code
```

All eight extensions statically link `PreviewKit`. TOMLKit is linked only by Config Preview, keeping that parser out of the other extensions. The containing App and extensions share only their per-format transparent-background booleans through the signing-team-derived macOS App Group `<TeamID>.com.lixinlv.PreAnything`; file contents never enter the App Group. This avoids embedding a provisioning profile in a development-signed GitHub build.

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
- Config Preview validates TOML with TOMLKit 0.6.0 and JSONC/JSON5 with Foundation JSON5 decoding. TOML and configuration-style formats retain their original text; JSON5 keys follow the JSON hierarchy palette and values remain neutral.
- Table Preview uses a bounded RFC 4180 parser and a selectable native `NSTableView`. It accepts quoted fields, escaped quotes, empty values, and newlines in quoted cells; complete previews show at most 500 data rows and 50 columns.
- XML Preview validates with `XMLParser` but always displays the original source with syntax spans for markup, attributes, CDATA, comments, and entities.
- Notebook Preview decodes `.ipynb` JSON into a native vertical cell stream. It renders no more than 200 cells and accepts only embedded PNG/JPEG output below the per-image and total-image limits; HTML, JavaScript, SVG, external resources, and code execution are excluded.
- Source Code uses the bounded, dependency-free native lexer shared with Markdown code blocks. It preserves the original text, detects the language from the suffix, and adds syntax spans, line numbers, selection/copy, and horizontal scrolling without running compilers or interpreters. Stable system source UTIs are supplemented by one exported aggregate UTI for common suffixes macOS does not identify consistently.

## Verification record

Validated on 2026-08-14 with macOS 27 beta, Xcode 27 beta (27A5237l), and Swift 6.4:

- Debug unit test suite: 29 tests passed, including all new UTI registrations, TOML/JSON5/config syntax styling, CSV quoted-newline parsing, UTF-16 tables, XML diagnostics, safe notebook rendering, source-language detection, bounded source fallback, and independent per-format appearance preferences.
- 1 MiB JSON processing baseline: approximately 0.29 seconds in the Debug test process.
- Debug app build: succeeded with all eight preview extensions embedded and validated by Xcode.
- Release build: succeeded using “Sign to Run Locally”.
- Alpha distribution packages are arm64-only. Universal packaging is intentionally deferred until the formal release stage. Heavy Mermaid and math rendering dependencies remain confined to Markdown.
- Code signature deep verification: passed.
- PlugInKit discovery is intentionally left to Finder/system-settings verification because each preview family is independently switchable.
- Computer Use confirmed that Finder launches `Source Code Preview` for concrete `public.python-script` and `com.sun.java-source` files. Both fixtures render selectable, line-numbered, syntax-highlighted native text.
- Dark appearance visually checked for the containing App, Markdown preview, and JSON preview.
- Computer Use previously confirmed that System Settings exposes the preview extensions as independent Quick Look switches.
- Computer Use confirmed that the containing App's management button opens the system Quick Look extension manager without changing switch state itself.

The 300 ms number is an initial local baseline, not a cross-device guarantee. Keep the performance test and fixture shape stable when changing parsers or rendering.
