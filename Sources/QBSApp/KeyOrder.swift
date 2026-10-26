import SwiftUI
import AppKit

/// Explicit Tab order for a screen. Tag each control with `.keyOrder(group, row, column)`; Tab then visits controls
/// by group, then row, then column, instead of AppKit's geometric guess (which hops between the two team panels).
struct KeyOrder: Equatable {
    var group: Int, row: Int, col: Int
    static func < (a: KeyOrder, b: KeyOrder) -> Bool { (a.group, a.row, a.col) < (b.group, b.row, b.col) }
}

final class KeyOrderMarker: NSView {
    var order = KeyOrder(group: 0, row: 0, col: 0)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window { KeyViewLinker.shared.schedule(w) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never intercept clicks

    // Layout can finish after the marker is added, so a moved or resized marker asks for a fresh link too.
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let changed = newOrigin != frame.origin
        super.setFrameOrigin(newOrigin)
        if changed, let w = window { KeyViewLinker.shared.schedule(w) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed, let w = window { KeyViewLinker.shared.schedule(w) }
    }
}

struct KeyOrderBackground: NSViewRepresentable {
    let order: KeyOrder
    func makeNSView(context: Context) -> KeyOrderMarker { let v = KeyOrderMarker(); v.order = order; return v }
    func updateNSView(_ v: KeyOrderMarker, context: Context) {
        v.order = order
        if let w = v.window { KeyViewLinker.shared.schedule(w) }
    }
}

extension View {
    func keyOrder(_ group: Int, _ row: Int, _ col: Int) -> some View {
        background(KeyOrderBackground(order: KeyOrder(group: group, row: row, col: col)))
    }
}

final class KeyViewLinker {
    static let shared = KeyViewLinker()
    private var pending: [ObjectIdentifier: DispatchWorkItem] = [:]

    /// Never holds a reference to the window: a window that is closing may not be weakly referenced, so the
    /// window is looked up again by identity when the work runs.
    func schedule(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        pending[id]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pending[id] = nil
            guard let window = NSApp.windows.first(where: { ObjectIdentifier($0) == id }) else { return }
            Self.relink(window)
        }
        pending[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    private static func markers(in view: NSView, into out: inout [KeyOrderMarker]) {
        if let m = view as? KeyOrderMarker { out.append(m) }
        for s in view.subviews { markers(in: s, into: &out) }
    }

    /// The control that sits on top of a marker (the marker is a background view with the same frame).
    private static func control(under marker: KeyOrderMarker, in window: NSWindow) -> NSView? {
        guard let content = window.contentView, let frame = content.superview else { return nil }
        let inWindow = marker.convert(NSPoint(x: marker.bounds.midX, y: marker.bounds.midY), to: nil)
        var hit = content.hitTest(frame.convert(inWindow, from: nil))
        while let v = hit {
            if v is NSTextField || v is NSPopUpButton || v is NSButton { return v }
            hit = v.superview
        }
        return nil
    }

    /// Follows the key-view chain from the first control and returns the orders visited (used to check the Tab order).
    static func traversal(_ window: NSWindow, steps: Int) -> [KeyOrder] {
        guard let root = window.contentView?.superview else { return [] }
        var found: [KeyOrderMarker] = []
        markers(in: root, into: &found)
        var byControl: [ObjectIdentifier: KeyOrder] = [:]
        for m in found { if let c = control(under: m, in: window) { byControl[ObjectIdentifier(c)] = m.order } }
        guard let first = found.sorted(by: { $0.order < $1.order }).compactMap({ control(under: $0, in: window) }).first else { return [] }
        var out: [KeyOrder] = []
        var v: NSView? = first
        for _ in 0..<steps {
            guard let cur = v else { break }
            if let o = byControl[ObjectIdentifier(cur)] { out.append(o) }
            v = cur.nextKeyView
            if v === first { break }
        }
        return out
    }

    static func relink(_ window: NSWindow) {
        guard let root = window.contentView?.superview else { return }
        var found: [KeyOrderMarker] = []
        markers(in: root, into: &found)
        guard !found.isEmpty else {
            window.autorecalculatesKeyViewLoop = true
            window.recalculateKeyViewLoop()
            return
        }
        let ordered = found.sorted { $0.order < $1.order }
        var chain: [NSView] = []
        for m in ordered {
            if let c = control(under: m, in: window), c.canBecomeKeyView, !chain.contains(where: { $0 === c }) { chain.append(c) }
        }
        guard chain.count > 1 else { return }
        window.autorecalculatesKeyViewLoop = false
        for (i, view) in chain.enumerated() { view.nextKeyView = chain[(i + 1) % chain.count] }
        if ProcessInfo.processInfo.environment["QBS_KEYDEBUG"] != nil {
            fputs("KEY relink chain=\(chain.count) markers=\(found.count)\n", stderr)
        }
    }

    /// Rebuilds the Tab chain from what is on screen right before every Tab or Shift-Tab, so a screen that changed
    /// a moment ago (new players, a forfeit, another game) can never be walked with an out-of-date order.
    static func installTabMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 48, let w = event.window { relink(w) }
            return event
        }
    }

    /// Debug aid (QBS_KEYDEBUG=1): logs where the first responder goes after each key press.
    static func installDebugMonitor() {
        guard ProcessInfo.processInfo.environment["QBS_KEYDEBUG"] != nil else { return }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let w = event.window
            let before = w?.firstResponder
            func describe(_ r: NSResponder?) -> String {
                guard let r else { return "nil" }
                if let v = r as? NSView {
                    let owner: NSView? = (r as? NSTextView).flatMap { $0.delegate as? NSView } ?? v
                    let f = owner?.convert(owner?.bounds ?? .zero, to: nil) ?? .zero
                    return "\(type(of: r)) x=\(Int(f.minX)) y=\(Int(f.minY)) next=\(owner?.nextKeyView.map { "\(type(of: $0))" } ?? "nil")"
                }
                return "\(type(of: r))"
            }
            fputs("KEY down code=\(event.keyCode) before=\(describe(before))\n", stderr)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                fputs("KEY after  code=\(event.keyCode) now=\(describe(w?.firstResponder))\n", stderr)
            }
            return event
        }
    }
}


/// Gives a new window somewhere harmless to put keyboard focus, so the Tournament Name field does not take it the moment
/// the window opens (which made macOS flash a text-suggestion popup). Tab still moves on into the fields as usual.
struct FocusAnchor: NSViewRepresentable {
    final class Anchor: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { false }
        override var focusRingType: NSFocusRingType { get { .none } set {} }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.initialFirstResponder == nil else { return }
            window.initialFirstResponder = self
            window.makeFirstResponder(self)
            // once the window is up, let go so the first Tab goes to the first field as usual
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, let w = self.window, w.firstResponder === self else { return }
                w.initialFirstResponder = nil
                w.makeFirstResponder(nil)
            }
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ v: Anchor, context: Context) {}
}
