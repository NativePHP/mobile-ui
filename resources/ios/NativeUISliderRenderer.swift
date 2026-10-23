import SwiftUI

/// SwiftUI Slider renderer.
///
/// Value binding with echo-prevention (plan K) and sync-mode dispatch
/// (plan L — `native:model.live` / `.blur` / `.debounce.Xms`). All colors
/// resolve from the theme — per-instance color overrides are intentionally
/// not supported (Model 3).
///
/// Dispatch semantics:
///   - `live` (default) — every drag tick fires onChange. Stress-tests the
///     PHP round-trip; great demo of the runtime's responsiveness.
///   - `blur` — onChange fires only when drag ends (onEditingChanged(false)).
///   - `debounce.Xms` — coalesces drag ticks; fires once after N ms of no
///     change, OR immediately on drag end (whichever comes first).
struct NativeUISliderRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var value: Double = 0
    @State private var lastSentValue: Double = 0
    @State private var initialized: Bool = false
    /// True while a finger is on the slider. Server values wait until it lifts.
    @State private var isEditing: Bool = false
    @State private var debounceTask: Task<Void, Never>? = nil

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props

        let serverValue = Double(p.getFloat("value"))
        let min         = Double(p.getFloat("min", default: 0))
        let max         = Double(p.getFloat("max", default: 1))
        let step        = Double(p.getFloat("step"))
        let onChangeCb  = p.getCallbackId("on_change")
        let disabled    = p.getBool("disabled")
        let syncMode    = p.getString("sync_mode", default: "live")
        let debounceMs  = p.getInt("debounce_ms", default: 300)
        let a11yLabel   = p.getString("a11y_label")
        let a11yHint    = p.getString("a11y_hint")

        Group {
            if step > 0 {
                Slider(
                    value: $value, in: min...max, step: step,
                    onEditingChanged: { editing in
                        handleEditingChanged(editing, mode: syncMode, onChangeCb: onChangeCb)
                    }
                )
            } else {
                Slider(
                    value: $value, in: min...max,
                    onEditingChanged: { editing in
                        handleEditingChanged(editing, mode: syncMode, onChangeCb: onChangeCb)
                    }
                )
            }
        }
        .tint(theme.primary)
        .disabled(disabled)
        .onAppear {
            if !initialized {
                value = serverValue
                lastSentValue = serverValue
                initialized = true
            }
        }
        .onDisappear {
            // A drag must never stick: if the slider goes mid-drag, server values apply again.
            isEditing = false
        }
        .onChange(of: serverValue) { _, newServerValue in
            // The finger owns the value during a drag. Without this, a re-render
            // (a poll, a timer) puts the thumb back under the finger.
            guard !isEditing else { return }
            // Echo-prevention: ignore server pushes that match what we sent.
            if abs(newServerValue - lastSentValue) > 0.0001 {
                value = newServerValue
                lastSentValue = newServerValue
            }
        }
        .onChange(of: value) { _, newValue in
            handleLocalChange(newValue, mode: syncMode, debounceMs: debounceMs, onChangeCb: onChangeCb)
        }
        .modifier(A11yLabelModifier(label: a11yLabel))
        .modifier(A11yHintModifier(hint: a11yHint))
        .accessibilityValue(Text(String(format: "%.2f", value)))
    }

    // ─── Dispatch policy ─────────────────────────────────────────────────────

    private func handleLocalChange(_ newValue: Double, mode: String, debounceMs: Int, onChangeCb: Int) {
        switch mode {
        case "blur":
            // Don't dispatch mid-drag. onEditingChanged(false) will flush.
            return

        case "debounce":
            debounceTask?.cancel()
            let captured = newValue
            let delayNanos = UInt64(max(20, debounceMs)) * 1_000_000
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delayNanos)
                if Task.isCancelled { return }
                commit(captured, onChangeCb: onChangeCb)
            }

        default: // "live"
            commit(newValue, onChangeCb: onChangeCb)
        }
    }

    private func handleEditingChanged(_ editing: Bool, mode: String, onChangeCb: Int) {
        isEditing = editing
        // Drag started (editing=true): onChange(of:value) handles ticks, and
        // server values wait (see onChange(of: serverValue)).
        // Drag ended (editing=false): flush any pending / un-sent value.
        guard !editing else { return }
        debounceTask?.cancel()
        debounceTask = nil
        if abs(value - lastSentValue) > 0.0001 {
            commit(value, onChangeCb: onChangeCb)
        }
    }

    private func commit(_ v: Double, onChangeCb: Int) {
        lastSentValue = v
        if onChangeCb != 0 {
            NativeElementBridge.sendSliderChangeEvent(onChangeCb, nodeId: node.id, value: Float(v))
        }
    }
}

// MARK: - Accessibility modifiers (conditional)

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}

private struct A11yHintModifier: ViewModifier {
    let hint: String
    func body(content: Content) -> some View {
        if hint.isEmpty { content }
        else { content.accessibilityHint(hint) }
    }
}
