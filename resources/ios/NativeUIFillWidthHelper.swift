import SwiftUI

/// SwiftUI primitives like `Button`, `Toggle`, `Picker`, `TextField`,
/// `Slider`, `Stepper`, etc. ignore outer `.frame(maxWidth: .infinity)`
/// — they size to their label's intrinsic content regardless of any
/// frame wrapping them. `NodeLayoutModifier` correctly applies the
/// full-width frame at the NodeView level, but the inner primitive
/// paints small inside that frame.
///
/// The fix has to live INSIDE the renderer for each affected primitive:
/// apply `.frame(maxWidth: .infinity)` to the primitive's own view
/// when the node's layout says `widthMode == .fill`. This helper
/// centralizes the check so every renderer can opt in with one line.
///
/// Usage:
///
///     Button(action: action) { content }
///         .buttonStyle(.borderedProminent)
///         .fillWidthIfRequested(node)
///
/// Compose doesn't have this problem — Material 3 widgets honor
/// `Modifier.fillMaxWidth()` from their modifier chain directly, so
/// `NodeLayoutModifier`'s `Modifier.fillMaxWidth()` flows through.
extension View {
    func fillWidthIfRequested(_ node: NativeUINode) -> some View {
        modifier(FillWidthIfRequestedModifier(widthMode: node.layout?.widthMode))
    }
}

/// `SizeMode` in this codebase is a static-Int container (not a Swift
/// enum with cases), so `widthMode` is plain `Int?` and the constant
/// is `SizeMode.fill` (Int = 2). Avoid `.fill` shorthand because Swift
/// will infer it as SwiftUI's `ContentMode.fill` and the build breaks.
private struct FillWidthIfRequestedModifier: ViewModifier {
    let widthMode: Int?

    func body(content: Content) -> some View {
        if widthMode == SizeMode.fill {
            content.frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

/// A `Menu` that is an *affordance* rather than a control — its label is
/// already the whole of what the user should see.
///
/// The two platforms disagree about what a bare `Menu` looks like, and the
/// disagreement is not cosmetic. On iOS a `Menu` is invisible until tapped: the
/// label is drawn exactly as given. On macOS the default menu style is a
/// **pull-down button** — a bordered box with a chevron — because that is what a
/// menu in the content area usually is on a Mac. Applied to a list row's
/// trailing ellipsis, that turned every row of `/explore/menus` into a row with
/// a full pop-up button sitting in it.
///
/// So macOS gets the borderless style and no indicator, which draws the label
/// and nothing else, and iOS is left completely alone. This is only for menus
/// whose label carries its own affordance (an ellipsis glyph, a styled
/// pressable). A menu that should look like a Mac pull-down button — one built
/// from a `<button :menu>` — must NOT use this: it wants the chevron.
extension View {
    @ViewBuilder
    func nuiCompactMenu() -> some View {
        #if os(macOS)
        // `.fixedSize()` as well as the style: a macOS `Menu` is a control, and
        // a control takes all the width it is offered. In a list row's trailing
        // slot that is whatever the headline left over, which both moves the
        // glyph away from the end of the row and widens the pop-up to match.
        self.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        #else
        self
        #endif
    }
}
