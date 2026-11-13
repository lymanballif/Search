import AppKit
import JavaScriptCore
import XCTest
@testable import Search

final class HiddenPreviewTests: XCTestCase {
    private func context() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, error in XCTFail(error?.toString() ?? "JavaScript error") }
        context.evaluateScript("""
        var window = this, listeners = {}, styles = {};
        var scrollX = 12, scrollY = 320;
        function addEventListener(name, fn) { listeners[name] = fn; }
        function scrollTo(pos) { scrollX = pos.left; scrollY = pos.top; }
        var scroller = {scrollLeft: 7, scrollTop: 90, parentElement: null, isConnected: true,
          scrollTo: function(p) { this.scrollLeft = p.left; this.scrollTop = p.top; }};
        var element = {parentElement: scroller, scrollIntoView: function(p) {
          if (p.behavior !== 'instant') throw new Error('preview must not leave a scroll running');
          scrollX = 0; scrollY = 1800; scroller.scrollLeft = 0; scroller.scrollTop = 600;
        }};
        var document = {
          scrollingElement: {},
          getElementById: function(id) { return styles[id]; },
          createElement: function() { return {textContent: ''}; },
          head: {appendChild: function(el) { styles[el.id] = el; }},
          querySelector: function(sel) {
            if (sel === 'invalid[') throw new Error('invalid selector');
            return sel === '#missing' ? null : element;
          }
        };
        styles['office-veil'] = {textContent: 'all hidden'};
        """)
        context.evaluateScript(Veiling.picker)
        return context
    }

    func testLeavingHoverRestoresWindowAndNestedScroll() throws {
        let c = try context()
        c.evaluateScript("__officeVeil.peek('all but one', '#one')")
        XCTAssertEqual(c.evaluateScript("scrollY")?.toInt32(), 1800)
        c.evaluateScript("__officeVeil.unpeek('all hidden')")
        XCTAssertEqual(c.evaluateScript("[scrollX,scrollY,scroller.scrollLeft,scroller.scrollTop].join(',')")?.toString(), "12,320,7,90")
        XCTAssertEqual(c.evaluateScript("styles['office-veil'].textContent")?.toString(), "all hidden")
        XCTAssertEqual(c.evaluateScript("styles['office-peek'].textContent")?.toString(), "")
    }

    func testMovingDirectlyToAnotherRowKeepsOriginalPosition() throws {
        let c = try context()
        c.evaluateScript("__officeVeil.peek('first', '#one'); __officeVeil.peek('second', '#two'); __officeVeil.unpeek('all hidden')")
        XCTAssertEqual(c.evaluateScript("[scrollY,scroller.scrollTop].join(',')")?.toString(), "320,90")
        c.evaluateScript("scrollY = 410; __officeVeil.peek('first', '#one'); __officeVeil.unpeek('one restored')")
        XCTAssertEqual(c.evaluateScript("scrollY")?.toInt32(), 410)
        XCTAssertEqual(c.evaluateScript("styles['office-veil'].textContent")?.toString(), "one restored")
    }

    func testMissingAndInvalidRowsDoNotLeaveAnOldPreview() throws {
        let c = try context()
        for selector in ["#missing", "invalid["] {
            c.evaluateScript("__officeVeil.peek('first', '#one'); __officeVeil.peek('missing', '\(selector)')")
            XCTAssertEqual(c.evaluateScript("scrollY")?.toInt32(), 320)
            XCTAssertEqual(c.evaluateScript("styles['office-veil'].textContent")?.toString(), "all hidden")
        }
    }

    func testNavigationCancelsPreviewWithoutRewindingItsDestination() throws {
        let c = try context()
        c.evaluateScript("__officeVeil.peek('first', '#one'); scrollY = 999; listeners.hashchange(); __officeVeil.unpeek('stale rules')")
        XCTAssertEqual(c.evaluateScript("scrollY")?.toInt32(), 999)
        XCTAssertEqual(c.evaluateScript("styles['office-veil'].textContent")?.toString(), "all hidden")
        c.evaluateScript("__officeVeil.peek('first', '#one'); listeners.pagehide()")
        XCTAssertEqual(c.evaluateScript("scrollY")?.toInt32(), 999)
    }

    func testUnpeekWithoutAPreviewDoesNotChangeTheDocument() throws {
        let c = try context()
        c.evaluateScript("__officeVeil.unpeek('old site rules')")
        XCTAssertEqual(c.evaluateScript("styles['office-veil'].textContent")?.toString(), "all hidden")
        XCTAssertEqual(c.evaluateScript("scrollY")?.toInt32(), 320)
    }
}

@MainActor
final class HiddenPreviewLifecycleTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "hidden-preview-lifecycle-\(getpid())", 1)
        super.setUp()
    }

    func testEndingAPreviewDoesNotBuildASleepingPage() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let tab = Tab()
        tab.restore(url: try XCTUnwrap(URL(string: "https://hidden.invalid/")), title: "Sleeping")
        defer { tab.close() }
        XCTAssertNil(tab.built)

        tab.unpeek("#hidden { display: none !important; }")

        XCTAssertNil(tab.built)
        XCTAssertTrue(tab.asleep)
    }
}
