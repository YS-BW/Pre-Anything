import Foundation

enum JSONPreviewRenderer {
    static func render(source: String, byteCount: Int) -> PreviewDocument {
        do {
            var tokenizer = JSONTokenizer(source: source)
            let tokens = try tokenizer.tokenize()
            var parser = JSONParser(tokens: tokens)
            try parser.validate()
            let formatted = JSONFormatter(tokens: tokens).format()
            return PreviewDocument(
                format: .json,
                content: formatted.content,
                spans: formatted.spans,
                byteCount: byteCount
            )
        } catch let error as JSONSyntaxError {
            return SourceHighlighter.document(
                format: .json,
                source: source,
                byteCount: byteCount,
                diagnostic: PreviewDiagnostic(
                    severity: .error,
                    message: error.message,
                    line: error.line,
                    column: error.column
                )
            )
        } catch {
            return SourceHighlighter.document(
                format: .json,
                source: source,
                byteCount: byteCount,
                diagnostic: PreviewDiagnostic(
                    severity: .error,
                    message: error.localizedDescription
                )
            )
        }
    }
}

struct JSONSyntaxError: Error, LocalizedError, Sendable, Equatable {
    let message: String
    let line: Int
    let column: Int

    var errorDescription: String? {
        "\(message) at line \(line), column \(column)."
    }
}

private enum JSONTokenKind: Sendable, Equatable {
    case leftBrace
    case rightBrace
    case leftBracket
    case rightBracket
    case colon
    case comma
    case string
    case number
    case trueLiteral
    case falseLiteral
    case nullLiteral
}

private struct JSONToken: Sendable, Equatable {
    let kind: JSONTokenKind
    let raw: String
    let line: Int
    let column: Int
}

private struct JSONTokenizer {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var line = 1
    private var column = 1
    private var tokens: [JSONToken] = []

    init(source: String) {
        scalars = Array(source.unicodeScalars)
    }

    mutating func tokenize() throws -> [JSONToken] {
        while let scalar = peek() {
            if isWhitespace(scalar) {
                advance()
                continue
            }

            guard tokens.count < PreviewLimits.maximumJSONTokens else {
                throw syntaxError("JSON contains too many tokens")
            }

            let tokenLine = line
            let tokenColumn = column

            switch scalar.value {
            case 0x7B:
                advance(); append(.leftBrace, "{", tokenLine, tokenColumn)
            case 0x7D:
                advance(); append(.rightBrace, "}", tokenLine, tokenColumn)
            case 0x5B:
                advance(); append(.leftBracket, "[", tokenLine, tokenColumn)
            case 0x5D:
                advance(); append(.rightBracket, "]", tokenLine, tokenColumn)
            case 0x3A:
                advance(); append(.colon, ":", tokenLine, tokenColumn)
            case 0x2C:
                advance(); append(.comma, ",", tokenLine, tokenColumn)
            case 0x22:
                let raw = try scanString()
                append(.string, raw, tokenLine, tokenColumn)
            case 0x2D, 0x30...0x39:
                let raw = try scanNumber()
                append(.number, raw, tokenLine, tokenColumn)
            case 0x74:
                try scanLiteral("true", kind: .trueLiteral, line: tokenLine, column: tokenColumn)
            case 0x66:
                try scanLiteral("false", kind: .falseLiteral, line: tokenLine, column: tokenColumn)
            case 0x6E:
                try scanLiteral("null", kind: .nullLiteral, line: tokenLine, column: tokenColumn)
            default:
                throw syntaxError("Unexpected character ‘\(Character(scalar))’")
            }
        }

        return tokens
    }

    private mutating func scanString() throws -> String {
        let start = index
        advance() // opening quote

        while let scalar = peek() {
            if scalar.value == 0x22 {
                advance()
                return String(String.UnicodeScalarView(scalars[start..<index]))
            }

            if scalar.value < 0x20 {
                throw syntaxError("Unescaped control character in string")
            }

            if scalar.value == 0x5C {
                advance()
                guard let escaped = peek() else {
                    throw syntaxError("Unterminated escape sequence")
                }

                if [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escaped.value) {
                    advance()
                    continue
                }

                guard escaped.value == 0x75 else {
                    throw syntaxError("Invalid escape sequence")
                }
                advance()
                for _ in 0..<4 {
                    guard let hex = peek(), isHexDigit(hex) else {
                        throw syntaxError("Invalid Unicode escape sequence")
                    }
                    advance()
                }
                continue
            }

            advance()
        }

        throw syntaxError("Unterminated string")
    }

