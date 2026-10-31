#if canImport(UIKit)
import SwiftUI
import UIKit

/// A table as a grid in a horizontal scroll: a header row on a fill, hairlines between rows, a rounded border.
struct TableBlockView: View {
    let table: TableContent
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            TableGrid(table: table, fitWidth: width)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The grid as one UIKit view, so a pass over the answer asks each table for one size rather than laying out its cells.
struct TableGrid: UIViewRepresentable {
    let table: TableContent
    /// The width the table fits in before it scrolls.
    let fitWidth: CGFloat
    @Environment(\.streamMarkdownStyle) private var style
    @Environment(\.streamMarkdownEm) private var em
    @Environment(\.streamMarkdownStream) private var stream
    @Environment(\.streamMarkdownFadesIn) private var fadesIn

    func makeCoordinator() -> TextViewActions { TextViewActions() }

    func makeUIView(context: Context) -> TableGridView {
        TableGridView(actions: context.coordinator)
    }

    func updateUIView(_ view: TableGridView, context: Context) {
        context.coordinator.openURL = context.environment.openURL
        view.show(table, metrics: TableGridView.Metrics(style: style, em: em), fadesNewRows: fadesIn && stream?.animates == true)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TableGridView, context: Context) -> CGSize? {
        uiView.size(fitting: fitWidth)
    }
}

/// Cells in labels on a grid: columns as wide as their widest cell, a body cell wrapping past the style's column width
/// and a header cell never, rows as tall as their tallest cell. A table wider than the width it is given that would fit
/// with its widest wrapping columns narrowed, none below its header or six ems, is narrowed; one that would not keeps
/// its widths and scrolls. Labels rather than text views, since creating a text view per cell cost the stream about
/// 25 ms/s of main thread; a tap on a link goes to `openURL`, and the cells' text cannot be selected.
final class TableGridView: UIView {
    struct Metrics: Equatable {
        var padding: UIEdgeInsets
        var maxColumnWidth: CGFloat
        var minColumnWidth: CGFloat
        var cornerRadius: CGFloat
        var headerBackground: UIColor
        var border: UIColor

        init(style: StreamMarkdownStyle, em: CGFloat) {
            padding = UIEdgeInsets(top: em * 0.4, left: em * 0.6, bottom: em * 0.4, right: em * 0.6)
            maxColumnWidth = style.tableColumnMaxWidth * em
            minColumnWidth = 6 * em
            cornerRadius = em * 0.5
            headerBackground = UIColor(style.tableHeaderBackground)
            border = UIColor(style.tableBorderColor)
        }
    }

