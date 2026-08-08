<?php

namespace Native\Mobile\UI\Elements;

use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;
use Exception;
use InvalidArgumentException;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * DatePicker — native date, time, or date+time selection.
 *
 * iOS: SwiftUI `DatePicker` with `displayedComponents` driven by `mode`.
 * Android: Material3 `DatePicker` / `TimePicker` behind a trigger field.
 *
 * ── The wire contract ────────────────────────────────────────────────────
 *
 * Values cross the bridge as **wall-clock ISO 8601 strings with no offset**,
 * shaped by `mode`:
 *
 *   date      →  `2026-07-25`
 *   time      →  `14:30`              (always 24-hour on the wire)
 *   datetime  →  `2026-07-25T14:30`
 *
 * That format is locale- and timezone-independent by construction. No UTC
 * conversion ever crosses the bridge, which is what keeps the classic
 * off-by-one-day bug out of this element: Android's `DatePickerState`
 * reports UTC-midnight epoch millis and SwiftUI's `DatePicker` binds an
 * instant, so each renderer converts to wall-clock on its own side against
 * a single agreed calendar — see `timezone()`.
 *
 * `Y-m-d` strings sort lexicographically, are what `date` columns already
 * hold, and feed straight into `Carbon::parse()`.
 *
 * ── Internationalization ─────────────────────────────────────────────────
 *
 * `locale()` drives DISPLAY only — month and weekday names, weekday order,
 * and the 12/24-hour default. It never changes the wire value. `timezone()`
 * names the calendar the picker operates in. `hourFormat()` overrides the
 * locale's clock convention when you need to force one.
 *
 * Model 3: colors come from theme tokens; no per-instance overrides.
 */
class DatePicker extends Element
{
    protected string $type = 'date_picker';

    /** Selection granularity. `date` is the default. */
    public const MODES = ['date', 'time', 'datetime'];

    /**
     * Presentation. Each maps to the nearest native idiom:
     *
     *   compact  →  iOS `.compact` (tap-to-popover) · Android trigger + modal dialog
     *   inline   →  iOS `.graphical` (embedded calendar) · Android embedded picker
     *   wheel    →  iOS `.wheel` (drum) · Android has no drum; falls back to inline
     */
    public const PICKER_STYLES = ['compact', 'inline', 'wheel'];

    /** Clock convention. `auto` defers to the resolved locale. */
    public const HOUR_FORMATS = ['auto', '12', '24'];

    /** ISO 8601 wall-clock format per mode — the wire contract, in one place. */
    private const WIRE_FORMATS = [
        'date' => 'Y-m-d',
        'time' => 'H:i',
        'datetime' => 'Y-m-d\TH:i',
    ];

    /** @var array<string, mixed> */
    protected array $pickerProps = [];

    protected ?string $changeCallback = null;

    /**
     * Raw value/bound inputs, normalized lazily in `resolveProps()` — `mode`
     * may be set after `value()` in a fluent chain, and the mode decides the
     * wire shape.
     */
    protected string|DateTimeInterface|null $rawValue = null;

    protected string|DateTimeInterface|null $rawMin = null;

