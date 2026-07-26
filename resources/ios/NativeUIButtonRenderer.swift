import SwiftUI

/// SwiftUI Button renderer.
///
/// Maps semantic `variant` prop to the matching SwiftUI button style:
///   - primary     → `.buttonStyle(.borderedProminent)` + `.tint(theme.primary)`
///   - secondary   → `.buttonStyle(.borderedProminent)` + `.tint(theme.secondary)`
///     (solid, like primary — for a tonal look set opacity on the token in
///     the theme config, e.g. `'secondary' => 'fuchsia-500/70'`)
///   - destructive → `.buttonStyle(.borderedProminent)` + `.tint(theme.destructive)`
///   - success     → `.buttonStyle(.borderedProminent)` + `.tint(theme.success)`
///   - accent      → `.buttonStyle(.borderedProminent)` + `.tint(theme.accent)`
///   - ghost       → `.buttonStyle(.plain)` + `.foregroundStyle(theme.primary)`
///
/// Tailwind `glass` family promotes the button to iOS 26's first-class
/// glass styles when available, falling back to bordered styles on older iOS.
/// Bitflag layout (matches `TailwindParser::parseGlassClass`):
///
///   bit 0 (1) — enabled
///   bit 1 (2) — prominent → `.buttonStyle(.glassProminent)` instead of `.glass`
///   bit 2 (4) — interactive (specular touch highlight; mostly redundant on
///                buttons since the buttonStyle already provides press feedback)
///
/// Markup:
///   class="glass"                       — regular glass
///   class="glass:prominent"             — prominent (filled) glass
///   class="glass:interactive"           — regular glass + interactive highlight
///   class="glass:prominent:interactive" — both
///
/// `glass:clear` (bit 3) drops the button to `.buttonStyle(.plain)` and
/// applies `.glassEffect(.clear, in: Capsule())` directly, since iOS 26
/// doesn't ship a `.buttonStyle(.glassClear)`. The label keeps its
/// variant-driven tint as the foreground color.
///
/// The variant's tint flows through both glass styles, so
/// `<button class="glass:prominent" variant="destructive">` reads as a
/// destructive-tinted prominent glass button on iOS 26+.
///
/// All colors come from the `\.nativeUITheme` environment. No per-instance
/// color/radius/shadow overrides are honored — that's intentional (plan doc
/// Model 3). For full visual control, use `<pressable>`.
struct NativeUIButtonRenderer: View {
    let node: NativeUINode
    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let hasMenu = node.props.getBool("has_menu")
        if hasMenu {
            let items = node.children.filter { $0.type == "top_bar_action" }
            Menu {
                ForEach(items) { item in buttonMenuItem(item) }
            } label: {
                buttonBody()
            }
        } else {
            buttonBody()
        }
    }

    @ViewBuilder
    private func buttonBody() -> some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let variant = p.getString("variant", default: "primary")
        let size = p.getString("size", default: "md")
        let label = p.getString("label")
        let disabled = p.getBool("disabled")
        let loading = p.getBool("loading")
        let icon = p.getString("leading_icon")
        let iconTrailing = p.getString("trailing_icon")
        let a11yLabel = p.getString("a11y_label")
        let a11yHint = p.getString("a11y_hint")
        let glassFlags = p.getInt("glass", default: 0)
        let glassEnabled    = (glassFlags & 1) != 0
        let glassProminent  = (glassFlags & 2) != 0
        let glassInteractive = (glassFlags & 4) != 0
        let glassClear      = (glassFlags & 8) != 0
        let pressCb = p.getCallbackId("on_press") != 0 ? p.getCallbackId("on_press") : node.onPress

        let metrics = sizeMetrics(for: size, theme: theme)
        let enabled = !disabled && !loading

        // Class-level text-size override. `text-xl` / `text-[28]` / etc.
        // arrive as a `font_size` prop. When set (>0), it wins over the
        // size-prop metric so authors can scale a button's label without
        // touching `size`. iconSize is left at the size-driven default —
        // changing icon size off the text scale would surprise users.
        let classFontSize = CGFloat(p.getFloat("font_size"))
        let textSize = classFontSize > 0 ? classFontSize : metrics.textSize
        let fontName = p.getString("font_name")
        // Leading — button labels are single-line, so this is usually a no-op.
        let lineSpacing = NativeUIFontResolver.lineSpacing(
            px: p.getFloat("line_height_px"),
            mult: p.getFloat("line_height"),
            fontSize: textSize,
            fontName: fontName
        )

        let action = {
            if pressCb != 0 {
                NativeElementBridge.sendPressEvent(pressCb, nodeId: node.id)
            }
        }

        let content = ButtonContent(
            label: label,
            icon: icon,
            iconTrailing: iconTrailing,
            loading: loading,
            iconSize: metrics.iconSize,
            textSize: textSize,
            fontName: fontName.isEmpty ? nil : fontName,
            lineSpacing: lineSpacing,
            spinnerColor: theme.onSurfaceVariant
        )
        // `.fillWidthIfRequested(node)` is applied INSIDE the Button's
        // label closure at each variant call site below. SwiftUI's
        // Button sizes to its label's intrinsic width, so we have to
        // expand the LABEL (not the outer Button frame) to honor
        // `w-full`. See `NativeUIFillWidthHelper.swift`.

        // Glass takes precedence over variant. iOS 26+ uses real `.glass` /
        // `.glassProminent`; older iOS falls back to bordered styles tinted
        // by variant — same UI hierarchy, no specular reflection.
        if glassEnabled {
            glassButton(
                prominent: glassProminent,
                interactive: glassInteractive,
                clear: glassClear,
                action: action,
                content: content,
                variant: variant,
                theme: theme,
                metrics: metrics,
                enabled: enabled,
                a11yLabel: a11yLabel,
                a11yHint: a11yHint
            )
        } else {
            variantButton(
                action: action,
                content: content,
                variant: variant,
                theme: theme,
                metrics: metrics,
                enabled: enabled,
                a11yLabel: a11yLabel,
                a11yHint: a11yHint
            )
        }
    }

    // MARK: - Glass path (iOS 26 first-class, older iOS bordered fallback)

    @ViewBuilder
    private func glassButton(
        prominent: Bool,
        interactive: Bool,
        clear: Bool,
        action: @escaping () -> Void,
        content: ButtonContent,
        variant: String,
        theme: NativeUITokens,
        metrics: SizeMetrics,
        enabled: Bool,
        a11yLabel: String,
        a11yHint: String
    ) -> some View {
        let tint = tintForVariant(variant, theme: theme)
        let onTint = onTintForVariant(variant, theme: theme)

        // Note: `interactive` on a button is mostly redundant — the button
        // already has built-in press feedback through SwiftUI's button styles.
        // We still chain it through `.glassEffect()` underneath when set so
        // the user gets the explicit specular highlight on press.
        if #available(iOS 26.0, *) {
            if clear {
                // No `.buttonStyle(.glassClear)` exists — drop to plain and
                // apply `.glassEffect(.clear)` directly. Variant tint flows
                // through as the label's foreground color.
                Button(action: action) { content.foregroundStyle(tint).fillWidthIfRequested(node) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.clear.interactive(interactive), in: Capsule())
                    .controlSize(metrics.controlSize)
                    .disabled(!enabled)
                    .modifier(A11yLabelModifier(label: a11yLabel))
                    .modifier(A11yHintModifier(hint: a11yHint))
            } else if prominent {
                Button(action: action) { content.fillWidthIfRequested(node) }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                    .foregroundStyle(onTint)
                    .controlSize(metrics.controlSize)
                    .disabled(!enabled)
                    .modifier(A11yLabelModifier(label: a11yLabel))
                    .modifier(A11yHintModifier(hint: a11yHint))
            } else {
                Button(action: action) { content.fillWidthIfRequested(node) }
                    .buttonStyle(.glass)
                    .tint(tint)
                    .controlSize(metrics.controlSize)
                    .disabled(!enabled)
                    .modifier(A11yLabelModifier(label: a11yLabel))
                    .modifier(A11yHintModifier(hint: a11yHint))
            }
        } else {
            // Pre-iOS 26 fallback. `.borderedProminent` for prominent (filled),
            // `.bordered` otherwise (light translucent chrome). Variant tint
            // still applies so `glass:prominent` + `variant="destructive"`
            // reads as a destructive button on older iOS too.
            if prominent {
                Button(action: action) { content.fillWidthIfRequested(node) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .foregroundStyle(onTint)
                    .controlSize(metrics.controlSize)
                    .disabled(!enabled)
                    .modifier(A11yLabelModifier(label: a11yLabel))
                    .modifier(A11yHintModifier(hint: a11yHint))
            } else {
                Button(action: action) { content.fillWidthIfRequested(node) }
                    .buttonStyle(.bordered)
                    .tint(tint)
                    .controlSize(metrics.controlSize)
                    .disabled(!enabled)
                    .modifier(A11yLabelModifier(label: a11yLabel))
                    .modifier(A11yHintModifier(hint: a11yHint))
            }
        }
    }

    // MARK: - Variant path (existing behaviour, unchanged)

    @ViewBuilder
    private func variantButton(
        action: @escaping () -> Void,
        content: ButtonContent,
        variant: String,
        theme: NativeUITokens,
        metrics: SizeMetrics,
        enabled: Bool,
        a11yLabel: String,
        a11yHint: String
    ) -> some View {
        // Disabled state (all variants): `surface-variant` fill +
        // `on-surface-variant` label from the theme. Explicit tints and
        // `.foregroundStyle` persist through `.disabled()` — the system
        // only dims, which left e.g. a white label on a pale fill. Android
        // uses the same token pair, so disabled looks identical there.
        switch variant {
        case "secondary":
            // Solid fill of the secondary token, same treatment as primary.
            // No renderer-imposed alpha: transparency belongs to the theme
            // config (e.g. `'secondary' => 'fuchsia-500/70'`). `.bordered`
            // would render the tint at ~15% opacity and lose the label.
            Button(action: action) { content.fillWidthIfRequested(node) }
                .buttonStyle(.borderedProminent)
                .tint(enabled ? theme.secondary : theme.surfaceVariant)
                .foregroundStyle(enabled ? theme.onSecondary : theme.onSurfaceVariant)
                .controlSize(metrics.controlSize)
                .disabled(!enabled)
                .modifier(A11yLabelModifier(label: a11yLabel))
                .modifier(A11yHintModifier(hint: a11yHint))

        case "destructive":
            // Note: not using `role: .destructive` — it fights `.tint()` on
            // `.borderedProminent` and can render as the system destructive
            // color rather than the theme's destructive token.
            Button(action: action) { content.fillWidthIfRequested(node) }
                .buttonStyle(.borderedProminent)
                .tint(enabled ? theme.destructive : theme.surfaceVariant)
                .foregroundStyle(enabled ? theme.onDestructive : theme.onSurfaceVariant)
                .controlSize(metrics.controlSize)
                .disabled(!enabled)
                .modifier(A11yLabelModifier(label: a11yLabel))
                .modifier(A11yHintModifier(hint: a11yHint))

        case "success":
            Button(action: action) { content.fillWidthIfRequested(node) }
                .buttonStyle(.borderedProminent)
                .tint(enabled ? theme.success : theme.surfaceVariant)
                .foregroundStyle(enabled ? theme.onSuccess : theme.onSurfaceVariant)
                .controlSize(metrics.controlSize)
                .disabled(!enabled)
                .modifier(A11yLabelModifier(label: a11yLabel))
                .modifier(A11yHintModifier(hint: a11yHint))

        case "ghost":
            Button(action: action) { content.fillWidthIfRequested(node) }
                .buttonStyle(.plain)
                .foregroundStyle(enabled ? theme.primary : theme.onSurfaceVariant)
                .controlSize(metrics.controlSize)
                .disabled(!enabled)
                .modifier(A11yLabelModifier(label: a11yLabel))
                .modifier(A11yHintModifier(hint: a11yHint))

        case "accent":
            Button(action: action) { content.fillWidthIfRequested(node) }
                .buttonStyle(.borderedProminent)
                .tint(enabled ? theme.accent : theme.surfaceVariant)
                .foregroundStyle(enabled ? theme.onAccent : theme.onSurfaceVariant)
                .controlSize(metrics.controlSize)
                .disabled(!enabled)
                .modifier(A11yLabelModifier(label: a11yLabel))
                .modifier(A11yHintModifier(hint: a11yHint))

        default: // "primary" and any unknown value
            Button(action: action) { content.fillWidthIfRequested(node) }
                .buttonStyle(.borderedProminent)
                .tint(enabled ? theme.primary : theme.surfaceVariant)
                .foregroundStyle(enabled ? theme.onPrimary : theme.onSurfaceVariant)
                .controlSize(metrics.controlSize)
                .disabled(!enabled)
                .modifier(A11yLabelModifier(label: a11yLabel))
                .modifier(A11yHintModifier(hint: a11yHint))
        }
    }

    // MARK: - Tint helpers (glass path only — variant path uses tints inline)

    private func tintForVariant(_ variant: String, theme: NativeUITokens) -> Color {
        switch variant {
        case "secondary":   return theme.secondary
        case "destructive": return theme.destructive
        case "success":     return theme.success
        case "accent":      return theme.accent
        case "ghost":       return theme.primary
        default:            return theme.primary
        }
    }

    private func onTintForVariant(_ variant: String, theme: NativeUITokens) -> Color {
        switch variant {
        case "secondary":   return theme.onSecondary
        case "destructive": return theme.onDestructive
        case "success":     return theme.onSuccess
        case "accent":      return theme.onAccent
        case "ghost":       return theme.primary
        default:            return theme.onPrimary
        }
    }

    // MARK: - Size metrics

    private struct SizeMetrics {
        let controlSize: ControlSize
        let iconSize: CGFloat
        let textSize: CGFloat
    }

    private func sizeMetrics(for size: String, theme: NativeUITokens) -> SizeMetrics {
        switch size {
        case "sm":
            return SizeMetrics(controlSize: .small,   iconSize: 14, textSize: theme.fontSm)
        case "lg":
            return SizeMetrics(controlSize: .large,   iconSize: 22, textSize: theme.fontLg)
        default:
            return SizeMetrics(controlSize: .regular, iconSize: 18, textSize: theme.fontMd)
        }
    }
}

