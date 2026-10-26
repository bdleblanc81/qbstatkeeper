import Foundation

/// "Merge Files...": brings the games of a second tournament file into the base tournament,
/// after checking the two describe the same event.
///
/// Two copies of one tournament usually share scheduled games and playoff games that have not been played yet.
/// Those waiting games are never copied over as games; a played game from the other file takes the place of the
/// same game still waiting in this one. A game that is already in both files is not added twice.
public enum TournamentMerge {
    public struct Failure: Error, CustomStringConvertible {
        public var differences: [String]
        public var description: String {
            "The following differences exist between this tournament and merging tournament - " + differences.joined(separator: "\n - ") + "."
        }
    }

    /// What a merge did.
    public struct Result {
        public var tournament: Tournament
        /// Games from the other file that were added.
        public var added = 0
        /// Games waiting for a score in this tournament that the other file had played.
        public var filledIn = 0
        /// Games already in both files with the same result (not added again).
        public var alreadyPresent = 0
        /// Games in both files with different results: this tournament's version was kept.
        public var conflicts: [String] = []
        /// Games that were given a new ID because their ID was already used for a different game.
        public var renamed: [String] = []
        public var addedTeams = 0
        /// The other file's schedule and playoff setup were used because this tournament had none.
        public var adoptedSchedule = false
        public var adoptedPlayoffs = false

        public var summary: String {
            var lines: [String] = []
            lines.append("\(added) game\(added == 1 ? "" : "s") added.")
            if filledIn > 0 { lines.append("\(filledIn) scheduled game\(filledIn == 1 ? "" : "s") that were waiting for a score now have results.") }
            if alreadyPresent > 0 { lines.append("\(alreadyPresent) game\(alreadyPresent == 1 ? " was" : "s were") already in both files and not added twice.") }
            if addedTeams > 0 { lines.append("\(addedTeams) extra team\(addedTeams == 1 ? "" : "s") added.") }
            if adoptedSchedule { lines.append("The other file's schedule was used because this tournament had none.") }
            if adoptedPlayoffs { lines.append("The other file's playoff setup was used because this tournament had none.") }
            if !renamed.isEmpty { lines.append("Given new game IDs: " + renamed.joined(separator: "; ") + ".") }
            if !conflicts.isEmpty { lines.append("Different results in the two files (this tournament's were kept):\n - " + conflicts.joined(separator: "\n - ")) }
            return lines.joined(separator: "\n")
        }
    }

    /// Differences that block a merge (empty when the files are compatible).
    public static func differences(base: Tournament, other: Tournament) -> [String] {
        var d: [String] = []
        let a = base.settings, b = other.settings
        for q in 0..<4 where a.questionValues[q] != b.questionValues[q] || a.questionSelected[q] != b.questionSelected[q] {
            // a spare question worth 0 can only be remembered in the .qzx file, so a .sqbs copy of it is not a difference
            if q == 3 && a.questionValues[3] == 0 && b.questionValues[3] == 0 { continue }
            d.append("Question \(q)#")
        }
        if a.bonusTracking.trackBonus != b.bonusTracking.trackBonus { d.append("Track Bonuses setting#") }
        if a.bonusTracking.autoTrack != b.bonusTracking.autoTrack { d.append("Bonus Conversion setting#") }
        if a.trackTossupsHeard != b.trackTossupsHeard { d.append("Track Toss Ups Heard setting#") }
        if a.trackLightning != b.trackLightning { d.append("Track Lightning Rounds setting#") }

        let shared = min(base.teams.count, other.teams.count)
        for i in 0..<shared {
            let x = base.teams[i], y = other.teams[i]
            var same = x.name == y.name && x.players == y.players
            if same && a.useDivisions && b.useDivisions {
                let dx = x.division.map { base.divisions[$0] }, dy = y.division.map { other.divisions[$0] }
                same = dx == dy
            }
            if !same { d.append("Team (\(x.name)) at index: \(i)#") }
        }
        return d
    }

