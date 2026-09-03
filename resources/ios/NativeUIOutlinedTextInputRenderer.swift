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
                        .foregroundStyle(theme.onSurfaceVariant)
                }
                if !prefixText.isEmpty {
                    Text(prefixText)
                        .nuiScaledFont(size: metrics.textSize)
                        .foregroundStyle(theme.onSurfaceVariant)
                }

                NativeUITextInputCore(
                    node: node,
                    textSize: metrics.textSize,
                    contentColor: disabled ? theme.onSurface.opacity(0.6) : theme.onSurface,
                    tintColor: isError ? theme.destructive : theme.primary,
                    supportsRevealToggle: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if !suffixText.isEmpty {
                    Text(suffixText)
                        .nuiScaledFont(size: metrics.textSize)
                        .foregroundStyle(theme.onSurfaceVariant)
                }
                if loading {
                    ProgressView().controlSize(.small)
                } else if !trailingIcon.isEmpty {
                    Image(systemName: getIconForName(trailingIcon))
                        .nuiScaledFont(size: metrics.iconSize)
                        .foregroundStyle(theme.onSurfaceVariant)
                }
            }
            .padding(.horizontal, metrics.hPadding)
            .padding(.vertical, metrics.vPadding)
            .background(
                // Honor user-supplied border radius via class (e.g.
                // `rounded-full` → 9999 → Capsule shape). Falls back to
                // Material 3's outlined default (theme.radiusMd ≈ 4pt)
                // when no class radius is set.
                RoundedRectangle(
                    cornerRadius: (node.style?.borderRadius ?? 0) > 0
                        ? CGFloat(node.style!.borderRadius)
                        : theme.radiusMd,
                    style: .continuous
                )
                .stroke(borderColor, lineWidth: isError ? 2 : 1)
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
