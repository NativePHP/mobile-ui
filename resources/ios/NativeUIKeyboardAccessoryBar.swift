import SwiftUI

/// The Next/Done affordance for pad-style keyboards (number / decimal /
/// phone), which have no return key of their own.
///
/// This replaces a `.toolbar(placement: .keyboard)` implementation. iOS 26
/// renders keyboard-placement toolbar items as a floating Liquid Glass
/// capsule sitting directly on the keyboard (and drops them from the
/// accessibility tree on 26.1), UIKit's `inputAccessoryView` no longer
/// attaches seamlessly to the redesigned keyboard, and SwiftUI never shows
/// keyboard toolbars inside a bare `.sheet` at all. Apple's own guidance for
/// the padding complaints is to show the affordance as a bottom safe-area
/// bar while the field is focused — which is exactly what this does: the
/// focused field publishes its submit affordance to the shared state below,
/// and a HOST (the bottom-sheet content root, or the screen root via
/// `NativeRootHostRegistry`) pins a full-width, theme-colored bar above the
/// keyboard with `.safeAreaInset(edge: .bottom)`. Keyboard avoidance keeps
/// it riding the keyboard's top edge on every iOS version, with no glass.
final class NativeUIKeyboardAccessoryState: ObservableObject {
    static let shared = NativeUIKeyboardAccessoryState()

    /// The bar's visible state — nil hides it. Only identity and title are
    /// published; the ACTION lives in `perform` (below, non-published) so
    /// the focused field can refresh it on every render without triggering
    /// view updates. It can genuinely change mid-focus: toggling the Yaniv
    /// caller re-renders the focused field with a different `next_focus`.
    struct Info: Equatable {
        let id: UUID
        let title: String
    }

    @Published private(set) var info: Info?

    /// Presented bottom sheets. The screen-root host hides its bar while a
    /// sheet is up — the sheet hosts its own copy, and the covered screen
    /// shouldn't inset for a bar nobody can see.
    @Published var sheetDepth: Int = 0

    private var perform: () -> Void = {}

    /// Monotonic claim counter — a deferred release only lands when no
    /// claim happened after it was scheduled (see `release`).
    private var claimSeq = 0

    /// Called when a field gains focus (or its accessory title changes).
    func claim(id: UUID, title: String, perform: @escaping () -> Void) {
        claimSeq += 1
        self.perform = perform
        if info?.id != id || info?.title != title {
            info = Info(id: id, title: title)
        }
    }

    /// Refresh the action from the focused field's body on every render.
    /// The closure swap is silent; a title change republishes async (body
    /// must not mutate published state synchronously).
    func refresh(id: UUID, title: String, perform: @escaping () -> Void) {
        guard info?.id == id else { return }
        self.perform = perform
        if info?.title != title {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.info?.id == id else { return }
                self.info = Info(id: id, title: title)
            }
        }
    }

    /// Called on blur / disappear. Deferred one runloop and guarded both
    /// ways: a field losing focus because ANOTHER field claimed the bar
    /// must not tear the new claim down, and during a pad-keyboard hop
    /// the release must not remove the bar for a frame between the old
    /// field's blur and the new field's claim (a visible 44pt safe-area
    /// jump that reads as a keyboard dip).
    func release(id: UUID) {
        let seq = claimSeq
        DispatchQueue.main.async { [weak self] in
            guard let self, self.claimSeq == seq, self.info?.id == id else { return }
            self.info = nil
            self.perform = {}
        }
    }

    func submit() {
        perform()
    }
}

/// Wraps a content root and pins the accessory bar above the keyboard while
/// a field has claimed it. Transparent pass-through (no inset, no cost)
/// while no claim is active.
struct NativeUIKeyboardAccessoryHost<Content: View>: View {
    /// Set on the screen-root instance — its bar yields while any bottom
    /// sheet is presented (the sheet's own host takes over).
    var hidesUnderSheets: Bool = false
    @ViewBuilder var content: Content

    @ObservedObject private var state = NativeUIKeyboardAccessoryState.shared
    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
            if let info = state.info, !(hidesUnderSheets && state.sheetDepth > 0) {
                let theme = themeStore.resolve(for: colorScheme)
                HStack {
                    Spacer()
                    Button {
                        state.submit()
                    } label: {
                        Text(info.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.primary)
                            // A generous hit target on a 44pt bar.
                            .padding(.horizontal, 4)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.surface)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.outlineVariant)
                        .frame(height: 0.5)
                }
            }
        }
    }
}
