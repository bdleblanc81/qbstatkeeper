import SwiftUI
import QBSCore

struct SetupView: View {
    @Binding var t: Tournament
    var showAlert: (AlertInfo) -> Void

    @State private var divisionsText = ""
    @State private var selectedTeam: Int?
    @State private var sortAscending = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tournament Name:")
                TextField("", text: $t.settings.tournamentName).frame(maxWidth: 360)
            }
            HStack(alignment: .top, spacing: 14) {
                questionValues
                statTracking
                bonusConversion
                divisionsBox
            }
            rosterTable
        }
        .padding(12)
        .onAppear { divisionsText = t.divisions.joined(separator: "\n") }
        .onChange(of: t.divisions) { divisionsText = $0.joined(separator: "\n") }
    }

    // MARK: Question values

    private func block(_ v: RuleViolation) { showAlert(AlertInfo(title: v.title, message: v.detail)) }

    private var questionValues: some View {
        GroupBox("Question Values") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<4, id: \.self) { q in
                    HStack {
                        Toggle("", isOn: Binding(get: { t.settings.questionSelected[q] }, set: { on in
                            if !on, let v = t.unselectQuestionViolation(q) { block(v); return }
                            t.settings.questionSelected[q] = on
                            // The spare question may keep any value, including 0; the others need a nonzero value to count.
                            if on && q < 3 && t.settings.questionValues[q] == 0 { t.settings.questionValues[q] = [15, 10, -5][q] }
                            if let v = t.powerNegViolation() { block(v) }
                        })).labelsHidden()
                        TextField("", value: Binding(get: { t.settings.questionValues[q] }, set: { v in
                            guard v != t.settings.questionValues[q] else { return }
                            if let violation = t.questionValueChangeViolation() { block(violation); return }
                            t.settings.questionValues[q] = v
                        }), format: .number).frame(width: 60)
                        Text(["power", "tossup", "neg", "spare"][q]).foregroundStyle(.secondary).font(.caption)
                    }
                }
            }.padding(6)
        }
    }

    // MARK: Stat tracking

    private var statTracking: some View {
        GroupBox("Stat Tracking") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Track Toss-Ups Heard", isOn: Binding(get: { t.settings.trackTossupsHeard != 0 }, set: { on in
                    t.settings.trackTossupsHeard = on ? 1 : 0
                    if on && t.hasGames { block(Tournament.tossupsHeardNotice) }
                }))
                Toggle("Track Power and Neg Stats", isOn: Binding(get: { t.settings.trackPowerNeg }, set: { on in
                    t.settings.trackPowerNeg = on
                    if on, let v = t.powerNegViolation() { t.settings.trackPowerNeg = false; block(v) }
                }))
                Toggle("Track Lightning Round Stats", isOn: Binding(get: { t.settings.trackLightning }, set: { on in
                    if !on, let v = t.unselectLightningViolation() { block(v); return }
                    t.settings.trackLightning = on
                }))
                Toggle("Use Divisions", isOn: Binding(get: { t.settings.useDivisions }, set: { on in
                    if t.divisionsComeFromPools { return }
                    if on { t.settings.useDivisions = true; return }
                    let clear = {
                        t.settings.useDivisions = false
                        t.divisions = []
                        for i in t.teams.indices { t.teams[i].division = nil }
                    }
                    if t.divisions.isEmpty { clear() } else {
                        showAlert(AlertInfo(title: "Clearing 'Using Divisions' will delete any existing division information.", primary: "Clear", secondary: "Cancel", onPrimary: clear))
                    }
                })).disabled(t.divisionsComeFromPools)
            }.padding(6)
        }
    }

    private var bonusConversion: some View {
        GroupBox("Bonus Conversion Tracking") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { t.settings.bonusTracking }, set: { mode in
                    if mode == t.settings.bonusTracking { return }
                    if let v = t.bonusModeChangeViolation(to: mode) { block(v); return }
                    t.settings.bonusTracking = mode
                })) {
                    ForEach(BonusTracking.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup).labelsHidden()
                HStack {
                    Stepper(value: $t.maxPlayersPerSide, in: 1...8) { Text("max # of seats/side: \(t.maxPlayersPerSide)") }
                }
                Text("(# assigned 1 game each in new Game entry)").font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }

    private var divisionsBox: some View {
        GroupBox("Divisions") {
            VStack(alignment: .leading) {
                TextEditor(text: $divisionsText)
                    .font(.body).frame(width: 170, height: 90)
                    .disabled(!t.settings.useDivisions || t.divisionsComeFromPools)
                Button("Save Divisions") { saveDivisions() }.disabled(!t.settings.useDivisions || t.divisionsComeFromPools)
                if t.divisionsComeFromPools {
                    Text("These divisions are the pools on the Schedule tab (Teams section). Add, rename or change pools there.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(6)
        }
    }

    private func saveDivisions() {
        let names = divisionsText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let removed = t.divisions.contains { !names.contains($0) } && t.teams.contains { $0.division != nil }
        if removed {
            showAlert(AlertInfo(title: "Existing Divisions deleted. Remove deleted division names from teams?", primary: "Clear", secondary: "Cancel", onPrimary: { t.setDivisions(names) }))
        } else {
            t.setDivisions(names)
        }
    }

    // MARK: Roster

    private func playerBinding(_ team: Int, _ j: Int) -> Binding<String> {
        Binding(get: {
            guard team < t.teams.count, j < t.teams[team].players.count else { return "" }
            return t.teams[team].players[j]
        }, set: { new in
            guard team < t.teams.count else { return }
            var players = t.teams[team].players
            let old = j < players.count ? players[j] : ""
            if old == new { return }
            if t.hasGames && (old.isEmpty != new.isEmpty) {
                showAlert(AlertInfo(title: "Games have been entered. Players cannot be added or deleted.",
                                    message: "Spelling corrections are allowed."))
                return
            }
            if !new.isEmpty, let other = players.enumerated().first(where: { $0.offset != j && $0.element == new }) {
                _ = other
                showAlert(AlertInfo(title: "Player name already exists", message: "Entered name same as \(new)"))
                return
            }
            while players.count <= j { players.append("") }
            players[j] = new
            while let last = players.last, last.isEmpty { players.removeLast() }
            t.teams[team].players = players
        })
    }

    private var rosterTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { addTeam() } label: { Image(systemName: "plus") }.help("Add team")
                Button { deleteTeam() } label: { Image(systemName: "minus") }.disabled(selectedTeam == nil).help("Delete selected team")
                Spacer()
            }
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 8) {
                    // Team name, exhibition flag and division stay in view while the player columns scroll sideways.
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Button("Team name \(sortAscending ? "▲" : "▼")") { t.sortTeams(ascending: sortAscending); sortAscending.toggle() }
                                .buttonStyle(.plain).frame(width: 190, alignment: .leading).bold()
                            ExhibitionHeader().frame(width: 56)
                            if t.settings.useDivisions { Text("Division").bold().frame(width: 130, alignment: .leading) }
                        }.frame(height: rowHeight)
                        ForEach(t.teams.indices, id: \.self) { i in
                            if i < t.teams.count {
                                HStack(spacing: 6) {
                                    TextField("", text: $t.teams[i].name).frame(width: 190)
                                    Toggle("", isOn: $t.teams[i].exhibition).labelsHidden().frame(width: 56)
                                    if t.settings.useDivisions {
                                        Picker("", selection: Binding(get: { t.teams[i].division ?? -1 }, set: { t.teams[i].division = $0 < 0 ? nil : $0 })) {
                                            Text("  Select Division").tag(-1)
                                            ForEach(t.divisions.indices, id: \.self) { Text(t.divisions[$0]).tag($0) }
                                        }.labelsHidden().frame(width: 130).disabled(t.divisionsComeFromPools)
                                    }
                                }
                                .frame(height: rowHeight)
                                .background(selectedTeam == i ? Color.accentColor.opacity(0.15) : .clear)
                                .onTapGesture { selectedTeam = i }
                            }
                        }
                    }
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                ForEach(1...12, id: \.self) { Text("Player \($0)").bold().frame(width: 150, alignment: .leading) }
                            }.frame(height: rowHeight)
                            ForEach(t.teams.indices, id: \.self) { i in
                                if i < t.teams.count {
                                    HStack(spacing: 6) {
                                        ForEach(0..<12, id: \.self) { j in TextField("", text: playerBinding(i, j)).frame(width: 150) }
                                    }
                                    .frame(height: rowHeight)
                                    .background(selectedTeam == i ? Color.accentColor.opacity(0.15) : .clear)
                                    .onTapGesture { selectedTeam = i }
                                }
                            }
                        }.padding(.bottom, 8)
                    }
                }.padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
        }
    }

    private let rowHeight: CGFloat = 24

    private func addTeam() {
        t.teams.append(Team(name: ""))
        selectedTeam = t.teams.count - 1
    }

    private func deleteTeam() {
        guard let i = selectedTeam, i < t.teams.count else { return }
        if let v = t.deleteTeamViolation() { block(v); return }
        showAlert(AlertInfo(title: "Action is deleting team name", message: t.teams[i].name, primary: "Delete", secondary: "Cancel", onPrimary: {
            t.teams.remove(at: i)
            selectedTeam = nil
        }))
    }
}


/// "EXH" column heading; clicking it explains what an exhibition team is.
struct ExhibitionHeader: View {
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: 2) { Text("EXH").bold(); Image(systemName: "info.circle").font(.caption) }
        }
        .buttonStyle(.plain)
        .help("Exhibition team – click for details")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exhibition team (EXH)").font(.headline)
                Text("An exhibition team is one that plays in the tournament but is not part of the competition: a guest team, an extra squad, or a team that is just there for the experience.")
                Text("What an exhibition team does").font(.subheadline).bold()
                Text("• Plays games like any other team. Its games are recorded and appear on the scoreboard, in Game Entry and in the round report.\n• Its own record and its players' stats against the other teams are still reported.")
                Text("What it does not do").font(.subheadline).bold()
                Text("• Games against it do not count for the other teams. No win, loss or tie, no points for or against, and no toss-up or individual stats are credited to its opponents, so it cannot change anyone's standing, ranking or player stats.\n• In playoffs it is not given a seed and does not take a place in a bracket.")
                Text("Leave this unchecked for every team that is competing. That is the normal case.").foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(width: 400)
        }
    }
}
