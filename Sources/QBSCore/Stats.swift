import Foundation

// Statistics engine. SQBS does its arithmetic in 32-bit floats and prints them with C-style formats,
// so this file deliberately uses `Float` where SQBS does, to reproduce its output digit-for-digit.

/// `-[NSString intValue]` / `floatValue` semantics.
public enum NS {
    public static func int(_ s: String) -> Int { Int((s as NSString).intValue) }
    public static func float(_ s: String) -> Float { (s as NSString).floatValue }
}

/// SQBS's `safeDivide`: 0 when the divisor is 0.
@inline(__always) func safeDivide(_ a: Float, _ b: Float) -> Float { b == 0 ? 0 : a / b }

public final class TeamStanding: NSObject {
    public var teamIndex = 0
    public var teamName = ""
    public var win = 0, loss = 0, tie = 0, forfeitWin = 0, forfeitLoss = 0
    public var gamesPlayed = 0
    public var pct: Float = 0
    public var ptsPerGame: Float = 0
    public var pointsFor = 0, pointsAgainst = 0
    public var tossUpsHeard = 0
    public var lightning = 0
    public var bonusHeard = 0, bonusPoints = 0
    public var bouncebacksHeard = 0, bouncebacksPoints = 0
    public var q = [0, 0, 0, 0]
    public var position = 0
    public var strength: Float = 0

    /// Wins + losses + ties, i.e. games that were actually scored (forfeits excluded).
    public var scoredGames: Int { win + loss + tie }
}

public final class PlayerStanding: NSObject {
    public var playerName = ""
    public var teamName = ""
    public var teamIndex = 0
    /// 1-based position of the player on the team roster.
    public var position = 0
    public var gamesPlayed: Float = 0
    public var q = [0, 0, 0, 0]
    public var points = 0
    public var tossUpsHeard = 0
}

/// Which games count toward reports.
public struct RoundFilter: Equatable, Sendable {
    public var all = true
    public var min = 0
    public var max = 0
    public init(all: Bool = true, min: Int = 0, max: Int = 0) { self.all = all; self.min = min; self.max = max }
    func includes(_ round: Int) -> Bool { all || (round >= min && round <= max) }
}

public struct Standings {
    public var teams: [TeamStanding]
    public var players: [PlayerStanding]
}

extension Tournament {
    /// Team `index` is not exhibition (games against it count toward opponents' records).
    func isCounted(_ index: Int) -> Bool {
        index >= 0 && index < teams.count && !teams[index].exhibition
    }

    /// Per-player result strings in SQBS are formatted with `%.2f` and re-parsed, so a game's
    /// games-played value is rounded to two decimals before it is accumulated.
    public static func roundedGP(_ gp: String) -> Float {
        NS.float(String(format: "%.2f", Double(NS.float(gp))))
    }

    // MARK: Team totals

    public func teamStandings(filter: RoundFilter = RoundFilter()) -> [TeamStanding] {
        var result: [TeamStanding] = []
        for (i, team) in teams.enumerated() {
            let s = TeamStanding()
            s.teamIndex = i
            s.teamName = team.name
            for g in statGames where filter.includes(g.round) {
                if g.teamA == i, isCounted(g.teamB) {
                    accumulate(s, g, isA: true)
                } else if g.teamB == i, isCounted(g.teamA) {
                    accumulate(s, g, isA: false)
                }
            }
            s.position = i
            s.gamesPlayed = s.win + s.loss + s.tie + s.forfeitWin + s.forfeitLoss
            if s.gamesPlayed == 0 {
                s.pct = 0
                s.ptsPerGame = 0
            } else {
                let numerator = Double(s.win + s.forfeitWin) + 0.5 * Double(s.tie)
                s.pct = Float(numerator) / Float(s.gamesPlayed)
                let scored = s.scoredGames
                s.ptsPerGame = scored == 0 ? 0 : Float(s.pointsFor) / Float(scored)
            }
            result.append(s)
        }

        // Strength of schedule: own PPG plus the PPG of every opponent faced.
        for s in result { s.strength = safeDivide(Float(s.pointsFor), Float(s.scoredGames)) }
        for s in result {
            for g in statGames where filter.includes(g.round) {
                guard !g.isForfeit, NS.int(g.scoreA) != -1, NS.int(g.scoreB) != -1 else { continue }
                if g.teamA == s.teamIndex, isCounted(g.teamB) {
                    let o = result[g.teamB]
                    s.strength += safeDivide(Float(o.pointsFor), Float(o.scoredGames))
                } else if g.teamB == s.teamIndex, isCounted(g.teamA) {
                    let o = result[g.teamA]
                    s.strength += safeDivide(Float(o.pointsFor), Float(o.scoredGames))
                }
            }
        }
        return result
    }

