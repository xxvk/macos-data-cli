/// Required-property metadata is kept separate from the schema prose so every
/// model can be audited in one compact table. An empty list is intentional for
/// patch or command-dependent inputs where no single property is always
/// required.
enum SchemaRequirements {
    private static let fields: [String: [String]] = [
        "AvatarWriteVerification": ["status", "saveAccepted", "requestedBytes"],
        "CalendarDescriptor": ["title", "identifier", "sourceIdentifier", "type", "allowsContentModifications"],
        "CalendarEventInput": ["title", "startDate", "endDate"],
        "CalendarEventPatch": [],
        "CalendarEventPayload": ["title", "startDate", "endDate", "allDay", "attendees", "alarms", "recurrenceRules", "status"],
        "CalendarSourceDescriptor": ["title", "identifier", "type", "isICloud"],
        "ContactContainer": ["name", "identifier", "type", "isICloud"],
        "ContactPatch": [],
        "ContactPayload": ["kind", "externalID", "emails", "phones", "urls", "addresses", "metadata", "imageAvailable"],
        "ContactWriteResult": ["operation", "contact"],
        "DataResource": ["id", "kind", "provider", "displayName", "capabilities"],
        "DataResourceCapabilities": ["readable", "writable", "selected", "permission"],
        "DataResourcesResult": ["resources", "limitations"],
        "LabeledValue": ["value"],
        "ListResult": ["items"],
        "MailAccountSummary": ["id", "kind", "mailboxCount", "totalCount", "unreadCount"],
        "MailMessageMetadata": ["id", "accountID", "mailboxID", "subject", "sender", "unread", "flagged", "hasAttachment", "sizeBytes", "cacheState"],
        "MailQueryResult": ["backend", "items", "truncated", "incomplete", "limitations"],
        "MailboxSummary": ["id", "accountID", "name", "totalCount", "unreadCount"],
        "MessagesPermissionStatus": ["readable", "fullDiskAccess", "limitations"],
        "MessagesRecentItem": ["id", "service", "isFromMe", "sentAt", "conversationId"],
        "MessagesRecentResult": ["items", "complete", "truncated", "limitations"],
        "NotesAccountPayload": ["id", "name", "isDefault", "folderCount"],
        "NotesCreateInput": ["folderID", "title", "bodyFormat", "body"],
        "NotesDeleteInput": ["expectedModificationDate"],
        "NotesEditBodyInput": ["bodyFormat", "body", "expectedModificationDate", "expectedBodySHA256"],
        "NotesFolderCreateInput": ["name", "parentFolderID"],
        "NotesFolderDeleteInput": ["expectedParentFolderID", "expectedNameSHA256"],
        "NotesFolderMoveInput": ["destinationParentFolderID", "expectedParentFolderID", "expectedNameSHA256"],
        "NotesFolderPayload": ["id", "accountID", "name", "shared", "depth"],
        "NotesFolderRenameInput": ["name", "expectedNameSHA256"],
        "NotesNotePayload": ["id", "accountID", "folderID", "title", "passwordProtected", "shared"],
        "NotesMoveInput": ["destinationFolderID", "expectedModificationDate"],
        "NotesRenameInput": ["title", "expectedModificationDate"],
        "Page": ["items", "limit", "truncated", "complete"],
        "PhoneCallItem": ["id", "direction", "kind", "answered", "missed", "durationSeconds", "at"],
        "PhoneCallsPermissionStatus": ["readable", "fullDiskAccess", "limitations"],
        "PhoneCallsRecentResult": ["items", "complete", "truncated", "limitations"],
        "PhotoAlbumPayload": ["id", "kind", "depth", "canContainAssets", "canContainCollections"],
        "PhotoAssetPayload": ["id", "mediaType", "mediaSubtypes", "pixelWidth", "pixelHeight", "favorite", "hidden", "livePhoto", "contentAvailability"],
        "PhotoExportPayload": ["id", "variant", "resourceKind", "bytes", "networkAllowed"],
        "PostalAddress": [],
        "ReminderInput": ["title"],
        "ReminderListDescriptor": ["title", "identifier", "sourceIdentifier", "type", "allowsContentModifications"],
        "ReminderPatch": [],
        "ReminderPayload": ["id", "listID", "listTitle", "title", "priority", "completed", "hasAlarms", "hasRecurrenceRules", "alarms", "recurrenceRules"],
        "SafariBookmarkPayload": ["id", "kind", "title", "childCount"],
        "SafariLocalMutationInput": [],
        "SafariReadingListAddInput": ["url"],
        "SafariReadingListItemPayload": ["id", "url", "title", "isRead"],
        "ShortcutFolderPayload": ["id", "name"],
        "ShortcutPayload": ["id", "name", "subtitle", "acceptsInput", "actionCount", "color", "iconAvailable"],
    ]

    static func apply(to schemas: [String: JSONSchema]) -> [String: JSONSchema] {
        precondition(Set(fields.keys) == Set(schemas.keys), "Every schema must have an audited required-property entry")
        return Dictionary(uniqueKeysWithValues: schemas.map { name, schema in
            (name, schema.requiring(fields[name] ?? []))
        })
    }
}
