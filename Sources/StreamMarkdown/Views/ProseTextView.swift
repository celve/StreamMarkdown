#if canImport(UIKit)
import SwiftUI
import UIKit

/// A block's text in a non-scrolling TextKit 2 text view: selectable, sized to its width, links through `openURL`.
struct ProseTextView: UIViewRepresentable {
    let text: RichText
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownSelection) private var selection

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        context.coordinator.baseTraits = view.accessibilityTraits
        StreamMarkdownDiagnostics.textViews += 1
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.openURL = context.environment.openURL
        coordinator.selection = selection
        let linkColor = UIColor(style.linkColor)
        if coordinator.linkColor != linkColor {
            coordinator.linkColor = linkColor
            view.linkTextAttributes = [.foregroundColor: linkColor]
        }
        guard coordinator.shown !== text else { return }
        coordinator.shown = text
        coordinator.sizes.removeAll()
        view.attributedText = text.string
        view.accessibilityTraits = text.headingLevel == nil ? coordinator.baseTraits : coordinator.baseTraits.union(.header)
        StreamMarkdownDiagnostics.textViewUpdates += 1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        if let size = context.coordinator.sizes[width] { return size }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: proposal.width ?? fitted.width.rounded(.up), height: fitted.height.rounded(.up))
        context.coordinator.sizes[width] = size
        return size
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var shown: RichText?
        var sizes: [CGFloat: CGSize] = [:]
        var openURL: OpenURLAction?
        weak var selection: SelectionOwner?
        var linkColor: UIColor?
        var baseTraits: UIAccessibilityTraits = []

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
            return UIAction { _ in openURL(url) }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 { selection?.claim(textView) }
        }
    }
}

/// Keeps a selection in at most one block of an answer: selecting in one clears the last.
@MainActor
final class SelectionOwner {
    private weak var holder: UITextView?

    func claim(_ view: UITextView) {
        if let holder, holder !== view { holder.selectedTextRange = nil }
        holder = view
    }
}
#endif
