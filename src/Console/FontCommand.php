<?php

namespace Native\Mobile\UI\Console;

use Illuminate\Console\Command;
use Native\Mobile\UI\Fonts\GoogleFonts;

use function Laravel\Prompts\confirm;
use function Laravel\Prompts\select;

/**
 * Download Google Fonts into the app's `resources/fonts/`.
 *
 *   php artisan native:font Lobster
 *   php artisan native:font "Rock Salt" Inter
 *   php artisan native:font Inter --weights=400,700
 *   php artisan native:font Inter --italic
 *   php artisan native:font Inter --default        # also set as app-wide default
 *
 * No API key: the CSS API serves TTF sources to non-browser user agents
 * (it only serves woff2 to browsers that advertise support), so we request
 * `fonts.googleapis.com/css2?family=…`, parse the @font-face src urls, and
 * download the files. A 400 from the endpoint means the family (or a
 * requested weight) doesn't exist.
 *
 * Files land as `resources/fonts/<Family>-<Style>.ttf` (e.g. Inter-Bold.ttf)
 * — the basename is the token used in Blade: `<native:text font="Inter-Bold">`.
 * The build's copy_assets hook bundles them into each native project.
 *
 * Google Fonts are libre-licensed (OFL / Apache / UFL), so bundling them in
 * your app is permitted; check the family page if you need specifics.
 *
 * Pure logic (spec building, css parsing, naming, config rewrite) lives in
 * `Fonts\GoogleFonts` so it stays unit-testable without the framework.
 */
class FontCommand extends Command
{
    protected $signature = 'native:font
        {family* : Google Fonts family name(s), e.g. Lobster or "Rock Salt"}
        {--weights=400 : Comma-separated weights to download (e.g. 400,700)}
        {--italic : Also download italic styles for each weight}
        {--default : Set the downloaded font as the app-wide default (theme font-family)}';

    protected $description = 'Download Google Fonts into resources/fonts/ for use with font="…"';

    private const CSS_URL = 'https://fonts.googleapis.com/css2';

    public function handle(): int
    {
        $weights = collect(explode(',', (string) $this->option('weights')))
            ->map(fn ($w) => (int) trim($w))
            ->filter(fn ($w) => isset(GoogleFonts::WEIGHT_NAMES[$w]))
            ->unique()->sort()->values()->all();

        if (empty($weights)) {
            $this->error('No valid weights. Use hundreds from 100–900, e.g. --weights=400,700');

            return self::FAILURE;
        }

        $fontsDir = base_path('resources/fonts');
        @mkdir($fontsDir, 0755, true);

        $tokens = [];

        foreach ($this->argument('family') as $family) {
            $faces = $this->fetchFaces($family, $weights, (bool) $this->option('italic'));

            if ($faces === null) {
                $this->error("\"{$family}\" not found on Google Fonts (check the family name and weights).");

                return self::FAILURE;
            }

            foreach ($faces as $face) {
                $filename = GoogleFonts::filenameFor($family, $face['weight'], $face['italic']);
                $path = $fontsDir.'/'.$filename;

                $ttf = @file_get_contents($face['url']);
                if ($ttf === false) {
                    $this->error("Failed to download {$face['url']}");

                    return self::FAILURE;
                }

                file_put_contents($path, $ttf);
                $tokens[] = pathinfo($filename, PATHINFO_FILENAME);
                $this->components->twoColumnDetail("resources/fonts/{$filename}", $this->formatBytes(strlen($ttf)));
            }
        }

        // Prefer the Regular face for the usage hint (css2 lists italics first).
        $hintToken = collect($tokens)->first(fn ($t) => str_ends_with($t, '-Regular')) ?? $tokens[0];

        $this->newLine();
        $this->components->info('Use in Blade with the font attribute:');
        $this->line('  <native:text font="'.$hintToken.'">…</native:text>');

        $this->maybeSetDefault($tokens);

        return self::SUCCESS;
    }

    /**
     * Fetch the @font-face descriptors for a family from the css2 endpoint.
     * Returns null when the family/weight combination doesn't exist (HTTP 400).
     *
     * @return ?array<int, array{weight: int, italic: bool, url: string}>
     */
    private function fetchFaces(string $family, array $weights, bool $italic): ?array
    {
        $url = self::CSS_URL.'?family='.GoogleFonts::familySpec($family, $weights, $italic);

        // A non-browser UA makes Google serve truetype src urls instead of
        // woff2 (it sniffs UA capabilities). Any non-browser string works.
        $context = stream_context_create(['http' => [
            'user_agent' => 'NativePHP-Fonts/1.0',
            'ignore_errors' => true,
        ]]);

        $css = @file_get_contents($url, context: $context);

        return $css === false ? null : GoogleFonts::parseFaces($css);
    }

    /**
     * Offer to set the downloaded font as the app-wide default — the theme's
     * `font-family` token, which every text renderer falls back to when an
     * element has no `font` of its own.
     */
    private function maybeSetDefault(array $tokens): void
    {
        if (empty($tokens)) {
            return;
        }

        $wantsDefault = $this->option('default')
            || ($this->input->isInteractive() && confirm('Set as the app-wide default font?', default: false));

        if (! $wantsDefault) {
            return;
        }

        $token = count($tokens) === 1 || ! $this->input->isInteractive()
            ? $tokens[0]
            : select('Which font should be the default?', $tokens);

        $configPath = config_path('native-ui.php');

        // Publish the config stub first if the app hasn't.
        if (! file_exists($configPath)) {
            copy(dirname(__DIR__, 2).'/config/native-ui.php', $configPath);
            $this->components->twoColumnDetail('Published', 'config/native-ui.php');
        }

        $updated = GoogleFonts::replaceDefaultFontToken(file_get_contents($configPath), $token);

        if ($updated === null) {
            $this->warn("Couldn't find a 'font-family' key in config/native-ui.php — add it to the theme block yourself:");
            $this->line("  'font-family' => '{$token}',");

            return;
        }

        file_put_contents($configPath, $updated);
        $this->components->twoColumnDetail('Default font', "{$token} (config/native-ui.php)");
    }

    private function formatBytes(int $bytes): string
    {
        return $bytes >= 1048576
            ? round($bytes / 1048576, 1).' MB'
            : round($bytes / 1024).' KB';
    }
}
