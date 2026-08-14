import Foundation

enum XMLPreviewRenderer {
    static func render(source: String, byteCount: Int) -> PreviewDocument {
        let delegate = XMLValidationDelegate()
        let parser = XMLParser(data: Data(source.utf8))
        parser.delegate = delegate
        let isValid = parser.parse()

        let diagnostic: PreviewDiagnostic?
        if isValid {
            diagnostic = nil
        } else {
            diagnostic = PreviewDiagnostic(
                severity: .error,
                message: delegate.message ?? parser.parserError?.localizedDescription ?? "Malformed XML.",
                line: max(1, parser.lineNumber),
                column: max(1, parser.columnNumber)
            )
        }

        return PreviewDocument(
            format: .xml,
            content: source,
            spans: XMLSourceHighlighter.highlight(source),
            diagnostic: diagnostic,
            byteCount: byteCount
        )
    }
}

private final class XMLValidationDelegate: NSObject, XMLParserDelegate {
    var message: String?

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        message = parseError.localizedDescription
    }
}

enum XMLSourceHighlighter {
    static func highlight(_ source: String) -> [PreviewStyleSpan] {
        let range = NSRange(location: 0, length: source.utf16.count)
        var spans: [PreviewStyleSpan] = []
        let protectedRanges = ranges(
            matching: #"(?s)<!--.*?-->|<!\[CDATA\[.*?\]\]>"#,
            in: source,
            range: range
        )
        add(#"(?s)<!--.*?-->"#, role: .comment, source: source, range: range, spans: &spans)
        add(#"(?s)<!\[CDATA\[.*?\]\]>"#, role: .string, source: source, range: range, spans: &spans)
        add(#"&(?:#\d+|#x[0-9A-Fa-f]+|[A-Za-z_:][A-Za-z0-9_.:-]*);"#, role: .attribute, source: source, range: range, spans: &spans)

        guard let expression = try? NSRegularExpression(pattern: #"</?([A-Za-z_][A-Za-z0-9_.:-]*)([^<>]*)/?>"#) else {
            return spans
        }
        let nsSource = source as NSString
        for match in expression.matches(in: source, range: range) {
            guard !protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                continue
            }
            spans.append(PreviewStyleSpan(location: match.range.location, length: 1, role: .punctuation))
            let name = match.range(at: 1)
            spans.append(PreviewStyleSpan(location: name.location, length: name.length, role: .keyword))
            let attributes = match.range(at: 2)
            guard attributes.length > 0 else { continue }
            let text = nsSource.substring(with: attributes)
            guard let attributeExpression = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9_.:-]*)(\s*=\s*)(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')"#) else { continue }
            for attribute in attributeExpression.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
                let key = attribute.range(at: 1)
                let value = attribute.range(at: 3)
                spans.append(PreviewStyleSpan(location: attributes.location + key.location, length: key.length, role: .attribute))
                spans.append(PreviewStyleSpan(location: attributes.location + value.location, length: value.length, role: .string))
            }
        }
        return spans
    }

    private static func add(_ pattern: String, role: PreviewStyleRole, source: String, range: NSRange, spans: inout [PreviewStyleSpan]) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        for match in expression.matches(in: source, range: range) {
            spans.append(PreviewStyleSpan(location: match.range.location, length: match.range.length, role: role))
        }
    }

    private static func ranges(matching pattern: String, in source: String, range: NSRange) -> [NSRange] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: source, range: range).map(\.range)
    }
}
