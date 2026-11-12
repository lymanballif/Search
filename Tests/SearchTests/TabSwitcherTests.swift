import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class TabSwitcherTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-switcher-\(getpid())", 1)
        super.setUp()
    }

    private func page() throws -> Tab {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let tab = Tab(configuration: WKWebViewConfiguration())
        tab.restore(url: try XCTUnwrap(URL(string: "https://example.test")), title: "Example")
        _ = tab.web
        return tab
    }

    private func shown(_ tab: Tab) -> TabSwitcher {
        let switcher = TabSwitcher()
        let second = UUID()
        switcher.step(row: [tab.id, second], current: tab.id, backwards: false)
        switcher.step(row: [tab.id, second], current: tab.id, backwards: false)
        return switcher
    }

    func testResetCancelsDelayedRevealAndDiscardsPictures() async throws {
        let tab = try page()
        defer { tab.close() }
        let switcher = shown(tab)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        switcher.cachePreview(image, for: tab, generation: tab.previewGeneration)
        XCTAssertNotNil(switcher.preview(for: tab))

        switcher.reset()
        XCTAssertNil(switcher.preview(for: tab))
        // A result arriving after reset cannot repopulate the cache.
        switcher.cachePreview(image, for: tab, generation: tab.previewGeneration)
        XCTAssertNil(switcher.preview(for: tab))

        switcher.step(row: [tab.id, UUID()], current: tab.id, backwards: false)
        switcher.reset()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(switcher.visible)
        XCTAssertFalse(switcher.active)
        XCTAssertNil(switcher.selectedID)
    }

    func testPutDownPinDropsPictureAndRejectsLateCaptureAfterReopening() throws {
        let tab = try page()
        defer { tab.close() }
        tab.pin = "Example"
        let switcher = shown(tab)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        let generation = tab.previewGeneration
        switcher.cachePreview(image, for: tab, generation: generation)
        XCTAssertNotNil(switcher.preview(for: tab))

        tab.rest()
        XCTAssertNil(tab.built)
        XCTAssertNil(switcher.preview(for: tab))
        switcher.cachePreview(image, for: tab, generation: generation)
        XCTAssertNil(switcher.preview(for: tab))

        // The address is unchanged, but a late result still belongs to the
        // page that was discarded, not to the pin opened a second time.
        _ = tab.web
        switcher.cachePreview(image, for: tab, generation: generation)
        XCTAssertNil(switcher.preview(for: tab))
        switcher.cachePreview(image, for: tab, generation: tab.previewGeneration)
        XCTAssertNotNil(switcher.preview(for: tab))
    }

    func testAutomaticSleepMayKeepItsOwnSnapshot() throws {
        let tab = try page()
        defer { tab.close() }
        let switcher = shown(tab)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        tab.sleep(picture: Data([1]))
        XCTAssertNil(tab.built)
        XCTAssertTrue(tab.hasPreview)
        switcher.cachePreview(image, for: tab, generation: tab.previewGeneration)
        XCTAssertNotNil(switcher.preview(for: tab))
        tab.rest()
        XCTAssertFalse(tab.hasPreview)
        XCTAssertNil(switcher.preview(for: tab))
    }
}
