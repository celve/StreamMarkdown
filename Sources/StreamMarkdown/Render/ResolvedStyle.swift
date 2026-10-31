import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// What rendering depends on besides the text: the host's style and the reader's text size.
struct RenderEnvironment: Hashable, Sendable {
    var style: StreamMarkdownStyle
    var dynamicTypeSize: DynamicTypeSize

    init(style: StreamMarkdownStyle = .default, dynamicTypeSize: DynamicTypeSize = .large) {
        self.style = style
        self.dynamicTypeSize = dynamicTypeSize
    }
}

/// A font as the builder varies it: a size and face from a token, then weight and slant from emphasis.
struct FontSpec: Hashable {
    var size: CGFloat
    var design: Font.Design
    /// The platform's weight value, so strong can raise it.
    var weight: CGFloat
    var italic = false

    var font: PlatformFont {
        #if canImport(UIKit)
        var descriptor = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(weight)).fontDescriptor
        descriptor = descriptor.withDesign(design.platform) ?? descriptor
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor }
        return UIFont(descriptor: descriptor, size: size)
        #else
        var descriptor = NSFont.systemFont(ofSize: size, weight: NSFont.Weight(weight)).fontDescriptor
        descriptor = descriptor.withDesign(design.platform) ?? descriptor
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
        #endif
    }

    static let boldWeight = PlatformFont.Weight.bold.rawValue
}

/// The style's tokens resolved for one text size: font specs, points and platform colours. Immutable, so jobs share it.
final class ResolvedStyle: @unchecked Sendable {
    let environment: RenderEnvironment
    let body: FontSpec
    let headings: [FontSpec]
    let source: FontSpec
    /// The body font's size, the unit of the style's spacing.
    let em: CGFloat
    let text: PlatformColor
    let secondaryText: PlatformColor
    let link: PlatformColor
    let inlineCodeBackground: PlatformColor
    let quoteText: PlatformColor

    init(_ environment: RenderEnvironment) {
        self.environment = environment
        let style = environment.style
        body = Self.spec(style.body, environment.dynamicTypeSize)
        headings = (1...6).map { Self.spec(style.heading($0), environment.dynamicTypeSize) }
        source = Self.spec(style.source, environment.dynamicTypeSize)
        em = body.size
        text = PlatformColor(style.textColor)
        secondaryText = PlatformColor(style.secondaryTextColor)
        link = PlatformColor(style.linkColor)
        inlineCodeBackground = PlatformColor(style.inlineCodeBackground)
        quoteText = PlatformColor(style.quoteTextColor)
    }

    static let standard = ResolvedStyle(RenderEnvironment())

    var style: StreamMarkdownStyle { environment.style }

    func heading(_ level: Int) -> FontSpec { headings[min(max(level, 1), 6) - 1] }

    private static func spec(_ token: StreamMarkdownStyle.FontToken, _ size: DynamicTypeSize) -> FontSpec {
        FontSpec(size: (pointSize(token.textStyle, size) * token.scale).rounded(toPlaces: 1), design: token.design, weight: token.weight.platform)
    }

    private static func pointSize(_ textStyle: Font.TextStyle, _ size: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle.platform, compatibleWith: traits).pointSize
        #else
        return NSFontDescriptor.preferredFontDescriptor(forTextStyle: textStyle.platform).pointSize
        #endif
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let scale = CGFloat(pow(10, Double(places)))
        return (self * scale).rounded() / scale
    }
}

private extension Font.TextStyle {
    var platform: PlatformFont.TextStyle {
        switch self {
        case .largeTitle, .extraLargeTitle, .extraLargeTitle2: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

private extension Font.Design {
    #if canImport(UIKit)
    var platform: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
    }
    #else
    var platform: NSFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
    }
    #endif
}

private extension Font.Weight {
    var platform: CGFloat {
        let weight: PlatformFont.Weight = switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
        return weight.rawValue
    }
}
