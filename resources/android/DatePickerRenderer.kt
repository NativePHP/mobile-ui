package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.MaterialIcon
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme
import com.nativephp.plugins.native_ui.NativeUITokens
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Material3 date / time picker.
 *
 * ── Wire contract ────────────────────────────────────────────────────────
 *
 * Values cross the bridge as wall-clock ISO 8601 strings with no offset:
 * `2026-07-25` (date), `14:30` (time), `2026-07-25T14:30` (datetime). That
 * maps exactly onto `java.time`'s ISO_LOCAL_* formats, so parse/format is
 * `LocalDate.parse` / `toString` with no formatter juggling.
 *
 * THE off-by-one trap: `DatePickerState.selectedDateMillis` is epoch millis
 * at UTC midnight for the tapped cell — it is NOT an instant in the display
 * timezone. Reading it in the device zone shifts the date by a day for any
 * negative-offset zone. Every conversion here therefore pins [ZoneOffset.UTC]
 * for the date-picker state specifically, independent of the `timezone`
 * prop, which governs the *calendar the user is picking in* (what "today"
 * means) rather than how the picked cell is decoded.
 *
 * Times need no conversion at all — `TimePickerState.hour/minute` are
 * already wall-clock.
 *
 * Echo-prevention value sync (plan K), theme-sourced colors (Model 3).
 */
object DatePickerRenderer {

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue  = p.getString("value")
        val mode         = p.getString("mode", "date")
        val display      = p.getString("picker_style", "compact")
        val label        = p.getString("label")
        val placeholder  = p.getString("placeholder")
        val title        = p.getString("title")
        val confirmLabel = p.getString("confirm_label", "OK")
        val cancelLabel  = p.getString("cancel_label", "Cancel")
        val minRaw       = p.getString("min")
        val maxRaw       = p.getString("max")
        val hourFormat   = p.getString("hour_format", "auto")
        val onChangeCb   = p.getCallbackId("on_change")
        val disabled     = p.getBool("disabled")
        val a11yLabel    = p.getString("a11y_label")
        val a11yHint     = p.getString("a11y_hint")
        val isError      = p.getBool("is_error")
        val supporting   = p.getString("supporting")

        val theme  = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        val zone   = resolveZone(p.getString("timezone"))
        val locale = resolveLocale(p.getString("locale"))
        val is24   = resolve24Hour(hourFormat, locale)

