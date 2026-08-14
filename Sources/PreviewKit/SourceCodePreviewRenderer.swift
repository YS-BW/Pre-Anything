import Foundation

enum SourceCodePreviewRenderer {
    static func render(
        source: String,
        byteCount: Int,
        language: SourceLanguage
    ) -> PreviewDocument {
        PreviewDocument(
            format: .sourceCode,
            content: source,
            spans: NativeCodeHighlighter.spans(
                source: source,
                language: language.rawValue
            ),
            byteCount: byteCount
        )
    }
}
