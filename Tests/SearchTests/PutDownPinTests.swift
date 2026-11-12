import AppKit
import XCTest
@testable import Search

@MainActor
final class PutDownPinTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "put-down-pin-\(getpid())", 1)
        super.setUp()
    }

    func testClosingAnAlreadyPutDownPinLeavesTheSelectionAlone() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let pin = Tab(configuration: Web.configuration(space: browser.spaceID))
        pin.restore(url: try XCTUnwrap(URL(string: "about:blank#pin")), title: "Pin")
        pin.pin = "Pin"
        let other = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.showRow([pin, other], active: other.id)
        pin.rest()
        let before = browser.activeID

        browser.close(pin)

        XCTAssertEqual(browser.activeID, before)
        XCTAssertEqual(browser.tabs.map(\.id), [pin.id, other.id])
        XCTAssertTrue(pin.asleep)
        XCTAssertNil(pin.built)
    }

    func testAnOrdinarySleepingTabCanStillBeClosed() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let sleeping = Tab(configuration: Web.configuration(space: browser.spaceID))
        sleeping.restore(url: try XCTUnwrap(URL(string: "about:blank#sleeping")), title: "Sleeping")
        let other = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.showRow([sleeping, other], active: other.id)
        XCTAssertTrue(sleeping.asleep)

        browser.close(sleeping)

        XCTAssertFalse(browser.tabs.contains { $0.id == sleeping.id })
        XCTAssertEqual(browser.activeID, other.id)
    }
}
