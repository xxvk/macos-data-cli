extension CommandRegistry {
    // MARK: Safety presets

    static let readOnly = CommandSafety.readOnly
    static let dryRunApply = CommandSafety(dryRun: true, apply: true)
    static let deleteContact = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE CONTACT")
    static let avatarReplace = CommandSafety(dryRun: true, apply: true, confirmation: "RECREATE CONTACT")
    static let migrateContact = CommandSafety(dryRun: true, apply: true, confirmation: "CHANGE EXTERNAL ID")
    static let deleteEvent = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE EVENT")
    static let deleteReminder = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE REMINDER")
    static let deleteNote = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE NOTE")
    static let deleteNotesFolder = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE EMPTY NOTES FOLDER")
    static let editCopy = CommandSafety(dryRun: true, apply: true, confirmation: "EDIT SHORTCUT COPY")
    static let runShortcut = CommandSafety(dryRun: false, apply: true, confirmation: "RUN SHORTCUT")
    static let moveShortcut = CommandSafety(dryRun: true, apply: true, confirmation: "MOVE SHORTCUT")
    static let createManagedShortcut = CommandSafety(dryRun: true, apply: true, confirmation: "CREATE MANAGED SHORTCUT")
    static let updateManagedShortcut = CommandSafety(dryRun: true, apply: true, confirmation: "UPDATE MANAGED SHORTCUT")
    static let forgetManagedShortcut = CommandSafety(dryRun: true, apply: true, confirmation: "FORGET MANAGED SHORTCUT")
    static let bindNotesAccount = CommandSafety(dryRun: true, apply: true, confirmation: "BIND ICLOUD NOTES")
    static let clearNotesAccount = CommandSafety(dryRun: true, apply: true, confirmation: "CLEAR ICLOUD NOTES")
    static let deleteSafariBookmark = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE SAFARI BOOKMARK")
    static let deleteSafariFolder = CommandSafety(dryRun: true, apply: true, confirmation: "DELETE SAFARI FOLDER")

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
    static let messagesExit = [ExitCodeSpec(code: 11, errorCode: "MESSAGES_ERROR", description: "Messages adapter error")]
    static let phoneCallsExit = [ExitCodeSpec(code: 12, errorCode: "PHONE_CALLS_ERROR", description: "Phone calls adapter error")]

    // MARK: Builders

    static func leaf(
        name: String,
        description: String,
        mutates: Bool = false,
        params: [CommandParam] = [],
        exitCodes: [ExitCodeSpec] = [],
        safety: CommandSafety = .readOnly,
        inputSchema: String? = nil,
        outputSchema: String? = nil
    ) -> CommandNode {
        CommandNode(
            name: name, kind: .leaf, description: description,
            mutates: mutates, params: params, exitCodes: exitCodes, safety: safety,
            inputSchema: inputSchema, outputSchema: outputSchema
        )
    }

    static func group(name: String, description: String, subcommands: [CommandNode]) -> CommandNode {
        CommandNode(
            name: name, kind: .group, description: description,
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

    static func strings(_ name: String, _ description: String) -> CommandParam {
        CommandParam(name: name, type: .stringArray, required: false, description: description)
    }
}