        var value by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }
        var showDialog by remember { mutableStateOf(false) }
        // datetime on the compact path is two dialogs back to back: pick the
        // date, then the time. This holds the date leg between them.
        var pendingDate by remember { mutableStateOf<LocalDate?>(null) }

        LaunchedEffect(serverValue) {
            // Only accept a server push that diverges from what we last sent,
            // or it clobbers an in-flight selection with a stale echo.
            if (serverValue != lastSentValue) {
                value = serverValue
                lastSentValue = serverValue
            }
        }

        val commit: (String) -> Unit = { iso ->
            if (iso != lastSentValue) {
                value = iso
                lastSentValue = iso
                if (onChangeCb != 0) {
                    NativeUIBridge.sendSelectChangeEvent(onChangeCb, node.id, iso)
                }
            }
        }

        val minDate = parseDate(minRaw, mode)
        val maxDate = parseDate(maxRaw, mode)
        val shown   = displayString(value, mode, locale, is24)

        // `wheel` is an iOS drum style with no Material counterpart; it
        // degrades to the embedded picker here (documented in the README).
        val embedded = display == "inline" || display == "wheel"

        Column(modifier = modifier.nuiA11y(a11yLabel.ifEmpty { label }, a11yHint)) {
            if (label.isNotEmpty()) {
                Text(
                    text = label,
                    fontFamily = nuiDefaultFontFamily(),
                    color = theme.onSurfaceVariant,
                    style = TextStyle(fontSize = theme.fontSm),
                )
            }

            if (embedded) {
                EmbeddedPicker(
                    mode = mode,
                    value = value,
                    zone = zone,
                    is24 = is24,
                    minDate = minDate,
                    maxDate = maxDate,
                    theme = theme,
                    onCommit = commit,
                )
            } else {
                // Trigger. An OutlinedTextField can't take clicks while
                // readOnly, so a transparent sibling Box in the same layout
                // slot captures them — keeps the field's normal (non-disabled)
                // colors, which `enabled = false` would grey out.
                Box {
                    OutlinedTextField(
                        value = shown,
                        onValueChange = {},
                        readOnly = true,
                        enabled = !disabled,
                        isError = isError,
                        supportingText = supportingSlot(supporting),
                        placeholder = if (placeholder.isNotEmpty()) {
                            { Text(placeholder, fontFamily = nuiDefaultFontFamily()) }
                        } else null,
                        trailingIcon = {
                            MaterialIcon(
                                name = if (mode == "time") "clock" else "calendar",
                                contentDescription = null,
                                tint = theme.onSurfaceVariant,
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        textStyle = TextStyle(color = theme.onSurface),
                        colors = OutlinedTextFieldDefaults.colors(
                            errorBorderColor = theme.destructive,
                            errorSupportingTextColor = theme.destructive,
                            errorTrailingIconColor = theme.destructive,
                            focusedTextColor = theme.onSurface,
                            unfocusedTextColor = theme.onSurface,
                            focusedBorderColor = theme.primary,
                            unfocusedBorderColor = theme.outline,
                            disabledBorderColor = theme.outline.copy(alpha = 0.5f),
                            focusedPlaceholderColor = theme.onSurfaceVariant,
                            unfocusedPlaceholderColor = theme.onSurfaceVariant,
                            focusedTrailingIconColor = theme.onSurfaceVariant,
                            unfocusedTrailingIconColor = theme.onSurfaceVariant,
                        ),
                    )
                    Box(
                        Modifier
                            .matchParentSize()
                            .clickable(enabled = !disabled) {
                                pendingDate = null
                                showDialog = true
                            }
                    )
                }
            }
        }

        if (showDialog) {
            // datetime runs the date leg first, then re-enters for the time
            // leg with `pendingDate` set.
            val leg = when {
                mode == "time" -> "time"
                mode == "datetime" && pendingDate != null -> "time"
                else -> "date"
            }

            if (leg == "date") {
                DateDialog(
                    initial = parseDate(value, mode) ?: LocalDate.now(zone),
                    minDate = minDate,
                    maxDate = maxDate,
                    title = title,
                    confirmLabel = confirmLabel,
                    cancelLabel = cancelLabel,
                    onCancel = { showDialog = false; pendingDate = null },
                    onConfirm = { picked ->
                        if (mode == "datetime") {
                            // Hold the date and fall through to the time leg.
                            pendingDate = picked
                        } else {
                            showDialog = false
                            commit(picked.toString())
                        }
                    },
                )
            } else {
                val initialTime = parseTime(value, mode) ?: LocalTime.now(zone).withSecond(0).withNano(0)
                TimeDialog(
                    initial = initialTime,
                    is24 = is24,
                    title = title,
                    confirmLabel = confirmLabel,
                    cancelLabel = cancelLabel,
                    onCancel = { showDialog = false; pendingDate = null },
                    onConfirm = { picked ->
                        showDialog = false
                        val iso = if (mode == "datetime") {
                            val date = pendingDate ?: parseDate(value, mode) ?: LocalDate.now(zone)
                            LocalDateTime.of(date, picked).toString()
                        } else {
                            picked.toString()
                        }
                        pendingDate = null
                        commit(iso)
                    },
                )
            }
        }
    }

    // ── Embedded (inline) presentation ───────────────────────────────────────

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun EmbeddedPicker(
        mode: String,
        value: String,
        zone: ZoneId,
        is24: Boolean,
        minDate: LocalDate?,
        maxDate: LocalDate?,
        theme: NativeUITokens,
        onCommit: (String) -> Unit,
    ) {
        // An embedded picker must bind SOME date, so with no incoming value
        // it seeds to today. Committing that on mount would silently write a
        // selection the user never made, so the initial millis are held and
        // the first effect pass is skipped while the value is still empty.
        val seededEmpty = value.isEmpty()

        Column {
            if (mode == "date" || mode == "datetime") {
                val initialMillis = (parseDate(value, mode) ?: LocalDate.now(zone)).toUtcMillis()
                val state = rememberDatePickerState(
                    initialSelectedDateMillis = initialMillis,
                    selectableDates = boundedDates(minDate, maxDate),
                    yearRange = yearRange(minDate, maxDate),
                )
                DatePicker(
                    state = state,
                    showModeToggle = true,
                    colors = DatePickerDefaults.colors(
                        selectedDayContainerColor = theme.primary,
                        todayDateBorderColor = theme.primary,
                    ),
                )
                LaunchedEffect(state.selectedDateMillis) {
                    val millis = state.selectedDateMillis ?: return@LaunchedEffect
                    if (seededEmpty && millis == initialMillis) return@LaunchedEffect
                    val picked = millis.toUtcLocalDate()
                    if (mode == "date") {
                        onCommit(picked.toString())
                    } else {
                        val time = parseTime(value, mode) ?: LocalTime.MIDNIGHT
                        onCommit(LocalDateTime.of(picked, time).toString())
                    }
                }
            }

            if (mode == "time" || mode == "datetime") {
                val initial = parseTime(value, mode) ?: LocalTime.now(zone).withSecond(0).withNano(0)
                val state = rememberTimePickerState(
                    initialHour = initial.hour,
                    initialMinute = initial.minute,
                    is24Hour = is24,
                )
                TimePicker(state = state, modifier = Modifier.padding(top = 8.dp))
                LaunchedEffect(state.hour, state.minute) {
                    val picked = LocalTime.of(state.hour, state.minute)
                    // Same mount-time guard as the date leg above.
                    if (seededEmpty && picked == LocalTime.of(initial.hour, initial.minute)) {
                        return@LaunchedEffect
                    }
                    if (mode == "time") {
                        onCommit(picked.toString())
                    } else {
                        val date = parseDate(value, mode) ?: LocalDate.now(zone)
                        onCommit(LocalDateTime.of(date, picked).toString())
                    }
                }
            }
        }
    }

    // ── Dialogs ──────────────────────────────────────────────────────────────

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun DateDialog(
        initial: LocalDate,
        minDate: LocalDate?,
        maxDate: LocalDate?,
        title: String,
        confirmLabel: String,
        cancelLabel: String,
        onCancel: () -> Unit,
        onConfirm: (LocalDate) -> Unit,
    ) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = initial.toUtcMillis(),
            selectableDates = boundedDates(minDate, maxDate),
            yearRange = yearRange(minDate, maxDate),
        )

        DatePickerDialog(
            onDismissRequest = onCancel,
            confirmButton = {
                TextButton(onClick = {
                    val picked = state.selectedDateMillis?.toUtcLocalDate() ?: initial
                    onConfirm(picked)
                }) { Text(confirmLabel, fontFamily = nuiDefaultFontFamily()) }
            },
            dismissButton = {
                TextButton(onClick = onCancel) {
                    Text(cancelLabel, fontFamily = nuiDefaultFontFamily())
                }
            },
        ) {
            DatePicker(
                state = state,
                title = if (title.isNotEmpty()) {
                    { Text(title, fontFamily = nuiDefaultFontFamily(), modifier = Modifier.padding(16.dp)) }
                } else null,
                showModeToggle = true,
            )
        }
    }

    /**
     * Material3 ships `DatePickerDialog` but has no time equivalent — per
     * Google's own docs the wrapper is the caller's job, so this reuses
     * `DatePickerDialog` as the surface to keep both legs of a `datetime`
     * pick visually identical.
     */
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun TimeDialog(
        initial: LocalTime,
        is24: Boolean,
        title: String,
        confirmLabel: String,
        cancelLabel: String,
        onCancel: () -> Unit,
        onConfirm: (LocalTime) -> Unit,
    ) {
        val state = rememberTimePickerState(
            initialHour = initial.hour,
            initialMinute = initial.minute,
            is24Hour = is24,
        )
        // Dial by default; the keyboard-entry variant is the accessible
        // fallback and the one users on a screen reader reach for.
        var keyboardEntry by remember { mutableStateOf(false) }

        DatePickerDialog(
            onDismissRequest = onCancel,
            confirmButton = {
                TextButton(onClick = { onConfirm(LocalTime.of(state.hour, state.minute)) }) {
                    Text(confirmLabel, fontFamily = nuiDefaultFontFamily())
                }
            },
            dismissButton = {
                TextButton(onClick = onCancel) {
                    Text(cancelLabel, fontFamily = nuiDefaultFontFamily())
                }
            },
        ) {
            Column(Modifier.padding(16.dp)) {
                if (title.isNotEmpty()) {
                    Text(title, fontFamily = nuiDefaultFontFamily(), modifier = Modifier.padding(bottom = 12.dp))
                }
                if (keyboardEntry) {
                    TimeInput(state = state)
                } else {
                    TimePicker(state = state)
                }
                TextButton(onClick = { keyboardEntry = !keyboardEntry }) {
                    Text(
                        text = if (keyboardEntry) "Dial" else "Keyboard",
                        fontFamily = nuiDefaultFontFamily(),
                    )
                }
            }
        }
    }

    // ── Wire parsing / formatting ────────────────────────────────────────────
    //
    // The wire shapes ARE java.time's ISO_LOCAL_* formats, so `parse` and
    // `toString` round-trip without a custom formatter. `LocalTime.toString()`
    // and `LocalDateTime.toString()` both drop zero seconds, which is exactly
    // the `HH:mm` / `yyyy-MM-ddTHH:mm` the contract specifies.

    private fun parseDate(raw: String, mode: String): LocalDate? {
        if (raw.isEmpty()) return null
        return runCatching {
            when (mode) {
                "datetime" -> LocalDateTime.parse(raw).toLocalDate()
                "date" -> LocalDate.parse(raw)
                else -> null
            }
        }.getOrNull()
    }

    private fun parseTime(raw: String, mode: String): LocalTime? {
        if (raw.isEmpty()) return null
        return runCatching {
            when (mode) {
                "datetime" -> LocalDateTime.parse(raw).toLocalTime()
                "time" -> LocalTime.parse(raw)
                else -> null
            }
        }.getOrNull()
    }

    /** UTC midnight millis — the units `DatePickerState` speaks. */
    private fun LocalDate.toUtcMillis(): Long =
        this.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

    /** Inverse of [toUtcMillis]. Pinned to UTC — see the class doc. */
    private fun Long.toUtcLocalDate(): LocalDate =
        Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()

    @OptIn(ExperimentalMaterial3Api::class)
    private fun boundedDates(minDate: LocalDate?, maxDate: LocalDate?): SelectableDates =
        object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                val date = utcTimeMillis.toUtcLocalDate()
                if (minDate != null && date.isBefore(minDate)) return false
                if (maxDate != null && date.isAfter(maxDate)) return false
                return true
            }

            override fun isSelectableYear(year: Int): Boolean {
                if (minDate != null && year < minDate.year) return false
                if (maxDate != null && year > maxDate.year) return false
                return true
            }
        }

    /** Narrow the year wheel to the bounds so scrolling isn't unbounded. */
    private fun yearRange(minDate: LocalDate?, maxDate: LocalDate?): IntRange {
        val currentYear = LocalDate.now().year
        val start = minDate?.year ?: (currentYear - 100)
        val end = maxDate?.year ?: (currentYear + 100)
        return if (start <= end) start..end else start..start
    }

    /** Locale-formatted selection for the trigger field. Display only. */
    private fun displayString(value: String, mode: String, locale: Locale, is24: Boolean): String {
        if (value.isEmpty()) return ""

        return runCatching {
            when (mode) {
                "time" -> {
                    val t = LocalTime.parse(value)
                    if (is24) t.format(DateTimeFormatter.ofPattern("HH:mm", locale))
                    else t.format(DateTimeFormatter.ofPattern("h:mm a", locale))
                }
                "datetime" -> {
                    val dt = LocalDateTime.parse(value)
                    val datePart = dt.toLocalDate()
                        .format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale))
                    val timePart = if (is24) dt.toLocalTime().format(DateTimeFormatter.ofPattern("HH:mm", locale))
                    else dt.toLocalTime().format(DateTimeFormatter.ofPattern("h:mm a", locale))
                    "$datePart $timePart"
                }
                else -> LocalDate.parse(value)
                    .format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale))
            }
        }.getOrDefault(value)
    }

    // ── Internationalization ─────────────────────────────────────────────────

    private fun resolveZone(identifier: String): ZoneId =
        if (identifier.isEmpty()) ZoneId.systemDefault()
        else runCatching { ZoneId.of(identifier) }.getOrDefault(ZoneId.systemDefault())

    private fun resolveLocale(tag: String): Locale =
        if (tag.isEmpty()) Locale.getDefault() else Locale.forLanguageTag(tag)

    /**
     * `auto` follows the LOCALE's clock convention rather than the device's
     * 24-hour system setting, so the same `locale` prop produces the same
     * result on both platforms — iOS derives it from the locale too.
     *
     * `getBestDateTimePattern(locale, "jm")` is the documented way to ask
     * for the locale's *preferred* hour field: 'j' resolves to H or h, so
     * the returned pattern tells us the convention without string-matching
     * a formatted sample.
     */
    private fun resolve24Hour(hourFormat: String, locale: Locale): Boolean = when (hourFormat) {
        "24" -> true
        "12" -> false
        else -> {
            val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "jm")
            pattern.contains('H') || pattern.contains('k')
        }
    }
}
