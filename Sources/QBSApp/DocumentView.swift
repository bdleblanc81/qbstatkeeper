import SwiftUI
import AppKit
import QBSCore

enum DocumentTab: String, CaseIterable, Identifiable {
    case setup = "Tournament Setup", schedule = "Schedule", gameEntry = "Game Entry", reports = "Reports", settings = "Settings"
    var id: String { rawValue }
}

enum QuickReport: String, CaseIterable, Identifiable {
    case teams = "Team Standings QuickPrint Report"
    case individuals = "Individual Standings QuickPrint Report"
    case games = "Game QuickPrint Report"
    case roomMatchups = "Room Matchups Report"
    case teamSchedules = "Team Schedules Report"
    case missingSlots = "Missing Slots Report"
    case buzzers = "Buzzer Locations Report"
    var id: String { rawValue }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String = ""
    var primary: String = "OK"
    var secondary: String? = nil
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
}

struct DocumentView: View {
    @Binding var document: TournamentDocument
    var fileURL: URL?

    init(document: Binding<TournamentDocument>, fileURL: URL?, initialTab: DocumentTab = .setup) {
        _document = document
        self.fileURL = fileURL
        _tab = State(initialValue: initialTab)
    }

    @StateObject private var actions = DocActions()
    @State private var tab: DocumentTab
    @State private var quick: QuickReport = .teams
    @State private var alert: AlertInfo?
    @State private var filter = RoundFilter()
    @State private var showMerge = false
    @State private var showPlayoffs = false
    @State private var shownLoadNotes = false
    @State private var lastAutorecover = Date()
    @AppStorage("autorecoverEnabled") private var autorecover = false
    @AppStorage("autorecoverMinutes") private var autorecoverMinutes = 10

