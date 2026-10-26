import SwiftUI
import AppKit
import QBSCore

struct GameEntryView: View {
    @Binding var t: Tournament
    var showAlert: (AlertInfo) -> Void

    @State private var index = 0
    @State private var draft = Game(id: "0", teamA: -1, teamB: -1, scoreA: "", scoreB: "")
    @State private var gotoText = ""
    @State private var loaded = false

    private var s: TournamentSettings { t.settings }
    private var forfeit: Bool { draft.forfeit != 0 }

    // MARK: Sizing
    // Names vary in length, so each panel is as wide as its longest player name (and the team pop-ups as wide as the
    // longest team name). If the window is still narrower than that, the screen scrolls sideways instead of clipping.

    private func textWidth(_ s: String) -> CGFloat {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).size().width
    }

    private func roster(_ isA: Bool) -> [String] {
        let team = isA ? draft.teamA : draft.teamB
        return team >= 0 && team < t.teams.count ? t.teams[team].players : []
    }

    @State private var availWidth: CGFloat = 1320

    /// Width a name pop-up wants so its longest name is not cut off.
    private func naturalPlayerPicker(_ isA: Bool) -> CGFloat {
        min(max((roster(isA).map(textWidth).max() ?? 0) + 46, max(textWidth("  Select Player") + 46, 170)), 460)
    }

    /// Everything in a panel that is not the player pop-up: GP, count and points columns plus padding.
    private func panelChrome() -> CGFloat {
        let columns = 1 + s.questionSelected.filter { $0 }.count
        return CGFloat(columns) * 46 + 40 + 6 * 8 + 28
    }

    /// Player pop-ups use their natural width, shrinking (never below 140) only when the window is too narrow.
    private func playerPickerWidth(_ isA: Bool) -> CGFloat {
        let natA = naturalPlayerPicker(true), natB = naturalPlayerPicker(false)
        let total = natA + natB + 2 * panelChrome() + 12 + 24
        let nat = isA ? natA : natB
        guard availWidth < total else { return nat }
        // Squeeze the longer list first; only when both are equal squeeze them together.
        let excess = total - availWidth
        let diff = abs(natA - natB)
        var a = natA, b = natB
        if excess <= diff {
            if natA > natB { a -= excess } else { b -= excess }
        } else {
            let shared = min(natA, natB) - (excess - diff) / 2
            a = shared; b = shared
        }
        return max(140, isA ? a : b)
    }

    private var teamPickerWidth: CGFloat {
        let natural = min(max((t.teams.map { textWidth($0.name) }.max() ?? 0) + 46, 180), 460)
        let room = (min(panelWidth(true), panelWidth(false))) - 200
        return max(150, min(natural, room))
    }

    private func panelWidth(_ isA: Bool) -> CGFloat {
        let grid = playerPickerWidth(isA) + panelChrome() - 28
        return max(grid, 380) + 28
    }

    private var contentWidth: CGFloat { panelWidth(true) + panelWidth(false) + 12 + 24 }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 10) {
                topBar
                HStack(alignment: .top, spacing: 12) {
                    teamPanel(isA: true).frame(width: panelWidth(true), alignment: .leading)
                    teamPanel(isA: false).frame(width: panelWidth(false), alignment: .leading)
                }
                bottomBar
            }
            .padding(12)
            .frame(minWidth: contentWidth, alignment: .leading)
        }
        .background(GeometryReader { g in
            Color.clear.onAppear { availWidth = g.size.width }.onChange(of: g.size.width) { availWidth = $0 }
        })
        .onAppear {
            guard !loaded else { return }
            loaded = true
            // start at the first game with nothing entered; if every game has results, at a new blank game
            load(t.firstUnenteredGameIndex() ?? t.games.count)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gamesSorted)) { _ in load(0) }
        .onChange(of: draft.round) { round in
            // A new game keeps the {round}-{game} ID format when its round is edited.
            if index >= t.games.count, round > 0, draft.id.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil {
                draft.id = t.nextGameID(round: round)
            }
        }
    }

    // MARK: Top and bottom bars

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Go to game:")
            TextField("", text: $gotoText, onCommit: gotoGame).frame(width: 70).keyOrder(0, 0, 0)
            VStack(spacing: 0) {
                Button { step(+1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                Button { step(-1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
            }
            Text("\(index + 1) / \(max(t.games.count, index + 1))").monospacedDigit()   // game position, counted from 1; a game not yet saved counts too
            if s.trackTossupsHeard != 0 && !forfeit {
                Divider().frame(height: 18)
                Text("Toss-Ups Heard:")
                TextField("", value: Binding(get: { draft.tossupsHeard }, set: { setTossupsHeard($0) }), format: .number)
                    .frame(width: 56).keyOrder(0, 0, 1)
                    .help("Toss-ups heard in this game. Players start with this many; change a player's TUH below if they heard fewer.")
            }
            Spacer()
            Button("Enter New Game") { enterNewGame() }.help("Save this game and start a new one in the same round")
            Button("Start New Round") { startNewRound() }.help("Save this game and start the next round")
            Button("Team Swap") { swapSides() }
            Button("Save") { record() }.keyboardShortcut(.defaultAction)
            Button("Delete") { deleteGame() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            HStack { Text("Rnd"); TextField("", value: $draft.round, format: .number).frame(width: 50).keyOrder(4, 0, 0) }
            HStack { Text("Id"); TextField("", text: $draft.id).frame(width: 80).keyOrder(4, 0, 1) }
            if !forfeit { Toggle("Overtime", isOn: Binding(get: { draft.isOvertime }, set: setOvertime)).keyOrder(4, 0, 3) }
            Toggle("Forfeit", isOn: Binding(get: { forfeit }, set: { setForfeit($0) })).keyOrder(4, 0, 4)
            Spacer()
        }.disabled(draft.teamA < 0 && draft.teamB < 0 && false)
    }

    // MARK: Team panel

    private func teamIndexBinding(_ isA: Bool) -> Binding<Int> {
        Binding(get: { isA ? draft.teamA : draft.teamB }, set: { new in
            if isA { draft.teamA = new; draft.playersA = t.defaultPlayerLines(forTeam: new, beforeRound: draft.round, excludingGame: index) }
            else { draft.teamB = new; draft.playersB = t.defaultPlayerLines(forTeam: new, beforeRound: draft.round, excludingGame: index) }
            recalc()
        })
    }

    private func sortedTeamIndices(excluding other: Int) -> [Int] {
        t.teams.indices.filter { $0 != other || other < 0 }.sorted {
            t.teams[$0].name.localizedCaseInsensitiveCompare(t.teams[$1].name) == .orderedAscending
        }
    }

    private func teamPanel(isA: Bool) -> some View {
        let team = isA ? draft.teamA : draft.teamB
        let other = isA ? draft.teamB : draft.teamA
        let roster = team >= 0 && team < t.teams.count ? t.teams[team].players : []
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("", selection: teamIndexBinding(isA)) {
                        Text("  Select Team").tag(-1)
                        ForEach(sortedTeamIndices(excluding: other), id: \.self) { Text(t.teams[$0].name).tag($0) }
                    }.labelsHidden().frame(width: teamPickerWidth).keyOrder(1, 0, isA ? 0 : 2)
                    Spacer()
                    if forfeit {
                        Text("Forfeit result")
                        Picker("", selection: Binding(get: { isA == (draft.forfeit != 2) }, set: { wins in draft.forfeit = (wins == isA) ? 1 : 2 })) {
                            Text("Win").tag(true)
                            Text("Loss").tag(false)
                        }.labelsHidden().frame(width: 90).keyOrder(1, 0, isA ? 1 : 3)
                    } else {
                        Text("Team's score")
                        TextField("", text: Binding(get: { isA ? draft.scoreA : draft.scoreB }, set: { if isA { draft.scoreA = $0 } else { draft.scoreB = $0 }; recalc() })).frame(width: 60).keyOrder(1, 0, isA ? 1 : 3)
                    }
                }
                if !forfeit && team >= 0 {
                    playerGrid(isA: isA, roster: roster)
                    ForEach(t.sideErrors(for: draft, isA: isA), id: \.self) { problem in
                        Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    sideBoxes(isA: isA)
                }
            }.padding(6)
        }
    }

    private func playerGrid(isA: Bool, roster: [String]) -> some View {
        let rows = min(Game.slotsPerSide, roster.count)
        return Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
            GridRow {
                Text("Player").bold()
                Text(s.trackTossupsHeard != 0 ? "TUH" : "GP").bold()
                ForEach(0..<4, id: \.self) { j in if s.questionSelected[j] { Text("\(s.questionValues[j])").bold() } }
                Text("pts").bold()
            }.font(.caption)
            ForEach(0..<rows, id: \.self) { slot in
                GridRow {
                    Picker("", selection: Binding(get: { line(isA, slot)?.rosterIndex ?? -1 }, set: { new in
                        setLine(isA, slot, new < 0 ? nil : PlayerLine(rosterIndex: new, gp: "1")); recalc()
                    })) {
                        Text("  Select Player").tag(-1)
                        ForEach(roster.indices, id: \.self) { Text(roster[$0]).tag($0) }
                    }.labelsHidden().frame(width: playerPickerWidth(isA)).keyOrder(isA ? 2 : 3, 1 + slot, 0)
                    if s.trackTossupsHeard != 0 {
                        TextField("", value: Binding(get: { playerTUH(isA, slot) }, set: { setPlayerTUH(isA, slot, $0) }), format: .number)
                            .frame(width: 46).disabled(line(isA, slot) == nil).keyOrder(isA ? 2 : 3, 1 + slot, 1)
                    } else {
                        TextField("", text: Binding(get: { line(isA, slot)?.gp ?? "" }, set: { mutate(isA, slot) { $0.gp = $1 }($0) }), onCommit: {
                            mutate(isA, slot) { $0.gp = Tournament.normalizedGamesPlayed($0.gp) }(())
                            recalc()
                        }).frame(width: 46).disabled(line(isA, slot) == nil).keyOrder(isA ? 2 : 3, 1 + slot, 1)
                    }
                    ForEach(0..<4, id: \.self) { j in
                        if s.questionSelected[j] {
                            TextField("", value: countBinding(isA, slot, j), format: .number).frame(width: 40).keyOrder(isA ? 2 : 3, 1 + slot, 2 + j)
                                .disabled(line(isA, slot) == nil)   // stays enabled at 0 TUH so Tab reaches a player whose TUH is being entered
                        }
                    }
                    Text("\(line(isA, slot)?.points ?? 0)").frame(width: 40, alignment: .trailing).monospacedDigit()
                }
            }
        }
    }

    private func sideBoxes(isA: Bool) -> some View {
        let mode = s.bonusTracking
        let heardEditable = [BonusTracking.manual, .manualHeardAutoPoints, .manualWithBouncebacks].contains(mode)
        let pointsEditable = [BonusTracking.manual, .manualWithBouncebacks, .autoWithBouncebacks].contains(mode)
        let bbEditable = mode == .manualWithBouncebacks
        func num(_ label: String, _ row: Int, _ col: Int, _ get: @escaping () -> Int, _ set: @escaping (Int) -> Void, editable: Bool = true) -> some View {
            HStack(spacing: 4) {
                Text(label).font(.caption)
                TextField("", value: Binding(get: get, set: { set($0); recalc() }), format: .number).frame(width: 52).disabled(!editable)
                    .keyOrder(isA ? 2 : 3, row, col)
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            if s.trackLightning {
                num("Ltng Points", 20, 0, { isA ? draft.lightningA : draft.lightningB }, { if isA { draft.lightningA = $0 } else { draft.lightningB = $0 } })
            }
            if s.bonusTracking != .none {
                HStack(spacing: 10) {
                    Text("Bonus").bold().font(.caption)
                    num("Heard", 21, 0, { isA ? draft.bonusHeardA : draft.bonusHeardB }, { if isA { draft.bonusHeardA = $0 } else { draft.bonusHeardB = $0 } }, editable: heardEditable)
                    num("Points", 21, 1, { isA ? draft.bonusPointsA : draft.bonusPointsB }, { if isA { draft.bonusPointsA = $0 } else { draft.bonusPointsB = $0 } }, editable: pointsEditable)
                }
                if mode.hasBouncebacks {
                    HStack(spacing: 10) {
                        Text("Bouncebacks").bold().font(.caption)
                        num("Heard", 22, 0, { isA ? draft.bouncebackHeardA : draft.bouncebackHeardB }, { if isA { draft.bouncebackHeardA = $0 } else { draft.bouncebackHeardB = $0 } }, editable: bbEditable)
                        num("Points", 22, 1, { isA ? draft.bouncebackPointsA : draft.bouncebackPointsB }, { if isA { draft.bouncebackPointsA = $0 } else { draft.bouncebackPointsB = $0 } }, editable: bbEditable)
                    }
                }
            }
            if draft.isOvertime {
                num("Overtime Gets", 23, 0, { isA ? draft.overtimeGetsA : draft.overtimeGetsB }, { if isA { draft.overtimeGetsA = $0 } else { draft.overtimeGetsB = $0 } })
            }
        }
    }

    // MARK: Player-line helpers

    private func line(_ isA: Bool, _ slot: Int) -> PlayerLine? { isA ? draft.playersA[slot] : draft.playersB[slot] }

    private func setLine(_ isA: Bool, _ slot: Int, _ new: PlayerLine?) {
        if isA { draft.playersA[slot] = new } else { draft.playersB[slot] = new }
    }

    /// Returns a closure that applies `change` with a value to the slot's line.
    private func mutate(_ isA: Bool, _ slot: Int, _ change: @escaping (inout PlayerLine, String) -> Void) -> (String) -> Void {
        { value in
            guard var l = line(isA, slot) else { return }
            change(&l, value)
            setLine(isA, slot, l)
        }
    }

    private func mutate(_ isA: Bool, _ slot: Int, _ change: @escaping (inout PlayerLine) -> Void) -> (Void) -> Void {
        { _ in
            guard var l = line(isA, slot) else { return }
            change(&l)
            setLine(isA, slot, l)
        }
    }

    private func countBinding(_ isA: Bool, _ slot: Int, _ j: Int) -> Binding<Int> {
        Binding(get: { line(isA, slot)?.counts[j] ?? 0 }, set: { new in
            guard var l = line(isA, slot) else { return }
            l.counts[j] = max(0, new)
            l.points = l.computedPoints(values: s.questionValues)
            setLine(isA, slot, l)
            recalc()
        })
    }

    private func recalc() { t.applyBonusCalculation(to: &draft) }

    // MARK: Forfeit

    private var hasEnteredData: Bool {
        if !draft.scoreA.isEmpty || !draft.scoreB.isEmpty || draft.tossupsHeard > 0 || draft.isOvertime { return true }
        if draft.lightningA != 0 || draft.lightningB != 0 || draft.bonusHeardA != 0 || draft.bonusHeardB != 0
            || draft.bonusPointsA != 0 || draft.bonusPointsB != 0 { return true }
        return (draft.playersA + draft.playersB).compactMap { $0 }.contains { $0.counts.contains { $0 != 0 } }
    }

    /// Checking Forfeit wipes the game (scores, players, counts, overtime) and leaves only who won; clearing it
    /// brings back a blank game with each team's usual lineup.
    private func setForfeit(_ on: Bool) {
        if on {
            let apply = {
                let keep = draft
                draft = Game(id: keep.id, teamA: keep.teamA, teamB: keep.teamB, scoreA: "", scoreB: "", tossupsHeard: 0, round: keep.round)
                draft.forfeit = 1
            }
            if hasEnteredData {
                showAlert(AlertInfo(title: "Forfeit this game?",
                                    message: "The scores, players and counts entered for this game will be cleared.",
                                    primary: "Clear and Forfeit", secondary: "Cancel", onPrimary: apply))
            } else { apply() }
        } else {
            draft.forfeit = 0
            if draft.teamA >= 0 { draft.playersA = t.defaultPlayerLines(forTeam: draft.teamA, beforeRound: draft.round, excludingGame: index) }
            if draft.teamB >= 0 { draft.playersB = t.defaultPlayerLines(forTeam: draft.teamB, beforeRound: draft.round, excludingGame: index) }
        }
    }

    // MARK: Toss-ups heard
    // A player's games-played value is stored as a fraction of the game (that is what the .sqbs file keeps);
    // the screen shows it as toss-ups heard, which is that fraction times the game's toss-ups heard.

    private func playerTUH(_ isA: Bool, _ slot: Int) -> Int {
        guard let l = line(isA, slot) else { return 0 }
        return Int((Tournament.roundedGP(l.gp) * Float(max(draft.tossupsHeard, 0))).rounded())
    }

    private func setPlayerTUH(_ isA: Bool, _ slot: Int, _ value: Int) {
        guard var l = line(isA, slot) else { return }
        let game = draft.tossupsHeard
        let v = min(max(value, 0), max(game, 0))
        if game <= 0 { l.gp = value > 0 ? "1" : "0" }
        else if v == game { l.gp = "1" }
        else { l.gp = Tournament.normalizedGamesPlayed("\(v)/\(game)") }
        setLine(isA, slot, l)
        recalc()
    }

    /// Entering the game's toss-ups heard fills every player in: the first `maxPlayersPerSide` hear all of them
    /// and anyone beyond that did not play. After that, players keep the share of the game they had.
    private func setTossupsHeard(_ new: Int) {
        let first = draft.tossupsHeard <= 0
        draft.tossupsHeard = new
        if first && new > 0 {
            let limit = t.maxPlayersPerSide
            for isA in [true, false] {
                var kept = 0
                for slot in 0..<Game.slotsPerSide {
                    guard var l = line(isA, slot) else { continue }
                    if Tournament.roundedGP(l.gp) > 0 && kept < limit { l.gp = "1"; kept += 1 } else { l.gp = "0" }
                    setLine(isA, slot, l)
                }
            }
        }
        recalc()
    }

    // MARK: Overtime / swap

    private func setOvertime(_ on: Bool) {
        if on { draft.overtime = 1; recalc(); return }
        if draft.overtimeGetsA != 0 || draft.overtimeGetsB != 0 {
            showAlert(AlertInfo(title: "Clearing 'overtime' will delete any existing overtime information. Continue?", primary: "Clear Overtime", secondary: "Cancel", onPrimary: {
                draft.overtime = 0; draft.overtimeGetsA = 0; draft.overtimeGetsB = 0; recalc()
            }))
        } else { draft.overtime = 0; recalc() }
    }

    private func swapSides() {
        let a = draft.teamA, b = draft.teamB
        let id = draft.id, round = draft.round
        let wasForfeit = draft.forfeit
        draft = Game(id: id, teamA: b, teamB: a, scoreA: "", scoreB: "", tossupsHeard: 0, round: round)
        if wasForfeit != 0 {
            draft.forfeit = wasForfeit == 2 ? 1 : 2   // the winner moves to the other side with its team
            return
        }
        draft.playersA = t.defaultPlayerLines(forTeam: b, beforeRound: round, excludingGame: index)
        draft.playersB = t.defaultPlayerLines(forTeam: a, beforeRound: round, excludingGame: index)
    }

    // MARK: Loading and saving

    /// The round the game in view belongs to (a new tournament starts in round 1).
    private var currentRound: Int { draft.round > 0 ? draft.round : max(t.games.last?.round ?? 1, 1) }

    private func blankDraft(round: Int? = nil) -> Game {
        let r = round ?? currentRound
        return Game(id: t.nextGameID(round: r), teamA: -1, teamB: -1, scoreA: "", scoreB: "", tossupsHeard: 0, round: r)
    }

    private func startBlank(round: Int) {
        index = t.games.count
        draft = blankDraft(round: round)
    }

    /// Saves the game in view, then moves to the next predetermined game of a playoff round if one is waiting,
    /// otherwise to a new game with a new unique ID in the same round.
    private func enterNewGame() {
        record {
            let round = currentRoundAfterSave
            if t.isPlayoffRound(round), let i = t.firstPlaceholderIndex(inRound: round) { load(i) } else { startBlank(round: round) }
        }
    }

    private var currentRoundAfterSave: Int { index < t.games.count ? t.games[index].round : currentRound }

    /// Saves the game in view and starts the next round, after checking the round that is ending.
    private func startNewRound() {
        record {
            let round = currentRoundAfterSave
            let next = round + 1
            let proceed = {
                t.syncPlayoffGames()
                if let i = t.firstPlaceholderIndex(inRound: next) { load(i) } else { startBlank(round: next) }
            }
            if t.isPlayoffRound(round) {
                let missing = t.unscoredBracketGames(inRound: round)
                if !missing.isEmpty {
                    let lines = missing.map { bg -> String in
                        let a = t.resolve(slot: bg.a).map { t.teams[$0].name } ?? "TBD"
                        let b = t.resolve(slot: bg.b).map { t.teams[$0].name } ?? "TBD"
                        return "Game \(bg.id): \(a) vs \(b)"
                    }
                    showAlert(AlertInfo(title: "Not every playoff game in round \(round) has a score entered.",
                                        message: lines.joined(separator: "\n") + "\n\nStart round \(next) anyway?",
                                        primary: "Start New Round Anyway", secondary: "Cancel", onPrimary: proceed))
                    return
                }
                proceed()
            } else {
                let missing = t.teamsWithoutGame(inRound: round)
                if missing.isEmpty { proceed(); return }
                showAlert(AlertInfo(title: "Start round \(next) even though some teams have no game recorded in round \(round)?",
                                    message: "No game is recorded in round \(round) for:\n" + missing.map { t.teams[$0].name }.joined(separator: "\n"),
                                    primary: "Start New Round", secondary: "Cancel", onPrimary: proceed))
            }
        }
    }

    private func display(_ g: Game) -> Game {
        var d = g
        if d.isForfeit { d.scoreA = ""; d.scoreB = ""; d.forfeit = 1 }
        if NS.int(d.scoreA) == -1 && d.scoreA == "-1" { d.scoreA = "" }
        if NS.int(d.scoreB) == -1 && d.scoreB == "-1" { d.scoreB = "" }
        return d
    }

    private func load(_ i: Int) {
        if i >= 0 && i < t.games.count {
            index = i; draft = display(t.games[i])
            // a scheduled game nobody has started: use today's rosters and each team's latest lineup
            if t.isPlaceholder(t.games[i]) && draft.tossupsHeard == 0 && !hasEnteredData {
                if draft.teamA >= 0 { draft.playersA = t.defaultPlayerLines(forTeam: draft.teamA, beforeRound: draft.round, excludingGame: i) }
                if draft.teamB >= 0 { draft.playersB = t.defaultPlayerLines(forTeam: draft.teamB, beforeRound: draft.round, excludingGame: i) }
            }
        }
        else { index = t.games.count; draft = blankDraft() }
    }

    private func normalized() -> Game {
        var g = draft
        if g.isForfeit {
            // a forfeit is stored with the winner as team A, whichever side it was entered on
            let bWins = draft.forfeit == 2
            g = Game(id: draft.id, teamA: bWins ? draft.teamB : draft.teamA, teamB: bWins ? draft.teamA : draft.teamB,
                     scoreA: "W", scoreB: "L", tossupsHeard: 0, round: draft.round)
            g.forfeit = 1
        } else {
            if g.scoreA.isEmpty { g.scoreA = "-1" }
            if g.scoreB.isEmpty { g.scoreB = "-1" }
            g.round = max(0, g.round)
        }
        return g
    }

    private func commit() {
        let g = normalized()
        if index < t.games.count { t.games[index] = g } else { t.games.append(g); index = t.games.count - 1 }
        draft = display(g)
    }

    /// Validates and stores the current game; `then` runs once it is stored (or when there was nothing to store).
    private func record(then: @escaping () -> Void = {}) {
        if draft.teamA < 0 && draft.teamB < 0 { then(); return }
        guard draft.teamA >= 0, draft.teamB >= 0, draft.teamA != draft.teamB else {
            showAlert(AlertInfo(title: "Both teams must be selected. Game not saved."))
            return
        }
        let errors = t.gameErrors(for: normalized())
        if !errors.isEmpty {
            showAlert(AlertInfo(title: "This game has errors and was not saved.", message: errors.joined(separator: "\n\n")))
            return
        }
        let warnings = t.warnings(for: normalized())
        if warnings.isEmpty { commit(); then(); return }
        showAlert(AlertInfo(title: "Current game has the following warnings:", message: warnings.joined(separator: "\n"),
                            primary: "Review", secondary: "Ignore", onPrimary: {}, onSecondary: { commit(); then() }))
    }

    private func step(_ delta: Int) {
        record {
            let target = index + delta
            if target < 0 { return }
            if target >= t.games.count {
                // Only create a new game after the last saved one.
                if index < t.games.count { startBlank(round: currentRoundAfterSave) }
            } else { load(target) }
        }
    }

    private func gotoGame() {
        let wanted = gotoText.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return }
        guard let i = t.games.firstIndex(where: { $0.id == wanted }) else {
            showAlert(AlertInfo(title: "Game '\(wanted)' not found."))
            return
        }
        record { load(i) }
    }

    private func deleteGame() {
        showAlert(AlertInfo(title: "Delete this game?", message: "This cannot be undone.", primary: "Delete", secondary: "Cancel", onPrimary: {
            if index < t.games.count { t.games.remove(at: index) }
            load(min(index, max(t.games.count - 1, 0)))
        }))
    }
}
