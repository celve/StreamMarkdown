#if canImport(UIKit)
import SwiftUI

/// A Markdown answer that may still be arriving, one view per root block. Pass the whole answer so far each time it
/// grows: it is parsed off the main thread, and only a block whose source changed is drawn again. While it streams,
/// new text is released at a steady pace and fades in, unfinished syntax at its end is hidden or closed, and new blocks
/// fade in; under Reduce Motion text shows as it arrives. Links go to the environment's `openURL`;
/// `streamMarkdownStyle(_:)` sets the look.
public struct StreamMarkdownView: View {
    private let text: String
    private let isStreaming: Bool
    @State private var stream = MarkdownStream()
    @State private var clock = DisplayLinkClock()
    @State private var selection = SelectionOwner()
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - text: the answer so far.
    ///   - isStreaming: whether more is coming. A view that first appears with a finished answer lays it out at once.
    public init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        let environment = RenderEnvironment(style: style, dynamicTypeSize: dynamicTypeSize)
        BlockStack(stream: stream)
            .environment(\.streamMarkdownSelection, selection)
            .environment(\.streamMarkdownStream, stream)
            .onAppear {
                clock.stream = stream
                stream.start(text: text, environment: environment, isStreaming: isStreaming, reduceMotion: reduceMotion, clock: clock)
            }
            .onChange(of: text) { stream.receive(text) }
            .onChange(of: isStreaming) { stream.update(isStreaming: isStreaming) }
            .onChange(of: reduceMotion) { stream.update(reduceMotion: reduceMotion) }
            .onChange(of: environment) { stream.update(environment: environment) }
    }
}

/// The root blocks top to bottom, spaced by kind. It redraws only when a block is added or removed; each slot redraws
/// on its own when its block was built anew.
struct BlockStack: View {
    let stream: MarkdownStream

    var body: some View {
        if !Tuning.slots {
            let blocks = stream.blocks
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    BlockView(kind: block.kind, revision: block.revision, content: block.content)
                        .equatable()
                        .padding(.top, block.id == 0 ? 0 : StreamMarkdownStyle.default.spacing(between: blocks[block.id - 1].kind, and: block.kind) * stream.em)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.streamMarkdownEm, stream.em)
        } else {
        let slots = stream.slots
        VStack(alignment: .leading, spacing: 0) {
            ForEach(slots) { slot in
                SlotView(slot: slot, previous: slot.id > 0 ? slots[slot.id - 1] : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.streamMarkdownEm, stream.em)
        }
    }
}

struct SlotView: View {
    let slot: BlockSlot
    let previous: BlockSlot?
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em

    var body: some View {
        let block = BlockView(kind: slot.kind, revision: slot.revision, content: slot.content)
            .equatable()
            .padding(.top, previous.map { style.spacing(between: $0.kind, and: slot.kind) * em } ?? 0)
            .environment(\.streamMarkdownFadesIn, slot.fadesIn)
        // Text fades in word by word instead.
        if Tuning.blockFade, slot.fadesIn, !slot.content.isText {
            block.modifier(FadeIn())
        } else {
            block
        }
    }
}

/// One block, redrawn only when its content was built anew.
struct BlockView: View, Equatable {
    let kind: BlockKind
    let revision: UInt64
    let content: BlockContent

    nonisolated static func == (lhs: BlockView, rhs: BlockView) -> Bool {
        lhs.revision == rhs.revision && lhs.kind == rhs.kind
    }

    var body: some View {
        BlockContentView(content: content)
    }
}

/// Fades a view in over 150 ms when it appears.
struct FadeIn: ViewModifier {
    var enabled = true
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(enabled && !shown ? 0 : 1)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeOut(duration: 0.15)) { shown = true }
            }
    }
}

struct BlockContentView: View {
    let content: BlockContent
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em
    @Environment(\.streamMarkdownFadesIn) private var fadesIn
    @Environment(\.streamMarkdownStream) private var stream

    /// A code block, table or formula that arrives inside a block already shown fades in on its own.
    private var fadesNewPieces: Bool { fadesIn && stream?.animates == true }

    var body: some View {
        switch content {
        case .text(let text):
            ProseTextView(text: text)
        case .quote(let blocks):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    BlockContentView(content: block.content)
                        .modifier(FadeIn(enabled: fadesNewPieces && !block.content.isText))
                        .padding(.top, block.id == 0 ? 0 : style.spacing(between: blocks[block.id - 1].kind, and: block.kind) * em)
                }
            }
            .padding(.leading, style.quoteBarWidth + style.quoteIndent * em)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Capsule().fill(style.quoteBarColor).frame(width: style.quoteBarWidth)
            }
        case .rule:
            Rectangle()
                .fill(style.ruleColor)
                .frame(height: 1)
                .padding(.vertical, em * 0.5)
                .accessibilityHidden(true)
        case .code(let code):
            CodeBlockView(code: code)
        case .table(let table):
            TableBlockView(table: table)
        case .stack(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    BlockContentView(content: item.content)
                        .modifier(FadeIn(enabled: fadesNewPieces && !item.content.isText))
                        .padding(.top, item.gap)
                        .padding(.leading, item.indent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .source(let text):
            SourceView(text: text)
        case .math(let formulas):
            VStack(spacing: em * 0.5) {
                ForEach(formulas) { DisplayMathView(formula: $0) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Text drawn as it is, on a rounded fill.
struct SourceView: View {
    let text: RichText
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em

    var body: some View {
        ProseTextView(text: text, fades: false)
            .padding(em * 0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.sourceBackground, in: .rect(cornerRadius: em * 0.6))
    }
}

/// A display formula centred in the column, scrolling sideways when wider; VoiceOver reads its TeX.
struct DisplayMathView: View {
    let formula: DisplayFormula

    var body: some View {
        if let rendered = formula.rendered {
            let image = Image(uiImage: rendered.image)
                .renderingMode(.template)
                .foregroundStyle(Color(uiColor: formula.color))
            ViewThatFits(in: .horizontal) {
                image
                ScrollView(.horizontal) { image }
                    .scrollIndicators(.hidden)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: formula.tex))
            .accessibilityIdentifier("math")
        } else {
            SourceView(text: formula.fallback)
        }
    }
}

extension EnvironmentValues {
    @Entry var streamMarkdownEm: CGFloat = 17
    @Entry var streamMarkdownSelection: SelectionOwner?
    /// The answer's stream, which text views ask whether new text fades in.
    @Entry var streamMarkdownStream: MarkdownStream?
    /// The block arrived while the answer streamed, so its first text fades in too.
    @Entry var streamMarkdownFadesIn = false
}

extension BlockContent {
    var isText: Bool {
        if case .text = self { true } else { false }
    }
}
#endif
