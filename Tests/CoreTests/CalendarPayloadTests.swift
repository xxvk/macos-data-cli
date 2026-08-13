import Foundation
import XCTest
@testable import Core

final class CalendarPayloadTests: XCTestCase {
    func testAllDayInputUsesDateOnlyContractAcrossTimeZones() throws {
        let json = #"{"title":"All day","allDay":true,"startDate":"2026-11-01","endDate":"2026-11-02","timeZone":"America/Los_Angeles"}"#
        let input = try CalendarJSON.decode(CalendarEventInput.self, from: Data(json.utf8))

        XCTAssertTrue(input.allDay)
        XCTAssertTrue(input.usesDateOnlyValues)
        XCTAssertEqual(CalendarJSON.dateOnlyString(input.startDate, timeZone: "America/Los_Angeles"), "2026-11-01")
        XCTAssertEqual(CalendarJSON.dateOnlyString(input.endDate, timeZone: "America/Los_Angeles"), "2026-11-02")
    }

    func testAllDayPayloadEncodesDateOnlyAcrossDSTBoundary() throws {
        let start = try CalendarJSON.parseDateOnly("2026-11-01", timeZone: "America/Los_Angeles")
        let end = try CalendarJSON.parseDateOnly("2026-11-02", timeZone: "America/Los_Angeles")
        let payload = CalendarEventPayload(title: "DST", startDate: start, endDate: end, allDay: true, timeZone: "America/Los_Angeles")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String: Any]

