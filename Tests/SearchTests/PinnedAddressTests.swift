import AppKit
import XCTest
@testable import Search

/// An address entered over a pin may leave the pin where it is (#1053).
/// Every browser is hidden, in the test world's own settings and files.
@MainActor
final class PinnedAddressTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "pinned-address-\(getpid())", 1)
        super.setUp()
    }

    private let home = URL(string: "about:blank#home")!
    private let current = URL(string: "about:blank#reading")!
    private let destination = URL(string: "https://destination.invalid/page")!

    func testTheChoiceIsOffByDefaultAndPersists() {
        let key = "pins.typedAside"
        let saved = Store.settings.object(forKey: key)
        defer {
            if let saved { Store.settings.set(saved, forKey: key) }
            else { Store.settings.removeObject(forKey: key) }
        }
        Store.settings.removeObject(forKey: key)
        XCTAssertFalse(Preferences().pinsTypedAside)
        let prefs = Preferences()
        prefs.pinsTypedAside = true
        XCTAssertTrue(Preferences().pinsTypedAside)
        prefs.pinsTypedAside = false
        XCTAssertFalse(Preferences().pinsTypedAside)
    }

    private func withBrowser(_ body: (Browser, Tab) throws -> Void) rethrows {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let saved = (prefs.pinsTypedAside, prefs.pinsKeepSite, prefs.floatingNewTab,
                     prefs.shiftEngine, prefs.shiftCustom, prefs.engineSuggests)
        defer {
            browser.closeAll()
            prefs.pinsTypedAside = saved.0
            prefs.pinsKeepSite = saved.1
            prefs.floatingNewTab = saved.2
            prefs.shiftEngine = saved.3
            prefs.shiftCustom = saved.4
            prefs.engineSuggests = saved.5
        }
        prefs.pinsTypedAside = true
        prefs.pinsKeepSite = true
        prefs.floatingNewTab = false
        prefs.engineSuggests = false
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: current, title: "Reading")
        tab.pin = "P"
        tab.home = home
        browser.prepare(tab)
        browser.showRow([tab], active: tab.id)
        browser.edit()
        browser.typed = destination.absoluteString
        try body(browser, tab)
    }

    func testOffStillNavigatesThePinEvenWhenPinsKeepTheirSite() {
        withBrowser { browser, pin in
            browser.prefs.pinsTypedAside = false
            browser.submit()
            XCTAssertEqual(browser.tabs.count, 1)
            XCTAssertEqual(browser.activeID, pin.id)
            XCTAssertEqual(pin.address, destination)
            XCTAssertEqual(pin.home, home)
        }
    }

    func testReturnOpensANormalTabAndPreservesThePin() {
        withBrowser { browser, pin in
            browser.submit()
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertNotEqual(browser.activeID, pin.id)
            XCTAssertNil(browser.active?.pin)
            XCTAssertEqual(browser.active?.address, destination)
            XCTAssertEqual(pin.address, current)
            XCTAssertEqual(pin.home, home)
            XCTAssertFalse(browser.editing)
            XCTAssertEqual(browser.typed, "")
        }
    }

    func testOrdinaryTabStillNavigatesInPlace() {
        withBrowser { browser, tab in
            tab.pin = nil
            browser.submit()
            XCTAssertEqual(browser.tabs.count, 1)
            XCTAssertEqual(browser.activeID, tab.id)
            XCTAssertEqual(tab.address, destination)
        }
    }

    func testCommandReturnKeepsTheNewTabInTheBackground() {
        withBrowser { browser, pin in
            browser.submit(aside: true)
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertEqual(browser.activeID, pin.id)
            XCTAssertEqual(browser.tabs.first { $0.id != pin.id }?.address, destination)
            XCTAssertEqual(pin.address, current)
        }
    }

    func testCommandShiftReturnStillOpensOnlyOneForegroundTab() {
        withBrowser { browser, pin in
            browser.submit(aside: true, front: true)
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertNotEqual(browser.activeID, pin.id)
            XCTAssertEqual(browser.active?.address, destination)
            XCTAssertEqual(pin.address, current)
        }
    }

    func testFloatingNewTabStillOpensOnlyOneTab() {
        withBrowser { browser, pin in
            browser.prefs.floatingNewTab = true
            browser.launch()
            XCTAssertTrue(browser.launching)
            browser.typed = destination.absoluteString
            browser.submit()
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertNotEqual(browser.activeID, pin.id)
            XCTAssertEqual(pin.address, current)
        }
    }

    func testClickedAddressSuggestionFollowsTheSameChoice() {
        withBrowser { browser, pin in
            browser.take(Suggestion(key: "destination", title: "Destination", url: destination, kind: .visited))
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertEqual(browser.active?.address, destination)
            XCTAssertEqual(pin.address, current)
            XCTAssertEqual(pin.home, home)
        }
    }

    func testSiteSearchOpensBesideThePin() {
        withBrowser { browser, pin in
            browser.siteChip = SearchSite(name: "Test", host: "test.invalid", template: "https://test.invalid/?q=%s")
            browser.typed = "two words"
            browser.submit()
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertEqual(browser.active?.address?.absoluteString, "https://test.invalid/?q=two%20words")
            XCTAssertEqual(pin.address, current)
        }
    }

    func testShiftReturnSearchAlsoPreservesThePin() {
        withBrowser { browser, pin in
            browser.prefs.shiftEngine = .custom
            browser.prefs.shiftCustom = "https://search.invalid/?q=%s"
            browser.typed = "two words"
            XCTAssertTrue(browser.submitToShiftEngine())
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertEqual(browser.active?.address?.absoluteString, "https://search.invalid/?q=two%20words")
            XCTAssertEqual(pin.address, current)
            XCTAssertEqual(pin.home, home)
        }
    }
}
