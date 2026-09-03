package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import com.nativephp.mobile.ui.MaterialIcon
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Shared plumbing for the text input variants. The two variants (outlined +
 * filled) only differ in which M3 primitive they construct and a few chrome
 * tweaks — extraction keeps prop parsing, keyboard mapping, dispatch policy,
 * and the decoration slot builders in one place.
 */

/** Dispatch policy — matches the `sync_mode` prop from the PHP side. */
internal enum class SyncMode { LIVE, BLUR, DEBOUNCE }

private fun parseSyncMode(value: String): SyncMode = when (value.lowercase()) {
    "blur"     -> SyncMode.BLUR
    "debounce" -> SyncMode.DEBOUNCE
    else       -> SyncMode.LIVE
}

/** Bag of parsed props — a plain data class, populated from the wire node. */
internal data class TextInputProps(
    val label: String,
    val placeholder: String,
    val supporting: String,
    val prefix: String,
    val suffix: String,
    val leadingIcon: String,
    val trailingIcon: String,
    val secure: Boolean,
    val revealable: Boolean,
    val multiline: Boolean,
    val maxLines: Int,
    val minLines: Int,
    val maxLength: Int,
    val keyboard: KeyboardType,
    val capitalization: KeyboardCapitalization?,
    val disabled: Boolean,
    val readOnly: Boolean,
    val isError: Boolean,
    val loading: Boolean,
    val size: String,
    val fontName: String,
    val lineHeight: Float,
    val lineHeightPx: Float,
    val a11yLabel: String,
    val a11yHint: String,
    val serverValue: String,
    val nodeId: Int,
    val onChangeCb: Int,
    val onSubmitCb: Int,
    val onSelectionChangeCb: Int,
    val syncMode: SyncMode,
    val debounceMs: Int,
    val selectionDebounceMs: Int,
) {
    val enabled: Boolean get() = !disabled && !loading

    /**
     * Masking for a field that may currently be revealed. The no-argument
     * property is the always-masked case, which is what the chromeless
     * variant uses — it has no decoration slot to put a toggle in, so it can
     * never be revealed.
     */
    fun visualTransformation(revealed: Boolean): VisualTransformation =
        if (secure && !revealed) PasswordVisualTransformation() else VisualTransformation.None

    val visualTransformation: VisualTransformation
        get() = visualTransformation(revealed = false)

    /**
     * Whether to draw the in-field reveal toggle. Opt-in via `revealable`,
     * meaningless without `secure`, and suppressed while the field is not
     * interactive — there is nothing to reveal in a field the user cannot
     * type into, and a disabled control that still answers taps is its own
     * bug.
     */
    val revealToggle: Boolean get() = secure && revealable && enabled && !readOnly

    val singleLine: Boolean get() = !multiline

    /** Numeric sp size for the chromeless variant. Tracks token fallbacks. */
    val textSize: Int get() = when (size) {
        "sm" -> 14
        "lg" -> 20
        else -> 16
    }

    /**
     * Direct bridge dispatchers for the chromeless variant — no sync-mode
     * policy, every change forwards immediately. Outlined / filled go through
     * [TextInputDispatcher] instead.
     */
    val dispatchChange: ((String) -> Unit)?
        get() = if (onChangeCb != 0) {
            { value -> NativeUIBridge.sendTextChangeEvent(onChangeCb, nodeId, value) }
        } else null

    val dispatchSubmit: ((String) -> Unit)?
        get() = if (onSubmitCb != 0) {
            { value -> NativeUIBridge.sendSubmitEvent(onSubmitCb, nodeId, value) }
        } else null
}

