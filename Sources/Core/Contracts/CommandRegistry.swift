import Foundation

/// Builds the machine-readable command registry consumed by the `manifest`
/// command, the DSH tool importer, and human documentation.
///
/// This first slice documents the core command surface. The remaining adapter
/// commands and their schemas are added incrementally and must stay in sync
/// with the parser.
public enum CommandRegistry {

    public static func standard(version: String) -> CommandManifest {
        CommandManifest(
            cli: CLIDescriptor(name: "mpia", version: version),
            commands: [resources, contacts, mail, calendar, reminders, photos, notes, shortcuts, safari],
            schemas: schemas
        )
    }

    // MARK: Top-level commands

    private static let resources = leaf(
        name: "resources",
        description: "List every data resource with selection, permission, and limitations.",
        usage: "mpia resources --format json"
    )

    private static let contacts = group(name: "contacts", description: "Query and manage contacts.", subcommands: [
        leaf(name: "permission", description: "Check Contacts authorization.", usage: "mpia contacts permission", exitCodes: contactsExit),
        leaf(name: "count", description: "Count contacts.", usage: "mpia contacts count [--format json]", exitCodes: contactsExit),
        leaf(name: "list", description: "List contacts with pagination.", usage: "mpia contacts list --format json",
             params: [int("limit", "Page size", default: "50"), string("cursor", "Opaque cursor")], exitCodes: contactsExit),
        leaf(name: "get", description: "Get one contact by external ID.", usage: "mpia contacts get --external-id <id> --format json",
             params: [string("external-id", "External ID", required: true)], exitCodes: [contactsExit, queryExit].flatMap { $0 },
             outputSchema: "ContactPayload"),
        leaf(name: "query", description: "Query contacts with AND semantics.", usage: "mpia contacts query [filters] --format json",
             params: [string("name", "Name filter"), string("email", "Email filter"), string("phone", "Phone filter"),
                      string("organization", "Organization filter"), string("postal-code", "Postal code filter"), string("kind", "person|organization")],
             exitCodes: [contactsExit, queryExit].flatMap { $0 }),
        leaf(name: "create", description: "Create a contact.", usage: "mpia contacts create --input <file>|--stdin --dry-run|--apply [--idempotent]",
             mutates: true, params: [string("input", "JSON file", type: .file), bool("stdin", "Read JSON from stdin"),
                                     bool("apply", "Persist (else dry-run)"), bool("idempotent", "Opt-in create retry")],
             exitCodes: contactsExit, safety: dryRunApply, inputSchema: "ContactPayload", outputSchema: "ContactWriteResult"),
        leaf(name: "edit", description: "Partially edit a contact.", usage: "mpia contacts edit --external-id <id> --input <file>|--stdin --dry-run|--apply",
             mutates: true, params: [string("external-id", "External ID", required: true), string("input", "JSON file", type: .file),
                                     bool("stdin", "Read JSON from stdin")], exitCodes: [contactsExit, queryExit].flatMap { $0 }, safety: dryRunApply),
        leaf(name: "delete", description: "Delete a contact.", usage: "mpia contacts delete --external-id <id> --apply --confirm \"DELETE CONTACT\"",
             mutates: true, params: [string("external-id", "External ID", required: true), bool("ignore-not-found", "Opt-in delete retry")],
             exitCodes: [contactsExit, queryExit].flatMap { $0 }, safety: deleteContact),
        leaf(name: "export", description: "Export a full JSON snapshot.", usage: "mpia contacts export --format json [--output <file>]",
             params: [string("output", "Output file", type: .file)], exitCodes: contactsExit),
    ])

    private static let mail = group(name: "mail", description: "Read-only Mail access.", subcommands: [
        leaf(name: "doctor", description: "Probe Mail-store and capability status without reading messages.", usage: "mpia mail doctor --format json",
             exitCodes: mailExit),
    ])

    private static let calendar = group(name: "calendar", description: "Query and manage calendar events.", subcommands: [
        leaf(name: "permission", description: "Check Calendar full-access authorization.", usage: "mpia calendar permission", exitCodes: calendarExit),
    ])

    private static let reminders = group(name: "reminders", description: "Query and manage reminders.", subcommands: [
        leaf(name: "permission", description: "Check Reminders full-access authorization.", usage: "mpia reminders permission", exitCodes: remindersExit),
    ])

    private static let photos = group(name: "photos", description: "Query photo metadata and export.", subcommands: [
        leaf(name: "permission", description: "Check Photos authorization (status only).", usage: "mpia photos permission", exitCodes: photosExit),
    ])

    private static let notes = group(name: "notes", description: "Bounded Notes.app Automation access.", subcommands: [
        leaf(name: "permission", description: "Check Notes Automation consent (status only).", usage: "mpia notes permission", exitCodes: notesExit),
    ])

