import Foundation

/// Reader/writer for SQBS tournament files (`.qzx` from the Mac version and the extensionless Windows files).
///
/// The format is a CRLF-separated list of lines; the layout is documented in docs/FINDINGS.md.
public enum TournamentFile {
    public enum ReadError: Error, Equatable, CustomStringConvertible {
        case notATournamentFile(String)
        case truncated(atLine: Int)
        case invalidTeamCount(String)
        case inconsistentGame(String)

        public var description: String {
            switch self {
            case .notATournamentFile(let why): return "File contents suspect. May not be a tournament file. (\(why))"
            case .truncated(let n): return "File ended unexpectedly near line \(n + 1)."
            case .invalidTeamCount(let s): return "Team count read as \"\(s)\". Expected number [0 - 100]."
            case .inconsistentGame(let s): return s
            }
        }
    }

    public struct ReadResult {
        public var tournament: Tournament
        /// Non-fatal notes (e.g. teams that had more than 12 players).
        public var notes: [String]
    }

    /// Line that introduces the extra data block.
    public static let plusMarker = "<<SQBS-MAC-2.0>>"
    public static let maxTeams = 100
    public static let maxPlayersPerTeam = 12

    // MARK: Reading

    public static func read(data: Data) throws -> ReadResult {
        try read(text: decode(data))
    }

    public static func read(url: URL) throws -> ReadResult {
        try read(data: Data(contentsOf: url))
    }

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    public static func read(text: String) throws -> ReadResult {
        var lines = text.components(separatedBy: "\r\n")
        if lines.count == 1 { lines = text.components(separatedBy: "\n") }
        var r = LineReader(lines: lines)
        var t = Tournament()
        var notes: [String] = []

        // --- Teams
        let teamCountText = try r.next()
        let teamCount = intValue(teamCountText)
        guard (0...maxTeams).contains(teamCount) else { throw ReadError.invalidTeamCount(teamCountText) }
        for _ in 0..<teamCount {
            let k = intValue(try r.next())
            var entries: [String] = []
            if k > 0 { for _ in 0..<k { entries.append(try r.next()) } }
            var team = Team(name: entries.first ?? "")
            var players = Array(entries.dropFirst())
            if players.count > maxPlayersPerTeam {
                notes.append("Team '\(team.name)'. Only first \(maxPlayersPerTeam) players imported.")
                players = Array(players.prefix(maxPlayersPerTeam))
            }
            team.players = players
            t.teams.append(team)
        }

        // --- Games
        let gameCount = intValue(try r.next())
        guard gameCount >= 0 else { throw ReadError.notATournamentFile("negative game count") }
        for _ in 0..<gameCount {
            let g = try readGame(&r)
            let range = 0..<max(teamCount, 0)
            guard range.contains(g.teamA) else {
                throw ReadError.inconsistentGame("File inconsistancy: Team A is not valid. Team Index: \(g.teamA) out of range {0 - \(teamCount - 1)}. (game \(g.id))")
            }
            guard range.contains(g.teamB) else {
                throw ReadError.inconsistentGame("File inconsistancy: Team B is not valid. Team Index: \(g.teamB) out of range {0 - \(teamCount - 1)}. (game \(g.id))")
            }
            guard g.teamA != g.teamB else {
                throw ReadError.inconsistentGame("File inconsistancy: Team B same as Team A. (game \(g.id))")
            }
            t.games.append(g)
        }

        var minRound = 999, maxRound = 0
        for g in t.games {
            minRound = min(minRound, g.round)
            maxRound = max(maxRound, g.round)
            t.packetNames[g.round] = "-"
        }
        if t.games.isEmpty { minRound = 0 }

        // --- Settings
        var s = TournamentSettings()
        let trackBonus = intValue(try r.next())
        let autoTrack = intValue(try r.next())
        s.bonusTracking = BonusTracking(trackBonus: trackBonus, autoTrack: autoTrack)

        var powerNeg = intValue(try r.next())
        var extA = false
        if powerNeg > 1 { powerNeg -= 2; extA = true }
        s.trackPowerNeg = powerNeg != 0

        s.trackLightning = boolValue(try r.next())
        s.trackTossupsHeard = intValue(try r.next())

        var tuhSort = intValue(try r.next())
        var extB = false
        if tuhSort > 1 { tuhSort -= 2; extB = true }
        s.sortPlayersByPointsPerTUH = tuhSort != 0

        let warnings = intValue(try r.next())
        s.warnings = (0..<7).map { warnings & (0x80 >> $0) != 0 }

        var enabled: [Bool] = []
        for _ in 0..<8 { enabled.append(boolValue(try r.next())) }
        s.reportEnabled = enabled

        s.useDivisions = boolValue(try r.next())
        s.teamSortRaw = intValue(try r.next())
        s.tournamentName = try r.next()
        s.ftpHost = try r.next()
        s.ftpUser = try r.next()
        s.ftpDirectory = try r.next()
        s.baseName = try r.next()
        let paths = intValue(try r.next())
        s.alwaysUseSlashInPaths = paths & 1 != 0
        s.britishStyle = paths & 2 != 0

        var names: [String] = []
        for _ in 0..<8 { names.append(try r.next()) }
        s.reportNames = names

        // --- Divisions
        let divisionCount = intValue(try r.next())
        if divisionCount > 0 {
            for _ in 0..<divisionCount { t.divisions.append(try r.next()) }
            _ = try r.next()   // team count line
            for i in 0..<t.teams.count {
                let d = intValue(try r.next())
                if d >= 0 && d < t.divisions.count { t.teams[i].division = d }
            }
        } else {
            r.skip(t.teams.count + 1)
        }

        // --- Question values
        for q in 0..<4 {
            let v = intValue(try r.next())
            s.questionValues[q] = v
            s.questionSelected[q] = v != 0
        }

        // --- Packet names (only in files carrying the second extension flag)
        if extB {
            let n = intValue(try r.next())
            s.packetNamesUsed = n
            if n > 0 {
                for i in 0..<n {
                    var name = try r.next().trimmingCharacters(in: .whitespaces)
                    if name.isEmpty { name = "-" }
                    t.packetNames[minRound + i] = name
                }
            }
        } else {
            s.packetNamesUsed = 0
        }

        // --- Exhibition flags (first extension flag)
        if extA {
            _ = try r.next()   // team count line
            for i in 0..<t.teams.count {
                t.teams[i].exhibition = boolValue(try r.next())
            }
        }

        t.settings = s

        // Version 2.0 data (playoffs and tiebreakers) follows a marker line, if present.
        if let marker = lines[r.index...].firstIndex(of: plusMarker), marker + 1 < lines.count,
           let json = lines[marker + 1].data(using: .utf8), let plus = try? JSONDecoder().decode(PlusData.self, from: json) {
            t.plus = plus
            if plus.spareTracked && t.settings.questionValues[3] == 0 { t.settings.questionSelected[3] = true }
        }
        return ReadResult(tournament: t, notes: notes)
    }

