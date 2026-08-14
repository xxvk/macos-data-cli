import Core
import EventKit
import Foundation

public final class RemindersStore: @unchecked Sendable {
    private let eventStore: EKEventStore
    private let permission: any ReminderAccessProviding
    private let sourceSelector: String?
    private let mapper: ReminderMapper
    private let fetchPolicy: ReminderFetchPolicy
    private let createExecutor: ReminderCreateExecutor
    private let deleteExecutor: ReminderDeleteExecutor
    private let idempotencyStore: ReminderIdempotencyStore
    private let now: @Sendable () -> Date

    public init(
        eventStore: EKEventStore = EKEventStore(),
        permission: (any ReminderAccessProviding)? = nil,
        sourceSelector: String? = nil,
        mapper: ReminderMapper = ReminderMapper(),
        fetchPolicy: ReminderFetchPolicy = .standard,
        mutation: (any ReminderMutationProviding)? = nil,
        idempotencyStore: ReminderIdempotencyStore = ReminderIdempotencyStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.permission = permission ?? RemindersPermission(store: eventStore)
        self.sourceSelector = sourceSelector
        self.mapper = mapper
        self.fetchPolicy = fetchPolicy
        let mutation = mutation ?? EventKitReminderMutationGateway(eventStore: eventStore)
        self.createExecutor = ReminderCreateExecutor(mutation: mutation)
        self.deleteExecutor = ReminderDeleteExecutor(mutation: mutation)
        self.idempotencyStore = idempotencyStore
        self.now = now
    }

    public func sourceDescriptions() throws -> ReminderSourceListResult {
        try requireFullAccess()
        let descriptions = allSourceDescriptions()
        let selected = try ReminderSourceSelector.select(descriptions, selector: sourceSelector)
        return ReminderSourceListResult(sources: descriptions, selectedSourceID: selected.identifier)
    }

    public func listDescriptions() throws -> ReminderListResult {
        try requireFullAccess()
        let selected = try ReminderSourceSelector.select(allSourceDescriptions(), selector: sourceSelector)
        let lists = reminderLists().filter { $0.source.sourceIdentifier == selected.identifier }
            .map(descriptor)
            .sorted(by: listOrder)
        return ReminderListResult(lists: lists, selectedSourceID: selected.identifier)
    }

