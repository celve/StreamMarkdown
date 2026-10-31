@_spi(Diagnostics) import StreamMarkdown
import SwiftUI

/// Replays recorded answers through StreamMarkdownView. Launch arguments: `-answer <id>` opens one, `-rate <tokens/s>`
/// sets the pace (0 for instant), `-hud 0` hides the meter; `-perf 1` runs LIN-2404's measurement instead (see PerfRun).
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            if UserDefaults.standard.bool(forKey: "perf") || UserDefaults.standard.bool(forKey: "stream") {
                PerfRun()
            } else {
                AnswerList()
            }
        }
    }
}

struct AnswerList: View {
    @State private var path: [Answer] = Answer.named(UserDefaults.standard.string(forKey: "answer") ?? "").map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List(Answer.all) { answer in
                NavigationLink(value: answer) {
                    VStack(alignment: .leading) {
                        Text(answer.title)
                        Text("\(answer.text.count) characters").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("StreamMarkdown")
            .navigationDestination(for: Answer.self) { ReplayScreen(answer: $0) }
        }
    }
}

struct ReplayScreen: View {
    let answer: Answer
    @State private var replay = Replay()
    @State private var rate: Rate = {
        guard UserDefaults.standard.object(forKey: "rate") != nil else { return .tokens(60) }
        let n = UserDefaults.standard.integer(forKey: "rate")
        return n > 0 ? .tokens(n) : .instant
    }()
    @State private var opened: URL?
    @State private var copied: String?
    private let showsMeter = UserDefaults.standard.object(forKey: "hud") == nil || UserDefaults.standard.bool(forKey: "hud")

    var body: some View {
        ScrollView {
            StreamMarkdownView(replay.shown, isStreaming: replay.isStreaming)
                .padding()
        }
        .safeAreaInset(edge: .top) { if showsMeter { Meter() } }
        .overlay(alignment: .bottom) {
            if let opened {
                Text("openURL: \(opened.absoluteString)")
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
                    .accessibilityIdentifier("opened-url")
            } else if let copied {
                Text("copied: \(copied.prefix { $0 != "\n" })")
                    .font(.footnote)
                    .lineLimit(1)
                    .padding(10)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
                    .accessibilityIdentifier("copied")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            copied = UIPasteboard.general.string
        }
        .environment(\.openURL, OpenURLAction { url in
            opened = url
            return .handled
        })
        .navigationTitle(answer.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Rate", selection: $rate) {
                        ForEach(Rate.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(rate.label, systemImage: "speedometer")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Replay", systemImage: "arrow.counterclockwise") { start() }
            }
        }
        .onChange(of: rate) { start() }
        .task { start() }
    }

    private func start() {
        opened = nil
        copied = nil
        StreamMarkdownDiagnostics.reset()
        replay.play(answer.text, rate: rate)
    }
}

/// Frames, main-thread busy time and the renderer's own counters over the last second.
struct Meter: View {
    @State private var reading = "…"

    var body: some View {
        Text(reading)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.bar)
            .accessibilityIdentifier("meter")
            .task {
                let perf = Perf.shared
                perf.start()
                while !Task.isCancelled {
                    perf.reset()
                    try? await Task.sleep(for: .seconds(1))
                    reading = String(format: "%d fps · %.0f ms/s main · %d parses · %d built · %d text updates · %d views · %d selected",
                                     perf.frames, perf.busyMs, StreamMarkdownDiagnostics.parses, StreamMarkdownDiagnostics.builtBlocks,
                                     StreamMarkdownDiagnostics.textViewUpdates, StreamMarkdownDiagnostics.textViews,
                                     StreamMarkdownDiagnostics.selectedTextViews)
                }
            }
    }
}
