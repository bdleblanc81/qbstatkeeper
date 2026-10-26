import Foundation

// Quiz Bowl Statkeeper: playoffs, consolation brackets, seeding and configurable tiebreakers.
// Everything here is additive; with default settings the 1.0 behavior is unchanged.

// MARK: - Settings

public enum TiebreakerKind: String, Codable, CaseIterable, Sendable {
    case headToHead
    case teamPointsPer20
    case topIndividualPer20
    case coinFlip

    public var title: String {
        switch self {
        case .headToHead: return "Head-to-head record (among the tied teams)"
        case .teamPointsPer20: return "Team points per 20 tossups heard"
        case .topIndividualPer20: return "Top individual points per 20 tossups heard"
        case .coinFlip: return "Coin flip (enter the result)"
        }
    }
}

public struct TiebreakerOption: Codable, Equatable, Sendable, Identifiable {
    public var kind: TiebreakerKind
    public var enabled: Bool
    public var id: String { kind.rawValue }
    public init(kind: TiebreakerKind, enabled: Bool = true) { self.kind = kind; self.enabled = enabled }
}

/// A place in a bracket game and where its team comes from.
public enum BracketSlot: Codable, Equatable, Sendable {
    case seed(Int)
    case winner(String)
    case loser(String)
    case team(Int)
    case bye

    public var storageKey: String {
        switch self {
        case .seed(let n): return "seed:\(n)"
        case .winner(let id): return "winner:\(id)"
        case .loser(let id): return "loser:\(id)"
        case .team(let i): return "team:\(i)"
        case .bye: return "bye"
        }
    }

    public init(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : "") {
        case ("seed", let v): self = .seed(Int(v) ?? 1)
        case ("winner", let v): self = .winner(v)
        case ("loser", let v): self = .loser(v)
        case ("team", let v): self = .team(Int(v) ?? 0)
        default: self = .bye
        }
    }
}

public struct BracketGame: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var round: Int
    public var a: BracketSlot
    public var b: BracketSlot
    public init(id: String, round: Int, a: BracketSlot, b: BracketSlot) { self.id = id; self.round = round; self.a = a; self.b = b }
}

public struct Bracket: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var games: [BracketGame]
    public init(id: String, name: String, games: [BracketGame] = []) { self.id = id; self.name = name; self.games = games }
}

public struct PlayoffSettings: Codable, Equatable, Sendable {
    /// Total rounds in the tournament, including playoffs (0 = not set).
    public var totalRounds = 0
    /// Number of playoff rounds (0 = not set). They are the last rounds of the tournament.
    public var playoffRounds = 0
    /// Add a third-place game between the losers of the two top-bracket semifinals.
    public var thirdPlaceGame = false
    /// First playoff round (0 = not set), derived from the total and the number of playoff rounds.
    public var playoffStartRound: Int { totalRounds > 0 && playoffRounds > 0 && playoffRounds <= totalRounds ? totalRounds - playoffRounds + 1 : 0 }
    /// How many teams go to the top bracket; everyone else goes to consolation.
    public var topBracketSize = 0
    /// When false, team standings use the 1.0 sort methods and tiebreakers are only used if asked for in the modal.
    public var useTiebreakers = false
    public var tiebreakers: [TiebreakerOption] = TiebreakerKind.allCases.map { TiebreakerOption(kind: $0) }
    /// After a tiebreaker splits a group, start over from the first tiebreaker for each smaller group.
    public var restartAfterSplit = true
    /// Coin-flip results: team index -> order (1 = wins the flip).
    public var coinFlipOrder: [Int: Int] = [:]
    /// Seed order set by hand (team index for seed 1, 2, ...). nil = follow the standings.
    public var manualSeeds: [Int]?
    public var brackets: [Bracket] = []
    /// Pool play: seeds alternate between the two pools (A1, B1, A2, B2, ...), the top `advancePerPool` teams of each pool
    /// play a cross-pool top bracket, and everyone else plays cross-pool consolation games.
    public var poolPlayoffs = false
    public var advancePerPool = 2
    /// Extra top-bracket spots for the best teams that did not finish in their pool's top places (by record).
    public var wildCards = 0
    public init() {}