    public func query(_ query: ReminderQuery) async throws -> PagedResult<ReminderPayload> {
        try requireFullAccess()
        let source = try selectedSource()
        let lists = try listsForRead(in: source, selector: query.listID)
        let predicate: NSPredicate
        switch query.status {
        case .all:
            predicate = eventStore.predicateForReminders(in: lists)
        case .incomplete:
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: query.dueStart,
                ending: query.dueEnd,
                calendars: lists
            )
        case .completed:
            predicate = eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: nil,
                ending: nil,
                calendars: lists
            )
        }

        let payloads = try await fetchReminders(matching: predicate)
            .map(mapForOutput)
            .filter { ReminderQueryMatcher.matches($0, query: query) }
        return try ReminderPagination.page(
            items: ReminderOrdering.sorted(payloads),
            query: query,
            selectedListIDs: lists.map(\.calendarIdentifier)
        )
    }

    public func get(id: String) throws -> ReminderPayload {
        try requireFullAccess()
        let source = try selectedSource()
        return try mapForOutput(findReminder(id: id, in: source))
    }

    public func previewDelete(id: String) throws -> ReminderDeleteResult {
        try requireFullAccess()
        let source = try selectedSource()
        let reminder = try findReminder(id: id, in: source)
        try requireWritable(reminder)
        return .preview(try mapForOutput(reminder))
    }

    public func delete(id: String) throws -> ReminderDeleteResult {
        try requireFullAccess()
        let source = try selectedSource()
        let reminder = try findReminder(id: id, in: source)
        try requireWritable(reminder)
        let payload = try mapForOutput(reminder)
        try deleteExecutor.remove(reminder)

        do {
            _ = try get(id: id)
            return .pending(payload)
        } catch ReminderError.reminderNotFound {
            return .confirmed(payload)
        } catch {
            return .pending(payload)
        }
    }

    private func findReminder(id: String, in source: EKSource) throws -> EKReminder {
        let locator = try ReminderOpaqueID.decode(id)

        if let reminder = eventStore.calendarItem(withIdentifier: locator.localIdentifier) as? EKReminder,
           reminder.calendar.source.sourceIdentifier == source.sourceIdentifier {
            return reminder
        }

        guard let externalIdentifier = locator.externalIdentifier, !externalIdentifier.isEmpty else {
            throw ReminderError.reminderNotFound(id)
        }
        let matches = eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
            .compactMap { $0 as? EKReminder }
            .filter { $0.calendar.source.sourceIdentifier == source.sourceIdentifier }
        guard !matches.isEmpty else { throw ReminderError.reminderNotFound(id) }
        guard matches.count == 1 else { throw ReminderError.ambiguousReminder(matches.count) }
        return matches[0]
    }

    private func requireWritable(_ reminder: EKReminder) throws {
        guard reminder.calendar.allowsContentModifications else {
            throw ReminderError.listReadOnly(reminder.calendar.calendarIdentifier)
        }
    }

    private func nextIncompleteOccurrence(
        externalIdentifier: String?,
        excludingLocalIdentifier: String
    ) throws -> ReminderPayload? {
        guard let externalIdentifier, !externalIdentifier.isEmpty else { return nil }
        let source = try selectedSource()
        let candidates = eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
            .compactMap { $0 as? EKReminder }
            .filter {
                !$0.isCompleted &&
                $0.calendarItemIdentifier != excludingLocalIdentifier &&
                $0.calendar.source.sourceIdentifier == source.sourceIdentifier
            }
        return try ReminderOrdering.sorted(candidates.map(mapForOutput)).first
    }

    public func previewCreate(_ rawInput: ReminderInput) throws -> ReminderCreatePreview {
        let prepared = try prepareCreate(rawInput)
        return ReminderCreatePreview(reminder: prepared.draft)
    }

    public func create(_ rawInput: ReminderInput, idempotent: Bool) throws -> ReminderCreateResult {
        let prepared = try prepareCreate(rawInput)
        let resolvedInput = prepared.input

        if idempotent, let receipt = try idempotencyStore.receipt(for: resolvedInput) {
            do {
                return ReminderCreateResult(
                    operation: "existing",
                    created: false,
                    verification: .idempotencyReceiptReadbackConfirmed,
                    reminder: try get(id: receipt.reminderID)
                )
            } catch {
                return ReminderCreateResult(
                    operation: "existing",
                    created: false,
                    verification: .idempotencyReceiptOnly,
                    reminder: payload(from: prepared.draft, id: receipt.reminderID),
                    nextAction: "A recent idempotency receipt prevented a duplicate save, but read-back is pending. Do not retry automatically; use reminders get with the returned ID."
                )
            }
        }

        let identity = try createExecutor.save(prepared.reminder)
        let id = ReminderOpaqueID.encode(
            localIdentifier: identity.localIdentifier,
            externalIdentifier: identity.externalIdentifier
        )
        let receiptSaved: Bool
        if idempotent {
            receiptSaved = (try? idempotencyStore.save(
                ReminderIdempotencyReceipt(reminderID: id, listID: prepared.draft.listID, createdAt: Date()),
                for: resolvedInput
            )) != nil
        } else {
            receiptSaved = true
        }

        do {
            return ReminderCreateResult(
                operation: "created",
                created: true,
                verification: .readbackConfirmed,
                reminder: try get(id: id),
                nextAction: receiptSaved ? nil : "Save and read-back succeeded, but the idempotency receipt could not be stored. Do not automatically retry this create request."
            )
        } catch {
            return ReminderCreateResult(
                operation: "created",
                created: true,
                verification: .saveAcceptedReadbackPending,
                reminder: try mapper.map(
                    prepared.reminder,
                    listID: prepared.draft.listID,
                    listTitle: prepared.draft.listTitle,
                    id: id
                ),
                nextAction: "EventKit accepted the save but immediate read-back is pending. Do not retry automatically; use reminders get with the returned ID."
            )
        }
    }

    public func previewUpdate(id: String, patch: ReminderPatch) throws -> ReminderUpdatePreview {
        let prepared = try prepareUpdate(id: id, patch: patch)
        return ReminderUpdatePreview(before: prepared.before, after: try mapForOutput(prepared.reminder))
    }

    public func update(id: String, patch: ReminderPatch) throws -> ReminderUpdateResult {
        let prepared = try prepareUpdate(id: id, patch: patch)
        let identity = try createExecutor.save(prepared.reminder)
        let updatedID = ReminderOpaqueID.encode(
            localIdentifier: identity.localIdentifier,
            externalIdentifier: identity.externalIdentifier
        )
        do {
            return ReminderUpdateResult(
                verification: .readbackConfirmed,
                reminder: try get(id: updatedID)
            )
        } catch {
            return ReminderUpdateResult(
                verification: .saveAcceptedReadbackPending,
                reminder: try mapper.map(
                    prepared.reminder,
                    listID: prepared.reminder.calendar.calendarIdentifier,
                    listTitle: prepared.reminder.calendar.title,
                    id: updatedID
                ),
                nextAction: "EventKit accepted the update but immediate read-back is pending. Do not retry automatically; use reminders get with the returned ID."
            )
        }
    }

    public func previewStateChange(
        id: String,
        action: ReminderStateAction
    ) throws -> ReminderStateChangePreview {
        let prepared = try prepareStateChange(id: id, action: action)
        return ReminderStateChangePreview(action: action, before: prepared.before, after: prepared.after)
    }

    public func changeState(
        id: String,
        action: ReminderStateAction
    ) throws -> ReminderStateChangeResult {
        let prepared = try prepareStateChange(id: id, action: action)
        guard prepared.changed else { return .noOp(action: action, reminder: prepared.before) }

        let identity = try createExecutor.save(prepared.reminder)
        let updatedID = ReminderOpaqueID.encode(
            localIdentifier: identity.localIdentifier,
            externalIdentifier: identity.externalIdentifier
        )
        let savedSnapshot = payload(prepared.after, replacingID: updatedID)
        do {
            let readback = try get(id: updatedID)
            guard readback.completed == action.targetCompleted else {
                if action == .complete, prepared.before.hasRecurrenceRules, !readback.completed {
                    return .confirmed(action: action, reminder: savedSnapshot, nextOccurrence: readback)
                }
                return .pending(action: action, reminder: savedSnapshot)
            }
            let nextOccurrence = action == .complete && prepared.before.hasRecurrenceRules
                ? try nextIncompleteOccurrence(
                    externalIdentifier: identity.externalIdentifier,
                    excludingLocalIdentifier: identity.localIdentifier
                )
                : nil
            return .confirmed(action: action, reminder: readback, nextOccurrence: nextOccurrence)
        } catch {
            return .pending(action: action, reminder: savedSnapshot)
        }
    }

    private struct PreparedCreate {
        let input: ReminderInput
        let reminder: EKReminder
        let draft: ReminderDraft
    }

    private struct PreparedUpdate {
        let reminder: EKReminder
        let before: ReminderPayload
    }

    private struct PreparedStateChange {
        let reminder: EKReminder
        let before: ReminderPayload
        let after: ReminderPayload
        let changed: Bool
    }

    private func prepareStateChange(
        id: String,
        action: ReminderStateAction
    ) throws -> PreparedStateChange {
        try requireFullAccess()
        let source = try selectedSource()
        let reminder = try findReminder(id: id, in: source)
        try requireWritable(reminder)
        let before = try mapForOutput(reminder)
        let changed = before.completed != action.targetCompleted
        if changed {
            mapper.applyCompletion(action.targetCompleted, completionDate: now(), to: reminder)
        }
        return PreparedStateChange(
            reminder: reminder,
            before: before,
            after: try mapForOutput(reminder),
            changed: changed
        )
    }

    private func prepareUpdate(id: String, patch rawPatch: ReminderPatch) throws -> PreparedUpdate {
        try requireFullAccess()
        let patch = try rawPatch.validated()
        let source = try selectedSource()
        let reminder = try findReminder(id: id, in: source)
        try requireWritable(reminder)
        let before = try mapForOutput(reminder)
        if patch.has("listID") {
            let selected = try ReminderListSelector.selectForWrite(
                lists(in: source).map(descriptor), selector: patch.listID, preferredIdentifier: nil
            )
            guard let calendar = lists(in: source).first(where: { $0.calendarIdentifier == selected.identifier }) else {
                throw ReminderError.listNotFound(selected.identifier)
            }
            reminder.calendar = calendar
        }
        try mapper.apply(patch, to: reminder)
        return PreparedUpdate(reminder: reminder, before: before)
    }

    private func prepareCreate(_ rawInput: ReminderInput) throws -> PreparedCreate {
        try requireFullAccess()
        let input = try rawInput.validated()
        let source = try selectedSource()
        let availableLists = lists(in: source)
        let preferredIdentifier = eventStore.defaultCalendarForNewReminders().flatMap { calendar in
            calendar.source.sourceIdentifier == source.sourceIdentifier && calendar.allowsContentModifications
                ? calendar.calendarIdentifier : nil
        }
        let selected = try ReminderListSelector.selectForWrite(
            availableLists.map(descriptor), selector: input.listID, preferredIdentifier: preferredIdentifier
        )
        guard let calendar = availableLists.first(where: { $0.calendarIdentifier == selected.identifier }) else {
            throw ReminderError.listNotFound(selected.identifier)
        }
        let resolvedInput = ReminderInput(
            listID: selected.identifier,
            title: input.title,
            notes: input.notes,
            url: input.url,
            priority: input.priority,
            start: input.start,
            due: input.due,
            alarms: input.alarms,
            recurrenceRules: input.recurrenceRules
        )
        let reminder = try mapper.makeReminder(from: resolvedInput, eventStore: eventStore, calendar: calendar)
        let draft = try mapper.mapDraft(reminder, listID: selected.identifier, listTitle: selected.title)
        return PreparedCreate(input: resolvedInput, reminder: reminder, draft: draft)
    }

    private func payload(from draft: ReminderDraft, id: String) -> ReminderPayload {
        ReminderPayload(
            id: id,
            listID: draft.listID,
            listTitle: draft.listTitle,
            title: draft.title,
            notes: draft.notes,
            url: draft.url,
            priority: draft.priority,
            start: draft.start,
            due: draft.due,
            hasAlarms: !draft.alarms.isEmpty,
            hasRecurrenceRules: !draft.recurrenceRules.isEmpty,
            alarms: draft.alarms,
            recurrenceRules: draft.recurrenceRules
        )
    }

    private func payload(_ value: ReminderPayload, replacingID id: String) -> ReminderPayload {
        ReminderPayload(
            id: id,
            listID: value.listID,
            listTitle: value.listTitle,
            title: value.title,
            notes: value.notes,
            url: value.url,
            priority: value.priority,
            completed: value.completed,
            completionDate: value.completionDate,
            start: value.start,
            due: value.due,
            hasAlarms: value.hasAlarms,
            hasRecurrenceRules: value.hasRecurrenceRules,
            alarms: value.alarms,
            recurrenceRules: value.recurrenceRules
        )
    }

    private func requireFullAccess() throws {
        switch permission.status {
        case .fullAccess: return
        case .notDetermined: throw ReminderError.permissionRequired
        case .denied: throw ReminderError.permissionDenied
        case .restricted: throw ReminderError.permissionRestricted
        case .writeOnly: throw ReminderError.fullAccessRequired
        }
    }

    private func reminderLists() -> [EKCalendar] {
        eventStore.calendars(for: .reminder)
    }

    private func selectedSource() throws -> EKSource {
        let selected = try ReminderSourceSelector.select(allSourceDescriptions(), selector: sourceSelector)
        guard let source = eventStore.sources.first(where: { $0.sourceIdentifier == selected.identifier }) else {
            throw ReminderError.sourceNotFound(selected.identifier)
        }
        return source
    }

    private func lists(in source: EKSource) -> [EKCalendar] {
        reminderLists().filter { $0.source.sourceIdentifier == source.sourceIdentifier }
    }

    private func listsForRead(in source: EKSource, selector: String?) throws -> [EKCalendar] {
        let values = lists(in: source)
        guard let selector else { return values }
        let matches = ReminderListSelector.matching(values.map(descriptor), selector: selector)
        guard !matches.isEmpty else { throw ReminderError.listNotFound(selector) }
        guard matches.count == 1 else { throw ReminderError.ambiguousList(matches.count) }
        return values.filter { $0.calendarIdentifier == matches[0].identifier }
    }

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        let values = try await ReminderFetchCoordinator(
            requester: EventKitReminderFetchRequester(eventStore: eventStore),
            timeoutSeconds: fetchPolicy.timeoutSeconds
        ).fetch(matching: predicate)
        try fetchPolicy.validate(itemCount: values.count)
        return values
    }

    private func mapForOutput(_ reminder: EKReminder) throws -> ReminderPayload {
        let localIdentifier = reminder.calendarItemIdentifier
        guard !localIdentifier.isEmpty else {
            throw ReminderError.readFailed("EventKit returned a reminder without a local identifier.")
        }
        let rawExternalIdentifier = reminder.calendarItemExternalIdentifier
        let externalIdentifier = rawExternalIdentifier?.isEmpty == false ? rawExternalIdentifier : nil
        return try mapper.map(
            reminder,
            listID: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title,
            id: ReminderOpaqueID.encode(
                localIdentifier: localIdentifier,
                externalIdentifier: externalIdentifier
            )
        )
    }

    private func allSourceDescriptions() -> [ReminderSourceDescriptor] {
        let sourceIDs = Set(reminderLists().map { $0.source.sourceIdentifier })
        return eventStore.sources.filter { sourceIDs.contains($0.sourceIdentifier) }
            .map(descriptor)
            .sorted {
                if $0.isICloud != $1.isICloud { return $0.isICloud && !$1.isICloud }
                if $0.title != $1.title {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.identifier < $1.identifier
            }
    }

    private func descriptor(_ source: EKSource) -> ReminderSourceDescriptor {
        let isICloud = source.sourceType == .calDAV &&
            source.title.compare("iCloud", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        return ReminderSourceDescriptor(
            title: source.title,
            identifier: source.sourceIdentifier,
            type: source.sourceType.reminderStringValue,
            isICloud: isICloud
        )
    }

    private func descriptor(_ list: EKCalendar) -> ReminderListDescriptor {
        ReminderListDescriptor(
            title: list.title,
            identifier: list.calendarIdentifier,
            sourceIdentifier: list.source.sourceIdentifier,
            type: list.type.reminderStringValue,
            allowsContentModifications: list.allowsContentModifications
        )
    }

    private func listOrder(_ lhs: ReminderListDescriptor, _ rhs: ReminderListDescriptor) -> Bool {
        if lhs.title != rhs.title {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.identifier < rhs.identifier
    }
}

private extension EKSourceType {
    var reminderStringValue: String {
        switch self {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "calDAV"
        case .mobileMe: "mobileMe"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        @unknown default: "unknown"
        }
    }
}

private extension EKCalendarType {
    var reminderStringValue: String {
        switch self {
        case .local: "local"
        case .calDAV: "calDAV"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }
}
