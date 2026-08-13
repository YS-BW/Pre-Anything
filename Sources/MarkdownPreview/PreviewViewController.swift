import Foundation
import PreviewKit

final class PreviewViewController: BasePreviewViewController {
    override var previewFormat: PreviewFormat { .markdown }

    override func finalizeAttributedString(
        _ attributed: NSMutableAttributedString,
        for document: PreviewDocument
    ) {
        NativeMarkdownAttachmentRenderer.render(
            spans: document.spans,
            in: attributed,
            appearance: view.effectiveAppearance
        )
    }
}
