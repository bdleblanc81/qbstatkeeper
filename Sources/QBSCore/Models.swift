import Foundation

/// How bonus statistics are tracked (the "Bonus Conversion Tracking" radio group).
/// Stored in the file as two values: `trackBonus` (0/1) and `autoTrack` (0...4).
public enum BonusTracking: Int, CaseIterable, Sendable {
    case none = 0
    case manual
    case automatic
    case manualHeardAutoPoints
    case manualWithBouncebacks
    case autoWithBouncebacks

    public init(trackBonus: Int, autoTrack: Int) {
        if trackBonus == 0 { self = .none; return }
        switch autoTrack {
        case 0: self = .manual
        case 2: self = .manualHeardAutoPoints
        case 3: self = .manualWithBouncebacks
        case 4: self = .autoWithBouncebacks
        default: self = .automatic
        }
    }

    public var trackBonus: Int { self == .none ? 0 : 1 }
    public var autoTrack: Int {
        switch self {
        case .none, .manual: return 0
        case .automatic: return 1
        case .manualHeardAutoPoints: return 2
        case .manualWithBouncebacks: return 3
        case .autoWithBouncebacks: return 4
        }
    }

    public var hasBouncebacks: Bool { self == .manualWithBouncebacks || self == .autoWithBouncebacks }

    public var title: String {
        switch self {
        case .none: return "None"
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        case .manualHeardAutoPoints: return "Manual Hear, Auto Points"
        case .manualWithBouncebacks: return "Manual with Bouncebacks"
        case .autoWithBouncebacks: return "Auto with Bouncebacks"
        }
    }
}

public struct Team: Equatable, Sendable {
    public var name: String
    public var players: [String]
    /// Index into `Tournament.divisions`, or nil.
    public var division: Int?
    public var exhibition: Bool

    public init(name: String, players: [String] = [], division: Int? = nil, exhibition: Bool = false) {
        self.name = name
        self.players = players
        self.division = division
        self.exhibition = exhibition
    }
}

/// One player's line in one game. `gp` is kept as the text the user typed ("1", "0.5", "10/21").
public struct PlayerLine: Equatable, Sendable {
    public var rosterIndex: Int
    public var gp: String
    public var counts: [Int]        // 4 entries: count of each question value
    public var points: Int

    public init(rosterIndex: Int, gp: String = "1", counts: [Int] = [0, 0, 0, 0], points: Int = 0) {
        self.rosterIndex = rosterIndex
        self.gp = gp
        self.counts = counts
        self.points = points
    }

    /// Games played as a number. Accepts decimals and fractions ("0.5", "10/21"); bad input is 0.
    public var gamesPlayed: Double { Double(NS.float(gp)) }

    public static func parseGamesPlayed(_ text: String) -> Double {
        let t = text.trimmingCharacters(in: .whitespaces)
        if let slash = t.firstIndex(of: "/") {
            let n = Double(t[t.startIndex..<slash].trimmingCharacters(in: .whitespaces)) ?? 0
            let d = Double(t[t.index(after: slash)...].trimmingCharacters(in: .whitespaces)) ?? 0
            return d == 0 ? 0 : n / d
        }
        return Double(t) ?? 0
    }
}

public struct Game: Equatable, Sendable {
    public static let slotsPerSide = 8

    public var id: String
    public var teamA: Int
    public var teamB: Int
    public var scoreA: String
    public var scoreB: String
    public var tossupsHeard: Int
    public var round: Int
    public var bonusHeardA = 0, bonusPointsA = 0, bouncebackHeardA = 0, bouncebackPointsA = 0
    public var bonusHeardB = 0, bonusPointsB = 0, bouncebackHeardB = 0, bouncebackPointsB = 0
    public var overtime = 0
    public var overtimeGetsA = 0, overtimeGetsB = 0
    public var forfeit = 0
    public var lightningA = 0, lightningB = 0
    public var playersA: [PlayerLine?]
    public var playersB: [PlayerLine?]

    public init(id: String, teamA: Int, teamB: Int, scoreA: String = "0", scoreB: String = "0",
                tossupsHeard: Int = 0, round: Int = 0) {
        self.id = id
        self.teamA = teamA
        self.teamB = teamB
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.tossupsHeard = tossupsHeard
        self.round = round
        self.playersA = Array(repeating: nil, count: Game.slotsPerSide)
        self.playersB = Array(repeating: nil, count: Game.slotsPerSide)
    }

    public var isForfeit: Bool { forfeit != 0 }
    public var isOvertime: Bool { overtime != 0 }
}

public struct TournamentSettings: Equatable, Sendable {
    public var questionValues: [Int] = [15, 10, -5, 0]
    public var questionSelected: [Bool] = [true, true, true, false]
    public var bonusTracking: BonusTracking = .automatic
    public var trackPowerNeg = true
    public var trackLightning = false
    /// 0 = don't track, otherwise track tossups heard.
    public var trackTossupsHeard = 1
    public var sortPlayersByPointsPerTUH = false
    public var useDivisions = false
    /// Raw sort-method number as stored in the file (meaning still being confirmed against the SQBS binary).
    public var teamSortRaw = 0

    /// Seven flags as stored in the file. In use: [1] same player twice, [2] score inconsistencies, [4] bonus points per bonus,
    /// [5] bonus points without bonuses heard, [6] negative toss-ups heard. [0] and [3] are kept for the file but unused.
    public var warnings: [Bool] = Array(repeating: true, count: 7)

    public var tournamentName = ""
    public var ftpHost = ""
    public var ftpUser = ""
    public var ftpDirectory = ""
    public var baseName = ""
    public var alwaysUseSlashInPaths = false
    public var britishStyle = false

    /// Report order: rounds, standings, individuals, scoreboard, team detail, player detail, stat key, style sheet.
    public var reportEnabled: [Bool] = [true, true, true, true, true, true, true, false]
    public var reportNames: [String] = ["_rounds.html", "_standings.html", "_individuals.html", "_games.html",
                                        "_teamdetail.html", "_playerdetail.html", "_statkey.html", ""]

    /// 0 = packet names unused; otherwise the count read from the file.
    public var packetNamesUsed = 0
    public init() {}
}

public struct Tournament: Equatable, Sendable {
    /// Seats per side (Mac-only setting; not stored in the file). Used for default game-entry rows and the table-limit error.
    public var maxPlayersPerSide = 4
    /// Additions beyond SQBS (playoffs, tiebreakers, schedule). Stored after the standard data; ignored by SQBS.
    public var plus = PlusData()
    public var teams: [Team] = []
    public var games: [Game] = []
    public var divisions: [String] = []
    public var settings = TournamentSettings()
    /// Round number -> packet name ("-" means unnamed).
    public var packetNames: [Int: String] = [:]

    public init() {}

    public var roundRange: ClosedRange<Int>? {
        let rounds = games.map(\.round)
        guard let lo = rounds.min(), let hi = rounds.max() else { return nil }
        return lo...hi
    }
}