internal fun parseTextInputProps(node: NativeUINode): TextInputProps {
    val p = node.props
    return TextInputProps(
        label        = p.getString("label"),
        placeholder  = p.getString("placeholder"),
        supporting   = p.getString("supporting"),
        prefix       = p.getString("prefix"),
        suffix       = p.getString("suffix"),
        leadingIcon  = p.getString("leading_icon"),
        trailingIcon = p.getString("trailing_icon"),
        secure       = p.getBool("secure"),
        revealable   = p.getBool("revealable"),
        multiline    = p.getBool("multiline"),
        maxLines     = p.getInt("max_lines").let { if (it > 0) it else if (p.getBool("multiline")) 5 else 1 },
        minLines     = p.getInt("min_lines").let { if (it > 0) it else 1 },
        maxLength    = p.getInt("max_length"),
        keyboard     = resolveKeyboardType(p.getString("keyboard")),
        capitalization = resolveCapitalization(p.getString("autocapitalize"), p.getBool("secure"), p.getString("keyboard")),
        disabled     = p.getBool("disabled"),
        readOnly     = p.getBool("read_only"),
        isError      = p.getBool("is_error"),
        loading      = p.getBool("loading"),
        size         = p.getString("size", "md"),
        fontName     = p.getString("font_name"),
        lineHeight   = p.getFloat("line_height", 0f),
        lineHeightPx = p.getFloat("line_height_px", 0f),
        a11yLabel    = p.getString("a11y_label"),
        a11yHint     = p.getString("a11y_hint"),
        serverValue  = p.getString("value"),
        nodeId       = node.id,
        onChangeCb   = p.getCallbackId("on_change"),
        onSubmitCb   = p.getCallbackId("on_submit"),
        onSelectionChangeCb = p.getCallbackId("on_selection_change"),
        syncMode     = parseSyncMode(p.getString("sync_mode", "live")),
        debounceMs   = p.getInt("debounce_ms").let { if (it > 0) it else 300 },
        selectionDebounceMs = resolveSelectionDebounceMs(p.getInt("selection_debounce_ms")),
    )
}

/**
 * Resolve `selection_debounce_ms` to an effective window. PHP only serializes
 * the prop when explicitly configured, so an absent prop and an explicit `0`
 * are indistinguishable here — both mean "use the default".
 *
 * Positive values are floored at one frame: every emission costs a bridge
 * frame plus a full PHP component re-render, so a sub-frame window buys
 * nothing and can saturate the bridge while the caret is dragged.
 *
 * iOS resolves the same prop identically ([NativeUITextInputCore.swift]) —
 * keep the two in sync.
 */
internal fun resolveSelectionDebounceMs(raw: Int): Int =
    if (raw > 0) raw.coerceAtLeast(NUI_SELECTION_DEBOUNCE_FLOOR_MS) else NUI_SELECTION_DEBOUNCE_DEFAULT_MS

/** Default coalescing window for `@selectionChange`, in ms. */
internal const val NUI_SELECTION_DEBOUNCE_DEFAULT_MS = 150

/** Lower bound for an explicitly configured window — one frame at 60fps. */
internal const val NUI_SELECTION_DEBOUNCE_FLOOR_MS = 16

/** String hint → M3 KeyboardType. Unknown falls through to text. */
internal fun resolveKeyboardType(kind: String): KeyboardType = when (kind.lowercase()) {
    "number"         -> KeyboardType.Number
    "email"          -> KeyboardType.Email
    "phone"          -> KeyboardType.Phone
    "url"            -> KeyboardType.Uri
    "decimal"        -> KeyboardType.Decimal
    "password"       -> KeyboardType.Password
    "numberpassword" -> KeyboardType.NumberPassword
    else             -> KeyboardType.Text
}

