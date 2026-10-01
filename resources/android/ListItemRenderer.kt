package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode

object ListItemRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val headline = p.getString("headline")
        val supporting = p.getString("supporting")
        val overline = p.getString("overline")
        val disabled = p.getBool("disabled")

        // Colors
        val headlineColor = p.getColor("headline_color", 0)
        val supportingColor = p.getColor("supporting_color", 0)
        val overlineColor = p.getColor("overline_color", 0)
        val containerColor = p.getColor("container_color", 0)
        val leadingIconColor = p.getColor("leading_icon_color", 0)
        val trailingIconColor = p.getColor("trailing_icon_color", 0)
        val trailingTextColor = p.getColor("trailing_text_color", 0)

        // Elevation
        val tonalElevation = p.getFloat("tonal_elevation", 0f)
        val shadowElevation = p.getFloat("shadow_elevation", 0f)

        // Leading content props
        val leadingType = p.getString("leading_type")
        val leadingValue = p.getString("leading_value")
        val leadingIcon = p.getString("leading_icon")
        val leadingCheckedInitial = p.getBool("leading_checked")
        val leadingMonogramColor = p.getColor("leading_monogram_color", 0)
        val leadingIconBgColor = p.getColor("leading_icon_bg_color", 0)
        val onLeadingChangeCb = p.getCallbackId("on_leading_change")

        // Trailing content props
        val trailingType = p.getString("trailing_type")
        val trailingValue = p.getString("trailing_value")
        val trailingIcon = p.getString("trailing_icon")
        val trailingCheckedInitial = p.getBool("trailing_checked")
        val onTrailingChangeCb = p.getCallbackId("on_trailing_change")
        val onTrailingPressCb = p.getCallbackId("on_trailing_press")

        // Press / long-press
        val pressCbId = node.onPress
        val longPressCbId = node.onLongPress

        // Click / gesture modifier
        val clickModifier = if (longPressCbId != 0) {
            modifier.pointerInput(pressCbId, longPressCbId) {
                detectTapGestures(
                    onTap = {
                        if (!disabled && pressCbId != 0) {
                            NativeUIBridge.sendPressEvent(pressCbId, node.id)
                        }
                    },
                    onLongPress = {
                        if (!disabled) {
                            NativeUIBridge.sendLongPressEvent(longPressCbId, node.id)
                        }
                    }
                )
            }
        } else if (pressCbId != 0) {
            modifier.clickable(enabled = !disabled, role = Role.Button) {
                NativeUIBridge.sendPressEvent(pressCbId, node.id)
            }
        } else {
            modifier
        }

        // Build colors
        val colors = ListItemDefaults.colors(
            containerColor = if (containerColor != 0) Color(containerColor) else Color.Unspecified,
            leadingIconColor = if (leadingIconColor != 0) Color(leadingIconColor) else Color.Unspecified,
            trailingIconColor = if (trailingIconColor != 0) Color(trailingIconColor) else Color.Unspecified
        )

        ListItem(
            headlineContent = {
                Text(
                    text = headline,
                    fontFamily = nuiDefaultFontFamily(),
                    color = if (headlineColor != 0) Color(headlineColor) else Color.Unspecified
                )
            },
            modifier = clickModifier,
            overlineContent = if (overline.isNotEmpty()) {
                {
                    Text(
                        text = overline,
                        fontFamily = nuiDefaultFontFamily(),
                        color = if (overlineColor != 0) Color(overlineColor) else Color.Unspecified
                    )
                }
            } else null,
            supportingContent = if (supporting.isNotEmpty()) {
                {
                    Text(
                        text = supporting,
                        fontFamily = nuiDefaultFontFamily(),
                        color = if (supportingColor != 0) Color(supportingColor) else Color.Unspecified
                    )
                }
            } else null,
            leadingContent = buildLeadingContent(
                type = leadingType,
                value = leadingValue,
                fallbackIcon = leadingIcon,
                checkedInitial = leadingCheckedInitial,
                monogramColor = leadingMonogramColor,
                iconColor = leadingIconColor,
                iconBgColor = leadingIconBgColor,
                onChangeCb = onLeadingChangeCb,
                nodeId = node.id,
                disabled = disabled
            ),
            trailingContent = run {
                // Multi-badge stack (e.g. flag + pin both visible)
                // wins over the single trailing-icon slot.
                val badgesJson = p.getString("trailing_badges_json", "")
                if (badgesJson.isNotEmpty()) {
                    buildTrailingBadges(badgesJson)
                } else {
                    buildTrailingContent(
                        type = trailingType,
                        value = trailingValue,
                        fallbackIcon = trailingIcon,
                        checkedInitial = trailingCheckedInitial,
                        iconColor = trailingIconColor,
                        textColor = trailingTextColor,
                        onChangeCb = onTrailingChangeCb,
                        onPressCb = onTrailingPressCb,
                        nodeId = node.id,
                        disabled = disabled,
                        hasMenu = p.getBool("has_trailing_menu"),
                        menuItems = node.children.filter { it.type == "top_bar_action" },
                        a11yLabel = p.getString("trailing_a11y_label"),
                    )
                }
            },
            colors = colors,
            tonalElevation = tonalElevation.dp,
            shadowElevation = shadowElevation.dp
        )
    }

    @Composable
    private fun buildLeadingContent(
        type: String,
        value: String,
        fallbackIcon: String,
        checkedInitial: Boolean,
        monogramColor: Int,
        iconColor: Int,
        iconBgColor: Int,
        onChangeCb: Int,
        nodeId: Int,
        disabled: Boolean
    ): (@Composable () -> Unit)? {
        // Determine effective type — backward compat: fall back to icon if leading_type empty
        val effectiveType = type.ifEmpty {
            if (fallbackIcon.isNotEmpty()) "icon" else return null
        }
        val effectiveValue = value.ifEmpty { fallbackIcon }

        return {
            when (effectiveType) {
                "icon" -> {
                    // Decorative — announcing the machine icon name is noise.
                    if (iconBgColor != 0) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .background(Color(iconBgColor), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            com.nativephp.mobile.ui.MaterialIcon(
                                name = effectiveValue,
                                contentDescription = null,
                                size = 22.dp,
                                tint = Color.White
                            )
                        }
                    } else {
                        com.nativephp.mobile.ui.MaterialIcon(
                            name = effectiveValue,
                            contentDescription = null,
                            size = 24.dp,
                            tint = if (iconColor != 0) Color(iconColor) else Color.Unspecified
                        )
                    }
                }
                "avatar" -> {
                    val context = LocalContext.current
                    SubcomposeAsyncImage(
                        model = remember(effectiveValue, context) {
                            nuiResolveImageSrc(effectiveValue, context)
                        },
                        contentDescription = null,
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape),
                        contentScale = ContentScale.Crop,
                        loading = {
                            Box(
                                modifier = Modifier
                                    .size(40.dp)
                                    .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                            )
                        },
                        error = {
                            Box(
                                modifier = Modifier
                                    .size(40.dp)
                                    .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                            )
                        }
                    )
                }
                "monogram" -> {
                    val bgColor = if (monogramColor != 0) Color(monogramColor)
                        else MaterialTheme.colorScheme.primaryContainer
                    val textColor = if (monogramColor != 0) Color.White
                        else MaterialTheme.colorScheme.onPrimaryContainer
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .background(bgColor, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = effectiveValue.take(2).uppercase(),
                            fontFamily = nuiDefaultFontFamily(),
                            color = textColor,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            textAlign = TextAlign.Center
                        )
                    }
                }
                "image" -> {
                    val context = LocalContext.current
                    SubcomposeAsyncImage(
                        model = remember(effectiveValue, context) {
                            nuiResolveImageSrc(effectiveValue, context)
                        },
                        contentDescription = null,
                        modifier = Modifier
                            .size(56.dp)
                            .clip(RoundedCornerShape(4.dp)),
                        contentScale = ContentScale.Crop,
                        loading = {
                            Box(
                                modifier = Modifier
                                    .size(56.dp)
                                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(4.dp))
                            )
                        },
                        error = {
                            Box(
                                modifier = Modifier
                                    .size(56.dp)
                                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(4.dp))
                            )
                        }
                    )
                }
                "checkbox" -> {
                    var checked by remember(nodeId, checkedInitial) { mutableStateOf(checkedInitial) }
                    Checkbox(
                        checked = checked,
                        onCheckedChange = { newValue ->
                            checked = newValue
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendCheckboxChangeEvent(onChangeCb, nodeId, newValue)
                            }
                        },
                        enabled = !disabled
                    )
                }
                "radio" -> {
                    var selected by remember(nodeId, checkedInitial) { mutableStateOf(checkedInitial) }
                    RadioButton(
                        selected = selected,
                        onClick = {
                            selected = !selected
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendCheckboxChangeEvent(onChangeCb, nodeId, selected)
                            }
                        },
                        enabled = !disabled
                    )
                }
            }
        }
    }

    /**
     * Build a composable that renders a horizontal stack of small
     * status badges (e.g. flag + pin both visible). Each badge is a
     * Material icon at 18.dp with its own tint color. Returns null
     * when the JSON is empty/invalid so the caller falls back to
     * the single-icon `buildTrailingContent`.
     */
    private fun buildTrailingBadges(json: String): (@Composable () -> Unit)? {
        if (json.isEmpty()) return null
        val arr = try { org.json.JSONArray(json) } catch (_: Exception) { return null }
        val badges = (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            val icon = o.optString("icon", "")
            if (icon.isEmpty()) return@mapNotNull null
            Triple(icon, o.optString("icon_variant", ""), o.optString("color", ""))
        }
        if (badges.isEmpty()) return null

        return {
            androidx.compose.foundation.layout.Row(
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                badges.forEach { (icon, _, color) ->
                    val tint = parseListItemBadgeHex(color) ?: Color.Unspecified
                    com.nativephp.mobile.ui.MaterialIcon(
                        name = icon,
                        contentDescription = null,
                        size = 18.dp,
                        tint = tint,
                    )
                }
            }
        }
    }

    @Composable
    private fun buildTrailingContent(
        type: String,
        value: String,
        fallbackIcon: String,
        checkedInitial: Boolean,
        iconColor: Int,
        textColor: Int,
        onChangeCb: Int,
        onPressCb: Int,
        nodeId: Int,
        disabled: Boolean,
        hasMenu: Boolean = false,
        menuItems: List<NativeUINode> = emptyList(),
        a11yLabel: String = "",
    ): (@Composable () -> Unit)? {
        val effectiveType = type.ifEmpty {
            if (fallbackIcon.isNotEmpty()) "icon" else return null
        }
        val effectiveValue = value.ifEmpty { fallbackIcon }
        // Interactive icon_button needs an accessible name: explicit
        // `trailing_a11y_label` wins, else humanize the machine icon name
        // ("more_vert" -> "more vert") so it's never unlabeled.
        val iconButtonDescription = a11yLabel.ifEmpty {
            effectiveValue.replace('_', ' ').replace('-', ' ')
        }

        return {
            when (effectiveType) {
                "icon" -> {
                    // Decorative — announcing the machine icon name is noise.
                    com.nativephp.mobile.ui.MaterialIcon(
                        name = effectiveValue,
                        contentDescription = null,
                        size = 24.dp,
                        tint = if (iconColor != 0) Color(iconColor) else Color.Unspecified
                    )
                }
                "text" -> {
                    Text(
                        text = effectiveValue,
                        fontFamily = nuiDefaultFontFamily(),
                        color = if (textColor != 0) Color(textColor) else Color.Unspecified
                    )
                }
                "checkbox" -> {
                    var checked by remember(nodeId, checkedInitial) { mutableStateOf(checkedInitial) }
                    Checkbox(
                        checked = checked,
                        onCheckedChange = { newValue ->
                            checked = newValue
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendCheckboxChangeEvent(onChangeCb, nodeId, newValue)
                            }
                        },
                        enabled = !disabled
                    )
                }
                "switch" -> {
                    var checked by remember(nodeId, checkedInitial) { mutableStateOf(checkedInitial) }
                    Switch(
                        checked = checked,
                        onCheckedChange = { newValue ->
                            checked = newValue
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendToggleChangeEvent(onChangeCb, nodeId, newValue)
                            }
                        },
                        enabled = !disabled
                    )
                }
                "icon_button" -> {
                    if (hasMenu) {
                        // `:trailing-menu` attached — IconButton becomes a
                        // DropdownMenu trigger. The on_trailing_press
                        // callback is shadowed (menu wins).
                        var menuExpanded by remember { mutableStateOf(false) }
                        Box {
                            IconButton(
                                onClick = { menuExpanded = true },
                                enabled = !disabled,
                            ) {
                                com.nativephp.mobile.ui.MaterialIcon(
                                    name = effectiveValue,
                                    contentDescription = iconButtonDescription,
                                    size = 24.dp,
                                    tint = if (iconColor != 0) Color(iconColor) else Color.Unspecified,
                                )
                            }
                            ExpressiveMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false },
                            ) {
                                menuItems.forEach { item ->
                                    renderAttachedMenuItem(item) { menuExpanded = false }
                                }
                            }
                        }
                    } else {
                        IconButton(
                            onClick = {
                                if (onPressCb != 0) {
                                    NativeUIBridge.sendPressEvent(onPressCb, nodeId)
                                }
                            },
                            enabled = !disabled
                        ) {
                            com.nativephp.mobile.ui.MaterialIcon(
                                name = effectiveValue,
                                contentDescription = iconButtonDescription,
                                size = 24.dp,
                                tint = if (iconColor != 0) Color(iconColor) else Color.Unspecified
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Parse `#RRGGBB` to a Compose Color. Returns null when invalid. */
private fun parseListItemBadgeHex(hex: String): Color? {
    val s = hex.trim().removePrefix("#")
    if (s.length != 6) return null
    return try {
        val v = s.toLong(16)
        Color(
            red = ((v shr 16) and 0xFF) / 255f,
            green = ((v shr 8) and 0xFF) / 255f,
            blue = (v and 0xFF) / 255f,
        )
    } catch (_: Exception) {
        null
    }
}
