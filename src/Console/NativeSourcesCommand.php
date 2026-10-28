<?php

namespace Native\Mobile\UI\Console;

use Illuminate\Console\Command;
use Native\Mobile\UI\TreeShaking\ComponentDetector;
use Native\Mobile\UI\TreeShaking\RendererMapper;

/**
 * Outputs a JSON list of native source files to copy for tree-shaking.
 *
 * Called by NativePHP core during the build process when `manages_native_sources`
 * is true in the plugin manifest. Receives `--platform=ios|android` (plus the
 * standard hook flags core always passes) and prints a JSON array of file
 * paths relative to the plugin's native source directory
 * (resources/ios/ or resources/android/).
 *
 * Tree-shaking modes:
 *   - auto: Scan app code to detect used components
 *   - all: Return every renderer file
 *   - manual: Use explicitly configured component list
 *
 * On any internal error, prints the full file list and exits 0 rather than
 * failing the build. Output to stdout is JSON only — any diagnostics go to
 * stderr so core can json_decode the buffer.
 */
class NativeSourcesCommand extends Command
{
    protected $signature = 'nativephp:native-ui:native-sources
        {--platform= : Target platform (ios or android)}
        {--build-path= : Native project build path (passed by core, unused)}
        {--plugin-path= : Plugin path (passed by core, unused)}
        {--app-id= : Application ID (passed by core, unused)}
        {--config= : Build config JSON (passed by core, unused)}
        {--plugins= : Plugin list JSON (passed by core, unused)}';

    protected $description = 'Output JSON list of native source files for tree-shaking';

    public function handle(): int
    {
        $platform = $this->option('platform');

        if (! in_array($platform, ['ios', 'android'], true)) {
            $this->emitJson($this->listAllSourceFiles('android'));

            return self::SUCCESS;
        }

        try {
            $this->emitJson($this->getFilesToCopy($platform));
        } catch (\Throwable $e) {
            fwrite(STDERR, 'Error during tree-shaking: '.$e->getMessage().PHP_EOL);
            $this->emitJson($this->listAllSourceFiles($platform));
        }

        return self::SUCCESS;
    }

    /**
     * @return list<string>
     */
    protected function getFilesToCopy(string $platform): array
    {
        if (! config('native-ui.tree_shaking.enabled', true)) {
            return $this->listAllSourceFiles($platform);
        }

        $mode = config('native-ui.tree_shaking.mode', 'auto');

        if ($mode === 'all') {
            return $this->listAllSourceFiles($platform);
        }

        $usedComponents = $this->detectUsedComponents($mode);

        if ($this->shouldFallbackToAll($usedComponents)) {
            return $this->listAllSourceFiles($platform);
        }

        $mapper = new RendererMapper($this->getManifestPath());

        return array_values(array_filter(
            $mapper->getFilesToCopy($usedComponents, $platform),
            fn (string $file) => $this->sourceFileExists($platform, $file)
        ));
    }

    /**
     * @return list<string>
     */
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

        return in_array('*', $detectedComponents, true);
    }

    /**
     * Every native source file for the platform (mode `all` / error fallback).
     *
     * @return list<string>
     */
    protected function listAllSourceFiles(string $platform): array
    {
        $dir = $this->sourceDir($platform);
        $ext = $platform === 'ios' ? 'swift' : 'kt';
        $files = is_dir($dir) ? (glob("{$dir}/*.{$ext}") ?: []) : [];

        return array_values(array_map('basename', $files));
    }

    protected function sourceFileExists(string $platform, string $file): bool
    {
        return is_file($this->sourceDir($platform).'/'.$file);
    }

    protected function sourceDir(string $platform): string
    {
        return dirname(__DIR__, 2)."/resources/{$platform}";
    }

    protected function getManifestPath(): string
    {
        return dirname(__DIR__, 2).'/nativephp.json';
    }

    /**
     * @param  list<string>  $files
     */
    protected function emitJson(array $files): void
    {
        $this->output->writeln(json_encode(array_values($files), JSON_UNESCAPED_SLASHES));
    }
}