/**
 * Capitalization for the field. [secure] wins outright; otherwise the explicit
 * `autocapitalize` prop when the author set one, otherwise derived from the
 * keyboard type. Null means "leave Compose's own default alone".
 *
 * Compose already defaults to no capitalization, so Android never had the iOS
 * bug (mobile-air #304) — it got the right answer by accident rather than on
 * purpose, and `autocapitalize` had no way to take effect at all.
 *
 * [secure] is checked FIRST, ahead of the explicit prop. Compose's default
 * already got an unannotated secure field right, so on Android this only
 * closes the one hole the `autocapitalize` prop opened: an author setting
 * `words` on a form and inheriting it onto the password field. Capitalizing a
 * secret is never what was meant, and the field is masked, so the stray
 * capital stays invisible until the login is rejected.
 *
 * The plain-text case deliberately returns NULL rather than `Sentences`.
 * Sentences is what iOS does and would make the platforms agree, but it would
 * also silently start capitalizing every unclassified text field in every
 * existing Android app. That default is a separate decision; this change only
 * makes the prop work and pins the cases the keyboard type already implies.
 *
 * Unknown values fall through to the derived behaviour rather than erroring,
 * matching `resolveKeyboardType`.
 */
internal fun resolveCapitalization(explicit: String, secure: Boolean, keyboard: String): KeyboardCapitalization? {
    if (secure) return KeyboardCapitalization.None

    return when (explicit.lowercase()) {
        "none"       -> KeyboardCapitalization.None
        "sentences"  -> KeyboardCapitalization.Sentences
        "words"      -> KeyboardCapitalization.Words
        "characters" -> KeyboardCapitalization.Characters
        else -> when (keyboard.lowercase()) {
            // Case-sensitive or non-alphabetic content — never capitalize.
            "email", "url", "number", "decimal", "phone",
            "numberpassword", "password" -> KeyboardCapitalization.None
            else -> null
        }
    }
}

internal fun keyboardOptionsFor(props: TextInputProps): KeyboardOptions =
    props.capitalization
        ?.let { KeyboardOptions(keyboardType = props.keyboard, capitalization = it) }
        ?: KeyboardOptions(keyboardType = props.keyboard)

/**
 * Outbound dispatch state machine. Call [onTextChanged] whenever local text
 * updates; the policy decides whether to forward the change over the bridge
 * now, later (debounce), or on blur. [onBlur] flushes any pending value.
 */
internal class TextInputDispatcher(
    private val scope: CoroutineScope,
    private val props: TextInputProps,
    private val nodeId: Int,
    private val setLastSent: (String) -> Unit,
    private val getLastSent: () -> String,
) {
    private var debounceJob: Job? = null

    fun onTextChanged(value: String) {
        when (props.syncMode) {
            SyncMode.BLUR -> {
                // Don't dispatch mid-typing. `lastSentValue` stays anchored to
                // the last committed value so echo-prevention still blocks
                // same-value echoes of the committed state.
            }

            SyncMode.DEBOUNCE -> {
                // Cancel any in-flight timer; schedule a fresh one. First
                // keystroke gets a fresh N ms budget; each keystroke resets.
                debounceJob?.cancel()
                val captured = value
                val delayMs = props.debounceMs.coerceAtLeast(50).toLong()
                debounceJob = scope.launch {
                    delay(delayMs)
                    commit(captured)
                }
            }

            SyncMode.LIVE -> commit(value)
        }
    }

    fun onBlur(currentText: String) {
        // Flush pending change — covers both blur mode (deferred dispatch) and
        // debounce (in-flight timer that should resolve immediately on focus
        // loss instead of racing with keyboard dismiss).
        debounceJob?.cancel()
        debounceJob = null
        if (currentText != getLastSent()) {
            commit(currentText)
        }
    }

    fun onSubmit(currentText: String) {
        onBlur(currentText)
        if (props.onSubmitCb != 0) {
            NativeUIBridge.sendSubmitEvent(props.onSubmitCb, nodeId, currentText)
        }
    }

    private fun commit(value: String) {
        setLastSent(value)
        if (props.onChangeCb != 0) {
            NativeUIBridge.sendTextChangeEvent(props.onChangeCb, nodeId, value)
        }
    }
}

