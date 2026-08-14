import Foundation

public struct NotesPermissionResult: Codable, Equatable, Sendable {
    public let access: NotesAutomationStatus
    public let readable: Bool
    public let complete: Bool
    public let requested: Bool

    public init(access: NotesAutomationStatus, requested: Bool) {
        self.access = access
        self.readable = access.readable
        self.complete = access.complete
        self.requested = requested
    }
}

public struct NotesAccountPayload: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public let folderCount: Int

    public init(id: String, name: String, isDefault: Bool, folderCount: Int) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.folderCount = folderCount
    }
}

public struct NotesAccountListResult: Codable, Equatable, Sendable {
    public let accounts: [NotesAccountPayload]
    public let complete: Bool

    public init(accounts: [NotesAccountPayload], complete: Bool) {
        self.accounts = accounts
        self.complete = complete
    }
}

public struct NotesFolderPayload: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let parentID: String?
    public let name: String
    public let shared: Bool
    public let depth: Int

    public init(id: String, accountID: String, parentID: String?, name: String, shared: Bool, depth: Int) {
        self.id = id
        self.accountID = accountID
        self.parentID = parentID
        self.name = name
        self.shared = shared
        self.depth = depth
    }
}

public struct NotesNotePayload: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let folderID: String
    public let title: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let passwordProtected: Bool
    public let shared: Bool

    public init(
        id: String,
        accountID: String,
        folderID: String,
        title: String,
        creationDate: Date?,
        modificationDate: Date?,
        passwordProtected: Bool,
        shared: Bool
    ) {
        self.id = id
        self.accountID = accountID
        self.folderID = folderID
        self.title = title
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.passwordProtected = passwordProtected
        self.shared = shared
    }
}

public struct NotesQuery: Equatable, Sendable {
    public let accountID: String?
    public let folderID: String?
    public let title: String?
    public let modifiedAfter: Date?
    public let limit: Int
    public let cursor: String?

    public init(
        accountID: String? = nil,
        folderID: String? = nil,
        title: String? = nil,
        modifiedAfter: Date? = nil,
        limit: Int = Pagination.defaultLimit,
        cursor: String? = nil
    ) {
        self.accountID = accountID
        self.folderID = folderID
        self.title = title
        self.modifiedAfter = modifiedAfter
        self.limit = limit
        self.cursor = cursor
    }
}

public enum NotesBodyFormat: String, Codable, Equatable, Sendable {
    case none
    case plaintext
    case html
}

public struct NotesGetResult: Codable, Equatable, Sendable {
    public let note: NotesNotePayload
    public let bodyFormat: NotesBodyFormat
    public let body: String?
    public let bodyBytes: Int?
    public let attachmentsIncluded: Bool
    public let attachments: [NotesAttachmentPayload]?
    public let attachmentsComplete: Bool?

    public init(
        note: NotesNotePayload,
        bodyFormat: NotesBodyFormat,
        body: String?,
        bodyBytes: Int?,
        attachmentsIncluded: Bool = false,
        attachments: [NotesAttachmentPayload]? = nil,
        attachmentsComplete: Bool? = nil
    ) {
        self.note = note
        self.bodyFormat = bodyFormat
        self.body = body
        self.bodyBytes = bodyBytes
        self.attachmentsIncluded = attachmentsIncluded
        self.attachments = attachments
        self.attachmentsComplete = attachmentsComplete
    }
}

public struct NotesAttachmentPayload: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let contentIdentifier: String?
    public let url: String?
    public let shared: Bool

    public init(id: String, name: String, creationDate: Date?, modificationDate: Date?, contentIdentifier: String?, url: String?, shared: Bool) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.contentIdentifier = contentIdentifier
        self.url = url
        self.shared = shared
    }
}

private struct NotesAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public struct NotesCreateInput: Codable, Equatable, Sendable {
    public let folderID: String
    public let title: String
    public let bodyFormat: NotesBodyFormat
    public let body: String

