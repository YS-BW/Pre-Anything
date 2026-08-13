import Foundation

public enum PreviewFormat: String, CaseIterable, Sendable {
    case markdown
    case json
    case yaml
}

public enum HierarchyTokenStyle: Sendable, Equatable {
    case delimiter
    case key
    case value
    case punctuation
}

public enum PreviewStyleRole: Sendable, Equatable {
    case heading(Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case codeBlock
    case codeLanguage
    case math(source: String, display: Bool)
    case mermaid(source: String)
    case quote
    case listMarker
    case tableCell(
        table: Int,
        row: Int,
        column: Int,
        columnCount: Int,
        isHeader: Bool
    )
    case link(String?)
    case imagePlaceholder
    case key
    case string
    case number
    case boolean
    case null
    case comment
    case keyword
    case punctuation
    case hierarchy(level: Int, style: HierarchyTokenStyle)
}

public struct PreviewStyleSpan: Sendable, Equatable {
    public let location: Int
    public let length: Int
    public let role: PreviewStyleRole

    public init(location: Int, length: Int, role: PreviewStyleRole) {
        self.location = location
        self.length = length
        self.role = role
    }
}

public enum PreviewDiagnosticSeverity: Sendable, Equatable {
    case information
    case warning
    case error
}

public struct PreviewDiagnostic: Sendable, Equatable {
    public let severity: PreviewDiagnosticSeverity
    public let message: String
    public let line: Int?
    public let column: Int?

    public init(
        severity: PreviewDiagnosticSeverity,
        message: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.severity = severity
        self.message = message
        self.line = line
        self.column = column
    }
}

public struct PreviewDocument: Sendable, Equatable {
    public let format: PreviewFormat
    public let content: String
    public let spans: [PreviewStyleSpan]
    public let diagnostic: PreviewDiagnostic?
    public let byteCount: Int
    public let isLimited: Bool

    public init(
        format: PreviewFormat,
        content: String,
        spans: [PreviewStyleSpan] = [],
        diagnostic: PreviewDiagnostic? = nil,
        byteCount: Int,
        isLimited: Bool = false
    ) {
        self.format = format
        self.content = content
        self.spans = spans
        self.diagnostic = diagnostic
        self.byteCount = byteCount
        self.isLimited = isLimited
    }
}

public enum PreviewLimits {
    public static let fullPreviewBytes = 5 * 1_024 * 1_024
    public static let limitedPreviewBytes = 25 * 1_024 * 1_024
    public static let mediumPrefixBytes = 1 * 1_024 * 1_024
    public static let largePrefixBytes = 256 * 1_024
    public static let maximumJSONDepth = 256
    public static let maximumJSONTokens = 1_000_000
}
