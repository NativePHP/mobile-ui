<?php

namespace Native\Mobile\UI\Console;

use Native\Mobile\Plugins\Commands\NativePluginHookCommand;

/**
 * Bundles the app's custom fonts into the native project at build time.
 *
 * Drop `.ttf`/`.otf`/`.ttc` files into the app's `resources/fonts/` and they're
 * copied where each platform's renderer looks for them:
 *   - iOS     → NativePHP/Resources/ (a PBXFileSystemSynchronizedRootGroup, so
 *               the file is bundled automatically; the renderer loads + registers
 *               it from Bundle.main and resolves the PostScript name)
 *   - Android → app/src/main/assets/fonts/ (loaded by the renderer via the
 *               AssetManager as `fonts/<file>`)
 *
 * The filename minus extension is the token referenced in Blade, e.g.
 * `resources/fonts/Inter-Bold.ttf` → `<native:text font="Inter-Bold">`.
 *
 * Wired as the plugin's `copy_assets` hook in nativephp.json; the build's
 * PluginHookRunner invokes it per platform during `native:run`.
 */
class CopyFontsCommand extends NativePluginHookCommand
{
    protected $signature = 'nativephp:native-ui:copy-fonts';

    protected $description = 'Copy custom fonts into the native project';

    /** Font container formats we bundle. */
    protected array $fontExtensions = ['ttf', 'otf', 'ttc'];

    public function handle(): int
    {
        $fontsDir = base_path('resources/fonts');

        if (! is_dir($fontsDir)) {
            $this->info('No resources/fonts/ directory found, skipping font assets');

            return self::SUCCESS;
        }

        $files = $this->getFontFiles($fontsDir);

        if (empty($files)) {
            $this->info('No font files found in resources/fonts/');

            return self::SUCCESS;
        }

        $this->info('Found '.count($files).' font file(s)');

        foreach ($files as $file) {
            if ($this->isIos()) {
                $this->copyFile($file, $this->buildPath().'/NativePHP/Resources/'.basename($file));
            }

            if ($this->isAndroid()) {
                $this->copyFile($file, $this->buildPath().'/app/src/main/assets/fonts/'.basename($file));
            }
        }

        return self::SUCCESS;
    }

    protected function getFontFiles(string $dir): array
    {
        $pattern = $dir.'/*.{'.implode(',', $this->fontExtensions).'}';

        return glob($pattern, GLOB_BRACE) ?: [];
    }
}
