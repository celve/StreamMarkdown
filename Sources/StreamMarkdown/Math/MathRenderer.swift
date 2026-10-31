import CoreGraphics
import Foundation
import SwiftMath
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// A formula as SwiftMath draws it: a template image, tinted with the colour of the text around it, and its baseline.
final class RenderedMath: @unchecked Sendable {
    let image: PlatformImage
    /// From the image's bottom edge up to the formula's baseline.
    let baseline: CGFloat

    init(image: PlatformImage, baseline: CGFloat) {
        self.image = image
        self.baseline = baseline
    }

    var size: CGSize { image.size }
}

/// Typesets formulas with SwiftMath, off the main thread, each once per size and style.
enum MathRenderer {
    private final class Entry {
        let math: RenderedMath?
        init(_ math: RenderedMath?) { self.math = math }
    }

    /// SwiftMath's typesetter races on its shared tables when two threads typeset at once (ThreadSanitizer, 1.7.3).
    private static let typesetting = NSLock()

    nonisolated(unsafe) private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 2000
        return cache
    }()

    /// `tex` in SwiftMath's text style (inline) or display style, or nil when SwiftMath cannot read it even after
    /// ``rewritten(_:)``. Failures are cached too.
    static func render(_ tex: String, fontSize: CGFloat, display: Bool) -> RenderedMath? {
        let key = "\(display ? "d" : "t")\(fontSize)\u{0}\(tex)" as NSString
        if let entry = cache.object(forKey: key) { return entry.math }
        let math = typeset(tex, fontSize: fontSize, display: display) ?? rewritten(tex).flatMap { typeset($0, fontSize: fontSize, display: display) }
        cache.setObject(Entry(math), forKey: key)
        return math
    }

    private static func typeset(_ tex: String, fontSize: CGFloat, display: Bool) -> RenderedMath? {
        var image = MathImage(latex: tex, fontSize: fontSize, textColor: .black, labelMode: display ? .display : .text, textAlignment: .left)
        let (error, drawn, layout) = typesetting.withLock { image.asImage() }
        guard error == nil, let drawn, let layout, drawn.size.width > 0, drawn.size.height > 0 else { return nil }
        // MathImage centres a formula shorter than half the font size, and rounds the image up to whole points.
        let height = max(layout.ascent + layout.descent, fontSize / 2)
        let baseline = (drawn.size.height - height) / 2 + layout.descent
        #if canImport(UIKit)
        return RenderedMath(image: drawn.withRenderingMode(.alwaysTemplate), baseline: baseline)
        #else
        drawn.isTemplate = true
        return RenderedMath(image: drawn, baseline: baseline)
        #endif
    }

    /// Commands LLMs write that SwiftMath lacks, as the nearest ones it has; nil when nothing changed.
    static func rewritten(_ tex: String) -> String? {
        var result = tex
        for (pattern, template) in rewrites {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result == tex ? nil : result
    }

    private static let rewrites: [(String, String)] = [
        (#"\\[dt]frac(?![a-zA-Z])"#, #"\\frac"#),
        (#"\\operatorname\*?\s*\{([^{}]*)\}"#, #"\\mathrm{$1}"#),
        (#"\\(boldsymbol|pmb)(?![a-zA-Z])"#, #"\\mathbf"#),
        (#"\\(begin|end)\{(align|alignat|flalign|eqnarray)\*?\}"#, #"\\$1{aligned}"#),
        (#"\\(begin|end)\{(gather|multline)\*?\}"#, #"\\$1{gather}"#),
        (#"\\(begin|end)\{(equation|displaymath)\*?\}"#, ""),
        (#"\\tag\*?\s*\{([^{}]*)\}"#, #"\\qquad ($1)"#),
        (#"\\(label|nonumber|notag)(\s*\{[^{}]*\})?"#, ""),
        (#"\\[Bb]igg?[lrm]?(?![a-zA-Z])"#, ""),
        (#"\\middle(?![a-zA-Z])"#, ""),
        (#"\\dots[bcimo]?(?![a-zA-Z])"#, #"\\ldots"#),
        (#"\\[lr]Vert(?![a-zA-Z])"#, #"\\|"#),
        (#"\\[lr]vert(?![a-zA-Z])"#, "|"),
        (#"\\implies(?![a-zA-Z])"#, #"\\Rightarrow"#),
        (#"\\impliedby(?![a-zA-Z])"#, #"\\Leftarrow"#),
        (#"\\intercal(?![a-zA-Z])"#, #"\\top"#),
        (#"\\varnothing(?![a-zA-Z])"#, #"\\emptyset"#),
        (#"\\coloneqq(?![a-zA-Z])"#, ":="),
        (#"\\iint(?![a-zA-Z])"#, #"\\int\\int"#),
        (#"\\mathds(?![a-zA-Z])"#, #"\\mathbb"#),
        (#"\\not\s*\\in(?![a-zA-Z])"#, #"\\notin"#),
        (#"\\overrightarrow(?![a-zA-Z])"#, #"\\vec"#),
        (#"\\(underbrace|overbrace)(?![a-zA-Z])"#, ""),
    ]
}

/// A formula in a text view, labelled with its TeX. An inline one sits on the baseline and shrinks to the line when
/// wider; a display one takes the line's width and draws nothing, for the text view to cover with a scrolling view.
final class MathAttachment: NSTextAttachment {
    private(set) var tex = ""
    private(set) var isDisplay = false
    /// The text's colour, which a display formula's view is tinted with.
    private(set) var color: PlatformColor?
    private(set) var rendered: RenderedMath?

    init(_ math: RenderedMath, tex: String, display: Bool = false, color: PlatformColor? = nil) {
        self.tex = tex
        isDisplay = display
        self.color = color
        rendered = math
        super.init(data: nil, ofType: nil)
        #if canImport(UIKit)
        if !display { image = math.image }
        #else
        image = math.image
        #endif
        bounds = CGRect(x: 0, y: -math.baseline, width: math.size.width, height: math.size.height)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        Self.bounds(bounds, display: isDisplay, within: proposedLineFragment.width - (isDisplay ? position.x : 0))
    }

    /// A display formula wider than its line keeps its size, since its view scrolls; an inline one shrinks to fit.
    static func bounds(_ natural: CGRect, display: Bool, within available: CGFloat) -> CGRect {
        guard available > 0, natural.width > available else { return natural }
        if display { return CGRect(x: 0, y: natural.minY, width: available, height: natural.height) }
        let scale = available / natural.width
        return CGRect(x: 0, y: natural.minY * scale, width: available, height: natural.height * scale)
    }

    #if canImport(UIKit)
    /// Read from the attachment rather than set on it, since the parse job builds attachments off the main actor.
    override var accessibilityLabel: String? {
        get { tex }
        set {}
    }

    /// Tinted with the run's colour as it resolves in the text view's appearance, so a formula follows dark mode.
    override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?) -> UIImage? {
        guard let image, let color = attributes[.foregroundColor] as? UIColor else { return image }
        return image.withTintColor(color, renderingMode: .alwaysOriginal)
    }
    #endif

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MathAttachment else { return false }
        return other.tex == tex && other.isDisplay == isDisplay && other.color == color && other.bounds == bounds && other.rendered === rendered
    }

    override var hash: Int { tex.hashValue }
}
