import AppKit
import Quartz

@MainActor
open class BasePreviewViewController: NSViewController, QLPreviewingController {
    open var previewFormat: PreviewFormat {
        fatalError("Subclasses must provide a preview format")
    }

    private let previewView = NativePreviewView()

    open override func loadView() {
        previewView.setBackgroundTransparent(
            PreviewAppearancePreferences.shared.isTransparent(for: previewFormat)
        )
        view = previewView
        preferredContentSize = NSSize(width: 900, height: 700)
    }

    public func preparePreviewOfFile(at url: URL) async throws {
        let document = await PreviewService.prepare(url: url, as: previewFormat)
        previewView.render(document) { [weak self] attributed in
            self?.finalizeAttributedString(attributed, for: document)
        }
    }

    /// Format-specific targets can replace marked ranges with native content
    /// without forcing their dependencies into every statically linked extension.
    open func finalizeAttributedString(
        _ attributed: NSMutableAttributedString,
        for document: PreviewDocument
    ) {
    }
}

@MainActor
private final class NativePreviewView: NSView {
    private let stackView = NSStackView()
    private let diagnosticContainer = NSVisualEffectView()
    private let diagnosticIcon = NSImageView()
    private let diagnosticLabel = NSTextField(wrappingLabelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var isBackgroundTransparent = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setBackgroundTransparent(_ isTransparent: Bool) {
        isBackgroundTransparent = isTransparent
        let backgroundColor: NSColor = isTransparent ? .clear : .textBackgroundColor

        layer?.backgroundColor = backgroundColor.cgColor
        scrollView.drawsBackground = !isTransparent
        scrollView.backgroundColor = backgroundColor
        scrollView.contentView.drawsBackground = !isTransparent
        scrollView.contentView.backgroundColor = backgroundColor
        textView.drawsBackground = !isTransparent
        textView.backgroundColor = backgroundColor
    }

    func render(
        _ document: PreviewDocument,
        finalize: (NSMutableAttributedString) -> Void
    ) {
        let attributed = makeAttributedString(for: document)
        finalize(attributed)
        textView.textStorage?.setAttributedString(attributed)
        textView.scrollToBeginningOfDocument(nil)

        if let diagnostic = document.diagnostic {
            diagnosticContainer.isHidden = false
            diagnosticIcon.image = NSImage(
                systemSymbolName: diagnostic.severity == .error
                    ? "exclamationmark.triangle.fill"
                    : "info.circle.fill",
                accessibilityDescription: nil
            )
            diagnosticIcon.contentTintColor = diagnostic.severity == .error
                ? .systemRed
                : .systemOrange

            var message = diagnostic.message
            if let line = diagnostic.line, let column = diagnostic.column {
                message += " — Line \(line), Column \(column)"
            }
            diagnosticLabel.stringValue = message
        } else {
            diagnosticContainer.isHidden = true
        }
    }

    private func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        diagnosticContainer.material = .headerView
        diagnosticContainer.blendingMode = .withinWindow
        diagnosticContainer.state = .active
        diagnosticContainer.isHidden = true
        diagnosticContainer.translatesAutoresizingMaskIntoConstraints = false

        diagnosticIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        diagnosticIcon.translatesAutoresizingMaskIntoConstraints = false

        diagnosticLabel.font = .systemFont(ofSize: 13, weight: .medium)
        diagnosticLabel.maximumNumberOfLines = 3
        diagnosticLabel.translatesAutoresizingMaskIntoConstraints = false

        diagnosticContainer.addSubview(diagnosticIcon)
        diagnosticContainer.addSubview(diagnosticLabel)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 32, height: 28)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView

