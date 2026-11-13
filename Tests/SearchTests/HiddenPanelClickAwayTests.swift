import AppKit
import XCTest
@testable import Search

/// A window-number lookup needs a WindowServer connection. These tests
/// exercise the real filter against AppKit view/window geometry, with the
/// event's owner explicit so a headless host does not turn every click
/// into an unrelated, windowless event.
private final class PanelMouseEvent: NSEvent {
    private let owner: NSWindow
    private let point: NSPoint
    private let kind: NSEvent.EventType

    init(window: NSWindow, point: NSPoint, type: NSEvent.EventType) {
        owner = window
        self.point = point
        kind = type
        super.init()
    }

    required init?(coder: NSCoder) { return nil }

    override var window: NSWindow? { owner }
    override var locationInWindow: NSPoint { point }
    override var type: NSEvent.EventType { kind }
}

@MainActor
final class HiddenPanelClickAwayTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    private func window(style: NSWindow.StyleMask = [.borderless]) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        windows.append(window)
        return window
    }

    private func click(_ window: NSWindow, at point: NSPoint, type: NSEvent.EventType = .leftMouseDown) throws -> NSEvent {
        let event = PanelMouseEvent(window: window, point: point, type: type)
        XCTAssertTrue(event.window === window)
        return event
    }

    func testOnlyOutsideLeftClicksInItsOwnWindowDismissAndAreConsumed() throws {
        let own = window(), other = window()
        let view = HiddenPanelClickAwayView(frame: NSRect(x: 400, y: 100, width: 300, height: 400))
        var dismissed = 0
        view.close = { dismissed += 1 }
        own.contentView?.addSubview(view)

        let inside = try click(own, at: NSPoint(x: 500, y: 200))
        XCTAssertTrue(view.filter(inside) === inside)
        let elsewhere = try click(other, at: NSPoint(x: 30, y: 30))
        XCTAssertTrue(view.filter(elsewhere) === elsewhere)
        let right = try click(own, at: NSPoint(x: 30, y: 30), type: .rightMouseDown)
        XCTAssertTrue(view.filter(right) === right)
        XCTAssertEqual(dismissed, 0)

        XCTAssertNil(view.filter(try click(own, at: NSPoint(x: 30, y: 30))))
        XCTAssertEqual(dismissed, 1)
    }

    func testBackgroundNeverHitTestsAndScrollIsPassedThrough() throws {
        let own = window()
        let view = HiddenPanelClickAwayView(frame: NSRect(x: 400, y: 100, width: 300, height: 400))
        view.close = { XCTFail("Scrolling must not dismiss the panel") }
        own.contentView?.addSubview(view)
        XCTAssertNil(view.hitTest(NSPoint(x: 450, y: 150)))
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                      wheelCount: 1, wheel1: 20, wheel2: 0, wheel3: 0))
        let scroll = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertEqual(scroll.type, .scrollWheel)
        XCTAssertTrue(view.filter(scroll) === scroll)
    }

    func testNativeWindowControlsAndTitlebarKeepTheirClicks() throws {
        for fullSize in [false, true] {
            var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
            if fullSize { style.insert(.fullSizeContentView) }
            let own = window(style: style)
            let view = HiddenPanelClickAwayView(frame: NSRect(x: 400, y: 100, width: 300, height: 400))
            view.close = { XCTFail("Native chrome must keep its first click") }
            own.contentView?.addSubview(view)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try XCTUnwrap(own.standardWindowButton(kind))
                let rect = button.convert(button.bounds, to: nil)
                let event = try click(own, at: NSPoint(x: rect.midX, y: rect.midY))
                XCTAssertTrue(view.filter(event) === event)
            }
            if !fullSize, let content = own.contentView {
                let rect = content.convert(content.bounds, to: nil)
                let event = try click(own, at: NSPoint(x: 300, y: rect.maxY + 8))
                XCTAssertTrue(view.filter(event) === event)
            }
        }
    }

    func testDetachingStopsObservationAndReattachingUsesTheNewWindow() throws {
        let first = window(), second = window()
        let view = HiddenPanelClickAwayView(frame: NSRect(x: 400, y: 100, width: 300, height: 400))
        var dismissed = 0
        view.close = { dismissed += 1 }
        first.contentView?.addSubview(view)
        let oldClick = try click(first, at: NSPoint(x: 30, y: 30))
        view.removeFromSuperview()
        XCTAssertTrue(view.filter(oldClick) === oldClick)
        second.contentView?.addSubview(view)
        XCTAssertTrue(view.filter(oldClick) === oldClick)
        XCTAssertNil(view.filter(try click(second, at: NSPoint(x: 30, y: 30))))
        XCTAssertEqual(dismissed, 1)
        view.stop()
        let stopped = try click(second, at: NSPoint(x: 30, y: 30))
        XCTAssertTrue(view.filter(stopped) === stopped)
        XCTAssertEqual(dismissed, 1)
    }
}
