import Foundation

// The schedule as part of a tournament: round counts shared with the playoff setup, roster links and reports.

extension Tournament {
    /// Rounds in the whole tournament. This is the same number the playoff setup uses.
    public var scheduleTotalRounds: Int { plus.playoffs.totalRounds }

    /// Rounds whose matchups are scheduled in advance (everything before the playoffs).
    public var schedulePrelimRounds: Int {
        let start = plus.playoffs.playoffStartRound
        return start > 0 ? start - 1 : plus.playoffs.totalRounds
    }

    /// The name to show for a scheduled team: the roster team once it is linked, otherwise the name it was scheduled under.
    public func scheduleTeamName(_ id: Int?) -> String {
        guard let id, let st = plus.schedule.team(id) else { return "" }
        if let r = st.rosterTeam, r >= 0, r < teams.count { return teams[r].name }
        return st.name
    }

    /// Links scheduled teams to roster teams that have the same name. Returns how many were linked.
    @discardableResult
    public mutating func linkScheduleTeamsToRoster() -> Int {
        var linked = 0
        var taken = Set(plus.schedule.teams.compactMap(\.rosterTeam))
        for i in plus.schedule.teams.indices where plus.schedule.teams[i].rosterTeam == nil {
            let wanted = plus.schedule.teams[i].name.trimmingCharacters(in: .whitespaces).lowercased()
            if let r = teams.indices.first(where: { !taken.contains($0) && teams[$0].name.trimmingCharacters(in: .whitespaces).lowercased() == wanted }) {
                plus.schedule.teams[i].rosterTeam = r
                taken.insert(r)
                linked += 1
            }
        }
        if linked > 0 && plus.schedule.teams.contains(where: { !$0.pool.isEmpty }) { applySchedulePoolsToDivisions() }
        return linked
    }

    /// Puts each playoff game in a room (in room order) for the playoff rounds, and clears the marks elsewhere.
    public mutating func syncSchedulePlayoffSlots() {
        let total = scheduleTotalRounds
        plus.schedule.ensureSlots(totalRounds: total)
        for i in plus.schedule.games.indices { plus.schedule.games[i].playoffGame = nil }
        let start = plus.playoffs.playoffStartRound
        guard start > 0 else { return }
        let all = plus.playoffs.brackets.flatMap(\.games)
        for r in start...max(total, start) {
            let ids = all.filter { $0.round == r }.map(\.id)
            let slots = plus.schedule.games.indices.filter { plus.schedule.games[$0].round == r }
            for (k, id) in ids.enumerated() where k < slots.count { plus.schedule.games[slots[k]].playoffGame = id }
        }
    }

    /// Adds a scheduled team for every roster team (not exhibition) that is not in the schedule yet, linked to it. The school
    /// is worked out from the name, and a division already set in Tournament Setup becomes the team's pool.
    @discardableResult
    public mutating func addRosterTeamsToSchedule() -> Int {
        let linked = Set(plus.schedule.teams.compactMap(\.rosterTeam))
        var added = 0
        for i in teams.indices where !linked.contains(i) && !teams[i].exhibition {
            let id = plus.schedule.addTeam(name: teams[i].name, school: Schedule.guessSchool(fromTeamName: teams[i].name))
            if let k = plus.schedule.teams.firstIndex(where: { $0.id == id }) {
                plus.schedule.teams[k].rosterTeam = i
                if settings.useDivisions, let d = teams[i].division, d >= 0, d < divisions.count { plus.schedule.teams[k].pool = divisions[d] }
            }
            added += 1
        }
        return added
    }

    /// Roster teams (not exhibition) that are not in the schedule.
    public var rosterTeamsNotScheduled: [Int] {
        let linked = Set(plus.schedule.teams.compactMap(\.rosterTeam))
        return teams.indices.filter { !linked.contains($0) && !teams[$0].exhibition }
    }

    /// Pools drive the divisions while any team has a pool; Tournament Setup then shows them without letting them be edited.
    public var divisionsComeFromPools: Bool { !plus.schedule.poolNames.isEmpty }

