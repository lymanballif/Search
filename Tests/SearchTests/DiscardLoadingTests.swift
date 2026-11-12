import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class DiscardLoadingTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "discard-loading-\(getpid())", 1)
        super.setUp()
    }

    private final class WaitingPage: NSObject, WKURLSchemeHandler {
        var started: (() -> Void)?
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            // Leave the response pending, as a slow site would.
            started?()
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
    }

    private func loadingPage() async throws -> Tab {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let handler = WaitingPage()
        let started = expectation(description: "The unfinished request started")
        handler.started = { started.fulfill() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(handler, forURLScheme: "search-loading-test")
        let tab = Tab(configuration: configuration)
        tab.go(to: try XCTUnwrap(URL(string: "search-loading-test://page/slow")))
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(tab.loading, "The regression needs a load still in progress")
        return tab
    }

    func testPuttingDownALoadingPinStopsItsSpinner() async throws {
        let tab = try await loadingPage()
        defer { tab.close() }
        tab.pin = "P"
        let oldPage = try XCTUnwrap(tab.built)

        tab.rest()

        XCTAssertTrue(tab.asleep)
        XCTAssertNil(tab.built)
        XCTAssertFalse(tab.loading)
        // A callback from the discarded view cannot light the pin again.
        oldPage.loadHTMLString("<p>Too late</p>", baseURL: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(tab.loading)
    }

    func testClosingALoadingPageStopsItsSpinner() async throws {
        let tab = try await loadingPage()
        tab.close()
        XCTAssertNil(tab.built)
        XCTAssertFalse(tab.loading)
    }
}
