import EventKit
import XCTest
@testable import CalendarAdapter
@testable import Core

final class CalendarAdapterTests: XCTestCase {
    func testIdempotencyReceiptStoresNoPrivateEventFieldsAndExpires() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = CalendarIdempotencyStore(directory: directory, validity: 60, now: { now })
        let input = CalendarEventInput(title: "Private title", startDate: now, endDate: now.addingTimeInterval(3600), notes: "Private notes")
        let receipt = CalendarIdempotencyReceipt(eventID: "opaque", calendarID: "calendar", createdAt: now)

        try store.save(receipt, for: input)
        XCTAssertEqual(try store.receipt(for: input), receipt)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertFalse(text.contains("Private title"))
        XCTAssertFalse(text.contains("Private notes"))
        store.invalidate(eventID: "opaque")
        XCTAssertNil(try store.receipt(for: input))
    }
    func testMapperReadsAndWritesRelativeAndAbsoluteAlarms() throws {
        let store = EKEventStore()
        let absolute = Date(timeIntervalSince1970: 1_799_999_000)
        let input = CalendarEventInput(
            title: "Alerts",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            alarms: [CalendarAlarm(relativeMinutes: -10), CalendarAlarm(absoluteDate: absolute)]
        )

        let event = try CalendarMapper().makeEvent(from: input, eventStore: store)
        let mapped = CalendarMapper().map(event)

        XCTAssertTrue(event.alarms?.contains(where: { $0.relativeOffset == -600 }) == true)
        XCTAssertTrue(mapped.alarms.contains(CalendarAlarm(relativeMinutes: -10)))
        XCTAssertTrue(mapped.alarms.contains(CalendarAlarm(absoluteDate: absolute)))
    }

    func testMapperCanClearAlarmsWithPatch() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Alerts"
        event.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        event.endDate = Date(timeIntervalSince1970: 1_800_003_600)
        event.addAlarm(EKAlarm(relativeOffset: -600))
        let patch = try CalendarJSON.decode(CalendarEventPatch.self, from: Data(#"{"alarms":[]}"#.utf8))

        try CalendarMapper().apply(patch, to: event)

        XCTAssertEqual(event.alarms?.count ?? 0, 0)
    }

    func testMapperRequiresBothDateOnlyValuesWhenChangingToAllDay() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Timed"
        event.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        event.endDate = Date(timeIntervalSince1970: 1_800_003_600)
        let patch = try CalendarJSON.decode(CalendarEventPatch.self, from: Data(#"{"allDay":true}"#.utf8))

        XCTAssertThrowsError(try CalendarMapper().apply(patch, to: event))
    }

    func testMapperAcceptsDateOnlyPatchForExistingAllDayEventWithoutRepeatedFlag() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "All day"
        event.isAllDay = true
        event.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        event.endDate = Date(timeIntervalSince1970: 1_800_086_400)
        let patch = try CalendarJSON.decode(CalendarEventPatch.self, from: Data(#"{"endDate":"2027-01-18"}"#.utf8))

        XCTAssertNoThrow(try CalendarMapper().apply(patch, to: event))
        XCTAssertTrue(event.isAllDay)
    }
    func testOpaqueEventIDDistinguishesRecurringOccurrencesAndRoundTrips() throws {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = first.addingTimeInterval(7 * 86_400)

        let firstID = CalendarOpaqueID.encode(calendarItemIdentifier: "series-001", occurrenceStart: first)
        let secondID = CalendarOpaqueID.encode(calendarItemIdentifier: "series-001", occurrenceStart: second)

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertTrue(firstID.hasPrefix("calevent_"))
        XCTAssertEqual(try CalendarOpaqueID.decode(firstID), CalendarEventLocator(calendarItemIdentifier: "series-001", occurrenceStart: first))
        XCTAssertThrowsError(try CalendarOpaqueID.decode("series-001"))
    }

    func testPermissionMapperRequiresFullAccessForReads() {
        XCTAssertEqual(CalendarPermission.map(.fullAccess), .fullAccess)
        XCTAssertEqual(CalendarPermission.map(.writeOnly), .writeOnly)
        XCTAssertEqual(CalendarPermission.map(.denied), .denied)
    }

    func testSourceSelectorChoosesUniqueICloudCalDAVSource() throws {
        let sources = [
            CalendarSourceDescriptor(title: "Other", identifier: "local", type: "local", isICloud: false),
            CalendarSourceDescriptor(title: "iCloud", identifier: "icloud", type: "calDAV", isICloud: true)
        ]

        XCTAssertEqual(try CalendarSourceSelector.select(sources).identifier, "icloud")
        XCTAssertEqual(try CalendarSourceSelector.select(sources, selector: "icloud").identifier, "icloud")
    }

    func testSourceSelectorFailsClosedWhenICloudIsMissingOrAmbiguous() {
        XCTAssertThrowsError(try CalendarSourceSelector.select([])) { error in
            XCTAssertEqual(error as? CalendarError, .icloudSourceNotFound)
        }

        let duplicate = [
            CalendarSourceDescriptor(title: "iCloud", identifier: "one", type: "calDAV", isICloud: true),
            CalendarSourceDescriptor(title: "iCloud", identifier: "two", type: "calDAV", isICloud: true)
        ]
        XCTAssertThrowsError(try CalendarSourceSelector.select(duplicate)) { error in
            XCTAssertEqual(error as? CalendarError, .ambiguousSource(2))
        }
    }

    func testResourceMapperPreservesICloudSelectionAndPermission() {
        let source = CalendarSourceDescriptor(title: "iCloud", identifier: "icloud", type: "calDAV", isICloud: true)
        let resource = CalendarResourceMapper.map(source, selected: true, permission: .available)

        XCTAssertEqual(resource.kind, .calendarSource)
        XCTAssertEqual(resource.provider, .iCloud)
        XCTAssertTrue(resource.capabilities.readable)
        XCTAssertTrue(resource.capabilities.writable)
        XCTAssertTrue(resource.capabilities.selected)
    }

    func testCalendarSelectorUsesExplicitIdentifierAndFailsOnAmbiguousDefault() throws {
        let calendars = [
            CalendarDescriptor(title: "Personal", identifier: "personal", sourceIdentifier: "icloud", type: "calDAV", allowsContentModifications: true),
            CalendarDescriptor(title: "Work", identifier: "work", sourceIdentifier: "icloud", type: "calDAV", allowsContentModifications: true)
        ]

        XCTAssertEqual(try CalendarSelector.selectForWrite(calendars, selector: "work").identifier, "work")
        XCTAssertThrowsError(try CalendarSelector.selectForWrite(calendars)) { error in
            XCTAssertEqual(error as? CalendarError, .ambiguousCalendar(2))
        }
    }

    func testMapperReadsTimeZoneAttendeesAndWeeklyRecurrence() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Weekly review"
        event.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        event.endDate = event.startDate.addingTimeInterval(3_600)
        event.timeZone = TimeZone(identifier: "Asia/Tokyo")
        event.location = "Tokyo"
        event.notes = "Agenda"
        event.url = URL(string: "https://example.invalid/event")
        event.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: EKRecurrenceEnd(occurrenceCount: 10)
        ))

        let payload = CalendarMapper().map(event)

        XCTAssertEqual(payload.title, "Weekly review")
        XCTAssertEqual(payload.timeZone, "Asia/Tokyo")
        XCTAssertEqual(payload.location, "Tokyo")
        XCTAssertEqual(payload.recurrenceRules.first?.frequency, .weekly)
        XCTAssertEqual(payload.recurrenceRules.first?.daysOfWeek, [.monday])
        XCTAssertEqual(payload.recurrenceRules.first?.end?.occurrenceCount, 10)
    }

    func testMapperBuildsValidatedEventInput() throws {
        let store = EKEventStore()
        let input = CalendarEventInput(
            calendarID: "calendar-001",
            title: "Planning",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            timeZone: "Asia/Tokyo",
            recurrenceRules: [CalendarRecurrenceRule(frequency: .daily, interval: 2)]
        )

        let event = try CalendarMapper().makeEvent(from: input, eventStore: store)

        XCTAssertEqual(event.title, "Planning")
        XCTAssertEqual(event.timeZone?.identifier, "Asia/Tokyo")
        XCTAssertEqual(event.recurrenceRules?.first?.frequency, .daily)
        XCTAssertEqual(event.recurrenceRules?.first?.interval, 2)
    }

    func testMapperPreservesOrdinalWeekdayRecurrence() throws {
        let store = EKEventStore()
        let input = CalendarEventInput(
            title: "Monthly review",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            recurrenceRules: [
                CalendarRecurrenceRule(
                    frequency: .monthly,
                    weekdayOrdinals: [CalendarRecurrenceWeekday(weekday: .monday, weekNumber: 2)]
                )
            ]
        )

        let event = try CalendarMapper().makeEvent(from: input, eventStore: store)
        let mapped = CalendarMapper().map(event)

        XCTAssertEqual(mapped.recurrenceRules.first?.weekdayOrdinals, [CalendarRecurrenceWeekday(weekday: .monday, weekNumber: 2)])
        XCTAssertTrue(mapped.recurrenceRules.first?.daysOfWeek.isEmpty == true)
    }
}
