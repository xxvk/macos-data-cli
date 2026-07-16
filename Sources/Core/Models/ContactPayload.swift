import Foundation

/// Adapter-neutral contact payload exchanged with agents and scripts.
public struct ContactPayload: Codable, Equatable, Sendable {
    public var kind: ContactKind
    public var externalID: String?
    public var givenName: String?
    public var familyName: String?
    public var organizationName: String?
    public var department: String?
    public var jobTitle: String?
    public var emails: [LabeledValue]
    public var phones: [LabeledValue]
    public var urls: [LabeledValue]
    public var addresses: [PostalAddress]
    public var metadata: [String: String]

    public init(kind: ContactKind = .person, externalID: String? = nil, givenName: String? = nil, familyName: String? = nil, organizationName: String? = nil, department: String? = nil, jobTitle: String? = nil, emails: [LabeledValue] = [], phones: [LabeledValue] = [], urls: [LabeledValue] = [], addresses: [PostalAddress] = [], metadata: [String: String] = [:]) {
        self.kind = kind
        self.externalID = externalID
        self.givenName = givenName
        self.familyName = familyName
        self.organizationName = organizationName
        self.department = department
        self.jobTitle = jobTitle
        self.emails = emails
        self.phones = phones
        self.urls = urls
        self.addresses = addresses
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case kind, externalID, givenName, familyName, organizationName, department, jobTitle, emails, phones, urls, addresses, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(ContactKind.self, forKey: .kind) ?? .person
        self.externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        self.givenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        self.familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
        self.organizationName = try container.decodeIfPresent(String.self, forKey: .organizationName)
        self.department = try container.decodeIfPresent(String.self, forKey: .department)
        self.jobTitle = try container.decodeIfPresent(String.self, forKey: .jobTitle)
        self.emails = try container.decodeIfPresent([LabeledValue].self, forKey: .emails) ?? []
        self.phones = try container.decodeIfPresent([LabeledValue].self, forKey: .phones) ?? []
        self.urls = try container.decodeIfPresent([LabeledValue].self, forKey: .urls) ?? []
        self.addresses = try container.decodeIfPresent([PostalAddress].self, forKey: .addresses) ?? []
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

public enum ContactKind: String, Codable, Equatable, Sendable {
    case person
    case organization
}

public struct LabeledValue: Codable, Equatable, Sendable {
    public var label: String?
    public var value: String

    public init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PostalAddress: Codable, Equatable, Sendable {
    public var label: String?
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var country: String?

    public init(label: String? = nil, street: String? = nil, city: String? = nil, state: String? = nil, postalCode: String? = nil, country: String? = nil) {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }
}
