import SwiftUI

/// Full-screen modal overlay. Visibility driven by the `visible` prop.
///
/// Dismiss semantics: the `@dismiss` callback fires only from explicit user
/// actions (the close button tap; a full-screen cover has no swipe-to-dismiss).
/// Programmatic `visible = false` from PHP does NOT fire dismiss — that
/// would double-invoke the callback that just set the flag.
///
/// Model 3: close icon + container colors come from theme tokens.
struct NativeUIModalRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let visible = node.props.getBool("visible")
        let dismissible = node.props.getBool("dismissible", default: true)
        let onDismissCb = node.props.getCallbackId("on_dismiss")
        let a11yLabel = node.props.getString("a11y_label")
        let nodeId = node.id

        let fireDismiss = {
            if onDismissCb != 0 {
                NativeElementBridge.sendPressEvent(onDismissCb, nodeId: nodeId)
            }
        }

        Color.clear
            .frame(width: 0, height: 0)
            // No onDismiss: on a constant binding the cover only goes away
            // because PHP set `visible` to false, so onDismiss could only
            // send that close back to PHP as a dismissal.
            .fullScreenCover(isPresented: .constant(visible)) {
                VStack(spacing: 0) {
                    if dismissible {
                        HStack {
                            Spacer()
                            Button(action: fireDismiss) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(theme.onSurfaceVariant)
                                    .nuiMinTapTarget()
                            }
                            .padding()
                            .accessibilityLabel("Close")
                        }
                    }

                    ForEach(node.children) { child in
                        NodeView(node: child).equatable()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(theme.background.ignoresSafeArea())
                // Contain VoiceOver focus within the presented modal content.
                .accessibilityAddTraits(.isModal)
                .modifier(A11yLabelModifier(label: a11yLabel))
            }
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
