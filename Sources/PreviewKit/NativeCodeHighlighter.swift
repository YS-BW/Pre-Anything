import Foundation

/// A bounded, dependency-free lexer for fenced Markdown code blocks.
///
/// It intentionally highlights stable lexical categories rather than trying to
/// build a complete compiler frontend for every language. Unknown languages
/// still receive string, comment, and number highlighting.
enum NativeCodeHighlighter {
    static func spans(source: String, language rawLanguage: String?) -> [PreviewStyleSpan] {
        guard !source.isEmpty else { return [] }

        let language = normalize(rawLanguage)
        let profile = Profile.profile(for: language)
        let fullRange = NSRange(location: 0, length: source.utf16.count)
        var occupied: [NSRange] = []
        var spans: [PreviewStyleSpan] = []

        func addMatches(
            _ pattern: String,
            role: PreviewStyleRole,
            options: NSRegularExpression.Options = [],
            captureGroup: Int = 0
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in expression.matches(in: source, range: fullRange) {
                guard captureGroup < match.numberOfRanges else { continue }
                let range = match.range(at: captureGroup)
                guard range.length > 0, !occupied.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
                    continue
                }
                occupied.append(range)
                spans.append(PreviewStyleSpan(location: range.location, length: range.length, role: role))
            }
        }

        for pattern in profile.commentPatterns {
            addMatches(pattern, role: .comment)
        }

        for pattern in profile.stringPatterns {
            addMatches(pattern, role: .string)
        }

