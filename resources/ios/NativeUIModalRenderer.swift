import SwiftUI

/// Full-screen modal overlay. Visibility driven by the `visible` prop.
///
/// Dismiss semantics: the `@dismiss` callback fires only from explicit user
/// actions (close button tap, system swipe-to-dismiss when dismissible).
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
            .nuiModalPresentation(isPresented: visible, onDismiss: {
                // Fired by system swipe-to-dismiss (iOS sheets) or when the
                // parent flips `visible` false via its own action. Intentional:
                // system-driven dismissals still need to notify PHP so the
                // component's boolean stays in sync.
                fireDismiss()
            }) {
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

private extension View {
    /// Present the modal's content over everything else.
    ///
    /// `.fullScreenCover` is the iOS way and does not exist on macOS at all — a
    /// Mac has windows, so covering the screen is not something an app asks for.
    /// The platform's own answer is a sheet: it takes the same
    /// `isPresented` / `onDismiss` / content, it is modal to the window, and
    /// closing it calls `onDismiss` — so the element's contract ("dismiss fires
    /// on an explicit user action, not on PHP flipping `visible`") holds either
    /// way.
    @ViewBuilder
    func nuiModalPresentation<Modal: View>(
        isPresented: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Modal
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: .constant(isPresented), onDismiss: onDismiss, content: content)
        #else
        fullScreenCover(isPresented: .constant(isPresented), onDismiss: onDismiss, content: content)
        #endif
    }
}
