#if canImport(UIKit)
import SwiftUI
import UIKit

/// A block's text in a non-scrolling TextKit 2 text view: selectable, sized to its width, links through `openURL`.
/// While the answer streams, new characters fade in, unless `fades` is off.
struct ProseTextView: UIViewRepresentable {
    let text: RichText
    var fades = true
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownSelection) private var selection
    @Environment(\.streamMarkdownStream) private var stream
    @Environment(\.streamMarkdownFadesFirstText) private var fadesFirstText

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProseUITextView {
        let view = UITextView.answerText(delegate: context.coordinator)
        context.coordinator.baseTraits = view.accessibilityTraits
        return view
    }

    func updateUIView(_ view: ProseUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.openURL = context.environment.openURL
        coordinator.selection = selection
        let linkColor = UIColor(style.linkColor)
        if coordinator.linkColor != linkColor {
            coordinator.linkColor = linkColor
            view.linkTextAttributes = [.foregroundColor: linkColor]
        }
        guard coordinator.shown !== text else { return }
        let previous = coordinator.shown
        coordinator.shown = text
        coordinator.sizes.removeAll()
        let began = ContinuousClock.now
        let kept = view.show(text.string, replacing: previous?.string)
        StreamMarkdownDiagnostics.textUpdateMs += (ContinuousClock.now - began).milliseconds
        if fades, stream?.animates == true, previous != nil || fadesFirstText, kept < text.string.length {
            view.fadeIn(NSRange(location: kept, length: text.string.length - kept))
        }
        view.accessibilityTraits = text.headingLevel == nil ? coordinator.baseTraits : coordinator.baseTraits.union(.header)
        StreamMarkdownDiagnostics.textViewUpdates += 1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProseUITextView, context: Context) -> CGSize? {
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
    static func answerText(delegate: UITextViewDelegate) -> ProseUITextView {
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
    static let fadeDuration = 0.3

    private var formulas: [(attachment: MathAttachment, location: Int, view: UIScrollView)] = []
    /// Ranges fading in, oldest first, each with when it started and its part of the mask.
    private var fades: [(range: NSRange, start: CFTimeInterval, part: CAShapeLayer)] = []
    private let fadeMask = CALayer()
    /// The mask's part over the text before the oldest fading range, which shows as it is.
    private let settledPart = CAShapeLayer()

    override var attributedText: NSAttributedString! {
        didSet { placeFormulaViews() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutFormulaViews()
        if !fades.isEmpty { layoutFadeMask() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishFades() }
    }

    /// Shows `text`. When it begins as `previous` did, only what follows their longest common start, attributes
    /// included, is replaced in the text storage, so TextKit lays out again only the paragraphs that changed.
    /// Returns how many characters of `previous` start `text` as well, which are not new.
    func show(_ text: NSAttributedString, replacing previous: NSAttributedString?) -> Int {
        guard let previous, previous.length == textStorage.length else {
            attributedText = text
            return 0
        }
        let common = (previous.string as NSString).commonPrefix(with: text.string, options: .literal).utf16.count
        let same = Self.sameAttributes(previous, text, upTo: common)
        guard same > 0 else {
            attributedText = text
            return common
        }
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: same, length: previous.length - same),
                                      with: text.attributedSubstring(from: NSRange(location: same, length: text.length - same)))
        textStorage.endEditing()
        placeFormulaViews()
        if !fades.isEmpty { layoutFadeMask() }
        return common
    }

    /// How far from the start two strings carry equal attributes, up to `end`.
    private static func sameAttributes(_ a: NSAttributedString, _ b: NSAttributedString, upTo end: Int) -> Int {
        var location = 0
        while location < end {
            var first = NSRange(), second = NSRange()
            let left = a.attributes(at: location, effectiveRange: &first)
            let right = b.attributes(at: location, effectiveRange: &second)
            guard NSDictionary(dictionary: left).isEqual(to: right) else { break }
            location = min(first.upperBound, second.upperBound, end)
        }
        return location
    }

    // MARK: Fading in

    /// Fades `range` in over ``fadeDuration``. The text draws at full strength under a mask: opaque over the settled
    /// text, and one part per fading range whose opacity Core Animation ramps, so no frame of a fade redraws text or
    /// runs on the main thread. Ramps are capped at 60 Hz, where a ProMotion screen would run them at 120.
    func fadeIn(_ range: NSRange) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Older fades give way where the new one starts, so no text is under two parts.
        fades = fades.compactMap { fade in
            let end = min(fade.range.upperBound, range.location)
            guard end > fade.range.location else {
                fade.part.removeFromSuperlayer()
                return nil
            }
            return (NSRange(location: fade.range.location, length: end - fade.range.location), fade.start, fade.part)
        }
        let part = CAShapeLayer()
        part.fillColor = UIColor.black.cgColor
        let ramp = CABasicAnimation(keyPath: "opacity")
        ramp.fromValue = 0
        ramp.toValue = 1
        ramp.duration = Self.fadeDuration
        ramp.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ramp.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        part.add(ramp, forKey: "fade")
        if fadeMask.sublayers == nil {
            settledPart.fillColor = UIColor.black.cgColor
            fadeMask.addSublayer(settledPart)
        }
        fadeMask.addSublayer(part)
        fades.append((range, CACurrentMediaTime(), part))
        layer.mask = fadeMask
        layoutFadeMask()
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration + 0.05) { [weak self] in self?.layoutFadeMask() }
    }

    /// Fits the mask to where the fading ranges are laid out now, since a word that grows can wrap to the next line,
    /// and drops the parts whose ramp has finished; the mask goes once none is left.
    private func layoutFadeMask() {
        let now = CACurrentMediaTime()
        fades.removeAll { fade in
            guard now - fade.start >= Self.fadeDuration else { return false }
            fade.part.removeFromSuperlayer()
            return true
        }
        guard !fades.isEmpty, let layout = textLayoutManager, let content = layout.textContentManager else { return finishFades() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = layer.bounds
        let inset = textContainerInset
        let length = textStorage.length
        var oldest: CGRect?
        for fade in fades {
            let path = CGMutablePath()
            let range = NSIntersectionRange(fade.range, NSRange(location: 0, length: length))
            if range.length > 0, let textRange = NSTextRange(range, in: content) {
                layout.ensureLayout(for: textRange)
                layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, segment, _, _ in
                    let line = segment.offsetBy(dx: inset.left, dy: inset.top)
                    if oldest == nil { oldest = line }
                    // Glyphs reach a little past their line's box.
                    path.addRect(line.insetBy(dx: -2, dy: -2))
                    return true
                }
            }
            fade.part.path = path
        }
        // Everything above the oldest fading line, and that line up to where the fading starts.
        let far: CGFloat = 100_000
        let settled = CGMutablePath()
        let start = oldest ?? CGRect(x: far, y: far, width: 0, height: 0)
        settled.addRect(CGRect(x: -far, y: -far, width: 2 * far, height: far + start.minY))
        settled.addRect(CGRect(x: -far, y: start.minY, width: far + start.minX, height: start.height))
        settledPart.path = settled
        CATransaction.commit()
    }

    /// Shows everything at full strength now, as when the stream ends or Reduce Motion turns on.
    func finishFades() {
        fades.forEach { $0.part.removeFromSuperlayer() }
        fades = []
        if layer.mask === fadeMask { layer.mask = nil }
    }

    func placeFormulaViews() {
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
        get { attributedText?.spokenMath ?? super.accessibilityValue }
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
extension NSAttributedString {
    /// The text with each formula read as its TeX, or nil when it holds none.
    var spokenMath: String? {
        var spoken = ""
        var hasMath = false
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            if let math = value as? MathAttachment {
                spoken += math.tex
                hasMath = true
            } else {
                spoken += (string as NSString).substring(with: range)
            }
        }
        return hasMath ? spoken : nil
    }

    /// The link under a point of the text laid out at `size`, as a label lays it out, if the point is on its text.
    func link(at point: CGPoint, within size: CGSize) -> URL? {
        let storage = NSTextStorage(attributedString: self)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: size)
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -6, dy: -6).contains(point) else { return nil }
        return attribute(.link, at: layout.characterIndexForGlyph(at: glyph), effectiveRange: nil) as? URL
    }
}
#endif