    protected string|DateTimeInterface|null $rawMax = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['mode'])) {
            $this->mode((string) $attrs['mode']);
        }
        if (isset($attrs['value'])) {
            $this->value($attrs['value']);
        }
        if (isset($attrs['min'])) {
            $this->min($attrs['min']);
        }
        if (isset($attrs['max'])) {
            $this->max($attrs['max']);
        }
        if (isset($attrs['label'])) {
            $this->label((string) $attrs['label']);
        }
        if (isset($attrs['placeholder'])) {
            $this->placeholder((string) $attrs['placeholder']);
        }
        $pickerStyle = $attrs['picker-style'] ?? $attrs['pickerStyle'] ?? null;
        if ($pickerStyle !== null) {
            $this->pickerStyle((string) $pickerStyle);
        }
        if (isset($attrs['timezone'])) {
            $this->timezone((string) $attrs['timezone']);
        }
        if (isset($attrs['locale'])) {
            $this->locale((string) $attrs['locale']);
        }

        $hourFormat = $attrs['hour-format'] ?? $attrs['hourFormat'] ?? null;
        if ($hourFormat !== null) {
            $this->hourFormat((string) $hourFormat);
        }

        if (isset($attrs['title'])) {
            $this->title((string) $attrs['title']);
        }

        $confirmLabel = $attrs['confirm-label'] ?? $attrs['confirmLabel'] ?? null;
        if ($confirmLabel !== null) {
            $this->confirmLabel((string) $confirmLabel);
        }

        $cancelLabel = $attrs['cancel-label'] ?? $attrs['cancelLabel'] ?? null;
        if ($cancelLabel !== null) {
            $this->cancelLabel((string) $cancelLabel);
        }

        if (! empty($attrs['disabled'])) {
            $this->disabled();
        }

        // `native:model` expands to `sync-mode="live"`; the modifier forms
        // (`.blur`, `.debounce.300ms`) expand to modes this element can't
        // honor. Validated rather than ignored — see `syncMode()`.
        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode((string) ($attrs['sync-mode'] ?? $attrs['syncMode']));
        }

        if (isset($attrs['supporting'])) {
            $this->supporting($attrs['supporting']);
        }
        if (! empty($attrs['error']) || ! empty($attrs['isError']) || ! empty($attrs['is-error'])) {
            $this->error();
        }

        $this->applyA11yAttributes($attrs);
    }

    /**
     * Accepted only as `live`. A picker commits discretely — there is no
     * mid-gesture stream of values to defer or coalesce — so
     * `native:model.blur` / `.debounce.Xms` have nothing to act on.
     *
     * Silently swallowing them would leave a developer believing they'd
     * throttled something, so an unsupported mode is a hard error. Nothing
     * is serialized: the renderers always commit on selection.
     */
    public function syncMode(string $mode): static
    {
        if ($mode !== 'live') {
            // Name the SYNC MODE, not a directive spelling. The precompiler
            // collapses `.lazy` into `blur` before we see it, so quoting
            // "native:model.{$mode}" would tell a developer who wrote `.lazy`
            // about a directive they never typed.
            $directives = $mode === 'blur'
                ? '`native:model.blur` / `native:model.lazy`'
                : '`native:model.debounce.Xms`';

            throw new InvalidArgumentException(
                "DatePicker commits on selection, so the `{$mode}` sync mode ({$directives}) has no effect. "
                .'Use plain `native:model` (or `native:model.live`) and defer in your component if you need to.'
            );
        }

        return $this;
    }

    // ── Selection ────────────────────────────────────────────────────────────

    /**
     * The selected value. Accepts an ISO 8601 string or any
     * `DateTimeInterface` (Carbon included) and normalizes to the wire shape
     * for the current `mode`.
     *
     * A fuller string than the mode needs is truncated, so a `datetime`
     * column can drive a `date` picker without the caller reformatting:
     * `'2026-07-25T14:30:00Z'` with `mode: date` serializes as `2026-07-25`.
     *
     * An empty string clears the selection (the placeholder shows).
     */
    public function value(string|DateTimeInterface|null $value): static
    {
        $this->rawValue = $value;

        return $this;
    }

    /** Earliest selectable value. Same input handling as `value()`. */
    public function min(string|DateTimeInterface|null $value): static
    {
        $this->rawMin = $value;

        return $this;
    }

    /** Latest selectable value. Same input handling as `value()`. */
    public function max(string|DateTimeInterface|null $value): static
    {
        $this->rawMax = $value;

        return $this;
    }

    /**
     * Selection granularity: `date` (default), `time`, or `datetime`.
     * Also decides the wire shape of `value` / `min` / `max`.
     */
    public function mode(string $mode): static
    {
        $this->pickerProps['mode'] = $this->oneOf($mode, self::MODES, 'mode');

        return $this;
    }

    // ── Presentation ─────────────────────────────────────────────────────────

    public function label(string $text): static
    {
        $this->pickerProps['label'] = $text;

        return $this;
    }

    /** Trigger text when nothing is selected yet. */
    public function placeholder(string $text): static
    {
        $this->pickerProps['placeholder'] = $text;

        return $this;
    }

    /**
     * `compact` (default), `inline`, or `wheel` — see [self::PICKER_STYLES].
     *
     * Named `pickerStyle` rather than `display` because `Element::display()`
     * is already taken by flex/layout display, which is a different axis
     * entirely.
     */
    public function pickerStyle(string $style): static
    {
        $this->pickerProps['picker_style'] = $this->oneOf($style, self::PICKER_STYLES, 'picker-style');

        return $this;
    }

    /**
     * Dialog heading. Android only — iOS's compact popover and inline styles
     * have no title affordance, so this is a no-op there.
     */
    public function title(string $text): static
    {
        $this->pickerProps['title'] = $text;

        return $this;
    }

    /**
     * Confirm button text. Android only (iOS commits on selection), but it
     * is user-visible chrome, so pass a translated string:
     * `->confirmLabel(__('Done'))`.
     */
    public function confirmLabel(string $text): static
    {
        $this->pickerProps['confirm_label'] = $text;

        return $this;
    }

    /** Cancel button text. Android only — see `confirmLabel()`. */
    public function cancelLabel(string $text): static
    {
        $this->pickerProps['cancel_label'] = $text;

        return $this;
    }

    // ── Internationalization ─────────────────────────────────────────────────

    /**
     * IANA timezone the picker's calendar operates in — `Europe/London`,
     * `America/New_York`. Defaults to the device timezone.
     *
     * This does NOT shift the wire value, which is always wall-clock. It
     * decides what "today" means for an empty picker, and on iOS it is the
     * calendar used to convert between the bound instant and the wall-clock
     * string. Set it when your app pins a business timezone rather than
     * following the device.
     */
    public function timezone(string $identifier): static
    {
        $this->assertTimezone($identifier);
        $this->pickerProps['timezone'] = $identifier;

        return $this;
    }

    /**
     * BCP-47 locale for DISPLAY — `en-GB`, `de-DE`, `ja-JP`. Drives month and
     * weekday names, weekday order, and the default clock convention.
     * Defaults to the device locale. Never affects the wire value.
     */
    public function locale(string $tag): static
    {
        $this->pickerProps['locale'] = $tag;

        return $this;
    }

    /** `auto` (locale default), `12`, or `24`. Display only. */
    public function hourFormat(string $format): static
    {
        $this->pickerProps['hour_format'] = $this->oneOf($format, self::HOUR_FORMATS, 'hour-format');

        return $this;
    }

    // ── State ────────────────────────────────────────────────────────────────

    public function disabled(bool $value = true): static
    {
        $this->pickerProps['disabled'] = $value;

        return $this;
    }

    /**
     * Fires when a selection is committed, with the wall-clock ISO string:
     * `method(string $value)`. Never fires mid-scroll — both platforms
     * commit discretely.
     */
    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    // ── Serialization ────────────────────────────────────────────────────────

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->pickerProps;
        $mode = $props['mode'] ?? 'date';

        // Neither platform can enforce a time-of-day range: SwiftUI's `in:`
        // bounds an absolute instant (a bare "09:00" parses against a
        // reference date, so the range never bites), and Material 3's
        // TimePicker exposes no bounds API at all. Rather than accept
        // constraints that quietly do nothing, refuse them.
        if ($mode === 'time' && ($this->rawMin !== null || $this->rawMax !== null)) {
            throw new InvalidArgumentException(
                'DatePicker `min`/`max` cannot be enforced for mode="time" on either platform. '
                .'Drop them and validate the chosen time in your component instead.'
            );
        }

        // Normalized here rather than in the setters: `mode()` may come after
        // `value()` in a fluent chain, and the mode picks the wire shape.
        foreach (['value' => $this->rawValue, 'min' => $this->rawMin, 'max' => $this->rawMax] as $key => $raw) {
            $normalized = $this->normalize($raw, $mode, $key);
            if ($normalized !== null) {
                $props[$key] = $normalized;
            }
        }

        if ($this->changeCallback !== null) {
            $props['on_change'] = $registry->register($this->changeCallback);
        }

        return $props;
    }

    /**
     * Coerce one input to the wire shape for `$mode`, or `null` to leave the
     * prop unserialized. An empty string is meaningful — it clears the
     * selection — so it serializes as `''`.
     */
    private function normalize(string|DateTimeInterface|null $raw, string $mode, string $prop): ?string
    {
        if ($raw === null) {
            return null;
        }

        $format = self::WIRE_FORMATS[$mode];

        if ($raw instanceof DateTimeInterface) {
            return $raw->format($format);
        }

        $trimmed = trim($raw);
        if ($trimmed === '') {
            return '';
        }

        // Parsed against UTC so a bare wall-clock string ("14:30") can't pick
        // up a host-timezone offset on the way through. A string that carries
        // its own offset keeps it, and we take the wall clock as written.
        try {
            $parsed = new DateTimeImmutable($trimmed, new DateTimeZone('UTC'));
        } catch (Exception) {
            throw new InvalidArgumentException(
                "DatePicker `{$prop}` expects an ISO 8601 string or DateTimeInterface, got [{$trimmed}]."
            );
        }

        return $parsed->format($format);
    }

    /** @param  list<string>  $allowed */
    private function oneOf(string $value, array $allowed, string $prop): string
    {
        if (! in_array($value, $allowed, true)) {
            throw new InvalidArgumentException(
                "DatePicker `{$prop}` must be one of [".implode(', ', $allowed)."], got [{$value}]."
            );
        }

        return $value;
    }

    private function assertTimezone(string $identifier): void
    {
        try {
            new DateTimeZone($identifier);
        } catch (Exception) {
            throw new InvalidArgumentException(
                "DatePicker `timezone` must be a valid IANA identifier, got [{$identifier}]."
            );
        }
    }

    // ── Model 3 enforcement ──────────────────────────────────────────────────

    public function getStyle(): array
    {
        return [];
    }

    public function getLayout(): array
    {
        $layout = parent::getLayout();
        unset($layout['padding']);

        return $layout;
    }

    /** Supporting/helper text under the control (error-colored when error()). */
    public function supporting(string $text): static
    {
        $this->pickerProps['supporting'] = $text;

        return $this;
    }

    /** Flag the control as invalid — destructive tint + supporting text color. */
    public function error(bool $on = true): static
    {
        $this->pickerProps['is_error'] = $on;

        return $this;
    }
}
