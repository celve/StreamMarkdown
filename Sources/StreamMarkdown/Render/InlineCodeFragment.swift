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

    /// Each chip's box in the fragment's coordinates: from `padding` before the code's first character, but not past
    /// the line's start, to after its last, whose kerning gives the room after; as tall as the code's font, a point over.
    func chips() -> [Chip] {
        guard let paragraph = textElement as? NSTextParagraph else { return [] }
        let text = paragraph.attributedString
        var chips: [Chip] = []
        text.enumerateAttribute(.streamMarkdownInlineCode, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let style = value as? InlineCodeChip, let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont else { return }
            for line in textLineFragments {
                let part = NSIntersectionRange(line.characterRange, range)
                guard part.length > 0 else { continue }
                let start = line.locationForCharacter(at: part.location).x
                let end = line.locationForCharacter(at: part.upperBound).x
                var minX = min(start, end), maxX = max(start, end)
                if part.location == range.location {
                    if start <= end { minX = max(minX - style.padding, 0) } else { maxX += style.padding }
                }
                let baseline = line.glyphOrigin.y
                let rect = CGRect(x: minX, y: baseline - font.ascender - 1, width: maxX - minX, height: font.ascender - font.descender + 2)
                chips.append(Chip(rect: rect.offsetBy(dx: line.typographicBounds.minX, dy: line.typographicBounds.minY), style: style))
            }
        }
        return chips
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
