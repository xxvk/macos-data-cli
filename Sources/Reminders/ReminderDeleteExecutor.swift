import EventKit

struct ReminderDeleteExecutor {
    private let mutation: any ReminderMutationProviding

    init(mutation: any ReminderMutationProviding) {
        self.mutation = mutation
    }

    func remove(_ reminder: EKReminder) throws {
        try mutation.remove(reminder)
    }
}
