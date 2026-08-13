import Foundation

struct LoadedText: Sendable {
    let text: String
    let byteCount: Int
    let isLimited: Bool
    let diagnostic: PreviewDiagnostic?
}

enum TextLoaderError: LocalizedError, Sendable {
    case unreadable(String)
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            return "The file could not be read: \(reason)"
        case .unsupportedEncoding:
            return "Unsupported text encoding. Pre-Anything accepts UTF-8 and BOM-marked UTF-16."
        }
    }
}

enum TextLoader {
    static func load(url: URL) throws -> LoadedText {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw TextLoaderError.unreadable(error.localizedDescription)
        }

        guard values.isRegularFile != false else {
            throw TextLoaderError.unreadable("The selected item is not a regular file.")
        }

        let byteCount = values.fileSize ?? 0
        let prefixLimit: Int?
        let diagnostic: PreviewDiagnostic?

        switch byteCount {
        case ...PreviewLimits.fullPreviewBytes:
            prefixLimit = nil
            diagnostic = nil
        case ...PreviewLimits.limitedPreviewBytes:
            prefixLimit = PreviewLimits.mediumPrefixBytes
            diagnostic = PreviewDiagnostic(
                severity: .warning,
                message: "Large file — showing the first 1 MiB without full parsing."
            )
        default:
            prefixLimit = PreviewLimits.largePrefixBytes
            diagnostic = PreviewDiagnostic(
                severity: .warning,
                message: "Very large file — showing the first 256 KiB without full parsing."
            )
        }

        let data: Data
        do {
            if let prefixLimit {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                data = try handle.read(upToCount: prefixLimit) ?? Data()
            } else {
                data = try Data(contentsOf: url, options: [.mappedIfSafe])
            }
        } catch {
            throw TextLoaderError.unreadable(error.localizedDescription)
        }

        guard let text = decode(data, allowTrimmedTail: prefixLimit != nil) else {
            throw TextLoaderError.unsupportedEncoding
        }

        return LoadedText(
            text: text,
            byteCount: byteCount,
            isLimited: prefixLimit != nil,
            diagnostic: diagnostic
        )
    }

    static func decode(_ data: Data, allowTrimmedTail: Bool = false) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return decodeUTF8(Data(data.dropFirst(3)), allowTrimmedTail: allowTrimmedTail)
        }

        if data.starts(with: [0xFF, 0xFE]) {
            var body = Data(data.dropFirst(2))
            if allowTrimmedTail, !body.count.isMultiple(of: 2) {
                body.removeLast()
            }
            return String(data: body, encoding: .utf16LittleEndian)
        }

        if data.starts(with: [0xFE, 0xFF]) {
            var body = Data(data.dropFirst(2))
            if allowTrimmedTail, !body.count.isMultiple(of: 2) {
                body.removeLast()
            }
            return String(data: body, encoding: .utf16BigEndian)
        }

        return decodeUTF8(data, allowTrimmedTail: allowTrimmedTail)
    }

    private static func decodeUTF8(_ data: Data, allowTrimmedTail: Bool) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        guard allowTrimmedTail else { return nil }

        for removedByteCount in 1...min(3, data.count) {
            let trimmed = data.dropLast(removedByteCount)
            if let text = String(data: trimmed, encoding: .utf8) {
                return text
            }
        }

        return nil
    }
}
