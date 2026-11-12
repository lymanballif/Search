import AppKit
import XCTest
@testable import Search

@MainActor
final class TabDoubleClickTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-double-click-\(getpid())", 1)
        super.setUp()
    }

    private var saved: Any?

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        saved = Store.settings.object(forKey: "tabs.doubleClick")
        Store.settings.removeObject(forKey: "tabs.doubleClick")
    }

    override func tearDown() async throws {
        Store.settings.set(saved, forKey: "tabs.doubleClick")
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible })
    }

    func testDefaultStillOpensANewTabWithoutWritingAChoice() {
        XCTAssertEqual(Preferences().tabDoubleClick, .newTab)
        XCTAssertNil(Store.settings.object(forKey: "tabs.doubleClick"))
        Store.settings.set("unknown", forKey: "tabs.doubleClick")
        XCTAssertEqual(Preferences().tabDoubleClick, .newTab)
        XCTAssertEqual(Store.settings.string(forKey: "tabs.doubleClick"), "unknown")
    }

    func testBothChoicesSurviveRelaunch() {
        let prefs = Preferences()
        for choice in [TabDoubleClick.titleBar, .newTab] {
            prefs.tabDoubleClick = choice
            XCTAssertEqual(Store.settings.string(forKey: "tabs.doubleClick"), choice.rawValue)
            XCTAssertEqual(Preferences().tabDoubleClick, choice)
        }
    }

    func testSettingCanBeFoundAndChangedWithoutChangingTabLayout() {
        let prefs = Preferences()
        let layout = prefs.tabsLayout
        XCTAssertTrue(SettingsIndex.find("title bar").contains { $0.id == "tabs.doubleClick" })
        XCTAssertEqual(SettingsIndex.item("tabs.doubleClick")?.page, .appearance)
        XCTAssertTrue(SettingsIndex.apply("tabs.doubleClick", "titleBar", to: prefs))
        XCTAssertEqual(prefs.tabDoubleClick, .titleBar)
        XCTAssertEqual(prefs.tabsLayout, layout)
        XCTAssertEqual(SettingsIndex.values(prefs)["tabs.doubleClick"] as? String, "titleBar")
        XCTAssertFalse(SettingsIndex.apply("tabs.doubleClick", "unknown", to: prefs))
        XCTAssertEqual(prefs.tabDoubleClick, .titleBar)
    }
}
