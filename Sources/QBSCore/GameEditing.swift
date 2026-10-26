import Foundation

// Game-entry rules: automatic bonus calculation, consistency warnings and defaults.
// These follow the Game Entry screen of SQBS for Mac.

extension Game {
    /// Points a team earned from toss-ups, given the tournament's question values.
    public func playerPoints(isA: Bool) -> Int {
        (isA ? playersA : playersB).compactMap { $0?.points }.reduce(0, +)
    }

    /// Positive-valued toss-ups answered ("gets") by one side.
    func gets(isA: Bool, values: [Int]) -> Int {
        var total = 0
        for line in (isA ? playersA : playersB).compactMap({ $0 }) {
            for j in 0..<4 where values[j] > 0 { total += line.counts[j] }
        }
        return total
    }
}

extension PlayerLine {
    /// Points implied by the counts and the tournament's question values.
    public func computedPoints(values: [Int]) -> Int {
        (0..<4).reduce(0) { $0 + counts[$1] * values[$1] }
    }
}

extension Tournament {
    /// Fills in the automatically calculated bonus fields (the "Automatic" family of bonus modes).
    /// Mirrors `-[GameEntryViewController bonusCalculation]`.
    public func applyBonusCalculation(to g: inout Game) {
        let mode = settings.bonusTracking
        let values = settings.questionValues
        guard mode == .automatic || mode == .manualHeardAutoPoints || mode == .autoWithBouncebacks else { return }

        if mode == .automatic || mode == .autoWithBouncebacks {
            var a = g.gets(isA: true, values: values)
            var b = g.gets(isA: false, values: values)
            if g.isOvertime {
                a -= g.overtimeGetsA
                b -= g.overtimeGetsB
            }
            g.bonusHeardA = a
            g.bonusHeardB = b
        }
        let scoreA = NS.int(g.scoreA), scoreB = NS.int(g.scoreB)
        let pointsA = g.playerPoints(isA: true), pointsB = g.playerPoints(isA: false)
        if mode != .autoWithBouncebacks {
            g.bonusPointsA = scoreA - (settings.trackLightning ? g.lightningA : 0) - pointsA
            g.bonusPointsB = scoreB - (settings.trackLightning ? g.lightningB : 0) - pointsB
        } else {
            // Bonus points are typed in; bounceback heard is the other side's unconverted bonus
            // potential (30 points per bonus) and bounceback points are what is left of the score.
            g.bouncebackPointsA = scoreA - g.bonusPointsA - pointsA
            g.bouncebackPointsB = scoreB - g.bonusPointsB - pointsB
            g.bouncebackHeardA = g.bonusHeardB * 30 - g.bonusPointsB
            g.bouncebackHeardB = g.bonusHeardA * 30 - g.bonusPointsA
        }
    }

    /// Consistency warnings for a game, honoring the Warnings settings. Empty when the game is fine.
    /// The file format keeps seven warning flags; the "same team twice" flag (index 0) and the "games played above the limit"
    /// flag (index 3) no longer do anything here, since those problems are refused outright, but their values are preserved.
    public func warnings(for g: Game) -> [String] {
        if g.isForfeit { return [] }
        var out: [String] = []
        let s = settings
        let nameA = g.teamA >= 0 && g.teamA < teams.count ? teams[g.teamA].name : ""
        let nameB = g.teamB >= 0 && g.teamB < teams.count ? teams[g.teamB].name : ""

        // a player entered twice on a side
        if s.warnings[1] {
            for (isA, name) in [(true, nameA), (false, nameB)] {
                var seen = Set<Int>()
                let team = isA ? g.teamA : g.teamB
                for line in (isA ? g.playersA : g.playersB).compactMap({ $0 }) where line.gamesPlayed > 0 {
                    if !seen.insert(line.rosterIndex).inserted, team >= 0, team < teams.count,
                       line.rosterIndex >= 0, line.rosterIndex < teams[team].players.count {
                        out.append("- Team \"\(name)\" player \(teams[team].players[line.rosterIndex]) was entered more than once.")
                    }
                }
            }
        }

        var sumA = g.playerPoints(isA: true), sumB = g.playerPoints(isA: false)
        if s.trackLightning { sumA += g.lightningA; sumB += g.lightningB }
        if s.bonusTracking != .none {
            sumA += g.bonusPointsA; sumB += g.bonusPointsB
            if s.bonusTracking.hasBouncebacks { sumA += g.bouncebackPointsA; sumB += g.bouncebackPointsB }
        }
        if s.warnings[2] {
            if NS.int(g.scoreA) != sumA { out.append("- Individual and Bonus Scores do not add to Total score for team \(nameA)") }
            if NS.int(g.scoreB) != sumB { out.append("- Individual and Bonus Scores do not add to Total score for team \(nameB)") }
        }
        if s.bonusTracking == .automatic {
            if s.warnings[4] {
                for (heard, pts, name) in [(g.bonusHeardA, g.bonusPointsA, nameA), (g.bonusHeardB, g.bonusPointsB, nameB)] {
                    if (heard > 0 && Double(pts / heard) > 30) || pts < 0 {
                        out.append("- Bonus points not between 0 and 30 for team \(name)")
                    }
                }
            }
            if s.warnings[5] {
                if g.bonusHeardA < 1 && g.bonusPointsA > 0 { out.append("- Bonus points earned without being heard for team \(nameA)") }
                if g.bonusHeardB < 1 && g.bonusPointsB > 0 { out.append("- Bonus points earned without being heard for team \(nameB)") }
            }
        }
        if s.warnings[6] && g.tossupsHeard < 0 { out.append("- Negative toss-ups heard.") }
        // Every bonus follows a toss-up that was answered, so the two teams together cannot hear more bonuses than
        // toss-ups. This one is not part of the SQBS warning list, so it is always on.
        if s.bonusTracking != .none && g.tossupsHeard > 0 && g.bonusHeardA + g.bonusHeardB > g.tossupsHeard {
            out.append("- Bonuses heard (\(g.bonusHeardA) + \(g.bonusHeardB) = \(g.bonusHeardA + g.bonusHeardB)) are more than the toss-ups heard (\(g.tossupsHeard)).")
        }
        return out
    }

