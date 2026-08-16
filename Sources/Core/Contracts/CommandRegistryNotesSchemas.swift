extension CommandRegistry {
    static let notesSchemas: [String: JSONSchema] = [
        "NotesAccountPayload": .object(description: "A Notes account.", properties: [
            "id": .string("Opaque account ID.", example: .string("acct_notes")), "name": .string("Account display name.", example: .string("iCloud")), "isDefault": .boolean("Whether this is the default account.", example: .bool(true)), "folderCount": .integer("Number of folders in the account.", example: .integer(5)),
        ]),
        "NotesFolderPayload": .object(description: "A Notes folder.", properties: [
            "id": .string("Opaque folder ID.", example: .string("folder_2e9d7a")), "accountID": .string("Opaque account ID.", example: .string("acct_notes")), "parentID": .string("Opaque parent folder ID.", example: .string("root")), "name": .string("Folder display name.", example: .string("Projects")), "shared": .boolean("Whether the folder is shared.", example: .bool(false)), "depth": .integer("Nesting depth.", example: .integer(0)),
        ]),
        "NotesNotePayload": .object(description: "A note.", properties: [
            "id": .string("Opaque note ID.", example: .string("note_7f4a1b")), "accountID": .string("Opaque account ID.", example: .string("acct_notes")), "folderID": .string("Opaque folder ID.", example: .string("folder_2e9d7a")), "title": .string("Note title.", example: .string("Meeting notes")),
            "creationDate": .string("ISO 8601 creation timestamp.", example: .string("2026-08-15T09:00:00Z")), "modificationDate": .string("ISO 8601 modification timestamp.", example: .string("2026-08-15T09:00:00Z")), "passwordProtected": .boolean("Whether the note is password-protected.", example: .bool(false)), "shared": .boolean("Whether the note is shared.", example: .bool(false)),
        ]),
        "NotesCreateInput": .object(description: "Note create input.", properties: [
            "folderID": .string("Opaque folder ID.", minLength: 1, example: .string("folder_2e9d7a")), "title": .string("Note title.", minLength: 1, maxLength: 200, example: .string("Meeting notes")), "bodyFormat": .stringEnum(["plaintext", "html"], description: "Body format (plaintext or html)."), "body": .string("Note body text; UTF-8 encoding must not exceed 256 KiB.", example: .string("Discuss Q3 goals")),
        ]),
        "NotesRenameInput": .object(description: "Note rename input.", properties: [
            "title": .string("New note title.", minLength: 1, maxLength: 200, example: .string("Meeting notes (updated)")), "expectedModificationDate": .string("Expected current modification timestamp for stale detection.", format: "date-time", example: .string("2026-08-15T09:00:00Z")),
        ]),
        "NotesMoveInput": .object(description: "Note move input.", properties: [
            "destinationFolderID": .string("Opaque destination folder ID.", minLength: 1, example: .string("folder_2e9d7a")), "expectedModificationDate": .string("Expected current modification timestamp for stale detection.", format: "date-time", example: .string("2026-08-15T09:00:00Z")),
        ]),
        "NotesDeleteInput": .object(description: "Note soft-delete input.", properties: [
            "expectedModificationDate": .string("Expected current modification timestamp for stale detection.", format: "date-time", example: .string("2026-08-15T09:00:00Z")),
        ]),
        "NotesEditBodyInput": .object(description: "Note body replacement input.", properties: [
            "bodyFormat": .stringEnum(["plaintext", "html"], description: "Body format (plaintext or html)."), "body": .string("Replacement body text; UTF-8 encoding must not exceed 256 KiB.", example: .string("Updated notes")), "expectedModificationDate": .string("Expected current modification timestamp for stale detection.", format: "date-time", example: .string("2026-08-15T09:00:00Z")), "expectedBodySHA256": .string("Expected current body SHA-256 for stale detection.", pattern: "^[0-9a-f]{64}$", minLength: 64, maxLength: 64, example: .string("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")),
        ]),
        "NotesFolderCreateInput": .object(description: "Note folder create input.", properties: [
            "name": .string("New folder name.", minLength: 1, maxLength: 200, example: .string("Projects")), "parentFolderID": .string("Opaque parent folder ID; use null for the account root.", minLength: 1, nullable: true, example: .string("root")),
        ]),
        "NotesFolderRenameInput": .object(description: "Note folder rename input.", properties: [
            "name": .string("New folder name.", minLength: 1, maxLength: 200, example: .string("Projects (renamed)")), "expectedNameSHA256": .string("Expected current folder-name SHA-256 for stale detection.", pattern: "^[0-9a-f]{64}$", minLength: 64, maxLength: 64, example: .string("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")),
        ]),
        "NotesFolderMoveInput": .object(description: "Note folder move input.", properties: [
            "destinationParentFolderID": .string("Opaque destination parent folder ID, or null for the account root.", nullable: true), "expectedParentFolderID": .string("Expected current parent folder ID for stale detection; use null for the account root.", nullable: true),
            "expectedNameSHA256": .string("Expected current folder-name SHA-256 for stale detection.", pattern: "^[0-9a-f]{64}$", minLength: 64, maxLength: 64, example: .string("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")),
        ]),
        "NotesFolderDeleteInput": .object(description: "Empty note folder delete input.", properties: [
            "expectedParentFolderID": .string("Expected current parent folder ID for stale detection; use null for the account root.", nullable: true),
            "expectedNameSHA256": .string("Expected current folder-name SHA-256 for stale detection.", pattern: "^[0-9a-f]{64}$", minLength: 64, maxLength: 64, example: .string("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")),
        ]),
    ]
}
