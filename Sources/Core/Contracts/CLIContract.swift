public enum CLIExitCode: Int32 {
    case success = 0
    case genericFailure = 1
    case contactsFailure = 2
    case queryFailure = 3
    case usage = 64
}

public enum CLIErrorCode: String {
    case contacts = "CONTACTS_ERROR"
    case query = "CONTACT_QUERY_ERROR"
    case invalidQuery = "INVALID_QUERY"
    case cli = "CLI_ERROR"
}
