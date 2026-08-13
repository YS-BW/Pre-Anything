import Foundation
import Markdown

enum MarkdownPreviewRenderer {
    static func render(source: String, byteCount: Int) -> PreviewDocument {
        let document = Document(parsing: source, options: [.disableSmartOpts])
        var renderer = NativeMarkdownRenderer(source: source)
        renderer.renderBlocks(document.children, indentation: 0)
        renderer.trimTrailingWhitespace()

        return PreviewDocument(
            format: .markdown,
            content: renderer.content,
            spans: renderer.spans,
            byteCount: byteCount
        )
    }
}

private struct NativeMarkdownRenderer {
    private(set) var content = ""
    private(set) var spans: [PreviewStyleSpan] = []
    private var nextTableIdentifier = 0
    private let sourceLines: [Substring]?

    init(source: String? = nil) {
        sourceLines = source?.split(separator: "\n", omittingEmptySubsequences: false)
    }

    mutating func renderBlocks(_ blocks: MarkupChildren, indentation: Int) {
        for block in blocks {
            renderBlock(block, indentation: indentation)
        }
    }

    mutating func renderBlock(_ markup: Markup, indentation: Int) {
        switch markup {
        case let heading as Heading:
            let start = utf16Count
            renderInlines(heading.children)
            addStyle(from: start, role: .heading(heading.level))
            endBlock()

        case let paragraph as Paragraph:
            if let math = displayMath(in: paragraph) {
                append(math.fallback, role: .math(source: math.source, display: true))
            } else {
                renderInlines(paragraph.children)
            }
            endBlock()

        case let codeBlock as CodeBlock:
            let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
            if language?.lowercased() == "mermaid" {
                append(codeBlock.code, role: .mermaid(source: codeBlock.code))
                endBlock()
                return
            }
            let blockStart = utf16Count
            if let language, !language.isEmpty {
                append(language.uppercased() + "\n", role: .codeLanguage)
            }
            appendHighlightedCode(codeBlock.code, language: language)
            if !content.hasSuffix("\n") { append("\n") }
            addStyle(from: blockStart, role: .codeBlock)
            ensureBlankLine()

        case let html as HTMLBlock:
            append(html.rawHTML, role: .codeBlock)
            endBlock()

        case let quote as BlockQuote:
            let start = utf16Count
            append("▎ ", role: .quote)
            renderBlocks(quote.children, indentation: indentation)
            addStyle(from: start, role: .quote)

        case let list as UnorderedList:
            renderList(list.children, orderedStart: nil, indentation: indentation)
            ensureBlankLine()

        case let list as OrderedList:
            renderList(list.children, orderedStart: Int(list.startIndex), indentation: indentation)
            ensureBlankLine()

        case let table as Table:
            renderTable(table)
            ensureBlankLine()

        case is ThematicBreak:
            append("────────────────────────")
            endBlock()

        case let item as ListItem:
            renderListItem(item, marker: "•", indentation: indentation)

        default:
            if markup.childCount > 0 {
                renderBlocks(markup.children, indentation: indentation)
            }
        }
    }

    mutating func renderInlines(_ inlines: MarkupChildren) {
        for inline in inlines {
            renderInline(inline)
        }
    }

    private mutating func renderInline(_ markup: Markup) {
        switch markup {
        case let text as Text:
            renderTextWithMath(text.string)

        case is SoftBreak:
            append(" ")

        case is LineBreak:
            append("\n")

        case let code as InlineCode:
            append(code.code, role: .inlineCode)

        case let html as InlineHTML:
            append(html.rawHTML, role: .inlineCode)

        case let emphasis as Emphasis:
            renderStyledChildren(emphasis.children, role: .emphasis)

        case let strong as Strong:
            renderStyledChildren(strong.children, role: .strong)

        case let strike as Strikethrough:
            renderStyledChildren(strike.children, role: .strikethrough)

        case let link as Link:
            let destination = allowedLink(link.destination)
            renderStyledChildren(link.children, role: .link(destination))

        case let image as Image:
            var altRenderer = NativeMarkdownRenderer()
            altRenderer.renderInlines(image.children)
            let alt = altRenderer.content.isEmpty ? "Image" : altRenderer.content
            append("[\(alt)]", role: .imagePlaceholder)

        default:
            renderInlines(markup.children)
        }
    }

    private mutating func renderStyledChildren(_ children: MarkupChildren, role: PreviewStyleRole) {
        let start = utf16Count
        renderInlines(children)
        addStyle(from: start, role: role)
    }

