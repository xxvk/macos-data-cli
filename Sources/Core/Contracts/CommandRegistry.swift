import Foundation

/// Builds the machine-readable command registry consumed by the `manifest`
/// command, the DSH tool importer, and human documentation.
///
/// The registry is the single source of truth for the CLI surface and must stay
/// in sync with `Sources/mpia/CLI.swift`. The per-adapter command definitions
/// live in `CommandRegistryAdapters.swift`; this file holds the shared builders,
/// safety/exit presets, and JSON Schemas.
public enum CommandRegistry {

    public static func standard(version: String) -> CommandManifest {
        CommandManifest(
            cli: CLIDescriptor(name: "mpia", version: version),
            commands: [resources, contacts, mail, calendar, reminders, photos, notes, shortcuts, safari],
            schemas: schemas
        )
    }

    // MARK: JSON Schemas

    static let schemas: [String: JSONSchema] = [
        // Generic result wrappers (abstracted across adapters)
        "Page": .object(description: "Paginated list result wrapper.", properties: [
            "items": .array(of: JSONSchema()),
            "limit": .integer("Page size.", example: .integer(50)),
            "nextCursor": .string("Opaque cursor.", example: .string("cursor_8f2c4e")),
            "truncated": .boolean("Whether results were truncated.", example: .bool(false)),
            "complete": .boolean("Whether the page is complete.", example: .bool(true)),
            "limitations": .array(of: .string("Limitation description.")),
        ]),
        "ListResult": .object(description: "Simple list result wrapper.", properties: [
            "items": .array(of: JSONSchema()),
            "limitations": .array(of: .string("Limitation description.")),
        ]),
        // Resources
        "DataResourceCapabilities": .object(description: "Permission and selection capabilities for a data resource.", properties: [
            "readable": .boolean("Whether the resource can be read.", example: .bool(true)),
            "writable": .boolean("Whether the resource can be written.", example: .bool(false)),
            "selected": .boolean("Whether the resource is the selected source.", example: .bool(true)),
            "permission": .stringEnum(["available", "denied", "notDetermined", "requiresConsent", "limited", "unavailable", "unknown"], description: "Authorization state."),
        ]),
        "DataResource": .object(description: "One discoverable macOS data resource.", properties: [
            "id": .string("Opaque local resource ID.", example: .string("acct_7f3a9c")),
            "kind": .stringEnum(["contactsContainer", "mailAccount", "calendarSource", "remindersSource", "photosLibrary", "notesLibrary", "shortcutsLibrary", "safariLibrary"], description: "Resource kind."),
            "provider": .stringEnum(["contacts", "iCloud", "mail", "eventKit", "photos", "notes", "shortcuts", "safari"], description: "Resource provider."),
            "displayName": .string("Human-readable name.", example: .string("iCloud Contacts")),
            "capabilities": .ref("DataResourceCapabilities"),
        ]),
        "DataResourcesResult": .object(description: "Unified resource discovery result.", properties: [
            "resources": .array(of: .ref("DataResource")),
            "limitations": .array(of: .string("Limitation description.")),
        ]),

        // Contacts
        "LabeledValue": .object(description: "A labeled string value.", properties: [
            "label": .string("Optional label.", example: .string("work")),
            "value": .string("Value.", example: .string("ada.lovelace@northwind.dev")),
        ]),
        "PostalAddress": .object(description: "A postal address.", properties: [
            "label": .string("Optional label.", example: .string("home")),
            "street": .string("Street line.", example: .string("350 Fifth Avenue")),
            "city": .string("City.", example: .string("New York")),
            "state": .string("State or region.", example: .string("NY")),
            "postalCode": .string("Postal code.", example: .string("10118")),
            "country": .string("Country.", example: .string("US")),
        ]),
        "ContactPayload": .object(
            title: "ContactPayload",
            description: "Adapter-neutral contact payload exchanged with agents and scripts.",
            properties: [
                "kind": .stringEnum(["person", "organization"], description: "Contact kind."),
                "externalID": .string("Stable external ID; required for every CLI-created contact.", example: .string("mpia-test-001")),
                "givenName": .string("Given name.", example: .string("Ada")),
                "familyName": .string("Family name.", example: .string("Lovelace")),
                "phoneticGivenName": .string("Phonetic given name.", example: .string("エイダ")),
                "phoneticFamilyName": .string("Phonetic family name.", example: .string("ラブレス")),
                "organizationName": .string("Organization name.", example: .string("Northwind")),
                "department": .string("Department.", example: .string("Engineering")),
                "jobTitle": .string("Job title.", example: .string("Engineer")),
                "emails": .array(of: .ref("LabeledValue")),
                "phones": .array(of: .ref("LabeledValue")),
                "urls": .array(of: .ref("LabeledValue")),
                "addresses": .array(of: .ref("PostalAddress")),
                "metadata": .object(description: "Arbitrary string metadata; preserved in JSON but not persisted by the Contacts adapter.", properties: [:]),
                "imageAvailable": .boolean("Read-only avatar availability.", example: .bool(false)),
            ],
            required: ["kind"]
        ),
        "ContactPatch": .object(description: "Partial contact edit patch; omitted fields are preserved.", properties: [
            "kind": .stringEnum(["person", "organization"], description: "Contact kind."),
            "givenName": .string(), "familyName": .string(),
            "phoneticGivenName": .string(), "phoneticFamilyName": .string(),
            "organizationName": .string(), "department": .string(), "jobTitle": .string(),
            "emails": .array(of: .ref("LabeledValue")),
            "phones": .array(of: .ref("LabeledValue")),
            "urls": .array(of: .ref("LabeledValue")),
            "addresses": .array(of: .ref("PostalAddress")),
        ]),
        "ContactContainer": .object(description: "A Contacts container.", properties: [
            "name": .string(example: .string("iCloud")), "identifier": .string(example: .string("container_7f2a")), "type": .string(example: .string("carddav")), "isICloud": .boolean(example: .bool(true)),
        ]),
        "AvatarWriteVerification": .object(description: "Avatar write verification result.", properties: [
            "status": .stringEnum(["readback_confirmed", "not_available", "save_accepted", "verification_unknown"], description: "Verification status."),
            "saveAccepted": .boolean(example: .bool(true)), "requestedBytes": .integer(example: .integer(24576)), "readBackBytes": .integer(example: .integer(24576)), "nextAction": .string(example: .string("none")),
        ]),
        "ContactWriteResult": .object(description: "Final saved state after a Contacts write.", properties: [
            "operation": .string("Write operation name.", example: .string("create")),
            "contact": .ref("ContactPayload"),
        ]),

        // Mail
        "MailAccountSummary": .object(description: "A Mail account summary.", properties: [
            "id": .string(example: .string("acct_7f3a9c")), "kind": .string(example: .string("imap")), "mailboxCount": .integer(example: .integer(12)), "totalCount": .integer(example: .integer(1530)), "unreadCount": .integer(example: .integer(7)),
        ]),
        "MailboxSummary": .object(description: "A mailbox summary.", properties: [
            "id": .string(example: .string("mbox_1a2b3c")), "accountID": .string(example: .string("acct_7f3a9c")), "name": .string(example: .string("Inbox")), "totalCount": .integer(example: .integer(1200)), "unreadCount": .integer(example: .integer(30)),
        ]),
        "MailMessageMetadata": .object(description: "Bounded message metadata (no body).", properties: [
            "id": .string(example: .string("msg_9f8e7d")), "accountID": .string(example: .string("acct_7f3a9c")), "mailboxID": .string(example: .string("mbox_1a2b3c")),
            "subject": .string(example: .string("Meeting notes")), "sender": .string(example: .string("ada.lovelace@northwind.dev")), "sentAt": .string(), "receivedAt": .string(),
            "unread": .boolean(example: .bool(true)), "flagged": .boolean(example: .bool(false)), "hasAttachment": .boolean(example: .bool(true)),
            "sizeBytes": .integer(example: .integer(48213)),
            "cacheState": .stringEnum(["metadata_only", "partial", "complete", "unknown"], description: "Local cache state."),
        ]),
        "MailQueryResult": .object(description: "Paged Mail metadata query result.", properties: [
            "backend": .string(example: .string("sqlite")), "items": .array(of: .ref("MailMessageMetadata")),
            "truncated": .boolean(example: .bool(false)), "nextCursor": .string(example: .string("cursor_8f2c4e")), "incomplete": .boolean(example: .bool(false)), "limitations": .array(of: .string()),
        ]),

        // Calendar
        "CalendarSourceDescriptor": .object(description: "A calendar source.", properties: [
            "title": .string(example: .string("iCloud")), "identifier": .string(example: .string("src_icloud")), "type": .string(example: .string("caldav")), "isICloud": .boolean(example: .bool(true)),
        ]),
        "CalendarDescriptor": .object(description: "A calendar.", properties: [
            "title": .string(example: .string("Work")), "identifier": .string(example: .string("cal_work")), "sourceIdentifier": .string(example: .string("src_icloud")), "type": .string(example: .string("caldav")), "allowsContentModifications": .boolean(example: .bool(true)),
        ]),
        "CalendarEventPayload": .object(description: "A calendar event.", properties: [
            "id": .string(example: .string("calevent_6d3f8a")), "calendarID": .string(example: .string("cal_work")), "calendarTitle": .string(example: .string("Work")), "title": .string(example: .string("Team sync")),
            "startDate": .string(example: .string("2026-08-20T09:00:00+08:00")), "endDate": .string(example: .string("2026-08-20T10:00:00+08:00")), "allDay": .boolean(example: .bool(false)), "timeZone": .string(example: .string("Asia/Shanghai")),
            "location": .string(example: .string("Room 3F")), "notes": .string(), "url": .string(),
            "attendees": .array(of: .string()), "alarms": .array(of: .string()),
            "recurrenceRules": .array(of: .string()), "status": .string(example: .string("confirmed")),
        ]),

        // Reminders
        "ReminderListDescriptor": .object(description: "A reminder list.", properties: [
            "title": .string(example: .string("Personal")), "identifier": .string(example: .string("list_personal")), "sourceIdentifier": .string(example: .string("src_icloud")), "type": .string(example: .string("caldav")), "allowsContentModifications": .boolean(example: .bool(true)),
        ]),
        "ReminderPayload": .object(description: "A reminder.", properties: [
            "id": .string(example: .string("reminder_5b7e2c")), "listID": .string(example: .string("list_personal")), "listTitle": .string(example: .string("Personal")), "title": .string(example: .string("Buy milk")), "notes": .string(example: .string("2% milk")), "url": .string(),
            "priority": .string(example: .string("high")), "completed": .boolean(example: .bool(false)), "completionDate": .string(),
            "start": .string(example: .string("2026-08-16T09:00:00Z")), "due": .string(example: .string("2026-08-16T18:00:00Z")), "hasAlarms": .boolean(example: .bool(false)), "hasRecurrenceRules": .boolean(example: .bool(false)),
            "alarms": .array(of: .string()), "recurrenceRules": .array(of: .string()),
        ]),

        // Photos
        "PhotoAlbumPayload": .object(description: "A photo album.", properties: [
            "id": .string(example: .string("album_9a1d4f")), "title": .string(example: .string("Vacation")), "kind": .string(example: .string("user")), "parentID": .string(example: .string("root")), "depth": .integer(example: .integer(0)),
            "canContainAssets": .boolean(example: .bool(true)), "canContainCollections": .boolean(example: .bool(false)), "estimatedAssetCount": .integer(example: .integer(120)),
        ]),
        "PhotoAssetPayload": .object(description: "Photo asset metadata (no media bytes).", properties: [
            "id": .string(example: .string("asset_3c8b6e")), "mediaType": .string(example: .string("image")), "mediaSubtypes": .array(of: .string()),
            "pixelWidth": .integer(example: .integer(4032)), "pixelHeight": .integer(example: .integer(3024)), "duration": .number(),
            "creationDate": .string(example: .string("2026-07-01T12:00:00Z")), "modificationDate": .string(example: .string("2026-07-01T12:00:00Z")),
            "favorite": .boolean(example: .bool(true)), "hidden": .boolean(example: .bool(false)), "burstIdentifier": .string(),
            "livePhoto": .boolean(example: .bool(false)), "contentAvailability": .string(example: .string("available")), "location": .string(example: .string("37.33182,-122.03118")),
        ]),

        // Notes
        "NotesAccountPayload": .object(description: "A Notes account.", properties: [
            "id": .string(example: .string("acct_notes")), "name": .string(example: .string("iCloud")), "isDefault": .boolean(example: .bool(true)), "folderCount": .integer(example: .integer(5)),
        ]),
        "NotesFolderPayload": .object(description: "A Notes folder.", properties: [
            "id": .string(example: .string("folder_2e9d7a")), "accountID": .string(example: .string("acct_notes")), "parentID": .string(example: .string("root")), "name": .string(example: .string("Projects")), "shared": .boolean(example: .bool(false)), "depth": .integer(example: .integer(0)),
        ]),
        "NotesNotePayload": .object(description: "A note.", properties: [
            "id": .string(example: .string("note_7f4a1b")), "accountID": .string(example: .string("acct_notes")), "folderID": .string(example: .string("folder_2e9d7a")), "title": .string(example: .string("Meeting notes")),
            "creationDate": .string(example: .string("2026-08-15T09:00:00Z")), "modificationDate": .string(example: .string("2026-08-15T09:00:00Z")), "passwordProtected": .boolean(example: .bool(false)), "shared": .boolean(example: .bool(false)),
        ]),

        // Shortcuts
        "ShortcutPayload": .object(description: "A shortcut.", properties: [
            "id": .string(example: .string("shortcut_4c6e8d")), "name": .string(example: .string("Send morning report")), "subtitle": .string(example: .string("Sends the daily report")), "folderID": .string(example: .string("folder_shortcuts")),
            "acceptsInput": .boolean(example: .bool(false)), "actionCount": .integer(example: .integer(8)), "color": .string(example: .string("blue")), "iconAvailable": .boolean(example: .bool(true)),
        ]),
        "ShortcutFolderPayload": .object(description: "A shortcut folder.", properties: [
            "id": .string(example: .string("folder_shortcuts")), "name": .string(example: .string("Work")),
        ]),

        // Safari
        "SafariBookmarkPayload": .object(description: "A Safari bookmark or folder.", properties: [
            "id": .string(example: .string("bm_1a5f9c")), "parentID": .string(example: .string("root")), "kind": .string(example: .string("bookmark")), "title": .string(example: .string("Apple Developer")), "url": .string(example: .string("https://developer.apple.com")),
            "childCount": .integer(example: .integer(0)), "dateAdded": .string(example: .string("2026-08-01T00:00:00Z")),
        ]),
        "SafariReadingListItemPayload": .object(description: "A Safari Reading List item.", properties: [
            "id": .string(example: .string("rl_6b2d8e")), "url": .string(example: .string("https://en.wikipedia.org/wiki/Analytical_Engine")), "title": .string(example: .string("Analytical Engine - Wikipedia")), "previewText": .string(example: .string("The Analytical Engine was a proposed mechanical general-purpose computer.")),
            "dateAdded": .string(example: .string("2026-08-01T00:00:00Z")), "lastViewedDate": .string(example: .string("2026-08-02T00:00:00Z")), "isRead": .boolean(example: .bool(false)),
        ]),
        "CalendarEventInput": .object(description: "Calendar event create input.", properties: [
            "calendarID": .string(example: .string("cal_work")), "title": .string(example: .string("Team sync")), "startDate": .string(example: .string("2026-08-20T09:00:00+08:00")), "endDate": .string(example: .string("2026-08-20T10:00:00+08:00")),
            "allDay": .boolean(example: .bool(false)), "timeZone": .string(example: .string("Asia/Shanghai")), "location": .string(example: .string("Room 3F")), "notes": .string(example: .string("Bring laptop")), "url": .string(),
            "attendees": .array(of: .string()), "alarms": .array(of: .string()), "recurrenceRules": .array(of: .string()),
        ]),
        "CalendarEventPatch": .object(description: "Calendar event edit patch; omitted fields are preserved.", properties: [
            "calendarID": .string(), "title": .string(), "startDate": .string(), "endDate": .string(),
            "allDay": .boolean(), "timeZone": .string(), "location": .string(), "notes": .string(), "url": .string(),
            "recurrenceRules": .array(of: .string()), "alarms": .array(of: .string()),
        ]),
        "ReminderInput": .object(description: "Reminder create input.", properties: [
            "listID": .string(example: .string("list_personal")), "title": .string(example: .string("Buy milk")), "notes": .string(example: .string("2% milk")), "url": .string(), "priority": .string(example: .string("high")),
            "start": .string(example: .string("2026-08-16T09:00:00Z")), "due": .string(example: .string("2026-08-16T18:00:00Z")), "alarms": .array(of: .string()), "recurrenceRules": .array(of: .string()),
        ]),
        "ReminderPatch": .object(description: "Reminder edit patch; omitted fields are preserved.", properties: [
            "listID": .string(), "title": .string(), "notes": .string(), "url": .string(), "priority": .string(),
            "start": .string(), "due": .string(), "alarms": .array(of: .string()), "recurrenceRules": .array(of: .string()),
        ]),
        "NotesCreateInput": .object(description: "Note create input.", properties: [
            "folderID": .string(example: .string("folder_2e9d7a")), "title": .string(example: .string("Meeting notes")), "bodyFormat": .string(example: .string("plain")), "body": .string(example: .string("Discuss Q3 goals")),
        ]),
        "NotesRenameInput": .object(description: "Note rename input.", properties: [
            "title": .string(example: .string("Meeting notes (updated)")), "expectedModificationDate": .string(example: .string("2026-08-15T09:00:00Z")),
        ]),
        "NotesEditBodyInput": .object(description: "Note body replacement input.", properties: [
            "bodyFormat": .string(example: .string("plain")), "body": .string(example: .string("Updated notes")), "expectedModificationDate": .string(example: .string("2026-08-15T09:00:00Z")), "expectedBodySHA256": .string(example: .string("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")),
        ]),
        "NotesFolderCreateInput": .object(description: "Note folder create input.", properties: [
            "name": .string(example: .string("Projects")), "parentFolderID": .string(example: .string("root")),
        ]),
        "NotesFolderRenameInput": .object(description: "Note folder rename input.", properties: [
            "name": .string(example: .string("Projects (renamed)")), "expectedNameSHA256": .string(example: .string("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")),
        ]),
        "PhotoExportPayload": .object(description: "Photo export result.", properties: [
            "id": .string(example: .string("asset_3c8b6e")), "variant": .string(example: .string("original")), "resourceKind": .string(example: .string("photo")), "contentType": .string(example: .string("image/jpeg")),
            "bytes": .integer(example: .integer(2457600)), "networkAllowed": .boolean(example: .bool(false)),
        ]),
        "SafariReadingListAddInput": .object(description: "Reading List add input.", properties: [
            "url": .string(example: .string("https://en.wikipedia.org/wiki/Analytical_Engine")), "title": .string(example: .string("Analytical Engine - Wikipedia")), "previewText": .string(example: .string("The Analytical Engine was a proposed mechanical general-purpose computer.")),
        ]),
    ]