    private func accumulate(_ s: TeamStanding, _ g: Game, isA: Bool) {
        if g.isForfeit {
            if isA { s.forfeitWin += 1 } else { s.forfeitLoss += 1 }
            return
        }
        let mine = NS.int(isA ? g.scoreA : g.scoreB)
        let theirs = NS.int(isA ? g.scoreB : g.scoreA)
        if mine != -1 && theirs != -1 {
            if mine > theirs { s.win += 1 } else if theirs > mine { s.loss += 1 } else { s.tie += 1 }
        }
        s.pointsFor += mine
        s.pointsAgainst += theirs
        s.tossUpsHeard += g.tossupsHeard
        s.lightning += isA ? g.lightningA : g.lightningB
        s.bonusHeard += isA ? g.bonusHeardA : g.bonusHeardB
        s.bonusPoints += isA ? g.bonusPointsA : g.bonusPointsB
        s.bouncebacksHeard += isA ? g.bouncebackHeardA : g.bouncebackHeardB
        s.bouncebacksPoints += isA ? g.bouncebackPointsA : g.bouncebackPointsB
        for slot in (isA ? g.playersA : g.playersB) {
            guard let p = slot else { continue }
            for k in 0..<4 { s.q[k] += p.counts[k] }
        }
    }

    // MARK: Individual totals

    public func playerStandings(filter: RoundFilter = RoundFilter()) -> [PlayerStanding] {
        var result: [PlayerStanding] = []
        for (ti, team) in teams.enumerated() {
            for (pi, name) in team.players.enumerated() {
                let p = PlayerStanding()
                p.teamName = team.name
                p.playerName = name
                for g in statGames where filter.includes(g.round) {
                    if g.isForfeit || NS.int(g.scoreA) == -1 || NS.int(g.scoreB) == -1 { continue }
                    for isA in [true, false] {
                        let mine = isA ? g.teamA : g.teamB
                        let other = isA ? g.teamB : g.teamA
                        guard mine == ti, isCounted(other) else { continue }
                        let slots = isA ? g.playersA : g.playersB
                        guard let line = slots.first(where: { $0?.rosterIndex == pi }) ?? nil else { continue }
                        let gp = Tournament.roundedGP(line.gp)
                        guard gp > 0 else { continue }
                        p.points += line.points
                        for k in 0..<4 { p.q[k] += line.counts[k] }
                        p.gamesPlayed += gp
                        p.tossUpsHeard = Int(Double(p.tossUpsHeard) + Double(Float(g.tossupsHeard) * gp))
                    }
                }
                p.position = pi + 1
                p.teamIndex = ti
                result.append(p)
            }
        }
        return result
    }

    // MARK: Sorting (SQBS comparators)

    /// Team standings in SQBS order.
    public func sortedTeamStandings(_ standings: [TeamStanding]) -> [TeamStanding] {
        let context = TeamSortContext(tournament: self, copy: standings)
        let array = NSMutableArray(array: standings)
        array.sort({ a, b, ctx in
            let c = Unmanaged<TeamSortContext>.fromOpaque(ctx!).takeUnretainedValue()
            return c.compare(a as! TeamStanding, b as! TeamStanding)
        }, context: Unmanaged.passUnretained(context).toOpaque())
        return array as! [TeamStanding]
    }

    /// Player standings in SQBS order (by PPG, or by points per toss-up heard, which orders the same as points per 20 toss-ups heard).
    public func sortedPlayerStandings(_ players: [PlayerStanding]) -> [PlayerStanding] {
        let values = settings.questionValues
        let context = PlayerSortContext(values: values)
        let array = NSMutableArray(array: players)
        if settings.sortPlayersByPointsPerTUH {
            array.sort({ a, b, ctx in
                let c = Unmanaged<PlayerSortContext>.fromOpaque(ctx!).takeUnretainedValue()
                return c.compareByTUH(a as! PlayerStanding, b as! PlayerStanding)
            }, context: Unmanaged.passUnretained(context).toOpaque())
        } else {
            array.sort({ a, b, ctx in
                let c = Unmanaged<PlayerSortContext>.fromOpaque(ctx!).takeUnretainedValue()
                return c.compareByPPG(a as! PlayerStanding, b as! PlayerStanding)
            }, context: Unmanaged.passUnretained(context).toOpaque())
        }
        return array as! [PlayerStanding]
    }
}