    private static func readGame(_ r: inout LineReader) throws -> Game {
        let id = try r.next()
        let a = intValue(try r.next())
        let b = intValue(try r.next())
        let scoreA = try r.next()
        let scoreB = try r.next()
        let tuh = intValue(try r.next())
        let round = max(0, intValue(try r.next()))
        var g = Game(id: id, teamA: a, teamB: b, scoreA: scoreA, scoreB: scoreB, tossupsHeard: tuh, round: round)

        func unpack(_ v: Int) -> (bonus: Int, bounceback: Int) { (v % 10000, v / 10000) }
        var v = unpack(intValue(try r.next())); g.bonusHeardA = v.bonus; g.bouncebackHeardA = v.bounceback
        v = unpack(intValue(try r.next())); g.bonusPointsA = v.bonus; g.bouncebackPointsA = v.bounceback
        v = unpack(intValue(try r.next())); g.bonusHeardB = v.bonus; g.bouncebackHeardB = v.bounceback
        v = unpack(intValue(try r.next())); g.bonusPointsB = v.bonus; g.bouncebackPointsB = v.bounceback

        g.overtime = intValue(try r.next())
        g.overtimeGetsA = intValue(try r.next())
        g.overtimeGetsB = intValue(try r.next())
        g.forfeit = intValue(try r.next())
        g.lightningA = intValue(try r.next())
        g.lightningB = intValue(try r.next())

        for slot in 0..<Game.slotsPerSide {
            g.playersA[slot] = try readPlayer(&r)
            g.playersB[slot] = try readPlayer(&r)
        }
        return g
    }

    private static func readPlayer(_ r: inout LineReader) throws -> PlayerLine? {
        let index = intValue(try r.next())
        if index < 0 {
            r.skip(6)
            return nil
        }
        let gp = try r.next()
        var counts: [Int] = []
        for _ in 0..<4 { counts.append(intValue(try r.next())) }
        let points = intValue(try r.next())
        return PlayerLine(rosterIndex: index, gp: gp, counts: counts, points: points)
    }

    // MARK: Writing

