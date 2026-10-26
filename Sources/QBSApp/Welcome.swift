import SwiftUI
import AppKit

/// The splash shown when the program starts (and when the last tournament window is closed): create a new tournament,
/// load an existing one, or exit.
struct WelcomeView: View {
    var recent: [URL] = []
    var create: () -> Void
    var load: () -> Void
    var openRecent: (URL) -> Void = { _ in }
    var exit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 92, height: 92)
                Text("Welcome to Quiz Bowl Statkeeper for Mac")
                    .font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    Button(action: create) { Text("Create a new tournament").frame(width: 260) }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    Button(action: load) { Text("Load an existing tournament").frame(width: 260) }
                        .controlSize(.large)
                }.padding(.top, 6)
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent tournaments").font(.headline)
                        ForEach(recent, id: \.self) { url in
                            Button { openRecent(url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                    Text(url.deletingPathExtension().lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head).frame(maxWidth: 200, alignment: .trailing)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(10).frame(width: 440)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 28)
            HStack {
                Spacer()
                Button(action: exit) { Text("Exit").frame(width: 56) }.controlSize(.regular).help("Quit Quiz Bowl Statkeeper")
            }.padding(12)
        }
        .frame(width: 560, height: WelcomeView.height(recent: recent.count))
    }

    static let maxRecent = 6
    static func height(recent n: Int) -> CGFloat { 400 + (n == 0 ? 0 : CGFloat(58 + 26 * n)) }
}

/// The program's own list of recently used tournament files, so the splash does not depend on the system's recent-items setting.
enum RecentTournaments {
    private static let key = "recentTournamentPaths"
    static let limit = 15

    /// Remembers a .qzx file as the most recently used.
    static func note(_ url: URL?) {
        guard let url, url.isFileURL, url.pathExtension.lowercased() == "qzx" else { return }
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }

    /// Recent .qzx files that still exist, newest first (the program's list, then the system's).
    static func list(max count: Int) -> [URL] {
        let own = (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
        var seen = Set<String>(), out: [URL] = []
        for url in own + NSDocumentController.shared.recentDocumentURLs
        where url.pathExtension.lowercased() == "qzx" && FileManager.default.fileExists(atPath: url.path) && seen.insert(url.path).inserted {
            out.append(url)
        }
        return Array(out.prefix(count))
    }
}

enum Welcome {
    /// True from launch until the splash has taken over: the empty tournament the program opens on its own is kept
    /// invisible from the moment it is put on screen, so it never flashes.
    static var startupPhase = true
    /// The program was started by opening a file (double-click in Finder), so there is no splash to show.
    static var launchedWithFile = false

    static func isDocumentWindow(_ w: NSWindow) -> Bool { String(describing: type(of: w)) == "AppKitWindow" }

    /// Windows hidden during start-up that turned out to be real tournaments are shown again.
    static func revealIfReal(_ window: NSWindow) {
        if window.alphaValue == 0 { window.alphaValue = 1 }
    }

    /// Keeps the program's own empty start-up tournament off the screen.
    static func installStartupFlashGuard() {
        let sel = #selector(NSWindow.order(_:relativeTo:))
        guard let m = class_getInstanceMethod(NSWindow.self, sel) else { return }
        typealias Original = @convention(c) (AnyObject, Selector, Int, Int) -> Void
        let original = unsafeBitCast(method_getImplementation(m), to: Original.self)
        let block: @convention(block) (NSWindow, Int, Int) -> Void = { window, mode, other in
            if startupPhase, mode == NSWindow.OrderingMode.above.rawValue, isDocumentWindow(window) {
                // Tournament windows are kept invisible while the program starts, so the empty tournament it opens on its
                // own is never seen. Real ones (a file, or one with content) are shown as soon as they report in.
                window.alphaValue = 0
            }
            original(window, sel, mode, other)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
        // never leave the guard on: after a few seconds every window is shown and behaves normally again
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            startupPhase = false
            for w in NSApp.windows where isDocumentWindow(w) { revealIfReal(w) }
        }
    }