/**
 * Caret / selection reporter. Independent of the [TextInputDispatcher] model
 * (sync_mode / debounce_ms) policy — it fires whenever the *text or selection*
 * changes so PHP can mirror the native caret, coalesced trailing-edge over
 * [TextInputProps.selectionDebounceMs] and deduped when nothing moved.
 *
 * Reuses the existing text-change channel with a distinct callback id: the
 * payload is packed as `"start,end" + U+001F + text`, where start/end are
 * Unicode **code-point** offsets into the current text.
 *
 * IME / composition policy: we deliberately do NOT skip emissions while a
 * composing region is active (`value.composition != null`). On soft keyboards
 * the composing region spans ordinary Latin typing, so hard-skipping it would
 * suppress exactly the "typing" reports the contract asks for. Instead we lean
 * on two guards that make composition safe: [codePointSelection] clamps the
 * (occasionally out-of-bounds) UTF-16 offsets into the current text, and the
 * trailing-edge debounce + dedup collapse the burst of intermediate composing
 * states into a single settled emission.
 */
internal class SelectionReporter(
    private val scope: CoroutineScope,
    private val props: TextInputProps,
    private val nodeId: Int,
) {
    // Opt-in (a callback id must be wired) and never for secure fields — we
    // must not leak password caret/selection offsets, and the value is masked
    // anyway. When inactive every entry point below is a cheap early return, so
    // there is zero behavior change when the prop is absent.
    private val active: Boolean get() = props.onSelectionChangeCb != 0 && !props.secure

    private var job: Job? = null

    // Last emitted triple, for dedup. `lastText == null` means "nothing sent".
    private var lastText: String? = null
    private var lastStart: Int = -1
    private var lastEnd: Int = -1

    /**
     * Debounced report of [value]. Call on every text/selection change. Each
     * call cancels the in-flight timer and schedules a fresh trailing-edge
     * emission [TextInputProps.selectionDebounceMs] later.
     */
    fun onValueChanged(value: TextFieldValue) {
        if (!active) return
        val text = value.text
        val (start, end) = codePointSelection(text, value.selection)
        job?.cancel()
        val delayMs = props.selectionDebounceMs.coerceAtLeast(0).toLong()
        job = scope.launch {
            delay(delayMs)
            emit(text, start, end)
        }
    }

    /**
     * Emit [value] immediately, cancelling any pending debounce. Used on blur
     * and before submit so the settled caret/selection always lands, and for
     * the programmatic server-push (see the renderers' value-sync effect).
     */
    fun flush(value: TextFieldValue) {
        if (!active) return
        job?.cancel()
        job = null
        val (start, end) = codePointSelection(value.text, value.selection)
        emit(value.text, start, end)
    }

    private fun emit(text: String, start: Int, end: Int) {
        // Dedup: an unchanged (text, start, end) is dropped so idle re-renders
        // and repeated blur/flush passes don't spam the bridge.
        if (text == lastText && start == lastStart && end == lastEnd) return
        lastText = text
        lastStart = start
        lastEnd = end
        // Wire format: "start,end" + U+001F (unit separator) + raw text. The
        // separator is a control char that cannot collide with typed content.
        val packed = "$start,$end\u001F$text"
        NativeUIBridge.sendTextChangeEvent(props.onSelectionChangeCb, nodeId, packed)
    }
}

/**
 * Map a Compose [TextRange] (UTF-16 offsets) to Unicode code-point offsets.
 *
 * Both ends are ordered via min/max (a reversed drag reports start > end) and
 * clamped into `0..text.length` before conversion — Compose can transiently
 * report offsets past the end during IME composition. `codePointCount` then
 * collapses surrogate pairs, so e.g. "👍🏽" (4 UTF-16 units) reads as 2 code
 * points. Guarantees `0 ≤ start ≤ end ≤ codePointCount(text)`.
 */
private fun codePointSelection(text: String, selection: TextRange): Pair<Int, Int> {
    val len = text.length
    val startUtf16 = selection.min.coerceIn(0, len)
    val endUtf16 = selection.max.coerceIn(0, len)
    val start = text.codePointCount(0, startUtf16)
    val end = text.codePointCount(0, endUtf16)
    return start to end
}

