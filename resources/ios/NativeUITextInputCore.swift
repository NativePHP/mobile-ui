import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared inner TextField core for both `outlined-text-input` and
/// `filled-text-input` variants. Handles:
///   - value binding with echo-prevention sync (PHP can update `value` at any
///     time; we avoid clobbering in-flight local edits by tracking the last
///     value we sent out)
///   - `sync_mode` dispatch policy (live | debounce | blur) — controlled by
///     the `native:model` directive modifier chain
///   - secure / multiline input
///   - keyboard type, submit label
///   - disabled / readOnly state
///   - onChange / onSubmit callbacks
///
/// Variant-specific chrome (label, icons, border/fill, supporting text) lives
/// in the variant renderers that wrap this view.
struct NativeUITextInputCore: View {
    let node: NativeUINode
    let textSize: CGFloat
    let contentColor: Color
    let tintColor: Color

    @State private var text: String = ""
    @State private var lastSentValue: String = ""
    @State private var initialized: Bool = false
    @State private var debounceTask: Task<Void, Never>? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        let p = node.props
        let placeholder   = p.getString("placeholder")
        let serverValue   = p.getString("value")
        let secure        = p.getBool("secure")
        let multiline     = p.getBool("multiline")
        let maxLength     = p.getInt("max_length")
        let maxLines      = p.getInt("max_lines")
        let minLines      = p.getInt("min_lines")
        let disabled      = p.getBool("disabled")
        let readOnly      = p.getBool("read_only")
        let keyboard      = p.getString("keyboard")
        let onChangeCb    = p.getCallbackId("on_change")
        let onSubmitCb    = p.getCallbackId("on_submit")
        let syncMode      = p.getString("sync_mode", default: "live")
        let debounceMs    = p.getInt("debounce_ms", default: 300)
        let keepFocus     = p.getBool("keep_focus_on_submit")
        let fontName      = p.getString("font_name")
        let lineSpacing   = NativeUIFontResolver.lineSpacing(
            px: p.getFloat("line_height_px"),
            mult: p.getFloat("line_height"),
            fontSize: textSize,
            fontName: fontName
        )

        // Apply `.foregroundColor` (not just `.foregroundStyle`) so the TYPED
        // text adopts `contentColor`. SwiftUI's TextField/SecureField don't
        // reliably pick up `.foregroundStyle` for the input text on older
        // iOS runtimes — `.foregroundColor` on the field itself always works.
        Group {
            if secure {
                SecureField(placeholder, text: $text)
                    .foregroundColor(contentColor)
                    .focused($isFocused)
            } else if multiline {
                // A vertical-axis TextField reports a ~0 intrinsic width when
                // empty and won't expand to fill an ancestor's `maxWidth:
                // .infinity` the way a single-line field does — so without this
                // explicit fill it collapses to its content (just the icon).
                // `min-lines` reserves visible height up front (a textarea
                // that LOOKS like a textarea before you type); `max-lines`
                // caps growth. Clamp so a min above the max still renders.
                let lower = max(minLines, 1)
                let upper = maxLines > 0 ? max(maxLines, lower) : max(5, lower)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(lower...upper)
                    .foregroundColor(contentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .foregroundColor(contentColor)
                    .focused($isFocused)
            }
        }
        .nuiChromelessField()
        .nuiScaledFont(size: textSize, fontName: fontName.isEmpty ? nil : fontName)
        // NOTE: SwiftUI's editable TextField ignores `.lineSpacing` for its
        // typed text (unlike `Text`), so `leading-*` has no visible effect on
        // iOS inputs. Kept for intent / forward-compat; leading works on
        // `<native:text>` and on Android inputs.
        .lineSpacing(lineSpacing)
        .tint(tintColor)
        .nuiKeyboardType(keyboard)
        .disabled(disabled || readOnly)
        .submitLabel(onSubmitCb != 0 ? .done : .return)
        .onAppear {
            if !initialized {
                text = serverValue
                lastSentValue = serverValue
                initialized = true
            }
        }
        .onChange(of: serverValue) { _, newServerValue in
            // Only sync from server when the incoming value differs from what
            // we last sent. Matching == it's an echo of our own change; ignore
            // to avoid cursor jumps / clobbering in-flight edits.
            if newServerValue != lastSentValue {
                text = newServerValue
                lastSentValue = newServerValue
                // Send-BUTTON path (no `onSubmit`): a send clears the draft to
                // empty. Keep the keyboard up by re-asserting focus. Opt-in via
                // `keep-focus-on-submit`; only on a clear-to-empty so ordinary
                // programmatic value pushes don't grab focus.
                if keepFocus && newServerValue.isEmpty {
                    DispatchQueue.main.async { isFocused = true }
                }
            }
        }
        .onChange(of: text) { _, newValue in
            let filtered = maxLength > 0 ? String(newValue.prefix(maxLength)) : newValue
            if filtered != newValue { text = filtered }
            handleLocalChange(filtered, mode: syncMode, debounceMs: debounceMs, onChangeCb: onChangeCb)
        }
        .onChange(of: isFocused) { _, focused in
            // On blur, flush any pending change — covers both `blur` mode
            // (never dispatched mid-typing) and `debounce` mode (in-flight
            // timer that should commit immediately rather than race with
            // focus loss / keyboard dismiss).
            if !focused {
                flushPending(onChangeCb: onChangeCb)
            }
        }
        .onSubmit {
            // Submit also acts as a commit point — flush pending, then dispatch.
            flushPending(onChangeCb: onChangeCb)
            if onSubmitCb != 0 {
                NativeElementBridge.sendSubmitEvent(onSubmitCb, nodeId: node.id, text: text)
            }
            // Chat "send and keep typing": SwiftUI resigns first responder on
            // return by default. Re-assert focus so the keyboard stays up. NOTE:
            // this causes a small keyboard "bounce" on return (resign → refocus)
            // that the send button doesn't have — the smooth fix needs a
            // UIKit-backed field (see notes), not the multiline workaround which
            // mis-sized the field in the flex layout.
            if keepFocus {
                DispatchQueue.main.async { isFocused = true }
            }
        }
    }

