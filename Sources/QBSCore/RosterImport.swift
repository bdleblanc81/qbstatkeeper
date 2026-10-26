import Foundation

/// Importing teams from a file: either the tournament-file team list (a team count, then each team's
/// line count, name, optional division, players) or the plain-text roster format from the help
/// (name, division if used, players, "." between teams, "~" at the end).
public enum RosterImport {
    public enum ImportError: Error, CustomStringConvertible, Equatable {
        case notATeamFile
        case badTeamCount(String)
        public var description: String {
            switch self {
            case .notATeamFile: return "File contents suspect. May not be a team file."
            case .badTeamCount(let s): return "Team count read as \"\(s)\". Expected number [1 - 100]."
            }
        }
    }

    public struct Result {
        public var teams: [Team]
        public var divisions: [String]
        public var notes: [String]
    }

    public static func parse(data: Data, useDivisions: Bool) throws -> Result {
        try parse(text: TournamentFile.decode(data), useDivisions: useDivisions)
    }

    public static func parse(text: String, useDivisions: Bool) throws -> Result {
        var lines = text.components(separatedBy: "\r\n")
        if lines.count == 1 { lines = text.components(separatedBy: "\n") }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard let firstLine = lines.first else { throw ImportError.notATeamFile }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) {
            return try parseCounted(lines, useDivisions: useDivisions)
        }
        return try parseDotted(lines, useDivisions: useDivisions)
    }

    private static func build(_ entries: [String], useDivisions: Bool, notes: inout [String]) -> (name: String, division: String?, players: [String]) {
        var rest = entries
        let name = rest.isEmpty ? "" : rest.removeFirst()
        var division: String?
        if useDivisions, !rest.isEmpty { division = rest.removeFirst() }
        if rest.count > TournamentFile.maxPlayersPerTeam {
            notes.append("Team '\(name)'. Only first \(TournamentFile.maxPlayersPerTeam) players imported.")
            rest = Array(rest.prefix(TournamentFile.maxPlayersPerTeam))
        }
        return (name, division, rest)
    }

    private static func assemble(_ raw: [(name: String, division: String?, players: [String])], notes: [String]) -> Result {
        var divisions: [String] = []
        var teams: [Team] = []
        for r in raw {
            var team = Team(name: r.name, players: r.players)
            if let d = r.division {
                let name = d.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    if let i = divisions.firstIndex(of: name) { team.division = i } else { divisions.append(name); team.division = divisions.count - 1 }
                }
            }
            teams.append(team)
        }
        return Result(teams: teams, divisions: divisions, notes: notes)
    }

    private static func parseCounted(_ lines: [String], useDivisions: Bool) throws -> Result {
        let count = NS.int(lines[0])
        guard (1...TournamentFile.maxTeams).contains(count) else { throw ImportError.badTeamCount(String(lines[0].prefix(4))) }
        var index = 1
        var raw: [(name: String, division: String?, players: [String])] = []
        var notes: [String] = []
        for _ in 0..<count {
            guard index < lines.count else { throw ImportError.notATeamFile }
            let k = NS.int(lines[index]); index += 1
            guard k >= 0, index + k <= lines.count else { throw ImportError.notATeamFile }
            raw.append(build(Array(lines[index..<(index + k)]), useDivisions: useDivisions, notes: &notes))
            index += k
        }
        return assemble(raw, notes: notes)
    }

    private static func parseDotted(_ lines: [String], useDivisions: Bool) throws -> Result {
        var raw: [(name: String, division: String?, players: [String])] = []
        var notes: [String] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { raw.append(build(current, useDivisions: useDivisions, notes: &notes)); current = [] }
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "~" { break }
            if t == "." { flush(); continue }
            if t.isEmpty && current.isEmpty { continue }
            current.append(line)
        }
        flush()
        guard !raw.isEmpty, raw.count <= TournamentFile.maxTeams else { throw ImportError.notATeamFile }
        return assemble(raw, notes: notes)
    }
}

public struct ImportMergeSummary: Equatable, Sendable {
    /// Teams that were already set up and received their roster from the file.
    public var updated: [String] = []
    /// Teams in the file that were not set up yet and were added.
    public var added: [String] = []
    /// Teams that were already set up but are not in the file; they are left as they were.
    public var notInFile: [String] = []
}

extension Tournament {
    /// Normal form used to match a team name typed in earlier with one from the file.
    static func teamKey(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Brings an imported team file together with teams that were already entered (before rosters were known).
    /// A team whose name matches keeps its place, exhibition mark and anything else set for it, and gets the roster
    /// (and division, when the file has one) from the file. Teams in the file that are new are added at the end, and teams
    /// that are not in the file stay as they are. The schedule's teams are linked to the roster by name afterwards.
    /// Only for a tournament without games, since a different roster would change what game entries mean.
    @discardableResult
    public mutating func mergeImport(_ result: RosterImport.Result) -> ImportMergeSummary {
        var summary = ImportMergeSummary()
        var seen = Set<Int>()
        if settings.useDivisions {
            // bring the file's divisions in, keeping the ones already defined
            for d in result.divisions where !divisions.contains(d) { divisions.append(d) }
        }
        for incoming in result.teams {
            var team = incoming
            if settings.useDivisions, let d = incoming.division, d >= 0, d < result.divisions.count {
                team.division = divisions.firstIndex(of: result.divisions[d])
            } else { team.division = nil }
            if let i = teams.indices.first(where: { !seen.contains($0) && Tournament.teamKey(teams[$0].name) == Tournament.teamKey(incoming.name) }) {
                seen.insert(i)
                teams[i].players = team.players
                if team.division != nil { teams[i].division = team.division }
                summary.updated.append(teams[i].name)
            } else {
                teams.append(team)
                seen.insert(teams.count - 1)
                summary.added.append(team.name)
            }
        }
        summary.notInFile = teams.indices.filter { !seen.contains($0) }.map { teams[$0].name }
        linkScheduleTeamsToRoster()
        return summary
    }

    /// Replaces the team list with imported teams. Existing games are erased, as in SQBS.
    public mutating func applyImport(_ result: RosterImport.Result) {
        teams = result.teams
        if settings.useDivisions { divisions = result.divisions }
        games = []
        packetNames = [:]
    }
}
