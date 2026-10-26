import SwiftUI
import WebKit
import QBSCore

struct ReportsView: View {
    let t: Tournament
    var fileURL: URL?
    var filter: RoundFilter
    @Binding var quick: QuickReport

    @State private var fitToPage = false
    @StateObject private var holder = WebHolder()

    private var html: String {
        let gen = ReportGenerator(tournament: t, baseName: "", filter: filter, quickPrint: true)
        switch quick {
        case .teams: return gen.page(.standings)
        case .individuals: return gen.page(.individuals)
        case .games: return gen.quickGamesPage()
        case .roomMatchups: return ScheduleReports(tournament: t).page(.roomMatchups)
        case .teamSchedules: return ScheduleReports(tournament: t).page(.teamSchedule)
        case .missingSlots: return ScheduleReports(tournament: t).page(.missingSlots)
        case .buzzers: return ScheduleReports(tournament: t).page(.buzzers)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Select Quick Report or use Reports Menu", selection: $quick) {
                    ForEach(QuickReport.allCases) { Text($0.rawValue).tag($0) }
                }.frame(maxWidth: 520)
                Spacer()
                Toggle("Fit to single page", isOn: $fitToPage)
                Button("Print") { holder.printReport(fit: fitToPage) }
            }
            WebView(html: html, holder: holder)
                .background(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
        }.padding(12)
    }
}

final class WebHolder: ObservableObject {
    weak var webView: WKWebView?
    func printReport(fit: Bool) {
        guard let webView else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        if fit { info.horizontalPagination = .fit; info.verticalPagination = .fit }
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        op.runModal(for: webView.window ?? NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
    }
}

struct WebView: NSViewRepresentable {
    let html: String
    let holder: WebHolder
    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero)
        holder.webView = v
        return v
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        holder.webView = view
        if context.coordinator.last != html {
            context.coordinator.last = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var last = "" }
}