        addMatches(#"(?<![\p{L}\p{N}_])(?:0[xX][0-9A-Fa-f](?:_?[0-9A-Fa-f])*|0[bB][01](?:_?[01])*|(?:\d(?:_?\d)*)?(?:\.\d(?:_?\d)*)|\d(?:_?\d)*(?:[eE][+-]?\d(?:_?\d)*)?)(?![\p{L}\p{N}_])"#, role: .number)

        switch language {
        case "c", "cpp", "objective-c", "csharp":
            addMatches(#"(?m)^[\t ]*#[\t ]*[A-Za-z_][A-Za-z0-9_]*"#, role: .preprocessor)
        case "swift", "java", "kotlin", "python":
            addMatches(#"(?m)(?<![\p{L}\p{N}_])@[A-Za-z_][A-Za-z0-9_.]*"#, role: .attribute)
        case "rust":
            addMatches(#"#\!?\[[^\]\r\n]+\]"#, role: .attribute)
        default:
            break
        }

        if !profile.keywords.isEmpty {
            let words = profile.keywords
                .sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|")
            addMatches(
                #"(?<![\p{L}\p{N}_])(?:"# + words + #")(?![\p{L}\p{N}_])"#,
                role: .keyword,
                options: [.caseInsensitive]
            )
        }

        let types = typeNames(for: language)
        if !types.isEmpty {
            let words = types
                .sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|")
            addMatches(
                #"(?<![\p{L}\p{N}_])(?:"# + words + #")(?![\p{L}\p{N}_])"#,
                role: .type
            )
        }

        addMatches(
            #"(?<![\p{L}\p{N}_])(?:class|struct|enum|protocol|interface|trait|record|typealias|type)[\t ]+([A-Za-z_][A-Za-z0-9_]*)"#,
            role: .type,
            captureGroup: 1
        )
        addMatches(
            #"(?<![.\p{L}\p{N}_])([A-Za-z_][A-Za-z0-9_]*)[\t ]*(?=\()"#,
            role: .function,
            captureGroup: 1
        )

        if profile.highlightsMarkupTags {
            addMatches(#"</?[A-Za-z][^>]*?>"#, role: .keyword)
        }

        return spans.sorted {
            if $0.location == $1.location { return $0.length > $1.length }
            return $0.location < $1.location
        }
    }

    private static func normalize(_ language: String?) -> String {
        let value = language?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let aliases: [String: String] = [
            "c++": "cpp", "cplusplus": "cpp", "objc": "objective-c", "objectivec": "objective-c",
            "js": "javascript", "jsx": "javascript", "ts": "typescript", "tsx": "typescript",
            "py": "python", "rb": "ruby", "sh": "shell", "bash": "shell", "zsh": "shell",
            "yml": "yaml", "html": "markup", "xml": "markup", "svg": "markup",
            "md": "markdown", "rs": "rust", "kt": "kotlin", "golang": "go",
        ]
        return aliases[value] ?? value
    }

    private static func typeNames(for language: String) -> Set<String> {
        switch language {
        case "swift":
            ["Any", "AnyObject", "Bool", "Character", "Double", "Float", "Int", "Never", "Self", "String", "UInt", "Void"]
        case "c", "cpp", "objective-c":
            ["bool", "char", "double", "float", "id", "int", "long", "short", "signed", "size_t", "unsigned", "void", "wchar_t"]
        case "java", "kotlin":
            ["boolean", "byte", "char", "double", "float", "int", "long", "short", "String", "Unit", "void"]
        case "csharp":
            ["bool", "byte", "char", "decimal", "double", "float", "int", "long", "object", "sbyte", "short", "string", "uint", "ulong", "ushort"]
        case "javascript", "typescript":
            ["any", "bigint", "boolean", "never", "number", "object", "string", "symbol", "unknown", "void"]
        case "python":
            ["bool", "bytes", "dict", "float", "frozenset", "int", "list", "object", "set", "str", "tuple"]
        case "go":
            ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"]
        case "rust":
            ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16", "u32", "u64", "u128", "usize"]
        default:
            []
        }
    }
}

private struct Profile {
    let keywords: Set<String>
    let commentPatterns: [String]
    let stringPatterns: [String]
    let highlightsMarkupTags: Bool

    static func profile(for language: String) -> Profile {
        let cComments = [#"(?s)/\*.*?\*/"#, #"(?m)//[^\r\n]*$"#]
        let hashComments = [#"(?m)#[^\r\n]*$"#]
        let sqlComments = [#"(?s)/\*.*?\*/"#, #"(?m)--[^\r\n]*$"#]
        let commonStrings = [
            #"(?s)\"\"\"(?:\\.|.)*?\"\"\""#,
            #"(?s)'''(?:\\.|.)*?'''"#,
            #"\"(?:\\.|[^\"\\])*\""#,
            #"'(?:\\.|[^'\\])*'"#,
            #"`(?:\\.|[^`\\])*`"#,
        ]

        let cFamily: Set<String> = [
            "abstract", "actor", "as", "async", "await", "break", "case", "catch", "class", "const",
            "continue", "default", "defer", "do", "else", "enum", "extension", "false", "final", "for",
            "func", "function", "guard", "if", "implements", "import", "in", "interface", "internal", "is",
            "let", "mutating", "new", "nil", "null", "operator", "override", "package", "private", "protocol",
            "public", "repeat", "return", "self", "static", "struct", "super", "switch", "this", "throw",
            "throws", "true", "try", "typealias", "typeof", "using", "var", "virtual", "void", "where", "while",
        ]

        switch language {
        case "swift", "c", "cpp", "objective-c", "java", "javascript", "typescript", "kotlin", "go", "rust", "csharp":
            return Profile(keywords: cFamily, commentPatterns: cComments, stringPatterns: commonStrings, highlightsMarkupTags: false)
        case "python":
            return Profile(
                keywords: ["and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"],
                commentPatterns: hashComments,
                stringPatterns: commonStrings,
                highlightsMarkupTags: false
            )
        case "ruby":
            return Profile(keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield"], commentPatterns: hashComments, stringPatterns: commonStrings, highlightsMarkupTags: false)
        case "shell":
            return Profile(keywords: ["case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in", "local", "readonly", "select", "then", "until", "while"], commentPatterns: hashComments, stringPatterns: commonStrings, highlightsMarkupTags: false)
        case "sql":
            return Profile(keywords: ["ALL", "ALTER", "AND", "AS", "ASC", "BEGIN", "BETWEEN", "BY", "CASE", "CREATE", "DELETE", "DESC", "DISTINCT", "DROP", "ELSE", "END", "EXISTS", "FROM", "FULL", "GROUP", "HAVING", "IN", "INNER", "INSERT", "INTO", "IS", "JOIN", "LEFT", "LIKE", "LIMIT", "NOT", "NULL", "ON", "OR", "ORDER", "OUTER", "PRIMARY", "REFERENCES", "RIGHT", "SELECT", "SET", "TABLE", "THEN", "UNION", "UNIQUE", "UPDATE", "VALUES", "WHEN", "WHERE", "WITH"], commentPatterns: sqlComments, stringPatterns: commonStrings, highlightsMarkupTags: false)
        case "json":
            return Profile(keywords: ["false", "null", "true"], commentPatterns: [], stringPatterns: commonStrings, highlightsMarkupTags: false)
        case "yaml", "toml":
            return Profile(keywords: ["false", "null", "true", "yes", "no"], commentPatterns: hashComments, stringPatterns: commonStrings, highlightsMarkupTags: false)
        case "markup":
            return Profile(keywords: [], commentPatterns: [#"(?s)<!--.*?-->"#], stringPatterns: commonStrings, highlightsMarkupTags: true)
        case "css":
            return Profile(keywords: ["@charset", "@font-face", "@import", "@keyframes", "@media", "@supports", "important"], commentPatterns: [#"(?s)/\*.*?\*/"#], stringPatterns: commonStrings, highlightsMarkupTags: false)
        default:
            return Profile(keywords: [], commentPatterns: cComments + hashComments, stringPatterns: commonStrings, highlightsMarkupTags: false)
        }
    }
}
