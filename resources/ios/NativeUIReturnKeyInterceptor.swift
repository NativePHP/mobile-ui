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

/// Invisible anchor placed in the field's `.background` —
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
                // Never wrap another anchor's proxy. Two proxies holding
                // each other as `original` forward `responds(to:)` back
                // and forth until the stack overflows, the first time UIKit
                // asks the field's delegate anything.
                let current = tf.delegate
                p.original = (current as? NativeUIReturnKeyProxy)?.original ?? current
                tf.delegate = p
            }
            hooked = tf
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // findTextField() matches by frame, so a hook that ran before
            // layout found nothing. Try again once there's a frame.
            if hooked == nil {
                DispatchQueue.main.async { [weak self] in self?.hook() }
            }
        }

        /// The anchor sits in the field's `.background`, so it has the
        /// field's frame, and our field is the UITextField under its
        /// centre. Climb a few ancestors, searching each level's subtree.
        /// Matching by frame keeps other fields out of reach, even when
        /// SwiftUI hosts them all in the same view: a multiline field is a
        /// UITextView, so without it the nearest UITextField would be some
        /// other input's.
        private func findTextField() -> UITextField? {
            let frame = convert(bounds, to: nil)
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            var ancestor = superview
            for _ in 0..<6 {
                guard let a = ancestor else { return nil }
                if let tf = Self.textField(in: a, under: centre) { return tf }
                ancestor = a.superview
            }
            return nil
        }

        private static func textField(in view: UIView, under point: CGPoint) -> UITextField? {
            if let tf = view as? UITextField {
                return tf.convert(tf.bounds, to: nil).insetBy(dx: -1, dy: -1).contains(point) ? tf : nil
            }
            for sub in view.subviews {
                if let tf = textField(in: sub, under: point) { return tf }
            }
            return nil
        }
    }
}