    // MARK: Safety presets

    static let readOnly = CommandSafety.readOnly
    static let dryRunApply = CommandSafety(dryRun: true, apply: true)
    static let deleteContact = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE CONTACT")
    static let avatarReplace = CommandSafety(dryRun: true, apply: true, confirmation: "RECREATE CONTACT")
    static let migrateContact = CommandSafety(dryRun: true, apply: true, confirmation: "CHANGE EXTERNAL ID")
    static let deleteEvent = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE EVENT")
    static let deleteReminder = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE REMINDER")
    static let deleteNote = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE NOTE")
    static let editCopy = CommandSafety(dryRun: true, apply: true, confirmation: "EDIT SHORTCUT COPY")

    // MARK: Exit-code presets

    static let contactsExit = [ExitCodeSpec(code: 2, errorCode: "CONTACTS_ERROR", description: "Contacts/permission/input error")]
    static let queryExit = [ExitCodeSpec(code: 3, errorCode: "CONTACT_QUERY_ERROR", description: "Contact lookup error")]
    static let mailExit = [ExitCodeSpec(code: 4, errorCode: "MAIL_ERROR", description: "Mail adapter error")]
    static let calendarExit = [ExitCodeSpec(code: 5, errorCode: "CALENDAR_ERROR", description: "Calendar adapter error")]
    static let remindersExit = [ExitCodeSpec(code: 6, errorCode: "REMINDERS_ERROR", description: "Reminders adapter error")]
    static let photosExit = [ExitCodeSpec(code: 7, errorCode: "PHOTOS_ERROR", description: "Photos adapter error")]
    static let notesExit = [ExitCodeSpec(code: 8, errorCode: "NOTES_ERROR", description: "Notes adapter error")]
    static let shortcutsExit = [ExitCodeSpec(code: 9, errorCode: "SHORTCUTS_ERROR", description: "Shortcuts adapter error")]
    static let safariExit = [ExitCodeSpec(code: 10, errorCode: "SAFARI_ERROR", description: "Safari adapter error")]

