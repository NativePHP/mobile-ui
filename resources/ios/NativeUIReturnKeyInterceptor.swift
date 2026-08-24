import SwiftUI
import UIKit

/// Dip-free `next-focus` chaining, the way every production framework does
/// it (React Native, Flutter, Compose all converged here).
///
/// SwiftUI queues the keyboard dismissal as part of handling the return
/// key ITSELF, before `.onSubmit` runs — and since iOS 17 the keyboard is
/// out-of-process, so a queued hide cannot be cancelled by anything the
/// submit handler does (focus writes, shared FocusState, even a UIKit
/// becomeFirstResponder — all tried, all dipped). The only way to keep
/// the keyboard still is to make sure a dismissal is NEVER queued:
/// intercept `textFieldShouldReturn` on the UIKit text field backing the
/// SwiftUI TextField, run the submit path ourselves, move first
/// responder straight to the target's backing field, and return `false`
/// — exactly React Native's `blurOnSubmit={false}` implementation.
///
/// Wiring: `ReturnKeyInterceptorAnchor` rides in the field's
/// `.background`. From there it finds the backing `UITextField`, wraps
/// SwiftUI's delegate in `NativeUIReturnKeyProxy` (forwarding everything
/// except `textFieldShouldReturn`), registers the backing field with the
/// focus registry so hops become plain responder handoffs, and re-checks
/// the hook on every SwiftUI update (SwiftUI may reinstall its
/// delegate). Fields with no chain forward return-key handling to
/// SwiftUI untouched — stock submit + dismissal.

/// Per-field mutable channel between the SwiftUI view (which recomputes
/// its submit closure and chain state every render) and the long-lived
/// UIKit proxy. Read at return-key time, so it can never go stale.
final class NativeUIReturnKeyBox {
    /// Whether the return key should be intercepted (a `next-focus`
    /// chain exists on a single-line field).
    var chains = false

    /// The field's full submit path — flush, submit event, focus hop.
    var perform: () -> Void = {}
}

/// Forwarding delegate wrapper. Everything SwiftUI's coordinator
/// implements keeps working; only the return key is rerouted.
final class NativeUIReturnKeyProxy: NSObject, UITextFieldDelegate {
    weak var original: UITextFieldDelegate?
    var box: NativeUIReturnKeyBox?

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let box, box.chains {
            box.perform()
            // `false` = no editingDidEndOnExit, no SwiftUI submit
            // machinery, and crucially NO queued keyboard dismissal.
            return false
        }
        if let original, original.responds(to: #selector(UITextFieldDelegate.textFieldShouldReturn(_:))) {
            return original.textFieldShouldReturn?(textField) ?? true
        }
        return true
    }
}

/// Invisible zero-size anchor placed in the field's `.background` —
/// the standard introspection seam between a SwiftUI view and its UIKit
/// backing.
struct ReturnKeyInterceptorAnchor: UIViewRepresentable {
    let box: NativeUIReturnKeyBox
    let focusRef: String

    func makeUIView(context: Context) -> IntrospectionView {
        let view = IntrospectionView()
        view.isUserInteractionEnabled = false
        view.box = box
        view.focusRef = focusRef
        return view
    }

    func updateUIView(_ view: IntrospectionView, context: Context) {
        view.box = box
        view.focusRef = focusRef
        // Deferred: never mutate UIKit delegates mid-SwiftUI-update, and
        // give SwiftUI a beat to (re)attach its own machinery first.
        DispatchQueue.main.async { view.hook() }
    }

    final class IntrospectionView: UIView {
        var box: NativeUIReturnKeyBox?
        var focusRef: String = ""

        private var proxy: NativeUIReturnKeyProxy?
        private weak var hooked: UITextField?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.hook() }
        }

        /// Find the backing field, install (or repair) the delegate
        /// proxy, and register the backing field for direct-responder
        /// focus hops. Idempotent; called on every SwiftUI update
        /// because SwiftUI can reinstall its delegate at any render.
        func hook() {
            guard window != nil, let tf = findTextField() else { return }

            if !focusRef.isEmpty {
                NativeUIFocusRegistry.shared.attachBackingField(focusRef, field: tf)
            }

            let p = proxy ?? NativeUIReturnKeyProxy()
            proxy = p
            p.box = box
            if tf.delegate !== p {
                p.original = tf.delegate
                tf.delegate = p
            }
            hooked = tf
        }

        /// The anchor sits in the field's `.background`, so the nearest
        /// UITextField above/beside us IS our field. Climb a few
        /// ancestors, searching each level's subtree; the first (i.e.
        /// closest) match wins, which keeps sibling rows out of reach.
        private func findTextField() -> UITextField? {
            var ancestor = superview
            for _ in 0..<6 {
                guard let a = ancestor else { return nil }
                if let tf = Self.firstTextField(in: a) { return tf }
                ancestor = a.superview
            }
            return nil
        }

        private static func firstTextField(in view: UIView) -> UITextField? {
            if let tf = view as? UITextField { return tf }
            for sub in view.subviews {
                if let tf = firstTextField(in: sub) { return tf }
            }
            return nil
        }
    }
}