    /// Returns the merged tournament: `base` plus the other file's games (and any extra trailing teams).
    public static func merge(base: Tournament, other: Tournament) throws -> Tournament {
        try mergeDetailed(base: base, other: other).tournament
    }

    private static func key(_ g: Game) -> [Int] { [g.round, min(g.teamA, g.teamB), max(g.teamA, g.teamB)] }

    private static func sameResult(_ x: Game, _ y: Game) -> Bool {
        if x.isForfeit || y.isForfeit {
            return x.isForfeit == y.isForfeit && x.teamA == y.teamA
        }
        let straight = x.teamA == y.teamA
        let sa = straight ? y.scoreA : y.scoreB, sb = straight ? y.scoreB : y.scoreA
        return NS.int(x.scoreA) == NS.int(sa) && NS.int(x.scoreB) == NS.int(sb)
    }

    public static func mergeDetailed(base: Tournament, other: Tournament) throws -> Result {
        let diffs = differences(base: base, other: other)
        if !diffs.isEmpty { throw Failure(differences: diffs) }
        var merged = base
        var result = Result(tournament: base)

        // extra trailing teams
        if other.teams.count > base.teams.count {
            for i in base.teams.count..<other.teams.count {
                var t = other.teams[i]
                if let d = t.division, d < other.divisions.count {
                    let name = other.divisions[d]
                    if let j = merged.divisions.firstIndex(of: name) { t.division = j } else { merged.divisions.append(name); t.division = merged.divisions.count - 1 }
                } else { t.division = nil }
                merged.teams.append(t)
                result.addedTeams += 1
            }
        }

        // a tournament with no schedule or playoff setup of its own takes the other file's
        let adoptSchedule = base.plus.schedule.isDefault && !other.plus.schedule.isDefault
        let adoptPlayoffs = base.plus.playoffs == PlayoffSettings() && other.plus.playoffs != PlayoffSettings()
        if adoptSchedule { merged.plus.schedule = other.plus.schedule; result.adoptedSchedule = true }
        if adoptPlayoffs { merged.plus.playoffs = other.plus.playoffs; result.adoptedPlayoffs = true }
        if adoptSchedule && merged.settings.useDivisions == false && !merged.plus.schedule.poolNames.isEmpty { merged.applySchedulePoolsToDivisions() }

        var position: [[Int]: Int] = [:]
        for (i, g) in merged.games.enumerated() where position[key(g)] == nil { position[key(g)] = i }

        for g in other.games {
            let waiting = other.isPlaceholder(g)
            if let i = position[key(g)] {
                let mine = merged.games[i]
                if waiting { continue }                       // nothing played in the other file
                if merged.isPlaceholder(mine) {
                    // the same game was only scheduled here: take the played game, keeping this one's ID and place
                    var played = g
                    played.id = mine.id
                    if played.teamA != mine.teamA { swap(&played.teamA, &played.teamB); swap(&played.scoreA, &played.scoreB) }
                    merged.games[i] = played
                    result.filledIn += 1
                } else if sameResult(mine, g) {
                    result.alreadyPresent += 1
                } else {
                    let a = merged.teams[safe: mine.teamA]?.name ?? "?", b = merged.teams[safe: mine.teamB]?.name ?? "?"
                    result.conflicts.append("Round \(g.round), \(a) v \(b)")
                }
                continue
            }
            // a game this tournament has no record of
            if waiting && !adoptSchedule && !adoptPlayoffs { continue }
            var added = g
            if merged.games.contains(where: { $0.id == added.id }) {
                let old = added.id
                added.id = merged.nextGameID(round: added.round)
                result.renamed.append("\(old) became \(added.id)")
            }
            merged.games.append(added)
            position[key(added)] = merged.games.count - 1
            if !waiting { result.added += 1 }
        }
        for (round, name) in other.packetNames where merged.packetNames[round] == nil { merged.packetNames[round] = name }
        if !merged.plus.schedule.teams.isEmpty { merged.linkScheduleTeamsToRoster() }
        result.tournament = merged
        return result
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
