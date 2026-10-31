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

/// What a parse needs to know besides the text and style.
struct CompileOptions: Hashable, Sendable {
    /// More of the answer is coming, so its last block may be unfinished.
    var isStreaming = false
    /// Code stays plain, for a parse on the main thread; a parse off it highlights.
    var defersHighlighting = false
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
    static func compile(_ text: String, style: ResolvedStyle, previous: [MarkdownBlock], nextRevision: UInt64,
                        options: CompileOptions = CompileOptions()) -> Compilation {
        var reusable = Dictionary(previous.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var revision = nextRevision
        var built = 0
        let parsedBlocks = BlockParser.parse(text, repairingTail: options.isStreaming)
        let blocks = parsedBlocks.map { parsed -> MarkdownBlock in
            let context = RenderContext(isOpenTail: options.isStreaming && parsed.index == parsedBlocks.count - 1, defersHighlighting: options.defersHighlighting)
            let key = parsed.key(context)
            let content: BlockContent
            let blockRevision: UInt64
            if let old = reusable[key] {
                (content, blockRevision) = (old.content, old.revision)
            } else {
                let cells = parsed.index < previous.count ? previous[parsed.index].content.tableCells : [:]
                content = BlockRenderer.render(parsed.markup, kind: parsed.kind, source: parsed.source, style: style, math: parsed.math,
                                               context: context, cells: cells)
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
/// With a frame clock attached, a streaming answer goes through a ``RevealPacer`` on the clock's tick, and each parse's
/// blocks are published at the start of the next frame.
@MainActor @Observable
final class MarkdownStream {
    typealias Compile = @Sendable (String, ResolvedStyle, [MarkdownBlock], UInt64, CompileOptions) -> Compilation

    private(set) var blocks: [MarkdownBlock] = []
    /// One per root block, in order. The array changes only when a block is added or removed, and a slot only when its
    /// block was built anew, so an update redraws the slot that changed and nothing else.
    private(set) var slots: [BlockSlot] = []
    /// The published blocks' em, in points, which spaces them.
    private(set) var em: CGFloat = 17
    @ObservationIgnored private(set) var text = ""
    @ObservationIgnored private(set) var style: ResolvedStyle
    @ObservationIgnored private(set) var isStreaming = false
    /// Whether new text is paced and fades in: streaming, and Reduce Motion is off.
    @ObservationIgnored private(set) var animates = false
    @ObservationIgnored private(set) var builtCount = 0
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var pacer = RevealPacer()
    /// UTF-8 length of the text shown at once when the view appeared: blocks starting before it do not fade in.
    @ObservationIgnored private var shownAtOnce = 0
    @ObservationIgnored private weak var clock: (any FrameClock)?
    @ObservationIgnored private var pending: (compilation: Compilation, style: ResolvedStyle)?
    /// The last parse's blocks, published or pending, which the next parse builds on.
    @ObservationIgnored private var latest: (blocks: [MarkdownBlock], style: ResolvedStyle)?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var isStale = false
    @ObservationIgnored private var nextRevision: UInt64 = 1
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let compile: Compile

    /// Cheap without an environment, since SwiftUI makes one for every `@State` initial value it then throws away.
    init(environment: RenderEnvironment? = nil, compile: @escaping Compile = { MarkdownCompiler.compile($0, style: $1, previous: $2, nextRevision: $3, options: $4) }) {
        style = environment.map(ResolvedStyle.init) ?? .standard
        self.compile = compile
    }

    /// Takes the answer and environment a view first appears with, all of it shown at once. A finished answer is
    /// parsed on the main thread when no parse is running, so its first layout has its height.
    func start(text: String, environment: RenderEnvironment, isStreaming: Bool, reduceMotion: Bool = false, clock: (any FrameClock)? = nil) {
        guard text != self.text || environment != style.environment || isStreaming != self.isStreaming || latest == nil else { return }
        self.clock = clock
        self.reduceMotion = reduceMotion
        pacer = RevealPacer(text)
        shownAtOnce = text.utf8.count
        self.text = text
        self.isStreaming = isStreaming
        animates = isStreaming && !reduceMotion
        if environment != style.environment { style = ResolvedStyle(environment) }
        if !isStreaming, job == nil { renderNow() } else { schedule() }
    }

    /// Takes the whole answer so far: parsed now, or released by the pacer on the clock's tick while it streams.
    func receive(_ text: String) {
        pacer.receive(text)
        guard isStreaming, let clock else { return reveal() }
        if pacer.backlog > 0 { clock.requestFrames() } else { update(text: pacer.text) }
    }

    func update(text: String) {
        guard text != self.text else { return }
        self.text = text
        schedule()
    }

    /// An answer that stops streaming shows the rest of its text at once and closes its last block, which highlights
    /// its code.
    func update(isStreaming: Bool) {
        guard isStreaming != self.isStreaming else { return }
        self.isStreaming = isStreaming
        animates = isStreaming && !reduceMotion
        if !isStreaming {
            pacer.revealAll()
            text = pacer.text
        }
        schedule()
    }

    func update(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        animates = isStreaming && !reduceMotion
    }

    func update(environment: RenderEnvironment) {
        guard environment != style.environment else { return }
        style = ResolvedStyle(environment)
        schedule()
    }

    /// Called by the clock at the start of each frame: publishes a finished parse, then takes the pacer's tick.
    /// Returns whether more frames are wanted.
    func frame(at now: Double) -> Bool {
        if let pending {
            self.pending = nil
            apply(pending.compilation, style: pending.style)
            resumeWaitersIfSettled()
        }
        if pacer.advance(to: now, paced: animates) { update(text: pacer.revealed) }
        return pacer.backlog > 0 || job != nil || pending != nil
    }

    /// Parses on the main thread now, for an answer shown whole, so its first layout already has its height. Code is
    /// plain in that parse, and highlighted by the parse off the main thread that follows.
    func renderNow() {
        guard job == nil else { return }
        let compilation = compile(text, style, reusableBlocks, nextRevision, CompileOptions(isStreaming: isStreaming, defersHighlighting: true))
        latest = (compilation.blocks, style)
        nextRevision = compilation.nextRevision
        pending = nil
        apply(compilation, style: style)
        schedule()
    }

    /// Returns once no parse is running, waiting or unpublished.
    func settled() async {
        guard job != nil || pending != nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private var reusableBlocks: [MarkdownBlock] { latest.flatMap { $0.style === style ? $0.blocks : nil } ?? [] }

    private func reveal() {
        pacer.revealAll()
        update(text: pacer.text)
    }

    private func schedule() {
        guard job == nil else {
            isStale = true
            return
        }
        let (text, style, previous, revision, compile) = (text, style, reusableBlocks, nextRevision, compile)
        let options = CompileOptions(isStreaming: isStreaming)
        job = Task.detached(priority: .userInitiated) { [weak self] in
            let began = ContinuousClock.now
            let compilation = compile(text, style, previous, revision, options)
            let took = ContinuousClock.now - began
            await self?.finish(compilation, style: style, took: took)
        }
    }

    private func finish(_ compilation: Compilation, style: ResolvedStyle, took: Duration) {
        job = nil
        StreamMarkdownDiagnostics.compileMs += took.milliseconds
        latest = (compilation.blocks, style)
        nextRevision = compilation.nextRevision
        if isStreaming, let clock {
            pending = (compilation, style)
            clock.requestFrames()
        } else {
            pending = nil
            apply(compilation, style: style)
        }
        if isStale {
            isStale = false
            schedule()
        }
        resumeWaitersIfSettled()
    }

    private func resumeWaitersIfSettled() {
        guard job == nil, pending == nil else { return }
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }

    private func apply(_ compilation: Compilation, style: ResolvedStyle) {
        let began = ContinuousClock.now
        defer { StreamMarkdownDiagnostics.publishMs += (ContinuousClock.now - began).milliseconds }
        builtCount += compilation.built
        StreamMarkdownDiagnostics.parses += 1
        StreamMarkdownDiagnostics.builtBlocks += compilation.built
        if style.em != em { em = style.em }
        guard compilation.blocks != blocks else { return }
        blocks = compilation.blocks
        var added: [BlockSlot] = []
        for block in compilation.blocks {
            if block.id < slots.count {
                slots[block.id].show(block)
            } else {
                added.append(BlockSlot(block, fadesIn: animates && block.range.lowerBound >= shownAtOnce))
            }
        }
        if !added.isEmpty || slots.count > compilation.blocks.count { slots = slots.prefix(compilation.blocks.count) + added }
    }
}

/// A root block's place in the view: what it draws, and whether it fades in, having arrived while the answer streamed.
@MainActor @Observable
final class BlockSlot: Identifiable {
    let id: Int
    private(set) var kind: BlockKind
    private(set) var revision: UInt64
    private(set) var content: BlockContent
    let fadesIn: Bool

    init(_ block: MarkdownBlock, fadesIn: Bool) {
        id = block.id
        kind = block.kind
        revision = block.revision
        content = block.content
        self.fadesIn = fadesIn
    }

    func show(_ block: MarkdownBlock) {
        if block.kind != kind { kind = block.kind }
        if block.revision != revision {
            revision = block.revision
            content = block.content
        }
    }
}

/// Calls ``MarkdownStream/frame(at:)`` at the start of each frame once asked, until it returns false.
@MainActor
protocol FrameClock: AnyObject {
    func requestFrames()
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
    /// Time spent in background parse jobs (parse and build), and on the main thread publishing their blocks, setting
    /// text views' strings, and laying text out to size a view.
    public static var compileMs = 0.0, publishMs = 0.0, textUpdateMs = 0.0, sizingMs = 0.0

    public static func reset() {
        parses = 0
        builtBlocks = 0
        textViewUpdates = 0
        textViews = 0
        compileMs = 0
        publishMs = 0
        textUpdateMs = 0
        sizingMs = 0
    }
}

extension Duration {
    var milliseconds: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}
