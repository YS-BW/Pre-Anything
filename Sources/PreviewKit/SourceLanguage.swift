import Foundation

public enum SourceLanguage: String, CaseIterable, Sendable {
    case swift
    case objectiveC = "objective-c"
    case c
    case cpp
    case csharp
    case java
    case javascript
    case typescript
    case kotlin
    case go
    case rust
    case python
    case ruby
    case shell
    case sql
    case css
    case plainText = "plain-text"

    public static func detect(url: URL) -> SourceLanguage {
        language(forPathExtension: url.pathExtension)
    }

    public static func language(forPathExtension pathExtension: String) -> SourceLanguage {
        switch pathExtension.lowercased() {
        case "swift": .swift
        case "m", "mm": .objectiveC
        case "c", "h": .c
        case "cc", "cpp", "cxx", "hh", "hpp", "hxx": .cpp
        case "cs": .csharp
        case "java": .java
        case "js", "jsx", "mjs", "cjs": .javascript
        case "ts", "tsx", "mts", "cts": .typescript
        case "kt", "kts": .kotlin
        case "go": .go
        case "rs": .rust
        case "py", "pyw", "pyi": .python
        case "rb": .ruby
        case "sh", "bash", "zsh": .shell
        case "sql": .sql
        case "css": .css
        default: .plainText
        }
    }
}
