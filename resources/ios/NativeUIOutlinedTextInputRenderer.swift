import SwiftUI

/// Material3-style outlined text field (iOS / SwiftUI).
///
/// Composition:
///
///   ┌──────────────────────────────┐
///   │ ⎯Label⎯                      │   ← optional floating label
///   │ 🔍 placeholder/value     ✕   │   ← leading icon + core + trailing
///   └──────────────────────────────┘
///     supporting text               ← optional (error-colored if error)
///
/// All chrome colors resolve from `NativeUITheme.shared`. Per-instance color
/// overrides are intentionally not supported (Model 3 — drop to
/// `<pressable>` for fully custom input visuals).
///
/// The box is filled with the `input-fill` theme token and its contents take
/// `on-input`. Both are transparent / absent by default, which is Material 3's
/// outlined container and reproduces this renderer exactly as it was before
/// the tokens existed; an app that wants its fields to read as fields on a
/// colored screen declares the pair and gets one.
struct NativeUIOutlinedTextInputRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props

        let label         = p.getString("label")
        let supporting    = p.getString("supporting")
        let prefixText    = p.getString("prefix")
        let suffixText    = p.getString("suffix")
        let leadingIcon   = p.getString("leading_icon")
        let trailingIcon  = p.getString("trailing_icon")
        let isError       = p.getBool("is_error")
        let disabled      = p.getBool("disabled")
        let readOnly      = p.getBool("read_only")
        let loading       = p.getBool("loading")
        let size          = p.getString("size", default: "md")
        let a11yLabel     = p.getString("a11y_label")
        let a11yHint      = p.getString("a11y_hint")

        let metrics = sizeMetrics(for: size, theme: theme)

        // Border / label color reflect state:
        //   error > focus-hint (we don't track focus here, so fall back to outline) > outline
        let borderColor: Color = isError
            ? theme.destructive
            : (disabled ? theme.outline.opacity(0.5) : theme.outline)

        let labelColor: Color = isError
            ? theme.destructive
            : theme.onSurfaceVariant

        let supportingColor: Color = isError ? theme.destructive : theme.onSurfaceVariant

        // Everything INSIDE the box. Two tones by default — typed text at full
        // emphasis, icons and affixes muted — which is the M3 hierarchy and
        // what this renderer has always drawn. A declared `on-input` collapses
        // both onto itself, because the moment `input-fill` is a saturated
        // color the muted gray stops being a hierarchy and starts being
        // unreadable.
        //
        // `label` and `supporting` sit OUTSIDE the box and are deliberately
        // NOT included: they are painted on the surface behind the field, so
        // they keep taking their color from it.
        let fieldTextColor: Color = theme.onInput ?? theme.onSurface
        let fieldDecorationColor: Color = theme.onInput ?? theme.onSurfaceVariant

        // Honor user-supplied border radius via class (e.g. `rounded-full` →
        // 9999 → Capsule shape). Falls back to Material 3's outlined default
        // (theme.radiusMd ≈ 4pt) when no class radius is set. Hoisted out of
        // the background below now that the fill and the stroke both need it —
        // one shape, two paints, so they cannot drift apart.
        let cornerRadius: CGFloat = (node.style?.borderRadius ?? 0) > 0
            ? CGFloat(node.style!.borderRadius)
            : theme.radiusMd

        // The visible label doubles as the field's accessibility label unless
        // an explicit a11y_label override was provided. When the field is in
        // an error state, the supporting text must be announced: it rides the
        // hint channel, or the value channel if a11y_hint is already taken.
        let effectiveA11yLabel = a11yLabel.isEmpty ? label : a11yLabel
        let errorText = (isError && !supporting.isEmpty) ? supporting : ""
        let effectiveA11yHint = a11yHint.isEmpty ? errorText : a11yHint
        let errorA11yValue = a11yHint.isEmpty ? "" : errorText

        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .nuiScaledFont(size: theme.fontSm, weight: .medium)
                    .foregroundStyle(labelColor)
            }

            HStack(spacing: 8) {
                if !leadingIcon.isEmpty {
                    Image(systemName: getIconForName(leadingIcon))
                        .nuiScaledFont(size: metrics.iconSize)
                        .foregroundStyle(fieldDecorationColor)
                }
                if !prefixText.isEmpty {
                    Text(prefixText)
                        .nuiScaledFont(size: metrics.textSize)
                        .foregroundStyle(fieldDecorationColor)
                }

                NativeUITextInputCore(
                    node: node,
                    textSize: metrics.textSize,
                    contentColor: disabled ? fieldTextColor.opacity(0.6) : fieldTextColor,
                    tintColor: isError ? theme.destructive : theme.primary
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if !suffixText.isEmpty {
                    Text(suffixText)
                        .nuiScaledFont(size: metrics.textSize)
                        .foregroundStyle(fieldDecorationColor)
                }
                if loading {
                    ProgressView().controlSize(.small)
                } else if !trailingIcon.isEmpty {
                    Image(systemName: getIconForName(trailingIcon))
                        .nuiScaledFont(size: metrics.iconSize)
                        .foregroundStyle(fieldDecorationColor)
                }
            }
            .padding(.horizontal, metrics.hPadding)
            .padding(.vertical, metrics.vPadding)
            .background(
                // Fill first, stroke over it, both on the same shape so the
                // border still sits exactly where it did — a stroke centers on
                // its path, and the path here is the background's own frame,
                // unchanged. The fill is decoration only: `.allowsHitTesting`
                // keeps it from swallowing taps that used to fall through the
                // hollow middle of the box.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.inputFill)
                    .allowsHitTesting(false)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(borderColor, lineWidth: isError ? 2 : 1)
                    )
            )
            .opacity(disabled ? 0.6 : 1.0)
            .allowsHitTesting(!disabled && !readOnly)

            if !supporting.isEmpty {
                Text(supporting)
                    .nuiScaledFont(size: theme.fontSm)
                    .foregroundStyle(supportingColor)
            }
        }
        .modifier(A11yLabelModifier(label: effectiveA11yLabel))
        .modifier(A11yHintModifier(hint: effectiveA11yHint))
        .modifier(A11yValueModifier(value: errorA11yValue))
    }

    // ─── Size metrics ────────────────────────────────────────────────────────

    private struct SizeMetrics {
        let textSize: CGFloat
        let iconSize: CGFloat
        let hPadding: CGFloat
        let vPadding: CGFloat
    }

    private func sizeMetrics(for size: String, theme: NativeUITokens) -> SizeMetrics {
        switch size {
        case "sm":
            return SizeMetrics(textSize: theme.fontSm, iconSize: 16, hPadding: 10, vPadding: 8)
        case "lg":
            return SizeMetrics(textSize: theme.fontLg, iconSize: 22, hPadding: 14, vPadding: 14)
        default:
            return SizeMetrics(textSize: theme.fontMd, iconSize: 18, hPadding: 12, vPadding: 11)
        }
    }
}

// MARK: - Accessibility modifiers (conditional)
// Note: duplicated from the button renderer to keep per-file drop-in usable.
// If this pattern spreads further we can lift these into a shared file.

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

private struct A11yValueModifier: ViewModifier {
    let value: String
    func body(content: Content) -> some View {
        if value.isEmpty { content }
        else { content.accessibilityValue(value) }
    }
}