    private mutating func scanNumber() throws -> String {
        let start = index

        if peek()?.value == 0x2D {
            advance()
        }

        guard let firstDigit = peek() else {
            throw syntaxError("Expected a digit after minus sign")
        }

        if firstDigit.value == 0x30 {
            advance()
            if let next = peek(), isDigit(next) {
                throw syntaxError("Leading zeros are not allowed in JSON numbers")
            }
        } else if isDigitOneToNine(firstDigit) {
            repeat { advance() } while peek().map(isDigit) == true
        } else {
            throw syntaxError("Expected a digit")
        }

        if peek()?.value == 0x2E {
            advance()
            guard let digit = peek(), isDigit(digit) else {
                throw syntaxError("Expected a digit after decimal point")
            }
            repeat { advance() } while peek().map(isDigit) == true
        }

        if let exponent = peek(), exponent.value == 0x65 || exponent.value == 0x45 {
            advance()
            if let sign = peek(), sign.value == 0x2B || sign.value == 0x2D {
                advance()
            }
            guard let digit = peek(), isDigit(digit) else {
                throw syntaxError("Expected a digit in exponent")
            }
            repeat { advance() } while peek().map(isDigit) == true
        }

        return String(String.UnicodeScalarView(scalars[start..<index]))
    }

    private mutating func scanLiteral(
        _ literal: String,
        kind: JSONTokenKind,
        line: Int,
        column: Int
    ) throws {
        for expected in literal.unicodeScalars {
            guard peek() == expected else {
                throw syntaxError("Invalid literal")
            }
            advance()
        }
        append(kind, literal, line, column)
    }

    private mutating func append(_ kind: JSONTokenKind, _ raw: String, _ line: Int, _ column: Int) {
        tokens.append(JSONToken(kind: kind, raw: raw, line: line, column: column))
    }

    private func peek() -> Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    private mutating func advance() {
        guard let scalar = peek() else { return }
        index += 1
        if scalar.value == 0x0A {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    private func syntaxError(_ message: String) -> JSONSyntaxError {
        JSONSyntaxError(message: message, line: line, column: column)
    }

    private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        [0x20, 0x09, 0x0A, 0x0D].contains(scalar.value)
    }

    private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    private func isDigitOneToNine(_ scalar: Unicode.Scalar) -> Bool {
        (0x31...0x39).contains(scalar.value)
    }

    private func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
            || (0x41...0x46).contains(scalar.value)
            || (0x61...0x66).contains(scalar.value)
    }
}

private struct JSONParser {
    private let tokens: [JSONToken]
    private var index = 0

    init(tokens: [JSONToken]) {
        self.tokens = tokens
    }

    mutating func validate() throws {
        guard !tokens.isEmpty else {
            throw JSONSyntaxError(message: "JSON document is empty", line: 1, column: 1)
        }
        try parseValue(depth: 0)
        guard index == tokens.count else {
            throw error(at: tokens[index], message: "Unexpected content after the top-level value")
        }
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= PreviewLimits.maximumJSONDepth else {
            throw currentError("JSON nesting exceeds the supported depth")
        }
        guard let token = current else {
            throw endError("Expected a JSON value")
        }

        switch token.kind {
        case .leftBrace:
            try parseObject(depth: depth + 1)
        case .leftBracket:
            try parseArray(depth: depth + 1)
        case .string, .number, .trueLiteral, .falseLiteral, .nullLiteral:
            index += 1
        default:
            throw error(at: token, message: "Expected a JSON value")
        }
    }

    private mutating func parseObject(depth: Int) throws {
        index += 1 // {
        if consume(.rightBrace) { return }

        while true {
            guard let key = current, key.kind == .string else {
                throw currentError("Expected a quoted object key")
            }
            index += 1
            try expect(.colon, message: "Expected ‘:’ after object key")
            try parseValue(depth: depth)

            if consume(.rightBrace) { return }
            try expect(.comma, message: "Expected ‘,’ or ‘}’ after object value")
            if current?.kind == .rightBrace {
                throw currentError("Trailing commas are not allowed")
            }
        }
    }

