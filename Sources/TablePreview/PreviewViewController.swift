import AppKit
import PreviewKit
import Quartz

@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController, NSTableViewDataSource, NSTableViewDelegate {
    private let stack = NSStackView()
    private let diagnostic = NSTextField(wrappingLabelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let fallbackText = NSTextView()
    private var document = TablePreviewDocument(headers: [], rows: [], sourceFallback: nil, byteCount: 0, isTruncated: false, diagnostic: nil)

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        let transparent = PreviewAppearancePreferences.shared.isTransparent(for: .table)
        let background: NSColor = transparent ? .clear : .textBackgroundColor
        root.layer?.backgroundColor = background.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        diagnostic.font = .systemFont(ofSize: 13, weight: .medium)
        diagnostic.textColor = .secondaryLabelColor
        diagnostic.maximumNumberOfLines = 3
        diagnostic.isHidden = true
        diagnostic.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = !transparent
        scrollView.backgroundColor = background
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.rowHeight = 26

        fallbackText.isEditable = false
        fallbackText.isSelectable = true
        fallbackText.usesFindBar = true
        fallbackText.drawsBackground = !transparent
        fallbackText.backgroundColor = background
        fallbackText.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        fallbackText.textContainerInset = NSSize(width: 24, height: 24)

        stack.addArrangedSubview(diagnostic)
        stack.addArrangedSubview(scrollView)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            diagnostic.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 16),
            diagnostic.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -16),
        ])
        view = root
        preferredContentSize = NSSize(width: 900, height: 700)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let delimiter: Character = url.pathExtension.lowercased() == "tsv" ? "\t" : ","
        document = await TablePreviewService.prepare(url: url, delimiter: delimiter)
        render()
    }

    @objc func copy(_ sender: Any?) {
        guard document.isTable else {
            fallbackText.copy(sender)
            return
        }
        let selected = tableView.selectedRowIndexes
        guard !selected.isEmpty else { return }
        let rows = selected.compactMap { index in document.rows.indices.contains(index) ? document.rows[index] : nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"), forType: .string)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { document.rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < document.rows.count else { return nil }
        let identifier = tableColumn.identifier
        let field: NSTextField
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            field = existing
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.isSelectable = true
            field.lineBreakMode = .byTruncatingTail
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        let index = tableView.tableColumns.firstIndex(of: tableColumn) ?? 0
        field.stringValue = index < document.rows[row].count ? document.rows[row][index] : ""
        return field
    }

    private func render() {
        if let diagnostic = document.diagnostic {
            self.diagnostic.stringValue = diagnostic.message
                + (diagnostic.line.map { " — Line \($0)" } ?? "")
            self.diagnostic.isHidden = false
        } else {
            diagnostic.isHidden = true
        }

        if let source = document.sourceFallback {
            fallbackText.string = source
            scrollView.documentView = fallbackText
            return
        }

        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        for (index, header) in document.headers.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column-\(index)"))
            column.title = header
            column.width = min(320, max(120, CGFloat(header.count * 8 + 32)))
            column.minWidth = 80
            tableView.addTableColumn(column)
        }
        tableView.reloadData()
        tableView.sizeToFit()
        scrollView.documentView = tableView
    }
}
