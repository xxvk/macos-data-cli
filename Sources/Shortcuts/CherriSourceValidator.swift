import Core
import CryptoKit
import Foundation

public struct CherriSourceInspection: Equatable, Sendable {
    public let sourceBytes: Int
    public let sourceSHA256: String
    public let declaredName: String
    public let includeCount: Int
}

public struct CherriSourceValidator: Sendable {
    public static let maximumSourceBytes = 256 * 1024

    private static let allowedIncludes: Set<String> = [
        "stdlib",
        "actions/a11y", "actions/calendar", "actions/contacts", "actions/crypto",
        "actions/device", "actions/documents", "actions/dropbox", "actions/images",
        "actions/intelligence", "actions/location", "actions/mac", "actions/math",
        "actions/media", "actions/music", "actions/network", "actions/pdf",
        "actions/photos", "actions/settings", "actions/sharing", "actions/shortcuts",
        "actions/text", "actions/translation", "actions/web",
    ]

    public init() {}

    public func validate(_ data: Data) throws -> CherriSourceInspection {
        guard data.count <= Self.maximumSourceBytes else { throw ShortcutsError.authorSourceTooLarge }
        guard let source = String(data: data, encoding: .utf8), !source.contains("\0") else {
            throw ShortcutsError.authorSourceInvalid
        }

        let names = captures(#"(?m)^\s*#define\s+name\s+(.+?)\s*$"#, in: source)
        guard names.count == 1 else { throw ShortcutsError.authorSourceInvalid }
        let name = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !name.isEmpty, name.count <= 200, Data(name.utf8).count <= 240,
              !name.contains("/"), !name.contains(":"), name != ".", name != "..",
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ShortcutsError.authorSourceInvalid
        }

        let includeLines = captures(#"(?m)^\s*#include\s+([^\r\n]+)$"#, in: source)
        for raw in includeLines {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2,
                  let first = value.first, first == "'" || first == "\"",
                  value.last == first else { throw ShortcutsError.authorSourceForbidden }
            let include = String(value.dropFirst().dropLast())
            guard Self.allowedIncludes.contains(include) else { throw ShortcutsError.authorSourceForbidden }
        }

        let forbiddenPatterns = [
            #"(?mi)^\s*#ref\b"#,
            #"(?i)\b(?:embedFile|base64File|rawAction)\s*\("#,
            #"(?mi)^\s*action\s+['\"]"#,
            #"(?i)\b(?:api[_-]?key|api[_-]?token|apikey|apitoken|access[_-]?token|accesstoken|secret|password|authorization|bearer)\b\s*="#,
            #"(?i)(?:api[_-]?key|api[_-]?token|access[_-]?token|password|secret)=[^&\s\"']+"#,
            #"(?i)\bbearer\s+[a-z0-9._-]{12,}"#,
        ]
        guard !forbiddenPatterns.contains(where: { matches($0, in: source) }) else {
            throw ShortcutsError.authorSourceForbidden
        }

        return CherriSourceInspection(
            sourceBytes: data.count,
            sourceSHA256: Self.hash(data),
            declaredName: name,
            includeCount: includeLines.count
        )
    }

    private func captures(_ pattern: String, in source: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let valueRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[valueRange])
        }
    }

    private func matches(_ pattern: String, in source: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return true }
        return expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
