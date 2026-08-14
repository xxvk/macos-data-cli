import Core
import EventKit
import Foundation

public struct ReminderSavedIdentity: Equatable, Sendable {
    public let localIdentifier: String
    public let externalIdentifier: String?

    public init(localIdentifier: String, externalIdentifier: String?) {
        self.localIdentifier = localIdentifier
        self.externalIdentifier = externalIdentifier
    }
}

public protocol ReminderMutationProviding: Sendable {
    func save(_ reminder: EKReminder) throws -> ReminderSavedIdentity
    func remove(_ reminder: EKReminder) throws
}

final class EventKitReminderMutationGateway: ReminderMutationProviding, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore) { self.eventStore = eventStore }

    func save(_ reminder: EKReminder) throws -> ReminderSavedIdentity {
        do { try eventStore.save(reminder, commit: true) }
        catch { throw ReminderError.writeFailed(error.localizedDescription) }
        let localIdentifier = reminder.calendarItemIdentifier
        guard !localIdentifier.isEmpty else { throw ReminderError.savedIdentifierUnavailable }
        let rawExternal = reminder.calendarItemExternalIdentifier
        return ReminderSavedIdentity(
            localIdentifier: localIdentifier,
            externalIdentifier: rawExternal?.isEmpty == false ? rawExternal : nil
        )
    }

    func remove(_ reminder: EKReminder) throws {
        do { try eventStore.remove(reminder, commit: true) }
        catch { throw ReminderError.writeFailed(error.localizedDescription) }
    }
}
