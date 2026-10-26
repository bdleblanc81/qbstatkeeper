import Foundation

/// Generates the SQBS web reports. The HTML is reproduced byte-for-byte from SQBS 2.0 for Mac,
/// including its quirks (e.g. table rows with no opening `<tr>`).
public struct ReportGenerator {
    public enum Kind: Int, CaseIterable, Sendable {
        case rounds = 0, standings, individuals, scoreboard, teamDetail, playerDetail, statKey
    }

    public let tournament: Tournament
    /// Base name used in links between pages (the name typed in the save dialog).
    public let baseName: String
    public var quickPrint = false
    public var filter = RoundFilter()
    /// When true, reproduces SQBS 2.0's HTML exactly, including its malformed tags and its "W / Forfeit" row for
    /// both sides of a forfeit. When false (the default) the HTML is well formed and the forfeit loser shows "L".
    public var legacyHTML = false

    // Rates per toss-up heard are shown per 20 toss-ups heard (a typical game); the byte-for-byte SQBS copy keeps per toss-up.
    private var per20: Bool { !legacyHTML }
    private var teamRateLabel: String { british ? (per20 ? "PP20SH" : "PPSH") : (per20 ? "PP20TUH" : "PPTH") }
    private var playerRateLabel: String { british ? (per20 ? "P/20S" : "P/S") : (per20 ? "P/20TU" : "P/TU") }
    private var roundRateLabel: String { british ? (per20 ? "SPts/20SH" : "SPts/SH") : (per20 ? "TUPts/20TUH" : "TUPts/TUH") }
    private var perUnit: String { british ? (per20 ? "20 starters" : "starter") : (per20 ? "20 toss-ups" : "toss-up") }
    private func rate(_ points: Int, _ heard: Int) -> String { f(safeDivide(Float(points), Float(heard)) * (per20 ? 20 : 1), 2) }

    private let s: TournamentSettings
    private let teamStandings: [TeamStanding]
    private let playerStandings: [PlayerStanding]
    /// Standings in roster order. SQBS builds the detail pages before it sorts, so they use these.
    private let rawTeams: [TeamStanding]
    private let rawPlayers: [PlayerStanding]

    public init(tournament: Tournament, baseName: String, filter: RoundFilter = RoundFilter(), quickPrint: Bool = false, legacyHTML: Bool = false) {
        self.legacyHTML = legacyHTML
        var visible = tournament
        visible.games = tournament.statGames
        let tournament = visible
        self.tournament = tournament
        self.baseName = baseName
        self.filter = filter
        self.quickPrint = quickPrint
        self.s = tournament.settings
        // SQBS sorts players first, then teams, using its own comparators.
        self.rawPlayers = tournament.playerStandings(filter: filter)
        self.rawTeams = tournament.teamStandings(filter: filter)
        self.playerStandings = tournament.sortedPlayerStandings(rawPlayers)
        self.teamStandings = tournament.plus.playoffs.useTiebreakers
            ? tournament.tiebreakerOrder(rawTeams, players: rawPlayers, filter: filter)
            : tournament.sortedTeamStandings(rawTeams)
    }

    // MARK: - Settings helpers

    private var trackBonus: Bool { s.bonusTracking != .none }
    private var hasBouncebacks: Bool { s.bonusTracking.hasBouncebacks }
    private var trackTUH: Bool { s.trackTossupsHeard != 0 }
    private var british: Bool { s.britishStyle }
    private func selected(_ q: Int) -> Bool { s.questionSelected[q] }
    private func fileName(_ kind: Kind) -> String { s.reportNames[nameIndex(kind)] }

    private func nameIndex(_ kind: Kind) -> Int {
        // reportNames order: rounds, standings, individuals, scoreboard, teamdetail, playerdetail, statkey, style
        kind.rawValue
    }

    /// Output file name (base name + suffix) for a report.
    public func outputName(_ kind: Kind) -> String { baseName + fileName(kind) }

    private func enabled(_ kind: Kind) -> Bool { s.reportEnabled[nameIndex(kind)] }

    // MARK: - Page frame

    private func prefix(title: String) -> String {
        var h = "<HTML>\n<HEAD>\n<TITLE>" + title + "</TITLE>\n"
        if s.reportEnabled[7] { h += "<LINK REL=stylesheet TYPE=\"text/css\" HREF=\(baseName)_style.css>" }
        h += "\n</HEAD>\n<BODY>\n<table border=0 width=100%>\n<tr>\n<meta http-equiv=\"Content-Type\" content=\"text/html;charset=ISO-8859-1\" />"
        let links: [(Kind, String)] = [(.standings, "Standings"), (.individuals, "Individuals"), (.scoreboard, "Scoreboard"),
                                       (.teamDetail, "Team Detail"), (.playerDetail, "Individual Detail"),
                                       (.rounds, "Round Report"), (.statKey, "Stat Key")]
        for (kind, label) in links where enabled(kind) {
            h += "  <td><A HREF=\(baseName)\(fileName(kind))>\(label)</A></td>\n"
        }
        h += "</tr>\n</table>\n<H1>\(title)</H1><P>\n"
        return h
    }

    private let suffix = "</BODY>\n</HTML>\n"

    private func title(_ what: String) -> String { "\(s.tournamentName) \(what) " }

    // MARK: - Formatting

    private func f(_ x: Float, _ digits: Int) -> String { String(format: "%.\(digits)f", Double(x)) }

    private func teamName(_ i: Int) -> String { tournament.teams[i].name }

    /// P/N text for counts (power, neg).
    private func ratioPN(_ q: [Int]) -> String {
        if q[0] > 0 && q[2] == 0 { return "inf" }
        return f(safeDivide(Float(q[0]), Float(q[2])), 2)
    }

    private func ratioGN(_ q: [Int]) -> String {
        let gets = q[0] + q[1] + q[3]
        if gets > 0 && q[2] == 0 { return "inf" }
        return f(safeDivide(Float(gets), Float(q[2])), 2)
    }

    // MARK: - Pages

    public func page(_ kind: Kind) -> String {
        switch kind {
        case .standings: return standingsPage()
        case .individuals: return individualsPage()
        case .scoreboard: return scoreboardPage()
        case .rounds: return roundsPage()
        case .statKey: return statKeyPage()
        case .teamDetail: return teamDetailPage()
        case .playerDetail: return playerDetailPage()
        }
    }

