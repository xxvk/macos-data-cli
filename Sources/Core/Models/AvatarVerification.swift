import Foundation

public enum AvatarVerificationStatus: String, Codable, Sendable {
    case readbackConfirmed = "readback_confirmed"
    case notAvailable = "not_available"
    case saveAccepted = "save_accepted"
    case verificationUnknown = "verification_unknown"
}

public struct AvatarWriteVerification: Codable, Equatable, Sendable {
    public let status: AvatarVerificationStatus
    public let saveAccepted: Bool
    public let requestedBytes: Int
    public let readBackBytes: Int?
    public let nextAction: String?

    public init(status: AvatarVerificationStatus, saveAccepted: Bool, requestedBytes: Int, readBackBytes: Int? = nil, nextAction: String? = nil) {
        self.status = status
        self.saveAccepted = saveAccepted
        self.requestedBytes = requestedBytes
        self.readBackBytes = readBackBytes
        self.nextAction = nextAction
    }
}
