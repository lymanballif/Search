import XCTest
@testable import Search

@MainActor
final class TabNavigationAliasTests: XCTestCase {
    private var saved: Data?

    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-navigation-alias-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        saved = Store.settings.data(forKey: "shortcuts")
        Store.settings.removeObject(forKey: "shortcuts")
    }

    override func tearDown() async throws {
        Store.settings.set(saved, forKey: "shortcuts")
    }

    func testDefaultArrowsAreAliasesWithoutReplacingMenuShortcuts() {
        let store = ShortcutStore()
        XCTAssertEqual(store.tabNavigationAlias(on: KeyCombo("left", option: true))?.id, "tabs.previous")
        XCTAssertEqual(store.tabNavigationAlias(on: KeyCombo("right", option: true))?.id, "tabs.next")
        XCTAssertEqual(store.key(for: "tabs.previous"), KeyCombo("[", shift: true))
        XCTAssertEqual(store.key(for: "tabs.next"), KeyCombo("]", shift: true))
        for combo in [KeyCombo("left"), KeyCombo("right", command: false, option: true),
                      KeyCombo("right", shift: true, option: true), KeyCombo("left", option: true, control: true)] {
            XCTAssertNil(store.tabNavigationAlias(on: combo))
        }
        XCTAssertFalse(store.anyChanged)
    }

    func testDisablingOrMovingTheCommandDisablesOnlyItsAlias() {
        let store = ShortcutStore()
        let left = KeyCombo("left", option: true), right = KeyCombo("right", option: true)
        store.clear("tabs.previous")
        XCTAssertNil(store.tabNavigationAlias(on: left))
        XCTAssertEqual(store.tabNavigationAlias(on: right)?.id, "tabs.next")
        store.assign(KeyCombo("j", option: true), to: "tabs.next")
        XCTAssertNil(store.tabNavigationAlias(on: right))
        XCTAssertNil(ShortcutStore().tabNavigationAlias(on: right))
        store.resetAll()
        XCTAssertEqual(store.tabNavigationAlias(on: left)?.id, "tabs.previous")
        XCTAssertEqual(store.tabNavigationAlias(on: right)?.id, "tabs.next")
    }

    func testExplicitBrowserAndExtensionAssignmentsWin() {
        let store = ShortcutStore()
        let right = KeyCombo("right", option: true)
        store.assign(right, to: "tabs.back")
        XCTAssertNil(store.tabNavigationAlias(on: right))
        XCTAssertEqual(store.customCommand(on: right)?.id, "tabs.back")
        store.resetAll()
        store.assign(right, to: "ext:test:do-something")
        XCTAssertNil(store.tabNavigationAlias(on: right))
        XCTAssertNil(ShortcutStore().tabNavigationAlias(on: right))
        store.clear("ext:test:do-something")
        XCTAssertEqual(store.tabNavigationAlias(on: right)?.id, "tabs.next")
    }
}
