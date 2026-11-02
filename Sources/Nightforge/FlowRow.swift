import SwiftUI

/// Items side by side at their own width, the next ones on a new line once a line is full: nothing
/// cut short or squeezed into two lines of its own. For Home's text column, which is narrower than a
/// game's page (36 % of the window), and the longer German texts – "Herunterladen · bis zu 12 GB"
/// came out as "Herunterlad / en · bis zu…" in an HStack (31.10.2026).
struct FlowRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    /// Items of different heights in one line: their centres level (badges), else their tops (stats).
    var centered = false

    /// The lines, by item, for items of these widths in `available` points: as many as fit on each,
    /// at least one (an item wider than the line gets a line of its own).
    static func lines(widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if !current.isEmpty, used + spacing + width > available {
                lines.append(current)
                current = []
                used = 0
            }
            used += (current.isEmpty ? 0 : spacing) + width
            current.append(index)
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (sizes: [CGSize], lines: [[Int]]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return (sizes, Self.lines(widths: sizes.map(\.width), available: width, spacing: spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? .infinity
        let (sizes, lines) = arrange(subviews, width: available)
        let widths = lines.map { line in line.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(line.count - 1, 0)) }
        let heights = lines.map { line in line.map { sizes[$0].height }.max() ?? 0 }
        let height = heights.reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: min(widths.max() ?? 0, available), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, lines) = arrange(subviews, width: bounds.width)
        var y = bounds.minY
        for line in lines {
            let height = line.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in line {
                let size = CGSize(width: min(sizes[index].width, bounds.width), height: sizes[index].height)
                let top = centered ? y + (height - size.height) / 2 : y
                subviews[index].place(at: CGPoint(x: x, y: top), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + lineSpacing
        }
    }
}