    enum CodingKeys: String, CodingKey {
        case totalRounds, playoffRounds, thirdPlaceGame, topBracketSize, useTiebreakers, tiebreakers, restartAfterSplit
        case coinFlipOrder, manualSeeds, brackets, poolPlayoffs, advancePerPool, wildCards
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalRounds = try c.decodeIfPresent(Int.self, forKey: .totalRounds) ?? 0
        playoffRounds = try c.decodeIfPresent(Int.self, forKey: .playoffRounds) ?? 0
        thirdPlaceGame = try c.decodeIfPresent(Bool.self, forKey: .thirdPlaceGame) ?? false
        topBracketSize = try c.decodeIfPresent(Int.self, forKey: .topBracketSize) ?? 0
        useTiebreakers = try c.decodeIfPresent(Bool.self, forKey: .useTiebreakers) ?? false
        tiebreakers = try c.decodeIfPresent([TiebreakerOption].self, forKey: .tiebreakers) ?? TiebreakerKind.allCases.map { TiebreakerOption(kind: $0) }
        restartAfterSplit = try c.decodeIfPresent(Bool.self, forKey: .restartAfterSplit) ?? true
        coinFlipOrder = try c.decodeIfPresent([Int: Int].self, forKey: .coinFlipOrder) ?? [:]
        manualSeeds = try c.decodeIfPresent([Int].self, forKey: .manualSeeds)
        brackets = try c.decodeIfPresent([Bracket].self, forKey: .brackets) ?? []
        poolPlayoffs = try c.decodeIfPresent(Bool.self, forKey: .poolPlayoffs) ?? false
        advancePerPool = try c.decodeIfPresent(Int.self, forKey: .advancePerPool) ?? 2
        wildCards = try c.decodeIfPresent(Int.self, forKey: .wildCards) ?? 0
    }
}

/// Extra data stored after the normal tournament data in a `.qzx` file.
public struct PlusData: Codable, Equatable, Sendable {
    public var playoffs = PlayoffSettings()
    public var schedule = Schedule()
    /// The spare question is tracked even though its value is 0. Standard files store an unused question as 0,
    /// so "selected with value 0" can only be remembered here.
    public var spareTracked = false
    public init() {}
    public var isDefault: Bool { self == PlusData() }

    enum CodingKeys: String, CodingKey { case playoffs, schedule, spareTracked }

    /// Files written before a part existed simply lack its key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playoffs = try c.decodeIfPresent(PlayoffSettings.self, forKey: .playoffs) ?? PlayoffSettings()
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule()
        spareTracked = try c.decodeIfPresent(Bool.self, forKey: .spareTracked) ?? false
    }
}

// MARK: - Ranking with tiebreakers

public struct RankedTeam: Equatable, Sendable {
    public var teamIndex: Int
    /// 1-based place after tiebreakers.
    public var rank: Int
    /// True when this team is still tied with a neighbor after every enabled tiebreaker.
    public var unresolvedTie: Bool
    /// Which tiebreaker separated this team from the group (nil if it was not tied).
    public var decidedBy: TiebreakerKind?
}

extension Tournament {
    public var preliminaryFilter: RoundFilter {
        let start = plus.playoffs.playoffStartRound
        guard start > 1 else { return RoundFilter() }
        return RoundFilter(all: false, min: 0, max: start - 1)
    }

    private func headToHeadPct(_ team: Int, group: Set<Int>, filter: RoundFilter) -> Double {
        var w = 0.0, n = 0.0
        for g in games where filter.includes(g.round) {
            guard !g.isForfeit || true else { continue }
            let isA = g.teamA == team
            guard isA || g.teamB == team else { continue }
            let opp = isA ? g.teamB : g.teamA
            guard group.contains(opp), opp != team else { continue }
            if g.isForfeit { w += isA ? 1 : 0; n += 1; continue }
            let sa = NS.int(g.scoreA), sb = NS.int(g.scoreB)
            guard sa != -1, sb != -1 else { continue }
            let mine = isA ? sa : sb, theirs = isA ? sb : sa
            n += 1
            if mine > theirs { w += 1 } else if mine == theirs { w += 0.5 }
        }
        return n == 0 ? 0 : w / n
    }

