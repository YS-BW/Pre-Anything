import Foundation

public enum ConfigSyntaxKind: Sendable {
    case toml
    case json5
    case dotenv
    case ini
    case properties
    case generic
}

/// Keeps configuration previews faithful to their source while assigning the
/// same key/value visual language used by JSON and YAML.
public enum ConfigSourceHighlighter {
    public static func highlight(_ source: String, kind: ConfigSyntaxKind) -> [PreviewStyleSpan] {
        switch kind {
        case .json5:
            return json5(source)
        case .toml:
            return assignments(source, comments: ["#"])
        case .dotenv, .ini, .properties, .generic:
            return assignments(source, comments: ["#", ";"])
        }
    }

    private static func assignments(
        _ source: String,
        comments: [Character]
    ) -> [PreviewStyleSpan] {
        let text = source as NSString
        var spans: [PreviewStyleSpan] = []
        var start = 0
        var level = 0
        let commentMarkers = Set(comments.compactMap { $0.unicodeScalars.first?.value }.map(unichar.init))

        while start < text.length {
            let range = text.lineRange(for: NSRange(location: start, length: 0))
            let lineStart = range.location
            let lineEnd = NSMaxRange(range)
            var contentEnd = lineEnd
            while contentEnd > lineStart {
                let character = text.character(at: contentEnd - 1)
                guard character == 0x0A || character == 0x0D else { break }
                contentEnd -= 1
            }

            var bodyStart = lineStart
            while bodyStart < contentEnd, isHorizontalWhitespace(text.character(at: bodyStart)) {
                bodyStart += 1
            }

            let marker = commentLocation(
                in: text,
                range: NSRange(location: bodyStart, length: contentEnd - bodyStart),
                markers: commentMarkers
            )
            var bodyEnd = marker ?? contentEnd
            while bodyEnd > bodyStart, isHorizontalWhitespace(text.character(at: bodyEnd - 1)) {
                bodyEnd -= 1
            }

            if bodyStart < bodyEnd, !commentMarkers.contains(text.character(at: bodyStart)) {
                if text.character(at: bodyStart) == 0x5B, text.character(at: bodyEnd - 1) == 0x5D {
                    spans.append(PreviewStyleSpan(
                        location: bodyStart,
                        length: bodyEnd - bodyStart,
                        role: .hierarchy(level: level, style: .delimiter)
                    ))
                    level = sectionDepth(in: text, range: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                } else if let separator = firstAssignmentSeparator(in: text, from: bodyStart, to: bodyEnd) {
                    var keyStart = bodyStart
                    var keyEnd = separator
                    while keyStart < keyEnd, isHorizontalWhitespace(text.character(at: keyStart)) { keyStart += 1 }
                    while keyEnd > keyStart, isHorizontalWhitespace(text.character(at: keyEnd - 1)) { keyEnd -= 1 }

                    if keyStart < keyEnd {
                        spans.append(PreviewStyleSpan(
                            location: keyStart,
                            length: keyEnd - keyStart,
                            role: .hierarchy(level: level, style: .key)
                        ))
                        spans.append(PreviewStyleSpan(
                            location: separator,
                            length: 1,
                            role: .hierarchy(level: level, style: .punctuation)
                        ))
                    }
                }
            }

            if let marker {
                spans.append(PreviewStyleSpan(
                    location: marker,
                    length: max(0, contentEnd - marker),
                    role: .comment
                ))
            }
            start = lineEnd
        }
        return spans
    }

    private static func json5(_ source: String) -> [PreviewStyleSpan] {
        let text = source as NSString
        var spans: [PreviewStyleSpan] = []
        var index = 0
        var depth = 0

        while index < text.length {
            let scalar = text.character(at: index)
            if scalar == 0x2F, index + 1 < text.length, text.character(at: index + 1) == 0x2F {
                let end = text.lineRange(for: NSRange(location: index, length: 0)).location
                let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
                spans.append(PreviewStyleSpan(location: index, length: NSMaxRange(lineRange) - index, role: .comment))
                index = max(index + 1, NSMaxRange(lineRange))
                _ = end
                continue
            }
            if scalar == 0x2F, index + 1 < text.length, text.character(at: index + 1) == 0x2A {
                let close = text.range(of: "*/", options: [], range: NSRange(location: index + 2, length: text.length - index - 2))
                let end = close.location == NSNotFound ? text.length : close.location + 2
                spans.append(PreviewStyleSpan(location: index, length: end - index, role: .comment))
                index = end
                continue
            }
            if scalar == 0x7B || scalar == 0x5B {
                spans.append(PreviewStyleSpan(location: index, length: 1, role: .hierarchy(level: depth, style: .delimiter)))
                depth += 1; index += 1; continue
            }
            if scalar == 0x7D || scalar == 0x5D {
                depth = max(0, depth - 1)
                spans.append(PreviewStyleSpan(location: index, length: 1, role: .hierarchy(level: depth, style: .delimiter)))
                index += 1; continue
            }
            if scalar == 0x3A || scalar == 0x2C {
                spans.append(PreviewStyleSpan(location: index, length: 1, role: .hierarchy(level: depth, style: .punctuation)))
                index += 1; continue
            }
            if scalar == 0x22 || scalar == 0x27 {
                let quote = scalar; let start = index; index += 1
                while index < text.length {
                    let next = text.character(at: index)
                    if next == 0x5C { index = min(text.length, index + 2); continue }
                    index += 1
                    if next == quote { break }
                }
                let next = firstNonWhitespace(after: index, in: text)
                spans.append(PreviewStyleSpan(location: start, length: index - start, role: .hierarchy(level: depth, style: next < text.length && text.character(at: next) == 0x3A ? .key : .value)))
                continue
            }
            if CharacterSet.letters.contains(UnicodeScalar(scalar) ?? UnicodeScalar(0x20)!) || scalar == 0x5F || scalar == 0x24 {
                let start = index; index += 1
                while index < text.length {
                    let next = text.character(at: index)
                    guard CharacterSet.alphanumerics.contains(UnicodeScalar(next) ?? UnicodeScalar(0x20)!) || next == 0x5F || next == 0x24 else { break }
                    index += 1
                }
                let next = firstNonWhitespace(after: index, in: text)
                spans.append(PreviewStyleSpan(location: start, length: index - start, role: .hierarchy(level: depth, style: next < text.length && text.character(at: next) == 0x3A ? .key : .value)))
                continue
            }
            index += 1
        }
        return spans
    }

    private static func commentLocation(in text: NSString, range: NSRange, markers: Set<unichar>) -> Int? {
        var quote: unichar?
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            let character = text.character(at: index)
            if character == 0x5C, quote != nil, index + 1 < end {
                index += 2
                continue
            }
            if character == 0x22 || character == 0x27 {
                quote = quote == character ? nil : (quote ?? character)
            } else if quote == nil && markers.contains(character) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func firstAssignmentSeparator(in text: NSString, from start: Int, to end: Int) -> Int? {
        var quote: unichar?
        var index = start
        while index < end {
            let character = text.character(at: index)
            if character == 0x5C, quote != nil, index + 1 < end {
                index += 2
                continue
            }
            if character == 0x22 || character == 0x27 {
                quote = quote == character ? nil : (quote ?? character)
            } else if quote == nil && (character == 0x3D || character == 0x3A) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func sectionDepth(in text: NSString, range: NSRange) -> Int {
        var separators = 0
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            if text.character(at: index) == 0x2E { separators += 1 }
            index += 1
        }
        return separators
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    private static func firstNonWhitespace(after index: Int, in source: NSString) -> Int {
        var value = index
        while value < source.length, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: value)) ?? UnicodeScalar(0x20)!) {
            value += 1
        }
        return value
    }
}
