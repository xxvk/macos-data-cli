import Core
import EventKit
import Foundation

public final class CalendarStore: @unchecked Sendable {
    private let eventStore: EKEventStore
    private let permission: any CalendarAccessProviding
    private let sourceSelector: String?
    private let mapper: CalendarMapper
    private let idempotencyStore: CalendarIdempotencyStore

    public init(
        eventStore: EKEventStore = EKEventStore(),
        permission: (any CalendarAccessProviding)? = nil,
        sourceSelector: String? = nil,
        mapper: CalendarMapper = CalendarMapper(),
        idempotencyStore: CalendarIdempotencyStore = CalendarIdempotencyStore()
    ) {
        self.eventStore = eventStore
        self.permission = permission ?? CalendarPermission(store: eventStore)
        self.sourceSelector = sourceSelector
        self.mapper = mapper
        self.idempotencyStore = idempotencyStore
    }

    public func sourceDescriptions() throws -> CalendarSourceListResult {
        try requireFullAccess()
        let descriptions = allSourceDescriptions()
        let selected = try CalendarSourceSelector.select(descriptions, selector: sourceSelector)
        return CalendarSourceListResult(sources: descriptions, selectedSourceID: selected.identifier)
    }

    public func selectedSourceDescription() throws -> CalendarSourceDescriptor {
        try requireFullAccess()
        return try CalendarSourceSelector.select(allSourceDescriptions(), selector: sourceSelector)
    }

    public func calendarDescriptions() throws -> CalendarListResult {
        try requireFullAccess()
        let source = try selectedSource()
        return CalendarListResult(
            calendars: calendars(in: source).map(descriptor).sorted(by: calendarOrder),
            selectedSourceID: source.sourceIdentifier
        )
    }

