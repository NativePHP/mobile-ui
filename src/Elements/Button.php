<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\Edge\Layouts\Builders\NavAction;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Icon\IconResolver;
use Native\Mobile\Icon\IosSymbol;
use Native\Mobile\UI\Theme;

/**
 * Native button.
 *
 * Renders as the platform's native button primitive — Material3 `Button`
 * family on Android, SwiftUI `Button` with `buttonStyle(...)` on iOS.
 *
 * API shape (locked in plan doc, sections A/C/E):
 *   - `variant`: semantic vocabulary (primary | secondary | destructive | success | accent | ghost),
 *     or the name of any colour token in the theme
 *   - `size`: sm | md | lg
 *   - `disabled`, `loading`: state
 *   - `icon`, `icon-trailing`: optional icon names (leading/trailing)
 *   - `a11y-label`, `a11y-hint`: accessibility overrides
 *   - `@press`: tap callback
 *
 * Label/content comes from the Blade slot, not a prop — see
 * `Components\Button` for slot capture.
 *
 * Per Model 3 customization (theme-only), there is intentionally NO per-instance
 * color, background, border, radius, shadow, font-size, or font-weight. All
 * visual styling comes from the theme (`Native\Mobile\UI\Theme`). For full
 * visual control, drop to `<pressable>` with your own content.
 */
class Button extends Element
{
    /**
     * The variants each renderer draws from its own theme tokens. Any other
     * variant that names a theme colour is sent with that colour.
     */
    public const array Variants = ['primary', 'secondary', 'destructive', 'success', 'accent', 'ghost'];

    protected string $type = 'button';

    /** @var array<string, mixed> */
    protected array $buttonProps = [];

    protected ?string $pressCallback = null;

    public static function make(string $label = ''): static
    {
        $el = new static;

        if ($label !== '') {
            $el->buttonProps['label'] = $label;
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['label'])) {
            $this->buttonProps['label'] = $attrs['label'];
        }
        if (isset($attrs['variant'])) {
            $this->variant($attrs['variant']);
        }
        if (isset($attrs['size'])) {
            $this->size($attrs['size']);
        }
        if (! empty($attrs['disabled'])) {
            $this->disabled();
        }
        if (! empty($attrs['loading'])) {
            $this->loading();
        }
        // Platform icon overrides, matching the core elements' convention
        // (`:ios-icon` / `:android-icon`, with `<icon>`-style `:ios` /
        // `:android` accepted as aliases). Button is multi-slot so it can't
        // use HasPlatformIcon; without this the shared name was the only
        // value reaching icon(), leaving an SF Symbol to render nothing on
        // Android and a Material ligature nothing on iOS.
        $iosIcon = $attrs['ios-icon'] ?? $attrs['iosIcon'] ?? $attrs['ios'] ?? null;
        $androidIcon = $attrs['android-icon'] ?? $attrs['androidIcon'] ?? $attrs['android'] ?? null;

        if (isset($attrs['icon']) || $iosIcon !== null || $androidIcon !== null) {
            $this->icon($attrs['icon'] ?? null, $iosIcon, $androidIcon);
        }

        $iosTrailing = $attrs['ios-icon-trailing'] ?? $attrs['iosIconTrailing'] ?? null;
        $androidTrailing = $attrs['android-icon-trailing'] ?? $attrs['androidIconTrailing'] ?? null;
        $sharedTrailing = $attrs['icon-trailing'] ?? $attrs['iconTrailing'] ?? null;

        if ($sharedTrailing !== null || $iosTrailing !== null || $androidTrailing !== null) {
            $this->iconTrailing($sharedTrailing, $iosTrailing, $androidTrailing);
        }
        // Custom font by name — the token is a font file (minus extension)
        // bundled from the app's resources/fonts/ by the copy_assets hook.
        if (isset($attrs['font'])) {
            $this->font($attrs['font']);
        }
        // Line height (leading). `line_height` is a multiplier of font size;
        // `line_height_px` an absolute override. Button labels are single-line,
        // so this is accepted for parity but rarely has a visible effect.
        $lineHeight = $attrs['line-height'] ?? $attrs['lineHeight'] ?? null;
        if ($lineHeight !== null) {
            $this->buttonProps['line_height'] = (float) $lineHeight;
        }
        $lineHeightPx = $attrs['line-height-px'] ?? $attrs['lineHeightPx'] ?? null;
        if ($lineHeightPx !== null) {
            $this->buttonProps['line_height_px'] = (float) $lineHeightPx;
        }
        $this->applyA11yAttributes($attrs);

