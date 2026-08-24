import SwiftUI
import UIKit

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

    // Token for this field's `focus_ref` registration (see
    // `NativeUIFocusRegistry`); nil when the element carries no ref.
    @State private var focusRegistryToken: UUID? = nil

    // Stable identity of this field's claim on the shared keyboard
    // accessory bar (pad keyboards only — see NativeUIKeyboardAccessoryBar).
    @State private var accessoryToken = UUID()

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
        let keyboardKind  = p.getString("keyboard")
        let keyboard      = resolveKeyboardType(keyboardKind)
        // Capitalization and autocorrect are derived from `secure` and the
        // keyboard type unless the author overrode them — declaring a field
        // `email` should carry its typing behavior, not just its key layout,
        // and declaring one `secure` should carry the behavior a secret needs.
        let capitalization = resolveAutocapitalization(
            explicit: p.getString("autocapitalize"),
            secure: secure,
            keyboard: keyboardKind
        )
        let autocorrect   = allowsAutocorrection(secure: secure, keyboard: keyboardKind)
        let onChangeCb    = p.getCallbackId("on_change")
        let onSubmitCb    = p.getCallbackId("on_submit")
        let syncMode      = p.getString("sync_mode", default: "live")
        let debounceMs    = p.getInt("debounce_ms", default: 300)
        let keepFocus     = p.getBool("keep_focus_on_submit")
        let submitLabelKind = p.getString("submit_label")
        // Focus chaining (`next-focus`): `focus_ref` is this field's own
        // address in the focus registry (the element's `ref`, surfaced as a
        // prop); `next_focus` is the ref to move the keyboard to on submit.
        let focusRef      = p.getString("focus_ref")
        let nextFocus     = p.getString("next_focus")
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

        // One submit routine for both entry points: the keyboard's return key
        // (`.onSubmit`) and the accessory-bar button below. Reading `text` /
        // `isFocused` inside resolves the live @State values at call time.
        let performSubmit = {
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
            // Focus routing after submit. `next-focus` wins over
            // `keep-focus-on-submit` — moving the keyboard to the chained
            // field IS keeping it up; keepFocus is only the fallback when the
            // target isn't on screen (recycled row, conditional render,
            // typo'd ref).
            //
            // The hop runs TWICE. Synchronously first: focus moving to the
            // target inside the same transaction as the return key's resign
            // reads as focus MOVING between fields, so the keyboard stays up
            // instead of playing a down-and-back-up bounce (what UIKit's
            // becomeFirstResponder-in-shouldReturn always did). Then again
            // async as a safety net: on paths where the system's resign
            // still wins after this handler returns, the re-assert restores
            // focus exactly as the async-only version did — a bounce, but
            // never a lost keyboard. Focusing an already-focused field is a
            // no-op, so the second pass costs nothing when the first stuck.
            if !nextFocus.isEmpty {
                NativeUIFocusRegistry.shared.focus(nextFocus)
                DispatchQueue.main.async {
                    if !NativeUIFocusRegistry.shared.focus(nextFocus) && keepFocus {
                        isFocused = true
                    }
                }
            } else if keepFocus {
                // Chat "send and keep typing": SwiftUI resigns first responder
                // on return by default. Re-assert focus so the keyboard stays
                // up. NOTE: this causes a small keyboard "bounce" on return
                // (resign → refocus) that the send button doesn't have — the
                // smooth fix needs a UIKit-backed field (see notes), not the
                // multiline workaround which mis-sized the field in the flex
                // layout.
                DispatchQueue.main.async { isFocused = true }
            } else {
                // Accessory-button path: unlike the return key, tapping the
                // bar doesn't resign first responder — dismiss explicitly so
                // "Done" behaves like Done. No-op on the return-key path
                // (focus is already gone by the time this runs).
                isFocused = false
            }
        }
        // Pad-style keyboards (number / decimal / phone) have NO return key,
        // so the submit label, `next-focus` chain and `@submit` are physically
        // unreachable from them. Surface the missing key as the shared
        // accessory BAR above the keyboard (NativeUIKeyboardAccessoryBar):
        // this field claims the bar while focused and hands it the same
        // submit path as the return key. Refreshed from body every render so
        // the action never goes stale while focused.
        let padKeyboard = ["number", "decimal", "numberpassword", "phone"].contains(keyboardKind.lowercased())
        let wantsAccessory = padKeyboard && !multiline
            && (onSubmitCb != 0 || !nextFocus.isEmpty || !submitLabelKind.isEmpty)
        let accessoryTitle = accessoryButtonTitle(
            explicit: submitLabelKind, hasSubmit: onSubmitCb != 0, nextFocus: nextFocus
        )
        let _ = refreshAccessoryClaim(wantsAccessory, title: accessoryTitle, perform: performSubmit)

        // Apply `.foregroundColor` (not just `.foregroundStyle`) so the TYPED
        // text adopts `contentColor`. SwiftUI's TextField/SecureField don't
        // reliably pick up `.foregroundStyle` for the input text on older
        // iOS runtimes — `.foregroundColor` on the field itself always works.
        Group {
            if secure {
                // SecureField has no selection binding — caret reporting is
                // intentionally never available for secure fields.
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
                // The iOS 18 `selection:` binding is honored on the vertical
                // (multiline) axis too. Kept as parallel branches so the
                // feature-off path is byte-for-byte the original field.
                if selectionEnabled {
                    TextField(placeholder, text: $text, selection: $selection, axis: .vertical)
                        .lineLimit(lower...upper)
                        .foregroundColor(contentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(lower...upper)
                        .foregroundColor(contentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focused($isFocused)
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
        .textInputAutocapitalization(capitalization)
        .autocorrectionDisabled(!autocorrect)
        .disabled(disabled || readOnly)
        .submitLabel(resolveSubmitLabel(explicit: submitLabelKind, multiline: multiline, hasSubmit: onSubmitCb != 0, nextFocus: nextFocus))
        .onAppear {
            if !initialized {
                text = serverValue
                lastSentValue = serverValue
                initialized = true
            }
            // Make this field focus-addressable. Capturing the FocusState
            // binding keeps the registry free of any view reference.
            if !focusRef.isEmpty {
                let binding = $isFocused
                focusRegistryToken = NativeUIFocusRegistry.shared.register(focusRef) {
                    binding.wrappedValue = true
                }
            }
            // `autofocus`: raise the keyboard on the field the user came to
            // fill. Fires per appearance (a fresh sheet presentation is a
            // fresh appearance); a re-render that moves the prop to an
            // already-mounted field never steals focus. The delay lets a
            // presenting sheet's animation settle — focusing mid-transition
            // is silently dropped by SwiftUI.
            if p.getBool("autofocus") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isFocused = true
                }
            }
        }
        .onDisappear {
            if let token = focusRegistryToken, !focusRef.isEmpty {
                NativeUIFocusRegistry.shared.unregister(focusRef, token: token)
                focusRegistryToken = nil
            }
            NativeUIKeyboardAccessoryState.shared.release(id: accessoryToken)
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
            if focused {
                if wantsAccessory {
                    NativeUIKeyboardAccessoryState.shared.claim(
                        id: accessoryToken, title: accessoryTitle, perform: performSubmit
                    )
                }
                return
            }
            // On blur, flush any pending change — covers both `blur` mode
            // (never dispatched mid-typing) and `debounce` mode (in-flight
            // timer that should commit immediately rather than race with
            // focus loss / keyboard dismiss).
            flushPending(onChangeCb: onChangeCb)
            // Flush any coalesced selection emit immediately on blur so the
            // final caret state isn't stranded in the debounce window.
            if selectionEnabled {
                flushSelection(cb: onSelectionCb)
            }
            NativeUIKeyboardAccessoryState.shared.release(id: accessoryToken)
        }
        .onSubmit {
            performSubmit()
        }
    }

    /// Body-time refresh of this field's accessory-bar claim — keeps the
    /// bar's action and title current while focused (props can change under
    /// a focused field when PHP republishes). No-op unless focused and
    /// accessory-worthy; the state object defers any published change.
    private func refreshAccessoryClaim(_ wants: Bool, title: String, perform: @escaping () -> Void) {
        guard wants, isFocused else { return }
        NativeUIKeyboardAccessoryState.shared.refresh(id: accessoryToken, title: title, perform: perform)
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

/// Submit-key face for the field. The explicit `submit_label` prop wins;
/// unset — or unknown, same policy as `resolveKeyboardType` — derives
/// `.next` when a `next_focus` chain is set (mirroring how capitalization
/// derives from the keyboard type), else keeps the original default:
/// `.done` when `@submit` is wired, `.return` otherwise.
///
/// A multiline field ignores the prop entirely: on the vertical-axis
/// TextField a non-return submit label swaps newline insertion for a submit
/// action, silently taking away the field's reason to be multiline. Android
/// ignores the prop for multiline the same way (`resolveImeAction` in
/// `TextInputShared.kt`) — keep the two in sync.
private func resolveSubmitLabel(explicit: String, multiline: Bool, hasSubmit: Bool, nextFocus: String) -> SubmitLabel {
    if !multiline {
        switch explicit.lowercased() {
        case "next":   return .next
        case "done":   return .done
        case "go":     return .go
        case "search": return .search
        case "send":   return .send
        case "return": return .return
        default:       break
        }
        if !nextFocus.isEmpty { return .next }
    }
    return hasSubmit ? .done : .return
}

/// Title for the keyboard accessory button shown above pad-style keyboards
/// (which have no return key to carry the submit label). Same precedence as
/// `resolveSubmitLabel`: the explicit prop wins, then a `next_focus` chain
/// implies "Next", then `@submit` implies "Done".
private func accessoryButtonTitle(explicit: String, hasSubmit: Bool, nextFocus: String) -> String {
    switch explicit.lowercased() {
    case "next":   return "Next"
    case "done":   return "Done"
    case "go":     return "Go"
    case "search": return "Search"
    case "send":   return "Send"
    case "return": return "Done"
    default:       break
    }
    if !nextFocus.isEmpty { return "Next" }
    return "Done"
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

/// Capitalization for the field. `secure` wins outright; otherwise the
/// explicit `autocapitalize` prop when the author set one, otherwise derived
/// from the keyboard type.
///
/// SwiftUI defaults an untouched TextField to `.sentences`, which is why an
/// email field capitalized its first letter even though `.emailAddress` was
/// applied: `keyboardType` sets the key layout and nothing else. Every keyboard
/// kind whose content is case-sensitive or non-alphabetic therefore has to opt
/// out explicitly.
///
/// A `secure` field is checked FIRST — ahead of the explicit prop, which is the
/// only place in this resolver where the author's word is not final. A password
/// is opaque bytes; there is no reading of `autocapitalize="sentences"` on a
/// secret under which shifting its first character is what the author wanted,
/// and the failure is silent (the field is masked, so the stray capital is
/// invisible until the login is rejected). The element already suppresses
/// selection reporting for secure fields at the source on the same reasoning —
/// some invariants shouldn't be a prop away from being wrong.
///
/// Unknown `autocapitalize` values fall through to the derived behaviour rather
/// than erroring — same policy as `resolveKeyboardType`.
private func resolveAutocapitalization(explicit: String, secure: Bool, keyboard: String) -> TextInputAutocapitalization {
    if secure { return .never }

    switch explicit.lowercased() {
    case "none":       return .never
    case "sentences":  return .sentences
    case "words":      return .words
    case "characters": return .characters
    default:           break
    }

    switch keyboard.lowercased() {
    // Case-sensitive content — capitalizing the first character is always
    // wrong here (an email's local part, a URL's path).
    case "email", "url":
        return .never
    // Numeric keypads have no shift key, so capitalization is moot; `.never`
    // just keeps the state honest if the user swaps to a hardware keyboard.
    case "number", "decimal", "phone", "numberpassword", "password":
        return .never
    default:
        return .sentences
    }
}

/// Whether autocorrect should run. Same reasoning as capitalization: iOS will
/// happily "correct" an email local part or a URL slug into a dictionary word,
/// and the field type is enough to know that's unwanted.
///
/// `secure` is the strongest case of all: a password is by definition not a
/// dictionary word, so every suggestion is a wrong one, and the candidate bar
/// over a masked field is also a place the secret can be shoulder-surfed.
private func allowsAutocorrection(secure: Bool, keyboard: String) -> Bool {
    if secure { return false }

    switch keyboard.lowercased() {
    case "email", "url", "number", "decimal", "phone", "numberpassword", "password":
        return false
    default:
        return true
    }
}
