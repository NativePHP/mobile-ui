<?php

namespace Native\Mobile\UI\Console;

use Illuminate\Console\Command;
use Native\Mobile\UI\TreeShaking\ComponentDetector;
use Native\Mobile\UI\TreeShaking\RendererMapper;

/**
 * Outputs a JSON list of native source files to copy for tree-shaking.
 *
 * Called by NativePHP core during the build process when `manages_native_sources`
 * is true in the plugin manifest. Receives `--platform=ios|android` and prints
 * a JSON array of file paths relative to the plugin's native source directory
 * (resources/ios/ or resources/android/).
 *
 * Tree-shaking modes:
 *   - auto: Scan app code to detect used components
 *   - all: Return every renderer file
 *   - manual: Use explicitly configured component list
 *
 * On any error, falls back to returning all files rather than failing the build.
 */
class NativeSourcesCommand extends Command
{
    protected $signature = 'nativephp:native-ui:native-sources {--platform=}';

    protected $description = 'Output JSON list of native source files for tree-shaking';

    public function handle(): int
    {
        $platform = $this->option('platform');

        if (! in_array($platform, ['ios', 'android'], true)) {
            $this->error('Invalid platform. Must be ios or android.');

            return self::FAILURE;
        }

        try {
            $files = $this->getFilesToCopy($platform);
            $this->line(json_encode($files, JSON_UNESCAPED_SLASHES));

            return self::SUCCESS;
        } catch (\Throwable $e) {
            // On error, output all files rather than failing the build
            $this->error('Error during tree-shaking: '.$e->getMessage(), 'stderr');
            $files = $this->getAllFiles($platform);
            $this->line(json_encode($files, JSON_UNESCAPED_SLASHES));

            return self::SUCCESS;
        }
    }

    protected function getFilesToCopy(string $platform): array
    {
        if (! config('native-ui.tree_shaking.enabled', true)) {
            return $this->getAllFiles($platform);
        }

        $mode = config('native-ui.tree_shaking.mode', 'auto');

        if ($mode === 'all') {
            return $this->getAllFiles($platform);
        }

        $usedComponents = $this->detectUsedComponents($mode);

        if ($this->shouldFallbackToAll($usedComponents)) {
            return $this->getAllFiles($platform);
        }

        $mapper = new RendererMapper($this->getManifestPath());

        return $mapper->getFilesToCopy($usedComponents, $platform);
    }

    protected function detectUsedComponents(string $mode): array
    {
        if ($mode === 'manual') {
            return config('native-ui.tree_shaking.components', []);
        }

        $detector = new ComponentDetector(base_path());

        return $detector->detect();
    }

    protected function shouldFallbackToAll(array $detectedComponents): bool
    {
        if (! config('native-ui.tree_shaking.include_all_on_uncertainty', true)) {
            return false;
        }

        // Special marker returned by detector when uncertainty is found
        return in_array('*', $detectedComponents, true);
    }

    protected function getAllFiles(string $platform): array
    {
        $mapper = new RendererMapper($this->getManifestPath());
        $allComponents = $mapper->getAllComponentTypes();

        return $mapper->getFilesToCopy($allComponents, $platform);
    }

    protected function getManifestPath(): string
    {
        return dirname(__DIR__, 2).'/nativephp.json';
    }
}
