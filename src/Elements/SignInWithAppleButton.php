<?php

namespace Native\Mobile\UI\Elements;

use InvalidArgumentException;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Apple's own Sign in with Apple button: SwiftUI's `SignInWithAppleButton`
 * on iOS, so the logo, title, font and proportions are always the ones App
 * Review expects.
 *
 * Tapping it runs the Apple ID request, as the system button always does.
 * The answer arrives as a native event, `SignInWithAppleCompleted` or
 * `SignInWithAppleFailed`, which a component listens for with `#[On(...)]`.
 * `@press` is called as the request starts.
 *
 * Apple has no button on Android, so nothing is drawn there unless the tag
 * has children, which then render as an Android-only fallback.
 *
 *   - `label`: sign-in (default) | continue | sign-up
 *   - `button-style`: auto (default; black in light mode, white in dark) | black | white | white-outline
 *   - `scopes`: any of email, full-name. None by default.
 *   - `nonce`: a raw nonce. Apple gets its SHA-256 hex; the completed event echoes the raw value.
 *   - `state`: echoed on both events.
 *   - `corner-radius`: points, or a `rounded-*` class. Rounder than the system's corners, up to a capsule.
 *   - `height`: points, or an `h-*` class. 44 when unset.
 *   - `disabled`
 *   - `@press`: called as the request starts
 */
class SignInWithAppleButton extends Element
{
    /** Title. `sign-in` is the default. */
    public const LABELS = ['sign-in', 'continue', 'sign-up'];

    /** Colours. `auto` (the default) is black in light mode and white in dark mode. */
    public const BUTTON_STYLES = ['auto', 'black', 'white', 'white-outline'];

    /** What to ask Apple for besides the user id. Apple only sends them on the first sign-in. */
    public const SCOPES = ['email', 'full-name'];

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
        if (isset($attrs['scopes'])) {
            $this->scopes(is_array($attrs['scopes']) ? $attrs['scopes'] : explode(',', (string) $attrs['scopes']));
        }
        if (isset($attrs['nonce'])) {
            $this->nonce((string) $attrs['nonce']);
        }
        if (isset($attrs['state'])) {
            $this->state((string) $attrs['state']);
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

    /**
     * Ask for the user's email and/or name: any of email, full-name.
     *
     * @param  list<string>  $scopes
     */
    public function scopes(array $scopes): static
    {
        $this->buttonProps['scopes'] = array_values(array_unique(array_map(
            fn (string $scope): string => $this->oneOf($scope, self::SCOPES, 'scopes'),
            array_filter(array_map('trim', $scopes), fn (string $scope): bool => $scope !== ''),
        )));

        return $this;
    }

    /**
     * The raw nonce for this attempt. Apple gets its SHA-256 hex, so the
     * identity token carries the hash, and the completed event echoes the raw
     * value for your server to check against the token.
     */
    public function nonce(string $nonce): static
    {
        $this->buttonProps['nonce'] = $nonce;

        return $this;
    }

    /** An opaque value echoed back on both events. */
    public function state(string $state): static
    {
        $this->buttonProps['state'] = $state;

        return $this;
    }

    /**
     * Corner radius in points. SwiftUI's button can only be clipped, so this
     * rounds the corners more than the system does, up to a capsule at half
     * the height or more. It can't make them squarer.
     */
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
     * Called as the Apple ID request starts. Rides the props as `on_press`
     * rather than the node's press field, so core doesn't wrap the button in
     * a second tap gesture.
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
