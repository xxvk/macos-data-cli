import Contacts
import Core

public final class ContactsPermission: ContactsAccessProviding, @unchecked Sendable {
    private let store: CNContactStore

    public init(store: CNContactStore = CNContactStore()) { self.store = store }

    public var status: ContactsAccessStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    public func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }
}
