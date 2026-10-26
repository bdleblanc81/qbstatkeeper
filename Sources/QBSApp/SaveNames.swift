import SwiftUI
import AppKit
import ObjectiveC

/// The tournament name is the suggested file name when a new tournament is saved for the first time.
enum SaveNames {
    private static let lock = NSLock()
    private static var names: [ObjectIdentifier: String] = [:]
    private static var blank: [ObjectIdentifier: Bool] = [:]
    private static var seen = Set<ObjectIdentifier>()
    /// Order in which tournament windows first appeared; only the newest window may close the others.
    private static var arrival: [ObjectIdentifier: Int] = [:]
    private static var arrivals = 0
    private static var installed = false

    static func clean(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\")
        return name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Records the tournament name for the document shown in `window` (main thread).
    static func register(_ window: NSWindow, name: String, isBlank: Bool) {
        guard let doc = window.windowController?.document as? NSDocument else { return }
        let c = clean(name)
        lock.lock()
        if c.isEmpty { names[ObjectIdentifier(doc)] = nil } else { names[ObjectIdentifier(doc)] = c }
        blank[ObjectIdentifier(doc)] = isBlank
        let isNew = seen.insert(ObjectIdentifier(window)).inserted
        if isNew { arrivals += 1; arrival[ObjectIdentifier(window)] = arrivals }
        lock.unlock()
        // A closed window's memory can be reused by the next window, so forget a window when it closes.
        if isNew {
            let id = ObjectIdentifier(window)
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                lock.lock(); seen.remove(id); arrival[id] = nil; lock.unlock()
                if let token { NotificationCenter.default.removeObserver(token) }
            }
        }
        // a tournament with a file or some content opened (from the splash's Load button, a recent file or Finder): the splash is done
        if isNew && !(doc.fileURL == nil && isBlank) {
            DispatchQueue.main.async { Welcome.revealIfReal(window); Welcome.dismiss() }
        }
        if isNew {
            // the older window may still be settling, so look again a couple of times
            for delay in [0.0, 0.4, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { closeOtherDocuments(keeping: window, doc: doc) }
            }
        }
    }

    /// Only one tournament window is open at a time: a window for a new or opened document replaces the others.
    /// An untouched blank tournament closes quietly; one with work in it asks to save first.
    private static let launched = Date()

    private static func closeOtherDocuments(keeping window: NSWindow, doc: NSDocument) {
        // At start-up the program makes an empty tournament while a file may be opening at the same moment; the empty one
        // must lose, or each would close the other.
        lock.lock(); let newIsBlank = doc.fileURL == nil && (blank[ObjectIdentifier(doc)] ?? false); lock.unlock()
        if newIsBlank && Date().timeIntervalSince(launched) < 4 {
            let othersWithWork = NSApp.windows.contains { other in
                guard other !== window, let od = other.windowController?.document as? NSDocument, od !== doc else { return false }
                lock.lock(); defer { lock.unlock() }
                return od.fileURL != nil || !(blank[ObjectIdentifier(od)] ?? false)
            }
            if othersWithWork { window.alphaValue = 0; doc.close(); return }
        }
        let debug = ProcessInfo.processInfo.environment["QBS_DEBUGWIN"] != nil
        if debug { fputs("WIN closeOthers keeping=\(window.title) windows=\(NSApp.windows.map { "\($0.title)|doc=\($0.windowController?.document != nil)" })\n", stderr) }
        // two windows arriving together (a restored one and one just opened, say) must not close each other:
        // an older window never closes a newer one
        lock.lock()
        let mine = arrival[ObjectIdentifier(window)] ?? 0
        let newerExists = NSApp.windows.contains { other in
            other !== window && other.windowController?.document != nil && (arrival[ObjectIdentifier(other)] ?? 0) > mine
        }
        lock.unlock()
        if newerExists { return }
        for other in NSApp.windows where other !== window {
            guard let od = other.windowController?.document as? NSDocument, od !== doc else { continue }
            if debug { fputs("WIN closing \(other.title) edited=\(od.isDocumentEdited) url=\(od.fileURL?.lastPathComponent ?? "nil")\n", stderr) }
            lock.lock(); let isBlank = blank[ObjectIdentifier(od)] ?? false; lock.unlock()
            if od.fileURL == nil && isBlank { od.close() } else { other.performClose(nil) }
        }
    }

