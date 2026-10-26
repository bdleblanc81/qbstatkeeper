import SwiftUI
import AppKit
import QBSCore

/// `QuizBowlStatkeeper --snapshot out.png file.qzx [tab 0-3] [width height]` renders a window offscreen and exits.
/// Used to check the layout without a visible screen.
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let input = URL(fileURLWithPath: args[i + 2])
        let tabIndex = args.count > i + 3 ? Int(args[i + 3]) ?? 0 : 0
        let width = args.count > i + 4 ? Double(args[i + 4]) ?? 1100 : 1100
        let height = args.count > i + 5 ? Double(args[i + 5]) ?? 760 : 760

        let tabTest = args.contains("--tabtest")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        final class Box { var doc: TournamentDocument = TournamentDocument() }
        let box = Box()
        if let data = try? Data(contentsOf: input), let result = try? TournamentFile.read(data: data) { box.doc.tournament = result.tournament }
        let binding = Binding(get: { box.doc }, set: { box.doc = $0 })
        if let j = args.firstIndex(of: "--playoffs"), args.count > j + 1 {
            var t = box.doc.tournament
            t.plus.playoffs.totalRounds = 5; t.plus.playoffs.playoffRounds = 3; t.plus.playoffs.thirdPlaceGame = true; t.plus.playoffs.topBracketSize = 4
            t.plus.playoffs.useTiebreakers = true
            t.generateDefaultBrackets()
            t.syncPlayoffGames()
            box.doc.tournament = t
            let pane = PlayoffsSheet.Pane.allCases[min(max(Int(args[j + 1]) ?? 0, 0), 3)]
            let tb = Binding(get: { box.doc.tournament }, set: { box.doc.tournament = $0 })
            let host = NSHostingView(rootView: PlayoffsSheet(t: tb, isPresented: .constant(true), initialPane: pane, showAlert: { _ in }))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua); host.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 860, height: 640)
            for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(2) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
            exit(0)
        }
        if let j = args.firstIndex(of: "--schedule"), args.count > j + 1 {
            var t = box.doc.tournament
            t.plus.playoffs.totalRounds = 8; t.plus.playoffs.playoffRounds = 2
            t.plus.schedule = Schedule()
            for (s, n) in [("Adams", 2), ("Jefferson", 3), ("Lincoln", 2), ("Riverside Christian", 1), ("Valley Science", 1), ("Washington", 2)] {
                t.plus.schedule.addSchool(name: s, teamCount: n)
            }
            for r in 1...5 { t.plus.schedule.addRoom(name: "Room \(r + 17)") }
            for k in 1...6 { t.plus.schedule.addStaff(name: "Moderator \(k)", role: .moderator, allDay: k < 5, fromRound: 1, toRound: 4) }
            for k in 1...6 { t.plus.schedule.addStaff(name: "Scorekeeper \(k)", role: .scorekeeper) }
            t.plus.schedule.addBuzzers(owner: "Adams", room: t.plus.schedule.rooms[0].id)
            t.plus.schedule.addBuzzers(owner: "Lincoln")
            t.generateSchedule(seed: 7)
            box.doc.tournament = t
            let pane = ScheduleView.Pane.allCases[min(max(Int(args[j + 1]) ?? 0, 0), ScheduleView.Pane.allCases.count - 1)]
            let tb = Binding(get: { box.doc.tournament }, set: { box.doc.tournament = $0 })
            let view = ScheduleView(t: tb, initialPane: pane, initialSheet: args.contains("--schoolsheet") ? .school : nil, showAlert: { _ in })
            let host = args.contains("--schoolsheet") ? NSHostingView(rootView: AnyView(view.addSchoolPreview.background(Color(NSColor.windowBackgroundColor)))) : NSHostingView(rootView: AnyView(view))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua); host.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            for _ in 0..<8 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(2) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
            exit(0)
        }
        if args.contains("--welcome") {
            let sample = ["2026 Spring Tournament", "Invitational", "Practice Tournament"].map { URL(fileURLWithPath: "/Users/example/Documents/Quiz Bowl/\($0).qzx") }
            let host = NSHostingView(rootView: WelcomeView(recent: sample, create: {}, load: {}, exit: {}))
            let h = WelcomeView.height(recent: sample.count)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: h), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua); host.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 560, height: h)
            for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(2) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
            exit(0)
        }
        let tab = DocumentTab.allCases[min(max(tabIndex, 0), DocumentTab.allCases.count - 1)]
        let host = NSHostingView(rootView: DocumentView(document: binding, fileURL: input, initialTab: tab))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua); host.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
        if args.contains("--anchortest") {
            window.makeKeyAndOrderFront(nil)
            for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
            func describe(_ r: NSResponder?) -> String {
                guard let r else { return "nil" }
                if let tv = r as? NSTextView, let tf = tv.delegate as? NSTextField { return "text field editor for field \"\(tf.stringValue)\" (name field = \(tf.isEditable))" }
                return String(describing: type(of: r))
            }
            print("first responder when the window opens: \(describe(window.firstResponder))")
            for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
            print("a moment later: \(describe(window.firstResponder))")
            window.selectNextKeyView(nil)
            print("after one Tab: \(describe(window.firstResponder))")
            window.selectNextKeyView(nil)
            print("after two Tabs: \(describe(window.firstResponder))")
            exit(0)
        }
        if tabTest {
            for _ in 0..<8 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
            KeyViewLinker.relink(window)
            let order = KeyViewLinker.traversal(window, steps: 200)
            print(order.map { "\($0.group).\($0.row).\($0.col)" }.joined(separator: " "))
            exit(0)
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(2) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
        try? png.write(to: out)
        exit(0)
    }
}
