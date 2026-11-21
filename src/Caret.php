<?php

namespace Native\Mobile\UI;

use Illuminate\Contracts\Routing\UrlRoutable;

/**
 * Where a multiline text input draws its caret, as `@caretChange` reports it.
 *
 * All values are in the field's own points (dp on Android), measured from the
 * top-left corner of the part of the field you can see, with its own scrolling
 * taken off. So `y` is 0 when the caret's line is the field's top visible line,
 * and it goes negative, or past `fieldHeight`, when the field has scrolled the
 * caret out of view. Add the field's position in its parent to place something
 * next to the caret, such as a mention list in an `absolute` column.
 *
 * `line` is the visual line the caret is on, wrapped lines included, counting
 * from 0 at the top of the text (not of what's visible).
 *
 * Type a handler's parameter as `Caret` and the event's payload is decoded
 * into one:
 *
 *     public function caretMoved(Caret $caret): void
 *
 * It rides on the binding the component invoker gives any `UrlRoutable`
 * parameter (as an Eloquent model or backed enum is bound), which is why it
 * implements that interface. A handler typed `string` gets the raw payload.
 */
final class Caret implements UrlRoutable
{
    public function __construct(
        public readonly float $x = 0,
        public readonly float $y = 0,
        public readonly float $width = 0,
        public readonly float $height = 0,
        public readonly int $line = 0,
        public readonly float $fieldWidth = 0,
        public readonly float $fieldHeight = 0,
    ) {}

    /**
     * Decode the wire payload: `x,y,width,height,line,fieldWidth,fieldHeight`,
     * numbers with a `.` decimal point. Missing or malformed parts read as 0.
     */
    public static function fromPayload(string $payload): self
    {
        $parts = array_map('trim', explode(',', $payload));
        $number = static fn (int $i): float => is_numeric($parts[$i] ?? null) ? (float) $parts[$i] : 0.0;

        return new self(
            x: $number(0),
            y: $number(1),
            width: $number(2),
            height: $number(3),
            line: (int) $number(4),
            fieldWidth: $number(5),
            fieldHeight: $number(6),
        );
    }

    /** The wire payload for this caret, as the renderers send it. */
    public function toPayload(): string
    {
        $format = static fn (float $value): string => rtrim(rtrim(number_format($value, 2, '.', ''), '0'), '.');

        return implode(',', [
            $format($this->x),
            $format($this->y),
            $format($this->width),
            $format($this->height),
            (string) $this->line,
            $format($this->fieldWidth),
            $format($this->fieldHeight),
        ]);
    }

    /** The bottom of the caret's line, in the same coordinates as `y`. */
    public function bottom(): float
    {
        return $this->y + $this->height;
    }

    /** Whether any of the caret is inside the field's visible area. */
    public function visible(): bool
    {
        return $this->bottom() > 0 && ($this->fieldHeight <= 0 || $this->y < $this->fieldHeight);
    }

    // ── UrlRoutable: how a `Caret $caret` handler parameter gets decoded ────

    public function getRouteKey(): string
    {
        return $this->toPayload();
    }

    public function getRouteKeyName(): string
    {
        return 'caret';
    }

    /**
     * @param  mixed  $value
     * @param  string|null  $field
     */
    public function resolveRouteBinding($value, $field = null): self
    {
        return self::fromPayload((string) $value);
    }

    /**
     * @param  string  $childType
     * @param  mixed  $value
     * @param  string|null  $field
     */
    public function resolveChildRouteBinding($childType, $value, $field): ?self
    {
        return null;
    }
}
