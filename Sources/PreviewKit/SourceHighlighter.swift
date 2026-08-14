import Foundation

enum SourceHighlighter {
    static func document(
        format: PreviewFormat,
        source: String,
        byteCount: Int,
        diagnostic: PreviewDiagnostic? = nil,
        isLimited: Bool = false,
        sourceLanguage: SourceLanguage? = nil
    ) -> PreviewDocument {
        let spans: [PreviewStyleSpan]
        switch format {
        case .json:
            spans = JSONFallbackHighlighter.highlight(source)
        case .yaml:
            spans = YAMLSourceHighlighter.highlight(source)
        case .markdown:
            spans = []
        case .sourceCode:
            spans = NativeCodeHighlighter.spans(
                source: source,
                language: (sourceLanguage ?? .plainText).rawValue
            )
        }

        return PreviewDocument(
            format: format,
            content: source,
            spans: spans,
            diagnostic: diagnostic,
            byteCount: byteCount,
            isLimited: isLimited
        )
    }
}

private enum JSONFallbackHighlighter {
    static func highlight(_ source: String) -> [PreviewStyleSpan] {
        let nsSource = source as NSString
        var spans: [PreviewStyleSpan] = []
        var location = 0
        var depth = 0

        while location < nsSource.length {
            let character = nsSource.character(at: location)

            if isWhitespace(character) {
                location += 1
                continue
            }

            if character == 0x22 {
                let start = location
                location += 1
                while location < nsSource.length {
                    let current = nsSource.character(at: location)
                    if current == 0x5C {
                        location = min(nsSource.length, location + 2)
                    } else {
                        location += 1
                        if current == 0x22 { break }
                    }
                }

                var next = location
                while next < nsSource.length, isWhitespace(nsSource.character(at: next)) {
                    next += 1
                }
                append(
                    range: NSRange(location: start, length: location - start),
                    level: depth,
                    style: next < nsSource.length && nsSource.character(at: next) == 0x3A
                        ? .key
                        : .value,
                    to: &spans
                )
                continue
            }

            switch character {
            case 0x7B, 0x5B: // { [
                append(
                    range: NSRange(location: location, length: 1),
                    level: depth,
                    style: .delimiter,
                    to: &spans
                )
                depth += 1
                location += 1
            case 0x7D, 0x5D: // } ]
                depth = max(0, depth - 1)
                append(
                    range: NSRange(location: location, length: 1),
                    level: depth,
                    style: .delimiter,
                    to: &spans
                )
                location += 1
            case 0x2C, 0x3A: // , :
                append(
                    range: NSRange(location: location, length: 1),
                    level: depth,
                    style: .punctuation,
                    to: &spans
                )
                location += 1
            default:
                let start = location
                while location < nsSource.length {
                    let current = nsSource.character(at: location)
                    if isWhitespace(current) || isStructural(current) { break }
                    location += 1
                }
                append(
                    range: NSRange(location: start, length: max(1, location - start)),
                    level: depth,
                    style: .value,
                    to: &spans
                )
                if location == start { location += 1 }
            }
        }

        return spans
    }

    private static func append(
        range: NSRange,
        level: Int,
        style: HierarchyTokenStyle,
        to spans: inout [PreviewStyleSpan]
    ) {
        guard range.length > 0 else { return }
        spans.append(PreviewStyleSpan(
            location: range.location,
            length: range.length,
            role: .hierarchy(level: level, style: style)
        ))
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09 || character == 0x0A || character == 0x0D
    }

    private static func isStructural(_ character: unichar) -> Bool {
        switch character {
        case 0x7B, 0x7D, 0x5B, 0x5D, 0x2C, 0x3A, 0x22:
            true
        default:
            false
        }
    }
}

enum YAMLSourceHighlighter {
    static func highlight(_ source: String) -> [PreviewStyleSpan] {
        let nsSource = source as NSString
        var spans: [PreviewStyleSpan] = []
        var lineStart = 0
        var indentationStack = [0]
        var blockScalarIndentation: Int?

        while lineStart < nsSource.length {
            let lineRange = nsSource.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = nsSource.substring(with: lineRange)
            let indentation = indentationWidth(in: line)
            let content = contentWithoutLineEnding(line)
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let isBlockScalarContent = blockScalarIndentation.map {
                !trimmed.isEmpty && indentation > $0
            } ?? false

            if let scalarIndentation = blockScalarIndentation,
               !trimmed.isEmpty,
               indentation <= scalarIndentation {
                blockScalarIndentation = nil
            }

            if !trimmed.isEmpty, !trimmed.hasPrefix("#") || isBlockScalarContent {
                if trimmed == "---" || trimmed == "..." {
                    indentationStack = [0]
                } else {
                    while indentationStack.count > 1,
                          indentation < (indentationStack.last ?? 0) {
                        indentationStack.removeLast()
                    }
                    if indentation > (indentationStack.last ?? 0) {
                        indentationStack.append(indentation)
                    } else if indentation != indentationStack.last {
                        indentationStack.append(indentation)
                    }
                }

                let level = max(0, indentationStack.count - 1)
                highlightLine(
                    line,
                    at: lineRange.location,
                    level: level,
                    treatsHashAsText: isBlockScalarContent,
                    spans: &spans
                )

                if !isBlockScalarContent, startsBlockScalar(in: content) {
                    blockScalarIndentation = indentation
                }
            } else if trimmed.hasPrefix("#") {
                highlightLine(
                    line,
                    at: lineRange.location,
                    level: max(0, indentationStack.count - 1),
                    treatsHashAsText: false,
                    spans: &spans
                )
            }
            lineStart = NSMaxRange(lineRange)
        }

        return spans
    }