    /// All pages that are switched on, keyed by file name.
    public func allPages() -> [(name: String, html: String)] {
        Kind.allCases.filter(enabled).map { (outputName($0), page($0)) }
    }

    /// ISO-8859-1 bytes, as SQBS writes them (characters outside Latin-1 become `?`).
    public static func encode(_ html: String) -> Data {
        html.data(using: .isoLatin1, allowLossyConversion: true) ?? Data()
    }

    // MARK: Team standings

    private func standingsPage() -> String {
        var out = quickPrint ? "" : prefix(title: title("Team Standings"))
        let divisions: [String?] = (s.useDivisions && !tournament.divisions.isEmpty) ? tournament.divisions.map { $0 } : [nil]
        let link = enabled(.teamDetail) && !quickPrint
        for division in divisions {
            if let d = division { out += "<P><P><H2>\(d)</H2><P>" }
            out += "<table border=\(quickPrint ? 0 : 1)"
            out += " width=100%>\n" + (legacyHTML ? "" : "<tr>\n") + "  <td ALIGN=LEFT><B>Rank</B></td>\n  <td ALIGN=LEFT><B>Team</B></td>\n  <td ALIGN=RIGHT><B>W</B></td>\n  <td ALIGN=RIGHT><B>L</B></td>\n  <td ALIGN=RIGHT><B>T</B></td>\n  <td ALIGN=RIGHT><B>Pct</B></td>\n  <td ALIGN=RIGHT><B>PPG</B></td>\n  <td ALIGN=RIGHT><B>PAPG</B></td>\n  <td ALIGN=RIGHT><B>Mrg</B></td>\n"
            if s.teamSortRaw == 3 { out += "  <td ALIGN=RIGHT><B>SoS</B></td>\n" }
            for q in 0..<4 where selected(q) { out += "  <td ALIGN=RIGHT><B>\(s.questionValues[q])</B></td>\n" }
            if trackTUH {
                out += british ? "  <td ALIGN=RIGHT><B>SH</B></td>\n  <td ALIGN=RIGHT><B>\(playerRateLabel)</B></td>\n"
                               : "  <td ALIGN=RIGHT><B>TUH</B></td>\n  <td ALIGN=RIGHT><B>\(playerRateLabel)</B></td>\n"
            }
            if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>P/N</B></td>\n  <td ALIGN=RIGHT><B>G/N</B></td>\n" }
            if s.trackLightning { out += "  <td ALIGN=RIGHT><B>Ltng</B></td>\n" }
            if trackBonus {
                out += "  <td ALIGN=RIGHT><B>BHrd</B></td>\n  <td ALIGN=RIGHT><B>BPts</B></td>\n  <td ALIGN=RIGHT><B>P/B</B></td>\n"
                if hasBouncebacks {
                    out += "  <td ALIGN=RIGHT><B>BBHrd</B></td>\n  <td ALIGN=RIGHT><B>BBPts</B></td>\n  <td ALIGN=RIGHT><B>P/BB</B></td>\n"
                }
            }
            out += "</tr>"

            var rank = 1
            for st in teamStandings {
                if s.useDivisions {
                    let team = tournament.teams[st.teamIndex]
                    let name = team.division.map { tournament.divisions[$0] }
                    if name != division { continue }
                }
                guard st.gamesPlayed > 0 else { continue }
                out += "<tr>\n  <td ALIGN=LEFT>\(rank)</td>"
                rank += 1
                out += "  <td ALIGN=LEFT>\n"
                if link { out += "<A HREF=\(baseName)\(fileName(.teamDetail))#t\(st.teamIndex)>" }
                out += st.teamName
                if link { out += "</A>" }
                let ppg = safeDivide(Float(st.pointsFor), Float(st.scoredGames))
                let papg = safeDivide(Float(st.pointsAgainst), Float(st.scoredGames))
                let mrg = ppg - papg
                out += "</td>\n  <td ALIGN=RIGHT>\(st.win + st.forfeitWin)</td>\n  <td ALIGN=RIGHT>\(st.loss + st.forfeitLoss)</td>\n  <td ALIGN=RIGHT>\(st.tie)</td>\n"
                out += "  <td ALIGN=RIGHT>\(f(st.pct, 3))</td>\n  <td ALIGN=RIGHT>\(f(ppg, 1))</td>\n  <td ALIGN=RIGHT>\(f(papg, 1))</td>\n  <td ALIGN=RIGHT>\(f(mrg, 1))</td>\n"
                if s.teamSortRaw == 3 {
                    out += "  <td ALIGN=RIGHT>\(f(safeDivide(st.strength, Float(st.scoredGames + 1)), 1))</td>\n"
                }
                for q in 0..<4 where selected(q) { out += "  <td ALIGN=RIGHT>\(st.q[q])</td>\n" }
                if trackTUH {
                    out += "  <td ALIGN=RIGHT>\(st.tossUpsHeard)</td>\n  <td ALIGN=RIGHT>\(rate(st.pointsFor, st.tossUpsHeard))</td>\n"
                }
                if s.trackPowerNeg {
                    out += "  <td ALIGN=RIGHT>\(ratioPN(st.q))</td>\n  <td ALIGN=RIGHT>\(ratioGN(st.q))</td>\n"
                }
                if s.trackLightning { out += "  <td ALIGN=RIGHT>\(st.lightning)</td>\n" }
                if trackBonus {
                    out += "  <td ALIGN=RIGHT>\(st.bonusHeard)</td>\n  <td ALIGN=RIGHT>\(st.bonusPoints)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(st.bonusPoints), Float(st.bonusHeard)), 2))</td>\n"
                    if hasBouncebacks {
                        out += "  <td ALIGN=RIGHT>\(st.bouncebacksHeard)</td>\n  <td ALIGN=RIGHT>\(st.bouncebacksPoints)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(st.bouncebacksPoints), Float(st.bouncebacksHeard)), 2))</td>\n"
                    }
                }
                out += "</tr>"
            }
            out += "</table>\n"
        }
        return out + (quickPrint ? "" : suffix)
    }

    // MARK: Individual standings