    /// Ranks teams by win percentage, then by the enabled tiebreakers in the configured order.
    public func rankTeams(filter: RoundFilter? = nil, includeExhibition: Bool = false) -> [RankedTeam] {
        let f = filter ?? preliminaryFilter
        let standings = teamStandings(filter: f)
        let players = playerStandings(filter: f)
        return rankTeams(standings: standings, players: players, filter: f, includeExhibition: includeExhibition)
    }

    func rankTeams(standings: [TeamStanding], players: [PlayerStanding], filter: RoundFilter, includeExhibition: Bool) -> [RankedTeam] {
        let eligible = standings.filter { includeExhibition || !teams[$0.teamIndex].exhibition }
        let ordered = eligible.sorted { a, b in
            if abs(Double(a.pct - b.pct)) >= 1e-5 { return a.pct > b.pct }
            return a.teamIndex < b.teamIndex
        }
        // group by equal win percentage
        var groups: [[TeamStanding]] = []
        for s in ordered {
            if let last = groups.last?.first, abs(Double(last.pct - s.pct)) < 1e-5 { groups[groups.count - 1].append(s) } else { groups.append([s]) }
        }
        let active = plus.playoffs.tiebreakers.filter(\.enabled).map(\.kind)
        var result: [RankedTeam] = []
        var place = 1
        for group in groups {
            if group.count == 1 {
                result.append(RankedTeam(teamIndex: group[0].teamIndex, rank: place, unresolvedTie: false, decidedBy: nil))
                place += 1
                continue
            }
            let resolved = resolve(group.map(\.teamIndex), order: active, all: active, standings: standings, players: players, filter: filter, decidedBy: nil)
            // Teams that have not played yet are not "tied" in any way that needs a tiebreaker.
            let noGames = group.allSatisfy { $0.gamesPlayed == 0 }
            for r in resolved {
                result.append(RankedTeam(teamIndex: r.team, rank: place, unresolvedTie: r.unresolved && !noGames, decidedBy: r.decidedBy))
                place += 1
            }
        }
        return result
    }

    private struct Resolved { var team: Int; var unresolved: Bool; var decidedBy: TiebreakerKind? }

    private func resolve(_ group: [Int], order: [TiebreakerKind], all: [TiebreakerKind], standings: [TeamStanding], players: [PlayerStanding],
                         filter: RoundFilter, decidedBy: TiebreakerKind?) -> [Resolved] {
        if group.count == 1 { return [Resolved(team: group[0], unresolved: false, decidedBy: decidedBy)] }
        guard let tb = order.first else {
            return group.sorted().map { Resolved(team: $0, unresolved: true, decidedBy: nil) }
        }
        let rest = Array(order.dropFirst())
        // metric per team; nil means this tiebreaker cannot separate the group
        var metric: [Int: Double] = [:]
        switch tb {
        case .headToHead:
            let set = Set(group)
            for t in group { metric[t] = headToHeadPct(t, group: set, filter: filter) }
        case .teamPointsPer20:
            for t in group {
                let s = standings.first { $0.teamIndex == t }
                metric[t] = (s?.tossUpsHeard ?? 0) > 0 ? Double(s!.pointsFor) / Double(s!.tossUpsHeard) * 20 : 0
            }
        case .topIndividualPer20:
            for t in group {
                let best = players.filter { $0.teamIndex == t && $0.tossUpsHeard > 0 }
                    .map { Double($0.points) / Double($0.tossUpsHeard) * 20 }.max() ?? 0
                metric[t] = best
            }
        case .coinFlip:
            let flips = plus.playoffs.coinFlipOrder
            if group.allSatisfy({ flips[$0] != nil }) { for t in group { metric[t] = -Double(flips[t]!) } }
        }
        guard metric.count == group.count else {
            return resolve(group, order: rest, all: all, standings: standings, players: players, filter: filter, decidedBy: decidedBy)
        }
        let sorted = group.sorted { a, b in
            if abs(metric[a]! - metric[b]!) >= 1e-9 { return metric[a]! > metric[b]! }
            return a < b
        }
        var subgroups: [[Int]] = []
        for t in sorted {
            if let first = subgroups.last?.first, abs(metric[first]! - metric[t]!) < 1e-9 { subgroups[subgroups.count - 1].append(t) } else { subgroups.append([t]) }
        }
        if subgroups.count == 1 {
            return resolve(group, order: rest, all: all, standings: standings, players: players, filter: filter, decidedBy: decidedBy)
        }
        return subgroups.flatMap { sub -> [Resolved] in
            resolve(sub, order: plus.playoffs.restartAfterSplit ? all : rest, all: all, standings: standings, players: players, filter: filter, decidedBy: tb)
        }
    }

