<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Windowed list. Native renders a LazyColumn/List with `count` logical
 * slots; PHP only emits the rows inside `[window_from..window_to]`. Slots
 * outside the window get a fixed-height placeholder on the native side.
 *
 * Native fires `on_window_change(from, to)` as the visible range moves;
 * the component handler updates window state and the next render emits
 * the new slice.
 *
 * Dev API and trait wiring: see HasVirtualListWindow in
 * `mobile-air/src/Edge/Traits/HasVirtualListWindow.php`.
 */
class NativeVirtualList extends Element
{
    protected string $type = 'virtual_list';

    protected array $listProps = [];

    protected ?string $windowCallback = null;

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['count'])) {
            $this->listProps['count'] = (int) $attrs['count'];
        }
        if (isset($attrs['window_from']) || isset($attrs['windowFrom']) || isset($attrs['from'])) {
            $this->listProps['window_from'] = (int) ($attrs['window_from'] ?? $attrs['windowFrom'] ?? $attrs['from']);
        }
        if (isset($attrs['window_to']) || isset($attrs['windowTo']) || isset($attrs['to'])) {
            $this->listProps['window_to'] = (int) ($attrs['window_to'] ?? $attrs['windowTo'] ?? $attrs['to']);
        }
        if (isset($attrs['estimated_row_height']) || isset($attrs['estimatedRowHeight']) || isset($attrs['estimated-row-height'])) {
            $this->listProps['estimated_row_height'] = (float) ($attrs['estimated_row_height'] ?? $attrs['estimatedRowHeight'] ?? $attrs['estimated-row-height']);
        }
        if (isset($attrs['overscan'])) {
            $this->listProps['overscan'] = (int) $attrs['overscan'];
        }
        if (isset($attrs['showsIndicators']) || isset($attrs['shows-indicators'])) {
            $this->showsIndicators((bool) ($attrs['showsIndicators'] ?? $attrs['shows-indicators']));
        }
        $autoScrollTo = $attrs['auto-scroll-to'] ?? $attrs['autoScrollTo'] ?? $attrs['auto_scroll_to'] ?? null;
        if ($autoScrollTo !== null && $autoScrollTo !== '') {
            $this->autoScrollTo((int) $autoScrollTo);
        }
        if (! empty($attrs['transparent'])) {
            $this->transparent();
        }
        $cb = $attrs['on_window_change'] ?? $attrs['onWindowChange'] ?? $attrs['on-window-change'] ?? null;
        if ($cb !== null) {
            $this->windowCallback = $cb;
        }

        $this->applyA11yAttributes($attrs);
    }

    /**
     * Same contract as list/scroll-view, default true. iOS-only in effect:
     * Compose's LazyColumn draws no indicators to begin with.
     */
    public function showsIndicators(bool $value = true): static
    {
        $this->listProps['shows_indicators'] = $value;

        return $this;
    }

    /**
     * Open the list with absolute row $index at the top. The list scrolls
     * when it is created and again when the index changes, never while it
     * stays the same, so re-renders don't fight the reader's scrolling.
     * Negative indices disable auto-scroll; an index beyond count waits
     * until that slot exists rather than scrolling to the last one.
     *
     * The window has to hold the row or native draws a placeholder there
     * until it asks for one that does: HasVirtualListWindow's
     * scrollVirtualListTo() moves the window and sets the index together.
     */
    public function autoScrollTo(int $index): static
    {
        $this->listProps['auto_scroll_to'] = $index;

        return $this;
    }

    /**
     * Let the screen behind the list show through, as on `native:list`:
     * SwiftUI's `List` paints the system background, and `bg-transparent`
     * packs to the same value as "no colour". iOS-only in effect:
     * Compose's LazyColumn draws no background of its own.
     */
    public function transparent(bool $value = true): static
    {
        $this->listProps['transparent'] = $value;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->listProps;

        if ($this->windowCallback !== null) {
            // 'virtual_window' kind tells NativeComponent::dispatch to decode
            // the event's `text` payload as "from,to" → two int args.
            $props['on_window_change'] = $registry->register($this->windowCallback, 'virtual_window');
        }

        return $props;
    }
}
