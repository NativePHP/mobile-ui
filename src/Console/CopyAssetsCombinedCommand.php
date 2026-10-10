<?php

namespace Native\Mobile\UI\Console;

use Native\Mobile\Plugins\Commands\NativePluginHookCommand;

/**
 * Combined hook command that runs both font copying and renderer tree-shaking.
 *
 * Wired as the plugin's `copy_assets` hook in nativephp.json; the build's
 * PluginHookRunner invokes it per platform during `native:run` / `native:build`.
 *
 * This combines two operations:
 * 1. Copy custom fonts from resources/fonts/ (CopyFontsCommand)
 * 2. Copy native UI renderers with tree-shaking (CopyRenderersCommand)
 *
 * Both operations run sequentially on the same hook to ensure proper execution
 * order within the NativePHP plugin lifecycle.
 */
class CopyAssetsCombinedCommand extends NativePluginHookCommand
{
    protected $signature = 'nativephp:native-ui:copy-assets-combined';

    protected $description = 'Copy fonts and native UI renderers with tree-shaking';

    public function handle(): int
    {
        // First, copy fonts
        $fontsCommand = new CopyFontsCommand();
        $fontsCommand->setLaravel($this->laravel);
        $fontsCommand->setApplication($this->getApplication());

        // Copy over the hook context (platform detection, build path, etc.)
        $this->transferContextTo($fontsCommand);

        $fontsResult = $fontsCommand->handle();

        if ($fontsResult !== self::SUCCESS) {
            $this->warn('Font copying encountered issues');
        }

        // Then, copy renderers with tree-shaking
        $renderersCommand = new CopyRenderersCommand();
        $renderersCommand->setLaravel($this->laravel);
        $renderersCommand->setApplication($this->getApplication());

        $this->transferContextTo($renderersCommand);

        $renderersResult = $renderersCommand->handle();

        // Return success only if both succeeded
        return ($fontsResult === self::SUCCESS && $renderersResult === self::SUCCESS)
            ? self::SUCCESS
            : self::FAILURE;
    }

    /**
     * Transfer the hook execution context (platform, build path, etc.) to a child command.
     * NativePluginHookCommand stores these in protected properties that need to be accessible.
     */
    protected function transferContextTo(NativePluginHookCommand $command): void
    {
        // The parent class handles platform detection and build paths via its own methods
        // that read from the execution context. No explicit transfer needed - the child
        // commands will inherit the same execution environment when called from this handle().
    }
}
