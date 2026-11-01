import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Hands TextKit an ``InlineCodeFragment`` for each paragraph that holds inline code, and a plain fragment otherwise.
final class InlineCodeLayout: NSObject, NSTextLayoutManagerDelegate, Sendable {
    static let shared = InlineCodeLayout()

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.holdsInlineCode {
            return InlineCodeFragment(textElement: textElement, range: textElement.elementRange)
        }
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}

/// A paragraph that draws a rounded chip under each run of inline code, line by line, before its text.
final class InlineCodeFragment: NSTextLayoutFragment, @unchecked Sendable {
    struct Chip {
        let rect: CGRect
        let style: InlineCodeChip
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: -2, dy: -2)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        for chip in chips() {
            let rect = chip.rect.offsetBy(dx: point.x, dy: point.y)
            let path = CGPath(roundedRect: rect, cornerWidth: chip.style.cornerRadius, cornerHeight: chip.style.cornerRadius, transform: nil)
            context.addPath(path)
            context.setFillColor(chip.style.fill.resolvedCGColor)
            context.fillPath()
            let line = 1 / max(context.ctm.a.magnitude, 1)
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerWidth: chip.style.cornerRadius,
                                   cornerHeight: chip.style.cornerRadius, transform: nil))
            context.setStrokeColor(chip.style.border.resolvedCGColor)
            context.setLineWidth(line)
            context.strokePath()
        }
        super.draw(at: point, in: context)
    }

    /// Each chip's box in the fragment's coordinates, one per piece of the code TextKit lays out on a line, so a run whose
    /// direction differs from the paragraph's is covered where it lands; as tall as the code's font, a point over. The
    /// piece beside the character before the code reaches `padding` towards it, into the room its kerning made.
    func chips() -> [Chip] {
        guard let paragraph = textElement as? NSTextParagraph, let layout = textLayoutManager, let content = layout.textContentManager,
              let element = paragraph.elementRange else { return [] }
        let text = paragraph.attributedString
        let base = content.offset(from: content.documentRange.location, to: element.location)
        let origin = layoutFragmentFrame.origin
        func segments(_ range: NSRange) -> [(frame: CGRect, baseline: CGFloat)] {
            guard let textRange = NSTextRange(NSRange(location: base + range.location, length: range.length), in: content) else { return [] }
            var found: [(CGRect, CGFloat)] = []
            layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, baseline, _ in
                if frame.width > 0 { found.append((frame.offsetBy(dx: -origin.x, dy: -origin.y), baseline)) }
                return true
            }
            return found
        }
        var chips: [Chip] = []
        text.enumerateAttribute(.streamMarkdownInlineCode, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let style = value as? InlineCodeChip, let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont else { return }
            let before = range.location > 0 ? segments((text.string as NSString).rangeOfComposedCharacterSequence(at: range.location - 1)).first : nil
            for (frame, baseline) in segments(range) {
                var (minX, maxX) = (frame.minX, frame.maxX)
                if let before, abs(before.frame.midY - frame.midY) < frame.height / 2 {
                    if before.frame.midX < frame.midX { minX -= style.padding } else { maxX += style.padding }
                }
                let top = frame.minY + baseline - font.ascender - 1
                chips.append(Chip(rect: CGRect(x: minX, y: top, width: maxX - minX, height: font.ascender - font.descender + 2), style: style))
            }
        }
        return chips
    }
}

extension NSTextRange {
    /// A range of UTF-16 offsets in a content manager's document.
    convenience init?(_ range: NSRange, in content: NSTextContentManager) {
        guard let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        self.init(location: start, end: end)
    }
}

extension NSAttributedString {
    var holdsInlineCode: Bool {
        var found = false
        enumerateAttribute(.streamMarkdownInlineCode, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

private extension PlatformColor {
    /// The colour for the appearance being drawn.
    var resolvedCGColor: CGColor {
        #if canImport(UIKit)
        resolvedColor(with: .current).cgColor
        #else
        cgColor
        #endif
    }
}
