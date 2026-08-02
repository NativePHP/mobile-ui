import SwiftUI

/// SwiftUI DisclosureGroup renderer.
///
/// Expand/collapse with echo-prevention value sync (the same contract
/// `NativeUIToggleRenderer` uses): `expanded` is a live binding, not just a
/// mount-time hint, so PHP can drive the group open or closed at any point.
struct NativeUIAccordionRenderer: View {
    let node: NativeUINode

    @State private var isExpanded: Bool = false
    @State private var lastSentValue: Bool = false
    @State private var initialized: Bool = false

    var body: some View {
        let p = node.props
        let serverValue = p.getBool("expanded")
        let onChangeCb  = p.getCallbackId("on_change")

        // Every *user-driven* change flows through this binding — the
        // disclosure chevron and the label tap both land in the setter — so
        // PHP hears about each one. Server-driven updates assign `isExpanded`
        // directly (see `.onChange(of: serverValue)`) and deliberately bypass
        // it, so adopting a programmatic value never echoes an event back.
        let expanded = Binding<Bool>(
            get: { isExpanded },
            set: { new in
                guard new != isExpanded else { return }
                isExpanded = new
                lastSentValue = new
                if onChangeCb != 0 {
                    NativeElementBridge.sendToggleChangeEvent(onChangeCb, nodeId: node.id, value: new)
                }
            }
        )

        DisclosureGroup(
            isExpanded: expanded,
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
                    withAnimation { expanded.wrappedValue.toggle() }
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
        .onChange(of: serverValue) { _, new in
            // Echo-prevention — ignore server pushes that match our last
            // commit; accept genuine programmatic updates. Without this the
            // group only ever reads `expanded` once, so "expand all" and
            // friends silently do nothing on iOS.
            if new != lastSentValue {
                withAnimation { isExpanded = new }
                lastSentValue = new
            }
        }
    }
}
