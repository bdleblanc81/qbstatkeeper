import SwiftUI
import QBSCore

/// The Schedule tab: rounds and rooms, teams (before rosters exist), the room-by-round grid, staff, buzzers and checks.
struct ScheduleView: View {
    @Binding var t: Tournament
    var showAlert: (AlertInfo) -> Void

    enum Pane: String, CaseIterable, Identifiable {
        case setup = "Setup", teams = "Teams", grid = "Schedule", staff = "Staff", buzzers = "Buzzers", checks = "Checks"
        var id: String { rawValue }
    }

    @State private var pane: Pane
    enum TeamSheet: Identifiable { case school; var id: Int { 0 } }
    @State private var teamSheet: TeamSheet?
    @State private var newSchoolName = ""
    @State private var newSchoolTeams = 1

    init(t: Binding<Tournament>, initialPane: Pane = .setup, initialSheet: TeamSheet? = nil, showAlert: @escaping (AlertInfo) -> Void) {
        _t = t
        self.showAlert = showAlert
        _pane = State(initialValue: initialPane)
        _teamSheet = State(initialValue: initialSheet)
        if initialSheet == .school { _newSchoolName = State(initialValue: "Central"); _newSchoolTeams = State(initialValue: 2) }
    }

    private var sched: Schedule { t.plus.schedule }
    private var total: Int { t.scheduleTotalRounds }
    private var prelim: Int { t.schedulePrelimRounds }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) { ForEach(Pane.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 640).padding(.vertical, 8)
            Divider()
            Group {
                switch pane {
                case .setup: setup
                case .teams: teams
                case .grid: grid
                case .staff: staffPane
                case .buzzers: buzzers
                case .checks: checks
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { syncSlots() }
        .onChange(of: total) { _ in syncSlots() }
        .onChange(of: sched.rooms.count) { _ in syncSlots() }
        .onChange(of: t.plus.playoffs.playoffRounds) { _ in syncSlots() }
        .sheet(item: $teamSheet) { which in
            switch which {
            case .school: addSchoolSheet
            }
        }
    }

    /// Keeps a slot for every room in every round, and puts playoff games in rooms.
    private func syncSlots() {
        t.syncSchedulePlayoffSlots()
    }

    // MARK: Setup

    private func numberRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).frame(width: 250, alignment: .leading)
            TextField("", value: value, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
        }
    }

    private var roomCount: Binding<Int> {
        Binding(get: { t.plus.schedule.rooms.count }, set: { n in
            let n = max(0, min(n, 60))
            while t.plus.schedule.rooms.count < n { t.plus.schedule.addRoom(name: "Room \(t.plus.schedule.rooms.count + 1)") }
            while t.plus.schedule.rooms.count > n, let last = t.plus.schedule.rooms.last { t.plus.schedule.removeRoom(last.id) }
        })
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Rounds") {
                        VStack(alignment: .leading, spacing: 8) {
                            numberRow("Rounds in the tournament", value: Binding(get: { t.plus.playoffs.totalRounds }, set: { v in
                                t.plus.playoffs.totalRounds = min(max(v, 0), 99)
                                if t.plus.playoffs.playoffRounds > t.plus.playoffs.totalRounds { t.plus.playoffs.playoffRounds = t.plus.playoffs.totalRounds }
                            }))
                            numberRow("Playoff rounds (the last rounds)", value: Binding(get: { t.plus.playoffs.playoffRounds }, set: { v in
                                t.plus.playoffs.playoffRounds = min(max(v, 0), max(t.plus.playoffs.totalRounds, 0))
                            }))
                            Text(roundsSummary).font(.caption).foregroundStyle(.secondary).frame(width: 330, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(8)
                    }
                    GroupBox("Rooms") {
                        VStack(alignment: .leading, spacing: 8) {
                            numberRow("Number of rooms", value: roomCount)
                            ForEach($t.plus.schedule.rooms) { $room in
                                HStack {
                                    TextField("Room name", text: $room.name).frame(width: 200)
                                    Button { t.plus.schedule.removeRoom(room.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove this room")
                                }
                            }
                            Button("Add Room") { t.plus.schedule.addRoom(name: "Room \(sched.rooms.count + 1)") }
                        }.padding(8)
                    }
                    }
                    GroupBox("Pairings and rules") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $t.plus.schedule.poolRoundRobin) {
                                Text("Random pairings").tag(false)
                                Text("Round robin within pools").tag(true)
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 330)
                            if sched.poolRoundRobin {
                                Text(poolSummary).font(.caption).foregroundStyle(.secondary).frame(width: 360, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }
                            HStack {
                                Toggle("A team does not return to a room for", isOn: Binding(get: { sched.roomRepeatGap > 0 }, set: { t.plus.schedule.roomRepeatGap = $0 ? 2 : 0 }))
                                TextField("", value: $t.plus.schedule.roomRepeatGap, format: .number).frame(width: 40).multilineTextAlignment(.trailing)
                                    .disabled(sched.roomRepeatGap <= 0)
                                Text("rounds")
                            }
                            Toggle("Teams from the same school do not play each other", isOn: $t.plus.schedule.avoidSameSchool).disabled(sched.poolRoundRobin)
                            Toggle("Every school plays every other school at least once", isOn: $t.plus.schedule.requireSchoolCoverage).disabled(sched.poolRoundRobin)
                            Text("Every team gets the same number of games; teams take byes in turn when there are fewer rooms than games or an odd number of teams.")
                                .font(.caption).foregroundStyle(.secondary).frame(width: 360, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(8)
                    }
                }
                HStack(spacing: 12) {
                    Button(sched.poolRoundRobin ? "Generate Round-Robin Schedule" : "Generate Random Schedule") { generate() }.buttonStyle(.borderedProminent)
                        .help("Fill every preliminary round with random matchups and rooms, and assign moderators and scorekeepers. Locked games stay as they are.")
                    Button("Create Games in Game Entry") { createGames() }
                        .help("Add each scheduled game to Game Entry (for teams linked to the roster) so you only have to enter scores.")
                    Button("Clear Automatic Games") {
                        t.plus.schedule.clearAutomatic(rounds: prelim)
                    }.help("Remove the randomly made games; games you set by hand (locked) stay.")
                    Button("Clear Everything") { confirmClearAll() }
                    Spacer()
                }
                Text("To schedule by hand instead, open the Schedule section and choose teams for each room; anything you set is locked and random scheduling works around it.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var roundsSummary: String {
        if total <= 0 { return "Enter the number of rounds to begin." }
        let p = t.plus.playoffs.playoffRounds
        if p > 0 && p < total { return "Rounds 1–\(prelim) are scheduled here; rounds \(prelim + 1)–\(total) are playoff rounds (set up under Playoffs & Consolation, which uses these same numbers)." }
        return "All \(total) rounds are scheduled here. The playoff format uses the same round count."
    }

    private func generate() {
        guard total > 0, prelim > 0 else { showAlert(AlertInfo(title: "Set the number of rounds first.")); return }
        if sched.teams.isEmpty && !t.teams.isEmpty { t.addRosterTeamsToSchedule() }
        guard sched.teams.count >= 2 else { showAlert(AlertInfo(title: "Add at least two teams first.")); return }
        guard !sched.rooms.isEmpty else { showAlert(AlertInfo(title: "Add at least one room first.")); return }
        let hasAuto = sched.games.contains { $0.round <= prelim && $0.hasAnyTeam && !$0.pinned }
        let run = {
            var copy = t
            let notes = copy.generateSchedule(seed: UInt64.random(in: 0..<UInt64.max))
            t = copy
            if !notes.isEmpty {
                showAlert(AlertInfo(title: "The schedule was made, but some requirements could not be met.", message: notes.joined(separator: "\n\n")))
            }
            pane = .grid
        }
        if hasAuto {
            showAlert(AlertInfo(title: "Replace the current random schedule?", message: "Games you locked by hand are kept.",
                                primary: "Replace", secondary: "Cancel", onPrimary: run))
        } else { run() }
    }

    private func confirmClearAll() {
        showAlert(AlertInfo(title: "Clear every game, moderator and scorekeeper?", message: "This removes locked games too. Teams, rooms and staff lists stay.",
                            primary: "Clear Everything", secondary: "Cancel", onPrimary: {
            t.plus.schedule.clearAllTeams(rounds: total)
            for i in t.plus.schedule.games.indices {
                t.plus.schedule.games[i].moderator = nil; t.plus.schedule.games[i].scorekeeper = nil
                t.plus.schedule.games[i].moderatorPinned = false; t.plus.schedule.games[i].scorekeeperPinned = false
            }
        }))
    }

    // MARK: Teams (schools and their teams)

    static let naqtTip = "Tip: enter each school's name exactly as it appears on its NAQT registration, so the schedule matches the NAQT team file when you import it."

    private var teams: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("Add School…") { newSchoolName = ""; newSchoolTeams = 1; teamSheet = .school }.buttonStyle(.borderedProminent)
                Menu("Deal into Pools") {
                    ForEach(2...8, id: \.self) { n in Button("\(n) pools") { dealPools(count: n) } }
                }.help("Deal the teams out in list order into Pool A, Pool B, ... (a school's teams are listed together, so they land in different pools).").fixedSize()
                Button("Add Roster Teams") { addRosterTeams() }.help("Add a scheduled team for each team in the roster that is not linked yet.")
                Button("Link Roster by Name") {
                    let n = t.linkScheduleTeamsToRoster()
                    showAlert(AlertInfo(title: n == 0 ? "No scheduled teams matched a roster team by name." : "Linked \(n) team\(n == 1 ? "" : "s") to the roster."))
                }.help("Once team rosters exist, link scheduled teams to the roster teams with the same name.")
                Spacer()
                Text("\(sched.schools.count) school\(sched.schools.count == 1 ? "" : "s"), \(sched.teams.count) team\(sched.teams.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            Label(Self.naqtTip, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary)
            if !t.rosterTeamsNotScheduled.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill").foregroundStyle(Color.accentColor)
                    Text("\(t.rosterTeamsNotScheduled.count) team\(t.rosterTeamsNotScheduled.count == 1 ? "" : "s") from the roster (for example an NAQT import) \(t.rosterTeamsNotScheduled.count == 1 ? "is" : "are") not in the schedule yet.")
                    Button("Add Them") { t.addRosterTeamsToSchedule() }
                }
                .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
            }
            if sched.schools.isEmpty && sched.teams.isEmpty && t.teams.isEmpty {
                Text("No schools yet. Choose Add School to begin: give the school's name and how many teams it is sending.")
                    .foregroundStyle(.secondary).padding(.top, 20)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sched.schools) { school in schoolBox(school) }
                    let loose = sched.teams.filter { $0.school.trimmingCharacters(in: .whitespaces).isEmpty }
                    if !loose.isEmpty {
                        GroupBox("Teams with no school") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(loose) { team in teamRow(team, showSchoolChoice: true) }
                            }.padding(6)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading).padding(.vertical, 4)
            }
            Text("A school with one team uses the school name as the team name. With two or more, the teams are lettered (Central A, Central B). Link each team to its roster team once rosters are in so reports show the real name.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }

    private func schoolBox(_ school: ScheduleSchool) -> some View {
        let members = sched.teams(inSchool: school.name)
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "building.2").foregroundStyle(.secondary)
                    TextField("School name", text: Binding(get: { school.name }, set: { t.plus.schedule.renameSchool(school.id, to: $0) }))
                        .frame(width: 280).font(.headline)
                    Text("\(members.count) team\(members.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Team") { t.plus.schedule.addTeam(toSchool: school.id) }
                    Button { removeSchool(school) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove this school and its teams")
                }
                ForEach(members) { team in teamRow(team, showSchoolChoice: false) }
            }.padding(6)
        }
    }

    private func teamIndex(_ id: Int) -> Int? { sched.teams.firstIndex { $0.id == id } }

    private func teamRow(_ team: ScheduleTeam, showSchoolChoice: Bool) -> some View {
        HStack(spacing: 10) {
            Text("").frame(width: 22)
            TextField("Team name", text: Binding(get: { teamIndex(team.id).map { t.plus.schedule.teams[$0].name } ?? "" }, set: { new in
                if let i = teamIndex(team.id) { t.plus.schedule.teams[i].name = new; t.plus.schedule.teams[i].autoName = false }
            })).frame(width: 240)
            if showSchoolChoice {
                Picker("", selection: Binding(get: { teamIndex(team.id).map { t.plus.schedule.teams[$0].school } ?? "" }, set: { new in
                    if let i = teamIndex(team.id) { t.plus.schedule.teams[i].school = new; t.plus.schedule.updateAutoNames(forSchool: new) }
                })) {
                    Text("Choose a school").tag("")
                    ForEach(sched.schools) { Text($0.name).tag($0.name) }
                }.labelsHidden().frame(width: 180)
            }
            Text("Pool").foregroundStyle(.secondary).font(.caption)
            TextField("Pool", text: Binding(get: { teamIndex(team.id).map { t.plus.schedule.teams[$0].pool } ?? "" }, set: { new in
                if let i = teamIndex(team.id) { t.plus.schedule.teams[i].pool = new; t.applySchedulePoolsToDivisions() }
            })).frame(width: 80)
            Picker("", selection: Binding(get: { teamIndex(team.id).flatMap { t.plus.schedule.teams[$0].rosterTeam } ?? -1 }, set: { new in
                if let i = teamIndex(team.id) { t.plus.schedule.teams[i].rosterTeam = new < 0 ? nil : new; t.applySchedulePoolsToDivisions() }
            })) {
                Text("Roster team: not linked yet").tag(-1)
                ForEach(t.teams.indices, id: \.self) { Text(t.teams[$0].name).tag($0) }
            }.labelsHidden().frame(width: 220)
            Button { t.plus.schedule.removeTeam(team.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove this team")
            Spacer()
        }
    }

    private func removeSchool(_ school: ScheduleSchool) {
        let n = sched.teams(inSchool: school.name).count
        showAlert(AlertInfo(title: "Remove \(school.name)?", message: n == 0 ? "" : "Its \(n) team\(n == 1 ? "" : "s") will be removed from the schedule too.",
                            primary: "Remove", secondary: "Cancel", onPrimary: { t.plus.schedule.removeSchool(school.id) }))
    }

    private var poolSummary: String {
        let pools = sched.poolNames
        if pools.isEmpty { return "Give each team a pool in the Teams section." }
        let parts = pools.map { p in "\(p): \(sched.teams.filter { $0.pool.trimmingCharacters(in: .whitespaces) == p }.count) teams" }
        let rounds = pools.map { p in Schedule.roundRobinRounds(forPoolOf: sched.teams.filter { $0.pool.trimmingCharacters(in: .whitespaces) == p }.count) }.max() ?? 0
        return parts.joined(separator: ", ") + ". A full round robin takes \(rounds) round\(rounds == 1 ? "" : "s"); each round needs a room for every game."
    }

    private func dealPools(count: Int) {
        t.addRosterTeamsToSchedule()   // teams imported from NAQT first: bring them into the schedule
        for (i, team) in sched.teams.enumerated() {
            if let k = t.plus.schedule.teams.firstIndex(where: { $0.id == team.id }) {
                t.plus.schedule.teams[k].pool = "Pool " + String(UnicodeScalar(65 + i % count)!)
            }
        }
        t.plus.schedule.poolRoundRobin = true
        t.applySchedulePoolsToDivisions()
    }

    private func createGames() {
        t.applySchedulePoolsToDivisions()
        let r = t.createScheduledGames()
        var message = ""
        if r.skipped > 0 { message = "\(r.skipped) scheduled game\(r.skipped == 1 ? "" : "s") could not be created because a team is not linked to a roster team yet (Teams section)." }
        showAlert(AlertInfo(title: r.created == 0 && r.updated == 0 ? "No new games were created." : "Created \(r.created) game\(r.created == 1 ? "" : "s") in Game Entry" + (r.updated > 0 ? ", updated \(r.updated)." : "."), message: message))
    }

    private func addRosterTeams() {
        let added = t.addRosterTeamsToSchedule()
        showAlert(AlertInfo(title: added == 0 ? "Every roster team is already scheduled." : "Added \(added) team\(added == 1 ? "" : "s") from the roster.",
                            message: added == 0 ? "" : "Schools were worked out from the team names (a trailing letter is dropped). Check them under Teams."))
    }

    // Sheets: add a school, or add schools from a list

    /// The Add School window on its own (used for previews).
    var addSchoolPreview: some View { addSchoolSheet }

    private var addSchoolSheet: some View {
        let name = newSchoolName.trimmingCharacters(in: .whitespaces)
        let duplicate = !name.isEmpty && sched.school(named: name) != nil
        return VStack(alignment: .leading, spacing: 12) {
            Text("Add a School").font(.title3).bold()
            Label(Self.naqtTip, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("School name").frame(width: 120, alignment: .leading)
                TextField("e.g. Central", text: $newSchoolName).frame(width: 300)
            }
            HStack {
                Text("Number of teams").frame(width: 120, alignment: .leading)
                TextField("", value: $newSchoolTeams, format: .number).frame(width: 50).multilineTextAlignment(.trailing)
                Stepper("", value: $newSchoolTeams, in: 1...12).labelsHidden()
            }
            if !name.isEmpty {
                let count = min(max(newSchoolTeams, 1), 12)
                Text("Teams: " + (count == 1 ? name : (0..<count).map { "\(name) \(String(UnicodeScalar(65 + $0)!))" }.joined(separator: ", ")))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if duplicate { Text("\(name) is already in the list.").font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { teamSheet = nil }
                Button("Add School") {
                    t.plus.schedule.addSchool(name: name, teamCount: min(max(newSchoolTeams, 1), 12))
                    teamSheet = nil
                }.keyboardShortcut(.defaultAction).disabled(name.isEmpty || duplicate)
            }
        }.padding(18).frame(width: 480)
    }

    // MARK: Schedule grid

    private var sortedTeams: [ScheduleTeam] {
        sched.teams.sorted { t.scheduleTeamName($0.id).localizedCaseInsensitiveCompare(t.scheduleTeamName($1.id)) == .orderedAscending }
    }

    private func teamLabel(_ team: ScheduleTeam) -> String {
        let n = t.scheduleTeamName(team.id)
        return team.school.isEmpty || n.localizedCaseInsensitiveContains(team.school) ? n : "\(n) (\(team.school))"
    }

    private var grid: some View {
        Group {
            if total <= 0 || sched.rooms.isEmpty {
                Text("Set the number of rounds and add rooms under Setup first.").foregroundStyle(.secondary).padding(20)
            } else {
                GeometryReader { geo in
                let cellW = cellWidth(available: geo.size.width)
                ScrollView([.horizontal, .vertical]) {
                    if prelim < total {
                        Text("Playoff games appear in rounds \(prelim + 1)–\(total) once the brackets are set up under Playoffs & Consolation; set moderators and scorekeepers for them here.")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Text("Round").bold()
                            ForEach(sched.rooms) { Text($0.name).bold().frame(width: cellW, alignment: .leading) }
                        }
                        ForEach(1...total, id: \.self) { r in
                            GridRow {
                                VStack(alignment: .leading) {
                                    Text("\(r)").font(.title3).bold()
                                    if r > prelim { Text("playoffs").font(.caption2).foregroundStyle(.secondary) }
                                }.frame(width: 60, alignment: .leading)
                                ForEach(sched.rooms) { room in cell(round: r, room: room, width: cellW) }
                            }
                            if !byeText(round: r).isEmpty {
                                GridRow {
                                    Color.clear.frame(width: 1, height: 1)
                                    Text("Bye: " + byeText(round: r)).font(.caption).foregroundStyle(.secondary)
                                        .gridCellColumns(max(sched.rooms.count, 1)).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Divider().gridCellUnsizedAxes(.horizontal)
                        }
                    }.padding(12)
                }
                }
            }
        }
    }

    /// Room columns share the window width (down to a minimum); beyond that the grid scrolls sideways.
    private func cellWidth(available: CGFloat) -> CGFloat {
        let rooms = CGFloat(max(sched.rooms.count, 1))
        let fixed: CGFloat = 60 + 24 + (rooms + 1) * 8     // round column, padding, gaps
        return min(max((available - fixed) / rooms, 150), 240)
    }

    private func byeText(round r: Int) -> String {
        guard r <= prelim else { return "" }
        let slots = sched.slots(inRound: r)
        guard slots.contains(where: \.hasAnyTeam) else { return "" }
        let playing = Set(slots.flatMap { [$0.teamA, $0.teamB].compactMap { $0 } })
        return sched.teams.filter { !playing.contains($0.id) }.map { t.scheduleTeamName($0.id) }.joined(separator: ", ")
    }

    private func cell(round r: Int, room: ScheduleRoom, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let i = sched.slotIndex(round: r, room: room.id) {
                if r <= prelim {
                    HStack(alignment: .top, spacing: 4) {
                        VStack(spacing: 2) { teamPicker(i, isA: true, width: width - 46); teamPicker(i, isA: false, width: width - 46) }
                        Button { t.plus.schedule.games[i].pinned.toggle() } label: {
                            Image(systemName: sched.games[i].pinned ? "lock.fill" : "lock.open").foregroundStyle(sched.games[i].pinned ? Color.accentColor : .secondary)
                        }.buttonStyle(.borderless)
                            .help(sched.games[i].pinned ? "Locked: random scheduling leaves this game alone. Click to unlock." : "Click to lock this game so random scheduling leaves it alone.")
                    }
                } else {
                    let m = t.scheduleMatchup(sched.games[i])
                    if sched.games[i].playoffGame != nil {
                        Text(m.a).font(.callout); Text("vs \(m.b)").font(.callout).foregroundStyle(.secondary)
                    } else { Text("—").foregroundStyle(.secondary) }
                }
                staffPicker(i, role: .moderator, round: r, width: width - 38)
                staffPicker(i, role: .scorekeeper, round: r, width: width - 38)
            }
        }
        .padding(5)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private func teamPicker(_ i: Int, isA: Bool, width: CGFloat) -> some View {
        Picker("", selection: Binding(get: { (isA ? t.plus.schedule.games[i].teamA : t.plus.schedule.games[i].teamB) ?? 0 }, set: { new in
            if isA { t.plus.schedule.games[i].teamA = new == 0 ? nil : new } else { t.plus.schedule.games[i].teamB = new == 0 ? nil : new }
            let g = t.plus.schedule.games[i]
            t.plus.schedule.games[i].pinned = g.hasAnyTeam
        })) {
            Text("—").tag(0)
            ForEach(sortedTeams) { Text(teamLabel($0)).tag($0.id) }
        }.labelsHidden().frame(width: width)
    }

    private func staffPicker(_ i: Int, role: StaffRole, round r: Int, width: CGFloat) -> some View {
        let people = sched.staff.filter { $0.role == role }
        return HStack(spacing: 4) {
            Text(role == .moderator ? "M" : "S").font(.caption).foregroundStyle(.secondary).frame(width: 12, alignment: .leading)
                .help(role == .moderator ? "Moderator" : "Scorekeeper")
            Picker("", selection: Binding(get: { (role == .moderator ? t.plus.schedule.games[i].moderator : t.plus.schedule.games[i].scorekeeper) ?? 0 }, set: { new in
                if role == .moderator { t.plus.schedule.games[i].moderator = new == 0 ? nil : new; t.plus.schedule.games[i].moderatorPinned = new != 0 }
                else { t.plus.schedule.games[i].scorekeeper = new == 0 ? nil : new; t.plus.schedule.games[i].scorekeeperPinned = new != 0 }
            })) {
                Text("—").tag(0)
                ForEach(people) { Text($0.isAvailable(round: r) ? $0.name : "\($0.name) (not available)").tag($0.id) }
            }.labelsHidden().frame(width: width)
        }
    }

    // MARK: Staff

    private var staffPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("Auto-Assign Moderators and Scorekeepers") {
                    var copy = t
                    copy.autoAssignScheduleStaff()
                    t = copy
                }.help("Fill every open slot from these lists. Slots you chose by hand stay.")
                Button("Clear Automatic Assignments") {
                    for i in t.plus.schedule.games.indices {
                        if !t.plus.schedule.games[i].moderatorPinned { t.plus.schedule.games[i].moderator = nil }
                        if !t.plus.schedule.games[i].scorekeeperPinned { t.plus.schedule.games[i].scorekeeper = nil }
                    }
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: 24) {
                staffList(.moderator)
                staffList(.scorekeeper)
            }
            Text("Someone who is only there for part of the day can be limited to certain rounds. Nobody is placed in two rooms in the same round.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }

    private func staffList(_ role: StaffRole) -> some View {
        GroupBox(role.title + "s") {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach($t.plus.schedule.staff) { $m in
                            if m.role == role {
                                HStack(spacing: 6) {
                                    TextField("Name", text: $m.name).frame(width: 150)
                                    Picker("", selection: $m.allDay) { Text("All day").tag(true); Text("Rounds…").tag(false) }.labelsHidden().frame(width: 90)
                                    if !m.allDay {
                                        TextField("", value: $m.fromRound, format: .number).frame(width: 34).multilineTextAlignment(.trailing)
                                        Text("to")
                                        TextField("", value: $m.toRound, format: .number).frame(width: 34).multilineTextAlignment(.trailing)
                                    }
                                    Button { t.plus.schedule.removeStaff(m.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }.frame(minHeight: 180)
                HStack {
                    Button("Add \(role.title)") { t.plus.schedule.addStaff(name: "", role: role, toRound: max(total, 1)) }
                    Text("\(sched.staff.filter { $0.role == role }.count) listed").foregroundStyle(.secondary)
                }
            }.padding(8)
        }.frame(minWidth: 400)
    }

    // MARK: Buzzers (day-of tracker)

    private var buzzers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("Add Buzzers") { t.plus.schedule.addBuzzers(owner: "") }
                Button("Add One per School") {
                    let schools = Array(Set(sched.teams.map { $0.school.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
                    let have = Set(sched.buzzers.map(\.owner))
                    for s in schools where !have.contains(s) { t.plus.schedule.addBuzzers(owner: s) }
                }
                Spacer()
                Text("Day-of tracker: whose buzzers are in which room.").foregroundStyle(.secondary)
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow { Text("Whose buzzers").bold(); Text("Room").bold(); Text("Note").bold(); Text("") }.font(.caption)
                    ForEach($t.plus.schedule.buzzers) { $b in
                        GridRow {
                            TextField("School, team or person", text: $b.owner).frame(width: 240)
                            Picker("", selection: Binding(get: { b.room ?? 0 }, set: { b.room = $0 == 0 ? nil : $0 })) {
                                Text("Not in a room").tag(0)
                                ForEach(sched.rooms) { Text($0.name).tag($0.id) }
                            }.labelsHidden().frame(width: 170)
                            TextField("Note", text: $b.note).frame(width: 220)
                            Button { t.plus.schedule.buzzers.removeAll { $0.id == b.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                }.padding(.vertical, 4)
            }
        }.padding(16)
    }

    // MARK: Checks

    private var checks: some View {
        let issues = t.scheduleIssues
        let counts = sched.gamesPerTeam(rounds: prelim)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sched.teams.isEmpty {
                    Text("Add teams and make a schedule to see checks here.").foregroundStyle(.secondary)
                } else if issues.isEmpty {
                    Label("The schedule passes every check.", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
                } else {
                    ForEach(issues) { issue in
                        Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !sched.teams.isEmpty && prelim > 0 {
                    GroupBox("Games per team (preliminary rounds)") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 3) {
                            GridRow { Text("Team").bold(); Text("School").bold(); Text("Games").bold(); Text("Byes").bold() }.font(.caption)
                            ForEach(sortedTeams) { team in
                                GridRow {
                                    Text(t.scheduleTeamName(team.id))
                                    Text(team.school).foregroundStyle(.secondary)
                                    Text("\(counts[team.id] ?? 0)").monospacedDigit()
                                    Text("\(prelim - (counts[team.id] ?? 0))").monospacedDigit()
                                }
                            }
                        }.padding(8)
                    }.frame(maxWidth: 560)
                }
            }.padding(16)
        }
    }
}
