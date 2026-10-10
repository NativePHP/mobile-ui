<?php

namespace Native\Mobile\UI\Console;

use Native\Mobile\Plugins\Commands\NativePluginHookCommand;
use Native\Mobile\UI\TreeShaking\ComponentDetector;
use Native\Mobile\UI\TreeShaking\RendererMapper;

/**
 * Copy native UI component renderers into the app bundle at build time.
 *
 * Tree-shaking: scans the app's Blade templates and PHP code to determine which
 * components are actually used, then copies only those renderers (Swift for iOS,
 * Kotlin for Android) plus shared utilities and transitive dependencies.
 *
 * Falls back to copying all renderers when:
 *   - config('native-ui.tree_shaking.mode') is 'all'
 *   - Dynamic component names detected (e.g., <native:{{ $type }}>)
 *   - Detection fails or throws
 *
 * Wired as the plugin's `copy_native_sources` hook in nativephp.json; the build's
 * PluginHookRunner invokes it per platform during `native:run` / `native:build`.
 */
class CopyRenderersCommand extends NativePluginHookCommand
{
    protected $signature = 'nativephp:native-ui:copy-renderers';

    protected $description = 'Copy native UI component renderers (with tree-shaking)';

    public function handle(): int
    {
        if (! config('native-ui.tree_shaking.enabled', true)) {
            $this->info('Tree-shaking disabled, copying all renderers');

            return $this->copyAllRenderers();
        }

        $mode = config('native-ui.tree_shaking.mode', 'auto');

        if ($mode === 'all') {
            $this->info('Tree-shaking mode: all — copying all renderers');

            return $this->copyAllRenderers();
        }

        try {
            $usedComponents = $this->detectUsedComponents($mode);

            if ($this->shouldFallbackToAll($usedComponents)) {
                $this->warn('Uncertainty detected, copying all renderers for safety');

                return $this->copyAllRenderers();
            }

            return $this->copySelectedRenderers($usedComponents);

        } catch (\Throwable $e) {
            $this->error('Tree-shaking failed: '.$e->getMessage());
            $this->warn('Falling back to copying all renderers');

            return $this->copyAllRenderers();
        }
    }

    protected function detectUsedComponents(string $mode): array
    {
        if ($mode === 'manual') {
            $components = config('native-ui.tree_shaking.components', []);
            $this->info('Manual mode: using '.count($components).' configured components');

            return $components;
        }

        $detector = new ComponentDetector(base_path());
        $components = $detector->detect();

        $this->info('Detected '.count($components).' used components');

        return $components;
    }

    protected function shouldFallbackToAll(array $detectedComponents): bool
    {
        if (! config('native-ui.tree_shaking.include_all_on_uncertainty', true)) {
            return false;
        }

        // Special marker returned by detector when uncertainty is found
        return in_array('*', $detectedComponents, true);
    }

    protected function copyAllRenderers(): int
    {
        $mapper = new RendererMapper($this->getManifestPath());
        $allComponents = $mapper->getAllComponentTypes();

        return $this->copySelectedRenderers($allComponents);
    }

    protected function copySelectedRenderers(array $componentTypes): int
    {
        $mapper = new RendererMapper($this->getManifestPath());

        $platform = $this->isIos() ? 'ios' : 'android';
        $filesToCopy = $mapper->getFilesToCopy($componentTypes, $platform);

        $this->info("Copying {$platform} renderers: ".count($filesToCopy).' files');

        $sourceBase = dirname(__DIR__, 2)."/resources/{$platform}";
        $destBase = $this->buildPath().$this->getPlatformDestPath($platform);

        foreach ($filesToCopy as $file) {
            $source = "{$sourceBase}/{$file}";
            $dest = "{$destBase}/{$file}";

            if (! file_exists($source)) {
                $this->warn("Source file not found: {$source}");
                continue;
            }

            $this->copyFile($source, $dest);
        }

        return self::SUCCESS;
    }

    protected function getPlatformDestPath(string $platform): string
    {
        return match ($platform) {
            'ios' => '/NativePHP/Sources/NativeUI',
            'android' => '/app/src/main/java/com/nativephp/plugins/native_ui',
        };
    }

    protected function getManifestPath(): string
    {
        return dirname(__DIR__, 2).'/nativephp.json';
    }
}
