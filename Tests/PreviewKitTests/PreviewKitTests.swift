import Foundation
import SwiftMath
import XCTest
@testable import PreviewKit

final class PreviewKitTests: XCTestCase {
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

    private func prepare(_ source: String, format: PreviewFormat) throws -> PreviewDocument {
        let url = temporaryURL(extension: format.rawValue)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(source.utf8).write(to: url)
        return PreviewService.prepareSynchronously(url: url, as: format)
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }
}
