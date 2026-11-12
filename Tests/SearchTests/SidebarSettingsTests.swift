import AppKit
import XCTest
@testable import Search

@MainActor
final class SidebarSettingsTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "sidebar-settings-\(getpid())", 1)
        super.setUp()
    }

    private let keys = ["sidebar.extensions", "sidebar.bookmarks", "sidebar.profiles", "spaces.swipeWrap", "spaces", "sidebar"]

    private func fresh(_ body: (Preferences) -> Void) {
        _ = NSApplication.shared
        let saved = keys.map { ($0, Store.settings.object(forKey: $0)) }
        defer { for (key, value) in saved { Store.settings.set(value, forKey: key) } }
        keys.forEach(Store.settings.removeObject(forKey:))
        body(Preferences())
    }

    func testExistingButtonsStayVisibleByDefaultWithoutWritingChoices() {
        fresh { prefs in
            XCTAssertTrue(prefs.showsSidebarExtensions)
            XCTAssertTrue(prefs.showsSidebarBookmarks)
            XCTAssertTrue(prefs.showsSidebarProfiles)
            for key in keys.prefix(3) { XCTAssertNil(Store.settings.object(forKey: key)) }
            XCTAssertFalse(prefs.wrapSpaceSwipes)
            XCTAssertNil(Store.settings.object(forKey: "spaces.swipeWrap"))
        }
    }

    func testHiddenButtonsPersistAndCanBeRestoredFromSettings() {
        fresh { prefs in
            for key in keys.prefix(3) {
                XCTAssertTrue(SettingsIndex.apply(key, false, to: prefs))
                XCTAssertEqual(SettingsIndex.values(prefs)[key] as? Bool, false)
            }
            let again = Preferences()
            XCTAssertFalse(again.showsSidebarExtensions)
            XCTAssertFalse(again.showsSidebarBookmarks)
            XCTAssertFalse(again.showsSidebarProfiles)
            for key in keys.prefix(3) {
                XCTAssertTrue(SettingsIndex.apply(key, true, to: again))
                XCTAssertEqual(SettingsIndex.values(again)[key] as? Bool, true)
            }
            XCTAssertFalse(SettingsIndex.apply("sidebar.profiles", "not a choice", to: prefs))
        }
    }

    func testFooterSpaceTracksTheButtonsThatRemain() {
        fresh { prefs in
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: false, downloads: false), 2)
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: true, downloads: true), 4)
            prefs.usesSpaces = true
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: true, downloads: true), 5)
            prefs.showsSidebarProfiles = false
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: true, downloads: true), 4)
            prefs.showsSidebarExtensions = false
            prefs.showsSidebarBookmarks = false
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: true, downloads: false), 1,
                           "The space mark remains when the profile mark is hidden")
            prefs.usesSpaces = false
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: true, downloads: false), 0)
            XCTAssertEqual(SideFoot.doorCount(prefs, severalProfiles: true, downloads: true), 1,
                           "An active download still has a button when the other buttons are hidden")
        }
    }

    func testFooterChoicesFollowTheColumnAndExternalAppearanceChanges() throws {
        fresh { prefs in
            for key in keys.prefix(3) {
                guard let item = SettingsIndex.item(key) else { return XCTFail("Missing \(key)") }
                prefs.sidebar = false
                XCTAssertFalse(SettingsIndex.applies(item, prefs))
                prefs.sidebar = true
                XCTAssertTrue(SettingsIndex.applies(item, prefs))
                Store.settings.set(false, forKey: key)
            }
            prefs.reread()
            XCTAssertFalse(prefs.showsSidebarExtensions)
            XCTAssertFalse(prefs.showsSidebarBookmarks)
            XCTAssertFalse(prefs.showsSidebarProfiles)
            keys.prefix(3).forEach(Store.settings.removeObject(forKey:))
            prefs.reread()
            XCTAssertTrue(prefs.showsSidebarExtensions)
            XCTAssertTrue(prefs.showsSidebarBookmarks)
            XCTAssertTrue(prefs.showsSidebarProfiles)
            for key in keys.prefix(3) { XCTAssertNil(Store.settings.object(forKey: key)) }
        }
    }

    func testWrapChoiceIsFindableAndOnlyAppliesWithSpaces() throws {
        fresh { prefs in
            guard let item = SettingsIndex.item("spaces.swipeWrap") else { return XCTFail("Missing swipe setting") }
            XCTAssertTrue(SettingsIndex.find("wrap").contains { $0.id == item.id })
            XCTAssertFalse(SettingsIndex.applies(item, prefs))
            prefs.usesSpaces = true
            XCTAssertTrue(SettingsIndex.applies(item, prefs))
            XCTAssertTrue(SettingsIndex.apply(item.id, true, to: prefs))
            XCTAssertTrue(Preferences().wrapSpaceSwipes)
            XCTAssertEqual(SettingsIndex.values(prefs)[item.id] as? Bool, true)
        }
    }
}

final class SettingsSearchSectionsTests: XCTestCase {
    func testMixedResultsKeepEveryMatchExactlyOnce() {
        let matches = SettingsIndex.find("tab")
        let split = SettingsIndex.splitResults(matches)
        XCTAssertFalse(split.settings.isEmpty)
        XCTAssertFalse(split.information.isEmpty)
        XCTAssertTrue(split.settings.allSatisfy { $0.kind != .note })
        XCTAssertTrue(split.information.allSatisfy { $0.kind == .note })
        XCTAssertEqual(split.settings.map(\.id), matches.filter { $0.kind != .note }.map(\.id))
        XCTAssertEqual(split.information.map(\.id), matches.filter { $0.kind == .note }.map(\.id))
        XCTAssertEqual(Set((split.settings + split.information).map(\.id)), Set(matches.map(\.id)))
        XCTAssertEqual(split.settings.count + split.information.count, matches.count)
    }

    func testFindOnlyControlsAreStillSettingsAndNotesStandAlone() {
        let spelling = SettingsIndex.splitResults(SettingsIndex.find("autocorrect"))
        XCTAssertTrue(spelling.settings.contains { $0.id == "autocorrect" })
        XCTAssertFalse(spelling.information.contains { $0.id == "autocorrect" })
        let notes = SettingsIndex.splitResults(SettingsIndex.find("always there"))
        XCTAssertTrue(notes.settings.isEmpty)
        XCTAssertFalse(notes.information.isEmpty)
        let none = SettingsIndex.splitResults(SettingsIndex.find("no-such-setting-4265"))
        XCTAssertTrue(none.settings.isEmpty && none.information.isEmpty)
    }
}
