import AppKit
import BeautifulMermaid
import PreviewKit
import SwiftMath

@MainActor
enum NativeMarkdownAttachmentRenderer {
    static func render(
        spans: [PreviewStyleSpan],
        in attributed: NSMutableAttributedString,
        appearance: NSAppearance
    ) {
        let embedded = spans.compactMap { span -> (PreviewStyleSpan, NSImage, Bool)? in
            switch span.role {
            case .math(let source, let display):
                guard source.utf8.count <= 64 * 1_024,
                      let image = renderMath(
                        source,
                        display: display,
                        appearance: appearance
                      ) else { return nil }
                return (span, image, display)
            case .mermaid(let source):
                guard source.utf8.count <= 128 * 1_024,
                      let image = renderMermaid(source, appearance: appearance) else { return nil }
                return (span, image, true)
            default:
                return nil
            }
        }
        .sorted { $0.0.location > $1.0.location }

        for (span, image, isBlock) in embedded {
            let range = NSRange(location: span.location, length: span.length)
            guard range.length > 0, NSMaxRange(range) <= attributed.length else { continue }

            let attachment = NSTextAttachment()
            attachment.attachmentCell = NSTextAttachmentCell(
                imageCell: scaled(image, maximumWidth: 760, maximumHeight: 520)
            )
            let replacement = NSMutableAttributedString(attachment: attachment)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = isBlock ? .center : .natural
            paragraph.paragraphSpacingBefore = isBlock ? 10 : 0
            paragraph.paragraphSpacing = isBlock ? 12 : 0
            replacement.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: 0, length: replacement.length)
            )
            if !isBlock {
                replacement.addAttribute(
                    .baselineOffset,
                    value: -2,
                    range: NSRange(location: 0, length: replacement.length)
                )
            }
            attributed.replaceCharacters(in: range, with: replacement)
        }
    }

    private static func renderMath(
        _ source: String,
        display: Bool,
        appearance: NSAppearance
    ) -> NSImage? {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // SwiftMath converts some glyph runs to CGColor immediately and draws
        // other symbols later. A dynamic labelColor therefore resolves against
        // two different appearances. Use one concrete color for the whole image.
        let textColor = NSColor(
            calibratedWhite: isDark ? 0.94 : 0.10,
            alpha: 1
        )
        let renderer = MTMathImage(
            latex: source,
            fontSize: display ? 22 : 16,
            textColor: textColor,
            labelMode: display ? .display : .text,
            textAlignment: display ? .center : .left
        )
        renderer.contentInsets = MTEdgeInsets(
            top: 3,
            left: display ? 8 : 2,
            bottom: 3,
            right: display ? 8 : 2
        )
        return renderer.asImage().1
    }

    private static func renderMermaid(_ source: String, appearance: NSAppearance) -> NSImage? {
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        let theme: DiagramTheme = match == .darkAqua ? .githubDark : .githubLight
        guard let image = try? MermaidRenderer.renderImage(source: source, theme: theme, scale: 2) else {
            return nil
        }
        return verticallyFlipped(image)
    }

    /// BeautifulMermaid 1.0.4 renders its macOS bitmap in Quartz's bottom-left
    /// coordinate system even though DiagramRenderer emits top-left coordinates.
    private static func verticallyFlipped(_ image: NSImage) -> NSImage {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ), let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return image
        }

        let pixelRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.translateBy(x: 0, y: CGFloat(source.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(source, in: pixelRect)

        guard let corrected = context.makeImage() else { return image }
        return NSImage(cgImage: corrected, size: image.size)
    }

    private static func scaled(
        _ image: NSImage,
        maximumWidth: CGFloat,
        maximumHeight: CGFloat
    ) -> NSImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }
        let scale = min(1, maximumWidth / image.size.width, maximumHeight / image.size.height)
        guard scale < 1 else { return image }

        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return copy
    }
}