final class PlayerSortContext {
    let values: [Int]
    init(values: [Int]) { self.values = values }

    private func ppg(_ p: PlayerStanding) -> Float { p.gamesPlayed == 0 ? 0 : Float(p.points) / p.gamesPlayed }
    private func ppth(_ p: PlayerStanding) -> Float { p.tossUpsHeard == 0 ? 0 : Float(p.points) / Float(p.tossUpsHeard) }

    /// Shared tie-break on question counts. `quirk` reproduces the one branch of the PPG comparator that
    /// always answers "ascending" when power counts differ.
    private func tieBreak(_ a: PlayerStanding, _ b: PlayerStanding, quirkOnFirst: Bool) -> Int? {
        if values[0] > 0 && a.q[0] != b.q[0] { return quirkOnFirst ? -1 : (a.q[0] > b.q[0] ? -1 : 1) }
        if values[1] > 0 && a.q[1] != b.q[1] { return a.q[1] > b.q[1] ? -1 : 1 }
        if values[2] > 0 && a.q[2] != b.q[2] { return a.q[0] > b.q[0] ? -1 : 1 }
        if values[3] > 0 && a.q[3] != b.q[3] { return a.q[3] > b.q[3] ? -1 : 1 }
        return nil
    }

    func compareByPPG(_ a: PlayerStanding, _ b: PlayerStanding) -> Int {
        let x = ppg(a), y = ppg(b)
        if abs(Double(x - y)) < 1e-5, let r = tieBreak(a, b, quirkOnFirst: true) { return r }
        return x > y ? -1 : 1
    }

    func compareByTUH(_ a: PlayerStanding, _ b: PlayerStanding) -> Int {
        let x = ppth(a), y = ppth(b)
        if abs(Double(x - y)) < 1e-5, let r = tieBreak(a, b, quirkOnFirst: false) { return r }
        return x > y ? -1 : 1
    }
}

final class TeamSortContext {
    let method: Int
    let games: [Game]
    let copy: [TeamStanding]
    let teams: [Team]
    init(tournament: Tournament, copy: [TeamStanding]) {
        method = tournament.settings.teamSortRaw
        games = tournament.statGames
        self.copy = copy
        teams = tournament.teams
    }

    /// Record among all teams tied with `a` on win percentage (the "tie group").
    private func headToHead(_ a: TeamStanding) -> Double {
        var w = 0, l = 0, t = 0
        for g in games {
            for isA in [true, false] {
                let me = isA ? g.teamA : g.teamB
                let opp = isA ? g.teamB : g.teamA
                guard me == a.teamIndex else { continue }
                for s in copy where s.teamIndex == opp && abs(Double(s.pct - a.pct)) < 1e-5 {
                    if g.isForfeit { if isA { w += 1 } else { l += 1 }; continue }
                    let sa = NS.int(g.scoreA), sb = NS.int(g.scoreB)
                    let mine = isA ? sa : sb, theirs = isA ? sb : sa
                    if mine > theirs { w += 1 } else if mine < theirs { l += 1 } else { t += 1 }
                }
            }
        }
        let total = w + l + t
        return total == 0 ? 0 : (Double(w) + 0.5 * Double(t)) / Double(total)
    }

    func compare(_ a: TeamStanding, _ b: TeamStanding) -> Int {
        if abs(Double(a.pct - b.pct)) < 1e-5 {
            if method == 2 || method == 5 {
                let ha = headToHead(a), hb = headToHead(b)
                if abs(ha - hb) >= 1e-5 { return ha > hb ? -1 : 1 }
            }
            if method == 3 {
                // The standings page shows strength / (games + 1), so sort on the same number.
                let x = safeDivide(a.strength, Float(a.scoredGames + 1))
                let y = safeDivide(b.strength, Float(b.scoredGames + 1))
                return x > y ? -1 : 1
            }
            if method == 4 || method == 5 {
                let x = a.tossUpsHeard == 0 ? 0 : Float(a.pointsFor) / Float(a.tossUpsHeard)
                let y = b.tossUpsHeard == 0 ? 0 : Float(b.pointsFor) / Float(b.tossUpsHeard)
                return x > y ? -1 : 1
            }
            return a.ptsPerGame > b.ptsPerGame ? -1 : 1
        }
        return a.pct > b.pct ? -1 : 1
    }
}
