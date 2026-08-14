import Core
import EventKit
import XCTest
@testable import RemindersAdapter

final class RemindersAdapterTests: XCTestCase {
    private struct PermissionStub: ReminderAccessProviding {
        let status: ReminderAccessStatus
        func requestFullAccess() async throws -> Bool { status == .fullAccess }
    }

    private final class FetchStub: ReminderFetchRequesting, @unchecked Sendable {
        private let lock = NSLock()
        private var completion: (@Sendable ([EKReminder]?) -> Void)?
        private var started = false
        private(set) var cancelCount = 0

        var isStarted: Bool { lock.withLock { started } }

        func start(
            matching predicate: NSPredicate,
            completion: @escaping @Sendable ([EKReminder]?) -> Void
        ) -> ReminderFetchToken {
            lock.withLock {
                self.completion = completion
                started = true
            }
            return ReminderFetchToken(rawValue: UUID())
        }

        func cancel(_ token: ReminderFetchToken) {
            lock.withLock { cancelCount += 1 }
        }

        func complete(with values: [EKReminder]?) {
            let callback = lock.withLock { completion }
            callback?(values)
        }
    }

    private final class MutationStub: ReminderMutationProviding, @unchecked Sendable {
        private(set) var saveCount = 0
        private(set) var removeCount = 0
        let result: Result<ReminderSavedIdentity, Error>
        var removeError: Error?

        init(result: Result<ReminderSavedIdentity, Error>) { self.result = result }

        func save(_ reminder: EKReminder) throws -> ReminderSavedIdentity {
            saveCount += 1
            return try result.get()
        }

        func remove(_ reminder: EKReminder) throws {
            removeCount += 1
            if let removeError { throw removeError }
        }
    }

    func testPermissionMapperRequiresFullAccess() {
        XCTAssertEqual(RemindersPermission.map(.notDetermined), .notDetermined)
        XCTAssertEqual(RemindersPermission.map(.restricted), .restricted)
        XCTAssertEqual(RemindersPermission.map(.denied), .denied)
        XCTAssertEqual(RemindersPermission.map(.writeOnly), .writeOnly)
        XCTAssertEqual(RemindersPermission.map(.fullAccess), .fullAccess)
    }

    func testStoreMapsInsufficientPermissionToStableErrors() {
        let cases: [(ReminderAccessStatus, ReminderError)] = [
            (.notDetermined, .permissionRequired),
            (.denied, .permissionDenied),
            (.restricted, .permissionRestricted),
            (.writeOnly, .fullAccessRequired)
        ]

        for (status, expected) in cases {
            let store = RemindersStore(eventStore: EKEventStore(), permission: PermissionStub(status: status))
            XCTAssertThrowsError(try store.sourceDescriptions()) { error in
                XCTAssertEqual(error as? ReminderError, expected)
            }
        }
    }

    func testSourceSelectorChoosesOnlyUniqueICloudSource() throws {
        let sources = [
            ReminderSourceDescriptor(title: "Local", identifier: "local", type: "local", isICloud: false),
            ReminderSourceDescriptor(title: "iCloud", identifier: "icloud", type: "calDAV", isICloud: true)
        ]

        XCTAssertEqual(try ReminderSourceSelector.select(sources).identifier, "icloud")
        XCTAssertEqual(try ReminderSourceSelector.select(sources, selector: "iCloud").identifier, "icloud")
        XCTAssertThrowsError(try ReminderSourceSelector.select([], selector: nil)) { error in
            XCTAssertEqual(error as? ReminderError, .icloudSourceNotFound)
        }
        XCTAssertThrowsError(try ReminderSourceSelector.select(Array(sources.dropFirst()) + [sources[1]])) { error in
            XCTAssertEqual(error as? ReminderError, .ambiguousSource(2))
        }
    }

