import SwiftUI
import UniformTypeIdentifiers
import QBSCore

extension UTType {
    /// Tournament files: `.qzx` (Mac) and `.sqbs` (the file sent to NAQT).
    static let sqbsTournament = UTType(exportedAs: "org.quizbowlstatkeeper.tournament", conformingTo: .data)
}

@main
struct QBSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    init() { Snapshot.runIfRequested(); SaveNames.install(); SaveTest.runIfRequested(); KeyViewLinker.installTabMonitor(); KeyViewLinker.installDebugMonitor() }

    var body: some Scene {
        DocumentGroup(newDocument: TournamentDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands { SQBSCommands() }
    }
}

/// Actions a document window offers to the menu bar.
final class DocActions: ObservableObject {
    var selectTab: (DocumentTab) -> Void = { _ in }
    var quickReport: (QuickReport) -> Void = { _ in }
    var webReports: () -> Void = {}
    var mergeFiles: () -> Void = {}
    var importTeams: () -> Void = {}
    var exportSQBS: () -> Void = {}
    var playoffs: () -> Void = {}
    var sortGames: (GameSortOrder) -> Void = { _ in }
}

struct SQBSCommands: Commands {
    @FocusedObject var actions: DocActions?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Teams…") { actions?.importTeams() }.disabled(actions == nil)
            Button("Merge Files…") { actions?.mergeFiles() }.disabled(actions == nil)
            Button("Export .sqbs File for NAQT…") { actions?.exportSQBS() }.disabled(actions == nil)
        }
        CommandMenu("Reports") {
            Button("QuickPrint Teams") { actions?.quickReport(.teams) }.keyboardShortcut("t", modifiers: .command).disabled(actions == nil)
            Button("QuickPrint Individuals") { actions?.quickReport(.individuals) }.keyboardShortcut("i", modifiers: .command).disabled(actions == nil)
            Button("QuickPrint Games") { actions?.quickReport(.games) }.keyboardShortcut("g", modifiers: .command).disabled(actions == nil)
            Divider()
            Button("Room Matchups") { actions?.quickReport(.roomMatchups) }.disabled(actions == nil)
            Button("Team Schedules") { actions?.quickReport(.teamSchedules) }.disabled(actions == nil)
            Button("Missing Slots") { actions?.quickReport(.missingSlots) }.disabled(actions == nil)
            Button("Buzzer Locations") { actions?.quickReport(.buzzers) }.disabled(actions == nil)
            Divider()
            Button("Playoffs & Consolation…") { actions?.playoffs() }.keyboardShortcut("p", modifiers: [.command, .shift]).disabled(actions == nil)
            // ⌘W is the standard Close Window shortcut, so the web report uses ⇧⌘W.
            Button("Full Web Report…") { actions?.webReports() }.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(actions == nil)
        }
    }
}
