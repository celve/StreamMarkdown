@_spi(Diagnostics) import StreamMarkdown
import SwiftUI

/// LIN-2404's measurement (softlash/LIN-2404 docs/compare/Host/App.swift), unchanged so numbers compare across renderers:
/// with `-stream 1 -perf 1`, wait 3 s, stream the answer `-speed` characters every 50 ms (6 by default), scroll it top to
/// bottom over 8 s and back over 4 s, print `PERF` lines and exit. `-long 1` streams the 10k-character answer; `-render 0`
/// keeps everything but the renderer, an empty view of about the answer's height in its place, to measure the floor.
struct PerfRun: View {
    let sample = UserDefaults.standard.bool(forKey: "long") ? Answer.longSample : Answer.named("lora")!.text
    @State private var shown = 0
    @State private var streaming = false
    @State private var position = ScrollPosition(edge: .top)
    @State private var scrollable: CGFloat = 0
    @ObservedObject private var perf = Perf.shared
    private let enabled = UserDefaults.standard.bool(forKey: "perf")
    private let renders = UserDefaults.standard.object(forKey: "render") == nil || UserDefaults.standard.bool(forKey: "render")

    var body: some View {
        let text = String(sample.prefix(shown))
        VStack(alignment: .leading, spacing: 0) {
            Text("\(renders ? "StreamMarkdown" : "No renderer") · stream \(shown)")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollView {
                if renders {
                    StreamMarkdownView(text, isStreaming: streaming).padding()
                } else {
                    Color.clear.frame(height: CGFloat(text.count) * 1.6).padding()
                }
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height - $0.containerSize.height } action: { scrollable = $1 }
            .onChange(of: perf.scrollProgress) { position.scrollTo(y: scrollable * perf.scrollProgress) }
        }
        .task { await run() }
    }

    private func run() async {
        if enabled {
            perf.start()
            let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
            Perf.log("screen maximumFramesPerSecond=\(screen?.maximumFramesPerSecond ?? 0)")
        }
        streaming = true
        try? await Task.sleep(for: .seconds(3))
        let speed = UserDefaults.standard.integer(forKey: "speed")
        let step = speed > 0 ? speed : 6
        var second = Date(), perSecond: [String] = []
        perf.reset()
        StreamMarkdownDiagnostics.reset()
        let began = Date()
        var early = (busy: 0.0, hitchMs: 0.0, secs: 0.0), late = (busy: 0.0, hitchMs: 0.0, secs: 0.0)
        var secBusy = 0.0, secHitch = 0.0
        while shown < sample.count {
            try? await Task.sleep(for: .milliseconds(50))
            shown = min(sample.count, shown + step)
            if enabled, Date().timeIntervalSince(second) >= 1 {
                let busy = perf.busyMs - secBusy, hitch = perf.hitchMs - secHitch
                secBusy = perf.busyMs; secHitch = perf.hitchMs
                let fraction = Double(shown) / Double(sample.count)
                if fraction <= 0.25 { early.busy += busy; early.hitchMs += hitch; early.secs += 1 }
                if fraction >= 0.75 { late.busy += busy; late.hitchMs += hitch; late.secs += 1 }
                perSecond.append(String(format: "%d:%.0f", shown, busy))
                second = Date()
            }
        }
        streaming = false
        guard enabled else { return }
        let streamSecs = Date().timeIntervalSince(began)
        Perf.log("StreamMarkdown stream chars=\(sample.count) secs=\(String(format: "%.1f", streamSecs)) " + perf.line("", seconds: streamSecs))
        Perf.log(String(format: "stream busyMsPerS first-quarter=%.0f last-quarter=%.0f hitchMsPerS first-quarter=%.0f last-quarter=%.0f", early.busy / max(1, early.secs), late.busy / max(1, late.secs), early.hitchMs / max(1, early.secs), late.hitchMs / max(1, late.secs)))
        Perf.log("stream busy per second at chars: " + perSecond.joined(separator: " "))
        let d = StreamMarkdownDiagnostics.self
        Perf.log("stream renderer parses=\(d.parses) built=\(d.builtBlocks) textViewUpdates=\(d.textViewUpdates) textViews=\(d.textViews)")
        Perf.log(String(format: "stream renderer msPerS offMain compile=%.1f main publish=%.1f textUpdate=%.1f sizing=%.1f", d.compileMs / streamSecs, d.publishMs / streamSecs, d.textUpdateMs / streamSecs, d.sizingMs / streamSecs))
        try? await Task.sleep(for: .seconds(3))
        Perf.log(String(format: "memory after stream footprintMB=%.0f", Perf.footprintMB()))
        perf.reset()
        let scrollBegan = Date()
        while Date().timeIntervalSince(scrollBegan) < 12 {
            try? await Task.sleep(for: .milliseconds(8))
            let t = Date().timeIntervalSince(scrollBegan)
            perf.scrollProgress = t < 8 ? t / 8 : max(0, 1 - (t - 8) / 4)
        }
        Perf.log("scroll " + perf.line("", seconds: Date().timeIntervalSince(scrollBegan)) + String(format: " scrollableHeight=%.0f", scrollable))
        Perf.log(String(format: "memory after scroll footprintMB=%.0f", Perf.footprintMB()))
        Perf.log("done")
        exit(0)
    }
}