    private func individualsPage() -> String {
        var out = quickPrint ? "" : prefix(title: title("Individual Statistics"))
        out += "<table border=\(quickPrint ? 0 : 1)"
        out += " width=100%>\n<tr>\n  <td ALIGN=LEFT><B>Rank</B></td>\n  <td ALIGN=LEFT><B>Player</B></td>\n  <td ALIGN=LEFT><B>Team</B></td>\n"
        if s.useDivisions { out += "  <td ALIGN=LEFT><B>Division</B></td>\n" }
        out += "  <td ALIGN=RIGHT><B>GP</B></td>\n"
        for q in 0..<4 where selected(q) { out += "  <td ALIGN=RIGHT><B>\(s.questionValues[q])</B></td>\n" }
        if trackTUH {
            out += british ? "  <td ALIGN=RIGHT><B>SH</B></td>\n  <td ALIGN=RIGHT><B>\(playerRateLabel)</B></td>\n"
                           : "  <td ALIGN=RIGHT><B>TUH</B></td>\n  <td ALIGN=RIGHT><B>\(playerRateLabel)</B></td>\n"
        }
        if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>P/N</B></td>\n  <td ALIGN=RIGHT><B>G/N</B></td>\n" }
        out += "  <td ALIGN=RIGHT><B>Pts</B></td>\n  <td ALIGN=RIGHT><B>PPG</B></td>\n</tr>\n"

        let link = enabled(.playerDetail) && !quickPrint
        var rank = 0
        for p in playerStandings where p.gamesPlayed > 0 {
            rank += 1
            out += "<tr>\n  <td ALIGN=LEFT>\(rank)</td>\n  <td ALIGN=LEFT>"
            if link { out += "<A HREF=\(baseName)\(fileName(.playerDetail))#p\(p.position)_\(p.teamIndex)>" }
            out += p.playerName
            if link { out += "</A>" }
            out += "</td>\n  <td ALIGN=LEFT>\(p.teamName)</td>\n"
            if s.useDivisions {
                if p.teamIndex >= 0, let d = tournament.teams[p.teamIndex].division {
                    out += "  <td ALIGN=LEFT>\(tournament.divisions[d])</td>\n"
                } else {
                    out += "  <td ALIGN=LEFT> </td>\n"
                }
            }
            out += "  <td ALIGN=RIGHT>\(f(p.gamesPlayed, 2))</td>\n"
            for q in 0..<4 where selected(q) { out += "  <td ALIGN=RIGHT>\(p.q[q])</td>\n" }
            if trackTUH {
                out += "  <td ALIGN=RIGHT>\(p.tossUpsHeard)</td>\n  <td ALIGN=RIGHT>\(rate(p.points, p.tossUpsHeard))</td>\n"
            }
            if s.trackPowerNeg {
                out += "  <td ALIGN=RIGHT>\(ratioPN(p.q))</td>\n  <td ALIGN=RIGHT>\(ratioGN(p.q))</td>\n"
            }
            out += "  <td ALIGN=RIGHT>\(p.points)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(p.points), p.gamesPlayed), 2))</td>\n</tr>\n"
        }
        if !legacyHTML { out += "</table>\n" }
        return out + (quickPrint ? "" : suffix)
    }

    // MARK: Scoreboard

    private func sortedGamesByRound() -> [Game] {
        // sortGameByRound: stable ordering by round number
        tournament.games.enumerated().sorted { a, b in
            a.element.round != b.element.round ? a.element.round < b.element.round : a.offset < b.offset
        }.map(\.element)
    }

    private func packetSuffix(_ round: Int) -> String {
        guard s.packetNamesUsed > 0, let name = tournament.packetNames[round], name != "-" else { return "" }
        return " (Packet: \(name))"
    }

    private func scoreboardPage() -> String {
        var out = prefix(title: title("Scoreboard"))
        let games = sortedGamesByRound()
        guard let first = games.first else { return out + suffix }
        var current = filter.all ? first.round : max(first.round, filter.min)
        var body = ""
        if enabled(.rounds) {
            body += "<FONT SIZE=+1 COLOR=red>Round \(current)" + packetSuffix(current) + "</FONT><P>\n"
        }
        for g in games {
            if !filter.includes(g.round) { continue }
            guard g.teamA >= 0, g.teamB >= 0 else { continue }
            if enabled(.rounds) && g.round > current {
                current = g.round
                body += "<hr><FONT SIZE=+1 COLOR=red>Round \(current)" + packetSuffix(current) + "</FONT><P>\n"
            }
            let a = teamName(g.teamA), b = teamName(g.teamB)
            if g.isForfeit {
                body += "<FONT SIZE=+1>\(a) defeats \(b) by forfeit" + (legacyHTML ? "</H2>\n" : "\n")
            } else {
                let sa = NS.int(g.scoreA), sb = NS.int(g.scoreB)
                if sa != -1 && sb != -1 {
                    if sa > sb { body += "<FONT SIZE=+1>\(a) \(sa), \(b) \(sb)" }
                    else { body += "<FONT SIZE=+1>\(b) \(sb), \(a) \(sa)" }
                    if sa == sb { body += " Tie" }
                    if g.isOvertime { body += " OT" }
                    body += "</FONT><br>\n<FONT SIZE=-1>\n\(a): "
                    body += playerLine(g.playersA, team: g.teamA)
                    body += "<br>\n\(b): "
                    body += playerLine(g.playersB, team: g.teamB)
                    body += "<br>\n"
                    if s.trackLightning {
                        body += "Lightning: \(a) \(g.lightningA), \(b) \(g.lightningB)<br>\n"
                    }
                    if trackBonus {
                        body += "Bonuses: \(a) \(g.bonusHeardA) \(g.bonusPointsA) \(f(safeDivide(Float(g.bonusPointsA), Float(g.bonusHeardA)), 2)), "
                        body += "\(b) \(g.bonusHeardB) \(g.bonusPointsB) \(f(safeDivide(Float(g.bonusPointsB), Float(g.bonusHeardB)), 2))<br>\n"
                        if hasBouncebacks {
                            body += "Bonus Bouncebacks: \(a) \(g.bouncebackHeardA) \(g.bouncebackPointsA) \(f(safeDivide(Float(g.bouncebackPointsA), Float(g.bouncebackHeardA)), 2)), "
                            body += "\(b) \(g.bouncebackHeardB) \(g.bouncebackPointsB) \(f(safeDivide(Float(g.bouncebackPointsB), Float(g.bouncebackHeardB)), 2))<br>\n"
                        }
                    }
                }
            }
            if !legacyHTML && !g.isForfeit && (NS.int(g.scoreA) == -1 || NS.int(g.scoreB) == -1) { continue }
            body += "<P></FONT>\n"
        }
        return out + body + suffix
    }

