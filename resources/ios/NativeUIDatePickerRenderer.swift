import SwiftUI

/// SwiftUI DatePicker — date, time, or date+time selection.
///
/// ── Wire contract ────────────────────────────────────────────────────────
///
/// Values cross the bridge as wall-clock ISO 8601 strings with no offset:
/// `2026-07-25` (date), `14:30` (time), `2026-07-25T14:30` (datetime).
///
/// SwiftUI's `DatePicker` binds a `Date`, which is an *instant*, not a wall
/// clock. Every conversion in this file therefore runs through ONE calendar
/// — `resolvedCalendar`, built from the `timezone` prop (device zone when
/// unset) — so a value round-trips: parse wall-clock → instant → render →
/// instant → format wall-clock lands back on the same string. The Android
/// renderer reads `DatePickerState.selectedDateMillis` as UTC for the same
/// reason. Neither side ever ships an instant.
///
/// Echo-prevention value sync (plan K) on the ISO string. Theme-sourced
/// colors (Model 3).
struct NativeUIDatePickerRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    /// The bound instant. Meaningful only through `resolvedCalendar`.
    @State private var selected: Date = Date()
    /// Last ISO string we sent or accepted — echo-prevention anchor.
    @State private var lastSentValue: String = ""
    /// Whether the user has a real selection. When false the picker still
    /// needs *some* instant to bind, so it shows "now" while the trigger
    /// reads as the placeholder.
    @State private var hasSelection: Bool = false
    @State private var initialized: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let serverValue = p.getString("value")
        let mode        = p.getString("mode", default: "date")
        let display     = p.getString("picker_style", default: "compact")
        let label       = p.getString("label")
        let placeholder = p.getString("placeholder")
        let minRaw      = p.getString("min")
        let maxRaw      = p.getString("max")
        let onChangeCb  = p.getCallbackId("on_change")
        let disabled    = p.getBool("disabled")
        let a11yLabel   = p.getString("a11y_label")
        let a11yHint    = p.getString("a11y_hint")
        let isError     = p.getBool("is_error")
        let supporting  = p.getString("supporting")

        // Error state rides the hint channel unless an explicit hint is
        // set (same convention as the text inputs).
        let errorText = (isError && !supporting.isEmpty) ? supporting : ""
        let effectiveA11yHint = a11yHint.isEmpty ? errorText : a11yHint

        let calendar = resolvedCalendar()
        let locale   = resolvedLocale()
        let minDate  = parse(minRaw, mode: mode, calendar: calendar)
        let maxDate  = parse(maxRaw, mode: mode, calendar: calendar)

        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .nuiScaledFont(size: theme.fontSm, weight: .medium)
                    .foregroundStyle(theme.onSurfaceVariant)
            }

            // No selection yet + compact style: SwiftUI's compact picker
            // always renders a concrete date, so there is no native "empty"
            // affordance. Show our own placeholder chip that adopts the
            // current instant on first tap, matching Select's trigger shape.
            if !hasSelection && display == "compact" && !placeholder.isEmpty {
                Button {
                    hasSelection = true
                    commit(mode: mode, calendar: calendar, onChangeCb: onChangeCb)
                } label: {
                    HStack {
                        Text(placeholder)
                            .nuiScaledFont(size: 17)
                            .foregroundStyle(theme.onSurfaceVariant)
                        Spacer()
                        Image(systemName: mode == "time" ? "clock" : "calendar")
                            .foregroundStyle(theme.onSurfaceVariant)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radiusMd, style: .continuous)
                            .stroke(isError ? theme.destructive : theme.outline, lineWidth: 1)
                    )
                }
                .disabled(disabled)
                .opacity(disabled ? 0.6 : 1.0)
            } else {
                picker(
                    mode: mode,
                    minDate: minDate,
                    maxDate: maxDate
                )
                // Our own label sits above; suppress SwiftUI's inline one so
                // the two don't double up.
                .labelsHidden()
                .datePickerStyle(for: display)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .environment(\.locale, locale)
                .tint(theme.primary)
                .disabled(disabled)
                .opacity(disabled ? 0.6 : 1.0)
                // VoiceOver reads the formatted selection as the control's
                // value, so a bare a11y-label still announces what's picked.
                .accessibilityValue(displayString(mode: mode, locale: locale, calendar: calendar))
            }

            if !supporting.isEmpty {
                Text(supporting)
                    .nuiScaledFont(size: theme.fontSm)
                    .foregroundStyle(isError ? theme.destructive : theme.onSurfaceVariant)
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            adopt(serverValue, mode: mode, calendar: calendar)
        }
        .onChange(of: serverValue) { _, new in
            // Echo-prevention: only accept a server push that diverges from
            // what we last sent, or it would clobber an in-flight selection.
            if new != lastSentValue {
                adopt(new, mode: mode, calendar: calendar)
            }
        }
        .onChange(of: selected) { _, _ in
            guard hasSelection else { return }
            commit(mode: mode, calendar: calendar, onChangeCb: onChangeCb)
        }
        .modifier(NativeUIDatePickerA11yLabel(label: a11yLabel))
        .modifier(NativeUIDatePickerA11yHint(hint: effectiveA11yHint))
    }

    // ── Picker construction ──────────────────────────────────────────────────

    /// Four range shapes, four SwiftUI initializers. Kept as explicit
    /// branches because `in:` is overloaded on the range type rather than
    /// taking an optional.
    @ViewBuilder
    private func picker(mode: String, minDate: Date?, maxDate: Date?) -> some View {
        let components = displayedComponents(for: mode)

        switch (minDate, maxDate) {
        case let (lower?, upper?) where lower <= upper:
            DatePicker(selection: $selected, in: lower...upper, displayedComponents: components) { EmptyView() }
        case let (lower?, _):
            DatePicker(selection: $selected, in: lower..., displayedComponents: components) { EmptyView() }
        case let (_, upper?):
            DatePicker(selection: $selected, in: ...upper, displayedComponents: components) { EmptyView() }
        default:
            DatePicker(selection: $selected, displayedComponents: components) { EmptyView() }
        }
    }

    private func displayedComponents(for mode: String) -> DatePickerComponents {
        switch mode {
        case "time":     return [.hourAndMinute]
        case "datetime": return [.date, .hourAndMinute]
        default:         return [.date]
        }
    }

    // ── Value plumbing ───────────────────────────────────────────────────────

    /// Accept an inbound wire value: an empty string clears the selection,
    /// anything parseable becomes the bound instant.
    private func adopt(_ raw: String, mode: String, calendar: Calendar) {
        lastSentValue = raw

        guard let date = parse(raw, mode: mode, calendar: calendar) else {
            hasSelection = false
            return
        }

        selected = date
        hasSelection = true
    }

    /// Format the current instant back to wall-clock and dispatch it.
    private func commit(mode: String, calendar: Calendar, onChangeCb: Int) {
        let iso = format(selected, mode: mode, calendar: calendar)
        guard iso != lastSentValue else { return }
        lastSentValue = iso

        if onChangeCb != 0 {
            NativeElementBridge.sendSelectChangeEvent(onChangeCb, nodeId: node.id, value: iso)
        }
    }

    /// Wall-clock string → instant, via `calendar`. Returns nil for an empty
    /// or malformed value (PHP validates before serializing, so malformed
    /// here means a hand-built prop).
    private func parse(_ raw: String, mode: String, calendar: Calendar) -> Date? {
        guard !raw.isEmpty else { return nil }
        return wireFormatter(mode: mode, timeZone: calendar.timeZone).date(from: raw)
    }

    /// Instant → wall-clock string, via `calendar`.
    private func format(_ date: Date, mode: String, calendar: Calendar) -> String {
        wireFormatter(mode: mode, timeZone: calendar.timeZone).string(from: date)
    }

    /// Fixed-format formatter for the WIRE value. Pinned to `en_US_POSIX` so
    /// the pattern is never reinterpreted by the device locale — a
    /// Buddhist or Japanese-era calendar locale would otherwise emit a
    /// non-Gregorian year here. Display formatting is a separate concern
    /// (see `displayString`).
    private func wireFormatter(mode: String, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        switch mode {
        case "time":     f.dateFormat = "HH:mm"
        case "datetime": f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        default:         f.dateFormat = "yyyy-MM-dd"
        }
        return f
    }

    /// Human-readable selection for VoiceOver, in the resolved locale.
    private func displayString(mode: String, locale: Locale, calendar: Calendar) -> String {
        guard hasSelection else { return "" }

        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        switch mode {
        case "time":
            f.dateStyle = .none
            f.timeStyle = .short
        case "datetime":
            f.dateStyle = .medium
            f.timeStyle = .short
        default:
            f.dateStyle = .medium
            f.timeStyle = .none
        }
        return f.string(from: selected)
    }

    // ── Internationalization ─────────────────────────────────────────────────

    /// Calendar carrying the resolved timezone. Every wall-clock ↔ instant
    /// conversion in this file goes through it.
    private func resolvedCalendar() -> Calendar {
        var calendar = Calendar.current
        let identifier = node.props.getString("timezone")
        if !identifier.isEmpty, let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }
        calendar.locale = resolvedLocale()
        return calendar
    }

    /// Display locale, with the `hour_format` override folded in.
    ///
    /// SwiftUI has no direct 12/24-hour switch — the clock convention rides
    /// on the locale. `Locale.Components` (iOS 16+) lets us clone the
    /// resolved locale and override just `hourCycle`, which is cleaner than
    /// the usual trick of swapping in an unrelated locale (`en_GB`) whose
    /// month names would then be wrong.
    private func resolvedLocale() -> Locale {
        let tag = node.props.getString("locale")
        let base = tag.isEmpty ? Locale.current : Locale(identifier: tag.replacingOccurrences(of: "-", with: "_"))

        let hourFormat = node.props.getString("hour_format", default: "auto")
        guard hourFormat == "12" || hourFormat == "24" else { return base }

        // Spelled out rather than an implicit-member ternary: the target is
        // `Locale.HourCycle?`, and inference through a double-optional
        // context is exactly where implicit members get ambiguous.
        let cycle: Locale.HourCycle = hourFormat == "24" ? .zeroToTwentyThree : .oneToTwelve
        var components = Locale.Components(locale: base)
        components.hourCycle = cycle
        return Locale(components: components)
    }
}

// MARK: - Style application

private extension View {
    /// `display` → SwiftUI picker style. `wheel` has no Android counterpart
    /// (documented as falling back to inline there); on iOS it's native.
    @ViewBuilder
    func datePickerStyle(for display: String) -> some View {
        switch display {
        case "inline": self.datePickerStyle(.graphical)
        case "wheel":  self.datePickerStyle(.wheel)
        default:       self.datePickerStyle(.compact)
        }
    }
}

// MARK: - Accessibility modifiers (conditional)

private struct NativeUIDatePickerA11yLabel: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}

private struct NativeUIDatePickerA11yHint: ViewModifier {
    let hint: String
    func body(content: Content) -> some View {
        if hint.isEmpty { content }
        else { content.accessibilityHint(hint) }
    }
}
