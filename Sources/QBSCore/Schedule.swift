import Foundation

// Quiz Bowl Statkeeper: scheduling. Teams are scheduled before their rosters are known, assigned to rooms, and
// given a moderator and scorekeeper. Everything here lives in the extra data block (never in the .sqbs export).

// MARK: - Data

public enum StaffRole: String, Codable, CaseIterable, Sendable {
    case moderator, scorekeeper
    public var title: String { self == .moderator ? "Moderator" : "Scorekeeper" }
}

/// A team as the schedule knows it. `rosterTeam` links it to a real team (index into `Tournament.teams`) once the roster exists.
public struct ScheduleTeam: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var school: String
    public var rosterTeam: Int?
    /// The pool the team plays in (empty = none). Used by round-robin scheduling and pool playoffs.
    public var pool: String
    /// The name follows the school: just the school name when it has one team, otherwise the school name and a letter.
    /// Typing a different name turns this off.
    public var autoName: Bool
    public init(id: Int, name: String, school: String = "", rosterTeam: Int? = nil, pool: String = "", autoName: Bool = false) {
        self.id = id; self.name = name; self.school = school; self.rosterTeam = rosterTeam; self.pool = pool; self.autoName = autoName
    }

    enum CodingKeys: String, CodingKey { case id, name, school, rosterTeam, pool, autoName }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        school = try c.decodeIfPresent(String.self, forKey: .school) ?? ""
        rosterTeam = try c.decodeIfPresent(Int.self, forKey: .rosterTeam)
        pool = try c.decodeIfPresent(String.self, forKey: .pool) ?? ""
        autoName = try c.decodeIfPresent(Bool.self, forKey: .autoName) ?? false
    }
}

/// A school that has teams in the schedule. Team names are built from it.
public struct ScheduleSchool: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

public struct ScheduleRoom: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

/// A moderator or scorekeeper, available all day or only for rounds `fromRound...toRound`.
public struct StaffMember: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var role: StaffRole
    public var allDay: Bool
    public var fromRound: Int
    public var toRound: Int
    public init(id: Int, name: String, role: StaffRole, allDay: Bool = true, fromRound: Int = 1, toRound: Int = 1) {
        self.id = id; self.name = name; self.role = role; self.allDay = allDay; self.fromRound = fromRound; self.toRound = toRound
    }
    public func isAvailable(round: Int) -> Bool { allDay || (round >= fromRound && round <= toRound) }
}

/// One room in one round. Every round has a slot for every room; a slot with no teams is simply unused.
public struct ScheduledGame: Codable, Equatable, Sendable, Identifiable {
    public var round: Int
    public var room: Int
    public var teamA: Int?
    public var teamB: Int?
    /// Set by hand: automatic scheduling leaves the teams and the room alone.
    public var pinned = false
    public var moderator: Int?
    public var scorekeeper: Int?
    public var moderatorPinned = false
    public var scorekeeperPinned = false
    /// Playoff rounds: the bracket game played in this room.
    public var playoffGame: String?
    /// The game created in Game Entry for this slot (preliminary rounds).
    public var gameID: String?
    public var id: String { "\(round)-\(room)" }
    public var hasBothTeams: Bool { teamA != nil && teamB != nil }
    public var hasAnyTeam: Bool { teamA != nil || teamB != nil }
    public init(round: Int, room: Int) { self.round = round; self.room = room }
}

/// A set of buzzers and whose it is, tracked on the day: which room it is in now.
public struct BuzzerSet: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    /// Whose buzzers these are (a school, a team or a person).
    public var owner: String
    /// The room they are in, or nil while they are not in a room.
    public var room: Int?
    public var note: String
    public init(id: Int, owner: String, room: Int? = nil, note: String = "") { self.id = id; self.owner = owner; self.room = room; self.note = note }
}

public struct ScheduleIssue: Identifiable, Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var message: String
    public var id: String { severity.rawValue + message }
    public init(_ severity: Severity, _ message: String) { self.severity = severity; self.message = message }
}

public struct Schedule: Codable, Equatable, Sendable {
    public var schools: [ScheduleSchool] = []
    public var teams: [ScheduleTeam] = []
    public var rooms: [ScheduleRoom] = []
    public var staff: [StaffMember] = []
    public var games: [ScheduledGame] = []
    public var buzzers: [BuzzerSet] = []
    /// A team does not return to a room it used within this many rounds (0 = no limit).
    public var roomRepeatGap = 2
    public var avoidSameSchool = true
    /// Every school plays every other school at least once (not every team need meet every other).
    public var requireSchoolCoverage = true
    /// Preliminary rounds are a full round robin within each pool instead of random pairings.
    public var poolRoundRobin = false
    public var nextSchoolID = 1
    public var nextTeamID = 1
    public var nextRoomID = 1
    public var nextStaffID = 1
    public var nextBuzzerID = 1

    public init() {}
    public var isDefault: Bool { self == Schedule() }

