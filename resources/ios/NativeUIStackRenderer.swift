import SwiftUI

/// Custom Layout for `<stack>` — z-layers children centered within
/// the stack's bounds at their natural (or explicitly fill) sizes.
///
/// Why not a plain `ZStack`? `ZStack` proposes its own bounds to each
/// child. Any child whose `NodeLayoutModifier` carries `maxWidth: .infinity`
/// (the default for nodes that don't set an explicit width) will inflate
/// its frame to fill the stack. Combined with the modifier's
/// `alignment: .topLeading`, that pushes the actual content (e.g. an
/// `<icon>` glyph) to the leading edge — even though ZStack's own
/// alignment is `.center`. The visible symptom is "icon-on-the-left"
/// inside any stack that mixes a small intrinsic-sized child with a
/// larger sibling.
///
/// This Layout sidesteps that by:
///  1. Sizing each child via `.unspecified` (so its frame doesn't inflate).
///  2. Honoring `widthMode == fill` / `heightMode == fill` if the child
///     explicitly opted in (e.g. `class="w-full"`).
///  3. Centering each child within the stack's bounds.
struct NativeUIStackLayout: Layout {
    let childNodes: [NativeUINode]

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // Targeted scroll-view fix: a scroll-view's `.unspecified` measure
        // returns its CONTENT size (e.g. a 2400x1600 image inside a 2D
        // pannable scroll), not its frame size. Including that in maxSize
        // inflates the stack to the inner content's dimensions, which
        // bleeds into siblings (e.g. a `w-full` foreground column ends up
        // 2400 wide too) and breaks scroll-view's own pan because it gets
        // sized to its content instead of the viewport.
        //
        // Other types are unchanged — column / row / image / text / etc.
        // contribute their natural size to maxSize as before.
        var maxSize = CGSize.zero
        for (i, subview) in subviews.enumerated() {
            let isScrollView = i < childNodes.count && childNodes[i].type == "scroll_view"
            if isScrollView { continue }
            // Absolute children overlay the stack (badges, corner chips) —
            // they must not inflate its size, same as FlexContainer keeping
            // them out of the flow measurement.
            let isAbsolute = i < childNodes.count
                && childNodes[i].layout?.positionType == PositionType.absolute
            if isAbsolute { continue }

            let size = subview.sizeThatFits(.unspecified)
            maxSize.width = max(maxSize.width, size.width)
            maxSize.height = max(maxSize.height, size.height)
        }
        return CGSize(
            width: proposal.width ?? maxSize.width,
            height: proposal.height ?? maxSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for (i, subview) in subviews.enumerated() {
            let layout = i < childNodes.count ? childNodes[i].layout : nil
            let widthFill = layout?.widthMode == SizeMode.fill
            let heightFill = layout?.heightMode == SizeMode.fill

            // Measure against the width the child will ACTUALLY be given. A
            // `w-full` child's height depends on that width — wrapping text is
            // the obvious case — and `.unspecified` measures at unbounded
            // width, so a multi-line title reports the height of ONE long line.
            // That under-reported height then feeds the bottom-anchored
            // placement below (`maxY - height - bottom`), putting the child far
            // too low and letting it spill out of the stack once it renders
            // wrapped. Non-filling children keep the unspecified proposal, so
            // intrinsic-sized badges and chips are unaffected.
            let natural = subview.sizeThatFits(ProposedViewSize(
                width: widthFill ? bounds.width : nil,
                height: heightFill ? bounds.height : nil
            ))
            let width = widthFill ? bounds.width : natural.width
            let height = heightFill ? bounds.height : natural.height

            // Absolute children pin to the stack's edges by inset — the
            // docs-blessed "layer a badge over an icon" pattern. Same anchor
            // convention as FlexContainer.placeAbsolute: a NON-ZERO right /
            // bottom inset (with zero left/top) anchors to that edge, and a
            // negative one deliberately overhangs it (`-right-8` bleed).
            if layout?.positionType == PositionType.absolute {
                let top = CGFloat(layout?.positionTop ?? 0)
                let right = CGFloat(layout?.positionRight ?? 0)
                let bottom = CGFloat(layout?.positionBottom ?? 0)
                let left = CGFloat(layout?.positionLeft ?? 0)

                var x = bounds.minX + left
                if right != 0 && left == 0 {
                    x = bounds.maxX - width - right
                }
                var y = bounds.minY + top
                if bottom != 0 && top == 0 {
                    y = bounds.maxY - height - bottom
                }

                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: width, height: height)
                )
                continue
            }

            let x = bounds.minX + (bounds.width - width) / 2
            let y = bounds.minY + (bounds.height - height) / 2

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: width, height: height)
            )
        }
    }
}

struct NativeUIStackRenderer: View {
    let node: NativeUINode

    var body: some View {
        NativeUIStackLayout(childNodes: node.children) {
            ForEach(node.children) { child in
                NodeView(node: child)
                    .equatable()
            }
        }
    }
}
