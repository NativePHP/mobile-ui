import SwiftUI

struct NativeUIColumnRenderer: View {
    let node: NativeUINode
    /// The children to lay out when that isn't all of `node.children`: a
    /// pressable leaves out its menu items.
    var children: [NativeUINode]? = nil

    var body: some View {
        let children = self.children ?? node.children
        if children.isEmpty {
            Color.clear
        } else {
            let dir = node.layout?.flexDirection ?? FlexDirection.column
            FlexContainer(
                direction: dir,
                justify: node.layout?.justifyContent ?? JustifyContent.start,
                align: node.layout?.alignItems ?? AlignItems.stretch,
                gap: CGFloat(node.layout?.gap ?? 0),
                wrap: node.layout?.flexWrap ?? 0,
                childNodes: children
            ) {
                ForEach(children) { child in
                    NodeView(node: child)
                        .equatable()
                }
            }
        }
    }
}