    private func playerLine(_ slots: [PlayerLine?], team: Int) -> String {
        var parts: [String] = []
        for slot in slots {
            guard let p = slot, Tournament.roundedGP(p.gp) > 0 else { continue }
            let roster = tournament.teams[team].players
            let name = p.rosterIndex >= 0 && p.rosterIndex < roster.count ? roster[p.rosterIndex] : ""
            var cell = name + " "
            for q in 0..<4 where selected(q) { cell += "\(p.counts[q]) " }
            cell += "\(p.points)"
            parts.append(cell)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Quick-print games report

    /// The compact "Games" quick report shown in the Reports tab.
    public func quickGamesPage() -> String {
        let close = legacyHTML ? "" : "</td>\n"
        func cells(_ w: String, _ ws: Int, _ l: String, _ ls: Int) -> String {
            "  <td style=\"width:30%\">\n\(w)\(close)  <td style=\"width:15%\">\n\(ws)\(close)  <td style=\"width:30%\">\n\(l)\(close)  <td style=\"width:15%\">\n\(ls)\(close)"
        }
        var out = "<table border=0  style=\"width:500px\""
        let games = sortedGamesByRound()
        guard let first = games.first else { return out + "</table>\n" + suffix }
        var current = filter.all ? first.round : max(first.round, filter.min)
        if enabled(.rounds) {
            out += "<tr>\n  <td></td>\n</tr>\n<tr>\n  <td colspan=4><B>Round \(current)" + packetSuffix(current) + "</B></td>\n</tr>\n<tr>\n"
        }
        for g in games {
            guard filter.includes(g.round), g.teamA >= 0, g.teamB >= 0 else { continue }
            if enabled(.rounds) && g.round > current {
                current = g.round
                out += "<tr>\n  <td></td>\n</tr>\n<tr>\n  <td colspan=4><B>Round \(current)" + packetSuffix(current) + "</B></td>\n</tr>\n<tr>\n"
            }
            let a = teamName(g.teamA), b = teamName(g.teamB)
            out += "<tr>\n"
            if g.isForfeit {
                out += "  <td colspan=4>\(a) defeats \(b) by forfeit</td>\n"
            } else {
                let sa = NS.int(g.scoreA), sb = NS.int(g.scoreB)
                if sa != -1 && sb != -1 {
                    if sa > sb { out += cells(a, sa, b, sb) }
                    else { out += cells(b, sb, a, sa) }
                    if sa == sb { out += "  <td style=\"width:10%\">\nTie</td>\n" }
                    if g.isOvertime { out += "  <td style=\"width:10%\">\nOT</td>\n" }
                }
            }
            out += "</tr>\n"
        }
        return out + "</table>\n" + suffix
    }

    // MARK: Round report

    private func roundsPage() -> String {
        var out = prefix(title: title("Round Report"))
        let games = sortedGamesByRound()
        guard let lo = games.map(\.round).min(), let hi = games.map(\.round).max() else {
            return out + tableHeaderForRounds() + "</table>\n" + suffix
        }
        struct RoundData { var points = 0, games = 0, tuh = 0, lightning = 0, bonusHeard = 0, bonusPoints = 0, bbHeard = 0, bbPoints = 0, tuPoints = 0 }
        var data: [Int: RoundData] = [:]
        for g in games where !g.isForfeit && g.teamA >= 0 && g.teamB >= 0 {
            var d = data[g.round] ?? RoundData()
            d.points += NS.int(g.scoreA) + NS.int(g.scoreB)
            d.games += 2
            d.tuh += g.tossupsHeard
            d.lightning += g.lightningA + g.lightningB
            d.bonusHeard += g.bonusHeardA + g.bonusHeardB
            d.bonusPoints += g.bonusPointsA + g.bonusPointsB
            if hasBouncebacks {
                d.bbHeard += g.bouncebackHeardA + g.bouncebackHeardB
                d.bbPoints += g.bouncebackPointsA + g.bouncebackPointsB
            }
            d.tuPoints += g.playersA.compactMap { $0?.points }.reduce(0, +) + g.playersB.compactMap { $0?.points }.reduce(0, +)
            data[g.round] = d
        }
        _ = (lo, hi)
        out += tableHeaderForRounds()
        for round in data.keys.sorted() {
            let d = data[round]!
            if !filter.all && (round < filter.min || round > filter.max) { continue }
            guard d.games > 0 else { continue }
            var label = "\(round)"
            if let name = tournament.packetNames[round], name != "-" { label = name }
            out += (legacyHTML ? "" : "<tr>\n") + "  <td>\(label)</td>\n"
            out += "  <td>\(f(safeDivide(Float(d.points), Float(d.games)), 2))</td>\n"
            if trackTUH { out += "  <td>\(rate(d.tuPoints, d.tuh))</td>\n" }
            if s.trackLightning { out += "  <td>\(f(safeDivide(Float(d.lightning), Float(d.games)), 2))</td>\n" }
            if trackBonus {
                out += "  <td>\(f(safeDivide(Float(d.bonusPoints), Float(d.bonusHeard)), 2))</td>\n"
                if hasBouncebacks { out += "  <td>\(f(safeDivide(Float(d.bbPoints), Float(d.bbHeard)), 2))</td>\n" }
            }
            out += "</tr>\n"
        }
        return out + "</table>\n" + suffix
    }

    private func tableHeaderForRounds() -> String {
        var h = "<table border=1 width=100%>\n<tr>\n  <td><B>Round</B></td>\n  <td><B>PPG/Team</B></td>\n"
        if trackTUH { h += british ? "  <td><B>\(roundRateLabel)</B></td>\n" : "  <td><B>\(roundRateLabel)</B></td>\n" }
        if s.trackLightning { h += "  <td><B>Pts/LtngRd</B></td>\n" }
        if trackBonus {
            h += "  <td><B>BPts/BHrd</B></td>\n"
            if hasBouncebacks { h += "  <td><B>BBPts/BBHrd</B></td>\n" }
        }
        return h + "</tr>\n"
    }

    // MARK: Stat key

    private func statKeyPage() -> String {
        var out = prefix(title: title("Stat Key"))
        let tu = british ? "starters" : "toss-ups"
        out += "<H2><A NAME=TeamStandings>Team Standings</A></H2><br>\n<table border=1 width=100%>\n<tr>\n<td>W, L, T</td>\n<td>Number of games won (W), lost (L), or tied (T)</td>\n"
        out += "</tr>\n<tr>\n<td>Pct</td>\n<td>Fraction of games won</td>\n</tr>\n<tr>\n<td>PPG</td>\n<td>Average number of points scored by the team in a game</td>\n</tr>\n<tr>\n<td>PAPG</td>\n<td>Average number of points scored against the team in a game</td>\n</tr>\n<tr>\n"
        out += "<td>Mrg</td>\n<td>Team's average margin of victory (if positive) or defeat (if negative)</td>\n</tr>\n"
        if s.teamSortRaw == 3 {
            out += "<tr>\n<td>SoS</td>\n<td>Strength of schedule: Average of own PPG and all opponents' total PPG</td>\n</tr>\n"
        }
        let values = (0..<4).filter(selected).map { "\(s.questionValues[$0]) " }.joined()
        let countRow = "<tr>\n<td>\(values)</td>\n<td>Number of \(tu) answered for the corresponding point value (negative point values are for incorrect interrupts)</td>\n</tr>\n"
        out += countRow
        out += "<tr>\n"
        if trackTUH {
            out += british
                ? "<td>SH</td>\n<td>Total number of starters heard by the team</td>\n</tr>\n<tr>\n<td>\(teamRateLabel)</td>\n<td>Average number of points scored by the team per \(perUnit) heard</td>\n</tr>\n"
                : "<td>TUH</td>\n<td>Total number of toss-ups heard by the team</td>\n</tr>\n<tr>\n<td>\(teamRateLabel)</td>\n<td>Average number of points scored by the team per \(perUnit) heard</td>\n</tr>\n"
        } else {
            out = String(out.dropLast("<tr>\n".count))
        }
        if s.trackPowerNeg { out += "<tr>\n<td>P/N</td>\n<td>Ratio of powers to negs</td>\n</tr>\n<tr>\n<td>G/N</td>\n<td>Ratio of gets (correctly answered questions) to negs</td>\n</tr>\n" }
        if s.trackLightning { out += "<tr>\n<td>Ltng</td>\n<td>Total number of points scored by the team in the lightning round</td>\n</tr>\n" }
        if trackBonus {
            out += "<tr>\n<td>BHrd</td>\n<td>Total number of bonus questions heard by the team</td>\n</tr>\n"
            out += "<tr>\n<td>BPts</td>\n<td>Total number of points scored by the team on bonus questions</td>\n</tr>\n"
            out += "<tr>\n<td>P/B</td>\n<td>Average number of points scored by the team on bonus questions</td>\n</tr>\n"
            if hasBouncebacks {
                out += "<tr>\n<td>BBHrd</td>\n<td>Total number of bonus bouncebacks heard by the team</td>\n</tr>\n"
                out += "<tr>\n<td>BBPts</td>\n<td>Total number of points scored by the team on bonus bouncebacks</td>\n</tr>\n"
                out += "<tr>\n<td>P/BB</td>\n<td>Average number of points scored by the team on bonus bouncebacks</td>\n</tr>\n"
            }
        }
        out += "</table><P>\n"

        // Individual statistics
        out += "<H2><A NAME=IndividualStandings>Individual Statistics</A></H2><br>\n<table border=1 width=100%>\n<tr>\n<td>GP</td>\n<td>Number of games in which the player participated</td>\n</tr>\n<tr>\n<td>"
        out += values + "</td>\n<td>Number of \(tu) answered for the corresponding point value (negative point values are for incorrect interrupts)</td>\n</tr>\n"
        out += "<tr>\n"
        if trackTUH {
            out += british
                ? "<td>SH</td>\n<td>Total number of starters heard by the player</td>\n</tr>\n<tr>\n<td>\(playerRateLabel)</td>\n<td>Average number of points scored by the player per \(perUnit) heard</td>\n</tr>\n"
                : "<td>TUH</td>\n<td>Total number of toss-ups heard by the player</td>\n</tr>\n<tr>\n<td>\(playerRateLabel)</td>\n<td>Average number of points scored by the player per \(perUnit) heard</td>\n</tr>\n"
        } else {
            out = String(out.dropLast("<tr>\n".count))
        }
        if s.trackPowerNeg { out += "<tr>\n<td>P/N</td>\n<td>Ratio of powers to negs</td>\n</tr>\n<tr>\n<td>G/N</td>\n<td>Ratio of gets (correctly answered questions) to negs</td>\n</tr>\n" }
        out += "<tr>\n<td>Pts</td>\n<td>Total number of points scored by the player</td>\n</tr>\n<tr>\n<td>PPG</td>\n<td>Average number of points scored by the player per game</td>\n</tr>\n</table><P>\n"

        // Scoreboard
        out += "<H2><A NAME=Scoreboard>Scoreboard</A></H2><br>\nFor each game, the score is listed in large bold print on the first line.  Then each individual who played in the game is listed, by team, along with "
        out += "the number of each type of question answered (in the order that they appear in the other reports (usually decreasing order, such as 15 10 -5).  The last number after each name is the individual's total points for the game.\n"
        if s.trackLightning { out += "The next line of the boxscore gives, for each team, the total number of points scored in the lightning round.  \n" }
        if trackBonus {
            out += "The next line of the boxscore gives, for each team, the total number of bonuses heard, the total number of points scored on bonuses, and the average number of points scored per bonus heard."
            if hasBouncebacks {
                out += "The next line of the boxscore gives, for each team, the total number of bonus bouncebacks heard, the total number of points scored on bonus bouncebacks, and the average number of points scored per bonus bounceback heard."
            }
        }
        out += "<P><P>\n"

        // Team detail
        out += "<H2><A NAME=TeamDetail>Team Detail</A></H2><br>\n<table border=1 width=100%>\n<tr>\n<td>Result</td>\n<td>Whether the team won (W), lost (L), or tied (T) the game</td>\n</tr>\n<tr>\n"
        out += "<td>PF</td>\n<td>Total number of points scored by the team</td>\n</tr>\n<tr>\n<td>PA</td>\n<td>Total number of points scored by the opponent</td>\n</tr>\n<tr>\n<td>"
        out += values + "</td>\n<td>Number of \(tu) answered for the corresponding point value (negative point values are for incorrect interrupts)</td>\n</tr>\n"
        out += "<tr>\n"
        if trackTUH {
            out += british
                ? "<td>SH</td>\n<td>Total number of starters heard</td>\n</tr>\n<tr>\n<td>\(teamRateLabel)</td>\n<td>Average number of points scored by the team per \(perUnit) heard</td>\n</tr>\n"
                : "<td>TUH</td>\n<td>Total number of toss-ups heard</td>\n</tr>\n<tr>\n<td>\(teamRateLabel)</td>\n<td>Average number of points scored by the team per \(perUnit) heard</td>\n</tr>\n"
        } else {
            out = String(out.dropLast("<tr>\n".count))
        }
        if s.trackPowerNeg {
            out += "<tr>\n<td>P/N</td>\n<td>Ratio of powers to negs</td>\n</tr>\n"
            out += "<tr>\n<td>G/N</td>\n<td>Ratio of gets (correctly answered questions) to negs</td>\n</tr>\n"
        }
        if s.trackLightning { out += "<tr>\n<td>Ltng</td>\n<td>Total number of points scored by the team in the lightning round</td>\n</tr>\n" }
        if trackBonus {
            out += "<tr>\n<td>BHrd</td>\n<td>Total number of bonus questions heard by the team</td>\n</tr>\n"
            out += "<tr>\n<td>BPts</td>\n<td>Total number of points scored by the team on bonus questions</td>\n</tr>\n"
            out += "<tr>\n<td>P/B</td>\n<td>Average number of points scored by the team on bonus questions</td>\n</tr>\n"
            if hasBouncebacks {
                out += "<tr>\n<td>BBHrd</td>\n<td>Total number of bonus bouncebacks heard by the team</td>\n</tr>\n"
                out += "<tr>\n<td>BBPts</td>\n<td>Total number of points scored by the team on bonus bouncebacks</td>\n</tr>\n"
                out += "<tr>\n<td>P/BB</td>\n<td>Average number of points scored by the team on bonus bouncebacks</td>\n</tr>\n"
            }
        }
        out += "</table><P>\n"

        // Individual detail
        out += "<H2><A NAME=IndividualDetail>Individual Detail</A></H2><br>\n<table border=1 width=100%>\n<tr>\n<td>GP</td>\n<td>Number of games in which the player participated</td>\n</tr>\n<tr>\n<td>"
        out += values + "</td>\n<td>Number of \(tu) answered for the corresponding point value (negative point values are for incorrect interrupts)</td>\n</tr>\n"
        out += "<tr>\n"
        if trackTUH {
            out += british
                ? "<td>SH</td>\n<td>Total number of starters heard by the player</td>\n</tr>\n<tr>\n<td>\(playerRateLabel)</td>\n<td>Average number of points scored by the player per \(perUnit) heard</td>\n</tr>\n"
                : "<td>TUH</td>\n<td>Total number of toss-ups heard by the player</td>\n</tr>\n<tr>\n<td>\(playerRateLabel)</td>\n<td>Average number of points scored by the player per \(perUnit) heard</td>\n</tr>\n"
        } else {
            out = String(out.dropLast("<tr>\n".count))
        }
        if s.trackPowerNeg { out += "<tr>\n<td>P/N</td>\n<td>Ratio of powers to negs</td>\n</tr>\n<tr>\n<td>G/N</td>\n<td>Ratio of gets (correctly answered questions) to negs</td>\n</tr>\n" }
        out += "<tr>\n<td>Pts</td>\n<td>Total number of points scored by the player</td>\n</tr>\n<tr>\n<td>PPG</td>\n<td>Average number of points scored by the player per game</td>\n</tr>\n</table><P>\n"

        // Round report
        out += "<H2><A NAME=RoundReport>Round Report</A></H2><br>\n<table border=1 width=100%>\n<tr>\n<td>PPG/Team</td>\n<td>Average number of points scored per team per game</td>\n</tr>\n"
        if trackTUH { out += "<tr>\n<td>\(roundRateLabel).</td>\n<td>Average number of points scored on \(british ? "starter" : "toss-up") questions per \(perUnit) heard</td>\n</tr>\n" }
        if s.trackLightning { out += "<tr>\n<td>Pts/LtngRd</td>\n<td>Average number of points scored in the lightning round per team per game</td></td>\n</tr>\n" }
        if trackBonus {
            out += "<tr>\n<td>BPts/BH</td>\n<td>Average number of points scored on bonus questions per bonus heard</td>\n</tr>\n"
            if hasBouncebacks { out += "<tr>\n<td>BBPts/BBH</td>\n<td>Average number of points scored on bonus bouncebacks per bonus bounceback heard</td>\n</tr>\n" }
        }
        out += "</table><P>\n"
        out += legacyHTML
            ? "For information about this statistics program, visit the <A HREF=http://www.stanford.edu/~csewell/sqbs/index.htm>SQBS homepage</A>."
            : "Statistics generated by Quiz Bowl Statkeeper for Mac."
        return out + suffix
    }

    // MARK: Detail pages

    private var packetColumn: Bool { enabled(.rounds) && s.packetNamesUsed > 0 }

    private func packetCell(_ round: Int, typo: Bool = false) -> String {
        var label = " "
        if let name = tournament.packetNames[round] { label = name }
        if label == "-" { label = "\(round)" }
        return "  <td ALIGN=LEFT>\(label)</td>\n" + (typo ? "n" : "")
    }

    private func valueHeaders() -> String {
        (0..<4).filter(selected).map { "  <td ALIGN=RIGHT><B>\(s.questionValues[$0])</B></td>\n" }.joined()
    }

    private func tuhHeader(_ team: Bool) -> String {
        guard trackTUH else { return "" }
        if team { return british ? "  <td ALIGN=RIGHT><B>SH</B></td>\n  <td ALIGN=RIGHT><B>\(teamRateLabel)</B></td>\n" : "  <td ALIGN=RIGHT><B>TUH</B></td>\n  <td ALIGN=RIGHT><B>\(teamRateLabel)</B></td>\n" }
        return british ? "  <td ALIGN=RIGHT><B>SH</B></td>\n  <td ALIGN=RIGHT><B>\(playerRateLabel)</B></td>\n" : "  <td ALIGN=RIGHT><B>TUH</B></td>\n  <td ALIGN=RIGHT><B>\(playerRateLabel)</B></td>\n"
    }

    private func teamDetailPage() -> String {
        var out = prefix(title: title("Team Details"))
        let games = sortedGamesByRound()
        for st in rawTeams {
            guard st.gamesPlayed > 0 else { continue }
            let i = st.teamIndex
            out += "<P><P><H2><A NAME=t\(i)>\(st.teamName)</A></H2><P>\n"
            out += "<table border=1 width=100%>\n<tr>\n<td ALIGN=LEFT><B>Opponent</B></td>\n<td ALIGN=RIGHT><B>Result</B></td>\n<td ALIGN=RIGHT><B>PF</B></td>\n<td ALIGN=RIGHT><B>PA</B></td>\n"
            out += valueHeaders() + tuhHeader(true)
            if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>P/N</B></td>\n  <td ALIGN=RIGHT><B>G/N</B></td>\n" }
            if s.trackLightning { out += "  <td ALIGN=RIGHT><B>Ltng</B></td>\n" }
            if trackBonus {
                out += "  <td ALIGN=RIGHT><B>BHrd</B></td>\n  <td ALIGN=RIGHT><B>BPts</B></td>\n  <td ALIGN=RIGHT><B>P/B</B></td>\n"
                if hasBouncebacks { out += "  <td ALIGN=RIGHT><B>BBHrd</B></td>\n  <td ALIGN=RIGHT><B>BBPts</B></td>\n  <td ALIGN=RIGHT><B>P/BB</B></td>\n" }
            }
            if packetColumn { out += "  <td ALIGN=LEFT><B>Packet</B></td>\n" }
            out += "</tr>\n"

            for g in games where filter.includes(g.round) {
                for isA in [true, false] {
                    let mine = isA ? g.teamA : g.teamB
                    let other = isA ? g.teamB : g.teamA
                    guard mine == i, other >= 0 else { continue }
                    out += "<tr>\n  <td ALIGN=LEFT>\(teamName(other))</td>\n"
                    if g.isForfeit {
                        // SQBS prints "W / Forfeit" for both sides of a forfeit; the loser is shown as "L" unless legacy.
                        let result = (isA || legacyHTML) ? "W" : "L"
                        out += "  <td ALIGN=RIGHT>\(result)</td>\n  <td ALIGN=RIGHT>Forfeit</td>\n</tr>\n"
                        continue
                    }
                    let sa = NS.int(g.scoreA), sb = NS.int(g.scoreB)
                    let result: String
                    if isA { result = sa > sb ? "W" : (sa == sb ? "T" : "L") } else { result = sb > sa ? "W" : (sa == sb ? "T" : "L") }
                    out += "  <td ALIGN=RIGHT>\(result)</td>\n  <td ALIGN=RIGHT>\(isA ? g.scoreA : g.scoreB)</td>\n  <td ALIGN=RIGHT>\(isA ? g.scoreB : g.scoreA)</td>\n"
                    var q = [0, 0, 0, 0]
                    for slot in (isA ? g.playersA : g.playersB) { if let p = slot { for k in 0..<4 { q[k] += p.counts[k] } } }
                    for k in 0..<4 where selected(k) { out += "  <td ALIGN=RIGHT>\(q[k])</td>\n" }
                    let myScore = NS.int(isA ? g.scoreA : g.scoreB)
                    if trackTUH {
                        out += "  <td ALIGN=RIGHT>\(g.tossupsHeard)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(myScore), Float(g.tossupsHeard)), 2))</td>\n"
                    }
                    if s.trackPowerNeg { out += "  <td ALIGN=RIGHT>\(ratioPN(q))</td>\n  <td ALIGN=RIGHT>\(ratioGN(q))</td>\n" }
                    if s.trackLightning { out += "  <td ALIGN=RIGHT>\(isA ? g.lightningA : g.lightningB)</td>\n" }
                    if trackBonus {
                        let h = isA ? g.bonusHeardA : g.bonusHeardB, pts = isA ? g.bonusPointsA : g.bonusPointsB
                        out += "  <td ALIGN=RIGHT>\(h)</td>\n  <td ALIGN=RIGHT>\(pts)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(pts), Float(h)), 2))</td>\n"
                        if hasBouncebacks {
                            let bh = isA ? g.bouncebackHeardA : g.bouncebackHeardB, bp = isA ? g.bouncebackPointsA : g.bouncebackPointsB
                            out += "  <td ALIGN=RIGHT>\(bh)</td>\n  <td ALIGN=RIGHT>\(bp)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(bp), Float(bh)), 2))</td>\n"
                        }
                    }
                    // With packet names off SQBS never closes the row (browsers cope).
                    if packetColumn { out += packetCell(g.round) + "</tr>\n" } else if !legacyHTML { out += "</tr>\n" }
                }
            }

            out += "<tr>\n  <td ALIGN=LEFT><B>Total</B></td>\n  <td></td>\n"
            out += "  <td ALIGN=RIGHT><B>\(st.pointsFor)</B></td>\n  <td ALIGN=RIGHT><B>\(st.pointsAgainst)</B>\(legacyHTML ? "" : "</td>")\n"
            for k in 0..<4 where selected(k) { out += "  <td ALIGN=RIGHT><B>\(st.q[k])</B></td>\n" }
            if trackTUH {
                out += "  <td ALIGN=RIGHT><B>\(st.tossUpsHeard)</B></td>\n  <td ALIGN=RIGHT><B>\(rate(st.pointsFor, st.tossUpsHeard))</B></td>\n"
            }
            if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>\(ratioPN(st.q))</B></td>\n  <td ALIGN=RIGHT><B>\(ratioGN(st.q))</B></td>\n" }
            if s.trackLightning { out += "  <td ALIGN=RIGHT><B>\(st.lightning)</B></td>\n" }
            if trackBonus {
                out += "  <td ALIGN=RIGHT><B>\(st.bonusHeard)</B></td>\n  <td ALIGN=RIGHT><B>\(st.bonusPoints)</B></td>\n  <td ALIGN=RIGHT><B>\(f(safeDivide(Float(st.bonusPoints), Float(st.bonusHeard)), 2))</B></td>\n"
                if hasBouncebacks {
                    out += "  <td ALIGN=RIGHT><B>\(st.bouncebacksHeard)</B></td>\n  <td ALIGN=RIGHT><B>\(st.bouncebacksPoints)</B></td>\n  <td ALIGN=RIGHT><B>\(f(safeDivide(Float(st.bouncebacksPoints), Float(st.bouncebacksHeard)), 2))</B></td>\n"
                }
            }
            if packetColumn { out += "  <td ALIGN=LEFT> </td>\n" }
            out += "</tr>\n</table><P>\n"

            // Player table for the team
            out += "<table border=1 width=100%>\n<tr>\n  <td ALIGN=LEFT><B>Player</B></td>\n  <td ALIGN=LEFT><B>Team</B></td>\n  <td ALIGN=RIGHT><B>GP</B></td>\n"
            out += valueHeaders() + tuhHeader(false)
            if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>P/N</B></td>\n  <td ALIGN=RIGHT><B>G/N</B></td>\n" }
            out += "  <td ALIGN=RIGHT><B>Pts</B></td>\n  <td ALIGN=RIGHT><B>PPG</B></td>\n</tr>\n"
            for p in rawPlayers where p.teamIndex == i && p.gamesPlayed > 0 {
                out += "<tr>\n  <td ALIGN=LEFT>"
                let link = enabled(.playerDetail)
                if link { out += "<A HREF=\(baseName)\(fileName(.playerDetail))#p\(p.position)_\(p.teamIndex)>" }
                out += p.playerName
                if link { out += "</A>" }
                out += "</td>\n  <td ALIGN=LEFT>\(p.teamName)</td>\n  <td ALIGN=RIGHT>\(f(p.gamesPlayed, 1))</td>\n"
                for k in 0..<4 where selected(k) { out += "  <td ALIGN=RIGHT>\(p.q[k])</td>\n" }
                if trackTUH {
                    out += "  <td ALIGN=RIGHT>\(p.tossUpsHeard)</td>\n  <td ALIGN=RIGHT>\(rate(p.points, p.tossUpsHeard))</td>\n"
                }
                if s.trackPowerNeg { out += "  <td ALIGN=RIGHT>\(ratioPN(p.q))</td>\n  <td ALIGN=RIGHT>\(ratioGN(p.q))</td>\n" }
                out += "  <td ALIGN=RIGHT>\(p.points)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(p.points), p.gamesPlayed), 2))</td>\n</tr>\n"
            }
            out += "</table>\n"
        }
        return out + suffix
    }

    private func playerDetailPage() -> String {
        var out = prefix(title: title("Individual Detail"))
        let games = sortedGamesByRound()
        for p in rawPlayers where p.gamesPlayed > 0 {
            out += "<P><P><H2><A NAME=p\(p.position)_\(p.teamIndex)>\(p.playerName)</A>, \(p.teamName)</H2><P>\n"
            out += "<table border=1 width=100%>\n<tr>\n<td ALIGN=LEFT><B>Opponent</B></td>\n"
            if packetColumn { out += "  <td ALIGN=LEFT><B>Packet</B></td>\n" }
            out += "  <td ALIGN=RIGHT><B>GP</B></td>\n" + valueHeaders() + tuhHeader(false)
            if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>P/N</B></td>\n  <td ALIGN=RIGHT><B>G/N</B></td>\n" }
            out += "  <td ALIGN=RIGHT><B>Pts</B></td>\n</tr>\n"

            for g in games where filter.includes(g.round) {
                if g.isForfeit || NS.int(g.scoreA) == -1 || NS.int(g.scoreB) == -1 { continue }
                for isA in [true, false] {
                    let mine = isA ? g.teamA : g.teamB
                    let other = isA ? g.teamB : g.teamA
                    guard mine == p.teamIndex, other >= 0 else { continue }
                    let slots = isA ? g.playersA : g.playersB
                    guard let line = slots.first(where: { $0?.rosterIndex == p.position - 1 }) ?? nil else { continue }
                    let gp = Tournament.roundedGP(line.gp)
                    guard gp > 0 else { continue }
                    out += (legacyHTML ? "" : "<tr>\n") + "  <td ALIGN=LEFT>\(teamName(other))</td>\n"
                    if packetColumn { out += packetCell(g.round, typo: legacyHTML && !isA) }
                    out += "  <td ALIGN=RIGHT>\(f(gp, 2))</td>\n"
                    for k in 0..<4 where selected(k) { out += "  <td ALIGN=RIGHT>\(line.counts[k])</td>\n" }
                    let tuh = Int(Double(Float(g.tossupsHeard) * gp))
                    if trackTUH {
                        out += "  <td ALIGN=RIGHT>\(tuh)</td>\n  <td ALIGN=RIGHT>\(f(safeDivide(Float(line.points), Float(tuh)), 2))</td>\n"
                    }
                    if s.trackPowerNeg { out += "  <td ALIGN=RIGHT>\(ratioPN(line.counts))</td>\n  <td ALIGN=RIGHT>\(ratioGN(line.counts))</td>\n" }
                    out += "  <td ALIGN=RIGHT>\(line.points)</td>\n</tr>\n"
                }
            }

            out += "<tr>\n  <td ALIGN=LEFT><B>Total</B></td>\n"
            if packetColumn { out += "  <td ALIGN=LEFT><B> </B></td>\n" }
            out += "  <td ALIGN=RIGHT><B>\(f(p.gamesPlayed, 2))</B></td>\n"
            for k in 0..<4 where selected(k) { out += "  <td ALIGN=RIGHT><B>\(p.q[k])</B></td>\n" }
            if trackTUH {
                out += "  <td ALIGN=RIGHT><B>\(p.tossUpsHeard)</B></td>\n  <td ALIGN=RIGHT><B>\(rate(p.points, p.tossUpsHeard))</B></td>\n"
            }
            if s.trackPowerNeg { out += "  <td ALIGN=RIGHT><B>\(ratioPN(p.q))</B></td>\n  <td ALIGN=RIGHT><B>\(ratioGN(p.q))</B></td>\n" }
            out += "  <td ALIGN=RIGHT><B>\(p.points)</B></td>\n</tr>\n</table>\n"
        }
        return out + suffix
    }
}
