<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Modal — full-screen overlay presentation.
 *
 * Visibility is driven by the `visible` prop. PHP keeps that state and
 * toggles it via a callback, typically bound through `native:model` or a
 * dedicated `@dismiss` action. `dismissible` controls whether tapping the
 * backdrop or the close button fires `@dismiss`.
 *
 * It slides up from the bottom, or with `transition="fade"` fades in over
 * the screen and out again. A faded modal keeps drawing what it last
 * showed while it goes, so a screen can empty it as it closes it.
 *
 * Morph — an image that grows into the modal, the photo viewer's opening.
 * Name an image on the screen with `morph-from` and an image inside the
 * modal with `morph-to`, both by their `ref`. As the modal fades in, the
 * picture flies from where the first is drawn to where the second is,
 * and as it fades out the picture flies back. Paging the modal to another
 * image only needs both names moved to the new pair. When the image on
 * the screen is off screen, or either one hasn't loaded, the modal just
 * fades:
 *
 *     <native:image ref="thumb-{{ $photo->id }}" :src="$photo->url" fit="cover" />
 *
 *     <native:modal :visible="$viewing" :morph-from="'thumb-'.$photo->id" morph-to="viewed-photo">
 *         <native:image ref="viewed-photo" :src="$photo->url" fit="contain" class="w-full h-full" />
 *     </native:modal>
 *
 * Model 3: backdrop + surface colors come from theme tokens.
 */
class Modal extends Element
{
    protected string $type = 'modal';

    /** @var array<string, mixed> */
    protected array $modalProps = [];

    protected ?string $dismissCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['visible'])) {
            $this->visible((bool) $attrs['visible']);
        }
        if (isset($attrs['dismissible']) || isset($attrs['dismissable'])) {
            $this->dismissible((bool) ($attrs['dismissible'] ?? $attrs['dismissable']));
        }
        if (isset($attrs['transition'])) {
            $this->transition((string) $attrs['transition']);
        }
        if (isset($attrs['morph-from'])) {
            $this->morphFrom((string) $attrs['morph-from']);
        }
        if (isset($attrs['morph-to'])) {
            $this->morphTo((string) $attrs['morph-to']);
        }
        $this->applyA11yAttributes($attrs);
    }

    public function visible(bool $value = true): static
    {
        $this->modalProps['visible'] = $value;

        return $this;
    }

    public function dismissible(bool $value = true): static
    {
        $this->modalProps['dismissible'] = $value;

        return $this;
    }

    /**
     * How the modal comes and goes: `slide` up from the bottom (the
     * default), or `fade` in over the screen.
     */
    public function transition(string $transition): static
    {
        if ($transition === 'fade') {
            $this->modalProps['transition'] = 'fade';
        } else {
            unset($this->modalProps['transition']);
        }

        return $this;
    }

    /**
     * The `ref` of an image on the screen that grows into the modal as it
     * opens, and that it shrinks back into as it closes (see the class
     * docblock). A morph fades the modal whatever its transition.
     */
    public function morphFrom(string $ref): static
    {
        return $this->morphRef('morph_from', $ref);
    }

    /**
     * The `ref` of the image inside the modal that the image named by
     * morphFrom() grows into.
     */
    public function morphTo(string $ref): static
    {
        return $this->morphRef('morph_to', $ref);
    }

    private function morphRef(string $prop, string $ref): static
    {
        if ($ref === '') {
            unset($this->modalProps[$prop]);
        } else {
            $this->modalProps[$prop] = $ref;
        }

        return $this;
    }

    public function onDismiss(string $method): static
    {
        $this->dismissCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->modalProps;

        if ($this->dismissCallback !== null) {
            $props['on_dismiss'] = $registry->register($this->dismissCallback);
        }

        return $props;
    }
}