    // MARK: Builders

    static func leaf(
        name: String,
        description: String,
        usage: String,
        mutates: Bool = false,
        params: [CommandParam] = [],
        exitCodes: [ExitCodeSpec] = [],
        safety: CommandSafety = .readOnly,
        inputSchema: String? = nil,
        outputSchema: String? = nil
    ) -> CommandNode {
        CommandNode(
            name: name, kind: .leaf, description: description, usage: usage,
            mutates: mutates, params: params, exitCodes: exitCodes, safety: safety,
            inputSchema: inputSchema, outputSchema: outputSchema
        )
    }

    static func group(name: String, description: String, subcommands: [CommandNode]) -> CommandNode {
        CommandNode(
            name: name, kind: .group, description: description, usage: "mpia \(name) <command>",
            mutates: false, params: [], exitCodes: [], safety: .readOnly, subcommands: subcommands
        )
    }

    static func string(_ name: String, _ description: String, type: ParamType = .string, required: Bool = false, default: String? = nil) -> CommandParam {
        CommandParam(name: name, type: type, required: required, description: description, defaultValue: `default`)
    }

    static func int(_ name: String, _ description: String, default: String? = nil) -> CommandParam {
        CommandParam(name: name, type: .int, required: false, description: description, defaultValue: `default`)
    }

    static func bool(_ name: String, _ description: String) -> CommandParam {
        CommandParam(name: name, type: .bool, required: false, description: description)
    }
}