    /// Makes the schedule's pools the tournament's divisions, so standings can be shown by pool.
    public mutating func applySchedulePoolsToDivisions() {
        let pools = plus.schedule.poolNames
        guard !pools.isEmpty else { return }
        // teams not tied to the schedule keep their division when its name still exists
        let oldNames = divisions
        let linked = Set(plus.schedule.teams.compactMap(\.rosterTeam))
        for i in teams.indices where !linked.contains(i) {
            if let d = teams[i].division, d < oldNames.count { teams[i].division = pools.firstIndex(of: oldNames[d]) } else { teams[i].division = nil }
        }
        settings.useDivisions = true
        divisions = pools
        for st in plus.schedule.teams {
            if let r = st.rosterTeam, r >= 0, r < teams.count { teams[r].division = pools.firstIndex(of: st.pool.trimmingCharacters(in: .whitespaces)) }
        }
    }

    /// Whether a team file being imported has a division line for each team. A NAQT team file never does; only a file from
    /// an SQBS tournament that uses divisions of its own does, so divisions that come from the schedule's pools do not count.
    public var importUsesDivisions: Bool { settings.useDivisions && plus.schedule.poolNames.isEmpty }

    /// Creates a game in the game list for each scheduled preliminary game whose two teams are linked to roster teams,
    /// so Game Entry already shows who plays whom. Games with no score yet are placeholders: they appear in Game Entry but
    /// never count in standings, reports or the export until a score is entered. Scored games are never changed.
    @discardableResult
    public mutating func createScheduledGames() -> (created: Int, updated: Int, skipped: Int) {
        var created = 0, updated = 0, skipped = 0
        let order = Dictionary(uniqueKeysWithValues: plus.schedule.rooms.enumerated().map { ($1.id, $0) })
        let slots = plus.schedule.games.indices.filter { plus.schedule.games[$0].round <= schedulePrelimRounds }
            .sorted { (plus.schedule.games[$0].round, order[plus.schedule.games[$0].room] ?? 0) < (plus.schedule.games[$1].round, order[plus.schedule.games[$1].room] ?? 0) }
        for i in slots {
            let slot = plus.schedule.games[i]
            guard let a = slot.teamA, let b = slot.teamB,
                  let ra = plus.schedule.team(a)?.rosterTeam, let rb = plus.schedule.team(b)?.rosterTeam,
                  ra >= 0, ra < teams.count, rb >= 0, rb < teams.count, ra != rb else { skipped += 1; continue }
            if let gid = slot.gameID, let gi = games.firstIndex(where: { $0.id == gid }) {
                if isPlaceholder(games[gi]) && (games[gi].teamA != ra || games[gi].teamB != rb || games[gi].round != slot.round) {
                    games[gi].teamA = ra; games[gi].teamB = rb; games[gi].round = slot.round
                    games[gi].playersA = defaultPlayerLines(forTeam: ra, beforeRound: slot.round, excludingGame: gi)
                    games[gi].playersB = defaultPlayerLines(forTeam: rb, beforeRound: slot.round, excludingGame: gi)
                    updated += 1
                }
                continue
            }
            let id = nextGameID(round: slot.round)
            var g = Game(id: id, teamA: ra, teamB: rb, scoreA: "-1", scoreB: "-1", tossupsHeard: 0, round: slot.round)
            g.playersA = defaultPlayerLines(forTeam: ra, beforeRound: slot.round)
            g.playersB = defaultPlayerLines(forTeam: rb, beforeRound: slot.round)
            games.append(g)
            plus.schedule.games[i].gameID = id
            created += 1
        }
        return (created, updated, skipped)
    }

    /// Random schedule for the preliminary rounds, then rooms for the playoffs and staff for every round.
    @discardableResult
    public mutating func generateSchedule(seed: UInt64) -> [String] {
        let notes = plus.schedule.generate(rounds: schedulePrelimRounds, seed: seed)
        syncSchedulePlayoffSlots()
        plus.schedule.autoAssignStaff(totalRounds: scheduleTotalRounds)
        return notes
    }

