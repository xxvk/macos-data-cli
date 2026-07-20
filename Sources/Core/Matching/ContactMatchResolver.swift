public enum ContactMatchResolver {
    public static func requireExactlyOne<T>(_ matches: [T]) throws -> T {
        switch matches.count {
        case 0: throw ContactsQueryError.notFound
        case 1: return matches[0]
        default: throw ContactsQueryError.ambiguous(matches.count)
        }
    }
}