    private enum CodingKeys: String, CodingKey, CaseIterable { case folderID, title, bodyFormat, body }

    public init(folderID: String, title: String, bodyFormat: NotesBodyFormat, body: String) {
        self.folderID = folderID; self.title = title; self.bodyFormat = bodyFormat; self.body = body
    }

    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes create field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        folderID = try values.decode(String.self, forKey: .folderID)
        title = try values.decode(String.self, forKey: .title)
        bodyFormat = try values.decode(NotesBodyFormat.self, forKey: .bodyFormat)
        body = try values.decode(String.self, forKey: .body)
    }
}

public struct NotesRenameInput: Codable, Equatable, Sendable {
    public let title: String
    public let expectedModificationDate: Date
    private enum CodingKeys: String, CodingKey, CaseIterable { case title, expectedModificationDate }
    public init(title: String, expectedModificationDate: Date) { self.title = title; self.expectedModificationDate = expectedModificationDate }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes rename field")) }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        expectedModificationDate = try values.decode(Date.self, forKey: .expectedModificationDate)
    }
}

public struct NotesMoveInput: Codable, Equatable, Sendable {
    public let destinationFolderID: String
    public let expectedModificationDate: Date
    private enum CodingKeys: String, CodingKey, CaseIterable { case destinationFolderID, expectedModificationDate }
    public init(destinationFolderID: String, expectedModificationDate: Date) { self.destinationFolderID = destinationFolderID; self.expectedModificationDate = expectedModificationDate }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes move field")) }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        destinationFolderID = try values.decode(String.self, forKey: .destinationFolderID)
        expectedModificationDate = try values.decode(Date.self, forKey: .expectedModificationDate)
    }
}

public struct NotesDeleteInput: Codable, Equatable, Sendable {
    public let expectedModificationDate: Date
    private enum CodingKeys: String, CodingKey, CaseIterable { case expectedModificationDate }
    public init(expectedModificationDate: Date) { self.expectedModificationDate = expectedModificationDate }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes delete field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        expectedModificationDate = try values.decode(Date.self, forKey: .expectedModificationDate)
    }
}

public struct NotesEditBodyInput: Codable, Equatable, Sendable {
    public let bodyFormat: NotesBodyFormat
    public let body: String
    public let expectedModificationDate: Date
    public let expectedBodySHA256: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case bodyFormat, body, expectedModificationDate, expectedBodySHA256
    }

    public init(bodyFormat: NotesBodyFormat, body: String, expectedModificationDate: Date, expectedBodySHA256: String) {
        self.bodyFormat = bodyFormat
        self.body = body
        self.expectedModificationDate = expectedModificationDate
        self.expectedBodySHA256 = expectedBodySHA256
    }

    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes edit-body field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bodyFormat = try values.decode(NotesBodyFormat.self, forKey: .bodyFormat)
        body = try values.decode(String.self, forKey: .body)
        expectedModificationDate = try values.decode(Date.self, forKey: .expectedModificationDate)
        expectedBodySHA256 = try values.decode(String.self, forKey: .expectedBodySHA256)
    }
}

public struct NotesFolderCreateInput: Codable, Equatable, Sendable {
    public let name: String
    public let parentFolderID: String?
    private enum CodingKeys: String, CodingKey, CaseIterable { case name, parentFolderID }
    public init(name: String, parentFolderID: String?) { self.name = name; self.parentFolderID = parentFolderID }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes folder create field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.parentFolderID) else {
            throw DecodingError.keyNotFound(CodingKeys.parentFolderID, .init(codingPath: decoder.codingPath, debugDescription: "parentFolderID must be explicit; use null for account root"))
        }
        name = try values.decode(String.self, forKey: .name)
        parentFolderID = try values.decodeIfPresent(String.self, forKey: .parentFolderID)
    }
}

