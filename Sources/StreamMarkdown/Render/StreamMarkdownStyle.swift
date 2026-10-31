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
    /// Code blocks, and HTML drawn as its source.
    public var source = FontToken(.footnote, design: .monospaced)
    /// Table cells, and header cells.
    public var table = FontToken(.callout, design: .serif)
    public var tableHeader = FontToken(.callout, design: .serif, weight: .semibold)

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
    /// How wide a table column grows before its body cells wrap, in ems of the body font. Header cells never wrap.
    public var tableColumnMaxWidth: CGFloat = 14

    public var textColor = SystemColor.label
    public var secondaryTextColor = SystemColor.secondaryLabel
    public var linkColor = Color.accentColor
    public var inlineCodeBackground = SystemColor.fill
    public var quoteTextColor = SystemColor.secondaryLabel
    public var quoteBarColor = SystemColor.tertiaryLabel
    public var ruleColor = SystemColor.separator
    /// Behind code blocks and HTML.
    public var sourceBackground = SystemColor.fill
    public var tableBorderColor = SystemColor.separator
    public var tableHeaderBackground = SystemColor.fill
    /// Code's colours by token.
    public var codeColors = CodeColors.xcode

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

/// Colours for highlighted code; plain code takes the text colour.
public struct CodeColors: Hashable, Sendable {
    public var keyword: Color
    public var string: Color
    public var comment: Color
    public var number: Color
    /// Type names, and the name a declaration introduces.
    public var type: Color
    /// Called and declared functions, and keys in JSON, YAML and markup attributes.
    public var function: Color
    /// Decorators, annotations, preprocessor lines and lifetimes.
    public var attribute: Color
    /// Shell and PHP `$variables`.
    public var variable: Color
    /// A diff's added and removed lines.
    public var inserted: Color
    public var deleted: Color

    public init(keyword: Color, string: Color, comment: Color, number: Color, type: Color, function: Color, attribute: Color,
                variable: Color, inserted: Color, deleted: Color) {
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.type = type
        self.function = function
        self.attribute = attribute
        self.variable = variable
        self.inserted = inserted
        self.deleted = deleted
    }

    /// Xcode's default light and dark themes, with GitHub's diff colours.
    public static let xcode = CodeColors(
        keyword: SystemColor.adaptive(light: 0x9B2393, dark: 0xFC5FA3),
        string: SystemColor.adaptive(light: 0xC41A16, dark: 0xFC6A5D),
        comment: SystemColor.adaptive(light: 0x5D6C79, dark: 0x7F8C98),
        number: SystemColor.adaptive(light: 0x1C00CF, dark: 0xD0BF69),
        type: SystemColor.adaptive(light: 0x0B4F79, dark: 0x5DD8FF),
        function: SystemColor.adaptive(light: 0x326D74, dark: 0x67B7A4),
        attribute: SystemColor.adaptive(light: 0x815F03, dark: 0xBF8555),
        variable: SystemColor.adaptive(light: 0x6C36A9, dark: 0xD0A8FF),
        inserted: SystemColor.adaptive(light: 0x1A7F37, dark: 0x3FB950),
        deleted: SystemColor.adaptive(light: 0xCF222E, dark: 0xF85149)
    )
}

/// The platform's adaptive colours, which follow light and dark appearance.
public enum SystemColor {
    #if canImport(UIKit)
    public static let label = Color(uiColor: .label)
    public static let secondaryLabel = Color(uiColor: .secondaryLabel)
    public static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    public static let separator = Color(uiColor: .separator)
    public static let fill = Color(uiColor: .tertiarySystemFill)

    /// One colour in light appearance and another in dark, each as 0xRRGGBB.
    public static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
    #else
    public static let label = Color(nsColor: .labelColor)
    public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    public static let separator = Color(nsColor: .separatorColor)
    public static let fill = Color(nsColor: .quaternaryLabelColor)

    public static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light) })
    }
    #endif
}

private extension PlatformColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
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