    public mutating func autoAssignScheduleStaff() {
        syncSchedulePlayoffSlots()
        plus.schedule.autoAssignStaff(totalRounds: scheduleTotalRounds)
    }

    public var scheduleIssues: [ScheduleIssue] {
        var out = plus.schedule.issues(prelimRounds: schedulePrelimRounds, totalRounds: scheduleTotalRounds)
        let missing = rosterTeamsNotScheduled
        if !plus.schedule.teams.isEmpty && !missing.isEmpty {
            out.append(ScheduleIssue(.warning, "\(missing.count) roster team\(missing.count == 1 ? " is" : "s are") not in the schedule: " + missing.prefix(6).map { teams[$0].name }.joined(separator: ", ") + (missing.count > 6 ? ", …" : "") + ". Use Add Roster Teams on the Teams section."))
        }
        let unpooled = plus.schedule.poolNames.isEmpty ? [] : plus.schedule.teams.filter { $0.pool.trimmingCharacters(in: .whitespaces).isEmpty }
        if !unpooled.isEmpty {
            out.append(ScheduleIssue(.warning, "\(unpooled.count) team\(unpooled.count == 1 ? " has" : "s have") no pool: " + unpooled.prefix(6).map(\.name).joined(separator: ", ") + "."))
        }
        return out
    }

    /// Text for a side of a bracket game that has no team yet.
    func scheduleSlotLabel(_ slot: BracketSlot) -> String {
        if let t = resolve(slot: slot), t >= 0, t < teams.count { return teams[t].name }
        switch slot {
        case .seed(let n): return "Seed \(n)"
        case .winner(let id): return "Winner of \(id)"
        case .loser(let id): return "Loser of \(id)"
        case .team(let i): return i >= 0 && i < teams.count ? teams[i].name : "TBD"
        case .bye: return "Bye"
        }
    }

    /// Both sides of a scheduled game as text: team names in the preliminary rounds, bracket entries in the playoffs.
    public func scheduleMatchup(_ g: ScheduledGame) -> (a: String, b: String) {
        if let id = g.playoffGame, let bg = plus.playoffs.brackets.flatMap(\.games).first(where: { $0.id == id }) {
            return (scheduleSlotLabel(bg.a), scheduleSlotLabel(bg.b))
        }
        return (scheduleTeamName(g.teamA), scheduleTeamName(g.teamB))
    }
}

// MARK: - Reports

public struct ScheduleReports {
    public enum Kind: CaseIterable, Sendable {
        case roomMatchups, teamSchedule, missingSlots, buzzers
        public var title: String {
            switch self {
            case .roomMatchups: return "Room Matchups"
            case .teamSchedule: return "Team Schedules"
            case .missingSlots: return "Missing Slots"
            case .buzzers: return "Buzzer Locations"
            }
        }
        /// Appended to the base name when web reports are written.
        public var fileSuffix: String {
            switch self {
            case .roomMatchups: return "_rooms.html"
            case .teamSchedule: return "_teamschedule.html"
            case .missingSlots: return "_missingslots.html"
            case .buzzers: return "_buzzers.html"
            }
        }
    }

    let t: Tournament
    var sc: Schedule { t.plus.schedule }

    public init(tournament: Tournament) { t = tournament }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private func wrap(_ title: String, _ body: String) -> String {
        let name = t.settings.tournamentName.isEmpty ? "" : esc(t.settings.tournamentName) + " "
        return "<html>\n<head>\n<meta http-equiv=\"Content-Type\" content=\"text/html;charset=ISO-8859-1\" />\n<title>\(name)\(title)</title>\n"
            + "<style>body{font-family:Helvetica,Arial,sans-serif} table{border-collapse:collapse;width:100%;margin-bottom:1.2em} "
            + "td,th{border:1px solid #999;padding:3px 8px;text-align:left} th{background:#eee} h2{margin-bottom:4px}</style>\n</head>\n<body>\n"
            + "<h1>\(name)\(title)</h1>\n\(body)</body>\n</html>\n"
    }