    /// Whether a document holds nothing yet (nil until its window has reported in).
    static func isBlank(_ document: NSDocument) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return blank[ObjectIdentifier(document)]
    }

    /// Suggested name for an untitled document. Safe to call from any thread.
    static func suggestion(for document: NSDocument) -> String? {
        lock.lock(); defer { lock.unlock() }
        return names[ObjectIdentifier(document)]
    }

    /// Makes untitled documents report the tournament name, which is what the Save panel starts with.
    static func install() {
        guard !installed else { return }
        installed = true
        let sel = #selector(getter: NSDocument.displayName)
        guard let m = class_getInstanceMethod(NSDocument.self, sel) else { return }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSString?
        let original = unsafeBitCast(method_getImplementation(m), to: Getter.self)
        let block: @convention(block) (AnyObject) -> NSString? = { obj in
            if let doc = obj as? NSDocument, doc.fileURL == nil, let name = suggestion(for: doc) { return name as NSString }
            return original(obj, sel)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
        installBlankCloseHook()
    }

    /// An untouched new tournament closes (or quits) without asking to save anything.
    private static func installBlankCloseHook() {
        let sel = #selector(NSDocument.canClose(withDelegate:shouldClose:contextInfo:))
        guard let m = class_getInstanceMethod(NSDocument.self, sel) else { return }
        typealias Original = @convention(c) (AnyObject, Selector, AnyObject, Selector?, UnsafeMutableRawPointer?) -> Void
        typealias Reply = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let original = unsafeBitCast(method_getImplementation(m), to: Original.self)
        let block: @convention(block) (AnyObject, AnyObject, Selector?, UnsafeMutableRawPointer?) -> Void = { obj, delegate, reply, context in
            if let doc = obj as? NSDocument, doc.fileURL == nil, isBlank(doc) == true, let reply, let target = delegate as? NSObject {
                let imp = target.method(for: reply)
                unsafeBitCast(imp, to: Reply.self)(target, reply, doc, true, context)
                return
            }
            original(obj, sel, delegate, reply, context)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
}

/// Reports the tournament name to `SaveNames` for the window this view lives in.
struct WindowNameTracker: NSViewRepresentable {
    let name: String
    let isBlank: Bool
    final class Tracker: NSView {
        var name = ""
        var isBlank = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            publish()
            DispatchQueue.main.async { [weak self] in self?.publish() }   // the document may attach just after
        }
        func publish() { if let w = window { SaveNames.register(w, name: name, isBlank: isBlank) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Tracker { let v = Tracker(); v.name = name; v.isBlank = isBlank; return v }
    func updateNSView(_ v: Tracker, context: Context) { v.name = name; v.isBlank = isBlank; v.publish() }
}

/// `QBS_SAVETEST=name` launches the real app, registers a tournament name, opens Save As and prints the suggested name.
enum SaveTest {
    static func runIfRequested() {
        guard let name = ProcessInfo.processInfo.environment["QBS_SAVETEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let w = NSApp.windows.first(where: { $0.windowController?.document != nil }),
                  let doc = w.windowController?.document as? NSDocument else { print("SAVETEST no document window"); exit(3) }
            SaveNames.register(w, name: name, isBlank: false)
            print("SAVETEST displayName=\(doc.displayName ?? "nil")")
            if let path = ProcessInfo.processInfo.environment["QBS_SAVETO"] {
                let url = URL(fileURLWithPath: path)
                print("SAVETEST saving to \(path) type=\(doc.fileType ?? "nil")")
                doc.save(to: url, ofType: doc.fileType ?? "", for: .saveAsOperation) { err in
                    print("SAVETEST save result: \(err.map { "\($0)" } ?? "ok") exists=\(FileManager.default.fileExists(atPath: path)) displayName=\(doc.displayName ?? "nil")")
                    exit(0)
                }
                return
            }
            if ProcessInfo.processInfo.environment["QBS_TOOLBAR"] != nil {
                print("SAVETEST toolbar action sent: \(NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil))")
            } else { doc.saveAs(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let panel = w.attachedSheet as? NSSavePanel ?? NSApp.windows.compactMap { $0 as? NSSavePanel }.first
                print("SAVETEST panel name=\(panel?.nameFieldStringValue ?? "no panel")")
                if let panel, ProcessInfo.processInfo.environment["QBS_CANCEL"] != nil {
                    w.endSheet(panel, returnCode: .cancel); panel.close()
                    print("SAVETEST cancelled cleanly"); exit(0)
                }
                if let panel, let dir = ProcessInfo.processInfo.environment["QBS_SAVEDIR"] {
                    panel.directoryURL = URL(fileURLWithPath: dir)
                    panel.nameFieldStringValue = ProcessInfo.processInfo.environment["QBS_SAVENAME"] ?? panel.nameFieldStringValue
                    w.endSheet(panel, returnCode: .OK)
                    panel.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        print("SAVETEST after UI save: fileURL=\(doc.fileURL?.path ?? "nil") displayName=\(doc.displayName ?? "nil")")
                        exit(0)
                    }
                    return
                }
                exit(0)
            }
        }
    }
}
