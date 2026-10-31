#if canImport(UIKit)
import SwiftUI

/// A Markdown answer that may still be arriving, one view per root block. Pass the whole answer so far each time it
/// grows: it is parsed off the main thread, and only a block whose source changed is drawn again. Links go to the
/// environment's `openURL`; `streamMarkdownStyle(_:)` sets the look.
public struct StreamMarkdownView: View {
    private let text: String
    private let isStreaming: Bool
    @State private var stream = MarkdownStream()
    @State private var selection = SelectionOwner()
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - text: the answer so far.
    ///   - isStreaming: whether more is coming. A view that first appears with a finished answer lays it out at once.
    public init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        let environment = RenderEnvironment(style: style, dynamicTypeSize: dynamicTypeSize)
        BlockStack(blocks: stream.blocks, em: stream.style.em)
            .environment(\.streamMarkdownSelection, selection)
            .onAppear { stream.start(text: text, environment: environment, now: !isStreaming) }
            .onChange(of: text) { stream.update(text: text) }
            .onChange(of: environment) { stream.update(environment: environment) }
    }
}

/// The root blocks top to bottom, spaced by kind.
struct BlockStack: View {
    let blocks: [MarkdownBlock]
    let em: CGFloat
    @Environment(\.streamMarkdownStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                BlockView(kind: block.kind, revision: block.revision, content: block.content)
                    .equatable()
                    .padding(.top, block.id == 0 ? 0 : style.spacing(between: blocks[block.id - 1].kind, and: block.kind) * em)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.streamMarkdownEm, em)
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

struct BlockContentView: View {
    let content: BlockContent
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em

    var body: some View {
        switch content {
        case .text(let text):
            ProseTextView(text: text)
        case .quote(let blocks):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    BlockContentView(content: block.content)
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
        case .source(let text):
            ProseTextView(text: text)
                .padding(em * 0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.sourceBackground, in: .rect(cornerRadius: em * 0.6))
        }
    }
}

extension EnvironmentValues {
    @Entry var streamMarkdownEm: CGFloat = 17
    @Entry var streamMarkdownSelection: SelectionOwner?
}
#endif