    /// Standings order used by reports when tiebreakers are switched on.
    public func tiebreakerOrder(_ standings: [TeamStanding], players: [PlayerStanding], filter: RoundFilter) -> [TeamStanding] {
        let ranked = rankTeams(standings: standings, players: players, filter: filter, includeExhibition: true)
        let byTeam = Dictionary(uniqueKeysWithValues: standings.map { ($0.teamIndex, $0) })
        return ranked.compactMap { byTeam[$0.teamIndex] }
    }

    // MARK: Seeds

    /// Team index for each seed (index 0 = seed 1): the manual order if set, otherwise the standings after the preliminary rounds.
    public func seedOrder() -> [Int] {
        var computed = rankTeams().map(\.teamIndex)
        if usesPoolSeeding { computed = poolSeedOrder(ranked: computed) }
        guard let manual = plus.playoffs.manualSeeds else { return computed }
        // Keep the manual order but drop teams that no longer exist and append new ones.
        var seen = Set<Int>()
        var order = manual.filter { $0 >= 0 && $0 < teams.count && seen.insert($0).inserted }
        for t in computed where seen.insert(t).inserted { order.append(t) }
        return order
    }

    /// Pool playoffs are on and the teams are split into two or more pools (divisions).
    public var usesPoolSeeding: Bool { plus.playoffs.poolPlayoffs && settings.useDivisions && divisions.count >= 2 }

    /// Seed order for pool play: the top places of every pool (A1, B1, C1, A2, ...), then the wild cards (the best of the
    /// rest by overall record), then everyone else by pool rank. Teams with no pool come last.
    func poolSeedOrder(ranked: [Int]) -> [Int] {
        let pools = poolRankings(ranked: ranked)
        let adv = min(max(plus.playoffs.advancePerPool, 1), pools.map(\.count).min() ?? 1)
        let qualifiers = Tournament.interleave(pools: pools.map { Array($0.prefix(adv)) })
        let rest = ranked.filter { !qualifiers.contains($0) && teams[$0].division != nil }
        let wildCards = Array(rest.prefix(min(max(plus.playoffs.wildCards, 0), rest.count)))
        let remaining = pools.map { Array($0.dropFirst(adv)).filter { !wildCards.contains($0) } }
        let undivided = ranked.filter { teams[$0].division == nil }
        return qualifiers + wildCards + Tournament.interleave(pools: remaining) + undivided
    }

    /// The ranked teams of each pool (division), best first. Teams without a pool are left out.
    func poolRankings(ranked: [Int]) -> [[Int]] {
        divisions.indices.map { d in ranked.filter { teams[$0].division == d } }
    }

    /// Alternates between pools by rank: A1, B1, C1, A2, B2, C2, ...
    static func interleave(pools: [[Int]]) -> [Int] {
        var out: [Int] = []
        let longest = pools.map(\.count).max() ?? 0
        for r in 0..<longest { for pool in pools where r < pool.count { out.append(pool[r]) } }
        return out
    }

    public func team(forSeed seed: Int) -> Int? {
        let order = seedOrder()
        return seed >= 1 && seed <= order.count ? order[seed - 1] : nil
    }

    // MARK: Brackets

    private func game(withID id: String) -> Game? { games.first { $0.id == id } }

