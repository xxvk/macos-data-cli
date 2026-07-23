import XCTest
@testable import Core

final class ContactPayloadTests: XCTestCase {
    func testAvatarWriteVerificationUsesStableMachineReadableStatuses() throws {
        let value = AvatarWriteVerification(status: .verificationUnknown, saveAccepted: true, requestedBytes: 120, nextAction: "retry_verification_after_iCloud_sync_or_recreate_after_confirmation")
        let data = try JSONEncoder().encode(value)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("verification_unknown"))
        XCTAssertTrue(json.contains("recreate_after_confirmation"))
        XCTAssertEqual(try JSONDecoder().decode(AvatarWriteVerification.self, from: data), value)

        let unavailable = AvatarWriteVerification(status: .notAvailable, saveAccepted: false, requestedBytes: 0)
        XCTAssertEqual(try JSONDecoder().decode(AvatarWriteVerification.self, from: JSONEncoder().encode(unavailable)), unavailable)
        XCTAssertEqual(ContactsError.avatarReplacementConfirmationRequired.description, "Avatar replacement requires --confirm \"RECREATE CONTACT\".")
    }
    func testPayloadRoundTripsThroughJSON() throws {
        let payload = ContactPayload(
            externalID: "org_12345",
            phoneticGivenName: "えいぐざんぷる",
            phoneticFamilyName: "かぶしきがいしゃ",
            organizationName: "Example Inc.",
            emails: [LabeledValue(label: "work", value: "hello@example.com")],
            metadata: ["source": "example"]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ContactPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
    }

    func testDefaultPayloadHasNoOptionalData() {
        let payload = ContactPayload()

        XCTAssertNil(payload.externalID)
        XCTAssertTrue(payload.emails.isEmpty)
        XCTAssertTrue(payload.metadata.isEmpty)
    }

    func testDataResourcesResultRoundTripsAndPreservesLimitations() throws {
        let resource = DataResource(
            id: "icloud-contacts",
            kind: .contactsContainer,
            provider: .iCloud,
            displayName: "iCloud",
            capabilities: DataResourceCapabilities(
                readable: true,
                writable: true,
                selected: true,
                permission: .available
            )
        )
        let result = DataResourcesResult(
            resources: [resource],
            limitations: ["calendar_adapter_not_implemented"]
        )

        let decoded = try JSONDecoder().decode(
            DataResourcesResult.self,
            from: JSONEncoder().encode(result)
        )

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.limitations, ["calendar_adapter_not_implemented"])
    }

    func testPaginationUsesOpaqueCursorAndCompletesOnLastPage() throws {
        let first = try Pagination.page(items: ["a", "b", "c"], limit: 2, prefix: "test_")
        XCTAssertEqual(first.items, ["a", "b"])
        XCTAssertTrue(first.truncated)
        XCTAssertTrue(first.complete)
        let cursor = try XCTUnwrap(first.nextCursor)
        XCTAssertTrue(cursor.hasPrefix("test_"))
        XCTAssertNotEqual(cursor, "2")

        let last = try Pagination.page(items: ["a", "b", "c"], limit: 2, cursor: cursor, prefix: "test_")
        XCTAssertEqual(last.items, ["c"])
        XCTAssertFalse(last.truncated)
        XCTAssertTrue(last.complete)
        XCTAssertNil(last.nextCursor)
    }

    func testPaginationRejectsInvalidLimitAndCursor() {
        XCTAssertThrowsError(try Pagination.page(items: ["a"], limit: 0, prefix: "test_")) { error in
            XCTAssertEqual(error as? PaginationError, .invalidLimit)
        }
        XCTAssertThrowsError(try Pagination.page(items: ["a"], limit: 1, cursor: "not-a-cursor", prefix: "test_")) { error in
            XCTAssertEqual(error as? PaginationError, .invalidCursor)
        }
    }

    func testQueryMatcherSupportsNameEmailOrganizationAndPostalCode() {
        let contact = ContactPayload(
            kind: .organization,
            givenName: "macos-data",
            familyName: "Test Contact",
            organizationName: "macos-data Test",
            emails: [LabeledValue(value: "macos-data-test@example.invalid")],
            addresses: [PostalAddress(postalCode: "100-0001")]
        )
        let matcher = ContactQueryMatcher()

        XCTAssertTrue(matcher.matches(contact, query: .name("test contact")))
        XCTAssertTrue(matcher.matches(contact, query: .email("MACOS-DATA-TEST@EXAMPLE.INVALID")))
        XCTAssertTrue(matcher.matches(contact, query: .organization("macos-data")))
        XCTAssertTrue(matcher.matches(contact, query: .postalCode("1000001")))
        XCTAssertEqual(contact.kind, .organization)
    }

    func testQuerySetUsesAndSemanticsAndLimitsThreeConditions() throws {
        let contact = ContactPayload(givenName: "Ada", organizationName: "Example", emails: [LabeledValue(value: "ada@example.com")])
        let matcher = ContactQueryMatcher()
        let query = try ContactQuerySet([.name("Ada"), .organization("Example"), .email("ada@example.com")])

        XCTAssertTrue(matcher.matches(contact, query: query))
        XCTAssertThrowsError(try ContactQuerySet([.name("Ada"), .organization("Example"), .email("ada@example.com"), .phone("123")]))
    }

    func testQueryCanFilterByContactKind() throws {
        let organization = ContactPayload(kind: .organization, organizationName: "Example")
        let person = ContactPayload(kind: .person, givenName: "Ada")
        let matcher = ContactQueryMatcher()
        let query = try ContactQuerySet([.kind(.organization)])

        XCTAssertTrue(matcher.matches(organization, query: query))
        XCTAssertFalse(matcher.matches(person, query: query))
    }

    func testIdempotentCreateComparisonIgnoresNonPersistentFields() {
        let requested = ContactPayload(
            kind: .organization,
            externalID: "org-1",
            organizationName: "Example",
            metadata: ["source": "obsidian"],
            imageAvailable: true
        )
        let existing = ContactPayload(
            kind: .organization,
            externalID: "org-1",
            organizationName: "Example"
        )

        XCTAssertTrue(requested.isEquivalentForIdempotentCreate(to: existing))
    }

    func testAmbiguousMatchRefusesToChooseAutomatically() {
        XCTAssertThrowsError(try ContactMatchResolver.requireExactlyOne(["first", "second"])) { error in
            XCTAssertEqual(error as? ContactsQueryError, .ambiguous(2))
        }
    }

    func testJSONContractHasStableVersion() {
        XCTAssertEqual(JSONContract.version, "0.1")
    }

    func testDataResourceRoundTripsWithoutPrivateAccountIdentifiers() throws {
        let resource = DataResource(
            id: "mail-account-opaque-001",
            kind: .mailAccount,
            provider: .mail,
            displayName: "aim-tech.jp work account",
            capabilities: DataResourceCapabilities(
                readable: true,
                writable: false,
                selected: true,
                permission: .available
            )
        )

        let data = try JSONEncoder().encode(resource)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("@"))
        XCTAssertFalse(json.contains("imap://"))
        XCTAssertEqual(try JSONDecoder().decode(DataResource.self, from: data), resource)
    }

    func testPagedResultRoundTripsAndPreservesCompleteness() throws {
        let page = PagedResult(
            items: ["first", "second"],
            limit: 2,
            nextCursor: "opaque-cursor-001",
            truncated: true,
            complete: false
        )

        let decoded = try JSONDecoder().decode(PagedResult<String>.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(decoded, page)
        XCTAssertTrue(decoded.truncated)
        XCTAssertFalse(decoded.complete)
    }

    func testCLIReleaseVersionIsMailAdapterRelease() {
        XCTAssertEqual(CLIVersion.current, "0.2.0")
    }

    func testCLIExitCodesAndErrorCodesAreStable() {
        XCTAssertEqual(CLIExitCode.success.rawValue, 0)
        XCTAssertEqual(CLIExitCode.genericFailure.rawValue, 1)
        XCTAssertEqual(CLIExitCode.contactsFailure.rawValue, 2)
        XCTAssertEqual(CLIExitCode.queryFailure.rawValue, 3)
        XCTAssertEqual(CLIExitCode.mailFailure.rawValue, 4)
        XCTAssertEqual(CLIExitCode.usage.rawValue, 64)
        XCTAssertEqual(CLIErrorCode.contacts.rawValue, "CONTACTS_ERROR")
        XCTAssertEqual(CLIErrorCode.query.rawValue, "CONTACT_QUERY_ERROR")
        XCTAssertEqual(CLIErrorCode.mail.rawValue, "MAIL_ERROR")
        XCTAssertEqual(CLIErrorCode.invalidQuery.rawValue, "INVALID_QUERY")
    }

    func testDiagnosticMessagesRedactContactSensitiveValues() {
        let message = "email=person@example.com phone=+81 90-1234-5678 path=/Users/mini/private/avatar.png"
        let sanitized = DiagnosticLogger.sanitize(message)

        XCTAssertFalse(sanitized.contains("person@example.com"))
        XCTAssertFalse(sanitized.contains("+81 90-1234-5678"))
        XCTAssertFalse(sanitized.contains("/Users/mini/private/avatar.png"))
        XCTAssertTrue(sanitized.contains("<redacted-email>"))
        XCTAssertTrue(sanitized.contains("<redacted-path>"))
    }

    func testDiagnosticErrorDetailsDoNotIncludeUnderlyingExceptionText() {
        let error = NSError(
            domain: "ContactsTest",
            code: 42,
            userInfo: ["NSUnderlyingException": "private contact@example.com details"]
        )

        let details = DiagnosticLogger.errorDetails(error)

        XCTAssertFalse(details.contains("private contact@example.com details"))
        XCTAssertTrue(details.contains("underlyingExceptionPresent=true"))
    }
}