public struct NotesFolderRenameInput: Codable, Equatable, Sendable {
    public let name: String
    public let expectedNameSHA256: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case name, expectedNameSHA256 }
    public init(name: String, expectedNameSHA256: String) { self.name = name; self.expectedNameSHA256 = expectedNameSHA256 }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes folder rename field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        expectedNameSHA256 = try values.decode(String.self, forKey: .expectedNameSHA256)
    }
}

public struct NotesFolderMoveInput: Codable, Equatable, Sendable {
    public let destinationParentFolderID: String?
    public let expectedParentFolderID: String?
    public let expectedNameSHA256: String
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case destinationParentFolderID, expectedParentFolderID, expectedNameSHA256
    }
    public init(destinationParentFolderID: String?, expectedParentFolderID: String?, expectedNameSHA256: String) {
        self.destinationParentFolderID = destinationParentFolderID
        self.expectedParentFolderID = expectedParentFolderID
        self.expectedNameSHA256 = expectedNameSHA256
    }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes folder move field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.destinationParentFolderID), values.contains(.expectedParentFolderID) else {
            throw DecodingError.keyNotFound(CodingKeys.expectedParentFolderID, .init(codingPath: decoder.codingPath, debugDescription: "Folder parent fields must be explicit; use null for account root"))
        }
        destinationParentFolderID = try values.decodeIfPresent(String.self, forKey: .destinationParentFolderID)
        expectedParentFolderID = try values.decodeIfPresent(String.self, forKey: .expectedParentFolderID)
        expectedNameSHA256 = try values.decode(String.self, forKey: .expectedNameSHA256)
    }
}

public struct NotesFolderDeleteInput: Codable, Equatable, Sendable {
    public let expectedParentFolderID: String?
    public let expectedNameSHA256: String
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectedParentFolderID, expectedNameSHA256
    }
    public init(expectedParentFolderID: String?, expectedNameSHA256: String) {
        self.expectedParentFolderID = expectedParentFolderID
        self.expectedNameSHA256 = expectedNameSHA256
    }
    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: NotesAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard dynamic.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Notes folder delete field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.expectedParentFolderID) else {
            throw DecodingError.keyNotFound(CodingKeys.expectedParentFolderID, .init(codingPath: decoder.codingPath, debugDescription: "expectedParentFolderID must be explicit; use null for account root"))
        }
        expectedParentFolderID = try values.decodeIfPresent(String.self, forKey: .expectedParentFolderID)
        expectedNameSHA256 = try values.decode(String.self, forKey: .expectedNameSHA256)
    }
}

public struct NotesWriteAccountBinding: Codable, Equatable, Sendable {
    public let version: Int
    public let accountID: String
    public let boundAt: Date
    public init(accountID: String, boundAt: Date, version: Int = 1) { self.version = version; self.accountID = accountID; self.boundAt = boundAt }
}

public struct NotesWriteAccountStatus: Codable, Equatable, Sendable {
    public let bound: Bool
    public let valid: Bool
    public let accountID: String?
    public let boundAt: Date?
    public init(bound: Bool, valid: Bool, accountID: String?, boundAt: Date?) { self.bound = bound; self.valid = valid; self.accountID = accountID; self.boundAt = boundAt }
}

public struct NotesWriteAccountChangeResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let accountID: String?
    public init(operation: String, dryRun: Bool, changed: Bool, accountID: String?) { self.operation = operation; self.dryRun = dryRun; self.changed = changed; self.accountID = accountID }
}

public enum NotesWriteVerification: String, Codable, Equatable, Sendable {
    case readbackConfirmed = "readback_confirmed"
    case saveAcceptedReadbackPending = "save_accepted_readback_pending"
    case outcomeUnknown = "outcome_unknown"
    case idempotencyReceiptReadbackConfirmed = "idempotency_receipt_readback_confirmed"
    case idempotencyReceiptPending = "idempotency_receipt_pending"
}

