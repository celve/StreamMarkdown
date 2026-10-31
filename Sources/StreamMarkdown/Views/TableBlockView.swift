#if canImport(UIKit)
import SwiftUI

/// A table as a grid in a horizontal scroll: a header row on a fill, hairlines between rows, a rounded border.
struct TableBlockView: View {
    let table: TableContent
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let hairline = 1 / displayScale
        let shape = RoundedRectangle(cornerRadius: em * 0.5)
        ScrollView(.horizontal) {
            TableLayout(columns: table.columns, maxColumnWidth: style.tableColumnMaxWidth * em) {
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
    }
}

/// Columns as wide as their widest cell, a body cell wrapping past `maxColumnWidth` and a header cell never; rows as
/// tall as their tallest cell. Subviews come row by row, header first.
struct TableLayout: Layout {
    let columns: Int
    let maxColumnWidth: CGFloat

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
        for (index, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified).width
            widths[index % columns] = max(widths[index % columns], index < columns ? natural : min(natural, maxColumnWidth))
        }
        widths = widths.map { $0.rounded(.up) }
        var heights = Array(repeating: CGFloat(0), count: subviews.count / columns)
        for (index, subview) in subviews.enumerated() where index / columns < heights.count {
            let height = subview.sizeThatFits(ProposedViewSize(width: widths[index % columns], height: nil)).height
            heights[index / columns] = max(heights[index / columns], height.rounded(.up))
        }
        return (widths, heights)
    }
}
#endif
