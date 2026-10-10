<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Scans renderer source files for references to other renderers.
 *
 * Example: ButtonGroupRenderer may reference ButtonRenderer,
 * so if ButtonGroup is used, Button's renderer must also be included.
 */
class RendererDependencyResolver
{
    protected string $sourcePath;

    protected string $platform;

    protected array $cache = [];

    public function __construct(string $sourcePath, string $platform)
    {
        $this->sourcePath = $sourcePath;
        $this->platform = $platform;
    }

    public function getDependencies(string $file): array
    {
        if (isset($this->cache[$file])) {
            return $this->cache[$file];
        }

        $filePath = $this->sourcePath.'/'.$file;

        if (! file_exists($filePath)) {
            $this->cache[$file] = [];

            return [];
        }

        $content = file_get_contents($filePath);
        $deps = $this->extractDependencies($content);

        $this->cache[$file] = $deps;

        return $deps;
    }

    protected function extractDependencies(string $content): array
    {
        $deps = [];

        if ($this->platform === 'ios') {
            // Look for references to other NativeUI renderers in Swift
            // Example: "NativeUIButtonRenderer", "NativeUIEmptyRenderer"
            if (preg_match_all('/NativeUI([A-Z][a-zA-Z]+)Renderer/', $content, $matches)) {
                foreach ($matches[0] as $renderer) {
                    $deps[] = "{$renderer}.swift";
                }
            }

            // Also check for struct/class usage patterns
            if (preg_match_all('/:\s*NativeUI([A-Z][a-zA-Z]+)/', $content, $matches)) {
                foreach ($matches[1] as $name) {
                    // Check if it's a renderer (not just a helper like NativeUITheme)
                    if (str_ends_with($name, 'Renderer') || $name === 'EmptyRenderer') {
                        $deps[] = "NativeUI{$name}.swift";
                    }
                }
            }
        } else {
            // Android: Look for references to other renderers in Kotlin
            // Pattern: "@Composable fun ButtonRenderer" or "ButtonRenderer("
            if (preg_match_all('/([A-Z][a-zA-Z]+Renderer)\s*\(/', $content, $matches)) {
                foreach ($matches[1] as $renderer) {
                    if ($renderer !== 'Renderer') { // Skip generic "Renderer" word
                        $deps[] = "{$renderer}.kt";
                    }
                }
            }

            // Import statements: com.nativephp.plugins.native_ui.ui.ButtonRenderer
            if (preg_match_all(
                '/import\s+com\.nativephp\.plugins\.native_ui\.ui\.([A-Z][a-zA-Z]+)/',
                $content,
                $matches
            )) {
                foreach ($matches[1] as $className) {
                    $deps[] = "{$className}.kt";
                }
            }
        }

        // Remove the file itself if it appears in deps
        $currentFile = basename($this->sourcePath);
        $deps = array_filter($deps, fn ($dep) => $dep !== $currentFile);

        return array_values(array_unique($deps));
    }
}