        XCTAssertEqual(object?["startDate"] as? String, "2026-11-01")
        XCTAssertEqual(object?["endDate"] as? String, "2026-11-02")
    }

    func testAllDayDateOnlyRoundTripsInTokyoAndUTC() throws {
        for zone in ["Asia/Tokyo", "UTC"] {
            let start = try CalendarJSON.parseDateOnly("2026-08-16", timeZone: zone)
            let end = try CalendarJSON.parseDateOnly("2026-08-18", timeZone: zone)
            XCTAssertEqual(CalendarJSON.dateOnlyString(start, timeZone: zone), "2026-08-16")
            XCTAssertEqual(CalendarJSON.dateOnlyString(end, timeZone: zone), "2026-08-18")
        }
    }

    func testAllDayDateOnlyRoundTripsAcrossDSTStartAndEnd() throws {
        for dates in [("2026-03-08", "2026-03-09"), ("2026-11-01", "2026-11-02")] {
            let start = try CalendarJSON.parseDateOnly(dates.0, timeZone: "America/Los_Angeles")
            let end = try CalendarJSON.parseDateOnly(dates.1, timeZone: "America/Los_Angeles")
            XCTAssertEqual(CalendarJSON.dateOnlyString(start, timeZone: "America/Los_Angeles"), dates.0)
            XCTAssertEqual(CalendarJSON.dateOnlyString(end, timeZone: "America/Los_Angeles"), dates.1)
        }
    }

    func testAllDayInputRejectsTimestampsAndTimedInputRejectsDateOnly() {
        XCTAssertThrowsError(try CalendarJSON.decode(CalendarEventInput.self, from: Data(#"{"title":"bad","allDay":true,"startDate":"2026-08-16T00:00:00Z","endDate":"2026-08-17T00:00:00Z"}"#.utf8)))
        XCTAssertThrowsError(try CalendarJSON.decode(CalendarEventInput.self, from: Data(#"{"title":"bad","startDate":"2026-08-16","endDate":"2026-08-17"}"#.utf8)))
    }

    func testAlarmContractSupportsRelativeAndAbsoluteTriggers() throws {
        let json = #"{"title":"Alerts","startDate":"2026-08-16T01:00:00Z","endDate":"2026-08-16T02:00:00Z","alarms":[{"relativeMinutes":-10},{"absoluteDate":"2026-08-15T23:00:00Z"}]}"#
        let input = try CalendarJSON.decode(CalendarEventInput.self, from: Data(json.utf8))

        XCTAssertEqual(input.alarms.first?.relativeMinutes, -10)
        XCTAssertNotNil(input.alarms.last?.absoluteDate)
    }

    func testAlarmRequiresExactlyOneTrigger() {
        XCTAssertThrowsError(try CalendarAlarm(relativeMinutes: nil, absoluteDate: nil).validated())
        XCTAssertThrowsError(try CalendarAlarm(relativeMinutes: -10, absoluteDate: Date()).validated())
        XCTAssertThrowsError(try CalendarAlarm(relativeMinutes: 525_601).validated())
        XCTAssertNoThrow(try CalendarAlarm(relativeMinutes: -525_600).validated())
    }

    func testConflictDetectorFindsStrictOverlapButNotAdjacentEvents() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            CalendarEventPayload(id: "a", title: "A", startDate: base, endDate: base.addingTimeInterval(3600)),
            CalendarEventPayload(id: "b", title: "B", startDate: base.addingTimeInterval(1800), endDate: base.addingTimeInterval(5400)),
            CalendarEventPayload(id: "c", title: "C", startDate: base.addingTimeInterval(5400), endDate: base.addingTimeInterval(7200))
        ]

        let conflicts = CalendarConflictDetector.detect(events)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.firstEventID, "a")
        XCTAssertEqual(conflicts.first?.secondEventID, "b")
    }

    func testConflictPolicyRejectsMoreThanTwoHundredCandidates() {
        XCTAssertNoThrow(try CalendarConflictDetector.validateEventCount(200))
        XCTAssertThrowsError(try CalendarConflictDetector.validateEventCount(201)) { error in
            XCTAssertEqual(error as? CalendarError, .conflictScanLimitExceeded)
        }
    }

    func testIdempotencyMatcherDistinguishesPersistedFieldsButIgnoresAlarmOrder() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let input = CalendarEventInput(
            title: "Retry",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            notes: "same",
            alarms: [CalendarAlarm(relativeMinutes: -10), CalendarAlarm(relativeMinutes: -30)]
        )
        let equivalent = CalendarEventPayload(
            title: "Retry",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            notes: "same",
            alarms: [CalendarAlarm(relativeMinutes: -30), CalendarAlarm(relativeMinutes: -10)]
        )
        let changed = CalendarEventPayload(
            title: "Retry",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            notes: "different",
            alarms: equivalent.alarms
        )

        XCTAssertTrue(CalendarIdempotencyMatcher.equivalent(input, equivalent))
        XCTAssertFalse(CalendarIdempotencyMatcher.equivalent(input, changed))
    }
    func testEventPayloadRoundTripsTimeZoneAttendeesAndRecurrence() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3_600)
        let payload = CalendarEventPayload(
            id: "event-opaque-001",
            calendarID: "calendar-opaque-001",
            calendarTitle: "Calendar",
            title: "Weekly review",
            startDate: start,
            endDate: end,
            timeZone: "Asia/Tokyo",
            location: "Tokyo",
            notes: "Agenda",
            url: "https://example.invalid/event",
            attendees: [CalendarAttendee(name: "Ada", email: "ada@example.invalid", status: "accepted", role: "required")],
            recurrenceRules: [
                CalendarRecurrenceRule(
                    frequency: .weekly,
                    interval: 1,
                    daysOfWeek: [.monday],
                    end: CalendarRecurrenceEnd(occurrenceCount: 10)
                )
            ]
        )

        let decoded = try JSONDecoder().decode(CalendarEventPayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.timeZone, "Asia/Tokyo")
        XCTAssertEqual(decoded.recurrenceRules.first?.daysOfWeek, [.monday])
    }

    func testQueryRequiresOrderedBoundedDateRange() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertNoThrow(try CalendarEventQuery(startDate: start, endDate: start.addingTimeInterval(86_400)))
        XCTAssertThrowsError(try CalendarEventQuery(startDate: start, endDate: start))
        XCTAssertThrowsError(try CalendarEventQuery(startDate: start, endDate: start.addingTimeInterval(367 * 86_400)))
    }

    func testMinimalCalendarInputAppliesStableDefaults() throws {
        let json = #"{"title":"Planning","startDate":"2026-08-16T01:00:00Z","endDate":"2026-08-16T02:00:00Z","recurrenceRules":[{"frequency":"weekly","end":{"occurrenceCount":2}}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let input = try decoder.decode(CalendarEventInput.self, from: Data(json.utf8))

        XCTAssertFalse(input.allDay)
        XCTAssertTrue(input.attendees.isEmpty)
        XCTAssertEqual(input.recurrenceRules.first?.interval, 1)
        XCTAssertEqual(input.recurrenceRules.first?.daysOfWeek, [])
        XCTAssertEqual(input.recurrenceRules.first?.weekdayOrdinals, [])
    }

    func testCalendarExitAndErrorCodesAreStable() {
        XCTAssertEqual(CLIExitCode.calendarFailure.rawValue, 5)
        XCTAssertEqual(CLIErrorCode.calendar.rawValue, "CALENDAR_ERROR")
    }

    func testCalendarErrorsDoNotEchoPrivateSelectorsIntoDiagnostics() {
        let privateCalendar = "Private Project Calendar"
        let privateSource = "private@example.invalid"

        XCTAssertFalse(CalendarError.calendarNotFound(privateCalendar).description.contains(privateCalendar))
        XCTAssertFalse(CalendarError.sourceNotFound(privateSource).description.contains(privateSource))
        XCTAssertFalse(CalendarError.eventNotFound("calevent_private").description.contains("calevent_private"))
    }
}
