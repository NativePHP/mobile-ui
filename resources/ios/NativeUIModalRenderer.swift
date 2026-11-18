import SwiftUI

/// Full-screen modal overlay. Visibility driven by the `visible` prop.
///
/// Dismiss semantics: the `@dismiss` callback fires only from explicit user
/// actions (the close button tap; a full-screen cover has no swipe-to-dismiss).
/// Programmatic `visible = false` from PHP does NOT fire dismiss — that
/// would double-invoke the callback that just set the flag.
///
/// It slides up, or with `transition="fade"` (or a morph) fades in over the
/// screen and out again (see NativeUIFadingModal).
///
/// Model 3: close icon + container colors come from theme tokens.
struct NativeUIModalRenderer: View {
    let node: NativeUINode

    var body: some View {
        if node.props.getString("transition") == "fade" || !node.props.getString("morph_from").isEmpty {
            NativeUIFadingModal(node: node)
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                // No onDismiss: on a constant binding the cover only goes away
                // because PHP set `visible` to false, so onDismiss could only
                // send that close back to PHP as a dismissal.
                .fullScreenCover(isPresented: .constant(node.props.getBool("visible"))) {
                    NativeUIModalContent(node: node, children: node.children)
                }
        }
    }
}

/// What a modal draws: the close row when it's dismissible, then its
/// children, on the theme's background.
private struct NativeUIModalContent: View {
    let node: NativeUINode
    let children: [NativeUINode]

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let dismissible = node.props.getBool("dismissible", default: true)
        let onDismissCb = node.props.getCallbackId("on_dismiss")
        let nodeId = node.id

        let fireDismiss = {
            if onDismissCb != 0 {
                NativeElementBridge.sendPressEvent(onDismissCb, nodeId: nodeId)
            }
        }

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

            ForEach(children) { child in
                NodeView(node: child).equatable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background.ignoresSafeArea())
        // Contain VoiceOver focus within the presented modal content.
        .accessibilityAddTraits(.isModal)
        .modifier(A11yLabelModifier(label: node.props.getString("a11y_label")))
    }
}

/// A modal that fades in over the screen and out again, rather than
/// sliding. The cover goes up and down with no animation of its own and a
/// clear background, and its content fades.
///
/// With `morph_from` and `morph_to` (the refs of an image on the screen and
/// an image in the modal), a copy of the picture flies between where the
/// two are drawn while the content fades, both real images hidden until it
/// lands (see NativeUIImageMorph). Opening waits a moment for the image in
/// the modal to draw, and just fades if it doesn't, or if the one on the
/// screen isn't on screen. Closing flies back from wherever the image in
/// the modal is drawn then, zoomed or dragged, to whichever image
/// `morph_from` names by then.
///
/// PHP can empty the modal as it closes it, so the content, and the refs to
/// fly between, are what it last showed while it was visible.
private struct NativeUIFadingModal: View {
    let node: NativeUINode

    /// How long a fade or a flight takes.
    private static let duration: TimeInterval = 0.35

    /// How long opening waits for the image in the modal to draw.
    private static let drawWait: TimeInterval = 0.3

    @State private var presented = false
    @State private var shown = false
    @State private var leaving = false
    @State private var flight: NativeUIImageFlight?
    /// A plain fade waiting for the cover's first frame to run from.
    @State private var fadePending = false
    /// Bumped on every open and close, so an old one's completion can tell
    /// it's been overtaken.
    @State private var turn = 0
    @State private var last = Remembered()

    var body: some View {
        let visible = node.props.getBool("visible")
        let remembered = remember(visible: visible)

        Color.clear
            .frame(width: 0, height: 0)
            .fullScreenCover(isPresented: $presented) {
                ZStack {
                    NativeUIModalContent(node: node, children: visible ? node.children : remembered.children)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(!leaving)

                    if let flight {
                        NativeUIImageFlightView(flight: flight)
                            .id(flight.id)
                    }
                }
                .presentationBackground(.clear)
                .onAppear {
                    if fadePending {
                        fadePending = false
                        fadeIn()
                    }
                }
            }
            .onAppear {
                if visible { open() }
            }
            .onChange(of: visible) { _, now in
                if now { open() } else { close() }
            }
    }

    /// What the modal showed while it was visible. A plain reference held in
    /// state, written while the body is read, so keeping it current redraws
    /// nothing.
    private final class Remembered {
        var children: [NativeUINode] = []
        var morphFrom = ""
        var morphTo = ""
    }

    private func remember(visible: Bool) -> Remembered {
        if visible {
            last.children = node.children
            last.morphFrom = node.props.getString("morph_from")
            last.morphTo = node.props.getString("morph_to")
        }
        return last
    }

    private func open() {
        turn += 1
        let thisTurn = turn
        let morph = NativeUIImageMorph.shared
        let from = last.morphFrom
        let to = last.morphTo

        if presented {
            // Back before it had gone: fade up again from where it is.
            leaving = false
            flight = nil
            morph.show([from, to])
            fadeIn()
            return
        }

        leaving = false
        shown = false
        withTransaction(Self.still) { presented = true }

        guard let source = morph.onScreen(from), !to.isEmpty else {
            fadePending = true
            return
        }

        morph.whenDrawn(to, timeout: Self.drawWait) { target in
            guard turn == thisTurn else { return }
            guard let target else {
                fadeIn()
                return
            }
            fly(from: source, to: target, image: target.image, hiding: [from, to], turn: thisTurn) {
                shown = true
            } landed: {
                // The real images draw again under the copy, which is just
                // where they are, and the copy goes a frame later.
                morph.show([from, to])
                DispatchQueue.main.async {
                    if turn == thisTurn { flight = nil }
                }
            }
        }
    }

    private func close() {
        guard presented else { return }
        turn += 1
        let thisTurn = turn
        let morph = NativeUIImageMorph.shared
        let from = last.morphFrom
        let to = last.morphTo
        leaving = true

        // By the time the cover goes there's nothing left on it to see, so
        // however UIKit takes it away doesn't show.
        let dismiss = {
            flight = nil
            withTransaction(Self.still) { presented = false }
            last.children = []
        }

        if let target = morph.onScreen(to), let source = morph.onScreen(from) {
            fly(from: target, to: source, image: target.image, hiding: [from, to], turn: thisTurn) {
                shown = false
            } landed: {
                // The image on the screen draws again under the copy, which
                // is just where it is, and the copy and the cover go a frame
                // later.
                morph.show([from, to])
                DispatchQueue.main.async {
                    if turn == thisTurn { dismiss() }
                }
            }
            return
        }

        withAnimation(.easeIn(duration: Self.duration)) {
            shown = false
        } completion: {
            guard turn == thisTurn else { return }
            dismiss()
        }
    }

    private func fadeIn() {
        withAnimation(.easeOut(duration: Self.duration)) { shown = true }
    }

    /// Flies a copy of the picture from one drawn rect to the other, with
    /// both real images hidden, running `alongside` over the same time.
    private func fly(
        from: NativeUIImageMorph.Drawn,
        to: NativeUIImageMorph.Drawn,
        image: Image,
        hiding refs: [String],
        turn thisTurn: Int,
        alongside: @escaping () -> Void,
        landed: @escaping () -> Void
    ) {
        NativeUIImageMorph.shared.hide(refs)
        flight = NativeUIImageFlight(from: from, to: to, image: image, duration: Self.duration) {
            guard turn == thisTurn else { return }
            landed()
        }
        withAnimation(.smooth(duration: Self.duration)) { alongside() }
    }

    private static var still: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