    /// Error for one side when more players are credited than can sit at the table: the players' toss-ups heard
    /// (their share of the game) may not add up to more than `maxPlayersPerSide` full games. nil when it is fine.
    public func tableLimitError(for g: Game, isA: Bool) -> String? {
        if g.isForfeit { return nil }
        let team = isA ? g.teamA : g.teamB
        guard team >= 0, team < teams.count else { return nil }
        let limit = maxPlayersPerSide
        let share = (isA ? g.playersA : g.playersB).compactMap { $0 }.reduce(0.0) { $0 + PlayerLine.parseGamesPlayed($1.gp) }
        guard share > Double(limit) + 0.0005 else { return nil }
        let name = teams[team].name
        if g.tossupsHeard > 0 {
            let credited = Int((share * Double(g.tossupsHeard)).rounded())
            return "\(name): players are credited with \(credited) toss-ups heard in total, but only \(limit) players can play at once, "
                + "which allows at most \(limit * g.tossupsHeard) (\(limit) × \(g.tossupsHeard))."
        }
        return "\(name): players are credited with \(String(format: "%g", share)) games played in total, but only \(limit) players can play at once."
    }

    /// Every bonus is worth ten points, so a side's bonus points (and bounceback points, when tracked) must be a
    /// multiple of ten. nil when they are, or when bonuses are not tracked.
    public func bonusPointsError(for g: Game, isA: Bool) -> String? {
        if g.isForfeit || settings.bonusTracking == .none { return nil }
        let team = isA ? g.teamA : g.teamB
        guard team >= 0, team < teams.count else { return nil }
        // Only once the team has a score and at least one player has a toss-up count: a score of zero leaves nothing to
        // enter, and before any player is entered the whole score would land on bonuses.
        let score = NS.int(isA ? g.scoreA : g.scoreB)
        let playerEntered = (isA ? g.playersA : g.playersB).compactMap { $0 }.contains { $0.counts.contains { $0 != 0 } }
        guard score != 0, score != -1, playerEntered else { return nil }
        let name = teams[team].name
        let bonus = isA ? g.bonusPointsA : g.bonusPointsB
        if bonus % 10 != 0 {
            return "\(name): bonus points (\(bonus)) must be a multiple of 10, because every bonus is worth 10 points. "
                + "Check the team's score and the players' toss-up counts."
        }
        if settings.bonusTracking.hasBouncebacks {
            let back = isA ? g.bouncebackPointsA : g.bouncebackPointsB
            if back % 10 != 0 {
                return "\(name): bounceback points (\(back)) must be a multiple of 10, because every bonus is worth 10 points."
            }
        }
        return nil
    }

    /// Errors for one side of a game that stop it from being saved.
    public func sideErrors(for g: Game, isA: Bool) -> [String] {
        [tableLimitError(for: g, isA: isA), bonusPointsError(for: g, isA: isA)].compactMap { $0 }
    }

    /// Errors that stop a game from being saved.
    public func gameErrors(for g: Game) -> [String] {
        sideErrors(for: g, isA: true) + sideErrors(for: g, isA: false)
    }

    /// Errors that stop a game from being saved (see `tableLimitError`).
    public func tableLimitErrors(for g: Game) -> [String] {
        [tableLimitError(for: g, isA: true), tableLimitError(for: g, isA: false)].compactMap { $0 }
    }

