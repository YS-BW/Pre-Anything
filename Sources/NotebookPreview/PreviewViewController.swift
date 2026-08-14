import AppKit
import PreviewKit

final class PreviewViewController: BasePreviewViewController {
    override var previewFormat: PreviewFormat { .notebook }

    override func finalizeAttributedString(_ attributed: NSMutableAttributedString, for document: PreviewDocument) {
        let images = document.spans.compactMap { span -> (PreviewStyleSpan, NSImage)? in
            guard case let .notebookImage(data, _) = span.role, let image = NSImage(data: data) else { return nil }
            return (span, image)
        }.sorted { $0.0.location > $1.0.location }

        for (span, image) in images {
            let range = NSRange(location: span.location, length: span.length)
            guard NSMaxRange(range) <= attributed.length else { continue }
            let attachment = NSTextAttachment()
            attachment.image = image
            let ratio = min(1, 620 / max(1, image.size.width))
            attachment.bounds = NSRect(x: 0, y: -4, width: image.size.width * ratio, height: image.size.height * ratio)
            attributed.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
        }
    }
}
