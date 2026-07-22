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
        $cb = $attrs['on_window_change'] ?? $attrs['onWindowChange'] ?? $attrs['on-window-change'] ?? null;
        if ($cb !== null) {
            $this->windowCallback = $cb;
        }

        $this->applyA11yAttributes($attrs);
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
