import Core
import EventKit
import Foundation

final class ReminderFetchToken: @unchecked Sendable {
    let rawValue: Any
    init(rawValue: Any) { self.rawValue = rawValue }
}

protocol ReminderFetchRequesting: Sendable {
    func start(
        matching predicate: NSPredicate,
        completion: @escaping @Sendable ([EKReminder]?) -> Void
    ) -> ReminderFetchToken
    func cancel(_ token: ReminderFetchToken)
}

final class EventKitReminderFetchRequester: ReminderFetchRequesting, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore) { self.eventStore = eventStore }

    func start(
        matching predicate: NSPredicate,
        completion: @escaping @Sendable ([EKReminder]?) -> Void
    ) -> ReminderFetchToken {
        let request = eventStore.fetchReminders(matching: predicate, completion: completion)
        return ReminderFetchToken(rawValue: request)
    }

    func cancel(_ token: ReminderFetchToken) {
        eventStore.cancelFetchRequest(token.rawValue)
    }
}

final class ReminderFetchCoordinator: @unchecked Sendable {
    private let requester: any ReminderFetchRequesting
    private let timeoutSeconds: TimeInterval
    private let lock = NSLock()
    private var completed = false
    private var cancellationRequested = false
    private var terminalOutcome: ReminderFetchOutcome?
    private var requestToken: ReminderFetchToken?
    private var continuation: CheckedContinuation<ReminderFetchOutcome, Never>?

    init(requester: any ReminderFetchRequesting, timeoutSeconds: TimeInterval) {
        self.requester = requester
        self.timeoutSeconds = timeoutSeconds
    }

    func fetch(matching predicate: NSPredicate) async throws -> [EKReminder] {
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let terminal = install(continuation) {
                    continuation.resume(returning: terminal)
                    return
                }

                let token = requester.start(matching: predicate) { [weak self] reminders in
                    guard let self else { return }
                    guard let reminders else {
                        self.finish(ReminderFetchOutcome(error: .readFailed("EventKit returned no reminder result.")))
                        return
                    }
                    self.finish(ReminderFetchOutcome(values: reminders))
                }
                install(token)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                    self?.cancel(with: .queryTimedOut)
                }
            }
        } onCancel: { [weak self] in
            self?.cancel(with: .queryCancelled)
        }

        if let error = outcome.error { throw error }
        return outcome.values ?? []
    }

    private func install(_ continuation: CheckedContinuation<ReminderFetchOutcome, Never>) -> ReminderFetchOutcome? {
        lock.withLock {
            if completed { return terminalOutcome ?? ReminderFetchOutcome(error: .queryCancelled) }
            self.continuation = continuation
            return nil
        }
    }

    private func install(_ token: ReminderFetchToken) {
        let shouldCancel = lock.withLock {
            requestToken = token
            return completed && cancellationRequested
        }
        if shouldCancel { requester.cancel(token) }
    }

    private func cancel(with error: ReminderError) {
        let action: (ReminderFetchToken?, CheckedContinuation<ReminderFetchOutcome, Never>?)? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            cancellationRequested = true
            let outcome = ReminderFetchOutcome(error: error)
            terminalOutcome = outcome
            let value = (requestToken, continuation)
            continuation = nil
            return value
        }
        guard let action else { return }
        if let token = action.0 { requester.cancel(token) }
        action.1?.resume(returning: ReminderFetchOutcome(error: error))
    }

    private func finish(_ outcome: ReminderFetchOutcome) {
        let continuation: CheckedContinuation<ReminderFetchOutcome, Never>? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            terminalOutcome = outcome
            let value = self.continuation
            self.continuation = nil
            return value
        }
        continuation?.resume(returning: outcome)
    }
}

private struct ReminderFetchOutcome: @unchecked Sendable {
    let values: [EKReminder]?
    let error: ReminderError?

    init(values: [EKReminder]? = nil, error: ReminderError? = nil) {
        self.values = values
        self.error = error
    }
}
