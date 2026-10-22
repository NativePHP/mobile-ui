import Foundation
import UIKit

/// Screen-wide focus routing for text inputs — the `next-focus` prop.
///
/// Each text input core whose element carries a `ref` registers a closure
/// that asserts its own `@FocusState` (keyed by that ref) on appear, and
/// unregisters on disappear. A submitting field with `next_focus` set asks
/// the registry to run the target's closure, moving the keyboard to that
/// field without any cross-view focus state or ancestor restructuring.
///
/// Main-thread only: every caller is a SwiftUI lifecycle hook or submit
/// handler. Focus is only ever requested from a user-initiated submit on
/// another field — never from server pushes — so the registry cannot steal
/// focus spontaneously.
///
/// Last registration wins: refs are unique per screen by convention (they
/// are the same refs `Native::test()` targets), but two live screens on a
/// navigation stack may reuse one — the most recently appeared field then
/// receives the focus, which is the visible one anyway. Unregistration is
/// token-guarded so a disappearing pushed screen can't tear down the ref
/// it was shadowing.
final class NativeUIFocusRegistry {
    static let shared = NativeUIFocusRegistry()

    private struct Entry {
        let token: UUID
        let focus: () -> Void
        weak var backingField: UITextField?
    }

    private var entries: [String: Entry] = [:]

    /// Register `focus` under `ref`, replacing any previous registration.
    /// Returns the token `unregister` needs.
    func register(_ ref: String, focus: @escaping () -> Void) -> UUID {
        let token = UUID()
        entries[ref] = Entry(token: token, focus: focus)
        return token
    }

    /// Remove the registration for `ref`, but only while it is still the
    /// one identified by `token` — a later registration under the same ref
    /// must survive its predecessor's disappearance.
    func unregister(_ ref: String, token: UUID) {
        if entries[ref]?.token == token {
            entries[ref] = nil
        }
    }

    /// Attach the UIKit text field backing the SwiftUI field registered
    /// under `ref` (found by the return-key interceptor's introspection).
    /// A hop can then be a direct responder handoff — the only transition
    /// that keeps the keyboard perfectly still. Weak: the entry outlives
    /// nothing; a recreated backing re-attaches on its next render.
    func attachBackingField(_ ref: String, field: UITextField) {
        entries[ref]?.backingField = field
    }

    /// Focus the field registered under `ref`. Returns whether a target
    /// existed — a missing target (off-screen, recycled row, typo'd ref)
    /// is a no-op, never a crash.
    ///
    /// Prefers a UIKit responder handoff to the target's backing field:
    /// with no dismissal queued (the return key was intercepted), UIKit
    /// moves the keyboard between fields without any hide/show. The
    /// SwiftUI FocusState closure is the fallback for fields whose
    /// backing hasn't been introspected yet.
    @discardableResult
    func focus(_ ref: String) -> Bool {
        guard let entry = entries[ref] else { return false }
        if let tf = entry.backingField, tf.window != nil, tf.becomeFirstResponder() {
            return true
        }
        entry.focus()
        return true
    }
}
