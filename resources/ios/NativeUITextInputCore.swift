import SwiftUI
import UIKit

/// Shared inner TextField core for both `outlined-text-input` and
/// `filled-text-input` variants. Handles:
///   - value binding with echo-prevention sync (PHP can update `value` at any
///     time; we avoid clobbering in-flight local edits by tracking the last
///     value we sent out)
///   - `sync_mode` dispatch policy (live | debounce | blur) — controlled by
///     the `native:model` directive modifier chain
///   - secure input; multiline input (TextEditor-backed — the return key
///     always inserts a line break, so submit is send-button-only there)
///   - keyboard type, submit label (single-line only)
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

    // ─── Selection / caret reporting (opt-in via `on_selection_change`) ──────
    //
    // Independent of the value/`sync_mode` machinery above: it never touches
    // `text` / `lastSentValue` / `debounceTask`, and it stays completely dormant
    // (zero emits, no field-init change) unless `on_selection_change` is set on
    // a NON-secure field. See the selection helpers at the bottom of the type.
    //
    // `selection` is bound to the field only when the feature is enabled, so
    // when it's off this stays `nil` forever and its `.onChange` never fires.
    @State private var selection: TextSelection? = nil
    @State private var selectionTask: Task<Void, Never>? = nil
    // Latest caret offsets (unicode-scalar / code-point units) taken from a
    // VALID selection. `text`-change handling only ever clamps these integers
    // to the new length — it never re-reads a possibly-stale `String.Index`.
    @State private var selStart: Int = 0
    @State private var selEnd: Int = 0
    // Trailing-edge coalescing: `pending` is the value the debounce timer will
    // emit (recomputed on every trigger); `lastEmitted` powers the dedupe.
    @State private var pendingSelection: NativeUISelectionPayload? = nil
    @State private var lastEmittedSelection: NativeUISelectionPayload? = nil

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
        let keyboard      = resolveKeyboardType(p.getString("keyboard"))
        let onChangeCb    = p.getCallbackId("on_change")
        let onSubmitCb    = p.getCallbackId("on_submit")
        let syncMode      = p.getString("sync_mode", default: "live")
        let debounceMs    = p.getInt("debounce_ms", default: 300)
        let keepFocus     = p.getBool("keep_focus_on_submit")
        // Selection reporting is opt-in (0/absent ⇒ off) and never applies to
        // secure fields. Read exactly like `on_change` / `debounce_ms` above.
        let onSelectionCb = p.getCallbackId("on_selection_change")
        // PHP only serializes this prop when explicitly configured, so an
        // absent prop and an explicit 0 are indistinguishable — both mean
        // "use the default". Positive values are floored at one frame.
        // Android resolves the same prop identically (`TextInputShared.kt`) —
        // keep the two in sync.
        let selDebounceMs = Self.resolveSelectionDebounceMs(p.getInt("selection_debounce_ms"))
        let selectionEnabled = onSelectionCb != 0 && !secure
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
        let core = Group {
            if secure {
                // SecureField has no selection binding — caret reporting is
                // intentionally never available for secure fields.
                SecureField(placeholder, text: $text)
                    .foregroundColor(contentColor)
                    .focused($isFocused)
            } else if multiline {
                // NOT a vertical-axis TextField: with a hardware keyboard
                // (simulator typed from the Mac keyboard, iPad + external
                // keyboard) Return UNFOCUSES a vertical TextField instead of
                // inserting a newline — confirmed as-designed by Apple DTS
                // (developer.apple.com/forums/thread/760511). TextEditor's
                // return key inserts a line break on every keyboard.
                //
                // The invisible Text mirror re-creates the auto-growing
                // `lineLimit(min...max)` window the vertical TextField had:
                // it sizes the branch (the trailing space keeps a just-typed
                // empty last line measurable — Text collapses a trailing
                // newline on its own), and the editor fills the overlay.
                let lower = max(minLines, 1)
                let upper = maxLines > 0 ? max(maxLines, lower) : max(5, lower)
                Text(text + " ")
                    .lineLimit(lower...upper)
                    .opacity(0)
                    // Sizing-only: without this VoiceOver reads the typed
                    // text twice (mirror + editor).
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay {
                        Group {
                            // The iOS 18 `selection:` binding exists on
                            // TextEditor too. Parallel branches so the
                            // feature-off path carries no selection state.
                            if selectionEnabled {
                                TextEditor(text: $text, selection: $selection)
                            } else {
                                TextEditor(text: $text)
                            }
                        }
                        // Let the variant chrome paint the background.
                        .scrollContentBackground(.hidden)
                        .foregroundColor(contentColor)
                        // Pull back UITextView's internal text-container
                        // padding (5pt line-fragment + ~8pt vertical inset)
                        // so the typed text lines up with the single-line
                        // variants inside the same chrome — and with the
                        // sizing mirror above.
                        .padding(.horizontal, -5)
                        .padding(.vertical, -8)
                        .focused($isFocused)
                    }
                    .overlay(alignment: .topLeading) {
                        // TextEditor has no placeholder slot.
                        if text.isEmpty && !placeholder.isEmpty {
                            Text(placeholder)
                                .foregroundStyle(Color(UIColor.placeholderText))
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                if selectionEnabled {
                    TextField(placeholder, text: $text, selection: $selection)
                        .foregroundColor(contentColor)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .foregroundColor(contentColor)
                        .focused($isFocused)
                }
            }
        }
        .nuiScaledFont(size: textSize, fontName: fontName.isEmpty ? nil : fontName)
        // NOTE: SwiftUI's editable TextField ignores `.lineSpacing` for its
        // typed text (unlike `Text`), so `leading-*` has no visible effect on
        // iOS inputs. Kept for intent / forward-compat; leading works on
        // `<native:text>` and on Android inputs.
        .lineSpacing(lineSpacing)
        .tint(tintColor)
        .keyboardType(keyboard)
        .disabled(disabled || readOnly)
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
                // A programmatic push replaces the field wholesale and drops
                // the caret at the end. Report that immediately, regardless of
                // focus — matching the Android renderers, which flush the same
                // end-caret event from their value-sync effect. Without this,
                // a handler that rewrites the bound model (the mention-
                // typeahead case) sees a follow-up event on Android and
                // nothing on iOS. Emitting here also beats letting the
                // `.onChange(of: text)` path below fire with the STALE cached
                // offsets clamped to the new length.
                if selectionEnabled {
                    emitServerPushSelection(text: newServerValue, cb: onSelectionCb)
                }
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
            // Text edits are also selection triggers. We deliberately do NOT
            // re-read `selection` here (its `String.Index`es can lag a
            // programmatic `text` swap by one render); instead we re-clamp the
            // last known scalar offsets to the new length. When focus is on, the
            // field's own reconciled selection lands via `.onChange(of: selection)`
            // right after and the debounce coalesces both into one emit.
            if selectionEnabled && isFocused {
                scheduleSelectionEmit(text: filtered, cb: onSelectionCb, debounceMs: selDebounceMs)
            }
        }
        .onChange(of: selection) { _, newSelection in
            // Caret moves via tap / arrow keys / selection drag arrive here.
            // A non-nil selection implies the field is focused; a `nil` value
            // is the no-focus state and must never emit.
            guard selectionEnabled, let sel = newSelection else { return }
            guard let (start, end) = offsets(from: sel, in: text) else { return }
            selStart = start
            selEnd = end
            scheduleSelectionEmit(text: text, cb: onSelectionCb, debounceMs: selDebounceMs)
        }
        .onChange(of: isFocused) { _, focused in
            // On blur, flush any pending change — covers both `blur` mode
            // (never dispatched mid-typing) and `debounce` mode (in-flight
            // timer that should commit immediately rather than race with
            // focus loss / keyboard dismiss).
            if !focused {
                flushPending(onChangeCb: onChangeCb)
                // Flush any coalesced selection emit immediately on blur so the
                // final caret state isn't stranded in the debounce window.
                if selectionEnabled {
                    flushSelection(cb: onSelectionCb)
                }
            }
        }
        // Return-key policy — parity with Android. `.onSubmit` must NOT be
        // attached to a multiline (vertical-axis) field: the soft keyboard's
        // return key inserts a newline either way, but with `.onSubmit`
        // attached a HARDWARE keyboard's Return (simulator typed from the Mac,
        // iPad + external keyboard) fires the submit path and swallows the
        // newline. Android multiline behaves the same on purpose: Enter always
        // inserts a line break and `@submit` is only reachable through a
        // dedicated send button. Blur still flushes pending changes above.
        if multiline {
            core
        } else {
            core
                .submitLabel(onSubmitCb != 0 ? .done : .return)
                .onSubmit {
                    // Submit also acts as a commit point — flush pending, then dispatch.
                    flushPending(onChangeCb: onChangeCb)
                    // Selection is flushed BEFORE the submit event so PHP sees the final
                    // caret/selection state ahead of (or alongside) the submit.
                    if selectionEnabled {
                        flushSelection(cb: onSelectionCb)
                    }
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

    // ─── Selection reporting ─────────────────────────────────────────────────
    //
    // Emits over the SAME binary text channel as `on_change`, packing the
    // selection as `"<start>,<end>\u{1F}<text>"` (U+001F unit separator). The
    // offsets are unicode code-point (scalar) counts into the current text.

    /// Convert a `TextSelection` (single or multi-range) to clamped
    /// scalar-offset bounds within `string`. Returns `nil` when the selection
    /// carries no usable range (empty multi-selection / unknown future case),
    /// in which case the caller skips the emit.
    ///
    /// This is the ONLY place we read a `String.Index` from the selection, and
    /// it runs exclusively from `.onChange(of: selection)`, where SwiftUI has
    /// just handed us indices that are valid for the current `text`.
    private func offsets(from selection: TextSelection, in string: String) -> (Int, Int)? {
        switch selection.indices {
        case .selection(let range):
            return (scalarOffset(of: range.lowerBound, in: string),
                    scalarOffset(of: range.upperBound, in: string))
        case .multiSelection(let rangeSet):
            // Multiple discontiguous ranges: span from the lowest start to the
            // highest end (contract: min lower / max upper).
            let ranges = rangeSet.ranges
            guard let lower = ranges.map(\.lowerBound).min(),
                  let upper = ranges.map(\.upperBound).max() else {
                return nil
            }
            return (scalarOffset(of: lower, in: string),
                    scalarOffset(of: upper, in: string))
        @unknown default:
            return nil
        }
    }

    /// Unicode-scalar (code-point) offset of `index` within `string`.
    ///
    /// Scalar count — NOT grapheme count — so a skin-toned 👍🏽 (2 scalars) or a
    /// combining "e"+◌́ (2 scalars) advances the offset by 2, matching the
    /// pinned contract.
    ///
    /// The clamp bounds a momentarily-stale index to `startIndex...endIndex`;
    /// it does NOT guarantee scalar ALIGNMENT (an index pointing into the
    /// middle of a multi-byte sequence stays misaligned). Swift rounds rather
    /// than traps when measuring distance to a misaligned index in the scalar
    /// view, so the worst case is an off-by-one offset, not a crash. On the
    /// normal path — indices SwiftUI just derived from this same string — the
    /// clamp is a no-op.
    private func scalarOffset(of index: String.Index, in string: String) -> Int {
        let scalars = string.unicodeScalars
        let clamped = min(max(index, string.startIndex), string.endIndex)
        return scalars.distance(from: scalars.startIndex, to: clamped)
    }

    /// Default coalescing window for `@selectionChange`, in ms.
    private static let selectionDebounceDefaultMs = 150

    /// Lower bound for an explicitly configured window — one frame at 60fps.
    private static let selectionDebounceFloorMs = 16

    /// Resolve `selection_debounce_ms` to an effective window. `<= 0` (which
    /// includes "prop absent", since PHP only serializes it when configured)
    /// means the default; positive values are floored at one frame, because
    /// every emission costs a bridge frame plus a full PHP component
    /// re-render.
    private static func resolveSelectionDebounceMs(_ raw: Int) -> Int {
        raw > 0 ? max(raw, selectionDebounceFloorMs) : selectionDebounceDefaultMs
    }

    /// Report an end-of-text caret for a programmatic value push, bypassing
    /// the debounce. Sets the cached offsets first so the `.onChange(of: text)`
    /// pass that follows recomputes the identical payload and is dropped by
    /// the dedupe rather than emitting stale offsets.
    private func emitServerPushSelection(text pushedText: String, cb: Int) {
        let count = pushedText.unicodeScalars.count
        selStart = count
        selEnd = count
        pendingSelection = NativeUISelectionPayload(text: pushedText, start: count, end: count)
        flushSelection(cb: cb)
    }

    /// (Re)arm the trailing-edge debounce. Recomputes the payload from the
    /// current text + latest offsets (clamped to `0...scalarCount`, `start ≤
    /// end`) so the timer always emits the most recent state; a fresh trigger
    /// replaces the pending payload and restarts the clock.
    private func scheduleSelectionEmit(text currentText: String, cb: Int, debounceMs: Int) {
        let count = currentText.unicodeScalars.count
        var start = min(max(selStart, 0), count)
        var end = min(max(selEnd, 0), count)
        if start > end { swap(&start, &end) }
        selStart = start
        selEnd = end
        pendingSelection = NativeUISelectionPayload(text: currentText, start: start, end: end)

        selectionTask?.cancel()
        let delayNanos = UInt64(max(0, debounceMs)) * 1_000_000
        selectionTask = Task { @MainActor in
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            if Task.isCancelled { return }
            flushSelection(cb: cb)
        }
    }

    /// Emit the pending selection now (used by the debounce timer, and directly
    /// on blur / before submit). Deduped: a payload equal to the last emitted
    /// `(text, start, end)` is dropped.
    private func flushSelection(cb: Int) {
        selectionTask?.cancel()
        selectionTask = nil
        guard let payload = pendingSelection else { return }
        pendingSelection = nil
        if payload == lastEmittedSelection { return }
        lastEmittedSelection = payload
        if cb != 0 {
            let packed = "\(payload.start),\(payload.end)\u{1F}\(payload.text)"
            NativeElementBridge.sendTextChangeEvent(cb, nodeId: node.id, text: packed)
        }
    }
}

/// Snapshot of a reported selection — the dedupe key and the debounce payload.
private struct NativeUISelectionPayload: Equatable {
    let text: String
    let start: Int
    let end: Int
}

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
