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
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
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
 * Material3 filled text field.
 *
 * Higher emphasis than outlined — tonal surface fill with a bottom accent
 * indicator. Best for forms where inputs need to stand out.
 *
 * Shares prop parsing + the echo-prevention value sync (plan K) with the
 * outlined variant via [parseTextInputProps].
 */
object FilledTextInputRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val props = parseTextInputProps(node)
        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        val scope = rememberCoroutineScope()

        // Local state owns text + caret (TextFieldValue). Initial caret sits at
        // the end of any pre-filled value, matching the server-push below.
        var value by remember { mutableStateOf(TextFieldValue(props.serverValue, TextRange(props.serverValue.length))) }
        var lastSentValue by remember { mutableStateOf(props.serverValue) }

        // Reveal state for a `revealable` secure field. Local on purpose, and
        // that is the whole safety argument for the feature: flipping it never
        // crosses the bridge, so it cannot republish the tree, disturb `value`
        // / `lastSentValue`, trip the sync-mode dispatcher, or move the caret.
        var revealed by remember { mutableStateOf(false) }

        val dispatcher = remember(props.syncMode, props.debounceMs, props.onChangeCb) {
            TextInputDispatcher(
                scope = scope,
                props = props,
                nodeId = node.id,
                setLastSent = { lastSentValue = it },
                getLastSent = { lastSentValue },
            )
        }

        // Caret / selection reporter — independent of the sync-mode dispatcher;
        // no-op unless `on_selection_change` is wired and the field isn't secure.
        val selectionReporter = remember(props.onSelectionChangeCb, props.selectionDebounceMs, props.secure) {
            SelectionReporter(scope = scope, props = props, nodeId = node.id)
        }

        LaunchedEffect(props.serverValue) {
            if (props.serverValue != lastSentValue) {
                // Programmatic server push: replace text, caret to the end, and
                // flush a single end-caret selection event (deduped) rather
                // than emitting stale pre-push offsets.
                val pushed = TextFieldValue(props.serverValue, TextRange(props.serverValue.length))
                value = pushed
                lastSentValue = props.serverValue
                selectionReporter.flush(pushed)
            }
        }

        val interactionSource = remember { MutableInteractionSource() }
        LaunchedEffect(interactionSource) {
            val focusStack = mutableListOf<FocusInteraction.Focus>()
            interactionSource.interactions.collect { interaction: Interaction ->
                when (interaction) {
                    is FocusInteraction.Focus   -> focusStack += interaction
                    is FocusInteraction.Unfocus -> {
                        focusStack.remove(interaction.focus)
                        if (focusStack.isEmpty()) {
                            // Flush the pending selection, then any deferred text.
                            selectionReporter.flush(value)
                            dispatcher.onBlur(value.text)
                        }
                    }
                    else -> { /* ignore */ }
                }
            }
        }

        val textSize = when (props.size) {
            "sm" -> theme.fontSm
            "lg" -> theme.fontLg
            else -> theme.fontMd
        }
        val customFontFamily = (if (props.fontName.isNotEmpty()) NativeUIFontResolver.resolve(LocalContext.current, props.fontName) else null)
            ?: nuiThemeDefaultFontFamily(LocalContext.current)
        val lineHeight = nuiLineHeightUnit(props.lineHeightPx, props.lineHeight, textSize.value)

        TextField(
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
                { CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = theme.onSurfaceVariant) }
            } else {
                // The reveal toggle owns the trailing slot whenever it is on.
                // An author who set a trailing icon AND `revealable` asked for
                // the toggle by asking for `revealable`, which the icon slot
                // has no other way to express; the icon is still drawn on
                // every field that didn't.
                revealToggleSlot(props, revealed) { revealed = !revealed }
                    ?: trailingIconSlot(props.trailingIcon)
            },
            isError = props.isError,
            singleLine = props.singleLine,
            maxLines = props.maxLines,
            minLines = props.minLines,
            visualTransformation = props.visualTransformation(revealed),
            keyboardOptions = keyboardOptionsFor(props),
            keyboardActions = KeyboardActions(onDone = {
                // Flush the settled caret before the submit event fires.
                selectionReporter.flush(value)
                dispatcher.onSubmit(value.text)
            }),
            textStyle = TextStyle(fontSize = textSize, color = theme.onSurface, fontFamily = customFontFamily, lineHeight = lineHeight),
            colors = TextFieldDefaults.colors(
                focusedTextColor = theme.onSurface,
                unfocusedTextColor = theme.onSurface,
                disabledTextColor = theme.onSurface.copy(alpha = 0.6f),
                errorTextColor = theme.onSurface,
                cursorColor = theme.primary,
                errorCursorColor = theme.destructive,
                focusedContainerColor = theme.surfaceVariant,
                unfocusedContainerColor = theme.surfaceVariant,
                disabledContainerColor = theme.surfaceVariant.copy(alpha = 0.5f),
                errorContainerColor = theme.surfaceVariant,
                focusedIndicatorColor = theme.primary,
                unfocusedIndicatorColor = theme.outline,
                disabledIndicatorColor = theme.outline.copy(alpha = 0.5f),
                errorIndicatorColor = theme.destructive,
                focusedLabelColor = theme.primary,
                unfocusedLabelColor = theme.onSurfaceVariant,
                disabledLabelColor = theme.onSurfaceVariant.copy(alpha = 0.6f),
                errorLabelColor = theme.destructive,
                focusedPlaceholderColor = theme.onSurfaceVariant,
                unfocusedPlaceholderColor = theme.onSurfaceVariant,
                focusedSupportingTextColor = theme.onSurfaceVariant,
                unfocusedSupportingTextColor = theme.onSurfaceVariant,
                errorSupportingTextColor = theme.destructive,
                focusedLeadingIconColor = theme.onSurfaceVariant,
                unfocusedLeadingIconColor = theme.onSurfaceVariant,
                focusedTrailingIconColor = theme.onSurfaceVariant,
                unfocusedTrailingIconColor = theme.onSurfaceVariant,
            ),
        )
    }
}
