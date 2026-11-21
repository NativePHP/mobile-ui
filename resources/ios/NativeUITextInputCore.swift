import SwiftUI
import UIKit

/// Shared inner TextField core for both `outlined-text-input` and
/// `filled-text-input` variants. Handles:
///   - value binding with echo-prevention sync (PHP can update `value` at any
///     time; we avoid clobbering in-flight local edits by tracking the last
///     value we sent out)
///   - `sync_mode` dispatch policy (live | debounce | blur) — controlled by
///     the `native:model` directive modifier chain
///   - secure input, with an optional in-field reveal toggle; multiline
///     input (TextEditor-backed — the return key always inserts a line
///     break, so submit is send-button-only there)
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

    /// Whether this variant has room to draw the `revealable` eye INSIDE the
    /// field. The chrome variants (outlined, filled) pass true; the chromeless
    /// one does not, because its whole contract is that it draws no decoration
    /// of its own — an author using it supplies their own trailing control.
    /// Defaulted so the bare renderer's call site stays as it was, and so the
    /// prop is honored on exactly the same two variants on both platforms
    /// (Android's toggle lives in the M3 `trailingIcon` slot, which the
    /// chromeless `BasicTextField` doesn't have).
    var supportsRevealToggle: Bool = false

    /// Optional placeholder override (for example, the outlined variant's
    /// `on-input` token). Otherwise use a muted field text colour so a custom
    /// surface stays readable even when it differs from the system appearance.
    var placeholderColor: Color? = nil

    @State private var text: String = ""
    @State private var lastSentValue: String = ""
    /// Values sent to PHP whose re-render hasn't come back yet. See
    /// `NativeUITextEchoTracker` for why `lastSentValue` alone isn't enough.
    @State private var echoes = NativeUITextEchoTracker()
    @State private var initialized: Bool = false
    @State private var debounceTask: Task<Void, Never>? = nil
    /// Whether a `secure` field is currently showing its contents.
    ///
    /// Local `@State` on purpose, and that is the whole safety argument for
    /// this feature: toggling it never crosses the bridge, so it cannot
    /// republish the tree, cannot perturb `text` / `lastSentValue`, cannot
    /// trip the `sync_mode` state machine, and cannot move the caret. Reveal
    /// state is also the kind of thing that must not be persisted or
    /// round-tripped anywhere near a password.
    @State private var revealed: Bool = false
    @FocusState private var isFocused: Bool
    /// This field's identity in `KeyboardFocusPolicy`. A blur only releases
    /// the policy while this field still owns it, so a blur that lands after
    /// the next field's focus can't clobber that field's state.
    @State private var focusToken = UUID()

    /// The enclosing vertical `<scroll-view>`'s proxy, published by
    /// `NativeUIScrollViewRenderer`. Nil everywhere there isn't one — sheets,
    /// modals, non-scrolling screens, and bottom-anchored chat logs, which run
    /// their own keyboard policy — and nil means this field does not scroll.
    @Environment(\.nativeUIScrollProxy) private var scrollProxy

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

    // What the UITextView behind a multiline field says about its text,
    // which sizes the field (see NativeUITextEditorSizer).
    @State private var editorSize = NativeUITextEditorSize()

    // Reports where a multiline field draws its caret (`@caretChange`). A
    // reference the sizer hands the UITextView to; dormant unless
    // `on_caret_change` is set on a multiline, non-secure field.
    @State private var caretReporter = NativeUICaretReporter()

    // Stable identity of this field's claim on the shared keyboard
    // accessory bar (pad keyboards only — see NativeUIKeyboardAccessoryBar).
    @State private var accessoryToken = UUID()

    // Channel to the UIKit return-key interceptor (see
    // NativeUIReturnKeyInterceptor.swift) — refreshed every render so the
    // proxy always runs the CURRENT submit path and chain state.
    @State private var returnKeyBox = NativeUIReturnKeyBox()

    var body: some View {
        let p = node.props
        let placeholder   = p.getString("placeholder")
        let resolvedPlaceholderColor = placeholderColor ?? contentColor.opacity(0.6)
        let prompt        = Text(placeholder).foregroundColor(resolvedPlaceholderColor)
        let serverValue   = p.getString("value")
        let secure        = p.getBool("secure")
        let multiline     = p.getBool("multiline")
        let maxLength     = p.getInt("max_length")
        let maxLines      = p.getInt("max_lines")
        let minLines      = p.getInt("min_lines")
        let disabled      = p.getBool("disabled")
        let readOnly      = p.getBool("read_only")
        // The in-field eye. Only on a secure field, only where the variant has
        // chrome to host it, and only while the field is interactive — there
        // is nothing to reveal in a field the user cannot type into, and a
        // disabled control that still responds to taps is its own bug.
        let revealToggle  = supportsRevealToggle
            && secure
            && p.getBool("revealable")
            && !(disabled || readOnly)
        // A secure field is masked unless the user has revealed it.
        let masked        = secure && !revealed
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
        // What the field holds, for AutoFill. Nil when the author didn't say,
        // and nil applies nothing at all — see `TextContentTypeModifier`.
        let contentType   = resolveTextContentType(p.getString("content_type"))
        let onChangeCb    = p.getCallbackId("on_change")
        let onSubmitCb    = p.getCallbackId("on_submit")
        let syncMode      = p.getString("sync_mode", default: "live")
        let debounceMs    = p.getInt("debounce_ms", default: 300)
        let keepFocus     = p.getBool("keep_focus_on_submit")
        let submitLabelKind = p.getString("submit_label")
        let autofocus     = p.getBool("autofocus")
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
        // `selection`: where the caret goes when PHP pushes a new value, in
        // code points (-1: PHP didn't say). The element serializes the pair
        // whenever the attribute is declared, null included, so whether the
        // field can be told where its caret goes never flips between renders.
        let placesSelection = p.has("selection_start") && !secure
        let placedStart   = p.getInt("selection_start", default: -1)
        let placedEnd     = p.getInt("selection_end", default: -1)
        // The field binds `selection` when it reports it or PHP places it.
        // Decided by props that hold still, because flipping it swaps the
        // field for a new one and drops the keyboard.
        // `@caretChange`: where a multiline field draws its caret. It needs
        // the selection bound too, since a caret move is what moves it.
        let onCaretCb     = p.getCallbackId("on_caret_change")
        let caretEnabled  = onCaretCb != 0 && multiline && !secure
        // `h-full` / `fill` on a multiline field (`fills_height`): as tall as
        // its parent makes it, scrolling its own text, rather than as tall as
        // its lines. `min-lines` is still the least it shows.
        let fillsHeight   = multiline && p.getBool("fills_height")
        let selectionBound = selectionEnabled || placesSelection || caretEnabled
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
                // With the return key intercepted (no dismissal queued),
                // this is a plain responder handoff to the target's backing
                // UITextField — the keyboard stays perfectly still. The
                // async pass is the safety net for a target whose backing
                // isn't introspected yet.
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
        let _ = syncReturnKeyBox(chains: !nextFocus.isEmpty && !multiline, perform: performSubmit)
        let _ = caretReporter.configure(callbackId: caretEnabled ? onCaretCb : 0, nodeId: node.id, debounceMs: selDebounceMs)

        // Apply `.foregroundColor` (not just `.foregroundStyle`) so the TYPED
        // text adopts `contentColor`. SwiftUI's TextField/SecureField don't
        // reliably pick up `.foregroundStyle` for the input text on older
        // iOS runtimes — `.foregroundColor` on the field itself always works.
        let core = Group {
            if secure {
                // SecureField has no selection binding — caret reporting is
                // intentionally never available for secure fields. That holds
                // for the revealed branch too: `selectionEnabled` is gated on
                // `!secure`, so an unmasked password still reports nothing.
                if masked {
                    SecureField(placeholder, text: $text, prompt: prompt)
                        .foregroundColor(contentColor)
                        .focused($isFocused)
                } else {
                    // SecureField has no unmasked mode, so revealing means
                    // swapping in a plain TextField. `multiline` is ignored on
                    // a secure field in both branches, as before.
                    TextField(placeholder, text: $text, prompt: prompt)
                        .foregroundColor(contentColor)
                        .focused($isFocused)
                }
            } else if multiline {
                // NOT a vertical-axis TextField: with a hardware keyboard
                // (simulator typed from the Mac keyboard, iPad + external
                // keyboard) Return UNFOCUSES a vertical TextField instead of
                // inserting a newline — confirmed as-designed by Apple DTS
                // (developer.apple.com/forums/thread/760511). TextEditor's
                // return key inserts a line break on every keyboard.
                //
                // The editor is sized by the UITextView behind it (see
                // NativeUITextEditorSizer): as tall as its own text, in whole
                // lines of its own line height, from min-lines up to
                // max-lines, and then it scrolls. An invisible Text mirror
                // used to size it, but Text and UITextView lay a custom
                // font's lines out at different heights, so the cap was never
                // a whole number of the editor's lines. Past max-lines the
                // editor scrolled the caret line to the bottom of a frame
                // that held, say, 5.4 lines, and the top line showed cut in
                // half (more or less, depending on the Dynamic Type size).
                // The text view's own insets are taken off as well, so
                // nothing it scrolls is drawn outside the frame.
                let lower = max(minLines, 1)
                let upper = maxLines > 0 ? max(maxLines, lower) : max(5, lower)
                Group {
                    // The iOS 18 `selection:` binding exists on
                    // TextEditor too. Parallel branches so the
                    // feature-off path carries no selection state.
                    if selectionBound {
                        TextEditor(text: $text, selection: $selection)
                    } else {
                        TextEditor(text: $text)
                    }
                }
                // Let the variant chrome paint the background.
                .scrollContentBackground(.hidden)
                .foregroundColor(contentColor)
                // Filling, the field takes the height it's given and never
                // less than `min-lines`; `max-lines` doesn't cap it.
                .modifier(NativeUITextEditorFrame(
                    fills: fillsHeight,
                    height: editorSize.height(minLines: lower, maxLines: upper, fallbackLineHeight: textSize * 1.3),
                    minHeight: editorSize.height(minLines: lower, maxLines: lower, fallbackLineHeight: textSize * 1.3)
                ))
                .background(NativeUITextEditorSizer(size: $editorSize, caret: caretReporter))
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    // TextEditor has no placeholder slot. Match the prompt
                    // used by the single-line and secure fields.
                    if text.isEmpty && !placeholder.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(resolvedPlaceholderColor)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                if selectionBound {
                    TextField(placeholder, text: $text, selection: $selection, prompt: prompt)
                        .foregroundColor(contentColor)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text, prompt: prompt)
                        .foregroundColor(contentColor)
                        .focused($isFocused)
                }
            }
        }
        .nuiScaledFont(size: textSize, fontName: fontName.isEmpty ? nil : fontName)
        // Invisible introspection anchor: finds the UIKit field backing
        // this TextField, reroutes its return key through `returnKeyBox`,
        // and registers the backing field for direct responder handoffs.
        .background(ReturnKeyInterceptorAnchor(box: returnKeyBox, focusRef: focusRef))
        // NOTE: SwiftUI's editable TextField ignores `.lineSpacing` for its
        // typed text (unlike `Text`), so `leading-*` has no visible effect on
        // iOS inputs. Kept for intent / forward-compat; leading works on
        // `<native:text>` and on Android inputs.
        .lineSpacing(lineSpacing)
        .tint(tintColor)
        .keyboardType(keyboard)
        .textInputAutocapitalization(capitalization)
        .autocorrectionDisabled(!autocorrect)
        .modifier(TextContentTypeModifier(contentType: contentType))
        .disabled(disabled || readOnly)
        // Scroll target for `scrollIntoView()` below. `node.id` is already the
        // ForEach identity of every node in the tree, so it is stable across
        // republishes; and because it is applied to the view `body` returns
        // rather than to this struct, it cannot reset the `@State` above.
        .id(node.id)
        .onAppear {
            if !initialized {
                text = serverValue
                lastSentValue = serverValue
                echoes.reset(serverValue: serverValue)
                initialized = true

                // First appearance only: a later re-render must not steal
                // focus back from wherever the user has since moved it.
                // Deferred a runloop because @FocusState does not take
                // while the view is still being installed.
                if autofocus && !disabled && !readOnly {
                    DispatchQueue.main.async { isFocused = true }
                }
            }
            // Make this field focus-addressable. Capturing the FocusState
            // binding keeps the registry free of any view reference. This
            // closure is the fallback hop — the registry prefers a direct
            // responder handoff to the backing UITextField attached by the
            // return-key interceptor, which is what keeps the keyboard up.
            if !focusRef.isEmpty {
                let binding = $isFocused
                focusRegistryToken = NativeUIFocusRegistry.shared.register(focusRef) {
                    binding.wrappedValue = true
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
            // Only sync from server when the incoming value is not an echo of
            // something we sent. PHP re-renders once per change event, so with
            // fast typing several echoes are in flight and an EARLIER one can
            // land after the user has typed more. Comparing only against
            // `lastSentValue` would let that stale echo overwrite the newer
            // text, which is how letters went missing.
            if echoes.receive(newServerValue) && newServerValue != lastSentValue {
                text = newServerValue
                lastSentValue = newServerValue
                // A programmatic push replaces the field wholesale and drops
                // the caret at the end, unless PHP said where it goes
                // (`selection`), in which case it goes there.
                let scalarCount = newServerValue.unicodeScalars.count
                var placed = (scalarCount, scalarCount)
                if placesSelection && placedStart >= 0 {
                    placed = placeSelection(start: placedStart, end: placedEnd, in: newServerValue)
                }
                // Report the new caret immediately, regardless of focus —
                // matching the Android renderers, which flush the same event
                // from their value-sync effect. Without this, a handler that
                // rewrites the bound model (the mention-typeahead case) sees
                // a follow-up event on Android and nothing on iOS. Emitting
                // here also beats letting the `.onChange(of: text)` path
                // below fire with the STALE cached offsets clamped to the new
                // length.
                if selectionEnabled {
                    emitServerPushSelection(text: newServerValue, start: placed.0, end: placed.1, cb: onSelectionCb)
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
            if caretEnabled && isFocused {
                caretReporter.schedule()
            }
        }
        .onChange(of: selection) { _, newSelection in
            // Caret moves via tap / arrow keys / selection drag arrive here.
            // A non-nil selection implies the field is focused; a `nil` value
            // is the no-focus state and must never emit.
            if caretEnabled && newSelection != nil {
                caretReporter.schedule()
            }
            guard selectionEnabled, let sel = newSelection else { return }
            guard let (start, end) = offsets(from: sel, in: text) else { return }
            selStart = start
            selEnd = end
            scheduleSelectionEmit(text: text, cb: onSelectionCb, debounceMs: selDebounceMs)
        }
        .onChange(of: isFocused) { _, focused in
            // Lets interactive taps elsewhere honor this field's
            // keep-focus-on-submit, and gives press dispatch a
            // flush hook so a tap-committed autocorrection's
            // change, and the caret's last move, reach PHP first
            // (mobile-air #335).
            if focused {
                KeyboardFocusPolicy.fieldFocused(focusToken, keepsFocus: keepFocus) {
                    // The caret goes first, as on Android, so a press that
                    // reads it (picking a mention) sees where it is now.
                    if selectionEnabled {
                        flushSelection(cb: onSelectionCb)
                    }
                    flushPending(onChangeCb: onChangeCb)
                }
                if wantsAccessory {
                    NativeUIKeyboardAccessoryState.shared.claim(
                        id: accessoryToken, title: accessoryTitle, perform: performSubmit
                    )
                }
            } else {
                KeyboardFocusPolicy.fieldBlurred(focusToken)
            }
            // On blur, flush any pending change — covers both `blur` mode
            // (never dispatched mid-typing) and `debounce` mode (in-flight
            // timer that should commit immediately rather than race with
            // focus loss / keyboard dismiss).
            if caretEnabled {
                // Focused, the caret is reported afresh even where it was
                // last time; blurred, a pending report is dropped, since
                // there's no caret to place anything by.
                caretReporter.focusChanged(focused)
            }
            if !focused {
                flushPending(onChangeCb: onChangeCb)
                // Flush any coalesced selection emit immediately on blur so the
                // final caret state isn't stranded in the debounce window.
                if selectionEnabled {
                    flushSelection(cb: onSelectionCb)
                }
                NativeUIKeyboardAccessoryState.shared.release(id: accessoryToken)
            } else {
                scrollIntoView()
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
        //
        // `secure` wins over `multiline` when the field is built above, so a
        // secure field is a single-line SecureField and keeps its submit path.
        //
        // Grouped so the reveal-toggle modifier below has a single view to
        // attach to, whichever branch was taken.
        Group {
            if multiline && !secure {
                core
            } else {
                core
                    .submitLabel(resolveSubmitLabel(explicit: submitLabelKind, multiline: multiline, hasSubmit: onSubmitCb != 0, nextFocus: nextFocus))
                    .onSubmit {
                        performSubmit()
                    }
            }
        }
        // Appended rather than woven in: when the toggle is off this modifier
        // returns its content untouched, so every field that doesn't ask for
        // an eye keeps the exact view tree it had.
        .modifier(RevealToggleModifier(
            enabled: revealToggle,
            revealed: $revealed,
            isFocused: $isFocused,
            textSize: textSize,
            contentColor: contentColor
        ))
        // A field popped off screen while focused gets no blur, so release
        // the policy here rather than leave it holding this view's flush
        // closure. Last in the chain so it sits outside the reveal toggle,
        // whose SecureField / TextField swap is not the field leaving.
        .onDisappear { KeyboardFocusPolicy.fieldBlurred(focusToken) }
    }

    /// Body-time refresh of the return-key interceptor's channel — the
    /// proxy reads it at key-press time, so the submit closure and chain
    /// state can never go stale under republishes.
    private func syncReturnKeyBox(chains: Bool, perform: @escaping () -> Void) {
        returnKeyBox.chains = chains
        returnKeyBox.perform = perform
    }

    /// Body-time refresh of this field's accessory-bar claim — keeps the
    /// bar's action and title current while focused (props can change under
    /// a focused field when PHP republishes). No-op unless focused and
    /// accessory-worthy; the state object defers any published change.
    private func refreshAccessoryClaim(_ wants: Bool, title: String, perform: @escaping () -> Void) {
        guard wants, isFocused else { return }
        NativeUIKeyboardAccessoryState.shared.refresh(id: accessoryToken, title: title, perform: perform)
    }

    // ─── Keyboard avoidance ──────────────────────────────────────────────────

    /// Ask the enclosing `<scroll-view>` to bring this field into view.
    ///
    /// SwiftUI already shrinks the screen by the keyboard height, but that
    /// only guarantees the field is somewhere in the SCROLLABLE CONTENT — not
    /// that it is on screen. On a chat composer pinned to the bottom the two
    /// amount to the same thing, which is why nothing needed this before; on a
    /// login form the password field sits mid-page and a shrunk viewport
    /// leaves it exactly where it was, under the keyboard.
    ///
    /// Deferred past the keyboard's own presentation so the scroll runs
    /// against the already-shrunk viewport. Centering against the full height
    /// first would put the field in the middle of a screen that is about to
    /// lose its bottom half — i.e. back under the keyboard. The delay is a
    /// little longer than the ~0.25s the system animates the keyboard in.
    ///
    /// Runs on focus rather than on `keyboardWillShow`, because moving from
    /// one field to the next never re-shows the keyboard and is exactly when
    /// this is needed. Where there is no proxy — sheets, modals, fixed
    /// screens, bottom-anchored scroll views — this is a no-op.
    private func scrollIntoView() {
        guard let scrollProxy else { return }

        let id = node.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusScrollDelay) {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollProxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// How long to wait after focus before scrolling, in seconds.
    private static let focusScrollDelay: TimeInterval = 0.35

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
            echoes.sent(value)
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

    /// Report the caret a programmatic value push left, bypassing the
    /// debounce. Sets the cached offsets first so the `.onChange(of: text)`
    /// pass that follows recomputes the identical payload and is dropped by
    /// the dedupe rather than emitting stale offsets.
    private func emitServerPushSelection(text pushedText: String, start: Int, end: Int, cb: Int) {
        selStart = start
        selEnd = end
        pendingSelection = NativeUISelectionPayload(text: pushedText, start: start, end: end)
        flushSelection(cb: cb)
    }

    /// Put the caret (or a selection) where PHP's `selection` prop says, in
    /// the value PHP just pushed. Offsets are code points, clamped to the
    /// text and rounded down to a character boundary, since a caret can't sit
    /// inside a flag or a skin-toned emoji. Returns the offsets it used.
    ///
    /// Set again on the next runloop turn: the field takes the pushed text in
    /// the same update, and UIKit moves the caret to the end when its text is
    /// replaced, which can land after this selection did.
    private func placeSelection(start: Int, end: Int, in value: String) -> (Int, Int) {
        let count = value.unicodeScalars.count
        let lower = characterIndex(atScalarOffset: min(max(start, 0), count), in: value)
        let upper = characterIndex(atScalarOffset: min(max(end, start, 0), count), in: value)
        let placed = TextSelection(range: lower..<max(lower, upper))
        selection = placed
        DispatchQueue.main.async {
            if text == value { selection = placed }
        }
        return (scalarOffset(of: lower, in: value), scalarOffset(of: max(lower, upper), in: value))
    }

    /// The `String.Index` for a code-point offset into `string`, moved back to
    /// the start of the character it falls inside.
    private func characterIndex(atScalarOffset offset: Int, in string: String) -> String.Index {
        let scalars = string.unicodeScalars
        var index = scalars.index(scalars.startIndex, offsetBy: offset)
        while index > string.startIndex && String.Index(index, within: string) == nil {
            index = scalars.index(before: index)
        }
        return index
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

/// Tells an echo of our own change apart from a value PHP actually set.
///
/// Every change event makes PHP re-render, and the tree it publishes carries
/// the value from THAT event. When keystrokes arrive faster than the round
/// trip, several of those renders are in flight at once. The field used to
/// remember only the newest value it sent, so the echo of an older keystroke
/// looked like a real server change and replaced everything typed since
/// ("Buy milk" saved as "Buyilk").
///
/// PHP handles events one at a time and in order, so echoes come back in the
/// order they were sent, though the renderer may skip some when trees arrive
/// faster than it draws. Matching an incoming value against the queue and
/// dropping everything up to it handles both. A value that isn't in the queue
/// is something PHP chose (clearing the field after "Add", say) and is applied
/// as before.
struct NativeUITextEchoTracker {
    /// Unacknowledged values, oldest first.
    private(set) var inFlight: [String] = []
    /// The newest value PHP has published for this field.
    private var serverValue: String = ""

    /// Bounds the queue for a field whose model PHP never publishes back.
    static let limit = 64

    mutating func reset(serverValue: String) {
        inFlight.removeAll()
        self.serverValue = serverValue
    }

    /// Record a value just sent to PHP.
    mutating func sent(_ value: String) {
        // With nothing in flight PHP already holds this value, so its echo
        // won't change the published tree and would never be seen. Leaving it
        // out of the queue stops it from later masking a real push of the
        // same value.
        if inFlight.isEmpty && value == serverValue { return }
        inFlight.append(value)
        if inFlight.count > Self.limit {
            inFlight.removeFirst(inFlight.count - Self.limit)
        }
    }

    /// Record a newly published server value. Returns true when it should be
    /// applied to the field, false when it is an echo of our own change.
    mutating func receive(_ value: String) -> Bool {
        serverValue = value
        if let index = inFlight.firstIndex(of: value) {
            inFlight.removeFirst(index + 1)
            return false
        }
        inFlight.removeAll()
        return true
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
    case "none", "never", "off": return .never
    case "sentences", "on":        return .sentences
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

/// The `content_type` prop → `UITextContentType`, for AutoFill. Tokens are
/// HTML's `autocomplete` vocabulary, normalized to kebab-case by the element.
///
/// This is what declares a login form's credential pair to iOS: a `username`
/// field beside a `password` one. Without it iOS has no pair to fill, which is
/// how a secure field filled as the partner of another field could be written
/// in UIKit without SwiftUI's `text` binding ever seeing the value
/// (NativePHP/mobile-air#422).
///
/// Unknown and empty values return nil — same policy as `resolveKeyboardType`.
private func resolveTextContentType(_ kind: String) -> UITextContentType? {
    switch kind.lowercased() {
    case "username":      return .username
    case "email":         return .emailAddress
    case "password":      return .password
    case "new-password":  return .newPassword
    case "one-time-code": return .oneTimeCode
    default:              return nil
    }
}

/// Applies `.textContentType` only when the author declared one.
///
/// Deliberately not `.textContentType(nil)` for the unset case. That is not
/// guaranteed to be a no-op: SwiftUI may assign its own content type to a
/// `SecureField` internally, and an explicit nil applied over it would change
/// the AutoFill behavior of every existing password field. Returning `content`
/// untouched keeps each field that doesn't set the prop exactly as it was.
private struct TextContentTypeModifier: ViewModifier {
    let contentType: UITextContentType?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let contentType {
            content.textContentType(contentType)
        } else {
            content
        }
    }
}

/// Places the reveal ("eye") control inside the field's own chrome, so it sits
/// where the trailing icon sits rather than as a separate Show / Hide control
/// next to the input — which is what an app has to build today, and which
/// costs a bridge round-trip and a republish on every tap.
///
/// Disabled, this returns `content` unchanged: no HStack, no wrapper, nothing
/// added to the view tree. Every existing field therefore lays out exactly as
/// it did.
private struct RevealToggleModifier: ViewModifier {
    let enabled: Bool
    @Binding var revealed: Bool
    var isFocused: FocusState<Bool>.Binding
    let textSize: CGFloat
    let contentColor: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            HStack(spacing: 6) {
                content
                Button {
                    // Read focus BEFORE the swap: flipping `revealed` changes
                    // which branch of the field is built, and SwiftUI treats
                    // SecureField and TextField as different views, so the
                    // one that had first responder is torn down and focus is
                    // dropped. Re-assert it on the next runloop turn — after
                    // the new field exists — or the keyboard drops away on
                    // every tap of the eye.
                    let wasFocused = isFocused.wrappedValue
                    revealed.toggle()
                    if wasFocused {
                        DispatchQueue.main.async { isFocused.wrappedValue = true }
                    }
                } label: {
                    Image(systemName: revealed ? "eye.slash.fill" : "eye.fill")
                        .nuiScaledFont(size: max(13, textSize - 2))
                        .foregroundStyle(contentColor.opacity(0.85))
                        // Deliberately NOT `.nuiMinTapTarget()`. That puts a
                        // `minHeight: 44` on the icon, and this HStack sits
                        // INSIDE the field's content — the variant renderer adds
                        // its own vertical padding around the whole thing — so a
                        // 44pt floor here makes a revealable field far taller
                        // than a plain one. Measured on a login form: 42.7pt for
                        // the email field, 64.7pt for the password field beside
                        // it. Half again as tall, and it reads as a layout bug.
                        //
                        // `maxHeight: .infinity` fills the row rather than
                        // demanding a height, so the field keeps exactly the
                        // height it had before it grew an eye (re-measured at
                        // 40.7pt, matching the same field with the toggle off).
                        // The tap target is still >= 44 wide by the full height
                        // of the field, and `contentShape` keeps all of that
                        // tappable instead of just the glyph.
                        .frame(minWidth: 44, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Announce the ACTION the tap performs, not the current state.
                // VoiceOver reads this as "Show password, button".
                .accessibilityLabel(revealed ? "Hide password" : "Show password")
            }
        } else {
            content
        }
    }
}

/// What the UITextView behind a multiline field reports about its text: how
/// tall it is, and the height of one of its lines.
struct NativeUITextEditorSize: Equatable {
    var contentHeight: CGFloat = 0
    var lineHeight: CGFloat = 0
    var lineSpacing: CGFloat = 0

    /// The field's height: its text's lines, at least `minLines` and at most
    /// `maxLines`, each the text view's own line height. Before the text view
    /// has reported, `minLines` of an estimated line.
    func height(minLines: Int, maxLines: Int, fallbackLineHeight: CGFloat) -> CGFloat {
        guard lineHeight > 0 else {
            return CGFloat(minLines) * fallbackLineHeight
        }

        let step = lineHeight + lineSpacing
        let lines = Int(((contentHeight + lineSpacing) / step).rounded())
        let shown = CGFloat(min(max(lines, minLines), maxLines))

        return shown * lineHeight + (shown - 1) * lineSpacing
    }
}

/// Finds the UITextView behind a multiline field's TextEditor, takes its text
/// container insets off, and reports its content height and line height
/// whenever they change, so the field is sized by the view that draws its
/// text rather than by a guess at it. It sits in the editor's `.background`,
/// so it has the editor's frame, and the text view is the one under its
/// centre.
struct NativeUITextEditorSizer: UIViewRepresentable {
    @Binding var size: NativeUITextEditorSize
    /// Told about the text view, and about every scroll and layout of it,
    /// so `@caretChange` can say where the caret is drawn.
    var caret: NativeUICaretReporter? = nil

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.report = { new in if size != new { size = new } }
        probe.caret = caret
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.report = { new in if size != new { size = new } }
        probe.caret = caret
        DispatchQueue.main.async { probe.hook() }
    }

    final class Probe: UIView {
        var report: ((NativeUITextEditorSize) -> Void)?
        weak var caret: NativeUICaretReporter?
        private weak var textView: UITextView?
        private var observation: NSKeyValueObservation?
        private var offsetObservation: NSKeyValueObservation?
        private var lastSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            // Matching by frame finds nothing before there is one.
            if textView == nil {
                DispatchQueue.main.async { [weak self] in self?.hook() }
            } else if bounds.size != lastSize, let tv = textView, tv.isFirstResponder {
                // The field changes height a moment after its text does. When
                // the text shrinks (a smaller text size, say), the text view
                // has already pulled its scroll back to fit the old height,
                // which leaves the caret's line below the new one.
                DispatchQueue.main.async { tv.scrollRangeToVisible(tv.selectedRange) }
            }
            if bounds.size != lastSize {
                caret?.schedule()
            }
            lastSize = bounds.size
        }

        func hook() {
            guard window != nil, let tv = findTextView() else { return }

            if textView !== tv {
                textView = tv
                observation = tv.observe(\.contentSize, options: [.new]) { [weak self] tv, _ in
                    DispatchQueue.main.async {
                        self?.send(tv)
                        // The text was laid out again: the caret may sit on
                        // another line now, without having moved in the text.
                        self?.caret?.schedule()
                    }
                }
                // The field scrolling its text moves the caret on screen.
                offsetObservation = tv.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.caret?.schedule() }
                }
            }

            caret?.textView = tv
            send(tv)
        }

        /// SwiftUI can put the insets back when it updates the editor, so
        /// they come off again before every report.
        private func send(_ tv: UITextView) {
            if tv.textContainerInset != .zero {
                tv.textContainerInset = .zero
            }
            if tv.textContainer.lineFragmentPadding != 0 {
                tv.textContainer.lineFragmentPadding = 0
            }

            // The typing font, which SwiftUI sets even while the field is
            // empty and `font` has nothing to report, so the field doesn't
            // change height as the first character goes in.
            let font = (tv.typingAttributes[.font] as? UIFont) ?? tv.font ?? UIFont.preferredFont(forTextStyle: .body)
            let spacing = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0

            report?(NativeUITextEditorSize(contentHeight: tv.contentSize.height, lineHeight: font.lineHeight, lineSpacing: spacing))
        }

        private func findTextView() -> UITextView? {
            let frame = convert(bounds, to: nil)
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            var ancestor = superview
            for _ in 0..<6 {
                guard let a = ancestor else { return nil }
                if let tv = Self.textView(in: a, under: centre) { return tv }
                ancestor = a.superview
            }
            return nil
        }

        private static func textView(in view: UIView, under point: CGPoint) -> UITextView? {
            if let tv = view as? UITextView {
                return tv.convert(tv.bounds, to: nil).insetBy(dx: -1, dy: -1).contains(point) ? tv : nil
            }
            for sub in view.subviews {
                if let tv = textView(in: sub, under: point) { return tv }
            }
            return nil
        }
    }
}

/// The multiline editor's frame: as tall as its lines (`height`), or, when it
/// fills (`h-full` / `fill`), as tall as its parent makes it and never less
/// than `minHeight`. The text view scrolls what doesn't fit either way.
struct NativeUITextEditorFrame: ViewModifier {
    let fills: Bool
    let height: CGFloat
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        if fills {
            content.frame(minHeight: minHeight, maxHeight: .infinity, alignment: .top)
        } else {
            content.frame(height: height)
        }
    }
}

/// Reports where a multiline field's UITextView draws its caret, for
/// `@caretChange`: `x,y,width,height,line,fieldWidth,fieldHeight` in points,
/// over the same text channel as `@change`.
///
/// The rectangle is the text view's `caretRect(for:)` at the selection's end,
/// less its `contentOffset`, so it's measured from the top-left of what the
/// field shows. With the insets the sizer takes off, that's the field's own
/// frame. `line` is the visual line from the top of the text, from the
/// caret's middle over the typing font's line height (the field's lines are
/// all one height).
///
/// Triggers (the field's selection and text, the text view's content size and
/// offset, the field's size) are coalesced over the selection window and an
/// unchanged payload is dropped. Nothing is sent while the field isn't first
/// responder, or while no callback is set.
final class NativeUICaretReporter {
    weak var textView: UITextView?
    private var callbackId = 0
    private var nodeId = 0
    private var debounceMs = 150
    private var work: DispatchWorkItem?
    private var lastSent: String?

    /// Body-time refresh, so the callback and window never go stale.
    func configure(callbackId: Int, nodeId: Int, debounceMs: Int) {
        if callbackId == 0 {
            work?.cancel()
            work = nil
        }
        self.callbackId = callbackId
        self.nodeId = nodeId
        self.debounceMs = debounceMs
    }

    func schedule() {
        guard callbackId != 0 else { return }
        work?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, debounceMs)), execute: item)
    }

    func focusChanged(_ focused: Bool) {
        lastSent = nil
        if focused {
            schedule()
        } else {
            work?.cancel()
            work = nil
        }
    }

    func flush() {
        work?.cancel()
        work = nil
        guard callbackId != 0, let tv = textView, tv.isFirstResponder, let range = tv.selectedTextRange else { return }

        let rect = tv.caretRect(for: range.end)
        guard !rect.isNull, !rect.isInfinite, rect.origin.x.isFinite, rect.origin.y.isFinite else { return }

        let font = (tv.typingAttributes[.font] as? UIFont) ?? tv.font ?? UIFont.preferredFont(forTextStyle: .body)
        let spacing = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0
        let step = font.lineHeight + spacing
        let line = step > 0 ? max(0, Int((rect.midY / step).rounded(.down))) : 0

        let payload = [
            Self.format(rect.minX - tv.contentOffset.x),
            Self.format(rect.minY - tv.contentOffset.y),
            Self.format(rect.width),
            Self.format(rect.height),
            String(line),
            Self.format(tv.bounds.width),
            Self.format(tv.bounds.height),
        ].joined(separator: ",")

        if payload == lastSent { return }
        lastSent = payload
        NativeElementBridge.sendTextChangeEvent(callbackId, nodeId: nodeId, text: payload)
    }

    /// Two decimals with a `.`, whatever the device's locale.
    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }
}
