import XCTest
@testable import ContactsAdapter
@testable import Core
import Contacts

final class ContactsStoreTests: XCTestCase {
    func testStoreCanBeCreated() {
        _ = ContactsStore()
    }

    func testMapperReturnsContactFields() {
        let contact = CNMutableContact()
        contact.givenName = "Ada"
        contact.organizationName = "Example Inc."
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "ada@example.com" as NSString)]

        let payload = ContactsMapper().map(contact)

        XCTAssertEqual(payload.givenName, "Ada")
        XCTAssertEqual(payload.organizationName, "Example Inc.")
        XCTAssertEqual(payload.emails.first?.value, "ada@example.com")
    }

    func testMapperReadsAndWritesPhoneticNames() {
        let contact = CNMutableContact()
        contact.phoneticGivenName = "えいだ"
        contact.phoneticFamilyName = "てすと"

        let mapped = ContactsMapper().map(contact)
        XCTAssertEqual(mapped.phoneticGivenName, "えいだ")
        XCTAssertEqual(mapped.phoneticFamilyName, "てすと")

        let rebuilt = ContactsMapper().makeMutableContact(from: mapped)
        XCTAssertEqual(rebuilt.phoneticGivenName, "えいだ")
        XCTAssertEqual(rebuilt.phoneticFamilyName, "てすと")
    }

    func testMapperExtractsExternalIDFromReservedURL() {
        let contact = CNMutableContact()
        contact.urlAddresses = [CNLabeledValue(label: "macos-data-cli", value: "x-macos-data://external-id/xvk-test-contacts-001" as NSString)]

        let payload = ContactsMapper().map(contact)

        XCTAssertEqual(payload.externalID, "xvk-test-contacts-001")
    }

    func testMapperDoesNotTreatOtherURLLabelsAsExternalID() {
        let contact = CNMutableContact()
        contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: "x-macos-data://external-id/should-not-match" as NSString)]

        XCTAssertNil(ContactsMapper().map(contact).externalID)
    }

    func testMapperDistinguishesOrganizationContact() {
        let contact = CNMutableContact()
        contact.contactType = .organization
        contact.organizationName = "Example Inc."

        XCTAssertEqual(ContactsMapper().map(contact).kind, .organization)
    }

    func testMapperCreatesOrganizationWithExternalIDURL() {
        let payload = ContactPayload(kind: .organization, externalID: "org-create-001", organizationName: "Example Inc.")
        let contact = ContactsMapper().makeMutableContact(from: payload)

        XCTAssertEqual(contact.contactType, .organization)
        XCTAssertEqual(contact.organizationName, "Example Inc.")
        XCTAssertEqual(contact.urlAddresses.first?.label, "macos-data-cli")
        XCTAssertEqual(contact.urlAddresses.first?.value as? String, "x-macos-data://external-id/org-create-001")
    }

    func testMapperSetsImageData() {
        let contact = CNMutableContact()
        ContactsMapper().setImageData(Data([0, 1, 2, 3]), on: contact)
        XCTAssertEqual(contact.imageData, Data([0, 1, 2, 3]))
    }

    func testMapperReportsImageAvailabilityWithoutReadingImageData() {
        let contact = CNMutableContact()
        XCTAssertFalse(ContactsMapper().map(contact).imageAvailable)

        contact.imageData = Data([0, 1, 2, 3])
        XCTAssertTrue(ContactsMapper().map(contact).imageAvailable)
    }

    func testProvidedAvatarFixturesAreNormalizedBelowLimit() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["icon1.png", "icon2.png", "icon3.jpeg"] {
            let result = try ContactImageProcessor().process(try Data(contentsOf: root.appendingPathComponent("docs/development/\(name)")))
            XCTAssertLessThanOrEqual(result.data.count, ContactImageProcessor.maxOutputBytes)
            XCTAssertLessThanOrEqual(result.width, ContactImageProcessor.maxDimension)
            XCTAssertLessThanOrEqual(result.height, ContactImageProcessor.maxDimension)
        }
    }

    func testImageInputOverTenMBIsRejected() {
        XCTAssertThrowsError(try ContactImageProcessor().process(Data(repeating: 0, count: ContactImageProcessor.maxInputBytes + 1)))
    }
}
