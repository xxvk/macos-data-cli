import Core
import EventKit

public final class CalendarPermission: CalendarAccessProviding, @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public var status: CalendarAccessStatus {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    public func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public static func map(_ status: EKAuthorizationStatus) -> CalendarAccessStatus {
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
