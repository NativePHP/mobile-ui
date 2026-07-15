<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

class NativeList extends Element
{

    protected string $type = 'list';

    protected array $listProps = [];

    protected ?string $refreshCallback = null;

    protected ?string $endReachedCallback = null;

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
        if (isset($attrs['on-refresh']) || isset($attrs['onRefresh'])) {
            $this->onRefresh($attrs['on-refresh'] ?? $attrs['onRefresh']);
        }
        if (isset($attrs['on-end-reached']) || isset($attrs['onEndReached'])) {
            $this->onEndReached($attrs['on-end-reached'] ?? $attrs['onEndReached']);
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

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->listProps;

        if ($this->refreshCallback !== null) {
            $props['on_refresh'] = $registry->register($this->refreshCallback);
        }

        if ($this->endReachedCallback !== null) {
            $props['on_end_reached'] = $registry->register($this->endReachedCallback);
        }

        return $props;
    }
}
