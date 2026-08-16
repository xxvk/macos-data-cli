import XCTest
@testable import Core

final class RESTCLIRequestTests: XCTestCase {
    private let manifest = CommandRegistry.standard(version: "0.9.3")

    func testParsesCaseInsensitiveMethodAndTranslatesReminderPatch() throws {
        let request = try RESTCLIRequestParser.parse([
            "patch", "/reminders/edit",
            "--params", #"{"id":"reminder_123"}"#,
            "--body", #"{"title":"updated"}"#,
            "--apply",
        ], manifest: manifest)

        XCTAssertEqual(request.route.method, .patch)
        XCTAssertTrue(request.diagnosticSummary.contains("route=PATCH /reminders/edit"))
        XCTAssertFalse(request.diagnosticSummary.contains("reminder_123"))
        XCTAssertFalse(request.diagnosticSummary.contains("updated"))
        XCTAssertEqual(request.internalArguments, [
            "reminders", "edit", "--id", "reminder_123",
            "--inline-json", #"{"title":"updated"}"#, "--apply",
        ])
    }

    func testRejectsLegacySyntaxWithStableMigrationCode() {
        XCTAssertThrowsError(try RESTCLIRequestParser.parse(["reminders", "edit"], manifest: manifest)) { error in
            guard case RESTCLIError.legacySyntaxRemoved(let action) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertTrue(action.contains("PATCH /reminders/edit"))
            XCTAssertEqual((error as? RESTCLIError)?.machineCode, "LEGACY_SYNTAX_REMOVED")
        }
    }

    func testRejectsUnknownRouteAndMethodMismatch() {
        XCTAssertThrowsError(try RESTCLIRequestParser.parse(["GET", "/missing"], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse(["POST", "/reminders/edit"], manifest: manifest)) { error in
            XCTAssertEqual((error as? RESTCLIError)?.machineCode, "METHOD_NOT_ALLOWED")
        }
    }

    func testRejectsInvalidPaths() {
        for path in ["reminders/edit", "/reminders/edit/", "/reminders/edit?q=x", "//reminders/edit"] {
            XCTAssertThrowsError(try RESTCLIRequestParser.parse(["PATCH", path], manifest: manifest), path)
        }
    }

    func testRejectsUnknownWrongTypeAndMissingParams() {
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "GET", "/contacts/get", "--params", #"{"external-id":12}"#,
        ], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "GET", "/contacts/get", "--params", #"{"unknown":"x"}"#,
        ], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse(["GET", "/contacts/get"], manifest: manifest))
    }

    func testRejectsDuplicateJSONKeysRecursively() {
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "POST", "/reminders/create", "--body", #"{"title":"a","nested":{"x":1,"x":2}}"#, "--dry-run",
        ], manifest: manifest)) { error in
            XCTAssertEqual(error as? RESTCLIError, .duplicateJSONKey("x"))
        }
    }

    func testRejectsBodyOnReadRouteAndMissingBodyOnWriteRoute() {
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "GET", "/contacts/get", "--params", #"{"external-id":"x"}"#, "--body", "{}",
        ], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "POST", "/reminders/create", "--dry-run",
        ], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "POST", "/reminders/create", "--body", #"{"title":"x"}"#,
        ], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "POST", "/reminders/create", "--body", #"{"title":"x","due":{"value":"2026-08-17","unknown":true}}"#, "--dry-run",
        ], manifest: manifest))
    }

    func testRejectsSafetyFlagsForReadOnlyRoute() {
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "GET", "/contacts/get", "--params", #"{"external-id":"x"}"#, "--apply",
        ], manifest: manifest))
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "POST", "/reminders/create", "--body", #"{"title":"x"}"#, "--dry-run", "--apply",
        ], manifest: manifest))
    }

    func testEnforcesInlineJSONLimits() {
        let oversized = String(repeating: "x", count: RESTCLIRequest.maximumParamsBytes + 1)
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "GET", "/contacts/get", "--params", oversized,
        ], manifest: manifest))
        let oversizedBody = #"{"title":""# + String(repeating: "x", count: RESTCLIRequest.maximumBodyBytes) + #""}"#
        XCTAssertThrowsError(try RESTCLIRequestParser.parse([
            "POST", "/reminders/create", "--body", oversizedBody, "--dry-run",
        ], manifest: manifest))
    }
}
