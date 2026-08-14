import AppKit
import Core
import CryptoKit
import Foundation

public struct PreparedNotesCreate: Equatable, Sendable {
    public let html: String
    public let titleSHA256: String
    public let bodySHA256: String
    public let bodyBytes: Int
    public let expectedPlaintext: String
}

public struct PreparedNotesBodyEdit: Equatable, Sendable {
    public let html: String
    public let bodySHA256: String
    public let bodyBytes: Int
    public let expectedPlaintext: String
}

public enum NotesWritePolicy {
    private static let bodyHashPattern = try! NSRegularExpression(pattern: "^[0-9a-f]{64}$")
    private static let htmlTagPattern = try! NSRegularExpression(pattern: "<\\s*/?\\s*([A-Za-z0-9]+)\\b[^>]*>")
    private static let safeReplaceableTags: Set<String> = [
        "html", "head", "meta", "body", "div", "p", "span", "br",
        "b", "strong", "i", "em", "u", "s", "strike", "font",
        "h1", "h2", "h3", "h4", "h5", "h6"
    ]

    public static func prepare(_ input: NotesCreateInput) throws -> PreparedNotesCreate {
        guard !input.folderID.isEmpty, !input.title.isEmpty, input.title.count <= 200,
              input.bodyFormat != .none else { throw NotesError.invalidWriteInput }
        let bytes = input.body.lengthOfBytes(using: .utf8)
        guard bytes <= NotesBodyPolicy.maximumBytes else { throw NotesError.bodyTooLarge }
        let title = escapeHTML(input.title)
        let content: String
        switch input.bodyFormat {
        case .plaintext:
            content = escapeHTML(input.body).replacingOccurrences(of: "\n", with: "<br>")
        case .html:
            content = input.body
        case .none:
            throw NotesError.invalidWriteInput
        }
        let html = "<div>\(title)</div><div>\(content)</div>"
        let expectedPlaintext: String
        if input.bodyFormat == .plaintext {
            expectedPlaintext = input.title + "\n" + input.body + "\n"
        } else {
            guard let data = html.data(using: .utf8),
                  let rendered = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil).string else {
                throw NotesError.invalidWriteInput
            }
            expectedPlaintext = rendered
        }
        return PreparedNotesCreate(
            html: html,
            titleSHA256: sha256(input.title),
            bodySHA256: sha256(expectedPlaintext),
            bodyBytes: bytes,
            expectedPlaintext: expectedPlaintext
        )
    }

    public static func validateTitle(_ title: String) throws {
        guard !title.isEmpty, title.count <= 200 else { throw NotesError.invalidWriteInput }
    }

    public static func prepareBodyEdit(_ input: NotesEditBodyInput, title: String) throws -> PreparedNotesBodyEdit {
        try validateBodyEditInput(input)
        let bytes = input.body.lengthOfBytes(using: .utf8)
        let content: String
        switch input.bodyFormat {
        case .plaintext:
            content = escapeHTML(input.body).replacingOccurrences(of: "\n", with: "<br>")
        case .html:
            content = input.body
        case .none:
            throw NotesError.invalidWriteInput
        }
        let html = "<div>\(escapeHTML(title))</div><div>\(content)</div>"
        let expectedPlaintext: String
        if input.bodyFormat == .plaintext {
            expectedPlaintext = title + "\n" + input.body + "\n"
        } else {
            guard let data = html.data(using: .utf8),
                  let rendered = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: nil
                  ).string else { throw NotesError.invalidWriteInput }
            expectedPlaintext = rendered
        }
        return PreparedNotesBodyEdit(
            html: html,
            bodySHA256: sha256(expectedPlaintext),
            bodyBytes: bytes,
            expectedPlaintext: expectedPlaintext
        )
    }

    public static func validateBodyEditInput(_ input: NotesEditBodyInput) throws {
        guard input.bodyFormat != .none, isValidSHA256(input.expectedBodySHA256) else {
            throw NotesError.invalidWriteInput
        }
        guard input.body.lengthOfBytes(using: .utf8) <= NotesBodyPolicy.maximumBytes else {
            throw NotesError.bodyTooLarge
        }
    }

    public static func validateFolderName(_ name: String) throws {
        guard !name.isEmpty, name.count <= 200,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw NotesError.invalidWriteInput
        }
    }

    public static func validateFolderNameHash(_ value: String) throws {
        guard isValidSHA256(value) else { throw NotesError.invalidWriteInput }
    }

    public static func folderNamesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func isFolderDescendant(
        candidateScriptingID: String,
        of ancestorScriptingID: String,
        folders: [NotesFolderDescriptor]
    ) -> Bool {
        var parents: [String: String?] = [:]
        for folder in folders {
            guard !parents.keys.contains(folder.scriptingID) else { return false }
            parents[folder.scriptingID] = folder.parentScriptingID
        }
        var current: String? = candidateScriptingID
        var visited = Set<String>()
        while let value = current, visited.insert(value).inserted {
            if value == ancestorScriptingID { return candidateScriptingID != ancestorScriptingID }
            current = parents[value] ?? nil
        }
        return false
    }

    public static func isSafeReplaceableHTML(_ html: String) -> Bool {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = htmlTagPattern.matches(in: html, range: range)
        guard !matches.isEmpty else { return false }
        return matches.allSatisfy { match in
            guard let tagRange = Range(match.range(at: 1), in: html) else { return false }
            return safeReplaceableTags.contains(html[tagRange].lowercased())
        }
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        bodyHashPattern.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) != nil
    }

    public static func modificationDatesMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        Int64(lhs.timeIntervalSince1970.rounded(.down)) == Int64(rhs.timeIntervalSince1970.rounded(.down))
    }

    public static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
