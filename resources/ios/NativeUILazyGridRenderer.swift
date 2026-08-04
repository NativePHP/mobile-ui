import SwiftUI

/// Self-scrolling grid backed by SwiftUI `LazyVGrid` / `LazyHGrid`.
///
/// Children are laid out lazily — SwiftUI only materializes the rows
/// currently in (or about to enter) the viewport, so this scales to
/// thousands of cells without paying for them at first paint. Use it in
/// place of `<scroll-view>` wrapping a manually-chunked row grid
/// whenever the cell count is large enough to matter.
struct NativeUILazyGridRenderer: View {
    let node: NativeUINode

    var body: some View {
        let columns = max(1, node.props.getInt("columns", default: 2))
        let gap = CGFloat(node.props.getFloat("gap", default: 0))
        let horizontal = node.props.getBool("horizontal")
        // Unlike scroll-view, the grid's historical default is HIDDEN —
        // `shows_indicators: true` opts long grids into a position cue.
        let showsIndicators = node.props.getBool("shows_indicators", default: false)

        // `.flexible()` lets each track share the available cross-axis
        // space evenly. Spacing is symmetrical with the inter-line gap.
        let tracks = Array(
            repeating: GridItem(.flexible(), spacing: gap),
            count: columns
        )

        if horizontal {
            ScrollView(.horizontal, showsIndicators: showsIndicators) {
                LazyHGrid(rows: tracks, spacing: gap) {
                    ForEach(node.children) { child in
                        NodeView(node: child).equatable()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                LazyVGrid(columns: tracks, spacing: gap) {
                    ForEach(node.children) { child in
                        NodeView(node: child).equatable()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
