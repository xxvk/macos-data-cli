public enum ContactQuery: Equatable, Sendable {
    case kind(ContactKind)
    case name(String)
    case phone(String)
    case email(String)
    case url(String)
    case organization(String)
    case postalCode(String)
}

public struct ContactQuerySet: Equatable, Sendable {
    public static let maximumConditions = 3
    public let conditions: [ContactQuery]

    public init(_ conditions: [ContactQuery]) throws {
        guard !conditions.isEmpty, conditions.count <= Self.maximumConditions else {
            throw ContactQuerySetError.invalidConditionCount
        }
        self.conditions = conditions
    }
}

public enum ContactQuerySetError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidConditionCount
    case duplicateField

    public var description: String {
        switch self {
        case .invalidConditionCount: return "Query requires between 1 and 3 conditions."
        case .duplicateField: return "Each query field may only be provided once."
        }
    }
}

public struct ContactQueryMatcher: Sendable {
    public init() {}

    public func matches(_ contact: ContactPayload, query: ContactQuery) -> Bool {
        switch query {
        case .kind(let kind):
            return contact.kind == kind
        case .name(let value):
            let name = [contact.givenName, contact.familyName].compactMap { $0 }.joined(separator: " ")
            return contains(name, value)
        case .phone(let value):
            return contact.phones.contains { normalize($0.value) == normalize(value) }
        case .email(let value):
            return contact.emails.contains { $0.value.caseInsensitiveCompare(value) == .orderedSame }
        case .url(let value):
            return contact.urls.contains { $0.value.caseInsensitiveCompare(value) == .orderedSame }
        case .organization(let value):
            return contains(contact.organizationName ?? "", value)
        case .postalCode(let value):
            return contact.addresses.contains { normalize($0.postalCode ?? "") == normalize(value) }
        }
    }

    public func matches(_ contact: ContactPayload, query: ContactQuerySet) -> Bool {
        query.conditions.allSatisfy { matches(contact, query: $0) }
    }

    private func contains(_ source: String, _ value: String) -> Bool {
        source.localizedCaseInsensitiveContains(value)
    }

    private func normalize(_ value: String) -> String {
        value.filter { $0.isNumber || $0.isLetter }.lowercased()
    }
}
