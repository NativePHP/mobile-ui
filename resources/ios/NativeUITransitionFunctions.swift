import Foundation
import SwiftUI
import UIKit

// MARK: - NativeUI.Transition.* bridge functions
//
// PHP signals an inter-screen transition via:
//   nativephp_call('NativeUI.Transition.Set', json_encode(['type' => 'slide_from_right']));
//
// `view_transition` additionally morphs elements sharing a `transition-name`
// across the swap; the mapping and the morph both live in core.
//
// The Set handler stages `pendingTransition` + `navigationPending` on the
// shared NativeUIBridge. The next nativephp_element_publish() flips
// `screenKey`, which causes SwiftUI to remount the tree renderer with
// the staged transition.

enum NativeUITransitionFunctions {

    /// `NativeUI.Transition.Set` — stage a transition for the next published tree.
    class Set: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            let requested = (parameters["type"] as? String) ?? "fade"

            // Reduce Motion: swap directional/scaling transitions for a plain
            // cross-fade. The Edge\Transition → AnyTransition mapping lives in
            // core (`nativeScreenTransition(for:)`), so this staging point is
            // where the substitution happens — "none" is left untouched since
            // it's already motionless.
            // Reduce Motion also catches `view_transition`: substituting a
            // plain fade drops the shared-element morph along with the
            // directional motion, since the morph IS the movement that
            // setting asks us not to make. `none` and `fade` are already
            // motionless and pass through untouched.
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
        }
    }
}

// The `Edge\Transition` → SwiftUI `AnyTransition` mapping that ContentView uses
// now lives in core (`nativeScreenTransition(for:)`), so core can swap native
// trees without depending on this plugin. This file keeps only the
// `NativeUI.Transition.Set` bridge function, which stages the value PHP sends.
