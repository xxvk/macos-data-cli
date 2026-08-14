public enum CLIExitCode: Int32 {
    case success = 0
    case genericFailure = 1
    case contactsFailure = 2
    case queryFailure = 3
    case mailFailure = 4
    case calendarFailure = 5
    case remindersFailure = 6
    case photosFailure = 7
    case notesFailure = 8
    case shortcutsFailure = 9
    case usage = 64
}

public enum CLIErrorCode: String {
    case contacts = "CONTACTS_ERROR"
    case query = "CONTACT_QUERY_ERROR"
    case mail = "MAIL_ERROR"
    case calendar = "CALENDAR_ERROR"
    case reminders = "REMINDERS_ERROR"
    case photos = "PHOTOS_ERROR"
    case notes = "NOTES_ERROR"
    case shortcuts = "SHORTCUTS_ERROR"
    case invalidQuery = "INVALID_QUERY"
    case cli = "CLI_ERROR"
}
