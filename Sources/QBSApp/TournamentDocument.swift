import SwiftUI
import UniformTypeIdentifiers
import QBSCore

struct TournamentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sqbsTournament, .data] }
    static var writableContentTypes: [UTType] { [.sqbsTournament] }

    var tournament: Tournament
    /// Notes from loading (for example teams with more than 12 players).
    var loadNotes: [String] = []

    init() {
        var t = Tournament()
        t.settings.teamSortRaw = 1
        tournament = t
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        do {
            let result = try TournamentFile.read(data: data)
            tournament = result.tournament
            loadNotes = result.notes
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "\(error)"])
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Files that may be sent to NAQT (.sqbs or no extension) never carry the extra playoff/schedule block.
        let name = (configuration.existingFile?.preferredFilename ?? "").lowercased()
        let keepPlus = !(name.hasSuffix(".sqbs") || (!name.isEmpty && !name.contains(".")))
        let text = TournamentFile.write(tournament, includePlus: keepPlus)
        return FileWrapper(regularFileWithContents: text.data(using: .isoLatin1) ?? Data(text.utf8))
    }
}
