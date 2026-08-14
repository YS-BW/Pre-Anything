import Foundation
import SwiftMath
import TOMLKit
import XCTest
@testable import PreviewKit

final class PreviewKitTests: XCTestCase {
    func testAppearancePreferencesDefaultToTransparentAndRemainIndependent() throws {
        let suiteName = "PreAnythingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreviewAppearancePreferences(defaults: defaults)

        for format in PreviewFormat.allCases {
            XCTAssertTrue(preferences.isTransparent(for: format))
        }

        preferences.setTransparent(false, for: .json)

        XCTAssertTrue(preferences.isTransparent(for: .markdown))
        XCTAssertFalse(preferences.isTransparent(for: .json))
        XCTAssertTrue(preferences.isTransparent(for: .yaml))
        XCTAssertTrue(preferences.isTransparent(for: .config))
        XCTAssertTrue(preferences.isTransparent(for: .table))
        XCTAssertTrue(preferences.isTransparent(for: .xml))
        XCTAssertTrue(preferences.isTransparent(for: .notebook))
        XCTAssertTrue(preferences.isTransparent(for: .sourceCode))
    }

    func testJSONPreservesOrderDuplicatesAndNumberSpelling() throws {
        let source = #"{"z":1e+09,"a":900719925474099312345,"z":-0.50}"#
        let document = try prepare(source, format: .json)

        XCTAssertNil(document.diagnostic)
        XCTAssertEqual(
            document.content,
            """
            {
              "z": 1e+09,
              "a": 900719925474099312345,
              "z": -0.50
            }

            """
        )
    }

