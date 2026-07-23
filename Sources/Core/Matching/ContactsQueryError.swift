public enum ContactsQueryError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound
    case ambiguous(Int)
    case invalidLimit
    case invalidCursor

    public var description: String {
        switch self {
        case .notFound: return "No contact matched the external ID."
        case .ambiguous(let count): return "The external ID matched \(count) contacts; refusing to choose automatically."
        case .invalidLimit: return "Contact page limit must be between 1 and 200."
        case .invalidCursor: return "Contact page cursor is invalid or stale."
        }
    }
}
