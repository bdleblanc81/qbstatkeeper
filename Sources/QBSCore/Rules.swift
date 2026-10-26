import Foundation

/// A change SQBS refuses (or warns about), with the wording it shows.
public struct RuleViolation: Equatable, Sendable {
    public var title: String
    public var detail: String
}

extension Tournament {
    /// Games that have been played (scheduled games still waiting for a score do not count).
    public var hasGames: Bool { !statGames.isEmpty }

    public func questionValueChangeViolation() -> RuleViolation? {
        hasGames ? RuleViolation(title: "Question values can't be changed once game data entered.",
                                 detail: "Changing question point value could make game results inconsistent.") : nil
    }

    public func unselectQuestionViolation(_ q: Int) -> RuleViolation? {
        let used = games.contains { g in
            (g.playersA + g.playersB).contains { ($0?.counts[q] ?? 0) != 0 }
        }
        return used ? RuleViolation(title: "Games exist with counts against Question \(q). Unselecting not allowed.",
                                    detail: "Action allowed once all counts for that question are zeroed.") : nil
    }

    public func unselectLightningViolation() -> RuleViolation? {
        let used = games.contains { $0.lightningA != 0 || $0.lightningB != 0 }
        return used ? RuleViolation(title: "Unselecting Lightning Round tracking not allowed because lightning points assigned in games.",
                                    detail: "Action allowed once all Lightning round points are zeroed.") : nil
    }

    /// Once games exist the bonus method can only be switched to Automatic, and only if no bonus values were entered.
    public func bonusModeChangeViolation(to mode: BonusTracking) -> RuleViolation? {
        guard hasGames else { return nil }
        if mode != .automatic {
            return RuleViolation(title: "Bonus conversion method can't be changed once game data entered.",
                                 detail: "Changing Bonus conversion method could make game results inconsistent.")
        }
        let hasBonus = games.contains { $0.bonusPointsA > 0 || $0.bonusPointsB > 0 || $0.bouncebackPointsA > 0 || $0.bouncebackPointsB > 0 }
        return hasBonus ? RuleViolation(title: "Games exist with Bonus values assigned. Change not allowed.",
                                        detail: "Changing Bonus conversion method could make game results inconsistent.") : nil
    }

    public func powerNegViolation() -> RuleViolation? {
        let v = settings.questionValues, sel = settings.questionSelected
        guard settings.trackPowerNeg else { return nil }
        if sel[0] && v[0] > 0 && sel[2] && v[2] < 0 { return nil }
        return RuleViolation(title: "Question settings not correct for power / negative tracking.",
                             detail: "P/N tracking assumes:\nQuestion 0 selected and value greater than 0, and\nQuestion 2 selected and value less than 0.")
    }

    public func deleteTeamViolation() -> RuleViolation? {
        !games.isEmpty ? RuleViolation(title: "You cannot delete a team once games have been entered",
                                 detail: "Games have been entered. Deletion not allowed.") : nil
    }

    public static let tossupsHeardNotice = RuleViolation(title: "TUH value for existing games not changed.",
                                                         detail: "Suggest existing games be reviewed to ensure tournament statistics are consistent and valid.")

    // MARK: Team list edits

    /// Sorts teams by name and rewrites game team indexes to match (SQBS's `adjustTeamIndexesInGames`).
    public mutating func sortTeams(ascending: Bool) {
        let order = teams.indices.sorted { a, b in
            let c = teams[a].name.localizedCaseInsensitiveCompare(teams[b].name)
            if c == .orderedSame { return a < b }
            return ascending ? c == .orderedAscending : c == .orderedDescending
        }
        var newIndex = [Int](repeating: 0, count: teams.count)
        for (new, old) in order.enumerated() { newIndex[old] = new }
        teams = order.map { teams[$0] }
        for i in games.indices {
            if games[i].teamA >= 0 && games[i].teamA < newIndex.count { games[i].teamA = newIndex[games[i].teamA] }
            if games[i].teamB >= 0 && games[i].teamB < newIndex.count { games[i].teamB = newIndex[games[i].teamB] }
        }
    }

    /// Replaces the division list; teams keep a division only if its name still exists.
    public mutating func setDivisions(_ names: [String]) {
        let old = divisions
        divisions = names
        for i in teams.indices {
            if let d = teams[i].division, d < old.count { teams[i].division = names.firstIndex(of: old[d]) } else { teams[i].division = nil }
        }
    }
}
