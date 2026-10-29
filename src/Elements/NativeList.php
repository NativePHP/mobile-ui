<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\UI\Concerns\ResolvesColorValues;

class NativeList extends Element
{
    use ResolvesColorValues;

    protected string $type = 'list';

    protected array $listProps = [];

    protected ?string $refreshCallback = null;

    protected ?string $endReachedCallback = null;

    protected ?string $visibleRangeCallback = null;

    protected ?string $scrollEndCallback = null;

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (! empty($attrs['horizontal'])) {
            $this->horizontal();
        }
        if (isset($attrs['showsIndicators']) || isset($attrs['shows-indicators'])) {
            $this->showsIndicators((bool) ($attrs['showsIndicators'] ?? $attrs['shows-indicators']));
        }
        if (! empty($attrs['separator'])) {
            $this->separator();
        }
        if (! empty($attrs['plain'])) {
            $this->plain();
        }
        if (! empty($attrs['transparent'])) {
            $this->transparent();
        }
        $rowColor = $attrs['row-color'] ?? $attrs['rowColor'] ?? null;
        if (is_string($rowColor) && $rowColor !== '') {
            $this->rowColor($rowColor);
        }
        if (isset($attrs['on-refresh']) || isset($attrs['onRefresh'])) {
            $this->onRefresh($attrs['on-refresh'] ?? $attrs['onRefresh']);
        }
        if (isset($attrs['on-end-reached']) || isset($attrs['onEndReached'])) {
            $this->onEndReached($attrs['on-end-reached'] ?? $attrs['onEndReached']);
        }
        if (isset($attrs['end-reached-buffer']) || isset($attrs['endReachedBuffer'])) {
            $this->endReachedBuffer((int) ($attrs['end-reached-buffer'] ?? $attrs['endReachedBuffer']));
        }
        if (isset($attrs['on-visible-range']) || isset($attrs['onVisibleRange'])) {
            $this->onVisibleRange($attrs['on-visible-range'] ?? $attrs['onVisibleRange']);
        }
        if (isset($attrs['visible-range-step']) || isset($attrs['visibleRangeStep'])) {
            $this->visibleRangeStep((int) ($attrs['visible-range-step'] ?? $attrs['visibleRangeStep']));
        }
        $autoScrollTo = $attrs['auto-scroll-to'] ?? $attrs['autoScrollTo'] ?? null;
        if ($autoScrollTo !== null && $autoScrollTo !== '') {
            $this->autoScrollTo((int) $autoScrollTo);
        }
        if (isset($attrs['on-scroll-end']) || isset($attrs['onScrollEnd'])) {
            $this->onScrollEnd($attrs['on-scroll-end'] ?? $attrs['onScrollEnd']);
        }

        $this->applyA11yAttributes($attrs);
    }

    public function horizontal(bool $value = true): static
    {
        $this->listProps['horizontal'] = $value;

        return $this;
    }

    public function showsIndicators(bool $value = true): static
    {
        $this->listProps['shows_indicators'] = $value;

        return $this;
    }

    public function separator(bool $value = true): static
    {
        $this->listProps['separator'] = $value;

        return $this;
    }

    /**
     * Force a plain (ungrouped) list style. By default a list containing
     * {@see ListSection} children adopts the inset-grouped look (rounded
     * cards on iOS `.insetGrouped` / hand-rolled cards on Android); call
     * this to keep flat rows with plain sticky section headers instead.
     */
    public function plain(bool $value = true): static
    {
        $this->listProps['plain'] = $value;

        return $this;
    }

    /**
     * Let the screen behind the list show through. SwiftUI's `List` paints
     * the system grouped background over whatever the screen draws; a
     * `bg-*` colour or gradient on the list already replaces it, but a
     * list that should sit directly on the screen's own background (a
     * gradient, an image, a background layer) has no colour to declare —
     * `bg-transparent` packs to the same value as "no colour". Android's
     * `LazyColumn` draws no background of its own, so this is iOS-only.
     */
    public function transparent(bool $value = true): static
    {
        $this->listProps['transparent'] = $value;

        return $this;
    }

    /**
     * Fill every row with one colour: the white cards of an inset-grouped
     * settings list (iOS Settings) or opaque rows on a plain one. Rows are
     * otherwise clear, so the screen background shows through them. Takes
     * a hex value or a theme token (`theme('surface')`).
     */
    public function rowColor(string $color): static
    {
        $this->listProps['row_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function onRefresh(string $method): static
    {
        $this->refreshCallback = $method;

        return $this;
    }

    public function onEndReached(string $method): static
    {
        $this->endReachedCallback = $method;

        return $this;
    }

    public function endReachedBuffer(int $items): static
    {
        $this->listProps['end_reached_buffer'] = max(1, $items);

        return $this;
    }

    /**
     * Calls $method(int $first, int $last) with the positions of the first and
     * last rows on screen, counting rows as end-reached does (a section's rows
     * in its place), each time either end has moved by the step since the last
     * call. The list doesn't call it before it has moved a step from the top.
     * Rows are measured while it's set, so a {@see ListPlaceholder} put in a
     * row's place takes the row's height.
     */
    public function onVisibleRange(string $method): static
    {
        $this->visibleRangeCallback = $method;

        return $this;
    }

    /**
     * How many rows either end of the visible range moves before
     * {@see onVisibleRange()} is called again. Defaults to 10.
     */
    public function visibleRangeStep(int $rows): static
    {
        $this->listProps['visible_range_step'] = max(1, $rows);

        return $this;
    }

    /**
     * Open the list with row $index at the top: a screen restored after a
     * relaunch, a deep link to a record, or the row just added. Rows count
     * as end-reached and visible-range count them (a section's rows in its
     * place).
     *
     * Like ScrollView::autoScrollTo(), the list scrolls when it is created
     * and again when the index changes, never while it stays the same, so
     * re-renders don't pull the list away from where the reader scrolled.
     * Going back to a screen keeps its list where it was without this.
     */
    public function autoScrollTo(int $index): static
    {
        $this->listProps['auto_scroll_to'] = max(0, $index);

        return $this;
    }

    /**
     * Calls $method(int $first, int $last) when a scroll comes to rest, with
     * the positions of the first and last rows on screen then, counted as
     * {@see onVisibleRange()} counts them. A drag, a fling and a scroll to the
     * top all end in one call once the list has stopped moving. A tap that
     * doesn't move the list isn't a scroll.
     *
     * A list reporting its visible range as well sends the range at rest here
     * instead, and counts it as a visible range report. So a screen can let
     * the reports while scrolling do only what can't wait, and do the rest
     * here, when a frame can't make the scrolling stutter.
     */
    public function onScrollEnd(string $method): static
    {
        $this->scrollEndCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->listProps;

        if ($this->refreshCallback !== null) {
            $props['on_refresh'] = $registry->register($this->refreshCallback);
        }

        if ($this->endReachedCallback !== null) {
            $props['on_end_reached'] = $registry->register($this->endReachedCallback);
        }

        if ($this->visibleRangeCallback !== null) {
            // The virtual list's "from,to" payload, which dispatch hands the method as two ints.
            $props['on_visible_range'] = $registry->register($this->visibleRangeCallback, 'virtual_window');
        }

        if ($this->scrollEndCallback !== null) {
            // "first,last" too, decoded the same way.
            $props['on_scroll_end'] = $registry->register($this->scrollEndCallback, 'virtual_window');
        }

        return $props;
    }
}
