import Foundation

public struct TablePreviewDocument: Sendable, Equatable {
    public let headers: [String]
    public let rows: [[String]]
    public let sourceFallback: String?
    public let byteCount: Int
    public let isTruncated: Bool
    public let diagnostic: PreviewDiagnostic?

    public init(
        headers: [String],
        rows: [[String]],
        sourceFallback: String?,
        byteCount: Int,
        isTruncated: Bool,
        diagnostic: PreviewDiagnostic?
    ) {
        self.headers = headers
        self.rows = rows
        self.sourceFallback = sourceFallback
        self.byteCount = byteCount
        self.isTruncated = isTruncated
        self.diagnostic = diagnostic
    }

    public var isTable: Bool { sourceFallback == nil }
}

public enum TablePreviewService {
    public static func prepare(url: URL, delimiter: Character) async -> TablePreviewDocument {
        await Task.detached(priority: .userInitiated) {
            prepareSynchronously(url: url, delimiter: delimiter)
        }.value
    }

    static func prepareSynchronously(url: URL, delimiter: Character) -> TablePreviewDocument {
        do {
            let loaded = try TextLoader.load(url: url)
            guard !loaded.isLimited else {
                return TablePreviewDocument(
                    headers: [], rows: [], sourceFallback: loaded.text, byteCount: loaded.byteCount,
                    isTruncated: true, diagnostic: loaded.diagnostic
                )
            }
            let parsed = try TableParser.parse(loaded.text, delimiter: delimiter)
            return TablePreviewDocument(
                headers: parsed.headers, rows: parsed.rows, sourceFallback: nil,
                byteCount: loaded.byteCount, isTruncated: parsed.isTruncated,
                diagnostic: parsed.isTruncated
                    ? PreviewDiagnostic(severity: .warning, message: "Table is limited to the first 500 data rows and 50 columns.")
                    : nil
            )
        } catch let error as TableSyntaxError {
            return TablePreviewDocument(
                headers: [], rows: [], sourceFallback: error.source, byteCount: error.source.utf8.count,
                isTruncated: false,
                diagnostic: PreviewDiagnostic(severity: .error, message: error.message, line: error.line, column: error.column)
            )
        } catch {
            return TablePreviewDocument(
                headers: [], rows: [], sourceFallback: "Unable to preview this file.", byteCount: 0,
                isTruncated: false, diagnostic: PreviewDiagnostic(severity: .error, message: error.localizedDescription)
            )
        }
    }
}

public struct ParsedTable: Sendable, Equatable {
    public let headers: [String]
    public let rows: [[String]]
    public let isTruncated: Bool
}

public struct TableSyntaxError: Error, Sendable, Equatable {
    public let source: String
    public let message: String
    public let line: Int
    public let column: Int
}

public enum TableParser {
    public static func parse(_ source: String, delimiter: Character) throws -> ParsedTable {
        let scalars = Array(source.unicodeScalars)
        let delimiterScalar = delimiter.unicodeScalars.first?.value ?? 0x2C
        var fields: [String] = []
        var rows: [[String]] = []
        var field = ""
        var quoted = false
        var index = 0
        var line = 1
        var column = 1
        var truncated = false

        func store(_ record: [String]) {
            guard !record.isEmpty || !rows.isEmpty else { return }
            if rows.count < 501 {
                let limited = Array(record.prefix(50))
                if record.count > 50 { truncated = true }
                rows.append(limited)
            } else {
                truncated = true
            }
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar.value == 0x22 {
                    if index + 1 < scalars.count, scalars[index + 1].value == 0x22 {
                        field.unicodeScalars.append(scalar); index += 2; column += 2
                    } else {
                        quoted = false; index += 1; column += 1
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                    if scalar.value == 0x0A { line += 1; column = 1 } else { column += 1 }
                    index += 1
                }
                continue
            }

            switch scalar.value {
            case 0x22:
                guard field.isEmpty else {
                    throw TableSyntaxError(source: source, message: "Unexpected quote in an unquoted field.", line: line, column: column)
                }
                quoted = true; index += 1; column += 1
            case let value where value == delimiterScalar:
                fields.append(field); field = ""; index += 1; column += 1
            case 0x0A, 0x0D:
                if scalar.value == 0x0D, index + 1 < scalars.count, scalars[index + 1].value == 0x0A { index += 1 }
                fields.append(field); field = ""; store(fields); fields = []
                index += 1; line += 1; column = 1
            default:
                field.unicodeScalars.append(scalar); index += 1; column += 1
            }
        }
        if quoted {
            throw TableSyntaxError(source: source, message: "Unterminated quoted field.", line: line, column: column)
        }
        if !field.isEmpty || !fields.isEmpty {
            fields.append(field); store(fields)
        }

        let headers = rows.first ?? ["Column 1"]
        let width = max(1, headers.count)
        let normalizedHeaders = (0..<width).map { index in
            index < headers.count && !headers[index].isEmpty ? headers[index] : "Column \(index + 1)"
        }
        let dataRows = rows.dropFirst().map { row in
            Array(row.prefix(width)) + Array(repeating: "", count: max(0, width - row.count))
        }
        return ParsedTable(headers: normalizedHeaders, rows: dataRows, isTruncated: truncated)
    }
}
