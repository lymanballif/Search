import AppKit
import XCTest
@testable import Search

@MainActor
final class GroupBookmarkTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "group-bookmarks-\(getpid())", 1)
        super.setUp()
    }

    private func withBrowser(_ body: (Browser, TabGroup) throws -> Void) rethrows {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let original = Set(browser.bookmarks.roots.map(\.id))
        defer {
            browser.bookmarks.roots.filter { !original.contains($0.id) }.forEach { browser.bookmarks.remove($0.id) }
            browser.closeAll()
        }
        let group = TabGroup(id: UUID(), name: "Research", collapsed: true)
        browser.tabGroups = [group]
        try body(browser, group)
    }

    private func tab(_ url: String?, title: String, group: UUID, shy: Bool = false, bench: Bool = false) -> Tab {
        let tab = Tab(shy: shy, bench: bench)
        if let url { tab.restore(url: URL(string: url)!, title: title) }
        tab.groupID = group
        return tab
    }

    func testSavingPreservesGroupNameTabOrderAndCustomTitlesWithoutClosingOrWakingTabs() throws {
        try withBrowser { browser, group in
            let second = tab("https://second.invalid/page", title: "Second page", group: group.id)
            let first = tab("https://first.invalid/page", title: "First page", group: group.id)
            first.name = "My title"
            browser.showRow([second, first], active: second.id)
            let folder = try XCTUnwrap(browser.bookmarkTabGroup(group.id))
            XCTAssertEqual(folder.title, "Research")
            XCTAssertEqual(folder.children?.map(\.title), ["Second page", "My title"])
            XCTAssertEqual(folder.children?.compactMap(\.url), ["https://second.invalid/page", "https://first.invalid/page"])
            XCTAssertEqual(browser.tabs.map(\.id), [second.id, first.id])
            XCTAssertEqual(browser.activeID, second.id)
            XCTAssertEqual(browser.tabGroups, [group])
            XCTAssertNil(second.built)
            XCTAssertNil(first.built)
            XCTAssertEqual(browser.bookmarks.roots.last?.id, folder.id)
        }
    }

    func testPrivateBlankAndSessionOnlyPagesAreExcluded() throws {
        try withBrowser { browser, group in
            let normal = tab("https://public.invalid/page", title: "Public", group: group.id)
            let excluded = [
                tab("https://private.invalid/secret", title: "Private", group: group.id, shy: true),
                tab("https://bench.invalid/", title: "Bench", group: group.id, bench: true),
                tab(nil, title: "Blank", group: group.id),
                tab("about:blank", title: "Blank page", group: group.id),
                tab("blob:https://public.invalid/session", title: "Blob", group: group.id),
                tab("data:text/html,private", title: "Data", group: group.id),
                tab("search://settings", title: "Settings", group: group.id),
                tab("javascript:alert(1)", title: "Script", group: group.id)
            ]
            browser.showRow([normal] + excluded, active: normal.id)
            let folder = try XCTUnwrap(browser.bookmarkTabGroup(group.id))
            XCTAssertEqual(folder.children?.compactMap(\.url), ["https://public.invalid/page"])
            XCTAssertEqual(browser.tabs.count, excluded.count + 1)
        }
    }

    func testEmptyOrMissingGroupDoesNotCreateAFolder() {
        withBrowser { browser, group in
            let blank = tab(nil, title: "Blank", group: group.id)
            browser.showRow([blank], active: blank.id)
            let before = browser.bookmarks.roots
            XCTAssertNil(browser.bookmarkTabGroup(group.id))
            XCTAssertNil(browser.bookmarkTabGroup(UUID()))
            XCTAssertEqual(browser.bookmarks.roots, before)
        }
    }

    func testSavingDoesNotMoveOrDeduplicateExistingBookmarks() throws {
        try withBrowser { browser, group in
            let url = URL(string: "https://repeated.invalid/page")!
            let existing = browser.bookmarks.insert(.site("Existing", url), into: nil)
            let a = tab(url.absoluteString, title: "First tab", group: group.id)
            let b = tab(url.absoluteString, title: "Second tab", group: group.id)
            browser.showRow([a, b], active: a.id)
            let folder = try XCTUnwrap(browser.bookmarkTabGroup(group.id))
            XCTAssertTrue(browser.bookmarks.roots.contains(existing))
            XCTAssertEqual(folder.children?.map(\.title), ["First tab", "Second tab"])
        }
    }

    func testAddressCredentialsAreNotWrittenIntoTheFolderOrFallbackTitle() throws {
        try withBrowser { browser, group in
            let page = tab("https://example-user:example-secret@site.invalid/page", title: "", group: group.id)
            browser.showRow([page], active: page.id)
            let folder = try XCTUnwrap(browser.bookmarkTabGroup(group.id))
            let bookmark = try XCTUnwrap(folder.children?.first)
            XCTAssertEqual(bookmark.url, "https://site.invalid/page")
            XCTAssertFalse(bookmark.title.contains("example-user"))
            XCTAssertFalse(bookmark.title.contains("example-secret"))
        }
    }
}
