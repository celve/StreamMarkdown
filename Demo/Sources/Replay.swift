import Foundation
import Observation

/// How fast a recorded answer arrives.
enum Rate: Hashable, CaseIterable, Identifiable {
    case instant
    case tokens(Int)
    /// Characters every 50 ms, as LIN-2404's harness streams (`-speed`).
    case charactersPerTick(Int)

    static let allCases: [Rate] = [.tokens(20), .tokens(60), .tokens(120), .charactersPerTick(24), .instant]

    var id: Self { self }

    var label: String {
        switch self {
        case .instant: "Instant"
        case .tokens(let n): "\(n) tokens/s"
        case .charactersPerTick(let n): "\(n * 20) chars/s"
        }
    }
}

/// Replays an answer a few tokens at a time on a 50 ms tick, the way a streamed reply grows.
@MainActor @Observable
final class Replay {
    private(set) var shown = ""
    private(set) var isStreaming = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func play(_ text: String, rate: Rate) {
        task?.cancel()
        guard rate != .instant else {
            shown = text
            isStreaming = false
            return
        }
        shown = ""
        isStreaming = true
        let pieces = Self.tokens(text)
        task = Task { [weak self] in
            var next = 0, characters = 0
            let began = ContinuousClock.now
            while next < pieces.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                switch rate {
                case .tokens(let perSecond):
                    let elapsed = ContinuousClock.now - began
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    let upTo = min(pieces.count, Int(Double(perSecond) * seconds))
                    if upTo > next { self.shown += pieces[next..<upTo].joined(); next = upTo }
                case .charactersPerTick(let n):
                    characters = min(text.count, characters + n)
                    self.shown = String(text.prefix(characters))
                    if characters == text.count { next = pieces.count }
                case .instant:
                    break
                }
            }
            self?.isStreaming = false
        }
    }

    /// About four characters a token, each with the whitespace before it, as an LLM's tokens fall.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var letters = 0
        for character in text {
            if character.isWhitespace {
                if letters > 0 { tokens.append(current); current = ""; letters = 0 }
                current.append(character)
            } else {
                if letters == 4 { tokens.append(current); current = ""; letters = 0 }
                current.append(character)
                letters += 1
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
