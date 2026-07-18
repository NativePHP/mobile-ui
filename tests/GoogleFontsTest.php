<?php

use Native\Mobile\UI\Fonts\GoogleFonts;

/**
 * Pure-logic tests for `native:font` — css2 URL spec building, @font-face
 * parsing of the TTF-flavored response, the Google-zip-style filename
 * convention, and the config `font-family` rewrite. Network fetch and file
 * writes are exercised manually (the command hits Google's live endpoint).
 */

// ── familySpec ──────────────────────────────────────────────────────────────

it('builds a bare family spec for plain regular', function () {
    expect(GoogleFonts::familySpec('Lobster', [400], false))->toBe('Lobster');
});

it('encodes spaces as plus signs', function () {
    expect(GoogleFonts::familySpec('Rock Salt', [400], false))->toBe('Rock+Salt');
});

it('builds a wght axis spec for multiple weights', function () {
    expect(GoogleFonts::familySpec('Inter', [400, 700], false))->toBe('Inter:wght@400;700');
});

it('builds sorted ital,wght tuples when italics are requested', function () {
    expect(GoogleFonts::familySpec('Inter', [400, 700], true))
        ->toBe('Inter:ital,wght@0,400;0,700;1,400;1,700');
});

// ── parseFaces ──────────────────────────────────────────────────────────────

it('parses weight, style, and ttf url from @font-face blocks', function () {
    $css = <<<'CSS'
    /* latin */
    @font-face {
      font-family: 'Inter';
      font-style: italic;
      font-weight: 700;
      font-display: swap;
      src: url(https://fonts.gstatic.com/s/inter/v20/bolditalic.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Inter';
      font-style: normal;
      font-weight: 400;
      font-display: swap;
      src: url(https://fonts.gstatic.com/s/inter/v20/regular.ttf) format('truetype');
    }
    CSS;

    $faces = GoogleFonts::parseFaces($css);

    expect($faces)->toHaveCount(2);
    expect($faces[0])->toBe(['weight' => 700, 'italic' => true, 'url' => 'https://fonts.gstatic.com/s/inter/v20/bolditalic.ttf']);
    expect($faces[1])->toBe(['weight' => 400, 'italic' => false, 'url' => 'https://fonts.gstatic.com/s/inter/v20/regular.ttf']);
});

it('dedupes unicode-range subset blocks keeping the last (latin) one', function () {
    $css = <<<'CSS'
    /* cyrillic */
    @font-face {
      font-family: 'X';
      font-style: normal;
      font-weight: 400;
      src: url(https://fonts.gstatic.com/s/x/cyrillic.ttf) format('truetype');
    }
    /* latin */
    @font-face {
      font-family: 'X';
      font-style: normal;
      font-weight: 400;
      src: url(https://fonts.gstatic.com/s/x/latin.ttf) format('truetype');
    }
    CSS;

    $faces = GoogleFonts::parseFaces($css);

    expect($faces)->toHaveCount(1);
    expect($faces[0]['url'])->toEndWith('latin.ttf');
});

it('returns null for responses without font faces or without ttf sources', function () {
    expect(GoogleFonts::parseFaces('<html>400 Bad Request</html>'))->toBeNull();

    // woff2-only response (browser UA leaked through) — no ttf urls to use.
    $woff = "@font-face { font-family: 'X'; font-style: normal; font-weight: 400; src: url(https://fonts.gstatic.com/s/x/a.woff2) format('woff2'); }";
    expect(GoogleFonts::parseFaces($woff))->toBeNull();
});

// ── filenameFor ─────────────────────────────────────────────────────────────

it('names files with the Google zip convention', function () {
    expect(GoogleFonts::filenameFor('Lobster', 400, false))->toBe('Lobster-Regular.ttf');
    expect(GoogleFonts::filenameFor('Inter', 700, false))->toBe('Inter-Bold.ttf');
    expect(GoogleFonts::filenameFor('Inter', 400, true))->toBe('Inter-Italic.ttf');
    expect(GoogleFonts::filenameFor('Inter', 700, true))->toBe('Inter-BoldItalic.ttf');
    expect(GoogleFonts::filenameFor('Inter', 200, false))->toBe('Inter-ExtraLight.ttf');
});

it('strips spaces from multi-word families', function () {
    expect(GoogleFonts::filenameFor('Rock Salt', 400, false))->toBe('RockSalt-Regular.ttf');
});

// ── replaceDefaultFontToken ─────────────────────────────────────────────────

it('rewrites the font-family value in config contents', function () {
    $config = "<?php return ['theme' => ['light' => ['font-family' => 'System']]];";

    $updated = GoogleFonts::replaceDefaultFontToken($config, 'Inter-Regular');

    expect($updated)->toContain("'font-family' => 'Inter-Regular'");
    expect($updated)->not->toContain("'System'");
});

it('returns null when the config has no font-family key', function () {
    expect(GoogleFonts::replaceDefaultFontToken('<?php return [];', 'X'))->toBeNull();
});

it('matches the shipped config stub', function () {
    // Regression guard: if the stub's formatting drifts, the command's
    // config rewrite must keep matching it.
    $stub = file_get_contents(dirname(__DIR__).'/config/native-ui.php');

    $updated = GoogleFonts::replaceDefaultFontToken($stub, 'Lobster-Regular');

    expect($updated)->not->toBeNull();
    expect($updated)->toContain("'font-family' => 'Lobster-Regular'");
});
