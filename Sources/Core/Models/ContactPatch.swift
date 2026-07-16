import Foundation

public struct ContactPatch: Codable, Sendable {
    public var kind: ContactKind?
    public var externalID: String?
    public var givenName: String?
    public var familyName: String?
    public var organizationName: String?
    public var department: String?
    public var jobTitle: String?
    public var emails: [LabeledValue]?
    public var phones: [LabeledValue]?
    public var urls: [LabeledValue]?
    public var addresses: [PostalAddress]?
    public var metadata: [String: String]?
    private var present: Set<String> = []

    private enum CodingKeys: String, CodingKey { case kind, externalID, givenName, familyName, organizationName, department, jobTitle, emails, phones, urls, addresses, metadata }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) throws -> T? { try c.contains(key) ? c.decodeIfPresent(T.self, forKey: key) : nil }
        kind = try value(.kind); externalID = try value(.externalID); givenName = try value(.givenName); familyName = try value(.familyName); organizationName = try value(.organizationName); department = try value(.department); jobTitle = try value(.jobTitle); emails = try value(.emails); phones = try value(.phones); urls = try value(.urls); addresses = try value(.addresses); metadata = try value(.metadata)
        present = Set(c.allKeys.map { $0.stringValue })
    }

    public func has(_ key: String) -> Bool { present.contains(key) }
}
