import SwiftUI
import UIKit

/// Holds the keyboard up through a `next-focus` hop.
///
/// SwiftUI cannot chain focus between two text fields without a visible
/// keyboard dip: the return key's resign and the target's focus are
/// processed as separate operations — even a screen-scoped shared
/// FocusState written atomically inside `onSubmit` still dips (verified
/// on device; the engine does not coalesce across a submit). UIKit never
/// had this problem, because the keyboard only dismisses when NO
/// responder holds it — `becomeFirstResponder` inside
/// `textFieldShouldReturn` is a responder HANDOFF.
///
/// So do exactly that. At hop start an invisible, zero-frame `UITextField`
/// takes first responder synchronously (handoff #1 — keyboard stays up),
/// SwiftUI then focuses the target on its own schedule (handoff #2 —
/// keyboard stays up), and the bridge removes itself. If the target never
/// claims focus (recycled row, conditional render, typo'd ref) the bridge
/// resigns after a grace period, dropping the keyboard exactly like a
/// failed hop always did — the user is never left typing into an
/// invisible field.
final class NativeUIKeyboardBridge {
    static let shared = NativeUIKeyboardBridge()

    private var field: UITextField?

    /// Bumped on every `hold` so an in-flight `settle` from a previous hop
    /// can never tear down a newer hold (fast serial hops).
    private var generation = 0

    private init() {}

    /// Take first responder synchronously. Keyboard type and autocorrect
    /// mirror the SOURCE field so the held keyboard keeps its exact layout
    /// (chains are homogeneous in practice; a differing target just morphs
    /// on handoff #2, as it would anyway).
    func hold(keyboardType: UIKeyboardType, autocorrect: Bool) {
        generation += 1
        guard let window = keyWindow() else { return }
        let f = field ?? UITextField(frame: .zero)
        f.keyboardType = keyboardType
        f.autocorrectionType = autocorrect ? .yes : .no
        f.spellCheckingType = autocorrect ? .yes : .no
        field = f
        if f.superview !== window {
            window.addSubview(f)
        }
        f.becomeFirstResponder()
    }

    /// Schedule the post-hop cleanup: if the bridge still holds first
    /// responder after the grace period the target never took over — let
    /// the keyboard go. Either way the field leaves the window.
    func settle(after delay: TimeInterval = 0.35) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen, let f = self.field else { return }
            if f.isFirstResponder {
                f.resignFirstResponder()
            }
            f.removeFromSuperview()
            self.field = nil
        }
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