    private mutating func appendHighlightedCode(_ code: String, language: String?) {
        let start = utf16Count
        append(code)
        for span in NativeCodeHighlighter.spans(source: code, language: language) {
            spans.append(PreviewStyleSpan(
                location: start + span.location,
                length: span.length,
                role: span.role
            ))
        }
    }

    private mutating func renderTextWithMath(_ text: String) {
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let opening = nextMathOpening(in: text, from: cursor) else {
                append(String(text[cursor...]))
                return
            }

            append(String(text[cursor..<opening.index]))
            let contentStart = text.index(opening.index, offsetBy: opening.open.count)
            guard contentStart < text.endIndex,
                  let closing = text.range(of: opening.close, range: contentStart..<text.endIndex),
                  closing.lowerBound > contentStart else {
                append(String(text[opening.index...]))
                return
            }

            let source = String(text[contentStart..<closing.lowerBound])
            if source.first?.isWhitespace == true || source.last?.isWhitespace == true {
                append(String(text[opening.index..<closing.upperBound]))
            } else {
                let fallback = opening.open + source + opening.close
                append(fallback, role: .math(source: source, display: opening.display))
            }
            cursor = closing.upperBound
        }
    }

    private func nextMathOpening(
        in text: String,
        from start: String.Index
    ) -> (index: String.Index, open: String, close: String, display: Bool)? {
        let delimiters: [(String, String, Bool)] = [
            ("$$", "$$", true),
            (#"\("#, #"\)"#, false),
            (#"\["#, #"\]"#, true),
            ("$", "$", false),
        ]

        var best: (String.Index, String, String, Bool)?
        for delimiter in delimiters {
            guard let range = text.range(of: delimiter.0, range: start..<text.endIndex) else { continue }
            if delimiter.0 == "$", range.upperBound < text.endIndex, text[range.upperBound] == "$" {
                continue
            }
            if let current = best, current.0 <= range.lowerBound { continue }
            best = (range.lowerBound, delimiter.0, delimiter.1, delimiter.2)
        }
        return best.map { (index: $0.0, open: $0.1, close: $0.2, display: $0.3) }
    }

    private func displayMath(in paragraph: Paragraph) -> (source: String, fallback: String)? {
        let parsedText = plainText(paragraph.children)
        guard let raw = (rawSource(for: paragraph) ?? parsedText)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let pairs = [("$$", "$$"), (#"\["#, #"\]"#)]
        for pair in pairs where raw.hasPrefix(pair.0) && raw.hasSuffix(pair.1) {
            let start = raw.index(raw.startIndex, offsetBy: pair.0.count)
            let end = raw.index(raw.endIndex, offsetBy: -pair.1.count)
            guard start <= end else { continue }
            let source = String(raw[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            return (source, pair.0 + source + pair.1)
        }
        return nil
    }

    /// CommonMark treats `\\` as an escaped backslash. That is correct for
    /// prose, but corrupts LaTeX matrix row separators before SwiftMath sees
    /// them. Source ranges let display math retain its exact original bytes.
    private func rawSource(for markup: Markup) -> String? {
        guard let sourceLines, let range = markup.range else { return nil }
        let startLine = range.lowerBound.line - 1
        let endLine = range.upperBound.line - 1
        guard sourceLines.indices.contains(startLine),
              sourceLines.indices.contains(endLine),
              startLine <= endLine else {
            return nil
        }

        if startLine == endLine {
            guard let start = stringIndex(
                in: sourceLines[startLine],
                utf8Column: range.lowerBound.column
            ), let end = stringIndex(
                in: sourceLines[endLine],
                utf8Column: range.upperBound.column
            ), start <= end else {
                return nil
            }
            return String(sourceLines[startLine][start..<end])
        }

        guard let start = stringIndex(
            in: sourceLines[startLine],
            utf8Column: range.lowerBound.column
        ), let end = stringIndex(
            in: sourceLines[endLine],
            utf8Column: range.upperBound.column
        ) else {
            return nil
        }

        var lines = [String(sourceLines[startLine][start...])]
        if endLine > startLine + 1 {
            lines.append(contentsOf: sourceLines[(startLine + 1)..<endLine].map(String.init))
        }
        lines.append(String(sourceLines[endLine][..<end]))
        return lines.joined(separator: "\n")
    }

    private func stringIndex(in line: Substring, utf8Column: Int) -> String.Index? {
        guard utf8Column >= 1,
              let utf8Index = line.utf8.index(
                line.utf8.startIndex,
                offsetBy: utf8Column - 1,
                limitedBy: line.utf8.endIndex
              ) else {
            return nil
        }
        return String.Index(utf8Index, within: line)
    }

    private func plainText(_ children: MarkupChildren) -> String? {
        var result = ""
        for child in children {
            switch child {
            case let text as Text:
                result += text.string
            case is SoftBreak, is LineBreak:
                result += "\n"
            default:
                return nil
            }
        }
        return result
    }

    private mutating func renderList(
        _ items: MarkupChildren,
        orderedStart: Int?,
        indentation: Int
    ) {
        var number = orderedStart ?? 0
        for child in items {
            guard let item = child as? ListItem else { continue }
            let marker: String
            if orderedStart != nil {
                marker = "\(number)."
                number += 1
            } else if let checkbox = item.checkbox {
                marker = checkbox == .checked ? "☑" : "☐"
            } else {
                marker = "•"
            }
            renderListItem(item, marker: marker, indentation: indentation)
        }
    }

    private mutating func renderListItem(_ item: ListItem, marker: String, indentation: Int) {
        append(String(repeating: "  ", count: indentation))
        append(marker + " ", role: .listMarker)

        var isFirstBlock = true
        for child in item.children {
            if let paragraph = child as? Paragraph {
                if !isFirstBlock {
                    append(String(repeating: "  ", count: indentation + 1))
                }
                renderInlines(paragraph.children)
                append("\n")
            } else if child is UnorderedList || child is OrderedList {
                renderBlock(child, indentation: indentation + 1)
            } else {
                renderBlock(child, indentation: indentation + 1)
            }
            isFirstBlock = false
        }

        if isFirstBlock { append("\n") }
    }

    private mutating func renderTable(_ table: Table) {
        let bodyRows = Array(table.body.children).compactMap { $0 as? Table.Row }
        let identifier = nextTableIdentifier
        nextTableIdentifier += 1

        renderTableCells(
            table.head.children,
            table: identifier,
            row: 0,
            isHeader: true
        )
        for (index, row) in bodyRows.enumerated() {
            renderTableCells(
                row.children,
                table: identifier,
                row: index + 1,
                isHeader: false
            )
        }
    }

    private mutating func renderTableCells(
        _ children: MarkupChildren,
        table identifier: Int,
        row: Int,
        isHeader: Bool
    ) {
        let cells = Array(children).compactMap { $0 as? Table.Cell }
        for (index, cell) in cells.enumerated() {
            let start = utf16Count
            renderInlines(cell.children)
            if start == utf16Count { append(" ") }
            append("\n")
            addStyle(
                from: start,
                role: .tableCell(
                    table: identifier,
                    row: row,
                    column: index,
                    columnCount: cells.count,
                    isHeader: isHeader
                )
            )
        }
    }

    private func allowedLink(_ destination: String?) -> String? {
        guard let destination,
              let components = URLComponents(string: destination) else {
            return nil
        }

        if components.scheme == nil {
            return nil
        }

        let allowedSchemes = ["https", "http", "mailto"]
        return allowedSchemes.contains(components.scheme?.lowercased() ?? "") ? destination : nil
    }

    private mutating func append(_ value: String, role: PreviewStyleRole? = nil) {
        let location = utf16Count
        content += value
        if let role, !value.isEmpty {
            spans.append(PreviewStyleSpan(
                location: location,
                length: value.utf16.count,
                role: role
            ))
        }
    }

    private mutating func addStyle(from start: Int, role: PreviewStyleRole) {
        let length = utf16Count - start
        guard length > 0 else { return }
        spans.append(PreviewStyleSpan(location: start, length: length, role: role))
    }

    private mutating func endBlock() {
        if !content.hasSuffix("\n") { append("\n") }
        ensureBlankLine()
    }

    private mutating func ensureBlankLine() {
        if content.isEmpty { return }
        if !content.hasSuffix("\n") { append("\n") }
        if !content.hasSuffix("\n\n") { append("\n") }
    }

    mutating func trimTrailingWhitespace() {
        let trimmed = content.replacingOccurrences(
            of: #"\s+$"#,
            with: "",
            options: .regularExpression
        )
        let newLength = trimmed.utf16.count
        content = trimmed
        spans = spans.compactMap { span in
            guard span.location < newLength else { return nil }
            let length = min(span.length, newLength - span.location)
            return PreviewStyleSpan(location: span.location, length: length, role: span.role)
        }
    }

    private var utf16Count: Int { content.utf16.count }
}