    enum CodingKeys: String, CodingKey {
        case schools, teams, rooms, staff, games, buzzers, roomRepeatGap, avoidSameSchool, requireSchoolCoverage, poolRoundRobin, nextSchoolID, nextTeamID, nextRoomID, nextStaffID, nextBuzzerID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schools = try c.decodeIfPresent([ScheduleSchool].self, forKey: .schools) ?? []
        teams = try c.decodeIfPresent([ScheduleTeam].self, forKey: .teams) ?? []
        rooms = try c.decodeIfPresent([ScheduleRoom].self, forKey: .rooms) ?? []
        staff = try c.decodeIfPresent([StaffMember].self, forKey: .staff) ?? []
        games = try c.decodeIfPresent([ScheduledGame].self, forKey: .games) ?? []
        buzzers = try c.decodeIfPresent([BuzzerSet].self, forKey: .buzzers) ?? []
        roomRepeatGap = try c.decodeIfPresent(Int.self, forKey: .roomRepeatGap) ?? 2
        avoidSameSchool = try c.decodeIfPresent(Bool.self, forKey: .avoidSameSchool) ?? true
        requireSchoolCoverage = try c.decodeIfPresent(Bool.self, forKey: .requireSchoolCoverage) ?? true
        poolRoundRobin = try c.decodeIfPresent(Bool.self, forKey: .poolRoundRobin) ?? false
        nextSchoolID = try c.decodeIfPresent(Int.self, forKey: .nextSchoolID) ?? 1
        nextTeamID = try c.decodeIfPresent(Int.self, forKey: .nextTeamID) ?? 1
        nextRoomID = try c.decodeIfPresent(Int.self, forKey: .nextRoomID) ?? 1
        nextStaffID = try c.decodeIfPresent(Int.self, forKey: .nextStaffID) ?? 1
        nextBuzzerID = try c.decodeIfPresent(Int.self, forKey: .nextBuzzerID) ?? 1
        syncSchoolsFromTeams()   // files from before schools were listed
    }

    // MARK: Editing

    // MARK: Schools and teams

