<?php

namespace Native\Mobile\UI;

use Native\Mobile\Edge\TailwindParser;

/**
 * Native UI — Theme token storage.
 *
 * Holds the effective set of theme tokens (colors, radii, typography) for
 * the plugin's components. Backed by `config/native-ui.php` defaults; can be
 * overridden at runtime via Theme::merge() — useful for per-tenant branding.
 *
 * Native side receives tokens via the `NativeUI.Theme.Set` bridge call,
 * which is fired on every merge. Renderers read from their own platform
 * theme store; PHP is the source of truth.
 *
 * Decision log: /docs/NATIVE-UI-REWRITE-PLAN.md (D — theme layer)
 */
class Theme
{
    private static array $tokens = [];

    /**
     * Font aliases — semantic name → resources/fonts/ file token, from
     * `config('native-ui.fonts')`. Rides the theme payload as `fonts`; the
     * native font resolvers consult it before file lookup, so `font="accent"`
     * works everywhere a font token does (elements, chrome, even the
     * `font-family` token itself). The `default` alias, when set, becomes the
     * app-wide default font.
     *
     * @var array<string, string>
     */
    private static array $fonts = [];

    /**
     * Initial load from config. Replaces any existing tokens.
     * Called by NativeUIServiceProvider during boot.
     */
    public static function load(array $tokens): void
    {
        static::$tokens = static::normalizeColors($tokens);
        static::syncConfig();
        static::pushToNative();
    }

    /**
     * Replace the font alias map. Called by NativeUIServiceProvider during
     * boot (before load(), which triggers the push) — call it yourself when
     * re-aliasing at runtime and the push follows automatically.
     */
    public static function fonts(array $aliases, bool $push = false): void
    {
        static::$fonts = $aliases;

        if ($push) {
            static::pushToNative();
        }
    }

    /**
     * Deep merge new tokens on top of existing ones.
     * Per-key override; other keys survive. Triggers native push.
     */
    public static function merge(array $tokens): void
    {
        static::$tokens = static::deepMerge(static::$tokens, static::normalizeColors($tokens));
        static::syncConfig();
        static::pushToNative();
    }

    /**
     * Full effective token set, with auto-derived dark mode where not
     * explicitly specified.
     */
    public static function all(): array
    {
        $tokens = static::$tokens;

        $light = $tokens['light'] ?? [];
        $explicitDark = $tokens['dark'] ?? [];

        // Fill missing dark tokens by inverting luminance of the light equivalent.
        $dark = [];
        foreach ($light as $key => $value) {
            $dark[$key] = $explicitDark[$key]
                ?? (is_string($value) && str_starts_with($value, '#')
                    ? static::invertLuminance($value)
                    : $value);
        }
        // Preserve any dark-only keys (unusual but possible).
        foreach ($explicitDark as $key => $value) {
            if (! isset($dark[$key])) {
                $dark[$key] = $value;
            }
        }

        $tokens['dark'] = $dark;

        // Font aliases ride the same payload. `default` doubles as the
        // app-wide default font: it wins over a literal `font-family` token
        // (the alias map is the newer, preferred spelling).
        if (! empty(static::$fonts)) {
            $tokens['fonts'] = static::$fonts;

            if (isset(static::$fonts['default'])) {
                $tokens['font-family'] = static::$fonts['default'];
            }
        }

        return $tokens;
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        return data_get(static::all(), $key, $default);
    }

    /**
     * Clear all tokens — intended for tests. Does not push.
     */
    public static function reset(): void
    {
        static::$tokens = [];
        static::$fonts = [];
    }

    /**
     * Push the current effective theme to the native side via the bridge.
     * No-ops when the bridge isn't available (e.g., during Laravel console
     * commands outside the mobile runtime, or during early boot).
     */
    public static function pushToNative(): void
    {
        if (! function_exists('nativephp_call')) {
            return;
        }

        // Never during test runs: on a dev machine nativephp_call is the
        // Jump TCP polyfill, and Theme::load() runs at provider boot — with
        // a live Jump session this would add a real device round-trip (~1s)
        // to EVERY test's application boot.
        if (function_exists('app') && app()->bound('env') && app()->runningUnitTests()) {
            return;
        }

        $payload = json_encode(static::all());
        if ($payload === false) {
            return;
        }

        nativephp_call('NativeUI.Theme.Set', $payload);
    }

    // ─── Internals ────────────────────────────────────────────────────────────

    /**
     * Mirror the effective light/dark color blocks back into the Laravel
     * config repository. Core's `theme()` helper reads
     * `config('native-ui.theme.{mode}.{token}')` directly, so without this
     * write-back it hands chrome setters the raw authored strings
     * (`red-500`) that the native color parsers can't decode — they fall
     * back to #000. Syncing the effective set (including the auto-derived
     * dark block) keeps the helper, the renderers, and the native theme
     * store reading identical wire-format hex. No-ops outside a booted
     * Laravel app (plain Pest runs, early boot).
     */
    private static function syncConfig(): void
    {
        if (! function_exists('app') || ! app()->bound('config')) {
            return;
        }

        $all = static::all();

        app('config')->set('native-ui.theme.light', $all['light'] ?? []);
        app('config')->set('native-ui.theme.dark', $all['dark'] ?? []);
    }

