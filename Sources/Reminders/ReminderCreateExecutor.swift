import EventKit

final class ReminderCreateExecutor: @unchecked Sendable {
    private let mutation: any ReminderMutationProviding

    init(mutation: any ReminderMutationProviding) { self.mutation = mutation }

    func save(_ reminder: EKReminder) throws -> ReminderSavedIdentity {
        try mutation.save(reminder)
    }
}