    private func staffName(_ id: Int?) -> String { esc(sc.staffMember(id)?.name ?? "") }
    private func roomName(_ id: Int) -> String { esc(sc.room(id)?.name ?? "") }
    private func teamLabel(_ id: Int?) -> String {
        guard let st = sc.team(id) else { return "" }
        let n = esc(t.scheduleTeamName(id))
        return st.school.isEmpty ? n : "\(n) <small>(\(esc(st.school)))</small>"
    }
    private func buzzerText(inRoom id: Int) -> String { esc(sc.buzzers(inRoom: id).map(\.owner).joined(separator: ", ")) }

    public func page(_ kind: Kind) -> String {
        switch kind {
        case .roomMatchups: return roomMatchups()
        case .teamSchedule: return teamSchedule()
        case .missingSlots: return missingSlots()
        case .buzzers: return buzzers()
        }
    }

    private func roomMatchups() -> String {
        let total = t.scheduleTotalRounds, prelim = t.schedulePrelimRounds
        guard total > 0, !sc.rooms.isEmpty else { return wrap(Kind.roomMatchups.title, "<p>Set the number of rounds and add rooms on the Schedule tab first.</p>\n") }
        let showBuzzers = !sc.buzzers.isEmpty
        var body = ""
        for r in 1...total {
            body += "<h2>Round \(r)\(r > prelim ? " (playoffs)" : "")</h2>\n<table>\n<tr><th>Room</th><th>Team A</th><th>Team B</th><th>Moderator</th><th>Scorekeeper</th>"
                + (showBuzzers ? "<th>Buzzers</th>" : "") + "</tr>\n"
            var rows = 0
            for g in sc.slots(inRound: r) where g.hasAnyTeam || g.playoffGame != nil {
                let m = t.scheduleMatchup(g)
                body += "<tr><td>\(roomName(g.room))</td><td>\(esc(m.a))</td><td>\(esc(m.b))</td><td>\(staffName(g.moderator))</td><td>\(staffName(g.scorekeeper))</td>"
                    + (showBuzzers ? "<td>\(buzzerText(inRoom: g.room))</td>" : "") + "</tr>\n"
                rows += 1
            }
            if rows == 0 { body += "<tr><td colspan=\"\(showBuzzers ? 6 : 5)\">No games scheduled.</td></tr>\n" }
            body += "</table>\n"
            if r <= prelim {
                let playing = Set(sc.slots(inRound: r).flatMap { [$0.teamA, $0.teamB].compactMap { $0 } })
                let byes = sc.teams.filter { !playing.contains($0.id) }
                if rows > 0 && !byes.isEmpty { body += "<p><b>Bye:</b> \(byes.map { esc(t.scheduleTeamName($0.id)) }.joined(separator: ", "))</p>\n" }
            }
        }
        return wrap(Kind.roomMatchups.title, body)
    }

    private func teamSchedule() -> String {
        let prelim = t.schedulePrelimRounds
        guard prelim > 0, !sc.teams.isEmpty else { return wrap(Kind.teamSchedule.title, "<p>Add teams and set the number of rounds on the Schedule tab first.</p>\n") }
        var body = ""
        let ordered = sc.teams.sorted { t.scheduleTeamName($0.id).localizedCaseInsensitiveCompare(t.scheduleTeamName($1.id)) == .orderedAscending }
        for team in ordered {
            body += "<h2>\(esc(t.scheduleTeamName(team.id)))\(team.school.isEmpty ? "" : " <small>(\(esc(team.school)))</small>")</h2>\n"
            body += "<table>\n<tr><th>Round</th><th>Opponent</th><th>Room</th></tr>\n"
            for r in 1...prelim {
                if let g = sc.slots(inRound: r).first(where: { $0.teamA == team.id || $0.teamB == team.id }) {
                    let other = g.teamA == team.id ? g.teamB : g.teamA
                    body += "<tr><td>\(r)</td><td>\(other == nil ? "TBD" : teamLabel(other))</td><td>\(roomName(g.room))</td></tr>\n"
                } else {
                    body += "<tr><td>\(r)</td><td colspan=\"2\"><i>Bye</i></td></tr>\n"
                }
            }
            body += "</table>\n"
        }
        return wrap(Kind.teamSchedule.title, body)
    }

