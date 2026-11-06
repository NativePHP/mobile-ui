<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Maps component types to native renderer files and resolves dependencies.
 *
 * Reads nativephp.json manifest to map components to Swift/Kotlin renderers,
 * scans renderer sources for transitive dependencies, and includes shared
 * utilities that all renderers need.
 */
class RendererMapper
{
    protected string $manifestPath;

    protected array $manifest;

    protected array $rendererDependenciesCache = [];

    /** @var array<string, array<string, string>> platform => rendererClass => filename */
    protected array $rendererFileIndex = [];

    public function __construct(string $manifestPath)
    {
        $this->manifestPath = $manifestPath;
        $this->manifest = $this->loadManifest();
    }

    public function getAllComponentTypes(): array
    {
        return array_column($this->manifest['components'] ?? [], 'type');
    }

    public function getFilesToCopy(array $componentTypes, string $platform): array
    {
        $files = [];

        // Always include shared/base files
        $files = array_merge($files, $this->getSharedFiles($platform));

        // Add renderer files for used components
        foreach ($componentTypes as $type) {
            $renderer = $this->getRendererName($type, $platform);

            if ($renderer === null) {
                continue;
            }

            $file = $this->rendererToFile($renderer, $platform);

            if ($file !== null) {
                $files[] = $file;
            }
        }

        // Resolve transitive dependencies
        $files = $this->resolveTransitiveDependencies($files, $platform);

        return array_values(array_unique($files));
    }

    protected function getSharedFiles(string $platform): array
    {
        // These files are always needed regardless of which components are used
        if ($platform === 'ios') {
            return [
                'NativeUITheme.swift',
                'NativeUIThemeFunctions.swift',
                'NativeUIFontResolver.swift',
                'NativeUIDrawerHost.swift',
                'NativeUIFloatingOverlayHost.swift',
                'NativeUIBackgroundLayerHost.swift',
                'NativeUITransitionFunctions.swift',
                'NativeUIFillWidthHelper.swift',
                'NativeUINavRenderers.swift',
                'NativeUITextInputCore.swift',
                'NativeUIImageSource.swift',
            ];
        }

        // Android
        return [
            'NativeUITheme.kt',
            'NativeUIThemeFunctions.kt',
            'NativeUIFontResolver.kt',
            'NativeUIChromeInit.kt',
            'NativeLayoutDrawerHost.kt',
            'NativeFloatingOverlayHost.kt',
            'NativeUIBackgroundLayerHost.kt',
            'NativeUITransitionFunctions.kt',
            'TextInputShared.kt',
            'NativeUIImageSource.kt',
        ];
    }

    protected function getRendererName(string $componentType, string $platform): ?string
    {
        $key = $platform === 'ios' ? 'ios_renderer' : 'android_renderer';

        foreach ($this->manifest['components'] ?? [] as $component) {
            if ($component['type'] === $componentType) {
                return $component[$key] ?? null;
            }
        }

        return null;
    }

    protected function rendererToFile(string $renderer, string $platform): ?string
    {
        if ($platform === 'ios') {
            return $this->resolveExistingFile("{$renderer}.swift", $platform);
        }

        $parts = explode('.', $renderer);
        $className = end($parts);

        return $this->resolveExistingFile("{$className}.kt", $platform);
    }

    /**
     * Map a class-named renderer file to the source file that actually
     * defines it (combined files like ContainerRenderers.kt / NativeUISimpleRenderers.swift).
     */
    protected function resolveExistingFile(string $filename, string $platform): ?string
    {
        $dir = dirname($this->manifestPath)."/resources/{$platform}";

        if (is_dir($dir) && file_exists($dir.'/'.$filename)) {
            return $filename;
        }

        $className = pathinfo($filename, PATHINFO_FILENAME);
        $index = $this->buildRendererFileIndex($platform);

        return $index[$className] ?? (is_dir($dir) ? null : $filename);
    }

    /**
     * Scan platform sources for `struct FooRenderer` / `object FooRenderer`
     * so combined files are found when the class-named file does not exist.
     *
     * @return array<string, string>
     */
    protected function buildRendererFileIndex(string $platform): array
    {
        if (isset($this->rendererFileIndex[$platform])) {
            return $this->rendererFileIndex[$platform];
        }

        $index = [];
        $dir = dirname($this->manifestPath)."/resources/{$platform}";
        $ext = $platform === 'ios' ? 'swift' : 'kt';

        if (is_dir($dir)) {
            foreach (glob("{$dir}/*.{$ext}") ?: [] as $path) {
                $content = (string) file_get_contents($path);
                $basename = basename($path);

                if (preg_match_all(
                    '/\b(?:struct|enum|class|protocol|extension|object|fun)\s+([A-Z][a-zA-Z]+Renderer)\b/',
                    $content,
                    $matches
                )) {
                    foreach ($matches[1] as $className) {
                        $index[$className] ??= $basename;
                    }
                }
            }
        }

        $this->rendererFileIndex[$platform] = $index;

        return $index;
    }

    protected function resolveTransitiveDependencies(array $files, string $platform): array
    {
        $resolver = new RendererDependencyResolver(
            dirname($this->manifestPath)."/resources/{$platform}",
            $platform
        );

        $allFiles = $files;

        foreach ($files as $file) {
            foreach ($resolver->getDependencies($file) as $dep) {
                $resolved = $this->resolveExistingFile($dep, $platform);
                if ($resolved !== null) {
                    $allFiles[] = $resolved;
                }
            }
        }

        return array_values(array_unique($allFiles));
    }

    protected function loadManifest(): array
    {
        if (! file_exists($this->manifestPath)) {
            throw new \RuntimeException("Manifest not found: {$this->manifestPath}");
        }

        $content = file_get_contents($this->manifestPath);
        $manifest = json_decode($content, true);

        if ($manifest === null) {
            throw new \RuntimeException("Invalid JSON in manifest: {$this->manifestPath}");
        }

        return $manifest;
    }
}
