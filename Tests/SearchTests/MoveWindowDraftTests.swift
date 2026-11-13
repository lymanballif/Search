import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class MoveWindowDraftTests: XCTestCase {
    private var source: Browser!
    private var target: Browser!
    private var answer: Bool?

    override class func setUp() {
        setenv("SEARCH_PROBE", "move-window-draft-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        answer = Ask.testing
        Ask.testing = false
        source = Browser(record: WindowRecord())
        target = Browser(record: WindowRecord())
        // An unknown space gets its own store, as a signed-out space does.
        target.spaceID = UUID()
    }

    override func tearDown() {
        source.closeAll()
        target.closeAll()
        Ask.testing = answer
        source = nil
        target = nil
        super.tearDown()
    }

    private func page(unsaved: Bool = true, shy: Bool = false) async throws -> Tab {
        let tab = Tab(shy: shy, configuration: Web.configuration(shy: shy, space: source.spaceID))
        tab.setAddressOptimistically(try XCTUnwrap(URL(string: "about:blank#draft")))
        source.prepare(tab)
        source.insert(tab, at: source.tabs.count)
        _ = tab.web
        let installed = await evaluate(tab.web, "window.__officeForms = {unsaved: () => \(unsaved ? "true" : "false")}; true")
        XCTAssertEqual(installed as? Bool, true)
        _ = try XCTUnwrap(installed, "The WebKit fixture did not start")
        return tab
    }

    private func evaluate(_ web: WKWebView, _ script: String) async -> Any? {
        await withCheckedContinuation { done in
            var answered = false
            web.evaluateJavaScript(script, in: nil, in: Web.world) { result in
                guard !answered else { return }
                answered = true
                done.resume(returning: try? result.get())
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                guard !answered else { return }
                answered = true
                XCTFail("WebKit did not answer the test script within five seconds")
                done.resume(returning: nil)
            }
        }
    }

    /// Queued on the same page after the form check; its reply arrives once
    /// the form check has answered, without relying on a fixed delay.
    private func afterCheck(_ web: WKWebView) async {
        _ = await evaluate(web, "true")
        await Task.yield()
    }

    func testCancelKeepsTheDraftAndItsOriginalView() async throws {
        let tab = try await page()
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        await afterCheck(original)
        XCTAssertTrue(source.tabs.contains { $0 === tab })
        XCTAssertFalse(target.tabs.contains { $0 === tab })
        XCTAssertTrue(tab.built === original)
    }

    func testConfirmationMovesAndUsesTheDestinationSignIns() async throws {
        let tab = try await page()
        let original = try XCTUnwrap(tab.built)
        Ask.testing = true
        source.moveToWindow(tab, target)
        await afterCheck(original)
        XCTAssertFalse(source.tabs.contains { $0 === tab })
        XCTAssertTrue(target.tabs.contains { $0 === tab })
        XCTAssertTrue(tab.store === Spaces.store(for: target.spaceID))
        XCTAssertFalse(tab.built === original)
    }

    func testNoDraftMovesWithoutConfirmation() async throws {
        let tab = try await page(unsaved: false)
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        await afterCheck(original)
        XCTAssertTrue(target.tabs.contains { $0 === tab })
    }

    func testSameStoreKeepsTheDraftWithoutAQuestion() async throws {
        target.spaceID = source.spaceID
        let tab = try await page()
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        XCTAssertTrue(target.tabs.contains { $0 === tab })
        XCTAssertTrue(tab.built === original)
    }

    func testPrivateTabKeepsItsStoreAndDraft() async throws {
        let tab = try await page(shy: true)
        let original = try XCTUnwrap(tab.built)
        let store = tab.store
        source.moveToWindow(tab, target)
        XCTAssertTrue(target.tabs.contains { $0 === tab })
        XCTAssertTrue(tab.built === original)
        XCTAssertTrue(tab.store === store)
    }

    func testClosingDestinationDuringCheckCancelsMove() async throws {
        let tab = try await page(unsaved: false)
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        target.closeAll()
        await afterCheck(original)
        XCTAssertTrue(source.tabs.contains { $0 === tab })
        XCTAssertFalse(target.tabs.contains { $0 === tab })
        XCTAssertTrue(tab.built === original)
    }

    func testChangingDestinationSpaceDuringCheckCancelsMove() async throws {
        let tab = try await page(unsaved: false)
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        target.spaceID = UUID()
        await afterCheck(original)
        XCTAssertTrue(source.tabs.contains { $0 === tab })
        XCTAssertFalse(target.tabs.contains { $0 === tab })
    }

    func testReplacingDocumentDuringCheckCancelsMove() async throws {
        let tab = try await page(unsaved: false)
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        // A native page navigation commits without passing through Tab.go.
        tab.didCommit()
        await afterCheck(original)
        XCTAssertTrue(source.tabs.contains { $0 === tab })
        XCTAssertFalse(target.tabs.contains { $0 === tab })
    }

    func testPuttingPageDownDuringCheckCancelsMove() async throws {
        let tab = try await page(unsaved: false)
        let original = try XCTUnwrap(tab.built)
        source.moveToWindow(tab, target)
        tab.rest()
        await afterCheck(original)
        XCTAssertTrue(source.tabs.contains { $0 === tab })
        XCTAssertFalse(target.tabs.contains { $0 === tab })
    }
}
