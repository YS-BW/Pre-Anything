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
                    isLimited: true
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
