import SwiftUI

/// `native:lazy-stack`: a vertical scroll of children drawn lazily, in a
/// ScrollView with a LazyVStack, each child identified by its node id.
///
/// It's for long feeds that change often. `native:list` is a SwiftUI `List`,
/// which got slower with every row inserted into it: at 60 inserts a second
/// an update cost about 10 ms after 100 inserts and 250 to 600 ms once the
/// list was full at 1,000 rows. The same rows here stayed at about 5 ms an
/// update through 3,600 inserts.
///
/// It does less than a list on purpose: no separators, swipe actions,
/// pull-to-refresh, sections or row callbacks. Rows draw themselves.
///
/// - Spacing between children is the node's `gap-*`.
/// - `p-*` pads the stack's frame, like any element. `content_padding_*`
///   pads the scrolled content instead, so the first and last child can sit
///   clear of the edges and still scroll under them.
/// - A child added above the screen doesn't move what's on it: the stack
///   keeps the top child on screen where it was. A reader at the very top
///   stays at the top and sees new children come in.
struct NativeUILazyStackRenderer: View {
    let node: NativeUINode

    /// The child the stack keeps in place when children are added above it.
    @State private var position = ScrollPosition(idType: Int.self)

    /// Whether the reader is at the very top, where children added above
    /// should show rather than be kept off screen.
    @State private var atTop = true

    var body: some View {
        let children = node.children
        let spacing = CGFloat(node.layout?.gap ?? 0)
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let contentPadding = EdgeInsets(
            top: CGFloat(node.props.getFloat("content_padding_top", default: 0)),
            leading: CGFloat(node.props.getFloat("content_padding_left", default: 0)),
            bottom: CGFloat(node.props.getFloat("content_padding_bottom", default: 0)),
            trailing: CGFloat(node.props.getFloat("content_padding_right", default: 0))
        )

        ScrollView(.vertical, showsIndicators: showsIndicators) {
            LazyVStack(alignment: .leading, spacing: spacing) {
                ForEach(children) { child in
                    NodeView(node: child)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // The children are what the scroll position is kept by.
            .scrollTargetLayout()
            .padding(contentPadding)
        }
        .scrollPosition($position, anchor: .top)
        .onScrollGeometryChange(for: Bool.self, of: Self.isAtTop) { _, isAtTop in
            atTop = isAtTop
        }
        .onChange(of: children.first?.id) { _, _ in
            // The scroll position keeps the child that was at the top in
            // place, which at the very top would hide what was just added.
            guard atTop else { return }
            position.scrollTo(edge: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(ScrollViewBackgroundModifier(node: node))
    }

    /// Built from the geometry alone, so it captures nothing of the stack.
    private static func isAtTop(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentOffset.y + geometry.contentInsets.top <= 1
    }
}
