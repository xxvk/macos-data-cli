import XCTest
@testable import Core

final class ContactPayloadTests: XCTestCase {
    func testPayloadRoundTripsThroughJSON() throws {
        let payload = ContactPayload(
            externalID: "org_12345",
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
}
