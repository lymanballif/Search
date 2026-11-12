import AppKit
import XCTest
@testable import Search

@MainActor
final class SpaceSwipeWrapTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "space-wrap-\(getpid())", 1)
        super.setUp()
    }

    func testWrappingIsOptionalAndPreservesTheCreationCard() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let oldWrap = prefs.wrapSpaceSwipes, oldMerge = prefs.profilesInOneWindow
        defer {
            browser.closeAll()
            prefs.wrapSpaceSwipes = oldWrap
            prefs.profilesInOneWindow = oldMerge
        }
        prefs.profilesInOneWindow = false
        let first = Space(id: UUID(), name: "First", colour: 0)
        let last = Space(id: UUID(), name: "Last", colour: 1)
        browser.spaces = [first, last]
        prefs.wrapSpaceSwipes = false
        XCTAssertNil(browser.spaceBeyond(-1))
        XCTAssertNil(browser.spaceBeyond(1))
        XCTAssertTrue(browser.drawsPage(after: 1), "the last swipe still offers a new space by default")
        prefs.wrapSpaceSwipes = true
        XCTAssertEqual(browser.spaceBeyond(-1), last.id)
        XCTAssertEqual(browser.spaceBeyond(1), first.id)
        XCTAssertFalse(browser.drawsPage(after: 1), "wrapping must not show a misleading new-space card")
        XCTAssertTrue(browser.drawsPage(after: 0))
        browser.makingSpace = true
        XCTAssertNil(browser.spaceBeyond(1), "an explicitly opened creation form remains reachable")
        XCTAssertTrue(browser.drawsPage(after: 1))
        browser.makingSpace = false
        browser.spaces = [first]
        XCTAssertEqual(browser.spaceBeyond(-1), first.id)
        XCTAssertEqual(browser.spaceBeyond(1), first.id)
        XCTAssertFalse(browser.drawsPage(after: 0))
    }

    func testWrappingCrossesAllProfilesOnlyWhenMerged() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // Cross-profile traversal reads each profile's saved spaces. A
        // runner that cannot write the isolated test folder cannot create
        // this fixture; an in-memory profile alone would test an empty list.
        let probe = Store.file("space-wrap-\(UUID().uuidString).probe")
        do {
            try FileManager.default.createDirectory(at: probe.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
        } catch {
            throw XCTSkip("Requires a writable isolated app-support test directory: \(error.localizedDescription)")
        }
        let other = Profiles.shared.add(named: "Wrap test")
        let browser = Browser(record: WindowRecord(space: other.home))
        let first = Browser(record: WindowRecord(space: Space.firstID))
        let prefs = browser.prefs
        let oldWrap = prefs.wrapSpaceSwipes, oldMerge = prefs.profilesInOneWindow
        defer {
            browser.closeAll()
            first.closeAll()
            prefs.wrapSpaceSwipes = oldWrap
            prefs.profilesInOneWindow = oldMerge
            Profiles.shared.delete(other.id)
        }
        prefs.wrapSpaceSwipes = true
        prefs.profilesInOneWindow = true
        XCTAssertEqual(first.spaceBeyond(-1), other.home, "the first profile wraps back to the last")
        XCTAssertEqual(browser.spaceBeyond(1), browser.everySpace.first?.id)
        XCTAssertNotEqual(browser.spaceBeyond(1), other.home)
        XCTAssertEqual(browser.spaceBeyond(-1), Spaces.read(profile: browser.profileBeyond(-1)!).last?.id)
        prefs.wrapSpaceSwipes = false
        XCTAssertNil(browser.spaceBeyond(1), "the last profile keeps the creation card when wrapping is off")
        XCTAssertNotNil(browser.spaceBeyond(-1), "ordinary cross-profile navigation still works")
        prefs.profilesInOneWindow = false
        prefs.wrapSpaceSwipes = true
        XCTAssertEqual(browser.spaceBeyond(1), other.home)
        XCTAssertEqual(browser.spaceBeyond(-1), other.home)
    }
}