// MARK: - Content (label + icons, or spinner)

private struct ButtonContent: View {
    let label: String
    let icon: String
    let iconTrailing: String
    let loading: Bool
    let iconSize: CGFloat
    let textSize: CGFloat
    var fontName: String? = nil
    var lineSpacing: CGFloat = 0
    var spinnerColor: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            if loading {
                // Explicit tint: the spinner follows the Button's tint by
                // default, which in the loading (= disabled) state is the
                // pale surface-variant fill — invisible against itself.
                // Matches Android, where the spinner uses the content color.
                ProgressView()
                    .controlSize(.small)
                    .tint(spinnerColor)
                if !label.isEmpty {
                    Text(label).nuiScaledFont(size: textSize, weight: .medium, fontName: fontName).lineSpacing(lineSpacing)
                }
            } else {
                if !icon.isEmpty {
                    Image(systemName: getIconForName(icon))
                        .nuiScaledFont(size: iconSize)
                }
                if !label.isEmpty {
                    Text(label).nuiScaledFont(size: textSize, weight: .medium, fontName: fontName).lineSpacing(lineSpacing)
                }
                if !iconTrailing.isEmpty {
                    Image(systemName: getIconForName(iconTrailing))
                        .nuiScaledFont(size: iconSize)
                }
            }
        }
        // Merged up into the Button's accessibility element so VoiceOver
        // announces the in-flight state.
        .modifier(A11yLoadingValueModifier(loading: loading))
    }
}

// MARK: - Accessibility modifiers (conditional)

private struct A11yLoadingValueModifier: ViewModifier {
    let loading: Bool
    func body(content: Content) -> some View {
        if loading { content.accessibilityValue("Loading") }
        else { content }
    }
}

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

/// Render one menu item attached to a Button via `:menu`. Mirrors the
/// pattern used by `pressableMenuItem` and `TopBarActionView`.
@ViewBuilder
private func buttonMenuItem(_ item: NativeUINode) -> some View {
    if item.props.getBool("divider") {
        Divider()
    } else {
        let label = item.props.getString("label", default: "")
        let icon = item.props.getString("icon", default: "")
        let isDestructive = item.props.getBool("destructive")
        Button(role: isDestructive ? .destructive : nil) {
            if item.onPress != 0 {
                NativeElementBridge.sendPressEvent(item.onPress, nodeId: item.id)
            }
        } label: {
            if !icon.isEmpty {
                Label(label, systemImage: getIconForName(icon))
            } else {
                Text(label)
            }
        }
        .tint(isDestructive ? .red : nil)
    }
}