        stackView.addArrangedSubview(diagnosticContainer)
        stackView.addArrangedSubview(scrollView)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            diagnosticContainer.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            diagnosticContainer.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            diagnosticIcon.leadingAnchor.constraint(equalTo: diagnosticContainer.leadingAnchor, constant: 16),
            diagnosticIcon.centerYAnchor.constraint(equalTo: diagnosticContainer.centerYAnchor),
            diagnosticIcon.widthAnchor.constraint(equalToConstant: 18),
            diagnosticIcon.heightAnchor.constraint(equalToConstant: 18),
            diagnosticLabel.leadingAnchor.constraint(equalTo: diagnosticIcon.trailingAnchor, constant: 10),
            diagnosticLabel.trailingAnchor.constraint(equalTo: diagnosticContainer.trailingAnchor, constant: -16),
            diagnosticLabel.topAnchor.constraint(equalTo: diagnosticContainer.topAnchor, constant: 10),
            diagnosticLabel.bottomAnchor.constraint(equalTo: diagnosticContainer.bottomAnchor, constant: -10),
            scrollView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
        ])
    }

    private func makeAttributedString(for document: PreviewDocument) -> NSMutableAttributedString {
        let baseFont: NSFont = document.format == .markdown
            ? .systemFont(ofSize: 15)
            : .monospacedSystemFont(ofSize: 13, weight: .regular)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = document.format == .markdown ? 3 : 1
        paragraphStyle.paragraphSpacing = document.format == .markdown ? 7 : 0
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributed = NSMutableAttributedString(
            string: document.content,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
        )

        var textTables: [Int: NSTextTable] = [:]

        // Text blocks and tables establish paragraph layout. Apply them before
        // inline font and syntax attributes so later spans can refine styling.
        for span in document.spans where span.role.isParagraphLayout {
            let range = NSRange(location: span.location, length: span.length)
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= attributed.length else {
                continue
            }
            applyParagraphLayout(
                span.role,
                to: range,
                in: attributed,
                baseFont: baseFont,
                textTables: &textTables
            )
        }

        for span in document.spans where !span.role.isParagraphLayout {
            let range = NSRange(location: span.location, length: span.length)
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= attributed.length else {
                continue
            }
            apply(span.role, to: range, in: attributed, baseFont: baseFont)
        }

        if let line = document.diagnostic?.line,
           let range = lineRange(line, in: document.content) {
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor.systemRed.withAlphaComponent(0.14),
                range: range
            )
        }

        return attributed
    }

    private func apply(
        _ role: PreviewStyleRole,
        to range: NSRange,
        in attributed: NSMutableAttributedString,
        baseFont: NSFont
    ) {
        switch role {
        case .heading(let level):
            let sizes: [CGFloat] = [30, 24, 20, 18, 16, 15]
            attributed.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: sizes[min(max(level - 1, 0), 5)], weight: .semibold),
                range: range
            )
        case .strong:
            addFontTrait(.boldFontMask, range: range, attributed: attributed, fallback: baseFont)
        case .emphasis:
            addFontTrait(.italicFontMask, range: range, attributed: attributed, fallback: baseFont)
        case .strikethrough:
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode:
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: max(12, baseFont.pointSize - 1), weight: .regular),
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18),
            ], range: range)
        case .codeBlock, .tableCell:
            break
        case .codeLanguage:
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: range)
        case .math(_, let display):
            attributed.addAttributes([
                .font: display
                    ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                    : NSFont.monospacedSystemFont(ofSize: max(12, baseFont.pointSize - 1), weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: range)
        case .mermaid:
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.14),
            ], range: range)
        case .quote:
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .listMarker:
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .link(let destination):
            attributed.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
            if let destination, let url = URL(string: destination) {
                attributed.addAttribute(.link, value: url, range: range)
            }
        case .imagePlaceholder:
            attributed.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium),
            ], range: range)
        case .key:
            attributed.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
        case .string:
            attributed.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
        case .number:
            attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
        case .boolean:
            attributed.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
        case .null:
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .comment:
            attributed.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: range)
        case .keyword:
            attributed.addAttributes([
                .foregroundColor: NSColor.systemIndigo,
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium),
            ], range: range)
        case .punctuation:
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .hierarchy(let level, let style):
            let color = hierarchyColor(for: level)

            switch style {
            case .delimiter:
                attributed.addAttributes([
                    .foregroundColor: color,
                    .font: NSFont.monospacedSystemFont(
                        ofSize: baseFont.pointSize,
                        weight: .semibold
                    ),
                ], range: range)
            case .key:
                attributed.addAttributes([
                    .foregroundColor: color,
                    .font: NSFont.monospacedSystemFont(
                        ofSize: baseFont.pointSize,
                        weight: .medium
                    ),
                ], range: range)
            case .value:
                attributed.addAttribute(
                    .foregroundColor,
                    value: NSColor.labelColor,
                    range: range
                )
            case .punctuation:
                attributed.addAttribute(
                    .foregroundColor,
                    value: color.withAlphaComponent(0.78),
                    range: range
                )
            }
        }
    }

    private func hierarchyColor(for level: Int) -> NSColor {
        let palette: [NSColor] = [
            .systemPurple,
            .systemBlue,
            .systemTeal,
            .systemGreen,
            .systemOrange,
            .systemPink,
        ]
        return palette[max(0, level) % palette.count]
    }

    private func applyParagraphLayout(
        _ role: PreviewStyleRole,
        to range: NSRange,
        in attributed: NSMutableAttributedString,
        baseFont: NSFont,
        textTables: inout [Int: NSTextTable]
    ) {
        switch role {
        case .codeBlock:
            let block = NSTextBlock()
            block.backgroundColor = NSColor.textColor.withAlphaComponent(0.065)
            block.setBorderColor(NSColor.separatorColor.withAlphaComponent(0.8))
            block.setWidth(10, type: .absolute, for: .padding)
            block.setWidth(1, type: .absolute, for: .border)
            block.setWidth(4, type: .absolute, for: .margin)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 0
            paragraph.lineBreakMode = .byClipping
            paragraph.textBlocks = [block]

            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .paragraphStyle: paragraph,
            ], range: range)

        case let .tableCell(identifier, row, column, columnCount, isHeader):
            let table: NSTextTable
            if let existing = textTables[identifier] {
                table = existing
            } else {
                let created = NSTextTable()
                created.numberOfColumns = max(1, columnCount)
                created.layoutAlgorithm = .automatic
                created.collapsesBorders = true
                created.hidesEmptyCells = false
                textTables[identifier] = created
                table = created
            }

            let cell = NSTextTableBlock(
                table: table,
                startingRow: row,
                rowSpan: 1,
                startingColumn: column,
                columnSpan: 1
            )
            cell.verticalAlignment = .middle
            cell.backgroundColor = isHeader
                ? NSColor.textColor.withAlphaComponent(0.09)
                : (isBackgroundTransparent ? .clear : .textBackgroundColor)
            cell.setBorderColor(NSColor.separatorColor)
            cell.setWidth(8, type: .absolute, for: .padding)
            cell.setWidth(1, type: .absolute, for: .border)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 1
            paragraph.paragraphSpacing = 0
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.textBlocks = [cell]
            attributed.addAttribute(.paragraphStyle, value: paragraph, range: range)

            if isHeader {
                addFontTrait(.boldFontMask, range: range, attributed: attributed, fallback: baseFont)
            }

        default:
            break
        }
    }

    private func addFontTrait(
        _ trait: NSFontTraitMask,
        range: NSRange,
        attributed: NSMutableAttributedString,
        fallback: NSFont
    ) {
        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? fallback
            attributed.addAttribute(
                .font,
                value: NSFontManager.shared.convert(font, toHaveTrait: trait),
                range: subrange
            )
        }
    }

    private func lineRange(_ requestedLine: Int, in content: String) -> NSRange? {
        guard requestedLine > 0 else { return nil }
        let nsContent = content as NSString
        var currentLine = 1
        var location = 0

        while location < nsContent.length {
            let range = nsContent.lineRange(for: NSRange(location: location, length: 0))
            if currentLine == requestedLine { return range }
            currentLine += 1
            location = NSMaxRange(range)
        }

        return nil
    }
}

private extension PreviewStyleRole {
    var isParagraphLayout: Bool {
        switch self {
        case .codeBlock, .tableCell:
            true
        default:
            false
        }
    }
}
