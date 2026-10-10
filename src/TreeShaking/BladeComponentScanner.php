<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Scans Blade templates for mobile-ui component usage.
 *
 * Detects:
 *   - <native:button>, <native:outlined-text-input> (namespace syntax)
 *   - <x-native::button> (x-component syntax)
 *   - <x-dynamic-component :component="..." (uncertainty)
 *   - Dynamic names like <native:{{ $type }}> (uncertainty)
 */
class BladeComponentScanner
{
    protected array $uncertaintyPatterns = [
        // Dynamic component names with expressions
        '/<native:[^>\s]*\{\{/',  // <native:button-{{ or <native:{{ 
        '/<native:[^>\s]*@/',     // <native:button@something (PHP expression)
        '/<native:[^>\s]*\$/',    // <native:button$var or variable interpolation
        '/<x-native::[^>\s]*\{\{/',
        '/<x-native::[^>\s]*\$/',

        // Dynamic component directive
        '/<x-dynamic-component/',
        
        // @component with variables or concatenation
        '/@component\s*\(\s*\$/',
        '/@component\s*\([^)]*\./',  // String concatenation
    ];

    public function scan(array $files): array
    {
        $components = [];
        $uncertain = false;

        foreach ($files as $file) {
            if (! is_readable($file)) {
                // Unreadable file - fail safe
                $uncertain = true;
                continue;
            }

            try {
                $content = @file_get_contents($file);

                if ($content === false) {
                    // Failed to read - fail safe
                    $uncertain = true;
                    continue;
                }

                // Check for uncertainty patterns first
                if ($this->hasUncertainty($content)) {
                    $uncertain = true;
                    continue;
                }

                // Extract component names
                $components = array_merge($components, $this->extractComponents($content));
            } catch (\Throwable $e) {
                // Any error during parsing - fail safe
                $uncertain = true;
            }
        }

        return [
            'components' => array_values(array_unique($components)),
            'uncertain' => $uncertain,
        ];
    }

    protected function hasUncertainty(string $content): bool
    {
        foreach ($this->uncertaintyPatterns as $pattern) {
            if (preg_match($pattern, $content)) {
                return true;
            }
        }

        return false;
    }

    protected function extractComponents(string $content): array
    {
        $components = [];

        // Pattern 1: <native:button>, <native:outlined-text-input>
        if (preg_match_all('/<native:([a-z][a-z0-9_-]*)/i', $content, $matches)) {
            foreach ($matches[1] as $name) {
                $components[] = $this->normalizeComponentName($name);
            }
        }

        // Pattern 2: <x-native::button>
        if (preg_match_all('/<x-native::([a-z][a-z0-9_-]*)/i', $content, $matches)) {
            foreach ($matches[1] as $name) {
                $components[] = $this->normalizeComponentName($name);
            }
        }

        // Pattern 3: @component('native:button') or @component("native.button")
        if (preg_match_all('/@component\s*\(\s*["\']native[:\.]([a-z][a-z0-9_.-]*)["\']/', $content, $matches)) {
            foreach ($matches[1] as $name) {
                $components[] = $this->normalizeComponentName($name);
            }
        }

        return $components;
    }

    protected function normalizeComponentName(string $name): string
    {
        // Convert kebab-case or dot-notation to underscore
        // outlined-text-input -> outlined_text_input
        return str_replace(['-', '.'], '_', strtolower($name));
    }
}