    private struct Grid {
        let fitWidth: CGFloat
        let widths: [CGFloat]
        let heights: [CGFloat]
        var size: CGSize { CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +)) }
    }

    private struct Cell {
        let view: UILabel
        var text: RichText?
        /// Its text's widest line, and its height at each width it was given, padding excluded.
        var natural: CGFloat?
        var heights: [CGFloat: CGFloat] = [:]
    }

    private let actions: TextViewActions
    private var cells: [Cell] = []
    private var columns = 0
    private var metrics: Metrics?
    private var grid: Grid?
    /// The width SwiftUI last fitted the table to, which layout keeps to.
    private var fitWidth: CGFloat = 0
    private let header = UIView()
    private var rules: [UIView] = []

    init(actions: TextViewActions) {
        self.actions = actions
        super.init(frame: .zero)
        layer.masksToBounds = true
        addSubview(header)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TableGridView, _) in view.updateBorder() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not available") }

    /// `fadesNewRows`: rows added to a table already shown fade in, as the answer streams.
    func show(_ table: TableContent, metrics: Metrics, fadesNewRows: Bool = false) {
        if metrics != self.metrics {
            self.metrics = metrics
            layer.cornerRadius = metrics.cornerRadius
            header.backgroundColor = metrics.headerBackground
            updateBorder()
            for index in cells.indices { (cells[index].natural, cells[index].heights) = (nil, [:]) }
            grid = nil
        }
        let texts = table.rows.flatMap { $0.map(\.text) }
        if columns != table.columns { (columns, grid) = (table.columns, nil) }
        var added: [UILabel] = []
        let wasShown = !cells.isEmpty
        while cells.count < texts.count {
            let view = UILabel()
            view.numberOfLines = 0
            addSubview(view)
            cells.append(Cell(view: view))
            added.append(view)
        }
        if fadesNewRows, wasShown, !added.isEmpty {
            added.forEach { $0.alpha = 0 }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { added.forEach { $0.alpha = 1 } }
        }
        while cells.count > texts.count {
            cells.removeLast().view.removeFromSuperview()
            grid = nil
        }
        for (index, text) in texts.enumerated() where cells[index].text !== text {
            let began = ContinuousClock.now
            cells[index].view.attributedText = text.string
            describe(cells[index].view, text.string)
            StreamMarkdownDiagnostics.textUpdateMs += (ContinuousClock.now - began).milliseconds
            StreamMarkdownDiagnostics.textViewUpdates += 1
            cells[index] = Cell(view: cells[index].view, text: text)
            grid = nil
        }
        let ruleCount = max((columns > 0 ? cells.count / columns : 0) - 1, 0)
        while rules.count < ruleCount {
            let rule = UIView()
            addSubview(rule)
            rules.append(rule)
        }
        while rules.count > ruleCount { rules.removeLast().removeFromSuperview() }
        rules.forEach { $0.backgroundColor = metrics.border }
        setNeedsLayout()
    }

    func size(fitting fitWidth: CGFloat) -> CGSize {
        self.fitWidth = fitWidth
        return grid(fitting: fitWidth).size
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let metrics, columns > 0 else { return }
        let grid = grid(fitting: fitWidth)
        let hairline = 1 / max(traitCollection.displayScale, 1)
        var y: CGFloat = 0
        for (row, height) in grid.heights.enumerated() {
            var x: CGFloat = 0
            for (column, width) in grid.widths.enumerated() {
                // As tall as its own text, since a label centres its text in a taller frame.
                var frame = CGRect(x: x, y: y, width: width, height: height).inset(by: metrics.padding)
                frame.size.height = textHeight(row * columns + column, width: frame.width)
                let view = cells[row * columns + column].view
                if view.frame != frame { view.frame = frame }
                x += width
            }
            y += height
            if row < rules.count { rules[row].frame = CGRect(x: 0, y: y - hairline, width: bounds.width, height: hairline) }
        }
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: grid.heights.first ?? 0)
        layer.borderWidth = hairline
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: self)
        guard let cell = cells.first(where: { $0.view.frame.contains(point) }), let url = cell.view.attributedText?.link(at: convert(point, to: cell.view), within: cell.view.bounds.size) else { return }
        actions.openURL?(url)
    }

    /// What VoiceOver reads for a cell: formulas as their TeX, and an action to open each link.
    private func describe(_ label: UILabel, _ text: NSAttributedString) {
        label.accessibilityLabel = text.spokenMath ?? text.string
        var links: [UIAccessibilityCustomAction] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let url = value as? URL else { return }
            let name = (text.string as NSString).substring(with: range)
            links.append(UIAccessibilityCustomAction(name: "Open \(name)") { [weak self] _ in
                self?.actions.openURL?(url)
                return true
            })
        }
        label.accessibilityCustomActions = links
        label.accessibilityTraits = links.isEmpty ? .staticText : [.staticText, .link]
    }

    private func updateBorder() {
        layer.borderColor = metrics?.border.resolvedColor(with: traitCollection).cgColor
    }

    private func grid(fitting fitWidth: CGFloat) -> Grid {
        if let grid, grid.fitWidth == fitWidth { return grid }
        guard let metrics, columns > 0 else { return Grid(fitWidth: fitWidth, widths: [], heights: []) }
        let padding = metrics.padding.left + metrics.padding.right
        var widths = Array(repeating: CGFloat(0), count: columns)
        var floors = Array(repeating: CGFloat(0), count: columns)
        for index in cells.indices {
            let natural = naturalWidth(index) + padding
            let column = index % columns
            widths[column] = max(widths[column], index < columns ? natural : min(natural, metrics.maxColumnWidth))
            floors[column] = max(floors[column], index < columns ? natural : min(natural, metrics.minColumnWidth))
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
        var heights = Array(repeating: CGFloat(0), count: cells.count / columns)
        for index in cells.indices where index / columns < heights.count {
            let height = textHeight(index, width: widths[index % columns] - padding) + metrics.padding.top + metrics.padding.bottom
            heights[index / columns] = max(heights[index / columns], height)
        }
        let grid = Grid(fitWidth: fitWidth, widths: widths, heights: heights)
        self.grid = grid
        return grid
    }

    private func naturalWidth(_ index: Int) -> CGFloat {
        if let natural = cells[index].natural { return natural }
        // A point to spare: a label can wrap at exactly the width its own sizeThatFits gave.
        let natural = measure(index, width: .greatestFiniteMagnitude).width + 1
        cells[index].natural = natural
        return natural
    }

    private func textHeight(_ index: Int, width: CGFloat) -> CGFloat {
        if let height = cells[index].heights[width] { return height }
        let height = measure(index, width: width).height
        cells[index].heights[width] = height
        return height
    }

    private func measure(_ index: Int, width: CGFloat) -> CGSize {
        let began = ContinuousClock.now
        defer { StreamMarkdownDiagnostics.sizingMs += (ContinuousClock.now - began).milliseconds }
        let size = cells[index].view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }
}
#endif
