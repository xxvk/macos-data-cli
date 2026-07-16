public enum ContactsQueryError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound
    case ambiguous(Int)

    public var description: String {
        switch self {
        case .notFound: return "No contact matched the external ID."
        case .ambiguous(let count): return "The external ID matched \(count) contacts; refusing to choose automatically."
        }
    }
}
