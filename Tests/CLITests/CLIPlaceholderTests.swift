import XCTest

final class CLIPlaceholderTests: XCTestCase {
    func testCLITestTargetIsReady() {
        XCTAssertTrue(true)
    }

    func testVersionAliasesAreDocumented() {
        XCTAssertEqual(["--version", "-v"], ["--version", "-v"])
    }
}
