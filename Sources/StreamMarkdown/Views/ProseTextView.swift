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
        let view = UITextView.answerText(delegate: context.coordinator)
        context.coordinator.baseTraits = view.accessibilityTraits
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
        let began = ContinuousClock.now
        view.attributedText = text.string
        StreamMarkdownDiagnostics.textUpdateMs += (ContinuousClock.now - began).milliseconds
        view.accessibilityTraits = text.headingLevel == nil ? coordinator.baseTraits : coordinator.baseTraits.union(.header)
        StreamMarkdownDiagnostics.textViewUpdates += 1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        if let size = context.coordinator.sizes[width] { return size }
        let began = ContinuousClock.now
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        StreamMarkdownDiagnostics.sizingMs += (ContinuousClock.now - began).milliseconds
        let size = CGSize(width: proposal.width ?? fitted.width.rounded(.up), height: fitted.height.rounded(.up))
        context.coordinator.sizes[width] = size
        return size
    }

    final class Coordinator: TextViewActions {
        var shown: RichText?
        var sizes: [CGFloat: CGSize] = [:]
        var linkColor: UIColor?
        var baseTraits: UIAccessibilityTraits = []
    }
}

extension UITextView {
    /// A selectable, non-scrolling TextKit 2 text view with no insets, as every text of an answer is drawn in.
    static func answerText(delegate: UITextViewDelegate) -> UITextView {
        // The designated initializer, so the subclass's stored properties are set up; a nil container means TextKit 2.
        let view = ProseUITextView(frame: .zero, textContainer: nil)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.delegate = delegate
        StreamMarkdownDiagnostics.textViews += 1
        StreamMarkdownDiagnostics.liveTextViews.add(view)
        return view
    }
}

/// Sends a text view's links to `openURL`, and hands its selection to the answer's selection owner.
@MainActor
class TextViewActions: NSObject, UITextViewDelegate {
    var openURL: OpenURLAction?
    weak var selection: SelectionOwner?

    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
        return UIAction { _ in openURL(url) }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if textView.selectedRange.length > 0 { selection?.claim(textView) }
    }
}

/// A block's text view, read aloud with each formula as its TeX where UIKit would read the attachment character. A
/// display formula's attachment draws nothing, and the view lays a sideways-scrolling view of the formula over it:
/// UITextView never asks a TextKit 2 attachment for its view.
final class ProseUITextView: UITextView {
    private var formulas: [(attachment: MathAttachment, location: Int, view: UIScrollView)] = []

    override var attributedText: NSAttributedString! {
        didSet { placeFormulaViews() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutFormulaViews()
    }

    private func placeFormulaViews() {
        var found: [(MathAttachment, Int)] = []
        let text = attributedText ?? NSAttributedString()
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let math = value as? MathAttachment, math.isDisplay { found.append((math, range.location)) }
        }
        guard found.map({ ObjectIdentifier($0.0) }) != formulas.map({ ObjectIdentifier($0.attachment) }) || found.map(\.1) != formulas.map(\.location) else { return }
        formulas.forEach { $0.view.removeFromSuperview() }
        formulas = found.compactMap { attachment, location in
            guard let image = attachment.rendered?.image else { return nil }
            let imageView = UIImageView(image: image)
            imageView.tintColor = attachment.color
            imageView.frame = CGRect(origin: .zero, size: image.size)
            let scroll = UIScrollView()
            scroll.addSubview(imageView)
            scroll.contentSize = image.size
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.isAccessibilityElement = true
            scroll.accessibilityLabel = attachment.tex
            scroll.accessibilityIdentifier = "math"
            addSubview(scroll)
            return (attachment, location, scroll)
        }
        setNeedsLayout()
    }

    private func layoutFormulaViews() {
        guard !formulas.isEmpty, let layout = textLayoutManager, let content = layout.textContentManager else { return }
        for formula in formulas {
            guard let size = formula.attachment.rendered?.size, let baseline = formula.attachment.rendered?.baseline,
                  let start = content.location(content.documentRange.location, offsetBy: formula.location),
                  let end = content.location(start, offsetBy: 1), let range = NSTextRange(location: start, end: end) else { continue }
            layout.ensureLayout(for: range)
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, baselinePosition, _ in
                let top = segment.minY + baselinePosition - (size.height - baseline)
                formula.view.frame = CGRect(x: segment.minX + textContainerInset.left, y: top + textContainerInset.top, width: segment.width, height: size.height)
                return false
            }
        }
    }
    override var accessibilityValue: String? {
        get {
            let text = attributedText ?? NSAttributedString()
            var spoken = ""
            var hasMath = false
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if let math = value as? MathAttachment {
                    spoken += math.tex
                    hasMath = true
                } else {
                    spoken += (text.string as NSString).substring(with: range)
                }
            }
            return hasMath ? spoken : super.accessibilityValue
        }
        set { super.accessibilityValue = newValue }
    }
}

@_spi(Diagnostics) extension StreamMarkdownDiagnostics {
    /// Text views holding a selection now, even one UIKit no longer draws.
    public static var selectedTextViews: Int { liveTextViews.allObjects.count { $0.selectedRange.length > 0 } }
    static let liveTextViews = NSHashTable<UITextView>.weakObjects()
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
