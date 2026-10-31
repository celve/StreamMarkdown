import Foundation
import Markdown

/// A table as drawn: the header row first, then the body rows, each with `columns` cells.
struct TableContent: Sendable {
    let columns: Int
    let rows: [[TableCell]]
}

struct TableCell: Sendable {
    /// Everything the cell's text was built from, so a later parse keeps an unchanged cell's text and its text view.
    let key: String
    let text: RichText
}

/// Builds a GFM table's cells through ``ProseBuilder``, in the column's alignment, the header's in its own font.
enum TableBuilder {
    static func build(_ table: Table, style: ResolvedStyle, color: PlatformColor?, math: MathTable, reusing previous: [String: RichText]) -> TableContent {
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        let columns = max(table.columnAlignments.count, rows.map(\.count).max() ?? 0)
        let built = rows.enumerated().map { index, cells in
            (0..<columns).map { column -> TableCell in
                let alignment = column < table.columnAlignments.count ? table.columnAlignments[column] : nil
                let cell = column < cells.count ? cells[column] : nil
                let key = "\(index == 0 ? "h" : "b")\(alignment.name)" + (cell.map { RenderInputs.of($0, math: math) } ?? "")
                if let text = previous[key] { return TableCell(key: key, text: text) }
                let text = ProseBuilder.cell(cell, header: index == 0, alignment: alignment, style: style, color: color, math: math)
                return TableCell(key: key, text: text)
            }
        }
        return TableContent(columns: columns, rows: built)
    }
}
