import Foundation
import Yams

enum YAMLPreviewRenderer {
    static func render(source: String, byteCount: Int) -> PreviewDocument {
        var diagnostic: PreviewDiagnostic?

        do {
            var documents = try compose_all(yaml: source)
            while documents.next() != nil {}
            if let error = documents.error {
                throw error
            }
        } catch let error as YamlError {
            diagnostic = makeDiagnostic(for: error)
        } catch {
            diagnostic = PreviewDiagnostic(
                severity: .error,
                message: error.localizedDescription
            )
        }

        return SourceHighlighter.document(
            format: .yaml,
            source: source,
            byteCount: byteCount,
            diagnostic: diagnostic
        )
    }

    private static func makeDiagnostic(for error: YamlError) -> PreviewDiagnostic {
        switch error {
        case .scanner(_, let problem, let mark, _),
             .parser(_, let problem, let mark, _),
             .composer(_, let problem, let mark, _):
            return PreviewDiagnostic(
                severity: .error,
                message: problem,
                line: mark.line,
                column: mark.column
            )
        case .reader(let problem, _, _, _):
            return PreviewDiagnostic(severity: .error, message: problem)
        case .duplicatedKeysInMapping(let duplicates, let context):
            return PreviewDiagnostic(
                severity: .error,
                message: "Duplicate mapping key: \(duplicates.joined(separator: ", "))",
                line: context.mark.line,
                column: context.mark.column
            )
        default:
            return PreviewDiagnostic(
                severity: .error,
                message: error.localizedDescription
            )
        }
    }
}
