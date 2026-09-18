<?php

namespace Native\Mobile\UI\Builders;

use Illuminate\View\View;
use Native\Mobile\Edge\Element;

/**
 * Fluent builder for a persistent background layer — content rendered
 * BENEATH every screen routed under the layout, mounted once at the
 * root so it survives tab switches and pushes. The canonical use is a
 * full-screen map behind a pane (Flighty/Maps-style apps): screens swap
 * above it while the map keeps its camera, tiles, and gesture state.
 *
 *   use Native\Mobile\UI\Builders\BackgroundLayer;
 *   use Native\Mobile\UI\Concerns\HasBackgroundLayer;
 *
 *   class AppLayout extends NativeLayout
 *   {
 *       use HasBackgroundLayer;
 *
 *       public function backgroundLayer(NativeComponent $screen): ?BackgroundLayer
 *       {
 *           return BackgroundLayer::make(view('native.map_layer', $screen->mapPayload()));
 *       }
 *   }
 *
 * The method re-evaluates on every publish from the current `$screen`,
 * so the layer's content can be driven by screen state — the NATIVE
 * side updates the existing mounted view in place rather than
 * recreating it.
 */
class BackgroundLayer
{
    protected function __construct(
        protected View|Element $content,
    ) {}

    public static function make(View|Element $content): static
    {
        return new static($content);
    }

    public function getContent(): View|Element
    {
        return $this->content;
    }
}
