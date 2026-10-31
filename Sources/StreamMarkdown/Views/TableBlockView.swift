#if canImport(UIKit)
import SwiftUI

/// A table as a grid in a horizontal scroll: a header row on a fill, hairlines between rows, a rounded border.
struct TableBlockView: View {
    let table: TableContent
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em
    @Environment(\.displayScale) private var displayScale
    @State private var width: CGFloat = 0

    var body: some View {
        let hairline = 1 / displayScale
        let shape = RoundedRectangle(cornerRadius: em * 0.5)
        ScrollView(.horizontal) {
            TableLayout(columns: table.columns, maxColumnWidth: style.tableColumnMaxWidth * em, fitWidth: width, minColumnWidth: 6 * em) {
                ForEach(0..<table.rows.count * table.columns, id: \.self) { index in
                    let row = index / table.columns
                    ProseTextView(text: table.rows[row][index % table.columns].text)
                        .padding(.horizontal, em * 0.6)
                        .padding(.vertical, em * 0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(row == 0 ? style.tableHeaderBackground : .clear)
                        .overlay(alignment: .bottom) {
                            if row < table.rows.count - 1 {
                                Rectangle().fill(style.tableBorderColor).frame(height: hairline)
                            }
                        }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(style.tableBorderColor, lineWidth: hairline) }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Columns as wide as their widest cell, a body cell wrapping past `maxColumnWidth` and a header cell never; rows as
/// tall as their tallest cell. A table wider than `fitWidth` that would fit with its widest wrapping columns narrowed,
/// none below its header or `minColumnWidth`, is narrowed; one that would not keeps its widths and scrolls. Subviews come row by row, header first.
struct TableLayout: Layout {
    let columns: Int
    let maxColumnWidth: CGFloat
    var fitWidth: CGFloat = 0
    var minColumnWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let grid = measure(subviews)
        return CGSize(width: grid.widths.reduce(0, +), height: grid.heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = measure(subviews)
        var y = bounds.minY
        for (row, height) in grid.heights.enumerated() {
            var x = bounds.minX
            for (column, width) in grid.widths.enumerated() {
                subviews[row * columns + column].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
                x += width
            }
            y += height
        }
    }

    private func measure(_ subviews: Subviews) -> (widths: [CGFloat], heights: [CGFloat]) {
        guard columns > 0 else { return ([], []) }
        var widths = Array(repeating: CGFloat(0), count: columns)
        var floors = Array(repeating: CGFloat(0), count: columns)
        for (index, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified).width.rounded(.up)
            let column = index % columns
            widths[column] = max(widths[column], index < columns ? natural : min(natural, maxColumnWidth))
            floors[column] = max(floors[column], index < columns ? natural : min(natural, minColumnWidth))
        }
        if fitWidth > 0, widths.reduce(0, +) > fitWidth, floors.reduce(0, +) <= fitWidth {
            // The widest columns give way first: find the cap at which the columns, each kept to its floor, fit.
            var (low, high) = (CGFloat(0), widths.max() ?? 0)
            for _ in 0..<24 {
                let cap = (low + high) / 2
                let total = zip(widths, floors).reduce(0) { $0 + max($1.1, min($1.0, cap)) }
                if total > fitWidth { high = cap } else { low = cap }
            }
            widths = zip(widths, floors).map { max($1, min($0, low)).rounded(.down) }
        }
        var heights = Array(repeating: CGFloat(0), count: subviews.count / columns)
        for (index, subview) in subviews.enumerated() where index / columns < heights.count {
            let height = subview.sizeThatFits(ProposedViewSize(width: widths[index % columns], height: nil)).height
            heights[index / columns] = max(heights[index / columns], height.rounded(.up))
        }
        return (widths, heights)
    }
}
#endif
