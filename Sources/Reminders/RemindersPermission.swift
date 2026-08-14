import Core
import EventKit

public final class RemindersPermission: ReminderAccessProviding, @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public var status: ReminderAccessStatus {
        Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    public func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public static func map(_ status: EKAuthorizationStatus) -> ReminderAccessStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess, .authorized: .fullAccess
        @unknown default: .denied
        }
    }
}
