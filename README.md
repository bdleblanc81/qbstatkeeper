# Quiz Bowl Statkeeper for Mac

A native macOS (Apple Silicon) statkeeping program for quiz bowl tournaments. It reads and writes the same
tournament data as the SQBS statkeeper and its reports match SQBS, and it adds scheduling, pools and playoffs.

This is an independent project. It is not affiliated with or endorsed by NAQT or the authors of SQBS.

## What it does
* **Tournament setup:** teams, rosters, divisions, question values, bonus tracking, exhibition teams.
* **Game entry:** per-player stats with automatic bonus calculation, warnings and errors for inconsistent games,
  lineups remembered from game to game, forfeits, overtime.
* **Reports:** team standings, individuals, scoreboard, team and player detail, round report, stat key, and web reports.
* **Schedule:** schools and teams (before rosters exist), rooms, random or hand-built schedules, round robin within pools,
  moderators and scorekeepers (all day or certain rounds), buzzer locations, checks, and room/team/missing-slot reports.
* **Playoffs and consolation:** seeding by standings or by pool, cross-pool brackets, wild cards, tiebreakers, third-place games.
* **Files:** `.qzx` is the tournament file. `.sqbs` is only used to import teams from NAQT and to export for NAQT.
  Merging two copies of a tournament is supported.

See [FEATURES.md](FEATURES.md) for details of the features added on top of SQBS.

## Requirements
* An Apple Silicon Mac running macOS 13 or later.
* To build it yourself: the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

## Install
Download `QuizBowlStatkeeper.dmg` from the [Releases](../../releases) page, open it, and drag the app to Applications.
The app is not notarized, so macOS blocks it the first time: try to open it, then go to System Settings > Privacy & Security
and click "Open Anyway".

## Build it yourself
```bash
./scripts/build-app.sh
open "dist/Quiz Bowl Statkeeper for Mac.app"
```

To make the disk image: `./scripts/make-dmg.sh`. To publish it as a GitHub Release: `./scripts/release.sh 1.0`.

## Layout
* `Sources/QBSCore`: file format, statistics, reports, scheduling, playoffs (no UI).
* `Sources/QBSApp`: the SwiftUI application.
* `scripts`: app build, disk image and release scripts, and the icon generator.

## License
MIT. See [LICENSE](LICENSE).
