import SwiftUI

struct NativeUIAccordionRenderer: View {
    let node: NativeUINode
    @State private var isExpanded: Bool = false
    @State private var lastSentValue: Bool = false
    @State private var initialized: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = node.props
        let serverValue = p.getBool("expanded")
        let onChangeCb  = p.getCallbackId("on_change")

        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                ForEach(node.children) { child in
                    if child.type == "accordion_content" {
                        ForEach(child.children) { child1 in
                            NodeView(node: child1)
                                .equatable()
                        }
                    }
                }
            },
            label: {
                HStack {
                    ForEach(node.children) { child in
                        if child.type == "accordion_header" {
                            ForEach(child.children) { child1 in
                                NodeView(node: child1)
                                    .equatable()
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        let new = !isExpanded
                        isExpanded = new
                        lastSentValue = new
                        if onChangeCb != 0 {
                            NativeElementBridge.sendToggleChangeEvent(onChangeCb, nodeId: node.id, value: new)
                        }
                    }
                }
            }
        )
        .onAppear {
            if !initialized {
                isExpanded = serverValue
                lastSentValue = serverValue
                initialized = true
            }
        }
    }
}
