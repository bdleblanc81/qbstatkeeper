import SwiftUI
import QBSCore

/// "Playoffs & Consolation": round plan, tiebreakers, seeds and brackets. Everything here is a director's aid;
/// the games it sets up are ordinary games in the game list and are what SQBS exports.
struct PlayoffsSheet: View {
    @Binding var t: Tournament
    @Binding var isPresented: Bool
    var showAlert: (AlertInfo) -> Void

    enum Pane: String, CaseIterable, Identifiable { case format = "Format", tiebreakers = "Tiebreakers", seeds = "Seeds", brackets = "Brackets"
        var id: String { rawValue } }
    @State private var pane: Pane

    init(t: Binding<Tournament>, isPresented: Binding<Bool>, initialPane: Pane = .format, showAlert: @escaping (AlertInfo) -> Void) {
        _t = t
        _isPresented = isPresented
        self.showAlert = showAlert
        _pane = State(initialValue: initialPane)
    }

    private var eligibleTeams: [Int] { t.teams.indices.filter { !t.teams[$0].exhibition } }
    private func name(_ i: Int?) -> String { i.flatMap { $0 < t.teams.count ? t.teams[$0].name : nil } ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playoffs & Consolation").font(.title2).bold()
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
            Picker("", selection: $pane) { ForEach(Pane.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 480)
            Group {
                switch pane {
                case .format: format
                case .tiebreakers: tiebreakers
                case .seeds: seeds
                case .brackets: brackets
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(width: 860, height: 640)
    }

    // MARK: Format

    private func numberRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).frame(width: 260, alignment: .leading)
            TextField("", value: value, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
        }
    }

    private var format: some View {
        let p = t.plus.playoffs
        let n = eligibleTeams.count
        let top = min(max(p.topBracketSize, 0), n)
        return VStack(alignment: .leading, spacing: 12) {
            GroupBox("Rounds") {
                VStack(alignment: .leading, spacing: 8) {
                    numberRow("Number of rounds in the tournament", value: Binding(get: { p.totalRounds }, set: { v in
                        t.plus.playoffs.totalRounds = min(max(v, 0), 99)
                        if t.plus.playoffs.playoffRounds > t.plus.playoffs.totalRounds { t.plus.playoffs.playoffRounds = t.plus.playoffs.totalRounds }
                    }))
                    numberRow("Number of playoff rounds", value: Binding(get: { p.playoffRounds }, set: { v in
                        t.plus.playoffs.playoffRounds = min(max(v, 0), max(t.plus.playoffs.totalRounds, 0))
                    }))
                    numberRow("Teams in the top bracket", value: Binding(get: { p.topBracketSize }, set: { v in
                        t.plus.playoffs.topBracketSize = min(max(v, 0), n)
                    }))
                    Text("The round counts are shared with the Schedule tab.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Include a third-place game (losers of the top-bracket semifinals)", isOn: $t.plus.playoffs.thirdPlaceGame)
                        .disabled(top < 4)
                    Toggle("Pool play: top teams from each pool play a top bracket; the rest play cross-pool games", isOn: $t.plus.playoffs.poolPlayoffs)
                        .disabled(t.divisions.count < 2 || !t.settings.useDivisions)
                        .help("Needs at least two pools (divisions). Seeds alternate between the pools: A1, B1, A2, B2, … (A1, B1, C1, A2, … with three pools).")
                    if t.plus.playoffs.poolPlayoffs {
                        numberRow("Teams advancing from each pool", value: Binding(get: { p.advancePerPool }, set: { v in
                            t.plus.playoffs.advancePerPool = min(max(v, 1), 8)
                        }))
                        numberRow("Wild card teams (best of the rest)", value: Binding(get: { p.wildCards }, set: { v in
                            t.plus.playoffs.wildCards = min(max(v, 0), max(n - min(max(p.advancePerPool, 1), 8) * max(t.divisions.count, 1), 0))
                        }))
                    } else if t.divisions.count < 2 || !t.settings.useDivisions {
                        Text("Pool play needs at least two pools: give teams a Pool on the Schedule tab and link them to the roster.").font(.caption).foregroundStyle(.secondary)
                    }
                    if p.playoffRounds > p.totalRounds && p.totalRounds > 0 {
                        Text("There can't be more playoff rounds than rounds.").foregroundStyle(.red).font(.callout)
                    }
                    if p.playoffStartRound > 0 {
                        Text("Preliminary rounds: 1–\(p.playoffStartRound - 1)   •   Playoff rounds: \(p.playoffStartRound)–\(p.totalRounds)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Enter the number of rounds and how many of them are playoff rounds.").foregroundStyle(.secondary).font(.callout)
                    }
                    if t.usesPoolSeeding {
                        let adv = min(max(p.advancePerPool, 1), 8)
                        let wild = max(p.wildCards, 0)
                        Text("The top \(adv) team\(adv == 1 ? "" : "s") in each of the \(t.divisions.count) pools" + (wild > 0 ? ", plus \(wild) wild card\(wild == 1 ? "" : "s") (the best remaining team\(wild == 1 ? "" : "s") by record, from any pool)," : "") + " go to the top bracket (\(adv * t.divisions.count + wild) teams), arranged so pool-mates avoid each other in the first round. Everyone else plays cross-pool games in each playoff round, never against a teammate from their pool or a repeat opponent. Exhibition teams are not seeded.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        Text("\(top) team\(top == 1 ? "" : "s") go to the top bracket; the remaining \(n - top) play in consolation games. Exhibition teams are not seeded.")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                }.padding(8)
            }
            GroupBox("Standings") {
                Toggle("Use the tiebreakers (Tiebreakers tab) to order team standings, reports and seeds", isOn: $t.plus.playoffs.useTiebreakers).padding(8)
            }
            Button("Generate Brackets…") {
                let apply = { t.generateDefaultBrackets() }
                if t.plus.playoffs.brackets.isEmpty { apply() } else {
                    showAlert(AlertInfo(title: "Replace the existing brackets?", message: "Games already created in the game list are kept.", primary: "Replace", secondary: "Cancel", onPrimary: apply))
                }
            }.disabled(p.playoffStartRound == 0 || top < 0)
            Text(t.usesPoolSeeding
                 ? "Creates a single-elimination top bracket from the best of each pool and cross-pool consolation games for the rest, one set in each playoff round. Games get IDs in the form {round}-{game}. Edit the games on the Brackets tab."
                 : "Creates a single-elimination top bracket for seeds 1–\(top) and a single-elimination consolation bracket for the rest, with byes where the field is not a power of two. Games get IDs in the form {round}-{game}. Edit the games on the Brackets tab.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Tiebreakers

    private var tiebreakers: some View {
        let ranked = t.rankTeams(filter: nil)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Order of tiebreakers (after win percentage)").font(.headline)
                ForEach(Array(t.plus.playoffs.tiebreakers.enumerated()), id: \.element.id) { i, option in
                    HStack {
                        Toggle("", isOn: $t.plus.playoffs.tiebreakers[i].enabled).labelsHidden()
                        Text("\(i + 1).").monospacedDigit()
                        Text(option.kind.title).frame(width: 330, alignment: .leading)
                        Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                        Button { move(i, +1) } label: { Image(systemName: "chevron.down") }.disabled(i == t.plus.playoffs.tiebreakers.count - 1)
                    }
                }
                Toggle("After a tiebreaker splits a group, start over from the first tiebreaker for each smaller group", isOn: $t.plus.playoffs.restartAfterSplit)
                    .font(.callout)
                Text("Uncheck a tiebreaker to skip it. The coin flip can sit anywhere in the order: when teams are still tied at that point it uses the order you enter at right; if no order is entered it does not break the tie.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                let unresolved = ranked.filter(\.unresolvedTie)
                if !unresolved.isEmpty {
                    Text("Still tied after the enabled tiebreakers: " + unresolved.map { name($0.teamIndex) }.joined(separator: ", "))
                        .foregroundStyle(.orange).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Coin flip order").font(.headline)
                Text("1 = wins the flip. Leave blank for teams that did not flip.").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow { Text("Rank").bold(); Text("Team").bold(); Text("Flip").bold() }
                        ForEach(ranked, id: \.teamIndex) { r in
                            GridRow {
                                Text("\(r.rank)\(r.unresolvedTie ? "*" : "")")
                                Text(name(r.teamIndex)).frame(width: 190, alignment: .leading)
                                TextField("", value: coinBinding(r.teamIndex), format: .number).frame(width: 44)
                            }
                        }
                    }
                }.frame(maxHeight: 420)
            }
        }
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard j >= 0, j < t.plus.playoffs.tiebreakers.count else { return }
        t.plus.playoffs.tiebreakers.swapAt(i, j)
    }

    private func coinBinding(_ team: Int) -> Binding<Int?> {
        Binding(get: { t.plus.playoffs.coinFlipOrder[team] }, set: { new in
            if let v = new, v > 0 { t.plus.playoffs.coinFlipOrder[team] = v } else { t.plus.playoffs.coinFlipOrder[team] = nil }
        })
    }

    // MARK: Seeds

    private var seeds: some View {
        let order = t.seedOrder()
        let ranked = Dictionary(uniqueKeysWithValues: t.rankTeams(filter: nil).map { ($0.teamIndex, $0) })
        let standings = Dictionary(uniqueKeysWithValues: t.teamStandings(filter: t.preliminaryFilter).map { ($0.teamIndex, $0) })
        let manual = t.plus.playoffs.manualSeeds != nil
        let x = t.plus.playoffs.topBracketSize
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(manual ? "Seeds set by hand." : "Seeds follow the standings" + (t.plus.playoffs.playoffStartRound > 1 ? " through round \(t.plus.playoffs.playoffStartRound - 1)." : "."))
                Spacer()
                Button("Use Standings Order") { t.plus.playoffs.manualSeeds = nil }.disabled(!manual)
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Seed").bold(); Text("Team").bold(); Text("W-L-T").bold(); Text("Bracket").bold(); Text("Note").bold() }
                    ForEach(Array(order.enumerated()), id: \.offset) { i, team in
                        if !t.teams[team].exhibition || true {
                            GridRow {
                                Text("\(i + 1)").monospacedDigit()
                                Picker("", selection: Binding(get: { team }, set: { new in setSeed(i, to: new, current: order) })) {
                                    ForEach(eligibleTeams, id: \.self) { Text(name($0)).tag($0) }
                                }.labelsHidden().frame(width: 240)
                                Text(standings[team].map { "\($0.win + $0.forfeitWin)-\($0.loss + $0.forfeitLoss)-\($0.tie)" } ?? "")
                                Text(x > 0 ? (i < x ? "Top" : "Consolation") : "")
                                Text(ranked[team]?.unresolvedTie == true ? "tied – needs a tiebreaker" : (ranked[team]?.decidedBy.map { "by " + shortName($0) } ?? ""))
                                    .foregroundStyle(.secondary).font(.callout)
                            }
                        }
                    }
                }.padding(4)
            }
            .background(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
        }
    }

    private func shortName(_ k: TiebreakerKind) -> String {
        switch k { case .headToHead: return "head-to-head"; case .teamPointsPer20: return "team pts/20 TUH"; case .topIndividualPer20: return "top individual pts/20 TUH"; case .coinFlip: return "coin flip" }
    }

    /// Picking a team for a seed swaps it with the team that held that seed.
    private func setSeed(_ index: Int, to team: Int, current: [Int]) {
        var order = current
        if let other = order.firstIndex(of: team) { order.swapAt(index, other) } else { order[index] = team }
        t.plus.playoffs.manualSeeds = order
    }

    // MARK: Brackets

    private func slotChoices(excluding gameID: String) -> [(key: String, label: String)] {
        var out: [(String, String)] = []
        for (i, team) in t.seedOrder().enumerated() { out.append(("seed:\(i + 1)", "Seed \(i + 1) – \(name(team))")) }
        for b in t.plus.playoffs.brackets {
            for g in b.games where g.id != gameID {
                out.append(("winner:\(g.id)", "Winner of \(g.id)"))
                out.append(("loser:\(g.id)", "Loser of \(g.id)"))
            }
        }
        for i in eligibleTeams { out.append(("team:\(i)", "Team – \(name(i))")) }
        out.append(("bye", "Bye"))
        return out
    }

    private var brackets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Assign Teams & Create Games") { assign() }.disabled(t.plus.playoffs.brackets.isEmpty)
                Button("Add Bracket") {
                    let n = t.plus.playoffs.brackets.count + 1
                    t.plus.playoffs.brackets.append(Bracket(id: "B\(n)", name: "Bracket \(n)"))
                }
                Spacer()
                Text("\(t.placeholderCount) set up, not yet played").foregroundStyle(.secondary).font(.callout)
            }
            Text("Seeds fill the first games; winners and losers feed the games you point them at. A game appears in Game Entry (with its round and teams filled in) as soon as both teams are known, and counts once you enter its score.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(t.plus.playoffs.brackets.indices, id: \.self) { bi in
                        if bi < t.plus.playoffs.brackets.count { bracketBox(bi) }
                    }
                }
            }
        }
    }

    private func bracketBox(_ bi: Int) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Name", text: $t.plus.playoffs.brackets[bi].name).frame(width: 200).font(.headline)
                    Spacer()
                    Button("Add Game") {
                        let b = t.plus.playoffs.brackets[bi]
                        let round = max(b.games.map(\.round).max() ?? t.plus.playoffs.playoffStartRound, 1)
                        t.plus.playoffs.brackets[bi].games.append(BracketGame(id: t.nextGameID(round: round), round: round, a: .bye, b: .bye))
                    }
                    Button { t.plus.playoffs.brackets.remove(at: bi) } label: { Image(systemName: "trash") }.help("Delete bracket")
                }
                ForEach(t.plus.playoffs.brackets[bi].games.indices, id: \.self) { gi in
                    if gi < t.plus.playoffs.brackets[bi].games.count { gameRow(bi, gi) }
                }
            }.padding(6)
        }
    }

    private func gameRow(_ bi: Int, _ gi: Int) -> some View {
        let g = t.plus.playoffs.brackets[bi].games[gi]
        let a = t.resolve(slot: g.a), b = t.resolve(slot: g.b)
        let result = t.winnerAndLoser(ofGameID: g.id)
        return HStack(spacing: 8) {
            TextField("", text: Binding(get: { g.id }, set: { rename(bi, gi, to: $0) })).frame(width: 64)
            Stepper("Rd \(g.round)", value: $t.plus.playoffs.brackets[bi].games[gi].round, in: 1...60).frame(width: 90)
            slotPicker(g.a, game: g.id) { t.plus.playoffs.brackets[bi].games[gi].a = $0 }
            Text("vs")
            slotPicker(g.b, game: g.id) { t.plus.playoffs.brackets[bi].games[gi].b = $0 }
            Text(result.map { "✓ \(name($0.winner)) won" } ?? ((a != nil && b != nil) ? "\(name(a)) v \(name(b))" : "waiting"))
                .font(.callout).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
            Button { t.plus.playoffs.brackets[bi].games.remove(at: gi) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
        }
    }

    private func slotPicker(_ slot: BracketSlot, game: String, set: @escaping (BracketSlot) -> Void) -> some View {
        let choices = slotChoices(excluding: game)
        return Picker("", selection: Binding(get: { slot.storageKey }, set: { set(BracketSlot(storageKey: $0)) })) {
            if !choices.contains(where: { $0.key == slot.storageKey }) { Text(slot.storageKey).tag(slot.storageKey) }
            ForEach(choices, id: \.key) { Text($0.label).tag($0.key) }
        }.labelsHidden().frame(width: 210)
    }

    /// Renames a bracket game and every slot and game-list entry that refers to it.
    private func rename(_ bi: Int, _ gi: Int, to new: String) {
        let old = t.plus.playoffs.brackets[bi].games[gi].id
        let clean = new.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != old, !t.plus.playoffs.brackets.contains(where: { $0.games.contains { $0.id == clean } }) else { return }
        for b in t.plus.playoffs.brackets.indices {
            for g in t.plus.playoffs.brackets[b].games.indices {
                if t.plus.playoffs.brackets[b].games[g].id == old { t.plus.playoffs.brackets[b].games[g].id = clean }
                for keyPath in [\BracketGame.a, \BracketGame.b] {
                    switch t.plus.playoffs.brackets[b].games[g][keyPath: keyPath] {
                    case .winner(let id) where id == old: t.plus.playoffs.brackets[b].games[g][keyPath: keyPath] = .winner(clean)
                    case .loser(let id) where id == old: t.plus.playoffs.brackets[b].games[g][keyPath: keyPath] = .loser(clean)
                    default: break
                    }
                }
            }
        }
        if let i = t.games.firstIndex(where: { $0.id == old }) { t.games[i].id = clean }
    }

    private func assign() {
        let made = t.syncPlayoffGames()
        showAlert(AlertInfo(title: made.isEmpty ? "No new games to create." : "Created \(made.count) game\(made.count == 1 ? "" : "s").",
                            message: made.isEmpty ? "Games appear here once both teams are known." : made.joined(separator: ", ") + "\n\nThey are in the game list with their rounds and teams filled in."))
    }
}