    // ─── Dispatch policy ─────────────────────────────────────────────────────

    private func handleLocalChange(_ value: String, mode: String, debounceMs: Int, onChangeCb: Int) {
        switch mode {
        case "blur":
            // Don't dispatch mid-typing. `lastSentValue` stays anchored to
            // the last committed value so the echo-prevention check still
            // protects against programmatic server pushes that match the
            // committed state.
            return

        case "debounce":
            // Cancel any in-flight timer and schedule a fresh one. First
            // keystroke wins a fresh N ms budget; each subsequent keystroke
            // resets it. Final value is committed when the timer fires OR
            // when the field blurs (whichever comes first).
            debounceTask?.cancel()
            let captured = value
            let delayNanos = UInt64(max(50, debounceMs)) * 1_000_000
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delayNanos)
                if Task.isCancelled { return }
                commit(captured, onChangeCb: onChangeCb)
            }

        default: // "live"
            commit(value, onChangeCb: onChangeCb)
        }
    }

    private func flushPending(onChangeCb: Int) {
        debounceTask?.cancel()
        debounceTask = nil
        if text != lastSentValue {
            commit(text, onChangeCb: onChangeCb)
        }
    }

    private func commit(_ value: String, onChangeCb: Int) {
        lastSentValue = value
        if onChangeCb != 0 {
            NativeElementBridge.sendTextChangeEvent(onChangeCb, nodeId: node.id, text: value)
        }
    }
}

// MARK: - Keyboard type
//
// `keyboardType` is a UIKit-only modifier: the concept is a software keyboard
// that the OS chooses a layout for, and a Mac has a hardware one. Applied
// through a modifier of our own rather than inline so the field above stays
// platform-neutral, and so the string→enum mapping — the part that is genuinely
// iOS-specific — is the only thing that has to disappear on macOS.
//
// Not a lost feature on the Mac: there is nothing for it to do there. The prop
// keeps arriving from PHP and is ignored, which is what `keyboard` already means
// on a platform with no software keyboard.

private extension View {
    /// Strip the platform's own text-field chrome, where it has any.
    ///
    /// The variant renderers wrapping this view draw the border, the fill and
    /// the corner radius themselves — that is what makes an outlined field look
    /// outlined and a bare one look bare. On iOS a plain `TextField` has no
    /// chrome to begin with, so there is nothing to strip. AppKit's does: macOS
    /// gives it a bezel and a focus ring, which land *inside* the renderer's
    /// border and read as two nested boxes, one of them the wrong shape.
    ///
    /// `.plain` is not "less styled on macOS", it is the same starting point iOS
    /// already gives — which is the only way one renderer can own its appearance
    /// on both.
    func nuiChromelessField() -> some View {
        #if os(macOS)
        return textFieldStyle(.plain)
        #else
        return self
        #endif
    }

    func nuiKeyboardType(_ kind: String) -> some View {
        #if canImport(UIKit)
        return keyboardType(resolveKeyboardType(kind))
        #else
        return self
        #endif
    }
}

#if canImport(UIKit)
/// Keyboard resolution — accepts string hints ("email", "number", etc.) that
/// map to UIKeyboardType. Unknown/empty falls through to default.
private func resolveKeyboardType(_ kind: String) -> UIKeyboardType {
    switch kind.lowercased() {
    case "number":         return .numberPad
    case "email":          return .emailAddress
    case "phone":          return .phonePad
    case "url":            return .URL
    case "decimal":        return .decimalPad
    case "numberpassword": return .numberPad
    default:               return .default
    }
}
#endif
