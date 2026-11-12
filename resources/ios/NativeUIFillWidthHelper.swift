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
///
/// The host gives a node a width of its own for `w-full`, for a fixed or
/// percentage width (`w-[120px]`, `w-1/2`), and for flex growth (`flex-1`
/// in a row), so the primitive fills it in each of those cases.
extension View {
    func fillWidthIfRequested(_ node: NativeUINode) -> some View {
        modifier(FillWidthIfRequestedModifier(fills: hostAllocatesWidth(node.layout)))
    }
}

private func hostAllocatesWidth(_ layout: NodeLayout?) -> Bool {
    guard let layout else { return false }
    if layout.widthMode == SizeMode.fill || layout.flexGrow > 0 { return true }
    return (layout.widthMode == SizeMode.fixed || layout.widthMode == SizeMode.percent)
        && layout.width > 0
}

/// `SizeMode` in this codebase is a static-Int container (not a Swift
/// enum with cases), so `widthMode` is plain `Int?` and the constant
/// is `SizeMode.fill` (Int = 2). Avoid `.fill` shorthand because Swift
/// will infer it as SwiftUI's `ContentMode.fill` and the build breaks.
private struct FillWidthIfRequestedModifier: ViewModifier {
    let fills: Bool

    func body(content: Content) -> some View {
        if fills {
            content.frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}