public struct NotesWritePreview: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let noteID: String?
    public let accountID: String
    public let sourceFolderID: String?
    public let destinationFolderID: String?
    public let expectedModificationDate: Date?
    public let titleSHA256: String?
    public let previousBodySHA256: String?
    public let bodySHA256: String?
    public let bodyBytes: Int?
    public var title: String? { nil }
    public var body: String? { nil }
    public init(operation: String, changed: Bool, noteID: String?, accountID: String, sourceFolderID: String?, destinationFolderID: String?, expectedModificationDate: Date?, titleSHA256: String?, previousBodySHA256: String? = nil, bodySHA256: String?, bodyBytes: Int?) {
        self.operation = operation; self.dryRun = true; self.changed = changed; self.noteID = noteID; self.accountID = accountID; self.sourceFolderID = sourceFolderID; self.destinationFolderID = destinationFolderID; self.expectedModificationDate = expectedModificationDate; self.titleSHA256 = titleSHA256; self.previousBodySHA256 = previousBodySHA256; self.bodySHA256 = bodySHA256; self.bodyBytes = bodyBytes
    }
}

public struct NotesWriteResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let verification: NotesWriteVerification
    public let noteID: String?
    public let previousNoteID: String?
    public let accountID: String
    public let folderID: String
    public let modificationDate: Date?
    public let titleSHA256: String?
    public let bodySHA256: String?
    public let bodyBytes: Int?
    public let identityChanged: Bool?
    public let deduplicated: Bool
    public let nextAction: String?
    public init(operation: String, changed: Bool, verification: NotesWriteVerification, noteID: String?, previousNoteID: String? = nil, accountID: String, folderID: String, modificationDate: Date?, titleSHA256: String?, bodySHA256: String? = nil, bodyBytes: Int? = nil, identityChanged: Bool? = nil, deduplicated: Bool = false, nextAction: String? = nil) {
        self.operation = operation; self.dryRun = false; self.changed = changed; self.verification = verification; self.noteID = noteID; self.previousNoteID = previousNoteID; self.accountID = accountID; self.folderID = folderID; self.modificationDate = modificationDate; self.titleSHA256 = titleSHA256; self.bodySHA256 = bodySHA256; self.bodyBytes = bodyBytes; self.identityChanged = identityChanged; self.deduplicated = deduplicated; self.nextAction = nextAction
    }
}

public struct NotesFolderWritePreview: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let folderID: String?
    public let accountID: String
    public let sourceParentFolderID: String?
    public let destinationParentFolderID: String?
    public let previousNameSHA256: String?
    public let nameSHA256: String
    public var name: String? { nil }
    public init(operation: String, changed: Bool, folderID: String?, accountID: String, sourceParentFolderID: String?, destinationParentFolderID: String?, previousNameSHA256: String?, nameSHA256: String) {
        self.operation = operation; self.dryRun = true; self.changed = changed
        self.folderID = folderID; self.accountID = accountID
        self.sourceParentFolderID = sourceParentFolderID; self.destinationParentFolderID = destinationParentFolderID
        self.previousNameSHA256 = previousNameSHA256; self.nameSHA256 = nameSHA256
    }
}

public struct NotesFolderWriteResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let verification: NotesWriteVerification
    public let folderID: String?
    public let previousFolderID: String?
    public let accountID: String
    public let parentFolderID: String?
    public let nameSHA256: String
    public let identityChanged: Bool?
    public let deduplicated: Bool
    public let nextAction: String?
    public init(operation: String, changed: Bool, verification: NotesWriteVerification, folderID: String?, previousFolderID: String? = nil, accountID: String, parentFolderID: String?, nameSHA256: String, identityChanged: Bool? = nil, deduplicated: Bool = false, nextAction: String? = nil) {
        self.operation = operation; self.dryRun = false; self.changed = changed; self.verification = verification
        self.folderID = folderID; self.previousFolderID = previousFolderID; self.accountID = accountID
        self.parentFolderID = parentFolderID; self.nameSHA256 = nameSHA256; self.identityChanged = identityChanged
        self.deduplicated = deduplicated; self.nextAction = nextAction
    }
}