    /// A bracket game that has been set up in the game list but not played yet (no score entered, not a forfeit).
    /// Placeholders let Game Entry show the pairing; they never count in stats, reports or the NAQT export.
    public func isPlaceholder(_ g: Game) -> Bool {
        guard !g.isForfeit else { return false }
        let unscored = (g.scoreA.isEmpty || NS.int(g.scoreA) == -1) && (g.scoreB.isEmpty || NS.int(g.scoreB) == -1)
        guard unscored else { return false }
        return plus.playoffs.brackets.contains { $0.games.contains { $0.id == g.id } }
            || plus.schedule.games.contains { $0.gameID == g.id }
    }

    /// Games that count: everything except unplayed bracket placeholders.
    public var statGames: [Game] {
        let hasPlaceholders = !plus.playoffs.brackets.isEmpty || plus.schedule.games.contains { $0.gameID != nil }
        return hasPlaceholders ? games.filter { !isPlaceholder($0) } : games
    }

    public var placeholderCount: Int { games.filter(isPlaceholder).count }

    /// Who won a finished game (nil while it is unplayed, unscored or tied).
    public func winnerAndLoser(ofGameID id: String) -> (winner: Int, loser: Int)? {
        guard let g = game(withID: id) else { return nil }
        if g.isForfeit { return (g.teamA, g.teamB) }
        let a = NS.int(g.scoreA), b = NS.int(g.scoreB)
        guard a != -1, b != -1, !g.scoreA.isEmpty, !g.scoreB.isEmpty, a != b else { return nil }
        return a > b ? (g.teamA, g.teamB) : (g.teamB, g.teamA)
    }

    /// The team a slot currently resolves to, or nil if it depends on a game that has not finished.
    public func resolve(slot: BracketSlot) -> Int? {
        switch slot {
        case .seed(let n): return team(forSeed: n)
        case .team(let i): return i >= 0 && i < teams.count ? i : nil
        case .winner(let id): return winnerAndLoser(ofGameID: id)?.winner
        case .loser(let id): return winnerAndLoser(ofGameID: id)?.loser
        case .bye: return nil
        }
    }

    /// Creates (or updates) a game in the game list for every bracket game whose two teams are known.
    /// Games that already have scores are left alone. Returns the ids of games that were created.
    @discardableResult
    public mutating func syncPlayoffGames(throughRound: Int? = nil) -> [String] {
        var created: [String] = []
        // resolve repeatedly so that a bye or a finished game can feed later rounds in one pass
        for bracket in plus.playoffs.brackets {
            for bg in bracket.games.sorted(by: { $0.round < $1.round }) {
                if let limit = throughRound, bg.round > limit { continue }
                guard let a = resolve(slot: bg.a), let b = resolve(slot: bg.b), a != b else { continue }
                if let i = games.firstIndex(where: { $0.id == bg.id }) {
                    let g = games[i]
                    let scored = NS.int(g.scoreA) != -1 && !g.scoreA.isEmpty || g.isForfeit
                    if !scored { games[i].teamA = a; games[i].teamB = b; games[i].round = bg.round }
                } else {
                    var g = Game(id: bg.id, teamA: a, teamB: b, scoreA: "-1", scoreB: "-1", tossupsHeard: 0, round: bg.round)
                    g.playersA = defaultPlayerLines(forTeam: a, beforeRound: bg.round)
                    g.playersB = defaultPlayerLines(forTeam: b, beforeRound: bg.round)
                    games.append(g)
                    created.append(bg.id)
                }
            }
        }
        return created
    }

