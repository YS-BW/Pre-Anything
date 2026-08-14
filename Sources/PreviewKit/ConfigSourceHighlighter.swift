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

        while start < text.length {
            let range = text.lineRange(for: NSRange(location: start, length: 0))
            let line = text.substring(with: range)
            let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyOffset = range.location + (line as NSString).range(of: body).location

            if body.hasPrefix("[") && body.hasSuffix("]") {
                let nameRange = NSRange(location: bodyOffset, length: (body as NSString).length)
                spans.append(PreviewStyleSpan(location: nameRange.location, length: nameRange.length, role: .hierarchy(level: level, style: .delimiter)))
                let path = body.dropFirst().dropLast().split(separator: ".")
                level = max(0, path.count - 1)
            } else if !body.isEmpty, let first = body.first, !comments.contains(first) {
                let nsLine = line as NSString
                let equals = nsLine.range(of: "=")
                let colon = nsLine.range(of: ":")
                let separator: NSRange
                if equals.location == NSNotFound { separator = colon }
                else if colon.location == NSNotFound { separator = equals }
                else { separator = equals.location < colon.location ? equals : colon }

                if separator.location != NSNotFound {
                    let rawKey = nsLine.substring(with: NSRange(location: 0, length: separator.location))
                        .trimmingCharacters(in: .whitespaces)
                    if !rawKey.isEmpty, let keyLocation = line.range(of: rawKey)?.lowerBound {
                        let offset = line.distance(from: line.startIndex, to: keyLocation)
                        spans.append(PreviewStyleSpan(
                            location: range.location + (line as NSString).substring(to: offset).utf16.count,
                            length: rawKey.utf16.count,
                            role: .hierarchy(level: level, style: .key)
                        ))
                        spans.append(PreviewStyleSpan(
                            location: range.location + separator.location,
                            length: separator.length,
                            role: .hierarchy(level: level, style: .punctuation)
                        ))
                    }
                }
            }

            if let marker = commentLocation(in: line, markers: comments) {
                spans.append(PreviewStyleSpan(
                    location: range.location + marker,
                    length: max(0, (line as NSString).length - marker),
                    role: .comment
                ))
            }
            start = NSMaxRange(range)
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

    private static func commentLocation(in line: String, markers: [Character]) -> Int? {
        var quoted: Character?
        for (offset, character) in line.utf16.enumerated() {
            let scalar = UnicodeScalar(character).map(Character.init) ?? " "
            if scalar == "\"" || scalar == "'" {
                quoted = quoted == scalar ? nil : (quoted ?? scalar)
            } else if quoted == nil && markers.contains(scalar) {
                return offset
            }
        }
        return nil
    }

    private static func firstNonWhitespace(after index: Int, in source: NSString) -> Int {
        var value = index
        while value < source.length, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: value)) ?? UnicodeScalar(0x20)!) {
            value += 1
        }
        return value
    }
}
