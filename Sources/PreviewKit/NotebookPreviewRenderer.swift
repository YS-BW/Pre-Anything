import Foundation

enum NotebookPreviewRenderer {
    private static let maximumCells = 200
    private static let maximumImageBytes = 2 * 1_024 * 1_024
    private static let maximumTotalImageBytes = 8 * 1_024 * 1_024

    static func render(source: String, byteCount: Int) -> PreviewDocument {
        do {
            guard let root = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any],
                  let cells = root["cells"] as? [[String: Any]] else {
                return invalid(source: source, byteCount: byteCount, message: "This is not a Jupyter notebook.")
            }

            let language = language(from: root)
            var builder = Builder(byteCount: byteCount, language: language)
            for (index, cell) in cells.prefix(maximumCells).enumerated() {
                builder.append(cell: cell, index: index + 1)
            }
            if cells.count > maximumCells {
                builder.appendNotice("Notebook has more than \(maximumCells) cells — remaining cells were not rendered.")
            }
            return builder.document()
        } catch {
            return invalid(source: source, byteCount: byteCount, message: error.localizedDescription)
        }
    }

    private static func invalid(source: String, byteCount: Int, message: String) -> PreviewDocument {
        PreviewDocument(
            format: .notebook,
            content: source,
            spans: JSONFallbackHighlighter.highlight(source),
            diagnostic: PreviewDiagnostic(severity: .error, message: "Invalid Jupyter notebook: \(message)"),
            byteCount: byteCount
        )
    }

    private static func language(from root: [String: Any]) -> SourceLanguage {
        let metadata = root["metadata"] as? [String: Any]
        let languageInfo = metadata?["language_info"] as? [String: Any]
        let kernelspec = metadata?["kernelspec"] as? [String: Any]
        let raw = (languageInfo?["name"] as? String) ?? (kernelspec?["language"] as? String) ?? ""
        return SourceLanguage.language(forName: raw)
    }

    private struct Builder {
        var content = ""
        var spans: [PreviewStyleSpan] = []
        let byteCount: Int
        let language: SourceLanguage
        var imageBytes = 0

        mutating func append(cell: [String: Any], index: Int) {
            let type = cell["cell_type"] as? String ?? "unknown"
            switch type {
            case "markdown":
                appendHeading("Markdown \(index)")
                appendMarkdown(source(from: cell["source"]))
            case "code":
                appendHeading("Code \(index) · \(language.rawValue)")
                appendCode(source(from: cell["source"]))
                for output in (cell["outputs"] as? [[String: Any]] ?? []) {
                    append(output: output)
                }
            case "raw":
                appendHeading("Raw \(index)")
                appendCode(source(from: cell["source"]))
            default:
                appendNotice("Unsupported notebook cell type: \(type)")
            }
        }

        mutating func appendNotice(_ text: String) {
            let start = content.utf16.count
            content += "\(text)\n\n"
            spans.append(PreviewStyleSpan(location: start, length: text.utf16.count, role: .quote))
        }

        mutating func appendHeading(_ text: String) {
            let start = content.utf16.count
            content += "\(text)\n"
            spans.append(PreviewStyleSpan(location: start, length: text.utf16.count, role: .heading(5)))
        }

        mutating func appendMarkdown(_ source: String) {
            let rendered = MarkdownPreviewRenderer.render(source: source, byteCount: source.utf8.count)
            append(document: rendered)
            content += "\n"
        }

        mutating func appendCode(_ source: String) {
            guard !source.isEmpty else { return }
            let start = content.utf16.count
            content += source
            if !source.hasSuffix("\n") { content += "\n" }
            spans.append(PreviewStyleSpan(location: start, length: source.utf16.count, role: .codeBlock))
            for span in NativeCodeHighlighter.spans(source: source, language: language.rawValue) {
                spans.append(PreviewStyleSpan(location: start + span.location, length: span.length, role: span.role))
            }
            content += "\n"
        }

        mutating func append(output: [String: Any]) {
            let type = output["output_type"] as? String ?? "output"
            switch type {
            case "stream":
                appendHeading("Output")
                appendCode(source(from: output["text"]))
            case "error":
                appendHeading("Error output")
                appendCode(source(from: output["traceback"]))
            case "execute_result", "display_data":
                guard let data = output["data"] as? [String: Any] else { return }
                if let text = data["text/plain"] {
                    appendHeading("Output")
                    appendCode(source(from: text))
                }
                appendImage(data["image/png"], mimeType: "image/png")
                appendImage(data["image/jpeg"], mimeType: "image/jpeg")
                if data["text/html"] != nil || data["application/javascript"] != nil || data["image/svg+xml"] != nil {
                    appendNotice("HTML, JavaScript, and SVG output were omitted for safety.")
                }
            default:
                appendNotice("Notebook output type \(type) was omitted.")
            }
        }

        mutating func appendImage(_ value: Any?, mimeType: String) {
            let encoded = source(from: value)
            guard !encoded.isEmpty, let data = Data(base64Encoded: encoded) else { return }
            guard data.count <= NotebookPreviewRenderer.maximumImageBytes else {
                appendNotice("Embedded image exceeds 2 MiB and was omitted.")
                return
            }
            guard imageBytes + data.count <= NotebookPreviewRenderer.maximumTotalImageBytes else {
                appendNotice("Notebook image limit reached; remaining images were omitted.")
                return
            }
            imageBytes += data.count
            appendHeading("Image output")
            let location = content.utf16.count
            content += "\u{FFFC}\n\n"
            spans.append(PreviewStyleSpan(location: location, length: 1, role: .notebookImage(data, mimeType: mimeType)))
        }

        mutating func append(document: PreviewDocument) {
            let offset = content.utf16.count
            content += document.content
            for span in document.spans {
                spans.append(PreviewStyleSpan(location: offset + span.location, length: span.length, role: span.role))
            }
        }

        func document() -> PreviewDocument {
            PreviewDocument(format: .notebook, content: content, spans: spans, byteCount: byteCount)
        }

        private func source(from value: Any?) -> String {
            switch value {
            case let string as String:
                return string
            case let strings as [String]:
                return strings.joined()
            default:
                return ""
            }
        }
    }
}