    /// The school a team name most likely belongs to: the name without a single trailing letter ("Adams A" is Adams).
    public static func guessSchool(fromTeamName name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: " ")
        if parts.count >= 2, let last = parts.last, last.count == 1, last.first!.isLetter, last.first!.isUppercase {
            return parts.dropLast().joined(separator: " ")
        }
        return t
    }

    /// Schools match without regard to case or extra spaces.
    static func schoolKey(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    public func school(named name: String) -> ScheduleSchool? {
        schools.first { Schedule.schoolKey($0.name) == Schedule.schoolKey(name) }
    }

    public func teams(inSchool name: String) -> [ScheduleTeam] {
        teams.filter { Schedule.schoolKey($0.school) == Schedule.schoolKey(name) }
    }

    /// The school's entry, created when it is new.
    @discardableResult
    public mutating func ensureSchool(_ name: String) -> ScheduleSchool? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let s = school(named: trimmed) { return s }
        let s = ScheduleSchool(id: nextSchoolID, name: trimmed)
        nextSchoolID += 1
        schools.append(s)
        return s
    }

    /// Schools named in team entries (older files) become school entries.
    mutating func syncSchoolsFromTeams() {
        for t in teams where !t.school.trimmingCharacters(in: .whitespaces).isEmpty { ensureSchool(t.school) }
    }

    /// Names automatic teams: the school name alone when the school has one team, otherwise the school name and a letter
    /// (by position among all the school's teams). Teams given their own name are left alone.
    public mutating func updateAutoNames(forSchool name: String) {
        let key = Schedule.schoolKey(name)
        let indexes = teams.indices.filter { Schedule.schoolKey(teams[$0].school) == key }
        let display = school(named: name)?.name ?? name.trimmingCharacters(in: .whitespaces)
        for (n, i) in indexes.enumerated() where teams[i].autoName {
            if indexes.count == 1 { teams[i].name = display }
            else {
                let letter = n < 26 ? String(UnicodeScalar(65 + n)!) : String(n + 1)
                teams[i].name = "\(display) \(letter)"
            }
        }
    }

    /// A new school with `teamCount` teams, named after it automatically.
    @discardableResult
    public mutating func addSchool(name: String, teamCount: Int = 1) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, school(named: trimmed) == nil, let s = ensureSchool(trimmed) else { return nil }
        for _ in 0..<max(teamCount, 1) { addTeam(toSchool: s.id) }
        return s.id
    }

    /// Another team for a school, named automatically.
    @discardableResult
    public mutating func addTeam(toSchool schoolID: Int) -> Int? {
        guard let s = schools.first(where: { $0.id == schoolID }) else { return nil }
        let id = nextTeamID; nextTeamID += 1
        teams.append(ScheduleTeam(id: id, name: s.name, school: s.name, autoName: true))
        updateAutoNames(forSchool: s.name)
        return id
    }

    public mutating func renameSchool(_ schoolID: Int, to newName: String) {
        guard let i = schools.firstIndex(where: { $0.id == schoolID }) else { return }
        let old = schools[i].name
        schools[i].name = newName
        for t in teams.indices where Schedule.schoolKey(teams[t].school) == Schedule.schoolKey(old) { teams[t].school = newName }
        updateAutoNames(forSchool: newName)
    }

    /// Removes a school and all its teams.
    public mutating func removeSchool(_ schoolID: Int) {
        guard let s = schools.first(where: { $0.id == schoolID }) else { return }
        for t in teams(inSchool: s.name) { removeTeam(t.id) }
        schools.removeAll { $0.id == schoolID }
    }

    /// A team with its own name (used for imported rosters, pasted lists and tests).
    @discardableResult
    public mutating func addTeam(name: String, school: String = "") -> Int {
        let id = nextTeamID; nextTeamID += 1
        teams.append(ScheduleTeam(id: id, name: name, school: school.trimmingCharacters(in: .whitespaces)))
        ensureSchool(school)
        if let s = school.trimmingCharacters(in: .whitespaces) as String?, !s.isEmpty { updateAutoNames(forSchool: s) }
        return id
    }

    public mutating func removeTeam(_ id: Int) {
        let school = teams.first { $0.id == id }?.school
        defer { if let school, !school.isEmpty { updateAutoNames(forSchool: school) } }
        teams.removeAll { $0.id == id }
        for i in games.indices {
            if games[i].teamA == id { games[i].teamA = nil; games[i].pinned = false }
            if games[i].teamB == id { games[i].teamB = nil; games[i].pinned = false }
        }
    }

    @discardableResult
    public mutating func addRoom(name: String) -> Int {
        let id = nextRoomID; nextRoomID += 1
        rooms.append(ScheduleRoom(id: id, name: name))
        return id
    }

    public mutating func removeRoom(_ id: Int) {
        rooms.removeAll { $0.id == id }
        games.removeAll { $0.room == id }
        for i in buzzers.indices where buzzers[i].room == id { buzzers[i].room = nil }
    }

    @discardableResult
    public mutating func addBuzzers(owner: String, room: Int? = nil) -> Int {
        let id = nextBuzzerID; nextBuzzerID += 1
        buzzers.append(BuzzerSet(id: id, owner: owner, room: room))
        return id
    }

    /// Buzzer sets currently in a room.
    public func buzzers(inRoom id: Int) -> [BuzzerSet] { buzzers.filter { $0.room == id } }

    @discardableResult
    public mutating func addStaff(name: String, role: StaffRole, allDay: Bool = true, fromRound: Int = 1, toRound: Int = 1) -> Int {
        let id = nextStaffID; nextStaffID += 1
        staff.append(StaffMember(id: id, name: name, role: role, allDay: allDay, fromRound: fromRound, toRound: toRound))
        return id
    }

    public mutating func removeStaff(_ id: Int) {
        staff.removeAll { $0.id == id }
        for i in games.indices {
            if games[i].moderator == id { games[i].moderator = nil; games[i].moderatorPinned = false }
            if games[i].scorekeeper == id { games[i].scorekeeper = nil; games[i].scorekeeperPinned = false }
        }
    }

    /// Makes sure every round from 1 to `totalRounds` has a slot for every room, and drops slots that no longer fit.
    public mutating func ensureSlots(totalRounds: Int) {
        let roomIDs = Set(rooms.map(\.id))
        games.removeAll { $0.round < 1 || $0.round > totalRounds || !roomIDs.contains($0.room) }
        var have = Set(games.map(\.id))
        if totalRounds >= 1 {
            for r in 1...totalRounds {
                for room in rooms where !have.contains("\(r)-\(room.id)") {
                    games.append(ScheduledGame(round: r, room: room.id))
                    have.insert("\(r)-\(room.id)")
                }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: rooms.enumerated().map { ($1.id, $0) })
        games.sort { ($0.round, order[$0.room] ?? 0) < ($1.round, order[$1.room] ?? 0) }
    }

    public func slotIndex(round: Int, room: Int) -> Int? { games.firstIndex { $0.round == round && $0.room == room } }
    public func slots(inRound r: Int) -> [ScheduledGame] { games.filter { $0.round == r } }
    public func team(_ id: Int?) -> ScheduleTeam? { id.flatMap { i in teams.first { $0.id == i } } }
    public func room(_ id: Int) -> ScheduleRoom? { rooms.first { $0.id == id } }
    public func staffMember(_ id: Int?) -> StaffMember? { id.flatMap { i in staff.first { $0.id == i } } }

    /// Clears every automatically made game in rounds 1...`rounds`; hand-made (pinned) games stay.
    public mutating func clearAutomatic(rounds: Int) {
        for i in games.indices where games[i].round <= rounds && !games[i].pinned {
            games[i].teamA = nil; games[i].teamB = nil
        }
    }

    public mutating func clearAllTeams(rounds: Int) {
        for i in games.indices where games[i].round <= rounds {
            games[i].teamA = nil; games[i].teamB = nil; games[i].pinned = false
        }
    }

    // MARK: Counting

    /// Games each team plays in rounds 1...`rounds`, by team id.
    public func gamesPerTeam(rounds: Int) -> [Int: Int] {
        var counts = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, 0) })
        for g in games where g.round <= rounds { for t in [g.teamA, g.teamB].compactMap({ $0 }) { counts[t, default: 0] += 1 } }
        return counts
    }

    /// Number of times each pair of teams meets in rounds 1...`rounds`, keyed by (smaller id, larger id).
    public func meetings(rounds: Int) -> [[Int]: Int] {
        var out: [[Int]: Int] = [:]
        for g in games where g.round <= rounds {
            if let a = g.teamA, let b = g.teamB { out[[min(a, b), max(a, b)], default: 0] += 1 }
        }
        return out
    }

    /// Pairs of schools (alphabetical) that never meet in rounds 1...`rounds`.
    public func schoolPairsNeverMeeting(rounds: Int) -> [(String, String)] {
        let schools = Array(Set(teams.map { $0.school.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        let schoolOf = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.school.trimmingCharacters(in: .whitespaces)) })
        var met = Set<[String]>()
        for g in games where g.round <= rounds {
            if let a = g.teamA, let b = g.teamB, let sa = schoolOf[a], let sb = schoolOf[b], !sa.isEmpty, !sb.isEmpty, sa != sb {
                met.insert([min(sa, sb), max(sa, sb)])
            }
        }
        var out: [(String, String)] = []
        for i in 0..<schools.count { for j in (i + 1)..<max(schools.count, i + 1) where !met.contains([schools[i], schools[j]]) { out.append((schools[i], schools[j])) } }
        return out
    }
}