    /// - Parameter windowsCompatible: when true, Mac-only options are downgraded
    ///   (Auto with Bouncebacks becomes Manual with Bouncebacks).
    public static func write(_ t: Tournament, windowsCompatible: Bool = false, includePlus: Bool = true) -> String {
        var out: [String] = []
        func add(_ s: String) { out.append(s) }
        func add(_ n: Int) { out.append(String(n)) }

        add(t.teams.count)
        for team in t.teams {
            add(team.players.count + 1)
            add(team.name)
            team.players.forEach(add)
        }

        // The NAQT export only carries games that were played; unplayed bracket placeholders are left out.
        let writtenGames = windowsCompatible ? t.statGames : t.games
        add(writtenGames.count)
        for g in writtenGames { writeGame(g, into: &out) }

        let s = t.settings
        add(s.bonusTracking.trackBonus)
        var auto = s.bonusTracking.autoTrack
        if windowsCompatible && auto == 4 { auto = 3 }
        add(auto)
        add((s.trackPowerNeg ? 1 : 0) + 2)
        add(s.trackLightning ? 1 : 0)
        add(s.trackTossupsHeard)
        add((s.sortPlayersByPointsPerTUH ? 1 : 0) + 2)

        var w = 0
        for (i, on) in s.warnings.enumerated() where on { w += 0x80 >> i }
        add(w)
        for on in s.reportEnabled { add(on ? 1 : 0) }
        add(s.useDivisions ? 1 : 0)
        add(s.teamSortRaw)
        add(s.tournamentName)
        add(s.ftpHost)
        add(s.ftpUser)
        add(s.ftpDirectory)
        add(s.baseName)
        add((s.britishStyle ? 2 : 0) + (s.alwaysUseSlashInPaths ? 1 : 0))
        s.reportNames.forEach(add)

        add(t.divisions.count)
        t.divisions.forEach(add)
        add(t.teams.count)
        for team in t.teams { add(team.division ?? -1) }

        for q in 0..<4 { add(s.questionSelected[q] ? s.questionValues[q] : 0) }

        if s.packetNamesUsed > 0, let range = t.roundRange {
            add(range.count)
            for round in range {
                let name = t.packetNames[round] ?? "-"
                add(name == "-" ? " " : name)
            }
        } else {
            add(0)
        }

        add(t.teams.count)
        for team in t.teams { add(team.exhibition ? 1 : 0) }

        var plus = t.plus
        plus.spareTracked = t.settings.questionSelected[3] && t.settings.questionValues[3] == 0
        if includePlus && !windowsCompatible && !plus.isDefault {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(plus), let json = String(data: data, encoding: .utf8), !json.contains("\n") {
                out.append(plusMarker)
                out.append(json)
            }
        }
        return out.joined(separator: "\r\n")
    }

    private static func writeGame(_ g: Game, into out: inout [String]) {
        out.append(g.id)
        out.append(String(g.teamA))
        out.append(String(g.teamB))
        out.append(g.scoreA)
        out.append(g.scoreB)
        out.append(String(g.tossupsHeard))
        out.append(String(g.round))
        out.append(String(g.bouncebackHeardA * 10000 + g.bonusHeardA))
        out.append(String(g.bouncebackPointsA * 10000 + g.bonusPointsA))
        out.append(String(g.bouncebackHeardB * 10000 + g.bonusHeardB))
        out.append(String(g.bouncebackPointsB * 10000 + g.bonusPointsB))
        out.append(String(g.overtime))
        out.append(String(g.overtimeGetsA))
        out.append(String(g.overtimeGetsB))
        out.append(String(g.forfeit))
        out.append(String(g.lightningA))
        out.append(String(g.lightningB))
        for slot in 0..<Game.slotsPerSide {
            writePlayer(g.playersA[slot], into: &out)
            writePlayer(g.playersB[slot], into: &out)
        }
    }

    private static func writePlayer(_ p: PlayerLine?, into out: inout [String]) {
        guard let p else {
            out.append(contentsOf: ["-1", "0", "0", "0", "0", "0", "0"])
            return
        }
        out.append(String(p.rosterIndex))
        out.append(p.gp)
        p.counts.forEach { out.append(String($0)) }
        out.append(String(p.points))
    }

    /// File bytes as SQBS writes them: ISO Latin-1. Text Latin-1 cannot represent is written as UTF-8 instead
    /// (SQBS itself would refuse to save), and the reader accepts either.
    public static func data(for t: Tournament, windowsCompatible: Bool = false) -> Data {
        let text = write(t, windowsCompatible: windowsCompatible)
        return text.data(using: .isoLatin1) ?? Data(text.utf8)
    }

    // MARK: Helpers

    struct LineReader {
        let lines: [String]
        var index = 0
        init(lines: [String]) { self.lines = lines }

        mutating func next() throws -> String {
            guard index < lines.count else { throw ReadError.truncated(atLine: index) }
            defer { index += 1 }
            return lines[index]
        }

        mutating func skip(_ n: Int) { index += max(0, n) }
    }

    /// Emulates `-[NSString intValue]`: optional leading whitespace and sign, then digits; anything else is 0.
    public static func intValue(_ s: String) -> Int {
        var scalars = Substring(s).unicodeScalars.drop(while: { $0 == " " || $0 == "\t" })
        var negative = false
        if let c = scalars.first, c == "-" || c == "+" {
            negative = c == "-"
            scalars = scalars.dropFirst()
        }
        var value = 0
        for c in scalars {
            guard c.value >= 48 && c.value <= 57 else { break }
            value = value &* 10 &+ Int(c.value - 48)
            if value > Int(Int32.max) { value = Int(Int32.max); break }
        }
        return negative ? -value : value
    }

    /// Emulates `-[NSString boolValue]`: first non-space char in 1-9, Y, y, T, t means true.
    public static func boolValue(_ s: String) -> Bool {
        let t = s.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard let c = t.first else { return false }
        switch c {
        case "1"..."9", "Y", "y", "T", "t": return true
        case "0":
            // NSString boolValue skips leading zeros ("007" is true)
            for ch in t where ch != "0" { return ("1"..."9").contains(ch) }
            return false
        default: return false
        }
    }
}
