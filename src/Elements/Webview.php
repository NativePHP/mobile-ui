<?php

namespace Nativephp\NativeUi\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

class Webview extends Element
{
    protected string $type = 'webview';

    protected array $webviewProps = [];

    protected ?string $navigatedMethod = null;

    public static function make(string $src = ''): static
    {
        $el = new static;
        if ($src !== '') {
            $el->webviewProps['src'] = $src;
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['src'])) {
            $this->webviewProps['src'] = (string) $attrs['src'];
        }

        if (isset($attrs['html'])) {
            $this->webviewProps['html'] = (string) $attrs['html'];
        }

        // Opt-in toggles. Default posture is locked down — JS off, no DOM
        // storage, no file access, no new windows. Hosts that need richer
        // behavior have to ask for it explicitly.
        if (isset($attrs['javascript']) || isset($attrs['js'])) {
            $this->webviewProps['javascript'] = filter_var(
                $attrs['javascript'] ?? $attrs['js'],
                FILTER_VALIDATE_BOOLEAN
            );
        }

        if (isset($attrs['dom-storage']) || isset($attrs['domStorage'])) {
            $this->webviewProps['dom_storage'] = filter_var(
                $attrs['dom-storage'] ?? $attrs['domStorage'],
                FILTER_VALIDATE_BOOLEAN
            );
        }

        $this->applyA11yAttributes($attrs);
    }

    /**
     * `@navigated="onUrlChange"` — fires once per top-frame URL load
     * (committed navigation), with the resolved URL as the first arg.
     */
    public function onNavigated(string $method): static
    {
        $this->navigatedMethod = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->webviewProps;

        if ($this->navigatedMethod !== null) {
            $props['on_navigated'] = $registry->register($this->navigatedMethod);
        }

        return $props;
    }
}