    /**
     * Resolve authored color tokens in the `light` / `dark` blocks to
     * wire-format hex. Accepts Tailwind palette names (`red-300`), opacity
     * modifiers (`red-300/20`, `#8B5CF6/50`), and CSS hex with alpha
     * (`#8B5CF680`) — see TailwindParser::resolveColorValue for the full
     * grammar. Unrecognized strings pass through untouched.
     *
     * Only the two color blocks are touched; radii, font sizes, and
     * `font-family` never enter the resolver. method_exists guards against
     * a core version that predates the shared resolver.
     */
    private static function normalizeColors(array $tokens): array
    {
        if (! method_exists(TailwindParser::class, 'resolveColorValue')) {
            return $tokens;
        }

        foreach (['light', 'dark'] as $mode) {
            if (! isset($tokens[$mode]) || ! is_array($tokens[$mode])) {
                continue;
            }
            foreach ($tokens[$mode] as $key => $value) {
                if (! is_string($value)) {
                    continue;
                }
                $tokens[$mode][$key] = TailwindParser::resolveColorValue($value) ?? $value;
            }
        }

        return $tokens;
    }

    private static function deepMerge(array $base, array $overlay): array
    {
        foreach ($overlay as $key => $value) {
            if (is_array($value) && isset($base[$key]) && is_array($base[$key])) {
                $base[$key] = static::deepMerge($base[$key], $value);
            } else {
                $base[$key] = $value;
            }
        }

        return $base;
    }

    /**
     * Invert lightness (HSL) of a #RRGGBB or #AARRGGBB color. Preserves hue
     * and saturation so brand colors remain recognizable in dark mode; a
     * leading alpha byte (wire format) is carried over unchanged.
     */
    private static function invertLuminance(string $hex): string
    {
        $hex = ltrim($hex, '#');

        $alpha = '';
        if (strlen($hex) === 8) {
            $alpha = strtoupper(substr($hex, 0, 2));
            $hex = substr($hex, 2);
        }

        if (strlen($hex) !== 6) {
            return '#'.$alpha.$hex;
        }

        $r = hexdec(substr($hex, 0, 2)) / 255.0;
        $g = hexdec(substr($hex, 2, 2)) / 255.0;
        $b = hexdec(substr($hex, 4, 2)) / 255.0;

        [$h, $s, $l] = static::rgbToHsl($r, $g, $b);

        $l = 1.0 - $l;

        [$r2, $g2, $b2] = static::hslToRgb($h, $s, $l);

        return sprintf(
            '#%s%02X%02X%02X',
            $alpha,
            (int) round($r2 * 255),
            (int) round($g2 * 255),
            (int) round($b2 * 255)
        );
    }

    /** @return array{0: float, 1: float, 2: float} */
    private static function rgbToHsl(float $r, float $g, float $b): array
    {
        $max = max($r, $g, $b);
        $min = min($r, $g, $b);
        $l = ($max + $min) / 2.0;

        if ($max === $min) {
            return [0.0, 0.0, $l];
        }

        $d = $max - $min;
        $s = $l > 0.5 ? $d / (2.0 - $max - $min) : $d / ($max + $min);

        $h = match (true) {
            $max === $r => ($g - $b) / $d + ($g < $b ? 6.0 : 0.0),
            $max === $g => ($b - $r) / $d + 2.0,
            default => ($r - $g) / $d + 4.0,
        };
        $h /= 6.0;

        return [$h, $s, $l];
    }

    /** @return array{0: float, 1: float, 2: float} */
    private static function hslToRgb(float $h, float $s, float $l): array
    {
        if ($s === 0.0) {
            return [$l, $l, $l];
        }

        $q = $l < 0.5 ? $l * (1.0 + $s) : $l + $s - $l * $s;
        $p = 2.0 * $l - $q;

        return [
            static::hueToRgb($p, $q, $h + 1.0 / 3.0),
            static::hueToRgb($p, $q, $h),
            static::hueToRgb($p, $q, $h - 1.0 / 3.0),
        ];
    }

    private static function hueToRgb(float $p, float $q, float $t): float
    {
        if ($t < 0.0) {
            $t += 1.0;
        }
        if ($t > 1.0) {
            $t -= 1.0;
        }
        if ($t < 1.0 / 6.0) {
            return $p + ($q - $p) * 6.0 * $t;
        }
        if ($t < 1.0 / 2.0) {
            return $q;
        }
        if ($t < 2.0 / 3.0) {
            return $p + ($q - $p) * (2.0 / 3.0 - $t) * 6.0;
        }

        return $p;
    }
}
