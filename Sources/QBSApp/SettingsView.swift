import SwiftUI
import AppKit
import QBSCore

struct SettingsView: View {
    @Binding var t: Tournament
    @Binding var filter: RoundFilter
    var showAlert: (AlertInfo) -> Void

    enum Pane: String, CaseIterable, Identifiable { case general = "General", reports = "Reports", sorting = "Sorting", warnings = "Warnings", packets = "Packets"
        var id: String { rawValue } }
    @State private var pane: Pane = .general
    @AppStorage("autorecoverEnabled") private var autorecover = false
    @AppStorage("autorecoverMinutes") private var autorecoverMinutes = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $pane) { ForEach(Pane.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
            switch pane {
            case .general: general
            case .reports: reports
            case .sorting: sorting
            case .warnings: warnings
            case .packets: packets
            }
            Spacer()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rounds: ClosedRange<Int> { t.roundRange ?? 0...0 }

    private var general: some View {
        GroupBox("Rounds Included in Reports") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { filter.all }, set: { all in
                    filter.all = all
                    if !all { filter.min = rounds.lowerBound; filter.max = rounds.upperBound }
                })) {
                    Text("All Rounds").tag(true)
                    Text("Rounds").tag(false)
                }.pickerStyle(.radioGroup).labelsHidden()
                HStack {
                    Stepper("From \(filter.min)", value: $filter.min, in: rounds.lowerBound...max(filter.max, rounds.lowerBound))
                    Stepper("to \(filter.max)", value: $filter.max, in: min(filter.min, rounds.upperBound)...rounds.upperBound)
                }.disabled(filter.all)
                Divider()
                HStack {
                    Toggle("Save autorecover info every:", isOn: $autorecover)
                    Stepper("\(autorecoverMinutes) minutes", value: $autorecoverMinutes, in: 1...120).disabled(!autorecover)
                }
                Text("Recovery copies are stored in ~/Library/Application Support/Quiz Bowl Statkeeper/Autorecover.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }.frame(maxWidth: 520)
    }

    private var reportRows: [(Int, String)] {
        [(1, "Include Team Standings"), (2, "Include Individual Standings"), (3, "Include Scoreboard"), (4, "Include Team Detail"), (5, "Include Individual Detail"), (0, "Include Round Report"), (6, "Include Stat Key")]
    }

    private var reports: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reportRows, id: \.0) { (i, label) in
                HStack {
                    Toggle(label, isOn: $t.settings.reportEnabled[i]).frame(width: 220, alignment: .leading)
                    TextField("", text: $t.settings.reportNames[i]).frame(width: 220)
                }
            }
            HStack {
                Toggle("Use Style Sheet", isOn: $t.settings.reportEnabled[7]).frame(width: 220, alignment: .leading)
                TextField("path to .css file", text: $t.settings.reportNames[7]).frame(width: 360)
                Button("Choose…") {
                    let p = NSOpenPanel()
                    if p.runModal() == .OK, let url = p.url { t.settings.reportNames[7] = url.path }
                }
            }
            Toggle("British Style Reports", isOn: $t.settings.britishStyle)
            Toggle("Always use / in paths", isOn: $t.settings.alwaysUseSlashInPaths)
        }
    }

    private var sorting: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Sort Criteria for Team Standings") {
                Picker("", selection: $t.settings.teamSortRaw) {
                    Text("Record, then points per game").tag(1)
                    Text("Record, then head-to-head, then points per game").tag(2)
                    Text("Record, then strength of schedule").tag(3)
                    Text("Record, then points per 20 tossups heard").tag(4)
                    Text("Record, then head-to-head, then points per 20 tossups heard").tag(5)
                }.pickerStyle(.radioGroup).labelsHidden().padding(8)
            }.frame(maxWidth: 440)
            Toggle("Sort players by points per 20 tossups heard", isOn: $t.settings.sortPlayersByPointsPerTUH)
        }
    }

    private var warnings: some View {
        GroupBox("Check for...") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach([(1, "Same player entered 2x for same game."),
                         (2, "Team score inconsistencies."),
                         (4, "Team bonus points per bonus heard is < 0 or > 30."),
                         (5, "Bonus points calculated > 0 but bonus heard is zero."),
                         (6, "Negative value entered for toss-ups heard.")], id: \.0) { (i, label) in
                    Toggle(label, isOn: $t.settings.warnings[i])
                }
            }.padding(8)
        }.frame(maxWidth: 520)
    }

    // MARK: Packet names

    private var packetRounds: [Int] {
        guard let r = t.roundRange else { return [] }
        return Array(r)
    }

    private var packets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Packet names appear in reports in place of round numbers. A round appears here once a game uses it.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Round").bold(); Text("Packet Name").bold() }
                    ForEach(packetRounds, id: \.self) { r in
                        GridRow {
                            Text("\(r)")
                            TextField("-", text: Binding(get: { let n = t.packetNames[r] ?? "-"; return n == "-" ? "" : n }, set: { new in
                                let clean = new.trimmingCharacters(in: .whitespaces)
                                t.packetNames[r] = clean.isEmpty ? "-" : clean
                                t.settings.packetNamesUsed = t.packetNames.values.contains { $0 != "-" } ? packetRounds.count : 0
                            })).frame(width: 240)
                        }
                    }
                }.padding(6)
            }.frame(maxWidth: 420, maxHeight: 360)
        }
    }
}