    /// Replaces the brackets with a single-elimination top bracket (seeds 1...X) and a single-elimination
    /// consolation bracket for the remaining seeds, starting at the first playoff round.
    public mutating func generateDefaultBrackets() {
        let n = teams.filter { !$0.exhibition }.count
        let start = max(plus.playoffs.playoffStartRound, 1)
        var brackets: [Bracket] = []
        if usesPoolSeeding {
            // top bracket: the best of each pool (A1, B1, C1, ... A2, B2, ...) and the wild cards, arranged so that teams from the
            // same pool do not meet in the first round when that can be avoided
            let eligible = teams.indices.filter { !teams[$0].exhibition }
            let sizes = divisions.indices.map { d in eligible.filter { teams[$0].division == d }.count }
            let adv = min(max(plus.playoffs.advancePerPool, 1), sizes.min() ?? 1)
            let wild = min(max(plus.playoffs.wildCards, 0), max(n - adv * sizes.count, 0))
            plus.playoffs.wildCards = wild
            let order = seedOrder()
            var poolOfSeed: [Int: Int] = [:]
            for (i, team) in order.enumerated() { poolOfSeed[i + 1] = teams[team].division ?? -1 }
            let x = min(adv * sizes.count + wild, n)
            plus.playoffs.topBracketSize = x
            if x >= 2 {
                let arranged = BracketBuilder.avoidingSamePool(count: x) { poolOfSeed[$0] ?? -1 }
                brackets.append(BracketBuilder.singleElimination(id: "T", name: "Top Bracket", seeds: arranged, startRound: start))
            }
            // consolation: everyone else, paired across pools in every playoff round
            var poolSeeds: [[Int]] = sizes.map { _ in [] }
            if order.count > x { for s in (x + 1)...order.count { if let d = poolOfSeed[s], d >= 0 { poolSeeds[d].append(s) } } }
            let rounds = max(plus.playoffs.playoffRounds, 1)
            let cross = BracketBuilder.crossPools(id: "C", name: "Consolation", poolSeeds: poolSeeds, startRound: start, rounds: rounds)
            if !cross.games.isEmpty { brackets.append(cross) }
            if plus.playoffs.thirdPlaceGame, !brackets.isEmpty { BracketBuilder.addThirdPlaceGame(to: &brackets[0]) }
            plus.playoffs.brackets = brackets
            standardizeBracketGameIDs()
            return
        }
        let x = min(max(plus.playoffs.topBracketSize, 0), n)
        if x >= 2 { brackets.append(BracketBuilder.singleElimination(id: "T", name: "Top Bracket", seeds: Array(1...x), startRound: start)) }
        if n - x >= 2 { brackets.append(BracketBuilder.singleElimination(id: "C", name: "Consolation", seeds: Array((x + 1)...n), startRound: start)) }
        if plus.playoffs.thirdPlaceGame, !brackets.isEmpty { BracketBuilder.addThirdPlaceGame(to: &brackets[0]) }
        plus.playoffs.brackets = brackets
        standardizeBracketGameIDs()
    }

    /// Gives every bracket game the common ID format {round}-{game}, numbering games within each round across brackets.
    public mutating func standardizeBracketGameIDs() {
        var rename: [String: String] = [:]
        var rounds = Set<Int>()
        for b in plus.playoffs.brackets { for g in b.games { rounds.insert(g.round) } }
        for round in rounds.sorted() {
            var n = 1
            for b in plus.playoffs.brackets {
                for g in b.games where g.round == round { rename[g.id] = "\(round)-\(n)"; n += 1 }
            }
        }
        func fix(_ slot: BracketSlot) -> BracketSlot {
            switch slot {
            case .winner(let id): return .winner(rename[id] ?? id)
            case .loser(let id): return .loser(rename[id] ?? id)
            default: return slot
            }
        }
        for bi in plus.playoffs.brackets.indices {
            for gi in plus.playoffs.brackets[bi].games.indices {
                var g = plus.playoffs.brackets[bi].games[gi]
                g.id = rename[g.id] ?? g.id
                g.a = fix(g.a); g.b = fix(g.b)
                plus.playoffs.brackets[bi].games[gi] = g
            }
        }
        for i in games.indices { if let new = rename[games[i].id], isBracketID(games[i].id) { games[i].id = new } }
    }

    private func isBracketID(_ id: String) -> Bool { plus.playoffs.brackets.contains { $0.games.contains { $0.id == id } } }

    // MARK: Game IDs and rounds

    /// The next unused game ID for a round, in the common {round}-{game} format.
    public func nextGameID(round: Int) -> String {
        var n = 1
        let prefix = "\(round)-"
        for g in games where g.id.hasPrefix(prefix) {
            if let k = Int(g.id.dropFirst(prefix.count)) { n = max(n, k + 1) }
        }
        for b in plus.playoffs.brackets { for g in b.games where g.id.hasPrefix(prefix) { if let k = Int(g.id.dropFirst(prefix.count)) { n = max(n, k + 1) } } }
        var id = "\(round)-\(n)"
        while games.contains(where: { $0.id == id }) { n += 1; id = "\(round)-\(n)" }
        return id
    }

