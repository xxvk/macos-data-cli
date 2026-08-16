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
        let commands = [agent, resources, contacts, mail, calendar, reminders, photos, notes, shortcuts, safari, messages, phoneCalls]
        return CommandManifest(
            cli: CLIDescriptor(name: "mpia", version: version),
            commands: commands,
            routes: restRoutes(from: commands),
            schemas: schemas
        )
    }

    // MARK: JSON Schemas

    static let schemas: [String: JSONSchema] = SchemaRequirements.apply(to:
        sharedSchemas
            .merging(notesSchemas) { current, _ in current }
            .merging(communicationSchemas) { current, _ in current }
    )

    private static let sharedSchemas: [String: JSONSchema] = [
        // Generic result wrappers (abstracted across adapters)
        "Page": .object(description: "Paginated list result wrapper.", properties: [
            "items": .array(of: JSONSchema(), maxItems: Pagination.maximumLimit),
            "limit": .integer("Page size.", minimum: 1, maximum: Double(Pagination.maximumLimit), example: .integer(50)),
            "nextCursor": .string("Opaque cursor for the next page; omitted when the page is complete.", minLength: 1, maxLength: 4096, example: .string("cursor_8f2c4e")),
            "truncated": .boolean("Whether more results remain beyond this page.", example: .bool(false)),
            "complete": .boolean("Whether this page contains all remaining results.", example: .bool(true)),
            "limitations": .array(of: .string("Human-readable limitation that applies to this result.")),
        ], required: ["items", "limit", "truncated", "complete"]),
        "ListResult": .object(description: "Simple list result wrapper.", properties: [
            "items": .array(of: JSONSchema()),
            "limitations": .array(of: .string("Human-readable limitation that applies to this result.")),
        ], required: ["items"]),
        // Resources
        "DataResourceCapabilities": .object(description: "Permission and selection capabilities for a data resource.", properties: [
            "readable": .boolean("Whether the resource can be read by the current process.", example: .bool(true)),
            "writable": .boolean("Whether the resource can be written by the current process.", example: .bool(false)),
            "selected": .boolean("Whether the resource is the selected source for its adapter.", example: .bool(true)),
            "permission": .stringEnum(["available", "denied", "notDetermined", "requiresConsent", "limited", "unavailable", "unknown"], description: "Authorization state of the resource."),
        ]),
        "DataResource": .object(description: "One discoverable macOS data resource.", properties: [
            "id": .string("Opaque local resource ID.", example: .string("acct_7f3a9c")),
            "kind": .stringEnum(["contactsContainer", "mailAccount", "calendarSource", "remindersSource", "photosLibrary", "notesLibrary", "shortcutsLibrary", "safariLibrary", "messagesLibrary", "phoneLibrary"], description: "Resource kind."),
            "provider": .stringEnum(["contacts", "iCloud", "mail", "eventKit", "photos", "notes", "shortcuts", "safari", "messages", "phone"], description: "Resource provider."),
            "displayName": .string("Human-readable name.", example: .string("iCloud Contacts")),
            "capabilities": .ref("DataResourceCapabilities"),
        ]),
        "DataResourcesResult": .object(description: "Unified resource discovery result.", properties: [
            "resources": .array(of: .ref("DataResource")),
            "limitations": .array(of: .string("Human-readable limitation that applies to this discovery.")),
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
            "givenName": .string("Given name."), "familyName": .string("Family name."),
            "phoneticGivenName": .string("Phonetic given name."), "phoneticFamilyName": .string("Phonetic family name."),
            "organizationName": .string("Organization name."), "department": .string("Department."), "jobTitle": .string("Job title."),
            "emails": .array(of: .ref("LabeledValue")),
            "phones": .array(of: .ref("LabeledValue")),
            "urls": .array(of: .ref("LabeledValue")),
            "addresses": .array(of: .ref("PostalAddress")),
        ]),
        "ContactContainer": .object(description: "A Contacts container.", properties: [
            "name": .string("Container display name.", example: .string("iCloud")), "identifier": .string("Opaque container identifier.", example: .string("container_7f2a")), "type": .string("Container backend type.", example: .string("carddav")), "isICloud": .boolean("Whether this is the iCloud container.", example: .bool(true)),
        ]),
        "AvatarWriteVerification": .object(description: "Avatar write verification result.", properties: [
            "status": .stringEnum(["readback_confirmed", "not_available", "save_accepted", "verification_unknown"], description: "Verification status."),
            "saveAccepted": .boolean("Whether the save was accepted by the store.", example: .bool(true)), "requestedBytes": .integer("Bytes submitted for the avatar.", example: .integer(24576)), "readBackBytes": .integer("Bytes read back from the saved avatar.", example: .integer(24576)), "nextAction": .string("Suggested follow-up for the caller.", example: .string("none")),
        ]),
        "ContactWriteResult": .object(description: "Final saved state after a Contacts write.", properties: [
            "operation": .string("Write operation name.", example: .string("create")),
            "contact": .ref("ContactPayload"),
        ]),

        // Mail
        "MailAccountSummary": .object(description: "A Mail account summary.", properties: [
            "id": .string("Opaque account ID.", example: .string("acct_7f3a9c")), "kind": .string("Account backend kind.", example: .string("imap")), "mailboxCount": .integer("Number of mailboxes in the account.", example: .integer(12)), "totalCount": .integer("Total message count.", example: .integer(1530)), "unreadCount": .integer("Unread message count.", example: .integer(7)),
        ]),
        "MailboxSummary": .object(description: "A mailbox summary.", properties: [
            "id": .string("Opaque mailbox ID.", example: .string("mbox_1a2b3c")), "accountID": .string("Opaque account ID.", example: .string("acct_7f3a9c")), "name": .string("Mailbox display name.", example: .string("Inbox")), "totalCount": .integer("Total message count.", example: .integer(1200)), "unreadCount": .integer("Unread message count.", example: .integer(30)),
        ]),
        "MailMessageMetadata": .object(description: "Bounded message metadata (no body).", properties: [
            "id": .string("Opaque message ID.", example: .string("msg_9f8e7d")), "accountID": .string("Opaque account ID.", example: .string("acct_7f3a9c")), "mailboxID": .string("Opaque mailbox ID.", example: .string("mbox_1a2b3c")),
            "subject": .string("Message subject.", example: .string("Meeting notes")), "sender": .string("Sender display address.", example: .string("ada.lovelace@northwind.dev")), "sentAt": .string("ISO 8601 send timestamp.", format: "date-time", example: .string("2026-08-14T09:12:00Z")), "receivedAt": .string("ISO 8601 receive timestamp.", format: "date-time", example: .string("2026-08-14T09:12:03Z")),
            "unread": .boolean("Whether the message is unread.", example: .bool(true)), "flagged": .boolean("Whether the message is flagged.", example: .bool(false)), "hasAttachment": .boolean("Whether the message has attachments.", example: .bool(true)),
            "sizeBytes": .integer("Cached message size in bytes.", example: .integer(48213)),
            "cacheState": .stringEnum(["metadata_only", "partial", "complete", "unknown"], description: "Local cache state."),
        ]),
        "MailQueryResult": .object(description: "Paged Mail metadata query result.", properties: [
            "backend": .string("Backend that produced the result (sqlite or app).", example: .string("sqlite")), "items": .array(of: .ref("MailMessageMetadata")),
            "truncated": .boolean("Whether more results remain.", example: .bool(false)), "nextCursor": .string("Opaque cursor for the next page.", example: .string("cursor_8f2c4e")), "incomplete": .boolean("Whether the result is incomplete (fallback backend).", example: .bool(false)), "limitations": .array(of: .string("Human-readable limitation that applies to this result.")),
        ]),

        // Calendar
        "CalendarSourceDescriptor": .object(description: "A calendar source.", properties: [
            "title": .string("Source display title.", example: .string("iCloud")), "identifier": .string("Opaque source identifier.", example: .string("src_icloud")), "type": .string("Source backend type.", example: .string("caldav")), "isICloud": .boolean("Whether this is the iCloud source.", example: .bool(true)),
        ]),
        "CalendarDescriptor": .object(description: "A calendar.", properties: [
            "title": .string("Calendar display title.", example: .string("Work")), "identifier": .string("Opaque calendar identifier.", example: .string("cal_work")), "sourceIdentifier": .string("Opaque source identifier.", example: .string("src_icloud")), "type": .string("Calendar backend type.", example: .string("caldav")), "allowsContentModifications": .boolean("Whether events can be modified.", example: .bool(true)),
        ]),
        "CalendarEventPayload": .object(description: "A calendar event.", properties: [
            "id": .string("Opaque event ID.", example: .string("calevent_6d3f8a")), "calendarID": .string("Opaque calendar ID.", example: .string("cal_work")), "calendarTitle": .string("Calendar display title.", example: .string("Work")), "title": .string("Event title.", example: .string("Team sync")),
            "startDate": .string("ISO 8601 start timestamp (date-only for all-day events).", example: .string("2026-08-20T09:00:00+08:00")), "endDate": .string("ISO 8601 end timestamp (exclusive date for all-day events).", example: .string("2026-08-20T10:00:00+08:00")), "allDay": .boolean("Whether the event is all-day.", example: .bool(false)), "timeZone": .string("IANA time-zone identifier.", example: .string("Asia/Shanghai")),
            "location": .string("Event location.", example: .string("Room 3F")), "notes": .string("Event notes.", example: .string("Bring laptop")), "url": .string("Event URL.", format: "uri", example: .string("https://example.com/meet")),
            "attendees": .array(of: .string("Attendee display value.")), "alarms": .array(of: .string("Alarm description.")),
            "recurrenceRules": .array(of: .string("Recurrence rule description.")), "status": .string("Event status.", example: .string("confirmed")),
        ]),

        // Reminders
        "ReminderListDescriptor": .object(description: "A reminder list.", properties: [
            "title": .string("List display title.", example: .string("Personal")), "identifier": .string("Opaque list identifier.", example: .string("list_personal")), "sourceIdentifier": .string("Opaque source identifier.", example: .string("src_icloud")), "type": .string("List backend type.", example: .string("caldav")), "allowsContentModifications": .boolean("Whether reminders can be modified.", example: .bool(true)),
        ]),
        "ReminderPayload": .object(description: "A reminder.", properties: [
            "id": .string("Opaque reminder ID.", minLength: 1, example: .string("reminder_5b7e2c")), "listID": .string("Opaque list ID.", minLength: 1, example: .string("list_personal")), "listTitle": .string("List display title.", minLength: 1, example: .string("Personal")), "title": .string("Reminder title.", minLength: 1, maxLength: 1_000, example: .string("Buy milk")), "notes": .string("Reminder notes.", maxLength: 100_000, example: .string("2% milk")), "url": .string("Reminder URL.", format: "uri", maxLength: 2_048, example: .string("https://example.com")),
            "priority": .string("Reminder priority.", example: .string("high")), "completed": .boolean("Whether the reminder is completed.", example: .bool(false)), "completionDate": .string("ISO 8601 completion timestamp, or null when open.", example: .string("2026-08-16T10:00:00Z")),
            "start": .string("ISO 8601 start timestamp.", example: .string("2026-08-16T09:00:00Z")), "due": .string("ISO 8601 due timestamp.", example: .string("2026-08-16T18:00:00Z")), "hasAlarms": .boolean("Whether the reminder has alarms.", example: .bool(false)), "hasRecurrenceRules": .boolean("Whether the reminder repeats.", example: .bool(false)),
            "alarms": .array(of: .string("Alarm description.")), "recurrenceRules": .array(of: .string("Recurrence rule description.")),
        ]),

        // Photos
        "PhotoAlbumPayload": .object(description: "A photo album.", properties: [
            "id": .string("Opaque album ID.", example: .string("album_9a1d4f")), "title": .string("Album title.", example: .string("Vacation")), "kind": .string("Album kind.", example: .string("user")), "parentID": .string("Opaque parent collection ID.", example: .string("root")), "depth": .integer("Nesting depth.", example: .integer(0)),
            "canContainAssets": .boolean("Whether the album can contain assets.", example: .bool(true)), "canContainCollections": .boolean("Whether the album can contain child collections.", example: .bool(false)), "estimatedAssetCount": .integer("Estimated asset count.", example: .integer(120)),
        ]),
        "PhotoAssetPayload": .object(description: "Photo asset metadata (no media bytes).", properties: [
            "id": .string("Opaque asset ID.", example: .string("asset_3c8b6e")), "mediaType": .string("Asset media type (image or video).", example: .string("image")), "mediaSubtypes": .array(of: .string("Asset media subtype.")),
            "pixelWidth": .integer("Pixel width.", example: .integer(4032)), "pixelHeight": .integer("Pixel height.", example: .integer(3024)), "duration": .number("Video duration in seconds.", example: .number(12.5)),
            "creationDate": .string("ISO 8601 creation timestamp.", example: .string("2026-07-01T12:00:00Z")), "modificationDate": .string("ISO 8601 modification timestamp.", example: .string("2026-07-01T12:00:00Z")),
            "favorite": .boolean("Whether the asset is a favorite.", example: .bool(true)), "hidden": .boolean("Whether the asset is hidden.", example: .bool(false)), "burstIdentifier": .string("Opaque burst identifier, or null.", example: .string("burst_1a2b3c")),
            "livePhoto": .boolean("Whether the asset has a Live Photo pair.", example: .bool(false)), "contentAvailability": .string("Whether media bytes are locally available.", example: .string("available")), "location": .string("Asset location, or null.", example: .string("37.33182,-122.03118")),
        ]),

        // Shortcuts
        "ShortcutPayload": .object(description: "A shortcut.", properties: [
            "id": .string("Opaque shortcut ID.", example: .string("shortcut_4c6e8d")), "name": .string("Shortcut display name.", example: .string("Send morning report")), "subtitle": .string("Shortcut subtitle.", example: .string("Sends the daily report")), "folderID": .string("Opaque folder ID.", example: .string("folder_shortcuts")),
            "acceptsInput": .boolean("Whether the shortcut accepts input.", example: .bool(false)), "actionCount": .integer("Compiled action count.", example: .integer(8)), "color": .string("Shortcut color.", example: .string("blue")), "iconAvailable": .boolean("Whether an icon is available.", example: .bool(true)),
        ]),
        "ShortcutFolderPayload": .object(description: "A shortcut folder.", properties: [
            "id": .string("Opaque folder ID.", example: .string("folder_shortcuts")), "name": .string("Folder display name.", example: .string("Work")),
        ]),

        // Safari
        "SafariBookmarkPayload": .object(description: "A Safari bookmark or folder.", properties: [
            "id": .string("Opaque bookmark or folder ID.", example: .string("bm_1a5f9c")), "parentID": .string("Opaque parent ID.", example: .string("root")), "kind": .string("Node kind (bookmark or folder).", example: .string("bookmark")), "title": .string("Bookmark or folder title.", example: .string("Apple Developer")), "url": .string("Bookmark URL, or null for folders.", example: .string("https://developer.apple.com")),
            "childCount": .integer("Number of children (folders).", example: .integer(0)), "dateAdded": .string("ISO 8601 add timestamp.", example: .string("2026-08-01T00:00:00Z")),
        ]),
        "SafariReadingListItemPayload": .object(description: "A Safari Reading List item.", properties: [
            "id": .string("Opaque item ID.", example: .string("rl_6b2d8e")), "url": .string("Item URL.", example: .string("https://en.wikipedia.org/wiki/Analytical_Engine")), "title": .string("Item title.", example: .string("Analytical Engine - Wikipedia")), "previewText": .string("Item preview text.", example: .string("The Analytical Engine was a proposed mechanical general-purpose computer.")),
            "dateAdded": .string("ISO 8601 add timestamp.", example: .string("2026-08-01T00:00:00Z")), "lastViewedDate": .string("ISO 8601 last-viewed timestamp, or null.", example: .string("2026-08-02T00:00:00Z")), "isRead": .boolean("Whether the item has been read.", example: .bool(false)),
        ]),
        "CalendarEventInput": .object(description: "Calendar event create input.", properties: [
            "calendarID": .string("Opaque calendar ID.", example: .string("cal_work")), "title": .string("Event title.", example: .string("Team sync")), "startDate": .string("ISO 8601 start timestamp.", example: .string("2026-08-20T09:00:00+08:00")), "endDate": .string("ISO 8601 end timestamp.", example: .string("2026-08-20T10:00:00+08:00")),
            "allDay": .boolean("Whether the event is all-day.", example: .bool(false)), "timeZone": .string("IANA time-zone identifier.", example: .string("Asia/Shanghai")), "location": .string("Event location.", example: .string("Room 3F")), "notes": .string("Event notes.", example: .string("Bring laptop")), "url": .string("Event URL.", example: .string("https://example.com/meet")),
            "attendees": .array(of: .string("Attendee display value.")), "alarms": .array(of: .string("Alarm description.")), "recurrenceRules": .array(of: .string("Recurrence rule description.")),
        ]),
        "CalendarEventPatch": .object(description: "Calendar event edit patch; omitted fields are preserved.", properties: [
            "calendarID": .string("Opaque calendar ID."), "title": .string("Event title."), "startDate": .string("ISO 8601 start timestamp."), "endDate": .string("ISO 8601 end timestamp."),
            "allDay": .boolean("Whether the event is all-day."), "timeZone": .string("IANA time-zone identifier."), "location": .string("Event location."), "notes": .string("Event notes."), "url": .string("Event URL."),
            "recurrenceRules": .array(of: .string("Recurrence rule description.")), "alarms": .array(of: .string("Alarm description.")),
        ]),
        "ReminderInput": .object(description: "Reminder create input.", properties: [
            "listID": .string("Opaque list ID.", minLength: 1, example: .string("list_personal")), "title": .string("Reminder title.", minLength: 1, maxLength: 1_000, example: .string("Buy milk")), "notes": .string("Reminder notes.", maxLength: 100_000, example: .string("2% milk")), "url": .string("Reminder URL.", format: "uri", maxLength: 2_048, example: .string("https://example.com")), "priority": .string("Reminder priority.", example: .string("high")),
            "start": .string("ISO 8601 start timestamp.", example: .string("2026-08-16T09:00:00Z")), "due": .string("ISO 8601 due timestamp.", example: .string("2026-08-16T18:00:00Z")), "alarms": .array(of: .string("Alarm description.")), "recurrenceRules": .array(of: .string("Recurrence rule description.")),
        ]),
        "ReminderPatch": .object(description: "Reminder edit patch; omitted fields are preserved.", properties: [
            "listID": .string("Opaque list ID."), "title": .string("Reminder title."), "notes": .string("Reminder notes."), "url": .string("Reminder URL."), "priority": .string("Reminder priority."),
            "start": .string("ISO 8601 start timestamp."), "due": .string("ISO 8601 due timestamp."), "alarms": .array(of: .string("Alarm description.")), "recurrenceRules": .array(of: .string("Recurrence rule description.")),
        ]),
        "PhotoExportPayload": .object(description: "Photo export result.", properties: [
            "id": .string("Opaque asset ID.", example: .string("asset_3c8b6e")), "variant": .string("Exported variant.", example: .string("original")), "resourceKind": .string("Exported resource kind.", example: .string("photo")), "contentType": .string("Exported MIME type.", example: .string("image/jpeg")),
            "bytes": .integer("Exported byte count.", example: .integer(2457600)), "networkAllowed": .boolean("Whether network download was allowed.", example: .bool(false)),
        ]),
        "SafariReadingListAddInput": .object(description: "Reading List add input.", properties: [
            "url": .string("Item URL.", format: "uri", minLength: 1, maxLength: 4_096, example: .string("https://en.wikipedia.org/wiki/Analytical_Engine")), "title": .string("Item title.", maxLength: 500, example: .string("Analytical Engine - Wikipedia")), "previewText": .string("Item preview text; UTF-8 encoding must not exceed 4,096 bytes.", example: .string("The Analytical Engine was a proposed mechanical general-purpose computer.")),
        ]),
        "SafariLocalMutationInput": .object(description: "Strict local-only Safari bookmark or folder mutation input; required fields depend on the selected command.", properties: [
            "id": .string("Opaque node ID for edit/move/delete.", minLength: 1, maxLength: 256), "parentID": .string("Opaque parent ID for create/move.", minLength: 1, maxLength: 256), "index": .integer("Zero-based insertion index.", minimum: 0), "title": .string("Node title.", minLength: 1, maxLength: 500), "url": .string("Bookmark URL.", format: "uri", maxLength: 4_096),
            "expectedSourceSHA256": .string("SHA-256 returned by the latest dry-run.", pattern: "^[0-9a-fA-F]{64}$", minLength: 64, maxLength: 64),
        ]),

    ]

}
