# Quiz Bowl Statkeeper for Mac

* Format: total rounds, playoff start round, size of the top bracket (the rest go to consolation).
* Tiebreakers: head-to-head, team points per 20 tossups heard, top individual points per 20 tossups heard, coin flip.
  Each can be switched on/off and reordered; coin-flip results are typed in per team. Optional: use them to order standings and reports.
* Seeds: follow the standings after the preliminary rounds, or set by hand.
* Brackets: generated single-elimination (byes when needed) for the top bracket and for consolation, then fully editable:
  each game's two sides can be a seed, the winner/loser of another game, a specific team, or a bye.
* "Assign Teams & Create Games" puts each ready pairing into the game list as a real game in its real round (ID like T1-1).
  Unplayed ones are placeholders: they appear in Game Entry but never count in stats, reports or exports until a score is entered.

File handling: the playoff layout is stored after the normal tournament data in .qzx files.
It is never written to the NAQT export, to .sqbs files or to extensionless files; the games themselves (played, with their rounds) always are.

## Rounds, game IDs and the new Game Entry buttons
* Format tab: type the number of rounds, the number of playoff rounds (the last rounds of the tournament) and the teams in the top bracket; optional third-place game.
* Game IDs use {round}-{game} everywhere (for example 4-2); bracket games get the same format.
* Game Entry: "Enter New Game" saves the game in view and starts a new one with a new unique ID in the same round (in a playoff round it
  moves to the next predetermined matchup instead). "Start New Round" saves, checks the round that is ending, and starts the next one:
  - preliminary round: if any team has no game recorded, a dialog asks you to confirm starting the round anyway;
  - playoff round with predetermined games: if any game has no score, a dialog lists them and offers to start the round anyway or cancel.

## Schedule
A **Schedule** tab sits after Tournament Setup. It schedules teams before their rosters are known, assigns rooms,
moderators and scorekeepers, tracks buzzers on the day, and feeds the playoff setup.

* **Setup**: rounds in the tournament and playoff rounds (the same numbers the Playoffs & Consolation setup uses), the rooms,
  and the rules for random scheduling (no return to a room for X rounds, no same-school games, every school meets every other).
* **Teams**: scheduled team, school, and a link to the roster team once rosters exist (Link Roster by Name / Add Roster Teams).
* **Schedule**: a round-by-room grid. Choose teams by hand to lock a game (random scheduling then works around it), or
  Generate Random Schedule. Teams sit out byes in turn so everyone gets the same number of games.
* **Staff**: moderators and scorekeepers, all day or for rounds X to Y; auto-assigned without double booking, with
  any slot overridable.
* **Buzzers**: whose buzzers are in which room (day-of tracker).
* **Checks**: equal games including byes, double booking, room repeats, same-school games, school coverage, staff conflicts.
* Reports (Reports menu and Full Web Report): Room Matchups, Team Schedules, Missing Slots, Buzzer Locations.

The schedule is stored in the `.qzx`  data block only; it is never part of the `.sqbs` file sent to NAQT.


## Files
* **.qzx** is the tournament file: every Save updates the tournament .qzx file.
* **.sqbs** is only used to bring teams in (Import Teams, which merges with teams already entered and matches them by name)
  and to send to NAQT (Export .sqbs File for NAQT). Opening a .sqbs opens an unsaved copy; the original is never written to.


## Pools and pool playoffs
* **Schedule > Teams > Pool** (or **Deal into Two Pools**): teams get a pool. **Round robin within pools** (Schedule > Setup) schedules a
  full round robin inside each pool; linking to roster teams makes the pools the tournament's divisions.
* **Create Games in Game Entry** adds each scheduled game (for teams linked to the roster) as a game waiting for a score; they never count
  in standings, reports or the NAQT export until a score is entered.
* **Playoffs & Consolation > Format > Pool play**: seeds alternate A1, B1, A2, B2, ...; the top N of each pool play a cross-pool top bracket
  (semifinals A1 v B2 and B1 v A2); everyone else plays cross-pool games in every playoff round (equal ranks first, then neighbors).

Pools can number two or more. With three or more pools the seeds go A1, B1, C1, A2, B2, C2, ...; the top bracket is arranged so
pool-mates avoid each other in the first round; consolation games pair teams from different pools, never a repeat opponent
(a team left without a valid partner has no game that round). Deal into Pools (Schedule > Teams) makes 2 to 8 pools.
Wild cards: on the Playoffs & Consolation Format screen, "Wild card teams" adds that many top-bracket spots for the best teams (by record,
from any pool) that did not finish in their pool's advancing places. Wild cards are seeded after the pool qualifiers.

Divisions and pools: while any scheduled team has a pool, Tournament Setup shows the divisions (and each team's division) read-only; pools are
changed on the Schedule tab. Teams can come first (import from NAQT, then Schedule > Teams > Add Roster Teams or Deal into Pools, which
brings the imported teams in) or pools first (set pools, then import: teams are matched by name). Divisions entered in Setup before scheduling
become the pools when the teams are added to the schedule.

Merge Files: games waiting for a score (scheduled or playoff) are never copied as games; a played game from the other file fills in the same
game still waiting here (keeping this tournament's ID). A game in both files is not added twice; one with different results is reported and
this tournament's is kept. A new game whose ID is already used gets a new ID. A tournament with no schedule or playoff setup takes the other
file's. The schedule, pools and playoff setup are otherwise kept as this tournament has them. A summary is shown after the merge.