// MARK: - Random numbers

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Assignment (Hungarian algorithm)

/// Minimum-cost assignment of every row to a different column (rows <= columns). Returns the column for each row.
func minimumCostAssignment(_ a: [[Int]]) -> [Int] {
    let n = a.count
    guard n > 0, let m = a.first?.count, m >= n else { return [] }
    let inf = Int.max / 4
    var u = [Int](repeating: 0, count: n + 1), v = [Int](repeating: 0, count: m + 1)
    var p = [Int](repeating: 0, count: m + 1), way = [Int](repeating: 0, count: m + 1)
    for i in 1...n {
        p[0] = i
        var j0 = 0
        var minv = [Int](repeating: inf, count: m + 1)
        var used = [Bool](repeating: false, count: m + 1)
        repeat {
            used[j0] = true
            let i0 = p[j0]
            var delta = inf, j1 = 0
            for j in 1...m where !used[j] {
                let cur = a[i0 - 1][j - 1] - u[i0] - v[j]
                if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                if minv[j] < delta { delta = minv[j]; j1 = j }
            }
            for j in 0...m {
                if used[j] { u[p[j]] += delta; v[j] -= delta } else { minv[j] -= delta }
            }
            j0 = j1
        } while p[j0] != 0
        repeat {
            let j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
        } while j0 != 0
    }
    var ans = [Int](repeating: -1, count: n)
    for j in 1...m where p[j] != 0 { ans[p[j] - 1] = j - 1 }
    return ans
}

// MARK: - Pairing cost

/// Running cost of a set of games: repeated opponents, same-school games and school pairs that never meet.
private final class PairingCost {
    let n: Int
    let schoolOf: [Int]
    let schoolCount: Int
    let avoidSame: Bool
    let cover: Bool
    var pair: [Int]
    var schoolPair: [Int]
    var missing = 0
    var total = 0

    static let repeatWeight = 60, sameSchoolWeight = 150, missingWeight = 400

    init(n: Int, schoolOf: [Int], schoolCount: Int, avoidSame: Bool, cover: Bool) {
        self.n = n; self.schoolOf = schoolOf; self.schoolCount = schoolCount; self.avoidSame = avoidSame; self.cover = cover
        pair = [Int](repeating: 0, count: n * n)
        schoolPair = [Int](repeating: 0, count: max(schoolCount * schoolCount, 1))
        if cover { missing = schoolCount * (schoolCount - 1) / 2; total = missing * Self.missingWeight }
    }

    @discardableResult
    func add(_ i: Int, _ j: Int) -> Int {
        var d = Self.repeatWeight * pair[i * n + j]
        pair[i * n + j] += 1; pair[j * n + i] += 1
        let si = schoolOf[i], sj = schoolOf[j]
        if si >= 0 && si == sj && avoidSame { d += Self.sameSchoolWeight }
        if cover && si >= 0 && sj >= 0 && si != sj {
            let k = min(si, sj) * schoolCount + max(si, sj)
            if schoolPair[k] == 0 { d -= Self.missingWeight; missing -= 1 }
            schoolPair[k] += 1
        }
        total += d
        return d
    }

    @discardableResult
    func remove(_ i: Int, _ j: Int) -> Int {
        pair[i * n + j] -= 1; pair[j * n + i] -= 1
        var d = -Self.repeatWeight * pair[i * n + j]
        let si = schoolOf[i], sj = schoolOf[j]
        if si >= 0 && si == sj && avoidSame { d -= Self.sameSchoolWeight }
        if cover && si >= 0 && sj >= 0 && si != sj {
            let k = min(si, sj) * schoolCount + max(si, sj)
            schoolPair[k] -= 1
            if schoolPair[k] == 0 { d += Self.missingWeight; missing += 1 }
        }
        total += d
        return d
    }
}

// MARK: - Generating a schedule

