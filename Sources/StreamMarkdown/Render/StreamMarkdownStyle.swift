import SwiftUI

/// The look of a rendered answer, as tokens a host can override: fonts by role, spacing in ems of the body font, colours.
public struct StreamMarkdownStyle: Hashable, Sendable {
    /// A font by its Dynamic Type text style, so it follows the reader's text size.
    public struct FontToken: Hashable, Sendable {
        public var textStyle: Font.TextStyle
        public var design: Font.Design
        public var weight: Font.Weight
        /// A multiple of the text style's size.
        public var scale: CGFloat

        public init(_ textStyle: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight = .regular, scale: CGFloat = 1) {
            self.textStyle = textStyle
            self.design = design
            self.weight = weight
            self.scale = scale
        }
    }

    public var body = FontToken(.body, design: .serif)
    /// Levels 1 to 6; a level past the end takes the last.
    public var headings = [
        FontToken(.title2, weight: .semibold),
        FontToken(.title3, weight: .semibold),
        FontToken(.headline, weight: .semibold),
        FontToken(.subheadline, weight: .semibold),
    ]
    /// Inline code's size as a multiple of the text around it; the face is monospaced.
    public var inlineCodeScale: CGFloat = 0.88
    /// Formulas' size as a multiple of the text around them: a math face reads smaller than the serif body at one size.
    public var mathScale: CGFloat = 1.1
    /// Code, tables and HTML, drawn as their source.
    public var source = FontToken(.footnote, design: .monospaced)

    /// Extra space between the lines of a paragraph, in ems of its font.
    public var lineSpacing: CGFloat = 0.25
    /// Between blocks, in ems of the body font.
    public var blockSpacing: CGFloat = 0.75
    public var headingSpacingBefore: CGFloat = 1.25
    public var headingSpacingAfter: CGFloat = 0.4
    public var listItemSpacing: CGFloat = 0.35
    /// How far each list level indents its items, in ems of the body font.
    public var listIndent: CGFloat = 1.6
    /// The gap between a block quote's bar and its blocks, in ems of the body font.
    public var quoteIndent: CGFloat = 0.8
    /// In points.
    public var quoteBarWidth: CGFloat = 3

    public var textColor = SystemColor.label
    public var secondaryTextColor = SystemColor.secondaryLabel
    public var linkColor = Color.accentColor
    public var inlineCodeBackground = SystemColor.fill
    public var quoteTextColor = SystemColor.secondaryLabel
    public var quoteBarColor = SystemColor.tertiaryLabel
    public var ruleColor = SystemColor.separator
    public var sourceBackground = SystemColor.fill

    public init() {}

    public static let `default` = StreamMarkdownStyle()

    func heading(_ level: Int) -> FontToken {
        headings.isEmpty ? body : headings[min(max(level, 1), headings.count) - 1]
    }

    /// The space above a block after another, in ems of the body font.
    func spacing(between previous: BlockKind, and next: BlockKind) -> CGFloat {
        if case .heading = next { return headingSpacingBefore }
        if case .heading = previous { return headingSpacingAfter }
        return blockSpacing
    }
}

/// The platform's adaptive colours, which follow light and dark appearance.
public enum SystemColor {
    #if canImport(UIKit)
    public static let label = Color(uiColor: .label)
    public static let secondaryLabel = Color(uiColor: .secondaryLabel)
    public static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    public static let separator = Color(uiColor: .separator)
    public static let fill = Color(uiColor: .tertiarySystemFill)
    #else
    public static let label = Color(nsColor: .labelColor)
    public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    public static let separator = Color(nsColor: .separatorColor)
    public static let fill = Color(nsColor: .quaternaryLabelColor)
    #endif
}

extension EnvironmentValues {
    @Entry var streamMarkdownStyle = StreamMarkdownStyle.default
}

public extension View {
    /// Sets the style of the ``StreamMarkdownView``s inside this view.
    func streamMarkdownStyle(_ style: StreamMarkdownStyle) -> some View {
        environment(\.streamMarkdownStyle, style)
    }
}
