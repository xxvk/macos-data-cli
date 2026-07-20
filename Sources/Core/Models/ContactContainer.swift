import Foundation

public struct ContactContainer: Codable, Equatable, Sendable {
    public let name: String
    public let identifier: String
    public let type: String
    public let isICloud: Bool

    public init(name: String, identifier: String, type: String, isICloud: Bool) {
        self.name = name
        self.identifier = identifier
        self.type = type
        self.isICloud = isICloud
    }
}