    private static var window: NSWindow?
    private static var observing = false

    /// Tournaments opened recently (.qzx files that still exist), newest first.
    static func recentTournaments() -> [URL] { RecentTournaments.list(max: WelcomeView.maxRecent) }

    /// Shows the splash when no tournament window is open (or always, with `force`).
    static func showIfNoDocuments(force: Bool = false) {
        guard force || (NSDocumentController.shared.documents.isEmpty && NSApp.windows.allSatisfy({ !$0.isVisible || $0 === window || $0.windowController?.document == nil })) else { return }
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let recent = recentTournaments()
        let view = WelcomeView(
            recent: recent,
            create: { NSDocumentController.shared.newDocument(nil); closeIfDocumentOpen() },
            load: { NSDocumentController.shared.openDocument(nil); closeIfDocumentOpen() },
            openRecent: { url in
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                    closeIfDocumentOpen()
                }
            },
            exit: { NSApp.terminate(nil) })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: WelcomeView.height(recent: recent.count)), styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // a file being opened at the same time may only show up now: if it has, the splash is not wanted
        for delay in [0.25, 0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if NSDocumentController.shared.documents.contains(where: { $0.fileURL != nil || SaveNames.isBlank($0) == false }) { dismiss() }
            }
        }
    }

    /// Closes the splash (a tournament has opened).
    static func dismiss() { if let w = window, w.isVisible { w.close() } }

    static func closeIfDocumentOpen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !NSDocumentController.shared.documents.isEmpty { window?.close() }
        }
    }

    /// SwiftUI opens an empty "Untitled" tournament when the program starts. If that is all there is, close it
    /// (before it is seen) and show the splash instead; a file opened from Finder is left alone.
    static func replaceStartupDocument(attempt: Int = 0) {
        let docs = NSDocumentController.shared.documents
        if docs.isEmpty {
            // started by opening a file: give it time to arrive before falling back to the splash
            let patience = launchedWithFile ? 25 : 5
            if attempt >= patience { startupPhase = false; showIfNoDocuments() } else { retry(attempt) }
            return
        }
        guard docs.count == 1, let doc = docs.first, doc.fileURL == nil else {
            startupPhase = false
            for w in NSApp.windows where isDocumentWindow(w) { revealIfReal(w) }
            return
        }
        guard let blank = SaveNames.isBlank(doc) else {
            if attempt < 15 { retry(attempt) } else { startupPhase = false }
            return
        }
        guard blank else {
            startupPhase = false
            doc.windowControllers.forEach { if let w = $0.window { revealIfReal(w) } }
            return
        }
        // the splash goes up first: with no window left for even a moment, the program would quit
        showIfNoDocuments(force: true)
        doc.windowControllers.forEach { $0.window?.alphaValue = 0 }
        doc.close()
        startupPhase = false
    }

    private static func retry(_ attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { replaceStartupDocument(attempt: attempt + 1) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Developer test modes (QBS_...) still start with an empty tournament.
    private var testMode: Bool { ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("QBS_") } || CommandLine.arguments.contains("--snapshot") }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { testMode }

    /// Closing the tournament window quits the program (after the usual question about unsaved changes).
    /// The splash is only for when the program first opens.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !testMode }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !testMode else { Welcome.startupPhase = false; return }
        let event = NSAppleEventManager.shared().currentAppleEvent
        Welcome.launchedWithFile = event?.eventClass == 0x61657674 && event?.eventID == 0x6F646F63   // 'aevt' 'odoc'
        Welcome.installStartupFlashGuard()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !testMode else { return }
        // a file opened from Finder arrives around launch; only show the splash if nothing opened
        DispatchQueue.main.async { Welcome.replaceStartupDocument() }
    }
}