    private static func highlightLine(
        _ line: String,
        at baseLocation: Int,
        level: Int,
        treatsHashAsText: Bool,
        spans: inout [PreviewStyleSpan]
    ) {
        let nsLine = line as NSString
        let contentLength = contentWithoutLineEnding(line).utf16.count
        let commentLocation = treatsHashAsText ? nil : firstCommentLocation(in: line)
        let codeEnd = min(commentLocation ?? contentLength, contentLength)
        var codeStart = 0
        while codeStart < codeEnd {
            let character = nsLine.character(at: codeStart)
            guard character == 0x20 || character == 0x09 else { break }
            codeStart += 1
        }
        let codeRange = NSRange(location: codeStart, length: max(0, codeEnd - codeStart))

        if codeRange.length > 0 {
            spans.append(PreviewStyleSpan(
                location: baseLocation + codeRange.location,
                length: codeRange.length,
                role: .hierarchy(level: level, style: .value)
            ))
        }

        if let commentLocation {
            spans.append(PreviewStyleSpan(
                location: baseLocation + commentLocation,
                length: max(0, contentLength - commentLocation),
                role: .comment
            ))
        }

        appendCaptureMatches(
            pattern: #"^\s*(?:-\s+|\?\s+)?(\"(?:\\.|[^\"])*\"|'(?:''|[^'])*'|[^:#\r\n]+?)(?=\s*:)"#,
            capture: 1,
            role: .hierarchy(level: level, style: .key),
            source: line,
            range: NSRange(location: 0, length: codeEnd),
            offset: baseLocation,
            to: &spans
        )
        appendCaptureMatches(
            pattern: #"^\s*([-?])(?=\s)"#,
            capture: 1,
            role: .hierarchy(level: level, style: .delimiter),
            source: line,
            range: NSRange(location: 0, length: codeEnd),
            offset: baseLocation,
            to: &spans
        )
        appendCaptureMatches(
            pattern: #"^\s*((?:---|\.\.\.))(?=\s|$)"#,
            capture: 1,
            role: .hierarchy(level: level, style: .delimiter),
            source: line,
            range: NSRange(location: 0, length: codeEnd),
            offset: baseLocation,
            to: &spans
        )
        appendMatches(
            pattern: #"[:\[\]{},|>]"#,
            role: .hierarchy(level: level, style: .punctuation),
            source: line,
            range: NSRange(location: 0, length: codeEnd),
            offset: baseLocation,
            to: &spans
        )
    }

    private static func indentationWidth(in line: String) -> Int {
        var width = 0
        for scalar in line.unicodeScalars {
            if scalar == " " {
                width += 1
            } else if scalar == "\t" {
                width += 2
            } else {
                break
            }
        }
        return width
    }

    private static func contentWithoutLineEnding(_ line: String) -> String {
        line.trimmingCharacters(in: .newlines)
    }

    private static func startsBlockScalar(in line: String) -> Bool {
        let codeEnd = firstCommentLocation(in: line) ?? line.utf16.count
        let code = (line as NSString).substring(with: NSRange(location: 0, length: codeEnd))
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:^|:\s+|-\s+)[|>](?:[+-]?[1-9]?|[1-9]?[+-]?)\s*$"#
        ) else { return false }
        let range = NSRange(location: 0, length: (code as NSString).length)
        return expression.firstMatch(in: code, range: range) != nil
    }

    private static func firstCommentLocation(in line: String) -> Int? {
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false
        var utf16Offset = 0
        var previousWasWhitespace = true

        for scalar in line.unicodeScalars {
            let scalarLength = String(scalar).utf16.count

            if inDoubleQuote {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inDoubleQuote = false
                }
            } else if inSingleQuote {
                if scalar == "'" {
                    inSingleQuote = false
                }
            } else if scalar == "\"" {
                inDoubleQuote = true
            } else if scalar == "'" {
                inSingleQuote = true
            } else if scalar == "#", previousWasWhitespace {
                return utf16Offset
            }

            if !inSingleQuote, !inDoubleQuote {
                previousWasWhitespace = scalar.properties.isWhitespace
            }
            utf16Offset += scalarLength
        }

        return nil
    }
}

private func appendCaptureMatches(
    pattern: String,
    capture: Int,
    role: PreviewStyleRole,
    source: String,
    range: NSRange,
    offset: Int = 0,
    to spans: inout [PreviewStyleSpan]
) {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
    expression.enumerateMatches(in: source, range: range) { match, _, _ in
        guard let match, capture < match.numberOfRanges else { return }
        let captured = match.range(at: capture)
        guard captured.location != NSNotFound, captured.length > 0 else { return }
        spans.append(PreviewStyleSpan(
            location: offset + captured.location,
            length: captured.length,
            role: role
        ))
    }
}

private func appendMatches(
    pattern: String,
    role: PreviewStyleRole,
    source: String,
    range: NSRange,
    offset: Int = 0,
    to spans: inout [PreviewStyleSpan],
    options: NSRegularExpression.Options = []
) {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
        return
    }

    expression.enumerateMatches(in: source, range: range) { match, _, _ in
        guard let match, match.range.length > 0 else { return }
        spans.append(PreviewStyleSpan(
            location: offset + match.range.location,
            length: match.range.length,
            role: role
        ))
    }
}