    func testJSONReportsPreciseSyntaxLocation() throws {
        let document = try prepare("""
        {
          "valid": true,
          "broken": [1,]
        }
        """, format: .json)

        XCTAssertEqual(document.diagnostic?.severity, .error)
        XCTAssertEqual(document.diagnostic?.line, 3)
        XCTAssertEqual(document.diagnostic?.column, 16)
        XCTAssertEqual(document.content.contains(#""broken": [1,]"#), true)
    }

    func testJSONAssignsMatchingDelimitersAndTokensByHierarchy() throws {
        let document = try prepare(
            #"{"a":{"b":[1,{"c":2}]},"d":[]}"#,
            format: .json
        )

        let hierarchy = document.spans.compactMap { span -> (String, Int, HierarchyTokenStyle)? in
            guard case .hierarchy(let level, let style) = span.role else { return nil }
            let token = (document.content as NSString).substring(
                with: NSRange(location: span.location, length: span.length)
            )
            return (token, level, style)
        }
        let keys = hierarchy.filter { $0.2 == .key }

        XCTAssertEqual(
            hierarchy.filter { $0.2 == .delimiter }.map(\.1),
            [0, 1, 2, 3, 3, 2, 1, 1, 1, 0]
        )
        XCTAssertEqual(keys.map(\.0), [#""a""#, #""b""#, #""c""#, #""d""#])
        XCTAssertEqual(keys.map(\.1), [1, 2, 4, 1])
        XCTAssertTrue(hierarchy.contains { $0.0 == "1" && $0.1 == 3 && $0.2 == .value })
        XCTAssertTrue(hierarchy.contains { $0.0 == "2" && $0.1 == 4 && $0.2 == .value })
    }

    func testJSONRejectsExcessiveNestingWithoutCrashing() throws {
        let depth = PreviewLimits.maximumJSONDepth + 2
        let source = String(repeating: "[", count: depth)
            + "0"
            + String(repeating: "]", count: depth)
        let document = try prepare(source, format: .json)

        XCTAssertEqual(document.diagnostic?.severity, .error)
        XCTAssertTrue(document.diagnostic?.message.contains("depth") == true)
    }

    func testYAMLPreservesCommentsAnchorsAndDocumentSeparators() throws {
        let source = """
        ---
        defaults: &defaults
          enabled: true # retained
        service:
          <<: *defaults
        ---
        tagged: !custom value
        """
        let document = try prepare(source, format: .yaml)

        XCTAssertEqual(document.content, source)
        XCTAssertNil(document.diagnostic)
        XCTAssertTrue(document.spans.contains { $0.role == .comment })
        XCTAssertTrue(document.spans.contains {
            $0.role == .hierarchy(level: 0, style: .delimiter)
        })
    }

    func testYAMLAssignsTextAndKeysByIndentationHierarchy() throws {
        let source = """
        root:
          child:
            enabled: true # retained
            hash: abc#def
          sibling: 1
        list:
          - name: one
            metadata:
              id: 1
          - name: two
        block: |
          # literal block content
        """
        let document = try prepare(source, format: .yaml)

        let hierarchy = document.spans.compactMap { span -> (String, Int, HierarchyTokenStyle)? in
            guard case .hierarchy(let level, let style) = span.role else { return nil }
            let token = (document.content as NSString).substring(
                with: NSRange(location: span.location, length: span.length)
            )
            return (token, level, style)
        }
        let keys = hierarchy.filter { $0.2 == .key }

        XCTAssertEqual(keys.map(\.0), [
            "root", "child", "enabled", "hash", "sibling", "list",
            "name", "metadata", "id", "name", "block",
        ])
        XCTAssertEqual(keys.map(\.1), [0, 1, 2, 2, 1, 0, 1, 2, 3, 1, 0])
        XCTAssertTrue(document.spans.contains { $0.role == .comment })

        let literalLocation = (document.content as NSString)
            .range(of: "# literal block content")
            .location
        XCTAssertFalse(document.spans.contains { span in
            span.role == .comment && NSLocationInRange(
                literalLocation,
                NSRange(location: span.location, length: span.length)
            )
        })
        let embeddedHashLocation = (document.content as NSString).range(of: "#def").location
        XCTAssertFalse(document.spans.contains { span in
            span.role == .comment && NSLocationInRange(
                embeddedHashLocation,
                NSRange(location: span.location, length: span.length)
            )
        })
        XCTAssertTrue(hierarchy.contains {
            $0.0 == "# literal block content" && $0.1 == 1 && $0.2 == .value
        })
    }

    func testInvalidYAMLStillShowsOriginalSourceAndLocation() throws {
        let source = "root:\n  child: [one, two\n"
        let document = try prepare(source, format: .yaml)

        XCTAssertEqual(document.content, source)
        XCTAssertEqual(document.diagnostic?.severity, .error)
        XCTAssertNotNil(document.diagnostic?.line)
        XCTAssertNotNil(document.diagnostic?.column)
    }

    func testMarkdownRendersCoreGFMAndTreatsHTMLAsText() throws {
        let source = """
        # Heading

        - [x] done
        - [ ] todo

        | A | B |
        | - | - |
        | 1 | 2 |

        **bold** and ~~removed~~ with `code`.

        <script>alert('no')</script>

        ![Remote](https://example.com/image.png)
        """
        let document = try prepare(source, format: .markdown)

        XCTAssertNil(document.diagnostic)
        XCTAssertTrue(document.content.contains("Heading"))
        XCTAssertTrue(document.content.contains("☑ done"))
        XCTAssertTrue(document.content.contains("☐ todo"))
        XCTAssertTrue(document.content.contains("A\nB\n1\n2"))
        XCTAssertTrue(document.content.contains("<script>alert('no')</script>"))
        XCTAssertTrue(document.content.contains("[Remote]"))
        XCTAssertFalse(document.content.contains("https://example.com/image.png"))
        XCTAssertTrue(document.spans.contains { $0.role == .heading(1) })
        XCTAssertTrue(document.spans.contains { $0.role == .strong })
        XCTAssertTrue(document.spans.contains { $0.role == .strikethrough })
        XCTAssertEqual(document.spans.filter {
            if case .tableCell = $0.role { return true }
            return false
        }.count, 4)
        XCTAssertEqual(document.spans.filter {
            if case .tableCell(_, _, _, _, let isHeader) = $0.role { return isHeader }
            return false
        }.count, 2)
    }

    func testMarkdownProducesNativeMathMermaidAndCodeTokens() throws {
        let source = #"""
        Inline math $E = mc^2$.

        $$
        \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
        $$

        ```swift
        // Native highlighting
        let message = "hello"
        let answer = 42
        ```

        ```mermaid
        flowchart LR
            Finder --> PreviewKit
        ```
        """#
        let document = try prepare(source, format: .markdown)

        XCTAssertNil(document.diagnostic)
        XCTAssertTrue(document.spans.contains {
            if case .math(let source, let display) = $0.role {
                return source == "E = mc^2" && !display
            }
            return false
        })
        XCTAssertTrue(document.spans.contains {
            if case .math(let source, let display) = $0.role {
                return source.contains(#"\sum"#) && display
            }
            return false
        })
        XCTAssertTrue(document.spans.contains {
            if case .mermaid(let source) = $0.role {
                return source.contains("Finder --> PreviewKit")
            }
            return false
        })
        XCTAssertTrue(document.spans.contains { $0.role == .comment })
        XCTAssertTrue(document.spans.contains { $0.role == .keyword })
        XCTAssertTrue(document.spans.contains { $0.role == .string })
        XCTAssertTrue(document.spans.contains { $0.role == .number })
        XCTAssertTrue(document.spans.contains { $0.role == .codeBlock })
    }

    func testMarkdownPreservesMatrixRowSeparatorsInDisplayMath() throws {
        let source = #"""
        Matrix:

        $$
        A = \begin{bmatrix}
        1 & 2 & 3 \\
        4 & 5 & 6 \\
        7 & 8 & 9
        \end{bmatrix}
        $$
        """#
        let document = try prepare(source, format: .markdown)

        let matrixSource = document.spans.compactMap { span -> String? in
            if case .math(let source, let display) = span.role, display {
                return source
            }
            return nil
        }.first

        XCTAssertNotNil(matrixSource)
        XCTAssertTrue(matrixSource?.contains(#"1 & 2 & 3 \\"#) == true)
        XCTAssertTrue(matrixSource?.contains(#"4 & 5 & 6 \\"#) == true)
        XCTAssertTrue(matrixSource?.contains(#"\begin{bmatrix}"#) == true)
        XCTAssertTrue(matrixSource?.contains(#"\end{bmatrix}"#) == true)

        let rendered = MTMathImage(
            latex: try XCTUnwrap(matrixSource),
            fontSize: 22,
            textColor: .white,
            labelMode: .display,
            textAlignment: .center
        ).asImage()
        XCTAssertNil(rendered.0)
        XCTAssertNotNil(rendered.1)
    }

    func testSupportedEncodingsDecodeStrictly() {
        XCTAssertEqual(TextLoader.decode(Data("hello".utf8)), "hello")
        XCTAssertEqual(TextLoader.decode(Data([0xEF, 0xBB, 0xBF] + Array("hello".utf8))), "hello")

        var littleEndian = Data([0xFF, 0xFE])
        littleEndian.append("hello".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(TextLoader.decode(littleEndian), "hello")

        var bigEndian = Data([0xFE, 0xFF])
        bigEndian.append("hello".data(using: .utf16BigEndian)!)
        XCTAssertEqual(TextLoader.decode(bigEndian), "hello")

        XCTAssertNil(TextLoader.decode(Data([0xFF, 0x00, 0xC3, 0x28])))
    }

    func testTrimmedUTF8BoundaryDropsOnlyIncompleteScalar() {
        let full = Data("hello 🦊".utf8)
        let truncated = full.dropLast(2)

        XCTAssertNil(TextLoader.decode(Data(truncated)))
        XCTAssertEqual(TextLoader.decode(Data(truncated), allowTrimmedTail: true), "hello ")
    }

    func testMediumFileUsesBoundedSourcePreview() throws {
        let url = temporaryURL(extension: "json")
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = Data(repeating: 0x20, count: PreviewLimits.fullPreviewBytes + 1)
        try payload.write(to: url)
        let document = PreviewService.prepareSynchronously(url: url, as: .json)

        XCTAssertTrue(document.isLimited)
        XCTAssertEqual(document.content.utf8.count, PreviewLimits.mediumPrefixBytes)
        XCTAssertEqual(document.diagnostic?.severity, .warning)
    }

    func testSourceLanguageDetectionCoversSupportedFamilies() {
        let cases: [(String, SourceLanguage)] = [
            ("swift", .swift), ("m", .objectiveC), ("hpp", .cpp),
            ("cs", .csharp), ("java", .java), ("jsx", .javascript),
            ("tsx", .typescript), ("kt", .kotlin), ("go", .go),
            ("rs", .rust), ("py", .python), ("rb", .ruby),
            ("zsh", .shell), ("sql", .sql), ("css", .css),
        ]

        for (pathExtension, expected) in cases {
            XCTAssertEqual(
                SourceLanguage.language(forPathExtension: pathExtension.uppercased()),
                expected
            )
        }
        XCTAssertEqual(SourceLanguage.language(forPathExtension: "unknown"), .plainText)
    }

    func testPythonSourceRemainsUnmodifiedAndHighlightsCoreTokens() throws {
        let source = #"""
        @dataclass(slots=True)
        class PreviewJob:
            retries: int = 3

            async def render(self, name: str) -> str:
                # The extension reads source; it never executes it.
                return f"Hello, {name}"
        """#
        let document = try prepare(source, format: .sourceCode, pathExtension: "py")

        XCTAssertEqual(document.content, source)
        XCTAssertEqual(document.format, .sourceCode)
        XCTAssertNil(document.diagnostic)
        XCTAssertEqual(texts(with: .attribute, in: document), ["@dataclass"])
        XCTAssertTrue(texts(with: .keyword, in: document).contains("async"))
        XCTAssertTrue(texts(with: .type, in: document).contains("PreviewJob"))
        XCTAssertTrue(texts(with: .function, in: document).contains("render"))
        XCTAssertTrue(texts(with: .comment, in: document).contains {
            $0.contains("never executes")
        })
        XCTAssertTrue(texts(with: .number, in: document).contains("3"))
    }

    func testJavaSourceHighlightsAnnotationsTypesAndFunctions() throws {
        let source = #"""
        @Deprecated
        public final class PreviewService {
            private static final int LIMIT = 256;

            public String render(String source) {
                return source.strip();
            }
        }
        """#
        let document = try prepare(source, format: .sourceCode, pathExtension: "java")

        XCTAssertEqual(document.content, source)
        XCTAssertTrue(texts(with: .attribute, in: document).contains("@Deprecated"))
        XCTAssertTrue(texts(with: .type, in: document).contains("PreviewService"))
        XCTAssertTrue(texts(with: .type, in: document).contains("String"))
        XCTAssertTrue(texts(with: .function, in: document).contains("render"))
        XCTAssertTrue(texts(with: .number, in: document).contains("256"))
    }

    func testLimitedSourceCodeStillUsesDetectedLanguage() throws {
        let url = temporaryURL(extension: "py")
        defer { try? FileManager.default.removeItem(at: url) }
        let prefix = "def preview() -> str:\n    return \"ready\"\n"
        var payload = Data(prefix.utf8)
        payload.append(Data(repeating: 0x20, count: PreviewLimits.fullPreviewBytes + 1))
        try payload.write(to: url)

        let document = PreviewService.prepareSynchronously(url: url, as: .sourceCode)

        XCTAssertTrue(document.isLimited)
        XCTAssertEqual(document.diagnostic?.severity, .warning)
        XCTAssertTrue(texts(with: .keyword, in: document).contains("def"))
        XCTAssertTrue(texts(with: .function, in: document).contains("preview"))
    }

    func testSourceExtensionRegistersConcreteLanguageTypes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot
            .appendingPathComponent("Sources/SourceCodePreview/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let extensionInfo = try XCTUnwrap(root["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(
            extensionInfo["NSExtensionAttributes"] as? [String: Any]
        )
        let supportedTypes = Set(try XCTUnwrap(
            attributes["QLSupportedContentTypes"] as? [String]
        ))

        XCTAssertTrue(supportedTypes.contains("public.python-script"))
        XCTAssertTrue(supportedTypes.contains("com.sun.java-source"))
        XCTAssertTrue(supportedTypes.contains("public.swift-source"))
        XCTAssertTrue(supportedTypes.contains("com.lixinlv.preanything.source-code"))
    }

    func testOneMiBJSONPerformanceBaseline() throws {
        let record = #"{"id":9007199254740993,"name":"preview","active":true}"#
        let count = max(1, (1_024 * 1_024) / (record.utf8.count + 1))
        let source = "[" + Array(repeating: record, count: count).joined(separator: ",") + "]"
        let url = temporaryURL(extension: "json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(source.utf8).write(to: url)

        let start = ContinuousClock.now
        let document = PreviewService.prepareSynchronously(url: url, as: .json)
        let elapsed = ContinuousClock.now - start

        XCTAssertNil(document.diagnostic)
        XCTAssertLessThan(elapsed, .seconds(2), "Debug safety ceiling exceeded; release target remains 300 ms.")
    }

    func testTOMLPreservesSourceAndHighlightsTablesKeysAndComments() throws {
        let source = """
        # retained comment
        [server.tls]
        enabled = true
        issued = 2026-08-14T12:34:56Z
        [[products]]
        name = "widget"
        """
        XCTAssertNoThrow(try TOMLTable(string: source))

        let spans = ConfigSourceHighlighter.highlight(source, kind: .toml)
        let content = source as NSString
        XCTAssertTrue(spans.contains { $0.role == .comment })
        XCTAssertTrue(spans.contains { span in
            content.substring(with: NSRange(location: span.location, length: span.length)) == "enabled"
                && span.role == .hierarchy(level: 1, style: .key)
        })
        XCTAssertTrue(spans.contains { $0.role == .hierarchy(level: 1, style: .delimiter) })
    }

    func testJSON5AcceptsCommentsTrailingCommasAndBareKeys() throws {
        let source = """
        {
          // preserved comment
          bareKey: 'value',
          trailing: [1, 2,],
        }
        """
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let decoded = try decoder.decode(JSON5Fixture.self, from: Data(source.utf8))
        XCTAssertEqual(decoded.bareKey, "value")
        XCTAssertEqual(decoded.trailing, [1, 2])

        let spans = ConfigSourceHighlighter.highlight(source, kind: .json5)
        XCTAssertTrue(spans.contains { $0.role == .comment })
        XCTAssertTrue(spans.contains { span in
            let text = (source as NSString).substring(with: NSRange(location: span.location, length: span.length))
            return text == "bareKey" && span.role == .hierarchy(level: 1, style: .key)
        })
    }

    func testConfigLineFormatsPreserveValuesAndColorOnlyStructure() {
        let source = """
        # comment
        EMPTY=
        TOKEN=${DO_NOT_EXPAND}
        [service]
        port: 8080
        """
        let spans = ConfigSourceHighlighter.highlight(source, kind: .dotenv)
        XCTAssertTrue(spans.contains { $0.role == .comment })
        XCTAssertTrue(spans.contains { $0.role == .hierarchy(level: 0, style: .key) })
        XCTAssertFalse(spans.contains { $0.role == .string || $0.role == .number })
    }

    func testTableParserHandlesQuotedNewlinesEscapesAndTruncation() throws {
        let table = try TableParser.parse(
            "name,notes,empty\nAda,\"first line\nsecond \"\"quote\"\"\",\n",
            delimiter: ","
        )
        XCTAssertEqual(table.headers, ["name", "notes", "empty"])
        XCTAssertEqual(table.rows, [["Ada", "first line\nsecond \"quote\"", ""]])

        let manyColumns = (0..<51).map(String.init).joined(separator: ",")
        XCTAssertTrue(try TableParser.parse(manyColumns, delimiter: ",").isTruncated)
    }

    func testTablePreviewLoadsUTF16() throws {
        let url = temporaryURL(extension: "tsv")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data([0xFF, 0xFE])
        data.append("name\tage\nAda\t42\n".data(using: .utf16LittleEndian)!)
        try data.write(to: url)

        let document = TablePreviewService.prepareSynchronously(url: url, delimiter: "\t")
        XCTAssertTrue(document.isTable)
        XCTAssertEqual(document.headers, ["name", "age"])
        XCTAssertEqual(document.rows, [["Ada", "42"]])
    }

    func testXMLPreservesSourceHighlightsMarkupAndReportsErrors() throws {
        let source = """
        <!-- keep -->
        <root mode="safe"><child><![CDATA[raw <text>]]>&amp;</child></root>
        """
        let document = try prepare(source, format: .xml, pathExtension: "xml")
        XCTAssertEqual(document.content, source)
        XCTAssertNil(document.diagnostic)
        XCTAssertTrue(document.spans.contains { $0.role == .comment })
        XCTAssertTrue(document.spans.contains { $0.role == .attribute })
        XCTAssertTrue(document.spans.contains { $0.role == .string })
        XCTAssertFalse(document.spans.contains { span in
            let text = (document.content as NSString).substring(with: NSRange(location: span.location, length: span.length))
            return text == "text" && span.role == .keyword
        })

        let invalid = try prepare("<root><child></root>", format: .xml, pathExtension: "xml")
        XCTAssertEqual(invalid.diagnostic?.severity, .error)
        XCTAssertNotNil(invalid.diagnostic?.line)
        XCTAssertNotNil(invalid.diagnostic?.column)
    }

    func testNotebookRendersSafeCellsAndOmitsUnsafeOutput() throws {
        let source = #"""
        {
          "metadata": {"language_info": {"name": "python"}},
          "cells": [
            {"cell_type": "markdown", "source": ["# Heading\\n", "**safe**"]},
            {"cell_type": "code", "source": "print('hello')", "outputs": [
              {"output_type": "stream", "text": "hello\\n"},
              {"output_type": "display_data", "data": {"text/plain": "42", "image/png": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLmtAAAAABJRU5ErkJggg==", "text/html": "<button>no</button>"}}
            ]}
          ]
        }
        """#
        let document = try prepare(source, format: .notebook, pathExtension: "ipynb")
        XCTAssertNil(document.diagnostic)
        XCTAssertTrue(document.content.contains("Heading"))
        XCTAssertTrue(document.content.contains("print('hello')"))
        XCTAssertTrue(document.content.contains("HTML, JavaScript, and SVG output were omitted for safety."))
        XCTAssertTrue(document.spans.contains { $0.role == .codeBlock })
        XCTAssertTrue(document.spans.contains { $0.role == .heading(5) })
        XCTAssertTrue(document.spans.contains {
            if case .notebookImage = $0.role { return true }
            return false
        })
    }

    func testNotebookInvalidJSONFallsBackToOriginalJSON() throws {
        let source = #"{"cells": [}"#
        let document = try prepare(source, format: .notebook, pathExtension: "ipynb")
        XCTAssertEqual(document.content, source)
        XCTAssertEqual(document.diagnostic?.severity, .error)
    }

    func testNewExtensionTargetsRegisterExpectedUTIs() throws {
        let expected: [String: Set<String>] = [
            "ConfigPreview": [
                "com.lixinlv.preanything.toml", "com.lixinlv.preanything.jsonc",
                "com.lixinlv.preanything.json5", "com.lixinlv.preanything.dotenv",
                "com.lixinlv.preanything.ini", "com.lixinlv.preanything.properties",
            ],
            "TablePreview": ["public.comma-separated-values-text", "public.tab-separated-values-text"],
            "XMLPreview": ["public.xml"],
            "NotebookPreview": ["com.lixinlv.preanything.notebook"],
        ]
        for (target, types) in expected {
            XCTAssertEqual(try extensionSupportedTypes(named: target), types)
        }
    }

    private func prepare(
        _ source: String,
        format: PreviewFormat,
        pathExtension: String? = nil
    ) throws -> PreviewDocument {
        let url = temporaryURL(extension: pathExtension ?? format.rawValue)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(source.utf8).write(to: url)
        return PreviewService.prepareSynchronously(url: url, as: format)
    }

    private func texts(
        with role: PreviewStyleRole,
        in document: PreviewDocument
    ) -> [String] {
        let content = document.content as NSString
        return document.spans.compactMap { span in
            guard span.role == role else { return nil }
            return content.substring(with: NSRange(location: span.location, length: span.length))
        }
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    private func extensionSupportedTypes(named target: String) throws -> Set<String> {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot.appendingPathComponent("Sources/\(target)/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let extensionInfo = try XCTUnwrap(root["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        return Set(try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String]))
    }
}

private struct JSON5Fixture: Decodable {
    let bareKey: String
    let trailing: [Int]
}