    func testListSelectorUsesPreferredThenSoleWritableAndOtherwiseFailsClosed() throws {
        let personal = ReminderListDescriptor(
            title: "Personal", identifier: "personal", sourceIdentifier: "icloud",
            type: "calDAV", allowsContentModifications: true
        )
        let work = ReminderListDescriptor(
            title: "Work", identifier: "work", sourceIdentifier: "icloud",
            type: "calDAV", allowsContentModifications: true
        )
        let readOnly = ReminderListDescriptor(
            title: "Shared", identifier: "shared", sourceIdentifier: "icloud",
            type: "calDAV", allowsContentModifications: false
        )

        XCTAssertEqual(try ReminderListSelector.selectForWrite([personal, work], preferredIdentifier: "work"), work)
        XCTAssertEqual(try ReminderListSelector.selectForWrite([personal, readOnly]), personal)
        XCTAssertThrowsError(try ReminderListSelector.selectForWrite([personal, work])) { error in
            XCTAssertEqual(error as? ReminderError, .ambiguousList(2))
        }
        XCTAssertThrowsError(try ReminderListSelector.selectForWrite([readOnly], selector: "shared")) { error in
            XCTAssertEqual(error as? ReminderError, .listReadOnly("Shared"))
        }
    }

    func testSourceAndListResultsEncodeWithoutAccountSecrets() throws {
        let source = ReminderSourceDescriptor(title: "iCloud", identifier: "opaque-source", type: "calDAV", isICloud: true)
        let list = ReminderListDescriptor(
            title: "Personal", identifier: "opaque-list", sourceIdentifier: source.identifier,
            type: "calDAV", allowsContentModifications: true
        )
        let data = try JSONEncoder().encode(ReminderListResult(lists: [list], selectedSourceID: source.identifier))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("opaque-list"))
        XCTAssertFalse(json.contains("appleID"))
        XCTAssertFalse(json.contains("email"))
    }

    func testReminderExitAndErrorCodesAreStable() {
        XCTAssertEqual(CLIExitCode.remindersFailure.rawValue, 6)
        XCTAssertEqual(CLIErrorCode.reminders.rawValue, "REMINDERS_ERROR")
        XCTAssertEqual(ReminderError.permissionRequired.machineCode, "REMINDERS_PERMISSION_REQUIRED")
        XCTAssertEqual(ReminderError.ambiguousList(2).machineCode, "REMINDERS_LIST_AMBIGUOUS")
    }

    func testDateComponentsPreserveDateOnlyAndFloatingTimedValues() throws {
        let dateOnly = try ReminderDateValue(components: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 8, day: 17))
        XCTAssertEqual(dateOnly.value, "2026-08-17")
        XCTAssertFalse(dateOnly.hasTime)
        XCTAssertTrue(dateOnly.floating)
        XCTAssertNil(dateOnly.timeZone)

        let floating = try ReminderDateValue(components: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 8, day: 17, hour: 9, minute: 30))
        XCTAssertEqual(floating.value, "2026-08-17T09:30:00")
        XCTAssertTrue(floating.hasTime)
        XCTAssertTrue(floating.floating)
        XCTAssertNil(floating.timeZone)
    }

    func testDateComponentsPreserveTimedIANAZone() throws {
        var components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "Asia/Tokyo"), year: 2026, month: 8, day: 17, hour: 9, minute: 30)
        components.second = 0
        let value = try ReminderDateValue(components: components)

        XCTAssertEqual(value.value, "2026-08-17T09:30:00+09:00")
        XCTAssertEqual(value.timeZone, "Asia/Tokyo")
        XCTAssertFalse(value.floating)
    }

    func testOpaqueIDRoundTripsLocalAndServerIdentifiers() throws {
        let encoded = ReminderOpaqueID.encode(localIdentifier: "local-1", externalIdentifier: "server-1")
        XCTAssertTrue(encoded.hasPrefix("reminder_"))
        XCTAssertEqual(
            try ReminderOpaqueID.decode(encoded),
            ReminderLocator(localIdentifier: "local-1", externalIdentifier: "server-1")
        )
        XCTAssertThrowsError(try ReminderOpaqueID.decode("local-1"))
    }

    func testMapperPreservesBasicReadOnlyReminderFields() throws {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Prepare report"
        reminder.notes = "Draft only"
        reminder.url = URL(string: "https://example.com/task")
        reminder.priority = 1
        reminder.dueDateComponents = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 8, day: 17)

        let payload = try ReminderMapper().map(reminder, listID: "list-1", listTitle: "Personal", id: "reminder_test")
        XCTAssertEqual(payload.title, "Prepare report")
        XCTAssertEqual(payload.notes, "Draft only")
        XCTAssertEqual(payload.url, "https://example.com/task")
        XCTAssertEqual(payload.priority, .high)
        XCTAssertEqual(payload.due?.value, "2026-08-17")
        XCTAssertFalse(payload.completed)
    }

    func testQueryOrdersIncompleteDueFirstThenCompletedAndPaginates() throws {
        let dueEarly = ReminderDateValue(value: "2026-08-17", timeZone: nil, hasTime: false, floating: true)
        let dueLate = ReminderDateValue(value: "2026-08-18", timeZone: nil, hasTime: false, floating: true)
        let values = [
            ReminderPayload(id: "completed", listID: "list", listTitle: "Personal", title: "Done", completed: true, completionDate: Date(timeIntervalSince1970: 10)),
            ReminderPayload(id: "undated", listID: "list", listTitle: "Personal", title: "No due"),
            ReminderPayload(id: "late", listID: "list", listTitle: "Personal", title: "Late", due: dueLate),
            ReminderPayload(id: "early", listID: "list", listTitle: "Personal", title: "Early", due: dueEarly)
        ]

        let sorted = ReminderOrdering.sorted(values)
        XCTAssertEqual(sorted.map(\.id), ["early", "late", "undated", "completed"])
        let page = try Pagination.page(items: sorted, limit: 2, prefix: "rempage_")
        XCTAssertEqual(page.items.map(\.id), ["early", "late"])
        XCTAssertNotNil(page.nextCursor)
    }

    func testQueryValidatesStatusLimitAndDueRange() {
        XCTAssertThrowsError(try ReminderQuery(status: .incomplete, dueStart: Date(timeIntervalSince1970: 2), dueEnd: Date(timeIntervalSince1970: 1))) { error in
            XCTAssertEqual(error as? ReminderError, .invalidDateRange)
        }
        XCTAssertThrowsError(try ReminderQuery(status: .all, limit: 201)) { error in
            XCTAssertEqual(error as? ReminderError, .invalidLimit)
        }
    }

    func testCoreMatcherAppliesStatusTitleAndDueRange() throws {
        let due = ReminderDateValue(value: "2026-08-17T09:00:00+09:00", timeZone: "Asia/Tokyo", hasTime: true, floating: false)
        let payload = ReminderPayload(id: "one", listID: "list", listTitle: "Personal", title: "Prepare Report", due: due)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-17T08:00:00+09:00"))
        let end = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-17T10:00:00+09:00"))

        XCTAssertTrue(ReminderQueryMatcher.matches(payload, query: try ReminderQuery(status: .incomplete, dueStart: start, dueEnd: end, title: "report")))
        XCTAssertFalse(ReminderQueryMatcher.matches(payload, query: try ReminderQuery(status: .completed)))
        XCTAssertFalse(ReminderQueryMatcher.matches(payload, query: try ReminderQuery(status: .incomplete, title: "invoice")))
    }

    func testResourceMapperPublishesSelectedICloudReminderSource() {
        let source = ReminderSourceDescriptor(title: "iCloud", identifier: "source-1", type: "calDAV", isICloud: true)
        let resource = RemindersResourceMapper.map(source, selected: true, permission: .available)

        XCTAssertEqual(resource.kind, .remindersSource)
        XCTAssertEqual(resource.provider, .iCloud)
        XCTAssertTrue(resource.capabilities.readable)
        XCTAssertTrue(resource.capabilities.writable)
        XCTAssertTrue(resource.capabilities.selected)
    }

    func testPaginationCursorIsBoundToQueryListSetAndLastItemAnchor() throws {
        let values = (1...3).map {
            ReminderPayload(id: "id-\($0)", listID: "private-list", listTitle: "Private", title: "Secret \($0)")
        }
        let query = try ReminderQuery(status: .incomplete, listID: "private-list", title: "Secret", limit: 2)
        let first = try ReminderPagination.page(items: values, query: query, selectedListIDs: ["private-list"])
        let cursor = try XCTUnwrap(first.nextCursor)

        XCTAssertFalse(cursor.contains("Secret"))
        XCTAssertFalse(cursor.contains("private-list"))
        let secondQuery = try ReminderQuery(status: .incomplete, listID: "private-list", title: "Secret", limit: 2, cursor: cursor)
        XCTAssertEqual(try ReminderPagination.page(items: values, query: secondQuery, selectedListIDs: ["private-list"]).items.map(\.id), ["id-3"])

        let insertedBeforeAnchor = [
            ReminderPayload(id: "id-0", listID: "private-list", listTitle: "Private", title: "Secret 0")
        ] + values
        XCTAssertEqual(
            try ReminderPagination.page(items: insertedBeforeAnchor, query: secondQuery, selectedListIDs: ["private-list"]).items.map(\.id),
            ["id-3"]
        )

        let changed = try ReminderQuery(status: .completed, listID: "private-list", title: "Secret", limit: 2, cursor: cursor)
        XCTAssertThrowsError(try ReminderPagination.page(items: values, query: changed, selectedListIDs: ["private-list"]))
        XCTAssertThrowsError(try ReminderPagination.page(items: values, query: secondQuery, selectedListIDs: ["another-list"]))
        XCTAssertThrowsError(try ReminderPagination.page(items: [values[0], values[2]], query: secondQuery, selectedListIDs: ["private-list"]))
    }

    func testFetchPolicyRejectsOversizedReminderScans() {
        XCTAssertNoThrow(try ReminderFetchPolicy(maximumItems: 2).validate(itemCount: 2))
        XCTAssertThrowsError(try ReminderFetchPolicy(maximumItems: 2).validate(itemCount: 3)) { error in
            XCTAssertEqual(error as? ReminderError, .scanLimitExceeded(2))
        }
    }

    func testOrderingUsesChronologicalInstantsInsteadOfISO8601LexicalOrder() {
        let earlierInstant = ReminderDateValue(
            value: "2026-08-17T00:30:00+09:00", timeZone: "Asia/Tokyo", hasTime: true, floating: false
        )
        let laterInstant = ReminderDateValue(
            value: "2026-08-16T23:00:00+00:00", timeZone: "UTC", hasTime: true, floating: false
        )
        let values = [
            ReminderPayload(id: "later", listID: "list", listTitle: "List", title: "Later", due: laterInstant),
            ReminderPayload(id: "earlier", listID: "list", listTitle: "List", title: "Earlier", due: earlierInstant)
        ]

        XCTAssertEqual(ReminderOrdering.sorted(values).map(\.id), ["earlier", "later"])
    }

    func testFetchCoordinatorTimesOutAndCancelsEventKitRequest() async {
        let stub = FetchStub()
        let coordinator = ReminderFetchCoordinator(requester: stub, timeoutSeconds: 0.01)

        do {
            _ = try await coordinator.fetch(matching: NSPredicate(value: true))
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? ReminderError, .queryTimedOut)
        }
        XCTAssertEqual(stub.cancelCount, 1)
    }

    func testFetchCoordinatorPropagatesTaskCancellation() async {
        let stub = FetchStub()
        let coordinator = ReminderFetchCoordinator(requester: stub, timeoutSeconds: 10)
        let task = Task { () -> ReminderError? in
            do {
                _ = try await coordinator.fetch(matching: NSPredicate(value: true))
                return nil
            } catch {
                return error as? ReminderError
            }
        }
        while !stub.isStarted { await Task.yield() }
        task.cancel()

        let cancellationError = await task.value
        XCTAssertEqual(cancellationError, .queryCancelled)
        XCTAssertEqual(stub.cancelCount, 1)
    }

    func testFetchCoordinatorCompletesOnceWithoutLateTimeoutCancellation() async throws {
        let stub = FetchStub()
        let coordinator = ReminderFetchCoordinator(requester: stub, timeoutSeconds: 0.02)
        let task = Task { try await coordinator.fetch(matching: NSPredicate(value: true)).count }
        while !stub.isStarted { await Task.yield() }
        stub.complete(with: [])

        let count = try await task.value
        XCTAssertEqual(count, 0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(stub.cancelCount, 0)
    }

    func testMapperReadsRelativeAbsoluteAndLocationAlarmsAndRecurrence() throws {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Recurring reminder"
        reminder.addAlarm(EKAlarm(relativeOffset: -600))
        reminder.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: 100)))
        let location = EKStructuredLocation(title: "Office")
        let locationAlarm = EKAlarm()
        locationAlarm.structuredLocation = location
        locationAlarm.proximity = .enter
        reminder.addAlarm(locationAlarm)
        reminder.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 2,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: EKRecurrenceEnd(occurrenceCount: 3)
        ))

        let payload = try ReminderMapper().map(reminder, listID: "list", listTitle: "Personal", id: "reminder_test")
        XCTAssertEqual(payload.alarms.count, 3)
        XCTAssertTrue(payload.alarms.contains { $0.relativeMinutes == -10 })
        XCTAssertTrue(payload.alarms.contains { $0.absoluteDate == Date(timeIntervalSince1970: 100) })
        let mappedLocation = try XCTUnwrap(payload.alarms.compactMap(\.location).first)
        XCTAssertEqual(mappedLocation.title, "Office")
        XCTAssertEqual(mappedLocation.proximity, .enter)
        XCTAssertEqual(payload.recurrenceRules.first?.frequency, .weekly)
        XCTAssertEqual(payload.recurrenceRules.first?.interval, 2)
        XCTAssertEqual(payload.recurrenceRules.first?.end?.occurrenceCount, 3)
    }

    func testCreateInputDecodesMinimalJSONWithStableDefaults() throws {
        let input = try JSONDecoder().decode(ReminderInput.self, from: Data(#"{"title":"Buy milk"}"#.utf8))

        XCTAssertEqual(input.title, "Buy milk")
        XCTAssertEqual(input.priority, .none)
        XCTAssertNil(input.listID)
        XCTAssertTrue(input.alarms.isEmpty)
        XCTAssertTrue(input.recurrenceRules.isEmpty)
        XCTAssertNoThrow(try input.validated())
    }

    func testCreateInputRejectsEmptyTitleInvalidDateAndLocationAlarm() throws {
        XCTAssertThrowsError(try ReminderInput(title: "   ").validated())

        let inconsistentDate = ReminderDateValue(
            value: "2026-08-17", timeZone: "Asia/Tokyo", hasTime: false, floating: true
        )
        XCTAssertThrowsError(try ReminderInput(title: "Date", due: inconsistentDate).validated())

        let location = ReminderAlarmLocation(title: "Office", proximity: .enter)
        XCTAssertThrowsError(try ReminderInput(title: "Location", alarms: [ReminderAlarm(location: location)]).validated()) { error in
            XCTAssertEqual(error as? ReminderError, .unsupportedField("location alarm"))
        }
    }

    func testCreateInputRejectsAlarmWithMultipleTriggers() {
        let alarm = ReminderAlarm(relativeMinutes: -10, absoluteDate: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try ReminderInput(title: "Alarm", alarms: [alarm]).validated())
    }

    func testCreateInputRejectsUnknownFieldsAndInvalidRecurrenceValues() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ReminderInput.self,
            from: Data(#"{"title":"Task","titel":"typo"}"#.utf8)
        ))

        let recurrence = CalendarRecurrenceRule(frequency: .monthly, daysOfMonth: [32])
        XCTAssertThrowsError(try ReminderInput(title: "Task", recurrenceRules: [recurrence]).validated())
    }

    func testMapperBuildsUnsavedDraftWithoutFabricatingOpaqueID() throws {
        let eventStore = EKEventStore()
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = "Personal"
        let due = ReminderDateValue(value: "2026-08-17", timeZone: nil, hasTime: false, floating: true)
        let input = ReminderInput(
            listID: "list-1",
            title: "Prepare report",
            notes: "Draft",
            url: "https://example.com/task",
            priority: .high,
            due: due,
            alarms: [ReminderAlarm(relativeMinutes: -10)]
        )

        let reminder = try ReminderMapper().makeReminder(from: input, eventStore: eventStore, calendar: calendar)
        let draft = try ReminderMapper().mapDraft(reminder, listID: "list-1", listTitle: "Personal")
        XCTAssertEqual(draft.title, "Prepare report")
        XCTAssertEqual(draft.listID, "list-1")
        XCTAssertEqual(draft.priority, .high)
        XCTAssertEqual(draft.due, due)
        XCTAssertEqual(draft.alarms.first?.relativeMinutes, -10)

        let encoded = try JSONEncoder().encode(draft)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("reminder_preview"))
        XCTAssertFalse(json.contains("\"id\""))
    }

    func testIdempotencyReceiptIsPrivateExpiresAndStoresNoReminderContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let createdAt = Date(timeIntervalSince1970: 2_000_000_000)
        let input = ReminderInput(listID: "list", title: "Private title", notes: "Private notes")
        let receipt = ReminderIdempotencyReceipt(reminderID: "reminder_opaque", listID: "list", createdAt: createdAt)
        let writer = ReminderIdempotencyStore(directory: directory, validity: 60, now: { createdAt })

        try writer.save(receipt, for: input)
        XCTAssertEqual(try writer.receipt(for: input), receipt)
        let directoryMode = (try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let fileMode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
        XCTAssertFalse(text.contains("Private title"))
        XCTAssertFalse(text.contains("Private notes"))

        let expired = ReminderIdempotencyStore(directory: directory, validity: 60, now: { createdAt.addingTimeInterval(61) })
        XCTAssertNil(try expired.receipt(for: input))
    }

    func testCreateExecutorSavesExactlyOnceAndReturnsStableIdentity() throws {
        let identity = ReminderSavedIdentity(localIdentifier: "local", externalIdentifier: "server")
        let mutation = MutationStub(result: .success(identity))
        let reminder = EKReminder(eventStore: EKEventStore())

        XCTAssertEqual(try ReminderCreateExecutor(mutation: mutation).save(reminder), identity)
        XCTAssertEqual(mutation.saveCount, 1)
    }

    func testDeleteExecutorRemovesExactlyOnce() throws {
        let mutation = MutationStub(result: .failure(ReminderError.writeFailed("unused")))
        let reminder = EKReminder(eventStore: EKEventStore())

        try ReminderDeleteExecutor(mutation: mutation).remove(reminder)

        XCTAssertEqual(mutation.removeCount, 1)
        XCTAssertEqual(mutation.saveCount, 0)
    }

    func testDeleteResultDistinguishesPreviewConfirmedAndPending() {
        let reminder = ReminderPayload(
            id: "reminder_test", listID: "list", listTitle: "List", title: "Disposable",
            notes: nil, url: nil, priority: .none, completed: false, completionDate: nil,
            start: nil, due: nil, hasAlarms: false, hasRecurrenceRules: false,
            alarms: [], recurrenceRules: []
        )

        XCTAssertEqual(ReminderDeleteResult.preview(reminder).verification, .preview)
        XCTAssertEqual(ReminderDeleteResult.confirmed(reminder).verification, .absenceConfirmed)
        XCTAssertEqual(ReminderDeleteResult.pending(reminder).verification, .removeAcceptedReadbackPending)
        XCTAssertFalse(ReminderDeleteResult.preview(reminder).deleted)
        XCTAssertTrue(ReminderDeleteResult.confirmed(reminder).deleted)
    }

    func testPatchDistinguishesOmittedNullAndReplacementValues() throws {
        let patch = try JSONDecoder().decode(
            ReminderPatch.self,
            from: Data(#"{"title":" Updated ","notes":null,"alarms":[]}"#.utf8)
        )

        XCTAssertTrue(patch.has("title"))
        XCTAssertEqual(patch.title, " Updated ")
        XCTAssertTrue(patch.has("notes"))
        XCTAssertNil(patch.notes)
        XCTAssertFalse(patch.has("url"))
        XCTAssertEqual(patch.alarms, [])
    }

    func testPatchRejectsUnknownEmptyAndReadOnlyCompletionFields() throws {
        for json in ["{}", #"{"titel":"typo"}"#, #"{"completed":true}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ReminderPatch.self, from: Data(json.utf8)))
        }
    }

    func testMapperAppliesPartialPatchWithoutClearingUnmentionedFields() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Before"
        reminder.notes = "Keep me"
        reminder.priority = 9
        let patch = try JSONDecoder().decode(
            ReminderPatch.self,
            from: Data(#"{"title":"After","priority":"high"}"#.utf8)
        )

        try ReminderMapper().apply(patch, to: reminder)

        XCTAssertEqual(reminder.title, "After")
        XCTAssertEqual(reminder.notes, "Keep me")
        XCTAssertEqual(reminder.priority, 1)
    }

    func testMapperRejectsAlarmEditWhenExistingLocationAlarmWouldBeLost() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        let locationAlarm = EKAlarm()
        locationAlarm.structuredLocation = EKStructuredLocation(title: "Office")
        reminder.addAlarm(locationAlarm)
        let patch = try JSONDecoder().decode(
            ReminderPatch.self,
            from: Data(#"{"alarms":[]}"#.utf8)
        )

        XCTAssertThrowsError(try ReminderMapper().apply(patch, to: reminder)) { error in
            XCTAssertEqual(error as? ReminderError, .unsupportedField("alarms on a reminder containing a location alarm"))
        }
    }

    func testMapperCompletesAndReopensWithExplicitCompletionDate() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        let completedAt = Date(timeIntervalSince1970: 2_000_000_000)

        ReminderMapper().applyCompletion(true, completionDate: completedAt, to: reminder)
        XCTAssertTrue(reminder.isCompleted)
        XCTAssertEqual(reminder.completionDate, completedAt)

        ReminderMapper().applyCompletion(false, completionDate: completedAt, to: reminder)
        XCTAssertFalse(reminder.isCompleted)
        XCTAssertNil(reminder.completionDate)
    }

    func testStateChangeResultsExposePreviewNoOpAndPendingStates() {
        let before = ReminderPayload(
            id: "reminder_test", listID: "list", listTitle: "List", title: "Task",
            notes: nil, url: nil, priority: .none, completed: false, completionDate: nil,
            start: nil, due: nil, hasAlarms: false, hasRecurrenceRules: false,
            alarms: [], recurrenceRules: []
        )
        let after = ReminderPayload(
            id: "reminder_test", listID: "list", listTitle: "List", title: "Task",
            notes: nil, url: nil, priority: .none, completed: true,
            completionDate: Date(timeIntervalSince1970: 2_000_000_000),
            start: nil, due: nil, hasAlarms: false, hasRecurrenceRules: false,
            alarms: [], recurrenceRules: []
        )

        let preview = ReminderStateChangePreview(action: .complete, before: before, after: after)
        XCTAssertEqual(preview.operation, "complete_preview")
        XCTAssertTrue(preview.dryRun)
        let noOp = ReminderStateChangeResult.noOp(action: .complete, reminder: after)
        XCTAssertEqual(noOp.operation, "already_completed")
        XCTAssertFalse(noOp.changed)
        let pending = ReminderStateChangeResult.pending(action: .complete, reminder: after)
        XCTAssertEqual(pending.verification, .saveAcceptedReadbackPending)
        XCTAssertTrue(pending.changed)
    }
}
