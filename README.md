# Pre-Anything

Native Quick Look previews for Markdown, JSON, and YAML on macOS 15 and later.

- Markdown is rendered as a native readable document, including common Mermaid diagrams, LaTeX math, and syntax-highlighted fenced code.
- JSON is faithfully formatted with matching rainbow delimiters and level-aware key colors, while values use the system text color.
- YAML keeps the original source, comments, anchors, tags, and indentation while coloring keys by indentation hierarchy and leaving values neutral.

Each format is a separate Quick Look extension, so macOS can enable or disable it independently. The containing App only lists the formats and opens the system extension management page. There are no preferences, background processes, network requests, or App Groups.

Markdown rendering remains AppKit/TextKit based: it does not use HTML, JavaScript, or `WKWebView`. Native Mermaid currently covers flowchart, sequence, state, class, ER, and XY diagrams. Unsupported diagrams and invalid math fall back to readable source text. Local and remote images remain placeholders.

## Development

Requirements:

- macOS 15+
- Xcode 27 beta or a compatible later Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Generate and open the project:

```sh
xcodegen generate
open PreAnything.xcodeproj
```

Command-line verification with the currently selected Xcode:

```sh
xcodebuild \
  -project PreAnything.xcodeproj \
  -scheme PreAnything \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

For local Finder testing, build the `PreAnything` scheme normally. Xcode can use “Sign to Run Locally”; a Personal Team can be supplied in `Config/Local.xcconfig` when needed. Copy the resulting `Pre-Anything.app` into `~/Applications` or `/Applications`, then launch it once so macOS discovers its extensions.

Product direction and non-negotiable behavior are documented in [docs/PRODUCT_DESIGN.md](docs/PRODUCT_DESIGN.md).