    public func isPlayoffRound(_ round: Int) -> Bool {
        let start = plus.playoffs.playoffStartRound
        return start > 0 && round >= start
    }

    /// Teams (not exhibition) with no game recorded in the round.
    public func teamsWithoutGame(inRound round: Int) -> [Int] {
        var played = Set<Int>()
        for g in statGames where g.round == round { played.insert(g.teamA); played.insert(g.teamB) }
        return teams.indices.filter { !teams[$0].exhibition && !played.contains($0) }
    }

    /// Bracket games of a round whose result has not been entered (missing from the game list, or still a placeholder).
    public func unscoredBracketGames(inRound round: Int) -> [BracketGame] {
        var out: [BracketGame] = []
        for b in plus.playoffs.brackets {
            for bg in b.games where bg.round == round {
                guard let g = games.first(where: { $0.id == bg.id }) else { out.append(bg); continue }
                if isPlaceholder(g) { out.append(bg) }
            }
        }
        return out
    }

    /// Index in the game list of the first unplayed bracket placeholder in a round, if any.
    public func firstPlaceholderIndex(inRound round: Int) -> Int? {
        games.firstIndex { $0.round == round && isPlaceholder($0) }
    }
}

// MARK: - Bracket generation

public enum BracketBuilder {
    /// Games between the pools' remaining teams, one set per round. Teams never meet a teammate from their pool or an
    /// opponent they already had in an earlier round, and each is paired with the nearest seed that allows it. With two
    /// equal pools this gives equal ranks first (A3-B3, A4-B4, ...), then neighbors (A3-B4, A4-B3, ...).
    /// `poolSeeds[d]` are the seed numbers of pool d's consolation teams. A team with no valid partner has no game that round.
    public static func crossPools(id: String, name: String, poolSeeds: [[Int]], startRound: Int, rounds: Int) -> Bracket {
        var bracket = Bracket(id: id, name: name)
        var poolOf: [Int: Int] = [:]
        for (d, seeds) in poolSeeds.enumerated() { for s in seeds { poolOf[s] = d } }
        let order = poolOf.keys.sorted()
        guard order.count >= 2 else { return bracket }
        var met = Set<[Int]>()
        for k in 0..<max(rounds, 0) {
            let pairs = bestPairing(order, canMeet: { a, b in poolOf[a] != poolOf[b] && !met.contains([min(a, b), max(a, b)]) })
            for p in pairs { met.insert([min(p.0, p.1), max(p.0, p.1)]) }
            for (n, pair) in pairs.enumerated() {
                bracket.games.append(BracketGame(id: "\(id)\(k + 1)-\(n + 1)", round: startRound + k, a: .seed(pair.0), b: .seed(pair.1)))
            }
        }
        return bracket
    }

    /// The most games that can be made from `seeds` (sorted) when only some pairs may meet, preferring pairs close in seed.
    /// Anyone left over has no game. Exact for up to 20 teams; larger groups are paired greedily.
    static func bestPairing(_ seeds: [Int], canMeet: (Int, Int) -> Bool) -> [(Int, Int)] {
        let n = seeds.count
        guard n <= 20 else {
            var free = seeds, pairs: [(Int, Int)] = []
            while let a = free.first {
                free.removeFirst()
                guard let b = free.filter({ canMeet(a, $0) }).min(by: { (abs($0 - a), $0) < (abs($1 - a), $1) }) else { continue }
                free.removeAll { $0 == b }; pairs.append((a, b))
            }
            return pairs
        }
        var memo: [Int: (games: Int, cost: Int, choice: Int)] = [:]
        func solve(_ mask: Int) -> (games: Int, cost: Int, choice: Int) {
            if mask == 0 { return (0, 0, -1) }
            if let m = memo[mask] { return m }
            let a = mask.trailingZeroBitCount
            let rest = mask & ~(1 << a)
            var best = solve(rest)            // a sits out
            best.choice = -1
            for b in (a + 1)..<max(n, a + 1) where rest & (1 << b) != 0 && canMeet(seeds[a], seeds[b]) {
                let sub = solve(rest & ~(1 << b))
                let candidate = (games: sub.games + 1, cost: sub.cost + abs(seeds[b] - seeds[a]), choice: b)
                if candidate.games > best.games || (candidate.games == best.games && candidate.cost < best.cost) { best = candidate }
            }
            memo[mask] = best
            return best
        }
        var mask = (1 << n) - 1, pairs: [(Int, Int)] = []
        while mask != 0 {
            let a = mask.trailingZeroBitCount
            let choice = solve(mask).choice
            mask &= ~(1 << a)
            if choice >= 0 { pairs.append((seeds[a], seeds[choice])); mask &= ~(1 << choice) }
        }
        return pairs
    }