extension Schedule {
    /// Fills rounds 1...`rounds` with random matchups and rooms, keeping every pinned game. Teams sit out (a bye) in turn when
    /// there are fewer rooms or an odd number of teams, so each team ends up with the same number of games whenever that
    /// is possible. Returns messages about anything that could not be satisfied.
    @discardableResult
    public mutating func generate(rounds R: Int, seed: UInt64) -> [String] {
        guard teams.count >= 2 else { return ["Add at least two teams first."] }
        guard !rooms.isEmpty else { return ["Add at least one room first."] }
        guard R > 0 else { return ["Set the number of rounds first."] }
        ensureSlots(totalRounds: R)
        clearAutomatic(rounds: R)
        var rng = SeededRNG(seed: seed)
        if poolRoundRobin { return generateRoundRobin(rounds: R, rng: &rng) }

        let n = teams.count
        let index = Dictionary(uniqueKeysWithValues: teams.enumerated().map { ($1.id, $0) })
        var schoolNames: [String] = []
        var schoolOf = [Int](repeating: -1, count: n)
        for (i, t) in teams.enumerated() {
            let s = t.school.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if let k = schoolNames.firstIndex(of: s) { schoolOf[i] = k } else { schoolNames.append(s); schoolOf[i] = schoolNames.count - 1 }
        }
        let cost = PairingCost(n: n, schoolOf: schoolOf, schoolCount: schoolNames.count, avoidSame: avoidSameSchool, cover: requireSchoolCoverage)

        // hand-made games count toward the totals and keep their teams out of the random pool
        var pinnedTeams = [Set<Int>](repeating: [], count: R + 1)
        var usage = [[(round: Int, room: Int)]](repeating: [], count: n)
        for g in games where g.pinned && g.round <= R {
            for t in [g.teamA, g.teamB].compactMap({ $0 }) {
                if let i = index[t] { pinnedTeams[g.round].insert(i); usage[i].append((g.round, g.room)) }
            }
            if let a = g.teamA, let b = g.teamB, let i = index[a], let j = index[b] { cost.add(i, j) }
        }

        // who sits out each round (fewest byes so far sit first), and the initial random pairing of the rest
        var byeCount = [Int](repeating: 0, count: n)
        var pairs = [[Int]](repeating: [], count: R + 1)
        var openRooms = [[Int]](repeating: [], count: R + 1)
        for r in 1...R {
            let pinnedRooms = Set(games.filter { $0.round == r && $0.pinned }.map(\.room))
            openRooms[r] = rooms.map(\.id).filter { !pinnedRooms.contains($0) }
            var free = (0..<n).filter { !pinnedTeams[r].contains($0) }
            let gamesNow = min(openRooms[r].count, free.count / 2)
            let sitting = free.count - 2 * gamesNow
            let keys = free.map { _ in Int.random(in: 0..<1_000_000, using: &rng) }
            let order = Dictionary(uniqueKeysWithValues: zip(free, keys))
            free.sort { (byeCount[$0], order[$0]!) < (byeCount[$1], order[$1]!) }
            for s in free.prefix(sitting) { byeCount[s] += 1 }
            var active = Array(free.dropFirst(sitting))
            active.shuffle(using: &rng)
            pairs[r] = active
        }
        for r in 1...R { for k in 0..<(pairs[r].count / 2) { cost.add(pairs[r][2 * k], pairs[r][2 * k + 1]) } }

        // improve by swapping teams between games of the same round
        let swappable = (1...R).filter { pairs[$0].count >= 4 }
        if !swappable.isEmpty {
            let totalGames = swappable.reduce(0) { $0 + pairs[$1].count / 2 }
            let iterations = min(30_000 + 700 * totalGames, 500_000)
            var best = pairs, bestCost = cost.total
            for it in 0..<iterations {
                let temperature = 60.0 * (1 - Double(it) / Double(iterations)) + 0.5
                let r = swappable[Int.random(in: 0..<swappable.count, using: &rng)]
                let count = pairs[r].count
                let a = Int.random(in: 0..<count, using: &rng), b = Int.random(in: 0..<count, using: &rng)
                let ga = a / 2, gb = b / 2
                if ga == gb { continue }
                var d = 0
                d += cost.remove(pairs[r][2 * ga], pairs[r][2 * ga + 1])
                d += cost.remove(pairs[r][2 * gb], pairs[r][2 * gb + 1])
                pairs[r].swapAt(a, b)
                d += cost.add(pairs[r][2 * ga], pairs[r][2 * ga + 1])
                d += cost.add(pairs[r][2 * gb], pairs[r][2 * gb + 1])
                if d <= 0 || exp(-Double(d) / temperature) > Double.random(in: 0..<1, using: &rng) {
                    if cost.total < bestCost { bestCost = cost.total; best = pairs }
                } else {
                    cost.remove(pairs[r][2 * ga], pairs[r][2 * ga + 1])
                    cost.remove(pairs[r][2 * gb], pairs[r][2 * gb + 1])
                    pairs[r].swapAt(a, b)
                    cost.add(pairs[r][2 * ga], pairs[r][2 * ga + 1])
                    cost.add(pairs[r][2 * gb], pairs[r][2 * gb + 1])
                }
            }
            pairs = best
        }

        placeRooms(pairs: pairs, openRooms: openRooms, usage: &usage, rounds: R, rng: &rng)

        var notes: [String] = []
        for issue in issues(prelimRounds: R, totalRounds: R) where issue.severity == .error || issue.message.hasPrefix("Schools") {
            notes.append(issue.message)
        }
        return notes
    }
}

// MARK: - Rooms and round robin

