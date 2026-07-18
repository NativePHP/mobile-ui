<?php

namespace Native\Mobile\UI\Builders;

use Illuminate\View\View;
use Native\Mobile\Edge\Element;

/**
 * Fluent builder for a content-agnostic floating overlay — a free-floating
 * element pinned above the content (and above the tab bar), Apple's
 * "capsule that hovers over everything" pattern. Unlike a bottom bar it does
 * NOT inset / push the content up; it floats on a top layer, so returning
 * null (or a builder wrapping nothing) leaves the screen untouched.
 *
 * A layout returns a FloatingOverlay from its `floatingOverlay()` method
 * (provide it with the {@see \Native\Mobile\UI\Concerns\HasFloatingOverlay}
 * trait). The content is any Blade view (or pre-built Element), so devs can
 * float whatever UI they want — a pill, a banner, a mini-player:
 *
 *   use Native\Mobile\UI\Builders\FloatingOverlay;
 *   use Native\Mobile\UI\Concerns\HasFloatingOverlay;
 *
 *   class AppLayout extends NativeLayout
 *   {
 *       use HasFloatingOverlay;
 *
 *       public function floatingOverlay(NativeComponent $screen): ?FloatingOverlay
 *       {
 *           if (! DiscoveryStore::hasServers()) {
 *               return null;                 // nothing floats
 *           }
 *
 *           return FloatingOverlay::make(view('native.discovery_pill'))
 *               ->offset(88);                // clear the tab bar
 *       }
 *   }
 *
 * The native-ui chrome contributor renders the content through the screen's own
 * bound Blade path (so `@press` / wire bindings resolve against the screen) and
 * wraps it in a {@see \Native\Mobile\UI\Elements\FloatingOverlay} sentinel.
 * The native floating-overlay host hoists that out onto a persistent top layer
 * over every screen routed under the layout.
 */
class FloatingOverlay
{
    private View|Element $content;

    private string $alignment = 'bottom';

    private ?int $offset = null;

    private function __construct(View|Element $content)
    {
        $this->content = $content;
    }

    public static function make(View|Element $content): self
    {
        return new self($content);
    }

    /** Float against the bottom edge, above the tab bar (default). */
    public function bottom(): self
    {
        $this->alignment = 'bottom';

        return $this;
    }

    /** Float against the top edge, below the nav bar. */
    public function top(): self
    {
        $this->alignment = 'top';

        return $this;
    }

    /**
     * Extra distance in points/dp between the overlay and the aligned edge,
     * on top of the safe-area inset. Null = platform default (clears a
     * standard bottom tab bar). Pass a small value on tab-less stack layouts.
     */
    public function offset(int $points): self
    {
        $this->offset = $points;

        return $this;
    }

    public function getContent(): View|Element
    {
        return $this->content;
    }

    public function getAlignment(): string
    {
        return $this->alignment;
    }

    public function getOffset(): ?int
    {
        return $this->offset;
    }
}
