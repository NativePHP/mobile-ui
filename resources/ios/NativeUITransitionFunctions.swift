import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - NativeUI.Transition.* bridge functions
//
// PHP signals an inter-screen transition via:
//   nativephp_call('NativeUI.Transition.Set', json_encode(['type' => 'slide_from_right']));
//
// On iOS the Set handler stages `pendingTransition` + `navigationPending` on
// the shared NativeUIBridge. The next nativephp_element_publish() flips
// `screenKey`, which causes SwiftUI to remount the tree renderer with
// the staged transition.
//
// On macOS there is no such machinery — and this file is contributed there
// anyway, deliberately. See `Set` below.

enum NativeUITransitionFunctions {

    /// `NativeUI.Transition.Set` — stage a transition for the next published tree.
    ///
    /// ## macOS: answered, and answered with "no"
    ///
    /// A desktop window has no screen-transition stage. There is no
    /// `screenKey` to flip and no remount for an `AnyTransition` to attach to:
    /// the host renders whatever tree was last published, in place. So there is
    /// nothing here to implement *yet*, and a plausible-looking cross-fade
    /// invented at this layer would be worse than nothing — it would animate a
    /// window's whole contents, sidebar included, for a navigation the platform
    /// draws instantly.
    ///
    /// It is still registered, and that is the point. An unregistered name is
    /// indistinguishable from a packaging mistake: the desktop plugin compiler
    /// warns about it on every install, and PHP's `nativephp_call()` returns
    /// null exactly as it would for a function nobody wrote. Answering makes
    /// the state explicit on both sides — `handled: true, applied: false` with
    /// the reason — and turns "did my plugin install correctly?" into
    /// "this platform doesn't animate screen swaps yet", which is a different
    /// and much shorter conversation.
    ///
    /// If desktop grows transitions, this is where they arm.
    class Set: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            let requested = (parameters["type"] as? String) ?? "fade"

            #if os(macOS)
            NativeUITransitionSupport.reportUnanimated(requested)

            return [
                "success": true,
                "applied": false,
                "reason": "macOS renders a published tree in place — there is no screen transition stage to arm.",
            ]
            #else
            // Reduce Motion: swap directional/scaling transitions for a plain
            // cross-fade. The Edge\Transition → AnyTransition mapping lives in
            // core (`nativeScreenTransition(for:)`), so this staging point is
            // where the substitution happens — "none" is left untouched since
            // it's already motionless.
            let type = (UIAccessibility.isReduceMotionEnabled && requested != "none" && requested != "fade")
                ? "fade"
                : requested

            if Thread.isMainThread {
                NativeUIBridge.shared.setNavigationPending(transition: type)
            } else {
                DispatchQueue.main.sync {
                    NativeUIBridge.shared.setNavigationPending(transition: type)
                }
            }

            return ["success": true]
            #endif
        }
    }
}

#if os(macOS)
/// One log line per transition type asked for, not per navigation.
///
/// A screen that navigates back and forth would otherwise write a line per
/// press for something that is working as designed. Same discipline the host's
/// own `UnhandledTypes` / `UnsupportedGestures` reporters use, and for the same
/// reason: the first occurrence is information, the fortieth is noise.
enum NativeUITransitionSupport {
    private static let lock = NSLock()
    private static var reported: Swift.Set<String> = []

    static func reportUnanimated(_ type: String) {
        guard type != "none" else { return }

        lock.lock()
        let isNew = reported.insert(type).inserted
        lock.unlock()

        guard isNew else { return }

        NSLog("NativeUI.Transition.Set: '\(type)' acknowledged and not animated — macOS publishes a tree in place, so there is no screen transition to arm.")
    }
}
#endif

// The `Edge\Transition` → SwiftUI `AnyTransition` mapping that ContentView uses
// now lives in core (`nativeScreenTransition(for:)`), so core can swap native
// trees without depending on this plugin. This file keeps only the
// `NativeUI.Transition.Set` bridge function, which stages the value PHP sends.