extension Schedule {
    /// Puts each round's games in rooms, round by round, so a team keeps away from rooms it used recently.
    /// `pairs[r]` lists team indexes two at a time; `openRooms[r]` are the room ids not taken by hand-made games.
    fileprivate mutating func placeRooms(pairs: [[Int]], openRooms: [[Int]], usage: inout [[(round: Int, room: Int)]], rounds R: Int, rng: inout SeededRNG) {
        let gap = max(roomRepeatGap, 0)
        for r in 1...R {
            let count = pairs[r].count / 2
            guard count > 0 else { continue }
            let roomIDs = openRooms[r]
            guard roomIDs.count >= count else { continue }
            var matrix = [[Int]](repeating: [Int](repeating: 0, count: roomIDs.count), count: count)
            for k in 0..<count {
                let members = [pairs[r][2 * k], pairs[r][2 * k + 1]]
                for (c, room) in roomIDs.enumerated() {
                    var penalty = 0
                    for t in members {
                        for use in usage[t] where use.room == room {
                            penalty += (gap > 0 && abs(use.round - r) <= gap) ? 1000 : 5
                        }
                    }
                    matrix[k][c] = penalty + Int.random(in: 0..<3, using: &rng)
                }
            }
            let chosen = minimumCostAssignment(matrix)
            for k in 0..<count where k < chosen.count && chosen[k] >= 0 {
                var a = pairs[r][2 * k], b = pairs[r][2 * k + 1]
                if Bool.random(using: &rng) { swap(&a, &b) }
                let room = roomIDs[chosen[k]]
                if let s = slotIndex(round: r, room: room) {
                    games[s].teamA = teams[a].id; games[s].teamB = teams[b].id; games[s].pinned = false
                    usage[a].append((r, room)); usage[b].append((r, room))
                }
            }
        }
    }

    /// Pool names in use, in alphabetical order.
    public var poolNames: [String] {
        Array(Set(teams.map { $0.pool.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }

    /// Rounds a full round robin takes for a pool of `size` teams.
    public static func roundRobinRounds(forPoolOf size: Int) -> Int { size < 2 ? 0 : (size % 2 == 0 ? size - 1 : size) }

    /// A full round robin inside each pool (the circle method), with a random order of teams and rounds, then rooms.
    fileprivate mutating func generateRoundRobin(rounds R: Int, rng: inout SeededRNG) -> [String] {
        var notes: [String] = []
        let pools = poolNames
        guard !pools.isEmpty else { return ["Give each team a pool first (Teams section), or turn off round-robin scheduling."] }
        let unpooled = teams.filter { $0.pool.trimmingCharacters(in: .whitespaces).isEmpty }
        if !unpooled.isEmpty { notes.append("\(unpooled.count) team\(unpooled.count == 1 ? " has" : "s have") no pool and \(unpooled.count == 1 ? "was" : "were") not scheduled.") }
        let index = Dictionary(uniqueKeysWithValues: teams.enumerated().map { ($1.id, $0) })

        // hand-made games keep their teams and rooms
        var busy = [Set<Int>](repeating: [], count: R + 1)
        var usage = [[(round: Int, room: Int)]](repeating: [], count: teams.count)
        for g in games where g.pinned && g.round <= R {
            for t in [g.teamA, g.teamB].compactMap({ $0 }) { if let i = index[t] { busy[g.round].insert(i); usage[i].append((g.round, g.room)) } }
        }
        var pairs = [[Int]](repeating: [], count: R + 1)
        for pool in pools {
            var members = teams.indices.filter { teams[$0].pool.trimmingCharacters(in: .whitespaces) == pool }
            members.shuffle(using: &rng)
            let needed = Schedule.roundRobinRounds(forPoolOf: members.count)
            if needed > 0 && needed < R {
                notes.append("\(pool) has \(members.count) teams, so its round robin takes \(needed) round\(needed == 1 ? "" : "s"); rounds \(needed + 1)–\(R) have no games for it.")
            }
            if needed > R { notes.append("\(pool) has \(members.count) teams and needs \(needed) rounds for a full round robin; only \(R) round\(R == 1 ? " is" : "s are") scheduled.") }
            // circle method; a missing team (odd pool) is a bye
            var ring: [Int?] = members.map { Optional($0) }
            if ring.count % 2 == 1 { ring.append(nil) }
            var rotation: [[(Int, Int)]] = []
            for _ in 0..<max(ring.count - 1, 0) {
                var round: [(Int, Int)] = []
                for k in 0..<(ring.count / 2) {
                    if let a = ring[k], let b = ring[ring.count - 1 - k] { round.append((a, b)) }
                }
                rotation.append(round)
                // keep the first fixed, move the last to second place
                let last = ring.removeLast()
                ring.insert(last, at: 1)
            }
            rotation.shuffle(using: &rng)
            for (offset, round) in rotation.enumerated() where offset + 1 <= R {
                for (a, b) in round where !busy[offset + 1].contains(a) && !busy[offset + 1].contains(b) {
                    pairs[offset + 1] += [a, b]
                }
            }
        }
        var openRooms = [[Int]](repeating: [], count: R + 1)
        for r in 1...R {
            let pinnedRooms = Set(games.filter { $0.round == r && $0.pinned }.map(\.room))
            openRooms[r] = rooms.map(\.id).filter { !pinnedRooms.contains($0) }
            if pairs[r].count / 2 > openRooms[r].count {
                notes.append("Round \(r) has \(pairs[r].count / 2) round-robin games but only \(openRooms[r].count) room\(openRooms[r].count == 1 ? "" : "s"); add rooms.")
                pairs[r] = Array(pairs[r].prefix(openRooms[r].count * 2))
            }
        }
        placeRooms(pairs: pairs, openRooms: openRooms, usage: &usage, rounds: R, rng: &rng)
        for issue in issues(prelimRounds: R, totalRounds: R) where issue.severity == .error { notes.append(issue.message) }
        return notes
    }
}

// MARK: - Staff

extension Schedule {
    /// Fills moderator and scorekeeper slots for rounds 1...`totalRounds` from the staff lists. People are only used when
    /// available that round, never in two rooms at once, spread evenly, and kept in the same room from round to round
    /// when they can be. Slots set by hand (pinned) are left alone.
    public mutating func autoAssignStaff(totalRounds: Int) {
        ensureSlots(totalRounds: totalRounds)
        for role in StaffRole.allCases {
            let pool = staff.filter { $0.role == role }
            var load = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, 0) })
            for g in games {
                let id = role == .moderator ? g.moderator : g.scorekeeper
                let pinned = role == .moderator ? g.moderatorPinned : g.scorekeeperPinned
                if pinned, let id { load[id, default: 0] += 1 }
            }
            var previousByRoom: [Int: Int] = [:]
            guard totalRounds >= 1 else { continue }
            for r in 1...totalRounds {
                var usedNow = Set<Int>()
                for g in slots(inRound: r) {
                    let id = role == .moderator ? g.moderator : g.scorekeeper
                    let pinned = role == .moderator ? g.moderatorPinned : g.scorekeeperPinned
                    if pinned, let id { usedNow.insert(id) }
                }
                var thisRound: [Int: Int] = [:]
                for g in slots(inRound: r) {
                    guard let s = slotIndex(round: r, room: g.room) else { continue }
                    let pinned = role == .moderator ? g.moderatorPinned : g.scorekeeperPinned
                    let needsStaff = g.hasAnyTeam || g.playoffGame != nil
                    if pinned { if let id = role == .moderator ? g.moderator : g.scorekeeper { thisRound[g.room] = id }; continue }
                    func set(_ id: Int?) {
                        if role == .moderator { games[s].moderator = id } else { games[s].scorekeeper = id }
                    }
                    guard needsStaff else { set(nil); continue }
                    let available = pool.filter { $0.isAvailable(round: r) && !usedNow.contains($0.id) }
                    var pick: StaffMember?
                    if let prev = previousByRoom[g.room], let p = available.first(where: { $0.id == prev }) { pick = p }
                    if pick == nil { pick = available.min { (load[$0.id] ?? 0, $0.id) < (load[$1.id] ?? 0, $1.id) } }
                    set(pick?.id)
                    if let p = pick { usedNow.insert(p.id); load[p.id, default: 0] += 1; thisRound[g.room] = p.id }
                }
                previousByRoom = thisRound
            }
        }
    }
}