    public func query(_ query: CalendarEventQuery) throws -> PagedResult<CalendarEventPayload> {
        try requireFullAccess()
        let source = try selectedSource()
        let selectedCalendars = try calendarsForRead(in: source, selector: query.calendarID)
        let predicate = eventStore.predicateForEvents(withStart: query.startDate, end: query.endDate, calendars: selectedCalendars)
        var events = eventStore.events(matching: predicate)
        if let title = query.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            events = events.filter { ($0.title ?? "").localizedCaseInsensitiveContains(title) }
        }
        let payloads = events.map(mapForOutput).sorted(by: eventOrder)
        return try Pagination.page(items: payloads, limit: query.limit, cursor: query.cursor, prefix: "calevt_")
    }

    public func get(id: String) throws -> CalendarEventPayload {
        mapForOutput(try requireEvent(id: id))
    }

    public func previewCreate(_ input: CalendarEventInput) throws -> CalendarEventPayload {
        try requireFullAccess()
        let source = try selectedSource()
        let event = try mapper.makeEvent(from: input, eventStore: eventStore)
        event.calendar = try calendarForWrite(in: source, selector: input.calendarID)
        return mapForOutput(event)
    }

    public func create(_ input: CalendarEventInput) throws -> CalendarEventPayload {
        try requireFullAccess()
        let source = try selectedSource()
        let event = try mapper.makeEvent(from: input, eventStore: eventStore)
        event.calendar = try calendarForWrite(in: source, selector: input.calendarID)
        do { try eventStore.save(event, span: .thisEvent, commit: true) }
        catch { throw CalendarError.writeFailed(error.localizedDescription) }
        return mapForOutput(event)
    }

    public func createIdempotent(_ input: CalendarEventInput, dryRun: Bool) throws -> (event: CalendarEventPayload, created: Bool) {
        try requireFullAccess()
        if !dryRun, let receipt = try idempotencyStore.receipt(for: input) {
            return (try payloadFromReceipt(receipt, input: input), false)
        }
        let candidates = try idempotencyCandidates(for: input)
        if let existing = candidates.first(where: { CalendarIdempotencyMatcher.equivalent(input, $0) }) {
            if !dryRun {
                try idempotencyStore.save(CalendarIdempotencyReceipt(eventID: existing.id, calendarID: existing.calendarID, createdAt: Date()), for: input)
            }
            return (existing, false)
        }
        if !candidates.isEmpty { throw CalendarError.idempotencyConflict(candidates.count) }
        if dryRun { return (try previewCreate(input), true) }
        let created = try create(input)
        try idempotencyStore.save(CalendarIdempotencyReceipt(eventID: created.id, calendarID: created.calendarID, createdAt: Date()), for: input)
        return (created, true)
    }

    private func payloadFromReceipt(_ receipt: CalendarIdempotencyReceipt, input: CalendarEventInput) throws -> CalendarEventPayload {
        let source = try selectedSource()
        let calendar = try calendarForWrite(in: source, selector: input.calendarID)
        return CalendarEventPayload(
            id: receipt.eventID,
            calendarID: receipt.calendarID ?? calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            title: input.title,
            startDate: input.startDate,
            endDate: input.endDate,
            allDay: input.allDay,
            timeZone: input.allDay ? nil : input.timeZone,
            location: input.location,
            notes: input.notes,
            url: input.url,
            alarms: input.alarms,
            recurrenceRules: input.recurrenceRules,
            availability: "busy",
            status: "none"
        )
    }

    private func idempotencyCandidates(for input: CalendarEventInput) throws -> [CalendarEventPayload] {
        let source = try selectedSource()
        let calendar = try calendarForWrite(in: source, selector: input.calendarID)
        let predicate = eventStore.predicateForEvents(
            withStart: input.startDate.addingTimeInterval(-1),
            end: input.startDate.addingTimeInterval(1),
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate).filter {
            ($0.title ?? "") == input.title && abs($0.startDate.timeIntervalSince(input.startDate)) < 0.001
        }.map(mapForOutput)
    }

    public func conflicts(_ query: CalendarEventQuery) throws -> CalendarConflictResult {
        try requireFullAccess()
        let source = try selectedSource()
        let selectedCalendars = try calendarsForRead(in: source, selector: query.calendarID)
        let predicate = eventStore.predicateForEvents(withStart: query.startDate, end: query.endDate, calendars: selectedCalendars)
        let events = eventStore.events(matching: predicate).map(mapForOutput)
        try CalendarConflictDetector.validateEventCount(events.count)
        return CalendarConflictResult(checkedEventCount: events.count, conflicts: CalendarConflictDetector.detect(events))
    }

    public func previewUpdate(id: String, patch: CalendarEventPatch, span: CalendarMutationSpan?) throws -> CalendarEventPayload {
        let event = try requireEvent(id: id)
        try requireSpanWhenRecurring(event, span: span)
        try apply(patch, to: event)
        return mapForOutput(event)
    }

    public func update(id: String, patch: CalendarEventPatch, span: CalendarMutationSpan?) throws -> CalendarEventPayload {
        let event = try requireEvent(id: id)
        let resolvedSpan = try requireSpanWhenRecurring(event, span: span)
        try apply(patch, to: event)
        do { try eventStore.save(event, span: resolvedSpan.eventKitValue, commit: true) }
        catch { throw CalendarError.writeFailed(error.localizedDescription) }
        idempotencyStore.invalidate(eventID: id)
        return mapForOutput(event)
    }

    public func previewDelete(id: String, span: CalendarMutationSpan?) throws -> CalendarEventPayload {
        let event = try requireEvent(id: id)
        _ = try requireSpanWhenRecurring(event, span: span)
        return mapForOutput(event)
    }

    public func delete(id: String, span: CalendarMutationSpan?) throws -> CalendarEventPayload {
        let event = try requireEvent(id: id)
        let resolvedSpan = try requireSpanWhenRecurring(event, span: span)
        let payload = mapForOutput(event)
        do { try eventStore.remove(event, span: resolvedSpan.eventKitValue, commit: true) }
        catch { throw CalendarError.writeFailed(error.localizedDescription) }
        idempotencyStore.invalidate(eventID: id)
        return payload
    }

    private func requireFullAccess() throws {
        switch permission.status {
        case .fullAccess: return
        case .notDetermined: throw CalendarError.permissionRequired
        case .denied: throw CalendarError.permissionDenied
        case .restricted: throw CalendarError.permissionRestricted
        case .writeOnly: throw CalendarError.fullAccessRequired
        }
    }

    private func allSourceDescriptions() -> [CalendarSourceDescriptor] {
        eventStore.sources.map(descriptor).sorted {
            if $0.isICloud != $1.isICloud { return $0.isICloud && !$1.isICloud }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.identifier < $1.identifier
        }
    }

    private func selectedSource() throws -> EKSource {
        let selected = try CalendarSourceSelector.select(allSourceDescriptions(), selector: sourceSelector)
        guard let source = eventStore.sources.first(where: { $0.sourceIdentifier == selected.identifier }) else {
            throw CalendarError.sourceNotFound(selected.identifier)
        }
        return source
    }

    private func calendars(in source: EKSource) -> [EKCalendar] {
        eventStore.calendars(for: .event).filter { $0.source.sourceIdentifier == source.sourceIdentifier }
    }

    private func calendarsForRead(in source: EKSource, selector: String?) throws -> [EKCalendar] {
        let values = calendars(in: source)
        guard let selector else { return values }
        let matches = CalendarSelector.matching(values.map(descriptor), selector: selector)
        guard !matches.isEmpty else { throw CalendarError.calendarNotFound(selector) }
        guard matches.count == 1 else { throw CalendarError.ambiguousCalendar(matches.count) }
        return values.filter { $0.calendarIdentifier == matches[0].identifier }
    }

    private func calendarForWrite(in source: EKSource, selector: String?) throws -> EKCalendar {
        let values = calendars(in: source)
        let selected = try CalendarSelector.selectForWrite(
            values.map(descriptor),
            selector: selector,
            preferredIdentifier: eventStore.defaultCalendarForNewEvents?.source.sourceIdentifier == source.sourceIdentifier
                ? eventStore.defaultCalendarForNewEvents?.calendarIdentifier
                : nil
        )
        guard let calendar = values.first(where: { $0.calendarIdentifier == selected.identifier }) else {
            throw CalendarError.calendarNotFound(selected.identifier)
        }
        return calendar
    }

    private func requireEvent(id: String) throws -> EKEvent {
        try requireFullAccess()
        let locator = try CalendarOpaqueID.decode(id)
        let source = try selectedSource()
        let values = calendars(in: source)
        let windowStart = locator.occurrenceStart.addingTimeInterval(-1)
        let windowEnd = locator.occurrenceStart.addingTimeInterval(1)
        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: values)
        guard let event = eventStore.events(matching: predicate).first(where: {
            $0.calendarItemIdentifier == locator.calendarItemIdentifier && abs($0.startDate.timeIntervalSince(locator.occurrenceStart)) < 0.001
        }) else { throw CalendarError.eventNotFound(id) }
        return event
    }

    private func mapForOutput(_ event: EKEvent) -> CalendarEventPayload {
        let identifier = event.calendarItemIdentifier
        guard !identifier.isEmpty else { return mapper.map(event) }
        return mapper.map(event, id: CalendarOpaqueID.encode(calendarItemIdentifier: identifier, occurrenceStart: event.startDate))
    }

    private func apply(_ patch: CalendarEventPatch, to event: EKEvent) throws {
        if patch.has("calendarID") {
            guard let selector = patch.calendarID else { throw CalendarError.invalidInput("calendarID cannot be null") }
            let source = try selectedSource()
            event.calendar = try calendarForWrite(in: source, selector: selector)
        }
        try mapper.apply(patch, to: event)
    }

    @discardableResult
    private func requireSpanWhenRecurring(_ event: EKEvent, span: CalendarMutationSpan?) throws -> CalendarMutationSpan {
        if event.hasRecurrenceRules, span == nil { throw CalendarError.recurringSpanRequired }
        return span ?? .thisEvent
    }

    private func descriptor(_ source: EKSource) -> CalendarSourceDescriptor {
        let title = source.title
        let isICloud = source.sourceType == .calDAV && title.compare("iCloud", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        return CalendarSourceDescriptor(title: title, identifier: source.sourceIdentifier, type: source.sourceType.stringValue, isICloud: isICloud)
    }

    private func descriptor(_ calendar: EKCalendar) -> CalendarDescriptor {
        CalendarDescriptor(
            title: calendar.title,
            identifier: calendar.calendarIdentifier,
            sourceIdentifier: calendar.source.sourceIdentifier,
            type: calendar.type.stringValue,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private func calendarOrder(_ lhs: CalendarDescriptor, _ rhs: CalendarDescriptor) -> Bool {
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return lhs.identifier < rhs.identifier
    }

    private func eventOrder(_ lhs: CalendarEventPayload, _ rhs: CalendarEventPayload) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return (lhs.id ?? "") < (rhs.id ?? "")
    }
}

private extension CalendarMutationSpan {
    var eventKitValue: EKSpan { self == .futureEvents ? .futureEvents : .thisEvent }
}

private extension EKSourceType {
    var stringValue: String {
        switch self { case .local: "local"; case .exchange: "exchange"; case .calDAV: "calDAV"; case .mobileMe: "mobileMe"; case .subscribed: "subscribed"; case .birthdays: "birthdays"; @unknown default: "unknown" }
    }
}

private extension EKCalendarType {
    var stringValue: String {
        switch self { case .local: "local"; case .calDAV: "calDAV"; case .exchange: "exchange"; case .subscription: "subscription"; case .birthday: "birthday"; @unknown default: "unknown" }
    }
}
