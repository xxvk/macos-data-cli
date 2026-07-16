import XCTest
@testable import Core
@testable import ContactsAdapter

final class ContactsPermissionTests: XCTestCase {
    func testCountRefusesUndeterminedPermission() {
        let permission = FakePermission(status: .notDetermined)
        let store = ContactsStore(permission: permission)

        XCTAssertThrowsError(try store.count()) { error in
            XCTAssertEqual(error as? ContactsError, .permissionRequired)
        }
    }

    func testCountRefusesDeniedPermission() {
        let permission = FakePermission(status: .denied)
        let store = ContactsStore(permission: permission)

        XCTAssertThrowsError(try store.count()) { error in
            XCTAssertEqual(error as? ContactsError, .permissionDenied)
        }
    }
}

private struct FakePermission: ContactsAccessProviding {
    let status: ContactsAccessStatus

    func requestAccess() async throws -> Bool { false }
}