    private var tournament: Binding<Tournament> { $document.tournament }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Select View", selection: $tab) {
                ForEach(DocumentTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            Group {
                switch tab {
                case .setup: SetupView(t: tournament, showAlert: { alert = $0 })
                case .schedule: ScheduleView(t: tournament, showAlert: { alert = $0 })
                case .gameEntry: GameEntryView(t: tournament, showAlert: { alert = $0 })
                case .reports: ReportsView(t: tournament.wrappedValue, fileURL: fileURL, filter: filter, quick: $quick)
                case .settings: SettingsView(t: tournament, filter: $filter, showAlert: { alert = $0 })
                }
            }
        }
        .frame(minWidth: 1000, idealWidth: 1320, minHeight: 620, idealHeight: 780)
        .toolbar { toolbarContent }
        .alert(item: $alert) { info in
            if let secondary = info.secondary {
                return Alert(title: Text(info.title), message: Text(info.message),
                             primaryButton: .default(Text(info.primary), action: info.onPrimary),
                             secondaryButton: .cancel(Text(secondary), action: info.onSecondary))
            }
            return Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text(info.primary), action: info.onPrimary))
        }
        .sheet(isPresented: $showMerge) { MergeSheet(base: tournament, baseName: fileURL?.lastPathComponent ?? "untitled", isPresented: $showMerge, showAlert: { alert = $0 }) }
        .sheet(isPresented: $showPlayoffs) { PlayoffsSheet(t: tournament, isPresented: $showPlayoffs, showAlert: { alert = $0 }) }
        .background(FocusAnchor())
        .background(WindowNameTracker(name: document.tournament.settings.tournamentName, isBlank: document.tournament.teams.isEmpty && document.tournament.games.isEmpty && document.tournament.settings.tournamentName.isEmpty))
        .focusedSceneObject(actions)
        .onAppear {
            wireActions()
            RecentTournaments.note(fileURL)
            detachFromSourceFileIfNeeded()
            if !shownLoadNotes, !document.loadNotes.isEmpty {
                shownLoadNotes = true
                alert = AlertInfo(title: "Current max players per team exceeded.", message: document.loadNotes.joined(separator: "\n"))
            }
        }
        .onChange(of: tab) { _ in wireActions() }
        .onChange(of: fileURL) { RecentTournaments.note($0) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in autorecoverIfDue() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { NSDocumentController.shared.newDocument(nil) } label: { Label("New", systemImage: "doc.badge.plus") }.help("Create a new tournament")
            Button { NSDocumentController.shared.openDocument(nil) } label: { Label("Open", systemImage: "folder") }.help("Open an existing tournament file.")
            Button { NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) } label: { Label("Save", systemImage: "square.and.arrow.down") }.help("Save current tournament.")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showPlayoffs = true } label: { Label("Playoffs", systemImage: "trophy") }.help("Playoffs & Consolation")
            Button { importTeams() } label: { Label("Import", systemImage: "person.3") }.help("Import team info from file")
            Menu {
                Button("By Game ID") { sortGames(.gameID) }
                Button("By Round") { sortGames(.round) }
                Button("By Round, Game ID") { sortGames(.roundThenGame) }
            } label: { Label("Sort Games", systemImage: "arrow.up.arrow.down") }.help("Sort games")
            Button { webReports() } label: { Label("Web Reports", systemImage: "globe") }.help("Create Full Web Reports")
        }
    }

    /// Only .qzx files are tournament files. Anything else that gets opened (a .sqbs from NAQT, say) is opened as an
    /// unsaved copy, so Save asks for a new .qzx name and the original file is never written to.
    private func detachFromSourceFileIfNeeded() {
        guard let url = fileURL, url.pathExtension.lowercased() != "qzx" else { return }
        DispatchQueue.main.async {
            guard let doc = NSDocumentController.shared.documents.first(where: { $0.fileURL == url }) else { return }
            doc.fileURL = nil
            doc.updateChangeCount(.changeDone)
            let kind = url.pathExtension.isEmpty ? "This file" : ".\(url.pathExtension) files"
            alert = AlertInfo(title: "Opened a copy of “\(url.lastPathComponent)”.",
                              message: "\(kind) are only used to import teams and to send to NAQT, so the original will not be changed. Saving makes a new .qzx file.")
        }
    }

    private func wireActions() {
        actions.selectTab = { tab = $0 }
        actions.quickReport = { quick = $0; tab = .reports }
        actions.webReports = { webReports() }
        actions.mergeFiles = { showMerge = true }
        actions.playoffs = { showPlayoffs = true }
        actions.importTeams = { importTeams() }
        actions.exportSQBS = { exportSQBS() }
        actions.sortGames = { sortGames($0) }
    }

    /// Writes a recovery copy of the tournament every N minutes when Settings > General asks for it.
    private func autorecoverIfDue() {
        guard autorecover, Date().timeIntervalSince(lastAutorecover) >= Double(max(autorecoverMinutes, 1)) * 60 else { return }
        lastAutorecover = Date()
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Quiz Bowl Statkeeper/Autorecover", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".qzx"
        try? TournamentFile.data(for: document.tournament).write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private func sortGames(_ order: GameSortOrder) {
        document.tournament.games = document.tournament.sortedGames(by: order)
        NotificationCenter.default.post(name: .gamesSorted, object: nil)
    }

    // MARK: Import teams

    private func importTeams() {
        let panel = NSOpenPanel()
        panel.message = "Choose a team file or saved tournament file."
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try RosterImport.parse(data: Data(contentsOf: url), useDivisions: document.tournament.importUsesDivisions)
            if document.tournament.hasGames {
                // a different roster would change what the games mean, so this is the replace-everything import
                let apply = {
                    document.tournament.applyImport(result)
                    if !result.notes.isEmpty { alert = AlertInfo(title: "Current max players per team exceeded.", message: result.notes.joined(separator: "\n")) }
                }
                alert = AlertInfo(title: "Importing team info will erase existing games.", message: "", primary: "Continue", secondary: "Cancel", onPrimary: apply)
            } else {
                // teams entered before the roster arrived are matched by name and keep their settings
                let summary = document.tournament.mergeImport(result)
                var lines: [String] = []
                if !summary.updated.isEmpty { lines.append("Rosters added to \(summary.updated.count) team\(summary.updated.count == 1 ? "" : "s") already set up.") }
                if !summary.added.isEmpty { lines.append("\(summary.added.count) new team\(summary.added.count == 1 ? "" : "s") added.") }
                if !summary.notInFile.isEmpty { lines.append("Not in the file (left as they were): " + summary.notInFile.joined(separator: ", ")) }
                lines.append(contentsOf: result.notes)
                alert = AlertInfo(title: "Teams imported.", message: lines.joined(separator: "\n"))
            }
        } catch {
            alert = AlertInfo(title: "\(error)")
        }
    }

    /// Saved file name if there is one, otherwise the tournament name.
    private func defaultBaseName(fallback: String = "tournament") -> String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        let n = SaveNames.clean(document.tournament.settings.tournamentName)
        return n.isEmpty ? fallback : n
    }

    // MARK: Export for NAQT

    private func exportSQBS() {
        let panel = NSSavePanel()
        panel.message = "Export the tournament as an .sqbs file."
        panel.nameFieldStringValue = defaultBaseName() + ".sqbs"
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = TournamentFile.data(for: document.tournament, windowsCompatible: true)
        do { try data.write(to: url) } catch { alert = AlertInfo(title: "save failed: error \((error as NSError).code), \(error.localizedDescription)") }
    }

    // MARK: Web reports

    private func webReports() {
        let panel = NSSavePanel()
        panel.title = "Create Reports In Folder"
        panel.prompt = "Create"
        panel.message = "Choose a short name without an extension (for example oqt2010)."
        panel.nameFieldStringValue = defaultBaseName(fallback: "reports")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let base = url.lastPathComponent
        let folder = url.deletingLastPathComponent()
        let t = document.tournament
        let gen = ReportGenerator(tournament: t, baseName: base, filter: filter)
        do {
            for (name, html) in gen.allPages() {
                try ReportGenerator.encode(html).write(to: folder.appendingPathComponent(name))
            }
            // schedule pages, when a schedule has been set up
            if !t.plus.schedule.isDefault {
                let sched = ScheduleReports(tournament: t)
                for kind in ScheduleReports.Kind.allCases {
                    try ReportGenerator.encode(sched.page(kind)).write(to: folder.appendingPathComponent(base + kind.fileSuffix))
                }
            }
            if t.settings.reportEnabled[7] {
                let src = URL(fileURLWithPath: t.settings.reportNames[7])
                guard FileManager.default.fileExists(atPath: src.path) else {
                    alert = AlertInfo(title: "Style sheet not found.", message: "style sheet name from Settings/Report: \(t.settings.reportNames[7])")
                    return
                }
                let dst = folder.appendingPathComponent(base + "_style.css")
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: src, to: dst)
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent(gen.outputName(.standings))])
        } catch {
            alert = AlertInfo(title: "File Error. Report not generated.", message: "file name: \(url.path)")
        }
    }
}

extension Notification.Name {
    static let gamesSorted = Notification.Name("gamesSorted")
}
