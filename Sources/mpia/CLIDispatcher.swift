import Core

extension MpiaCLI {
    static func dispatch(
        _ arguments: [String],
        manifest: CommandManifest,
        containerSelector: String?,
        calendarSourceSelector: String?,
        remindersSourceSelector: String?
    ) async throws -> Bool {
        switch arguments.first {
        case "agent", "resources":
            return try handleAgentResources(
                arguments,
                manifest: manifest,
                containerSelector: containerSelector,
                calendarSourceSelector: calendarSourceSelector,
                remindersSourceSelector: remindersSourceSelector
            )
        case "contacts": return try await handleContacts(arguments, containerSelector: containerSelector)
        case "mail": return try handleMail(arguments)
        case "calendar": return try await handleCalendar(arguments, sourceSelector: calendarSourceSelector)
        case "reminders": return try await handleReminders(arguments, sourceSelector: remindersSourceSelector)
        case "photos": return try await handlePhotos(arguments)
        case "notes": return try handleNotes(arguments)
        case "shortcuts": return try handleShortcuts(arguments)
        case "safari": return try handleSafari(arguments)
        case "messages", "phone-calls": return try handleCommunication(arguments)
        default: return false
        }
    }
}