    private func missingSlots() -> String {
        let total = t.scheduleTotalRounds, prelim = t.schedulePrelimRounds
        guard total > 0, !sc.rooms.isEmpty else { return wrap(Kind.missingSlots.title, "<p>Set the number of rounds and add rooms on the Schedule tab first.</p>\n") }
        var teamRows = "", modRows = "", skRows = "", byeRows = "", buzzRows = ""
        for r in 1...total {
            for g in sc.slots(inRound: r) {
                let active = g.hasAnyTeam || g.playoffGame != nil
                guard active else { continue }
                if r <= prelim && !g.hasBothTeams { teamRows += "<tr><td>\(r)</td><td>\(roomName(g.room))</td><td>\(g.teamA == nil && g.teamB == nil ? "Both teams" : "One team")</td></tr>\n" }
                if g.moderator == nil { modRows += "<tr><td>\(r)</td><td>\(roomName(g.room))</td></tr>\n" }
                if g.scorekeeper == nil { skRows += "<tr><td>\(r)</td><td>\(roomName(g.room))</td></tr>\n" }
            }
            if r <= prelim {
                let slots = sc.slots(inRound: r)
                let playing = Set(slots.flatMap { [$0.teamA, $0.teamB].compactMap { $0 } })
                let sitting = sc.teams.filter { !playing.contains($0.id) }
                if !sitting.isEmpty && slots.contains(where: \.hasAnyTeam) { byeRows += "<tr><td>\(r)</td><td>\(sitting.map { esc(t.scheduleTeamName($0.id)) }.joined(separator: ", "))</td></tr>\n" }
            }
        }
        if !sc.buzzers.isEmpty {
            let used = Set(sc.games.filter { $0.hasAnyTeam || $0.playoffGame != nil }.map(\.room))
            for room in sc.rooms where used.contains(room.id) && sc.buzzers(inRoom: room.id).isEmpty { buzzRows += "<tr><td>\(esc(room.name))</td></tr>\n" }
        }
        func section(_ title: String, _ header: String, _ rows: String) -> String {
            "<h2>\(title)</h2>\n" + (rows.isEmpty ? "<p>None.</p>\n" : "<table>\n<tr>\(header)</tr>\n\(rows)</table>\n")
        }
        var body = section("Games missing teams", "<th>Round</th><th>Room</th><th>Missing</th>", teamRows)
        body += section("Games missing a moderator", "<th>Round</th><th>Room</th>", modRows)
        body += section("Games missing a scorekeeper", "<th>Round</th><th>Room</th>", skRows)
        body += section("Teams without a game (byes)", "<th>Round</th><th>Teams</th>", byeRows)
        if !sc.buzzers.isEmpty { body += section("Rooms with no buzzers", "<th>Room</th>", buzzRows) }
        return wrap(Kind.missingSlots.title, body)
    }

    private func buzzers() -> String {
        guard !sc.rooms.isEmpty || !sc.buzzers.isEmpty else { return wrap(Kind.buzzers.title, "<p>No buzzers have been entered.</p>\n") }
        var body = "<table>\n<tr><th>Room</th><th>Buzzers</th><th>Notes</th></tr>\n"
        for room in sc.rooms {
            let sets = sc.buzzers(inRoom: room.id)
            body += "<tr><td>\(esc(room.name))</td><td>\(esc(sets.map(\.owner).joined(separator: ", ")))</td><td>\(esc(sets.map(\.note).filter { !$0.isEmpty }.joined(separator: "; ")))</td></tr>\n"
        }
        body += "</table>\n"
        let loose = sc.buzzers.filter { $0.room == nil }
        if !loose.isEmpty {
            body += "<h2>Not in a room</h2>\n<table>\n<tr><th>Buzzers</th><th>Notes</th></tr>\n"
            for b in loose { body += "<tr><td>\(esc(b.owner))</td><td>\(esc(b.note))</td></tr>\n" }
            body += "</table>\n"
        }
        return wrap(Kind.buzzers.title, body)
    }
}
