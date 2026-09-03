package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.Interaction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 outlined text field.
 *
 * Emphasis: lower than filled. Border-only chrome, good default for forms.
 *
 * All colors drawn from [NativeUITheme] — per-instance color overrides are
 * intentionally not honored (plan doc Model 3).
 *
 * The container is filled with the `input-fill` theme token and its contents
 * take `on-input`. Both are transparent / absent by default, which is what
 * `OutlinedTextFieldDefaults.colors()` already resolved to, so an app that
 * declares neither renders exactly as before.
 */
object OutlinedTextInputRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val props = parseTextInputProps(node)
        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        val scope = rememberCoroutineScope()

        // Echo-prevention sync (plan K). Local state owns what the user is
        // typing — now a TextFieldValue so we also own the caret / selection.
        // PHP may push an updated `value` prop at any time; we only accept it
        // if it diverges from `lastSentValue` — otherwise it's just the
        // Livewire echo of our own change and would clobber text and caret.
        // Initial caret sits at the end of any pre-filled value (parity with
        // the server-push behavior below).
        var value by remember { mutableStateOf(TextFieldValue(props.serverValue, TextRange(props.serverValue.length))) }
        var lastSentValue by remember { mutableStateOf(props.serverValue) }

        // Sync-mode dispatcher (plan L). Owns the live / blur / debounce
        // decision for outbound change events.
        val dispatcher = remember(props.syncMode, props.debounceMs, props.onChangeCb) {
            TextInputDispatcher(
                scope = scope,
                props = props,
                nodeId = node.id,
                setLastSent = { lastSentValue = it },
                getLastSent = { lastSentValue },
            )
        }

        // Caret / selection reporter. Independent of the sync-mode dispatcher;
        // no-op unless `on_selection_change` is wired and the field isn't secure.
        val selectionReporter = remember(props.onSelectionChangeCb, props.selectionDebounceMs, props.secure) {
            SelectionReporter(scope = scope, props = props, nodeId = node.id)
        }

        LaunchedEffect(props.serverValue) {
            if (props.serverValue != lastSentValue) {
                // Programmatic server push: replace the text and drop the caret
                // at the very end (parity with the pre-migration String sync,
                // which reset the field wholesale). We do NOT emit stale
                // pre-push offsets; instead we flush a single end-caret
                // selection event (deduped) so PHP mirrors the new caret.
                val pushed = TextFieldValue(props.serverValue, TextRange(props.serverValue.length))
                value = pushed
                lastSentValue = props.serverValue
                selectionReporter.flush(pushed)
            }
        }

        // Observe focus via the field's InteractionSource; we use that edge
        // (focused → unfocused) to flush pending changes in blur / debounce
        // modes. Passing our own source also means we don't pay for M3's
        // default ripple-focus-hover machinery elsewhere.
        val interactionSource = remember { MutableInteractionSource() }
        LaunchedEffect(interactionSource) {
            val focusStack = mutableListOf<FocusInteraction.Focus>()
            interactionSource.interactions.collect { interaction: Interaction ->
                when (interaction) {
                    is FocusInteraction.Focus   -> focusStack += interaction
                    is FocusInteraction.Unfocus -> {
                        focusStack.remove(interaction.focus)
                        if (focusStack.isEmpty()) {
                            // Flush the pending selection first so the final
                            // caret lands, then flush any deferred text change.
                            selectionReporter.flush(value)
                            dispatcher.onBlur(value.text)
                        }
                    }
                    else -> { /* ignore press/hover/drag */ }
                }
            }
        }

        // Everything INSIDE the box. Two tones by default — typed text at full
        // emphasis, labels, placeholders and icons muted — which is the M3
        // hierarchy this renderer has always drawn. A declared `on-input`
        // collapses both onto itself, because the moment `input-fill` is a
        // saturated color the muted gray stops being a hierarchy and starts
        // being unreadable. Supporting text is excluded: M3 draws it BELOW the
        // box, on the surface behind the field, so it keeps that surface's
        // colors. So is the focused label color, which is a focus accent
        // (`primary`) rather than in-field content.
        val fieldTextColor = theme.onInput ?: theme.onSurface
        val fieldDecorationColor = theme.onInput ?: theme.onSurfaceVariant

        val textSize = when (props.size) {
            "sm" -> theme.fontSm
            "lg" -> theme.fontLg
            else -> theme.fontMd
        }
        val customFontFamily = (if (props.fontName.isNotEmpty()) NativeUIFontResolver.resolve(LocalContext.current, props.fontName) else null)
            ?: nuiThemeDefaultFontFamily(LocalContext.current)
        val lineHeight = nuiLineHeightUnit(props.lineHeightPx, props.lineHeight, textSize.value)

        OutlinedTextField(
            value = value,
            onValueChange = { new ->
                // maxLength now also clamps the caret/selection into the
                // trimmed text (see `cappedTo`).
                val capped = new.cappedTo(props.maxLength)
                val textChanged = capped.text != value.text
                value = capped
                // Only forward *text* changes to the model dispatcher — the
                // String overload never invoked onValueChange for caret-only
                // moves, so selection-only updates must not re-fire change
                // events. Text-change dispatch still receives the plain String.
                if (textChanged) dispatcher.onTextChanged(capped.text)
                selectionReporter.onValueChanged(capped)
            },
            // Full width by default (parity with the iOS renderer's
            // maxWidth: .infinity); an explicit width in `modifier` (FIXED
            // layout mode) still wins since it comes later in the chain.
            modifier = Modifier.fillMaxWidth().then(modifier).nuiA11y(props.a11yLabel, props.a11yHint),
            enabled = props.enabled,
            readOnly = props.readOnly,
            interactionSource = interactionSource,
            label = labelSlot(props.label),
            placeholder = placeholderSlot(props.placeholder),
            supportingText = supportingSlot(props.supporting),
            prefix = prefixSlot(props.prefix),
            suffix = suffixSlot(props.suffix),
            leadingIcon = leadingIconSlot(props.leadingIcon),
            trailingIcon = if (props.loading) {
                { CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = fieldDecorationColor) }
            } else trailingIconSlot(props.trailingIcon),
            isError = props.isError,
            singleLine = props.singleLine,
            maxLines = props.maxLines,
            minLines = props.minLines,
            visualTransformation = props.visualTransformation,
            keyboardOptions = keyboardOptionsFor(props),
            keyboardActions = KeyboardActions(onDone = {
                // Flush the settled caret before the submit event fires.
                selectionReporter.flush(value)
                dispatcher.onSubmit(value.text)
            }),
            textStyle = TextStyle(fontSize = textSize, color = fieldTextColor, fontFamily = customFontFamily, lineHeight = lineHeight),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = fieldTextColor,
                unfocusedTextColor = fieldTextColor,
                disabledTextColor = fieldTextColor.copy(alpha = 0.6f),
                errorTextColor = fieldTextColor,
                // The container defaults to Transparent in
                // OutlinedTextFieldDefaults, so naming it here changes nothing
                // until `input-fill` is declared. All four states take the
                // same value: a field that vanishes into the page is just as
                // wrong once it's focused or in error.
                focusedContainerColor = theme.inputFill,
                unfocusedContainerColor = theme.inputFill,
                disabledContainerColor = theme.inputFill,
                errorContainerColor = theme.inputFill,
                cursorColor = theme.primary,
                errorCursorColor = theme.destructive,
                focusedBorderColor = theme.primary,
                unfocusedBorderColor = theme.outline,
                disabledBorderColor = theme.outline.copy(alpha = 0.5f),
                errorBorderColor = theme.destructive,
                focusedLabelColor = theme.primary,
                unfocusedLabelColor = fieldDecorationColor,
                disabledLabelColor = fieldDecorationColor.copy(alpha = 0.6f),
                errorLabelColor = theme.destructive,
                focusedPlaceholderColor = fieldDecorationColor,
                unfocusedPlaceholderColor = fieldDecorationColor,
                focusedSupportingTextColor = theme.onSurfaceVariant,
                unfocusedSupportingTextColor = theme.onSurfaceVariant,
                errorSupportingTextColor = theme.destructive,
                focusedLeadingIconColor = fieldDecorationColor,
                unfocusedLeadingIconColor = fieldDecorationColor,
                focusedTrailingIconColor = fieldDecorationColor,
                unfocusedTrailingIconColor = fieldDecorationColor,
            ),
        )
    }
}