/**
 * Apply the `max_length` cap to an incoming [TextFieldValue], preserving a sane
 * selection. Keeps the pre-migration `text.take(maxLength)` semantics (UTF-16
 * units) and additionally clamps the caret/selection into the trimmed text so
 * it can never point past the end after an over-long paste or IME commit. A
 * value at or under the cap is returned untouched (selection + composition
 * intact).
 */
internal fun TextFieldValue.cappedTo(maxLength: Int): TextFieldValue {
    if (maxLength <= 0 || text.length <= maxLength) return this
    val trimmed = text.take(maxLength)
    val start = selection.start.coerceIn(0, trimmed.length)
    val end = selection.end.coerceIn(0, trimmed.length)
    return TextFieldValue(text = trimmed, selection = TextRange(start, end))
}

/** Common slot renderers — shared between OutlinedTextField and TextField. */
@Composable
internal fun labelSlot(text: String): (@Composable () -> Unit)? =
    if (text.isEmpty()) null else ({ Text(text, fontFamily = nuiDefaultFontFamily()) })

@Composable
internal fun placeholderSlot(text: String): (@Composable () -> Unit)? =
    if (text.isEmpty()) null else ({ Text(text, fontFamily = nuiDefaultFontFamily()) })

@Composable
internal fun supportingSlot(text: String): (@Composable () -> Unit)? =
    if (text.isEmpty()) null else ({ Text(text, fontFamily = nuiDefaultFontFamily()) })

@Composable
internal fun prefixSlot(text: String): (@Composable () -> Unit)? =
    if (text.isEmpty()) null else ({ Text(text, fontFamily = nuiDefaultFontFamily()) })

@Composable
internal fun suffixSlot(text: String): (@Composable () -> Unit)? =
    if (text.isEmpty()) null else ({ Text(text, fontFamily = nuiDefaultFontFamily()) })

@Composable
internal fun leadingIconSlot(name: String): (@Composable () -> Unit)? =
    if (name.isEmpty()) null else ({ MaterialIcon(name = name, contentDescription = null) })

@Composable
internal fun trailingIconSlot(name: String): (@Composable () -> Unit)? =
    if (name.isEmpty()) null else ({ MaterialIcon(name = name, contentDescription = null) })

/**
 * The in-field reveal ("eye") for a `secure` field, for the M3 `trailingIcon`
 * slot — so it sits where the trailing icon sits rather than as a separate
 * Show / Hide control beside the input, which is what an app has to build
 * today and which costs a bridge round-trip and a republish on every tap.
 *
 * [revealed] is caller-owned local state and stays local: it must never be
 * reported to PHP, republish the tree, or touch the value / caret / sync-mode
 * machinery. Returns null when the field didn't ask for a toggle, so the
 * caller's existing trailing slot is used unchanged.
 *
 * The content description announces the ACTION the tap performs rather than
 * the current state — TalkBack reads "Show password, button".
 */
@Composable
internal fun revealToggleSlot(
    props: TextInputProps,
    revealed: Boolean,
    onToggle: () -> Unit,
): (@Composable () -> Unit)? {
    if (!props.revealToggle) return null

    return {
        IconButton(onClick = onToggle) {
            MaterialIcon(
                name = if (revealed) "visibility_off" else "visibility",
                contentDescription = if (revealed) "Hide password" else "Show password",
            )
        }
    }
}

/**
 * Apply optional a11y label/hint to a modifier.
 *
 * The hint is merged into the contentDescription (TalkBack reads it right
 * after the label) — never into stateDescription, which is reserved for
 * actual widget state ("On", "Loading", ...).
 */
internal fun Modifier.nuiA11y(label: String, hint: String): Modifier {
    val merged = listOf(label, hint).filter { it.isNotEmpty() }.joinToString(". ")
    return if (merged.isEmpty()) this else semantics { contentDescription = merged }
}