    private mutating func parseArray(depth: Int) throws {
        index += 1 // [
        if consume(.rightBracket) { return }

        while true {
            try parseValue(depth: depth)
            if consume(.rightBracket) { return }
            try expect(.comma, message: "Expected ‘,’ or ‘]’ after array value")
            if current?.kind == .rightBracket {
                throw currentError("Trailing commas are not allowed")
            }
        }
    }

    private mutating func expect(_ kind: JSONTokenKind, message: String) throws {
        guard consume(kind) else { throw currentError(message) }
    }

    private mutating func consume(_ kind: JSONTokenKind) -> Bool {
        guard current?.kind == kind else { return false }
        index += 1
        return true
    }

    private var current: JSONToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private func currentError(_ message: String) -> JSONSyntaxError {
        if let current { return error(at: current, message: message) }
        return endError(message)
    }

    private func endError(_ message: String) -> JSONSyntaxError {
        guard let last = tokens.last else {
            return JSONSyntaxError(message: message, line: 1, column: 1)
        }
        return JSONSyntaxError(
            message: message,
            line: last.line,
            column: last.column + last.raw.unicodeScalars.count
        )
    }

    private func error(at token: JSONToken, message: String) -> JSONSyntaxError {
        JSONSyntaxError(message: message, line: token.line, column: token.column)
    }
}

private struct JSONFormatter {
    let tokens: [JSONToken]

    func format() -> (content: String, spans: [PreviewStyleSpan]) {
        var output = ""
        var spans: [PreviewStyleSpan] = []
        var indentation = 0

        func append(_ value: String, role: PreviewStyleRole? = nil) {
            let location = output.utf16.count
            output += value
            if let role, !value.isEmpty {
                spans.append(PreviewStyleSpan(
                    location: location,
                    length: value.utf16.count,
                    role: role
                ))
            }
        }

        func appendIndent() {
            append(String(repeating: "  ", count: indentation))
        }

        for (tokenIndex, token) in tokens.enumerated() {
            let nextKind = tokenIndex + 1 < tokens.count ? tokens[tokenIndex + 1].kind : nil

            switch token.kind {
            case .leftBrace, .leftBracket:
                append(
                    token.raw,
                    role: .hierarchy(level: indentation, style: .delimiter)
                )
                if nextKind != matchingClose(for: token.kind) {
                    indentation += 1
                    append("\n")
                    appendIndent()
                }
            case .rightBrace, .rightBracket:
                let previousKind = tokenIndex > 0 ? tokens[tokenIndex - 1].kind : nil
                if previousKind != matchingOpen(for: token.kind) {
                    indentation = max(0, indentation - 1)
                    append("\n")
                    appendIndent()
                }
                append(
                    token.raw,
                    role: .hierarchy(level: indentation, style: .delimiter)
                )
            case .comma:
                append(",", role: .hierarchy(level: indentation, style: .punctuation))
                append("\n")
                appendIndent()
            case .colon:
                append(":", role: .hierarchy(level: indentation, style: .punctuation))
                append(" ")
            case .string:
                append(
                    token.raw,
                    role: .hierarchy(
                        level: indentation,
                        style: nextKind == .colon ? .key : .value
                    )
                )
            case .number:
                append(token.raw, role: .hierarchy(level: indentation, style: .value))
            case .trueLiteral, .falseLiteral:
                append(token.raw, role: .hierarchy(level: indentation, style: .value))
            case .nullLiteral:
                append(token.raw, role: .hierarchy(level: indentation, style: .value))
            }
        }

        if !output.isEmpty { output += "\n" }
        return (output, spans)
    }

    private func matchingClose(for kind: JSONTokenKind) -> JSONTokenKind? {
        switch kind {
        case .leftBrace: return .rightBrace
        case .leftBracket: return .rightBracket
        default: return nil
        }
    }

    private func matchingOpen(for kind: JSONTokenKind) -> JSONTokenKind? {
        switch kind {
        case .rightBrace: return .leftBrace
        case .rightBracket: return .leftBracket
        default: return nil
        }
    }
}
