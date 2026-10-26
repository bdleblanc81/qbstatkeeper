import SwiftUI
import AppKit
import QBSCore

struct MergeSheet: View {
    @Binding var base: Tournament
    var baseName: String
    @Binding var isPresented: Bool
    var showAlert: (AlertInfo) -> Void

    @State private var chosen: URL?
    @State private var other: Tournament?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge Tournaments").font(.headline)
            Text("This tournament will be used as the base for merge of other tournament file.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Base Tournament Name", value: base.settings.tournamentName)
            LabeledContent("Base Tournament FileName", value: baseName)
            Divider()
            Text("Select tournament below to merge with this tournament.")
            HStack {
                Text(chosen?.lastPathComponent ?? "No file selected").foregroundStyle(chosen == nil ? .secondary : .primary)
                Spacer()
                Button("Choose File…") { choose() }
            }
            if let o = other { LabeledContent("Tournament Name", value: o.settings.tournamentName) }
            if let problem { Text(problem).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Merge") { merge() }.disabled(other == nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 520)
    }

    private func choose() {
        let p = NSOpenPanel()
        p.message = "Choose the tournament file to merge into this one."
        guard p.runModal() == .OK, let url = p.url else { return }
        chosen = url; other = nil; problem = nil
        do { other = try TournamentFile.read(url: url).tournament } catch { problem = "\(error)" }
    }

    private func merge() {
        guard let other else { return }
        do {
            let result = try TournamentMerge.mergeDetailed(base: base, other: other)
            base = result.tournament
            isPresented = false
            showAlert(AlertInfo(title: "Merge complete.", message: result.summary))
        } catch let failure as TournamentMerge.Failure {
            problem = failure.description
        } catch { problem = "\(error)" }
    }
}
