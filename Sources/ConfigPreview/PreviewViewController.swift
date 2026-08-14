import Foundation
import PreviewKit
import TOMLKit

final class PreviewViewController: BasePreviewViewController {
    override var previewFormat: PreviewFormat { .config }

    override func prepareDocument(at url: URL) async -> PreviewDocument {
        let fallback = await PreviewService.prepare(url: url, as: .config)
        guard !fallback.isLimited, fallback.diagnostic == nil else { return fallback }

        let kind = ConfigFileKind(url: url)
        return ConfigPreviewRenderer.render(
            source: fallback.content,
            byteCount: fallback.byteCount,
            kind: kind
        )
    }
}

private enum ConfigFileKind {
    case toml
    case json5
    case dotenv
    case ini
    case properties
    case generic

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "toml": self = .toml
        case "jsonc", "json5": self = .json5
        case "env": self = .dotenv
        case "ini", "cfg": self = .ini
        case "properties": self = .properties
        default:
            self = url.lastPathComponent.hasPrefix(".env") ? .dotenv : .generic
        }
    }

    var highlighterKind: ConfigSyntaxKind {
        switch self {
        case .toml: .toml
        case .json5: .json5
        case .dotenv: .dotenv
        case .ini: .ini
        case .properties: .properties
        case .generic: .generic
        }
    }
}

private enum ConfigPreviewRenderer {
    static func render(source: String, byteCount: Int, kind: ConfigFileKind) -> PreviewDocument {
        do {
            switch kind {
            case .toml:
                _ = try TOMLTable(string: source)
            case .json5:
                try JSON5ValidationValue.validate(source)
            case .dotenv, .ini, .properties, .generic:
                break
            }
            return PreviewDocument(
                format: .config,
                content: source,
                spans: ConfigSourceHighlighter.highlight(source, kind: kind.highlighterKind),
                byteCount: byteCount
            )
        } catch {
            return PreviewDocument(
                format: .config,
                content: source,
                spans: ConfigSourceHighlighter.highlight(source, kind: kind.highlighterKind),
                diagnostic: PreviewDiagnostic(severity: .error, message: error.localizedDescription),
                byteCount: byteCount
            )
        }
    }
}

private indirect enum JSON5ValidationValue: Decodable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([JSON5ValidationValue])
    case object([String: JSON5ValidationValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSON5ValidationValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSON5ValidationValue].self)) }
    }

    static func validate(_ source: String) throws {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        _ = try decoder.decode(JSON5ValidationValue.self, from: Data(source.utf8))
    }
}