    /// Seeds 1...count in bracket order (the first entry fills the first slot), rearranged slightly so that first-round
    /// games between teams of the same pool are avoided where possible. Seeds move as little as they can.
    public static func avoidingSamePool(count n: Int, poolOf: (Int) -> Int) -> [Int] {
        var size = 1
        while size < n { size *= 2 }
        let slots = positions(size)
        var labels = Array(1...max(n, 1))
        func conflicts(_ l: [Int]) -> Int {
            var c = 0
            for i in stride(from: 0, to: slots.count, by: 2) {
                let a = slots[i], b = slots[i + 1]
                if a <= n && b <= n && poolOf(l[a - 1]) == poolOf(l[b - 1]) { c += 1 }
            }
            return c
        }
        func displacement(_ l: [Int]) -> Int { l.enumerated().reduce(0) { $0 + abs($1.element - ($1.offset + 1)) } }
        for _ in 0..<4 {
            let current = (conflicts(labels), displacement(labels))
            guard current.0 > 0 else { break }
            var best = labels, bestScore = current
            for i in 0..<n { for j in (i + 1)..<n {
                var trial = labels; trial.swapAt(i, j)
                let score = (conflicts(trial), displacement(trial))
                if score < bestScore { best = trial; bestScore = score }
            } }
            if best == labels { break }
            labels = best
        }
        return labels
    }

    /// Adds a game between the losers of the two semifinals, played in the final's round.
    public static func addThirdPlaceGame(to bracket: inout Bracket) {
        guard let final = bracket.games.max(by: { $0.round < $1.round }),
              case .winner(let s1) = final.a, case .winner(let s2) = final.b else { return }
        bracket.games.append(BracketGame(id: bracket.id + "3rd", round: final.round, a: .loser(s1), b: .loser(s2)))
    }

    /// Standard seeding order for a bracket of `size` (a power of two): 1 v size, 4 v size-3, ...
    static func positions(_ size: Int) -> [Int] {
        var order = [1]
        while order.count < size {
            let next = order.count * 2
            order = order.flatMap { [$0, next + 1 - $0] }
        }
        return order
    }

    /// Single-elimination bracket for the given seeds (best seed first). Missing opponents become byes:
    /// the seed advances and meets the winner of the next game.
    public static func singleElimination(id: String, name: String, seeds: [Int], startRound: Int) -> Bracket {
        var bracket = Bracket(id: id, name: name)
        let n = seeds.count
        guard n >= 2 else { return bracket }
        var size = 1
        while size < n { size *= 2 }
        // slots in bracket order; `nil` is a bye
        var current: [BracketSlot?] = positions(size).map { $0 <= n ? .seed(seeds[$0 - 1]) : nil }
        var round = startRound
        while current.count > 1 {
            var next: [BracketSlot?] = []
            var gameNumber = 1
            for pair in stride(from: 0, to: current.count, by: 2) {
                let a = current[pair], b = current[pair + 1]
                switch (a, b) {
                case (nil, nil): next.append(nil)
                case (let x?, nil): next.append(x)
                case (nil, let y?): next.append(y)
                case (let x?, let y?):
                    let gid = "\(id)\(round - startRound + 1)-\(gameNumber)"
                    gameNumber += 1
                    bracket.games.append(BracketGame(id: gid, round: round, a: x, b: y))
                    next.append(.winner(gid))
                }
            }
            current = next
            round += 1
        }
        return bracket
    }
}
