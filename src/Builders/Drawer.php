<?php

namespace Native\Mobile\UI\Builders;

use Illuminate\View\View;
use Native\Mobile\Edge\Element;

/**
 * Fluent builder for a content-agnostic side drawer (X-style side nav).
 *
 * A layout returns a Drawer from its `drawer()` method (provide it with the
 * {@see \Native\Mobile\UI\Concerns\HasLayoutDrawer} trait). The content is any
 * Blade view (or pre-built Element), so devs can put whatever UI they want
 * inside:
 *
 *   use Native\Mobile\UI\Builders\Drawer;
 *   use Native\Mobile\UI\Concerns\HasLayoutDrawer;
 *
 *   class AppLayout extends NativeLayout
 *   {
 *       use HasLayoutDrawer;
 *
 *       public function drawer(NativeComponent $screen): ?Drawer
 *       {
 *           return Drawer::make(view('native.side_bar'))
 *               ->width(320)
 *               ->reveal();          // ->modal() is the default
 *       }
 *   }
 *
 * The native-ui chrome contributor renders the content through the screen's own
 * bound Blade path (so `@press` / wire bindings resolve against the screen) and
 * wraps it in an {@see \Native\Mobile\UI\Elements\NativeDrawer} sentinel. The
 * native drawer host hoists that out into a global, persistent drawer.
 */
class Drawer
{
    private View|Element $content;

    private string $mode = 'modal';

    private ?int $width = null;

    private function __construct(View|Element $content)
    {
        $this->content = $content;
    }

    public static function make(View|Element $content): self
    {
        return new self($content);
    }

    /** Drawer width in points/dp. Null = platform default (≈85% phone width). */
    public function width(int $points): self
    {
        $this->width = $points;

        return $this;
    }

    /** Slide the drawer over the content with a dim scrim (default). */
    public function modal(): self
    {
        $this->mode = 'modal';

        return $this;
    }

    /** Push the main content aside to expose the drawer behind it. */
    public function reveal(): self
    {
        $this->mode = 'reveal';

        return $this;
    }

    public function getContent(): View|Element
    {
        return $this->content;
    }

    public function getMode(): string
    {
        return $this->mode;
    }

    public function getWidth(): ?int
    {
        return $this->width;
    }
}
