import Foundation

public enum PreviewService {
    public static func prepare(url: URL, as format: PreviewFormat) async -> PreviewDocument {
        await Task.detached(priority: .userInitiated) {
            prepareSynchronously(url: url, as: format)
        }.value
    }

    static func prepareSynchronously(url: URL, as format: PreviewFormat) -> PreviewDocument {
        do {
            let loaded = try TextLoader.load(url: url)

            if loaded.isLimited {
                return SourceHighlighter.document(
                    format: format,
                    source: loaded.text,
                    byteCount: loaded.byteCount,
                    diagnostic: loaded.diagnostic,
                    isLimited: true,
                    sourceLanguage: format == .sourceCode
                        ? SourceLanguage.detect(url: url)
                        : nil
                )
            }

            switch format {
            case .markdown:
                return MarkdownPreviewRenderer.render(
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .json:
                return JSONPreviewRenderer.render(
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .yaml:
                return YAMLPreviewRenderer.render(
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .config:
                return SourceHighlighter.document(
                    format: .config,
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .table:
                return SourceHighlighter.document(
                    format: .table,
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .xml:
                return XMLPreviewRenderer.render(
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .notebook:
                return NotebookPreviewRenderer.render(
                    source: loaded.text,
                    byteCount: loaded.byteCount
                )
            case .sourceCode:
                return SourceCodePreviewRenderer.render(
                    source: loaded.text,
                    byteCount: loaded.byteCount,
                    language: SourceLanguage.detect(url: url)
                )
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return PreviewDocument(
                format: format,
                content: "Unable to preview this file.",
                diagnostic: PreviewDiagnostic(severity: .error, message: message),
                byteCount: 0
            )
        }
    }
}