// MARK: - Equal games

extension Schedule {
    /// When the rooms and team count make equal byes impossible over `rounds` rounds, says why and what would work.
    /// (For a fully random schedule: hand-made games and unusable rooms can change the arithmetic.)
    public func equalGamesAdvice(rounds R: Int) -> String? {
        let n = teams.count, m = rooms.count
        guard n >= 2, m >= 1, R >= 1 else { return nil }
        func sits(rooms r: Int, rounds: Int) -> Int { rounds * (n - 2 * min(r, n / 2)) }
        guard sits(rooms: m, rounds: R) % n != 0 else { return nil }
        let perRound = n - 2 * min(m, n / 2)
        let roundOptions = (1...(R + 6)).filter { sits(rooms: m, rounds: $0) % n == 0 && abs($0 - R) <= 4 }.prefix(4)
        let roomOptions = (1...(n / 2)).filter { sits(rooms: $0, rounds: R) % n == 0 && abs($0 - m) <= 8 }.prefix(4)
        var text = "With \(n) teams and \(m) room\(m == 1 ? "" : "s"), \(perRound) team\(perRound == 1 ? "" : "s") sit out each round, so \(sits(rooms: m, rounds: R)) byes over \(R) rounds cannot be shared evenly."
        var options: [String] = []
        if !roundOptions.isEmpty { options.append("\(roundOptions.map(String.init).joined(separator: ", ")) rounds") }
        if !roomOptions.isEmpty { options.append("\(roomOptions.map(String.init).joined(separator: ", ")) rooms") }
        if !options.isEmpty { text += " Equal byes would work with " + options.joined(separator: ", or ") + "." }
        return text
    }
}

// MARK: - Checking

