import SwiftUI

/// Inline draggable bottom pane (`sheet_pane`) — the Maps/Flighty
/// "always-on sheet". Renders inside the screen's layer (floating chrome
/// stays above it), tracks drags continuously, and spring-snaps to the
/// nearest detent on release. The settled detent is reported to PHP via
/// the element's on_change callback; PHP re-publishes it as the `detent`
/// prop so re-renders don't move the pane.
///
/// Height lives in a @StateObject so republished trees (poll frames)
/// never reset an in-progress position; the `detent` prop only moves the
/// pane when its value actually changes (same applied-key pattern as the
/// map camera).
struct NativeUISheetPaneRenderer: View {
    let node: NativeUINode

    @StateObject private var model = SheetPaneModel()
    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let detents = Self.parseDetents(p.getString("detents", default: "200,560,780"))
        let radius = CGFloat(p.getFloat("corner_radius", default: 44))
        let insetX = CGFloat(p.getFloat("inset_x", default: 8))
        let insetBottom = CGFloat(p.getFloat("inset_bottom", default: 8))
        let detentProp = CGFloat(p.getFloat("detent", default: Float(detents.first ?? 200)))
        let changeCb = p.getCallbackId("on_change")

        GeometryReader { geo in
            let paneWidth = max(0, geo.size.width - insetX * 2)
            let maxDetent = detents.last ?? 780

            // Reveal model: content is laid out ONCE at the tallest detent
            // and the animated frame just uncovers more or less of it —
            // real bottom-sheet behavior. Re-flowing content to the live
            // height would make text and flex children shuffle mid-drag.
            //
            // Children go through FlexContainer (not a plain VStack) so
            // EDGE flex semantics — a scroll-view's flex-1, gaps,
            // alignment — behave identically to a regular <column>.
            FlexContainer(
                direction: FlexDirection.column,
                justify: JustifyContent.start,
                align: AlignItems.stretch,
                gap: 0,
                wrap: 0,
                childNodes: node.children
            ) {
                ForEach(node.children) { child in
                    NodeView(node: child).equatable()
                }
            }
            .frame(width: paneWidth, height: maxDetent, alignment: .top)
            .frame(width: paneWidth, height: model.height, alignment: .top)
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .position(
                x: geo.size.width / 2,
                y: geo.size.height - insetBottom - model.height / 2
            )
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if model.dragStartHeight == nil {
                            model.dragStartHeight = model.height
                        }
                        let proposed = (model.dragStartHeight ?? model.height) - value.translation.height
                        model.height = Self.rubberBand(proposed, detents: detents)
                    }
                    .onEnded { value in
                        model.dragStartHeight = nil
                        // Project momentum so a flick advances a detent even
                        // from a short travel distance.
                        let projected = model.height - value.predictedEndTranslation.height + value.translation.height
                        let target = Self.nearestDetent(to: projected, in: detents)

                        // Seed the spring with the RELEASE velocity so the
                        // settle continues the fling instead of restarting
                        // from rest (a zero-velocity spring visibly hitches
                        // on fast swipes). initialVelocity is normalized:
                        // (points/sec) ÷ distance-to-target, clamped so a
                        // violent flick can't overshoot absurdly.
                        let distance = target - model.height
                        let released = -value.velocity.height
                        let initialVelocity = distance.magnitude > 1
                            ? max(-25, min(25, released / distance))
                            : 0
                        withAnimation(.interpolatingSpring(
                            stiffness: 240, damping: 28, initialVelocity: initialVelocity
                        )) {
                            model.height = target
                        }
                        let settledElsewhere = target != model.appliedDetent
                        model.appliedDetent = target
                        // Only report a detent CHANGE — snapping back to the
                        // detent we started from is not one. Report fractional
                        // detents faithfully: truncating `560.5` to `560`
                        // fails the applied-detent equality on the republish
                        // and nudges the pane a frame after every drag.
                        if changeCb != 0 && settledElsewhere {
                            let text = target == target.rounded() ? String(Int(target)) : String(describing: target)
                            NativeElementBridge.sendTextChangeEvent(changeCb, nodeId: node.id, text: text)
                        }
                    }
            )
            .onAppear { model.apply(detentProp, animated: false) }
            .onChange(of: detentProp) { _, newValue in
                model.apply(newValue, animated: true)
            }
        }
        // The tab bar insets the content's safe area; a Flighty-style pane
        // slides BEHIND the floating Liquid Glass bar down to the physical
        // screen edge, so measure and position against the full screen.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private static func parseDetents(_ raw: String) -> [CGFloat] {
        let parsed = raw.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .map { CGFloat($0) }
            .sorted()

        return parsed.isEmpty ? [200, 560] : parsed
    }

    private static func nearestDetent(to height: CGFloat, in detents: [CGFloat]) -> CGFloat {
        detents.min(by: { abs($0 - height) < abs($1 - height) }) ?? height
    }

    /// Clamp with a soft overshoot past the outermost detents, so pulling
    /// beyond the range resists instead of hard-stopping.
    private static func rubberBand(_ proposed: CGFloat, detents: [CGFloat]) -> CGFloat {
        guard let lo = detents.first, let hi = detents.last else { return proposed }
        if proposed > hi {
            return hi + (proposed - hi) * 0.25
        }
        if proposed < lo {
            return lo - (lo - proposed) * 0.25
        }
        return proposed
    }
}

/// Pane height that survives recomposition. `apply` early-returns when the
/// prop value hasn't changed, so republished trees never yank the pane —
/// only a genuinely new PHP-side detent moves it.
final class SheetPaneModel: ObservableObject {
    @Published var height: CGFloat = 0
    var dragStartHeight: CGFloat?
    var appliedDetent: CGFloat = -1

    func apply(_ detent: CGFloat, animated: Bool) {
        guard detent != appliedDetent else { return }
        appliedDetent = detent

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                height = detent
            }
        } else {
            height = detent
        }
    }
}
