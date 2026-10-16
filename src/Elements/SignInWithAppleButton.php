<?php

namespace Native\Mobile\UI\Elements;

use InvalidArgumentException;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Apple's own Sign in with Apple button.
 *
 * Draws the system button on iOS (`ASAuthorizationAppleIDButton`), so the
 * logo, title, font and proportions are always the ones App Review expects.
 * A tap only fires `@press`. The element never talks to Apple itself: the
 * press handler starts the sign-in, usually through a social auth plugin.
 *
 * Apple has no button on Android, so nothing is drawn there unless the tag
 * has children, which then render as an Android-only fallback.
 *
 *   - `label`: sign-in (default) | continue | sign-up
 *   - `button-style`: auto (default; black in light mode, white in dark) | black | white | white-outline
 *   - `corner-radius`: points, or a `rounded-*` class. The system default when unset.
 *   - `height`: points, or an `h-*` class. 44 when unset.
 *   - `disabled`
 *   - `@press`: tap callback
 */
class SignInWithAppleButton extends Element
{
    /** Title. `sign-in` is the default. */
    public const LABELS = ['sign-in', 'continue', 'sign-up'];

    /** Colours. `auto` (the default) is black in light mode and white in dark mode. */
    public const BUTTON_STYLES = ['auto', 'black', 'white', 'white-outline'];

    protected string $type = 'sign_in_with_apple_button';

    /** @var array<string, mixed> */
    protected array $buttonProps = [];

    protected ?string $pressCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['label'])) {
            $this->label((string) $attrs['label']);
        }
        $buttonStyle = $attrs['button-style'] ?? $attrs['buttonStyle'] ?? null;
        if ($buttonStyle !== null) {
            $this->buttonStyle((string) $buttonStyle);
        }

        // `rounded-*` classes arrive as `borderRadius`; the attribute wins.
        $cornerRadius = $attrs['corner-radius'] ?? $attrs['cornerRadius'] ?? $attrs['borderRadius'] ?? null;
        if ($cornerRadius !== null) {
            $this->cornerRadius((float) $cornerRadius);
        }
        if (! empty($attrs['disabled'])) {
            $this->disabled();
        }

        $this->applyA11yAttributes($attrs);
    }

    /** sign-in | continue | sign-up, matching SwiftUI's `SignInWithAppleButton.Label`. */
    public function label(string $label): static
    {
        $this->buttonProps['label'] = $this->oneOf($label, self::LABELS, 'label');

        return $this;
    }

    /** auto | black | white | white-outline, matching SwiftUI's `SignInWithAppleButton.Style`. */
    public function buttonStyle(string $style): static
    {
        $this->buttonProps['button_style'] = $this->oneOf($style, self::BUTTON_STYLES, 'button-style');

        return $this;
    }

    /** Corner radius in points. A radius of half the height or more draws a capsule. */
    public function cornerRadius(float $radius): static
    {
        $this->buttonProps['corner_radius'] = max(0.0, $radius);

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->buttonProps['disabled'] = $value;

        return $this;
    }

    /**
     * Rides the props as `on_press` rather than the node's press field, so
     * core doesn't wrap the button in a second tap gesture.
     */
    public function onPress(string $method): static
    {
        $this->pressCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->buttonProps;

        if ($this->pressCallback !== null) {
            $props['on_press'] = $registry->register($this->pressCallback);
        }

        return $props;
    }

    /**
     * Apple's guidelines fix the button's colours and shape, so per-instance
     * styling (bg, border, shadow) is dropped, as it is for `<button>`.
     */
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

    /**
     * Accepts the documented kebab-case value, or its snake_case or camelCase
     * spelling, and sends snake_case on the wire.
     *
     * @param  list<string>  $allowed
     */
    private function oneOf(string $value, array $allowed, string $prop): string
    {
        $kebab = strtolower((string) preg_replace(['/(?<=[a-z])(?=[A-Z])/', '/_/'], '-', trim($value)));

        if (! in_array($kebab, $allowed, true)) {
            throw new InvalidArgumentException(
                "SignInWithAppleButton `{$prop}` must be one of [".implode(', ', $allowed)."], got [{$value}]."
            );
        }

        return str_replace('-', '_', $kebab);
    }
}