extension Schedule {
    /// Everything wrong with the schedule. `prelimRounds` are the rounds whose teams are scheduled here; `totalRounds`
    /// also covers the playoff rounds, which only need rooms and staff.
    public func issues(prelimRounds R: Int, totalRounds: Int) -> [ScheduleIssue] {
        var out: [ScheduleIssue] = []
        guard !teams.isEmpty else { return out }
        func name(_ id: Int) -> String { team(id)?.name ?? "?" }
        func roomName(_ id: Int) -> String { room(id)?.name ?? "?" }

        if R >= 1 {
            // double booking and half-filled games
            for r in 1...R {
                var seen: [Int: String] = [:]
                for g in slots(inRound: r) {
                    if g.hasAnyTeam && !g.hasBothTeams {
                        out.append(ScheduleIssue(.error, "Round \(r), \(roomName(g.room)): only one team is assigned."))
                    }
                    for t in [g.teamA, g.teamB].compactMap({ $0 }) {
                        if let other = seen[t] {
                            out.append(ScheduleIssue(.error, "\(name(t)) is in two rooms in round \(r) (\(other) and \(roomName(g.room)))."))
                        }
                        seen[t] = roomName(g.room)
                    }
                    if let a = g.teamA, let b = g.teamB, a == b {
                        out.append(ScheduleIssue(.error, "Round \(r), \(roomName(g.room)): \(name(a)) is playing itself."))
                    }
                }
            }

            // the same number of games for everyone, byes included
            let counts = gamesPerTeam(rounds: R)
            if Set(counts.values).count > 1 {
                let groups = Dictionary(grouping: teams, by: { counts[$0.id] ?? 0 })
                let parts = groups.keys.sorted(by: >).map { n in
                    "\(n) game\(n == 1 ? "" : "s") (\(R - n) bye\(R - n == 1 ? "" : "s")): " + groups[n]!.map(\.name).joined(separator: ", ")
                }
                out.append(ScheduleIssue(.error, "Teams do not all play the same number of games. " + parts.joined(separator: "; ") + "."
                    + (equalGamesAdvice(rounds: R).map { " " + $0 } ?? "")))
            }

            // rooms
            if roomRepeatGap > 0 {
                var uses: [Int: [(round: Int, room: Int)]] = [:]
                for g in games where g.round <= R { for t in [g.teamA, g.teamB].compactMap({ $0 }) { uses[t, default: []].append((g.round, g.room)) } }
                for t in teams {
                    let list = (uses[t.id] ?? []).sorted { $0.round < $1.round }
                    for i in 0..<list.count { for j in (i + 1)..<max(list.count, i + 1) where list[j].round - list[i].round <= roomRepeatGap && list[i].room == list[j].room {
                        out.append(ScheduleIssue(.warning, "\(t.name) is in \(roomName(list[i].room)) in rounds \(list[i].round) and \(list[j].round) (within \(roomRepeatGap) round\(roomRepeatGap == 1 ? "" : "s"))."))
                    } }
                }
            }

            // schools
            if avoidSameSchool {
                for g in games where g.round <= R {
                    if let a = team(g.teamA), let b = team(g.teamB), !a.school.trimmingCharacters(in: .whitespaces).isEmpty,
                       a.school.trimmingCharacters(in: .whitespaces) == b.school.trimmingCharacters(in: .whitespaces) {
                        out.append(ScheduleIssue(.warning, "Round \(g.round), \(roomName(g.room)): \(a.name) plays \(b.name), a team from the same school."))
                    }
                }
            }
            if requireSchoolCoverage {
                for (a, b) in schoolPairsNeverMeeting(rounds: R) { out.append(ScheduleIssue(.warning, "Schools \(a) and \(b) never play each other.")) }
            }

            // round robin: every pair in a pool meets once, and nobody plays outside the pool
            if poolRoundRobin {
                let meet = meetings(rounds: R)
                for pool in poolNames {
                    let members = teams.filter { $0.pool.trimmingCharacters(in: .whitespaces) == pool }
                    for i in 0..<members.count { for j in (i + 1)..<max(members.count, i + 1) {
                        let key = [min(members[i].id, members[j].id), max(members[i].id, members[j].id)]
                        let n = meet[key] ?? 0
                        if n == 0 { out.append(ScheduleIssue(.error, "\(pool): \(members[i].name) and \(members[j].name) never play each other.")) }
                        else if n > 1 { out.append(ScheduleIssue(.warning, "\(pool): \(members[i].name) plays \(members[j].name) \(n) times.")) }
                    } }
                }
                for g in games where g.round <= R {
                    if let a = team(g.teamA), let b = team(g.teamB), a.pool != b.pool {
                        out.append(ScheduleIssue(.warning, "Round \(g.round), \(roomName(g.room)): \(a.name) (\(a.pool.isEmpty ? "no pool" : a.pool)) plays \(b.name) (\(b.pool.isEmpty ? "no pool" : b.pool)), outside the pool."))
                    }
                }
            }

            // repeated opponents, only when everyone could have met someone new each round
            if R <= teams.count - 1 && !poolRoundRobin {
                for (pair, count) in meetings(rounds: R).sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) where count > 1 {
                    out.append(ScheduleIssue(.warning, "\(name(pair[0])) plays \(name(pair[1])) \(count) times."))
                }
            }
        }

        // staff
        if totalRounds >= 1 {
            for r in 1...totalRounds {
                var used: [Int: String] = [:]
                for g in slots(inRound: r) {
                    for id in [g.moderator, g.scorekeeper].compactMap({ $0 }) {
                        guard let s = staffMember(id) else { continue }
                        if let other = used[id] {
                            out.append(ScheduleIssue(.error, "\(s.name) is assigned to two rooms in round \(r) (\(other) and \(roomName(g.room)))."))
                        }
                        used[id] = roomName(g.room)
                        if !s.isAvailable(round: r) {
                            out.append(ScheduleIssue(.warning, "\(s.name) is not available in round \(r) (\(roomName(g.room)))."))
                        }
                    }
                }
            }
        }
        return out
    }
}
