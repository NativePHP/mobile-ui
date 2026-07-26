<?php

namespace Native\Mobile\UI\Fonts;

/**
 * Pure helpers for the `native:font` Google Fonts downloader — URL spec
 * building, css2 response parsing, filename conventions, and the config
 * default-font rewrite. No framework dependencies so the logic is unit
 * testable without booting Laravel; `Console\FontCommand` does the I/O.
 */
class GoogleFonts
{
    /** css2 weight → conventional style name (matches Google's own zip naming). */
    public const WEIGHT_NAMES = [
        100 => 'Thin', 200 => 'ExtraLight', 300 => 'Light', 400 => 'Regular',
        500 => 'Medium', 600 => 'SemiBold', 700 => 'Bold', 800 => 'ExtraBold',
        900 => 'Black',
    ];

    /**
     * Build the css2 family spec. Bare name for plain regular; otherwise the
     * axis-tuple form (tuples must be sorted): Inter:ital,wght@0,400;0,700;1,400
     */
    public static function familySpec(string $family, array $weights, bool $italic): string
    {
        $name = str_replace(' ', '+', self::canonicalFamily($family));

        if ($weights === [400] && ! $italic) {
            return $name;
        }

        if (! $italic) {
            return $name.':wght@'.implode(';', $weights);
        }

        $tuples = [];
        foreach ([0, 1] as $ital) {
            foreach ($weights as $w) {
                $tuples[] = "{$ital},{$w}";
            }
        }

        return $name.':ital,wght@'.implode(';', $tuples);
    }

    /**
     * Parse @font-face blocks out of a css2 response. One block per style for
     * truetype responses (no unicode-range subsetting). Dedupes by weight+style
     * keeping the last block anyway, in case a subset response ever slips
     * through — the latin subset is conventionally last.
     *
     * @return ?array<int, array{weight: int, italic: bool, url: string}>
     */
    public static function parseFaces(string $css): ?array
    {
        if (! str_contains($css, '@font-face')) {
            return null;
        }

        $faces = [];
        preg_match_all('/@font-face\s*{([^}]+)}/', $css, $blocks);

        foreach ($blocks[1] as $block) {
            if (! preg_match('/src:\s*url\((https:[^)]+\.ttf)\)/', $block, $src)) {
                continue;
            }
            preg_match('/font-weight:\s*(\d+)/', $block, $w);
            preg_match('/font-style:\s*(\w+)/', $block, $s);

            $weight = (int) ($w[1] ?? 400);
            $isItalic = ($s[1] ?? 'normal') === 'italic';

            $faces[$weight.($isItalic ? 'i' : '')] = [
                'weight' => $weight,
                'italic' => $isItalic,
                'url' => $src[1],
            ];
        }

        return empty($faces) ? null : array_values($faces);
    }

    /**
     * Family name as typed → canonical spaced form. `+` reads as a space —
     * it's the css2 URL spelling users copy from fonts.google.com, so
     * `Archivo+Black` means the "Archivo Black" family.
     */
    public static function canonicalFamily(string $family): string
    {
        return trim(str_replace('+', ' ', $family));
    }

    /** Inter + 700 + italic → Inter-BoldItalic.ttf (Google's zip convention). */
    public static function filenameFor(string $family, int $weight, bool $italic): string
    {
        $base = str_replace(' ', '', ucwords(self::canonicalFamily($family)));
        $style = self::WEIGHT_NAMES[$weight] ?? (string) $weight;

        if ($italic) {
            $style = $style === 'Regular' ? 'Italic' : $style.'Italic';
        }

        return "{$base}-{$style}.ttf";
    }

    /**
     * Rewrite the app-wide default font in a config file's contents — the
     * `default` alias of the top-level `fonts` block, falling back to a
     * legacy theme `font-family` token. Returns null when neither exists.
     * Line-start anchors keep the docblock example above the fonts block
     * (its lines begin with `|`) from being touched.
     */
    public static function replaceDefaultFontToken(string $config, string $token): ?string
    {
        // Preferred spelling: 'fonts' => ['default' => '…'].
        $updated = preg_replace(
            "/^([ \t]*'fonts'\s*=>\s*\[[^\]]*?'default'\s*=>\s*)'[^']*'/m",
            "\$1'{$token}'",
            $config, 1, $replaced,
        );

        if ($replaced) {
            return $updated;
        }

        // A fonts block with no default alias yet (possibly empty) — insert one.
        $updated = preg_replace(
            "/^([ \t]*)'fonts'\s*=>\s*\[\s*\]/m",
            "\$1'fonts' => [\n\$1    'default' => '{$token}',\n\$1]",
            $config, 1, $replaced,
        );

        if ($replaced) {
            return $updated;
        }

        $updated = preg_replace(
            "/^([ \t]*)('fonts'\s*=>\s*\[)/m",
            "\$1\$2\n\$1    'default' => '{$token}',",
            $config, 1, $replaced,
        );

        if ($replaced) {
            return $updated;
        }

        // Legacy configs predating the fonts block: rewrite font-family in place.
        $updated = preg_replace(
            "/'font-family'\s*=>\s*'[^']*'/",
            "'font-family' => '{$token}'",
            $config,
            count: $replaced,
        );

        return $replaced ? $updated : null;
    }
}
