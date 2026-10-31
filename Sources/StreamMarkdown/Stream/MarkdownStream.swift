import Foundation
import Observation

/// A root block of the answer as published to the views: its place, kind, source, and what it draws as.
struct MarkdownBlock: Identifiable, Equatable, Sendable {
    /// Its index among the root blocks, which an answer that only grows never changes.
    let id: Int
    let kind: BlockKind
    /// UTF-8 offsets into the answer.
    let range: Range<Int>
    let source: String
    let key: BlockKey
    /// Changes exactly when `content` was built anew.
    let revision: UInt64
    let content: BlockContent

    static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision && lhs.range == rhs.range
    }
}

/// One parse of the whole answer and the blocks built from it.
struct Compilation: Sendable {
    let blocks: [MarkdownBlock]
    let nextRevision: UInt64
    /// How many blocks were built anew rather than taken from the previous blocks.
    let built: Int
}

enum MarkdownCompiler {
    /// Parses `text` and renders its root blocks, taking the content of any block whose key is in `previous` (blocks
    /// built with the same style) instead of building it again.
    static func compile(_ text: String, style: ResolvedStyle, previous: [MarkdownBlock], nextRevision: UInt64) -> Compilation {
        var reusable = Dictionary(previous.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var revision = nextRevision
        var built = 0
        let blocks = BlockParser.parse(text).map { parsed -> MarkdownBlock in
            let key = parsed.key
            let content: BlockContent
            let blockRevision: UInt64
            if let old = reusable[key] {
                (content, blockRevision) = (old.content, old.revision)
            } else {
                content = BlockRenderer.render(parsed.markup, kind: parsed.kind, source: parsed.source, style: style)
                blockRevision = revision
                revision += 1
                built += 1
            }
            let block = MarkdownBlock(id: parsed.index, kind: parsed.kind, range: parsed.range, source: parsed.source, key: key, revision: blockRevision, content: content)
            reusable[key] = block
            return block
        }
        return Compilation(blocks: blocks, nextRevision: revision, built: built)
    }
}

/// The streaming parse coordinator: takes the growing answer, parses it off the main thread with at most one parse in
/// flight, and publishes its root blocks. A text that arrives during a parse waits, and only the latest is parsed next.
@MainActor @Observable
final class MarkdownStream {
    typealias Compile = @Sendable (String, ResolvedStyle, [MarkdownBlock], UInt64) -> Compilation

    private(set) var blocks: [MarkdownBlock] = []
    @ObservationIgnored private(set) var text = ""
    @ObservationIgnored private(set) var style: ResolvedStyle
    @ObservationIgnored private(set) var builtCount = 0
    @ObservationIgnored private var blocksStyle: ResolvedStyle?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var isStale = false
    @ObservationIgnored private var nextRevision: UInt64 = 1
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let compile: Compile

    /// Cheap without an environment, since SwiftUI makes one for every `@State` initial value it then throws away.
    init(environment: RenderEnvironment? = nil, compile: @escaping Compile = MarkdownCompiler.compile) {
        style = environment.map(ResolvedStyle.init) ?? .standard
        self.compile = compile
    }

    /// Takes the answer and environment a view first appears with; `now` parses on the main thread when no parse is running.
    func start(text: String, environment: RenderEnvironment, now: Bool) {
        guard text != self.text || environment != style.environment || blocksStyle == nil else { return }
        self.text = text
        if environment != style.environment { style = ResolvedStyle(environment) }
        if now, job == nil { renderNow() } else { schedule() }
    }

    func update(text: String) {
        guard text != self.text else { return }
        self.text = text
        schedule()
    }

    func update(environment: RenderEnvironment) {
        guard environment != style.environment else { return }
        style = ResolvedStyle(environment)
        schedule()
    }

    /// Parses on the main thread now, for an answer shown whole, so its first layout already has its height.
    func renderNow() {
        guard job == nil else { return }
        apply(compile(text, style, reusableBlocks, nextRevision), style: style)
    }

    /// Returns once no parse is running or waiting.
    func settled() async {
        guard job != nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private var reusableBlocks: [MarkdownBlock] { blocksStyle === style ? blocks : [] }

    private func schedule() {
        guard job == nil else {
            isStale = true
            return
        }
        let (text, style, previous, revision, compile) = (text, style, reusableBlocks, nextRevision, compile)
        job = Task.detached(priority: .userInitiated) { [weak self] in
            let compilation = compile(text, style, previous, revision)
            await self?.finish(compilation, style: style)
        }
    }

    private func finish(_ compilation: Compilation, style: ResolvedStyle) {
        job = nil
        apply(compilation, style: style)
        if isStale {
            isStale = false
            schedule()
        } else {
            let waiters = waiters
            self.waiters = []
            waiters.forEach { $0.resume() }
        }
    }

    private func apply(_ compilation: Compilation, style: ResolvedStyle) {
        nextRevision = compilation.nextRevision
        builtCount += compilation.built
        StreamMarkdownDiagnostics.parses += 1
        StreamMarkdownDiagnostics.builtBlocks += compilation.built
        blocksStyle = style
        if compilation.blocks != blocks { blocks = compilation.blocks }
    }
}

/// Counters a demo or a performance run reads.
@_spi(Diagnostics) @MainActor
public enum StreamMarkdownDiagnostics {
    /// Parses applied, across every view.
    public static var parses = 0
    /// Blocks rendered anew (an attributed string built), across every view.
    public static var builtBlocks = 0
    /// Times a block's text view was given a new attributed string, its first included.
    public static var textViewUpdates = 0
    public static var textViews = 0

    public static func reset() {
        parses = 0
        builtBlocks = 0
        textViewUpdates = 0
        textViews = 0
    }
}
