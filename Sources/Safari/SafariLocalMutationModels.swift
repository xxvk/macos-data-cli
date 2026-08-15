import Foundation

public enum SafariLocalMutationCommand: String, Sendable {
    case bookmarkCreate = "bookmark_create"
    case bookmarkEdit = "bookmark_edit"
    case bookmarkMove = "bookmark_move"
    case bookmarkDelete = "bookmark_delete"
    case folderCreate = "folder_create"
    case folderRename = "folder_rename"
    case folderMove = "folder_move"
    case folderDelete = "folder_delete"
}

public struct SafariLocalMutationInput: Sendable {
    public static let maximumInputBytes = 32 * 1024
    public let command: SafariLocalMutationCommand
    public let id: String?
    public let parentID: String?
    public let index: Int?
    public let title: String?
    public let url: String?
    public let expectedSourceSHA256: String?

    public static func decode(_ data: Data, command: SafariLocalMutationCommand) throws -> Self {
        guard !data.isEmpty, data.count <= maximumInputBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { throw SafariError.invalidInput }
        let required: Set<String>
        switch command {
        case .bookmarkCreate: required = ["parentID", "index", "title", "url"]
        case .bookmarkEdit: required = ["id", "title", "url"]
        case .bookmarkMove, .folderMove: required = ["id", "parentID", "index"]
        case .bookmarkDelete, .folderDelete: required = ["id"]
        case .folderCreate: required = ["parentID", "index", "title"]
        case .folderRename: required = ["id", "title"]
        }
        let allowed = required.union(["expectedSourceSHA256"])
        guard Set(dictionary.keys).isSubset(of: allowed), required.isSubset(of: Set(dictionary.keys)),
              dictionary.allSatisfy({ key, value in
                  key == "index" ? value is NSNumber : value is String
              }) else { throw SafariError.invalidInput }
        let index = (dictionary["index"] as? NSNumber)?.intValue
        if let index, index < 0 { throw SafariError.invalidInput }
        let expected = dictionary["expectedSourceSHA256"] as? String
        if let expected, !Self.validDigest(expected) { throw SafariError.invalidInput }
        return .init(
            command: command,
            id: dictionary["id"] as? String,
            parentID: dictionary["parentID"] as? String,
            index: index,
            title: dictionary["title"] as? String,
            url: dictionary["url"] as? String,
            expectedSourceSHA256: expected
        )
    }

    private init(command: SafariLocalMutationCommand, id: String?, parentID: String?, index: Int?, title: String?, url: String?, expectedSourceSHA256: String?) {
        self.command = command
        self.id = id
        self.parentID = parentID
        self.index = index
        self.title = title
        self.url = url
        self.expectedSourceSHA256 = expectedSourceSHA256
    }

    private static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

public struct SafariLocalMutationResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let targetID: String?
    public let parentID: String?
    public let sourceSHA256Before: String
    public let sourceSHA256After: String
    public let syncStatus: String
    public let verification: String
    public let recoverySessionID: String?
    public let nextAction: String?
}