#if canImport(UIKit)
extension NSTextRange {
    /// A range of UTF-16 offsets in a content manager's document.
    convenience init?(_ range: NSRange, in content: NSTextContentManager) {
        guard let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        self.init(location: start, end: end)
    }
}
#endif

#if DEBUG && canImport(UIKit)
extension ProseUITextView {
    /// Characters of the shown text that the fade mask leaves hidden: neither under the settled part nor under a
    /// fading part. Empty when nothing is fading.
    func hiddenByFadeMask() -> [Int] {
        guard layer.mask === fadeMask, let layout = textLayoutManager, let content = layout.textContentManager else { return [] }
        let parts = [settledPart] + fades.map(\.part)
        return (0..<textStorage.length).filter { index in
            guard let range = NSTextRange(NSRange(location: index, length: 1), in: content) else { return false }
            var center: CGPoint?
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
                center = CGPoint(x: segment.midX + textContainerInset.left, y: segment.midY + textContainerInset.top)
                return false
            }
            guard let center else { return false }
            return !parts.contains { $0.path?.contains(center) == true }
        }
    }
}

@_spi(Diagnostics) extension StreamMarkdownDiagnostics {
    /// Drives a block's text view through what a stream does to it and names each step after which shown text sits
    /// outside the fade mask: text shown without fading while an earlier fade runs, and right-to-left text.
    public static func fadeMaskProblems() -> [String] {
        let steps: [(name: String, texts: [(String, fades: Bool)])] = [
            ("unfaded text after a fade", [("Hello ", false), ("Hello there ", true), ("Hello there FINAL", false)]),
            ("right-to-left text", [("مرحبا ", false), ("مرحبا بكم ", true), ("مرحبا بكم في ", true)]),
            ("a word wrapping while it fades", [("A line of words that nearly fills the ", false), ("A line of words that nearly fills the width", true),
                                                ("A line of words that nearly fills the widthwidth", true)]),
        ]
        var problems: [String] = []
        for (name, texts) in steps {
            let view = UITextView.answerText(delegate: TextViewActions())
            view.frame = CGRect(x: 0, y: 0, width: 260, height: 300)
            var previous: NSAttributedString?
            for (text, fades) in texts {
                let string = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label])
                let kept = view.show(string, replacing: previous)
                if fades, kept < string.length { view.fadeIn(NSRange(location: kept, length: string.length - kept)) }
                previous = string
                view.layoutIfNeeded()
                let hidden = view.hiddenByFadeMask()
                if !hidden.isEmpty { problems.append("\(name): \(hidden.count) characters hidden after \(text.debugDescription)") }
            }
        }
        return problems
    }
}
#endif