        // Optional tap-to-open dropdown menu — see Pressable.php for the
        // wire shape. When `:menu` is set, tapping shadows `@press` and
        // opens the menu instead.
        if (isset($attrs['menu']) && is_array($attrs['menu']) && ! empty($attrs['menu'])) {
            foreach ($attrs['menu'] as $item) {
                if ($item instanceof NavAction) {
                    $this->addChild($item->toElement());
                } elseif ($item instanceof Element) {
                    $this->addChild($item);
                }
            }
            $this->buttonProps['has_menu'] = true;
        }
    }

    /**
     * primary | secondary | destructive | success | accent | ghost, or the
     * name of a colour token in the theme. Default: primary.
     *
     * A token variant fills the button like primary does, in that token's
     * colour, with the label in its `on-` token (`variant="brand"` draws in
     * `brand` and `on-brand`), or in `on-primary` when the theme has none.
     * Both are sent in their light and dark shades. That lets an app pick a
     * button's colour at runtime, say one per user, while the colours still
     * live in the theme. A name the theme doesn't have draws as primary.
     */
    public function variant(string $value): static
    {
        $this->buttonProps['variant'] = $value;

        foreach (['tint', 'on_tint'] as $prop) {
            unset($this->buttonProps[$prop], $this->buttonProps['dark_'.$prop]);
        }

        if (! in_array($value, self::Variants, true) && is_string(Theme::get("light.{$value}"))) {
            $this->tokenColor('tint', $value);
            $this->tokenColor('on_tint', is_string(Theme::get("light.on-{$value}")) ? "on-{$value}" : 'on-primary');
        }

        return $this;
    }

    /**
     * Sends a theme token's light shade as `$prop`, and its dark shade as
     * `dark_$prop` when that differs.
     */
    protected function tokenColor(string $prop, string $token): void
    {
        $light = Theme::get("light.{$token}");
        $dark = Theme::get("dark.{$token}");

        if (is_string($light)) {
            $this->buttonProps[$prop] = $light;
        }
        if (is_string($dark) && $dark !== $light) {
            $this->buttonProps['dark_'.$prop] = $dark;
        }
    }

    /** sm | md | lg. Default: md. */
    public function size(string $value): static
    {
        $this->buttonProps['size'] = $value;

        return $this;
    }

    /**
     * Render the label in a custom font. The name is a font file bundled from
     * the app's resources/fonts/ (e.g. `Inter-Bold` for `Inter-Bold.ttf`).
     */
    public function font(string $name): static
    {
        $this->buttonProps['font_name'] = $name;

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->buttonProps['disabled'] = $value;

        return $this;
    }

    public function loading(bool $value = true): static
    {
        $this->buttonProps['loading'] = $value;

        return $this;
    }

    /**
     * Leading icon. Resolved per-platform — pass `ios:` and/or `android:`
     * for cross-platform parity. Stored as `leading_icon` to match the
     * interned prop key table (NPUI_KEY_LEADING_ICON = 37); the optional
     * `leading_icon_variant` companion ('filled' / 'outlined') tells the
     * Compose `MaterialIcon` composable which font to use.
     */
    public function icon(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->buttonProps['leading_icon'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->buttonProps['leading_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

    public function iconTrailing(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->buttonProps['trailing_icon'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->buttonProps['trailing_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

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

    // ── Model 3 enforcement ──────────────────────────────────────────────────
    //
    // Button controls its own visuals via `variant` + theme tokens. Per-instance
    // style overrides (bg, border, radius, shadow, opacity, elevation) and
    // internal padding are intentionally ignored. This prevents the collector's
    // applyStyle() from painting a wrapper around the native button.
    //
    // Legit layout props still pass through: margin, width/height/fill, flex,
    // alignSelf. They position the button within its parent.

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
}
