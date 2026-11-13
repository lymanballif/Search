import SwiftUI

/// What you have taken off this site, and the way back.
///
/// A list of selectors is not something anyone can read. So resting the pointer
/// on a row puts that one thing back on the page, outlined, and scrolls to it —
/// you decide what to restore by looking at it, not by decoding its name.
struct HiddenPanel: View {
    @ObservedObject var browser: Browser

    var body: some View {
        Plate(browser.hereHost ?? "This page", width: 380, close: { browser.reviewing = false }) {
            if browser.hereVeils.isEmpty {
                Card { Nothing("Nothing is hidden here.") }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Caption("Hidden on this site — rest on a line to see it")
                    ScrollView(showsIndicators: false) {
                        Card {
                            ForEach(Array(browser.hereVeils.enumerated()), id: \.element.id) { index, veil in
                                if index > 0 { Rule() }
                                Row(
                                    veil: veil,
                                    peek: { browser.peek(veil) },
                                    stop: { browser.stopPeeking() },
                                    restore: { browser.restore(veil) }
                                )
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .frame(maxHeight: 320)
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Pill("Hide something…", filled: true) { browser.toggleHiding() }
                if !browser.hereVeils.isEmpty {
                    Pill("Restore all") { browser.restoreAll() }
                }
                Spacer()
            }
        }
        .background(HiddenPanelClickAway { [weak browser] in browser?.reviewing = false })
        .onDisappear { browser.stopPeeking() }
        // Leaving the panel puts the page back the way it was.
        .onHover { inside in
            if !inside { browser.stopPeeking() }
        }
    }

    private struct Row: View {
        let veil: Veil
        let peek: () -> Void
        let stop: () -> Void
        let restore: () -> Void

        @State private var hovering = false

        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(veil.label)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let note = veil.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)

                Quick("Restore", act: restore)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovering ? Palette.hover : .clear)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { peek() } else { stop() }
            }
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// Observe clicks instead of laying a hit-testing view over the page: the
/// page must still receive scrolling while this list is open.
private struct HiddenPanelClickAway: NSViewRepresentable {
    let close: () -> Void

    func makeNSView(context: Context) -> HiddenPanelClickAwayView {
        let view = HiddenPanelClickAwayView()
        view.close = close
        return view
    }

    func updateNSView(_ view: HiddenPanelClickAwayView, context: Context) {
        view.close = close
    }

    static func dismantleNSView(_ view: HiddenPanelClickAwayView, coordinator: ()) {
        view.stop()
        view.close = nil
    }
}

final class HiddenPanelClickAwayView: NSView {
    var close: (() -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.filter(event)
        }
    }

    /// The card's own controls and other windows keep their clicks. An
    /// outside click only dismisses, as the old backdrop did; it must not
    /// also follow a link underneath the panel.
    func filter(_ event: NSEvent) -> NSEvent? {
        guard monitor != nil, event.type == .leftMouseDown,
              let window, event.window === window, !isHiddenOrHasHiddenAncestor,
              !bounds.isEmpty, !bounds.contains(convert(event.locationInWindow, from: nil))
        else { return event }
        // The old backdrop was inside the content view, beneath native
        // window controls. Closing or minimising still works on one click.
        guard let content = window.contentView,
              content.convert(content.bounds, to: nil).contains(event.locationInWindow),
              ![NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].contains(where: { kind in
                  guard let button = window.standardWindowButton(kind), !button.isHiddenOrHasHiddenAncestor else { return false }
                  return button.convert(button.bounds, to: nil).contains(event.locationInWindow)
              })
        else { return event }
        close?()
        return nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
