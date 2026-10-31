import Foundation

/// A recorded answer from the app's Answers folder.
struct Answer: Identifiable, Hashable {
    let id: String
    let title: String
    let text: String

    static let all: [Answer] = {
        let titles = [
            ("paper-summary", "Paper summary"),
            ("follow-up", "Follow-up work"),
            ("showcase", "Every prose block"),
            ("lora", "LoRA: math, table, code"),
        ]
        let answers = titles.map { id, title in Answer(id: id, title: title, text: load(id)) }
        return answers + [Answer(id: "long", title: "Long answer (10k)", text: longSample)]
    }()

    /// LIN-2404's stress answer ten times over, built exactly as its harness builds `longSample`, so runs compare.
    static var longSample: String {
        let sample = load("lora")
        return (1...10).map { "## Part \($0)\n\n" + sample.split(separator: "\n", maxSplits: 1)[1] }.joined(separator: "\n\n")
    }

    static func named(_ id: String) -> Answer? { all.first { $0.id == id } }

    private static func load(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Answers"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Missing answer \(name).md" }
        return text
    }
}
