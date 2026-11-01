#if canImport(UIKit)
import SwiftUI
import UIKit

/// A code block: its language and a copy button over the code, whose long lines scroll sideways instead of wrapping.
struct CodeBlockView: View {
    let code: CodeContent
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em
    @Environment(\.displayScale) private var displayScale
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: em * 0.5) {
                if let language = code.language {
                    Text(language).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code.code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .padding(.vertical, em * 0.35)
                        .padding(.leading, em * 0.5)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Copied" : "Copy code")
            }
            .font(.caption)
            .foregroundStyle(style.secondaryTextColor)
            .padding(.horizontal, em * 0.75)
            .padding(.top, em * 0.15)
            ScrollView(.horizontal) {
                ProseTextView(text: code.text, fades: false)
                    .padding(.horizontal, em * 0.75)
                    .padding(.bottom, em * 0.75)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sourceBox(style: style, em: em, displayScale: displayScale)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

extension View {
    /// The rounded fill and hairline that code blocks and HTML sit in.
    func sourceBox(style: StreamMarkdownStyle, em: CGFloat, displayScale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.sourceCornerRadius * em)
        return background(style.sourceBackground, in: shape)
            .overlay { shape.strokeBorder(style.sourceBorderColor, lineWidth: 1 / max(displayScale, 1)) }
    }
}
#endif
