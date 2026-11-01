import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension NSAttributedString.Key {
    /// Inline code, drawn on a rounded chip by ``InlineCodeFragment``; the value is an ``InlineCodeChip``.
    static let streamMarkdownInlineCode = NSAttributedString.Key("StreamMarkdownInlineCode")
}

/// How inline code's chip is drawn: a fill and a hairline, rounded, reaching `padding` before the code's first character.
/// The builder kerns the character before the code and the code's last one by `padding`, so the chip has room.
final class InlineCodeChip: NSObject, @unchecked Sendable {
    let fill: PlatformColor
    let border: PlatformColor
    let cornerRadius: CGFloat
    let padding: CGFloat

    init(fill: PlatformColor, border: PlatformColor, cornerRadius: CGFloat, padding: CGFloat) {
        self.fill = fill
        self.border = border
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? InlineCodeChip else { return false }
        return other === self || (other.fill == fill && other.border == border && other.cornerRadius == cornerRadius && other.padding == padding)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(fill)
        hasher.combine(border)
        hasher.combine(cornerRadius)
        hasher.combine(padding)
        return hasher.finalize()
    }
}