    /// Roster lines a new game starts with for a team (up to 8 slots).
    /// With no earlier game to go on, the first `maxPlayersPerSide` players in roster order play one game and the
    /// rest none. Otherwise the new game starts with whoever played in the team's most recent earlier game
    /// (the one in the highest round below `beforeRound`, when given), so a lineup change carries forward.
    public func defaultPlayerLines(forTeam index: Int, beforeRound: Int? = nil, excludingGame: Int? = nil) -> [PlayerLine?] {
        var slots = [PlayerLine?](repeating: nil, count: Game.slotsPerSide)
        guard index >= 0, index < teams.count else { return slots }
        let rosterCount = teams[index].players.count
        let limit = maxPlayersPerSide

        if let lineup = previousLineup(forTeam: index, beforeRound: beforeRound, excludingGame: excludingGame), !lineup.isEmpty {
            let playing = Array(lineup.prefix(limit))
            if playing.allSatisfy({ $0 < Game.slotsPerSide }) {
                for i in 0..<min(rosterCount, Game.slotsPerSide) {
                    slots[i] = PlayerLine(rosterIndex: i, gp: playing.contains(i) ? "1" : "0")
                }
            } else {
                // someone from beyond the first eight roster spots played: list the lineup first
                var order = playing
                for i in 0..<rosterCount where !playing.contains(i) { order.append(i) }
                for (slot, r) in order.prefix(Game.slotsPerSide).enumerated() {
                    slots[slot] = PlayerLine(rosterIndex: r, gp: playing.contains(r) ? "1" : "0")
                }
            }
            return slots
        }

        for i in 0..<min(rosterCount, Game.slotsPerSide) {
            slots[i] = PlayerLine(rosterIndex: i, gp: i < limit ? "1" : "0")
        }
        return slots
    }

    /// Roster indices of the players who played (games played above zero) in the team's most recent earlier game.
    public func previousLineup(forTeam index: Int, beforeRound: Int? = nil, excludingGame: Int? = nil) -> [Int]? {
        let rosterCount = teams[index].players.count
        var best: (round: Int, position: Int, lineup: [Int])?
        for (i, g) in games.enumerated() {
            if i == excludingGame || g.isForfeit { continue }
            if let r = beforeRound, r > 0, g.round >= r { continue }
            let lines: [PlayerLine?]
            if g.teamA == index { lines = g.playersA } else if g.teamB == index { lines = g.playersB } else { continue }
            let lineup = lines.compactMap { $0 }
                .filter { Tournament.roundedGP($0.gp) > 0 && $0.rosterIndex >= 0 && $0.rosterIndex < rosterCount }
                .map(\.rosterIndex)
            if lineup.isEmpty { continue }
            if best == nil || g.round > best!.round || (g.round == best!.round && i > best!.position) {
                best = (g.round, i, lineup)
            }
        }
        return best?.lineup
    }

    /// True when nothing at all has been entered for a game: no score, no toss-ups heard, no player counts, no bonus or
    /// lightning numbers, and it is not a forfeit or overtime game.
    public func isUnentered(_ g: Game) -> Bool {
        if g.isForfeit || g.isOvertime { return false }
        let noScore = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty || NS.int(s) == -1 }
        guard noScore(g.scoreA), noScore(g.scoreB), g.tossupsHeard == 0 else { return false }
        guard g.lightningA == 0, g.lightningB == 0, g.bonusHeardA == 0, g.bonusHeardB == 0, g.bonusPointsA == 0, g.bonusPointsB == 0,
              g.bouncebackHeardA == 0, g.bouncebackHeardB == 0, g.bouncebackPointsA == 0, g.bouncebackPointsB == 0 else { return false }
        return !(g.playersA + g.playersB).compactMap { $0 }.contains { $0.counts.contains { $0 != 0 } }
    }

    /// Index of the first game (earliest round, then list order) with nothing entered, or nil when every game has something.
    /// This is where Game Entry starts, so you pick up at the next game that still needs its results.
    public func firstUnenteredGameIndex() -> Int? {
        games.indices.filter { isUnentered(games[$0]) }.min { (games[$0].round, $0) < (games[$1].round, $1) }
    }

    /// Next default game ID: one more than the last numeric ID, or "0" for the first game.
    public func nextGameID() -> String {
        guard let last = games.last else { return "0" }
        if let n = Int(last.id.trimmingCharacters(in: .whitespaces)) { return String(n + 1) }
        return String(games.count)
    }

    /// Game-entry text for games played: a decimal, or "a/b" converted to a decimal.
    public static func normalizedGamesPlayed(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.contains("/") else { return t }
        let v = PlayerLine.parseGamesPlayed(t)
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Orders games for the Game Entry screen ("Sort Games"). Returns a new array.
    public func sortedGames(by order: GameSortOrder) -> [Game] {
        let indexed = games.enumerated().map { $0 }
        func idLess(_ a: Game, _ b: Game) -> Bool {
            let la = a.id.rangeOfCharacter(from: .letters) != nil, lb = b.id.rangeOfCharacter(from: .letters) != nil
            if !la && !lb { return NS.float(a.id) < NS.float(b.id) }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }
        let sorted = indexed.sorted { x, y in
            let a = x.element, b = y.element
            switch order {
            case .gameID:
                if idLess(a, b) { return true }
                if idLess(b, a) { return false }
            case .round:
                if a.round != b.round { return a.round < b.round }
            case .roundThenGame:
                if a.round != b.round { return a.round < b.round }
                if idLess(a, b) { return true }
                if idLess(b, a) { return false }
            }
            return x.offset < y.offset
        }
        return sorted.map(\.element)
    }
}

public enum GameSortOrder: Sendable { case gameID, round, roundThenGame }