    private static let shortcuts = group(name: "shortcuts", description: "Run and author shortcuts.", subcommands: [
        leaf(name: "permission", description: "Check Shortcuts Events consent (status only).", usage: "mpia shortcuts permission", exitCodes: shortcutsExit),
    ])

    private static let safari = group(name: "safari", description: "Bounded Safari bookmarks and Reading List.", subcommands: [
        leaf(name: "permission", description: "Check Safari readability and Automation status.", usage: "mpia safari permission", exitCodes: safariExit),
    ])

    // MARK: JSON Schemas

    private static let schemas: [String: JSONSchema] = [
        "LabeledValue": .object(description: "A labeled string value.", properties: [
            "label": .string("Optional label."),
            "value": .string("Value."),
        ]),
        "PostalAddress": .object(description: "A postal address.", properties: [
            "label": .string("Optional label."),
            "street": .string("Street line."),
            "city": .string("City."),
            "state": .string("State or region."),
            "postalCode": .string("Postal code."),
            "country": .string("Country."),
        ]),
        "ContactPayload": .object(
            title: "ContactPayload",
            description: "Adapter-neutral contact payload exchanged with agents and scripts.",
            properties: [
                "kind": .stringEnum(["person", "organization"], description: "Contact kind."),
                "externalID": .string("Stable external ID; required for every CLI-created contact."),
                "givenName": .string("Given name."),
                "familyName": .string("Family name."),
                "phoneticGivenName": .string("Phonetic given name."),
                "phoneticFamilyName": .string("Phonetic family name."),
                "organizationName": .string("Organization name."),
                "department": .string("Department."),
                "jobTitle": .string("Job title."),
                "emails": .array(of: .ref("LabeledValue")),
                "phones": .array(of: .ref("LabeledValue")),
                "urls": .array(of: .ref("LabeledValue")),
                "addresses": .array(of: .ref("PostalAddress")),
                "metadata": .object(description: "Arbitrary string metadata; preserved in JSON but not persisted by the Contacts adapter.", properties: [:]),
                "imageAvailable": .boolean("Read-only avatar availability."),
            ],
            required: ["kind"]
        ),
        "ContactWriteResult": .object(description: "Final saved state after a Contacts write.", properties: [
            "operation": .string("Write operation name."),
            "contact": .ref("ContactPayload"),
        ]),
    ]

    // MARK: Safety presets

    private static let readOnly = CommandSafety.readOnly
    private static let dryRunApply = CommandSafety(dryRun: true, apply: true)
    private static let deleteContact = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE CONTACT")

    // MARK: Exit-code presets

    private static let contactsExit = [ExitCodeSpec(code: 2, errorCode: "CONTACTS_ERROR", description: "Contacts/permission/input error")]
    private static let queryExit = [ExitCodeSpec(code: 3, errorCode: "CONTACT_QUERY_ERROR", description: "Contact lookup error")]
    private static let mailExit = [ExitCodeSpec(code: 4, errorCode: "MAIL_ERROR", description: "Mail adapter error")]
    private static let calendarExit = [ExitCodeSpec(code: 5, errorCode: "CALENDAR_ERROR", description: "Calendar adapter error")]
    private static let remindersExit = [ExitCodeSpec(code: 6, errorCode: "REMINDERS_ERROR", description: "Reminders adapter error")]
    private static let photosExit = [ExitCodeSpec(code: 7, errorCode: "PHOTOS_ERROR", description: "Photos adapter error")]
    private static let notesExit = [ExitCodeSpec(code: 8, errorCode: "NOTES_ERROR", description: "Notes adapter error")]
    private static let shortcutsExit = [ExitCodeSpec(code: 9, errorCode: "SHORTCUTS_ERROR", description: "Shortcuts adapter error")]
    private static let safariExit = [ExitCodeSpec(code: 10, errorCode: "SAFARI_ERROR", description: "Safari adapter error")]

    // MARK: Builders

    private static func leaf(
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

    private static func group(name: String, description: String, subcommands: [CommandNode]) -> CommandNode {
        CommandNode(
            name: name, kind: .group, description: description, usage: "mpia \(name) <command>",
            mutates: false, params: [], exitCodes: [], safety: .readOnly, subcommands: subcommands
        )
    }

    private static func string(_ name: String, _ description: String, type: ParamType = .string, required: Bool = false, default: String? = nil) -> CommandParam {
        CommandParam(name: name, type: type, required: required, description: description, defaultValue: `default`)
    }

    private static func int(_ name: String, _ description: String, default: String? = nil) -> CommandParam {
        CommandParam(name: name, type: .int, required: false, description: description, defaultValue: `default`)
    }

    private static func bool(_ name: String, _ description: String) -> CommandParam {
        CommandParam(name: name, type: .bool, required: false, description: description)
    }
}
