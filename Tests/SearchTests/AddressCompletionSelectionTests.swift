import AppKit
import XCTest
@testable import Search

@MainActor
final class AddressCompletionSelectionTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "address-completion-selection-\(getpid())", 1)
        super.setUp()
    }

    func testLongCompletionKeepsTheSiteVisibleAndTheEndingReplaceable() {
        withField("docs.google.com/document/d/" + String(repeating: "a", count: 120) + "/edit") { coordinator, field in
            coordinator.select(from: 5, in: field)

            XCTAssertEqual(field.editor.revealedRange, NSRange(location: 0, length: 5))
            XCTAssertEqual((field.editor.string as NSString).substring(with: field.editor.selectedRange()),
                           "google.com/document/d/" + String(repeating: "a", count: 120) + "/edit")
            field.editor.insertText("example", replacementRange: field.editor.selectedRange())
            XCTAssertEqual(field.editor.string, "docs.example", "Typing must still replace the offered ending")
        }
    }

    func testCompletionUsesUTF16ForEmojiAndCombiningCharacters() {
        // One emoji and one decomposed accented letter occupy four UTF-16
        // units, although Swift counts only two Characters.
        withField("🦊e\u{301}.example/🦊") { coordinator, field in
            coordinator.select(from: 4, in: field)

            XCTAssertEqual(field.editor.selectedRange(), NSRange(location: 4, length: 11))
            XCTAssertEqual((field.editor.string as NSString).substring(with: field.editor.selectedRange()), ".example/🦊")
            XCTAssertEqual(field.editor.revealedRange, NSRange(location: 0, length: 4))
            field.editor.insertText("x", replacementRange: field.editor.selectedRange())
            XCTAssertEqual(field.editor.string, "🦊e\u{301}x")
        }
    }

    func testNoCompletionLeavesOrdinaryCaretScrollingAlone() {
        withField("example.com/🦊") { coordinator, field in
            let native = CompletionEditor()
            native.string = field.editor.string
            native.revealedRanges = []
            native.selectedRange = NSRange(location: 14, length: 0)
            coordinator.select(from: 14, in: field)

            XCTAssertEqual(field.editor.selectedRange(), NSRange(location: 14, length: 0))
            XCTAssertEqual(field.editor.revealedRanges, native.revealedRanges,
                           "Without an offered ending, scrolling must remain AppKit's own")
        }
    }

    func testInvalidOffsetsLeaveTheSelectionAlone() {
        withField("example.com") { coordinator, field in
            field.editor.selectedRange = NSRange(location: 2, length: 3)
            field.editor.revealedRanges = []
            for offset in [-1, 12] {
                coordinator.select(from: offset, in: field)
                XCTAssertEqual(field.editor.selectedRange(), NSRange(location: 2, length: 3))
                XCTAssertTrue(field.editor.revealedRanges.isEmpty)
            }
        }
    }

    private func withField(_ text: String, body: (AddressField.Coordinator, CompletionField) -> Void) {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let field = CompletionField()
        field.stringValue = text
        field.editor.string = text
        // Assigning the initial string can itself ask AppKit to reveal it.
        // Only selection and scrolling after setup belong to the operation.
        field.editor.revealedRanges = []
        body(AddressField.Coordinator(browser: browser), field)
    }

    private final class CompletionField: NSTextField {
        let editor = CompletionEditor()
        override func currentEditor() -> NSText? { editor }
    }

    private final class CompletionEditor: NSTextView {
        var revealedRanges: [NSRange] = []
        var revealedRange: NSRange? { revealedRanges.last }
        override func scrollRangeToVisible(_ range: NSRange) { revealedRanges.append(range) }
    }
}
