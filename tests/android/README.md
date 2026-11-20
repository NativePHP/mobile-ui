# Android renderer regression tests

This standalone Robolectric/Compose module compiles a number of component renderers.

It records the bridge event boundary; it does not load PHP/JNI, render icons or
menus, or prove device IME behaviour. The Mobile policy and node models are read
from an explicit checkout, not substituted by test implementations.

Requires JDK 21, Android SDK 36 and a Mobile checkout with the Android
`KeyboardFocusPolicy.fieldFocused(..., flush)` hook. From this repository:

```bash
/path/to/mobile/resources/androidstudio/gradlew \
  -p tests/android -PmobileRoot=/absolute/path/to/mobile testDebugUnitTest
```

The twelve cases exercise both editors with live, blur and debounce models,
with and without keep-focus-on-submit. They edit while focused, replace the
change callback during composition, then invoke the separate Button's semantic
click action. The latest change must precede press with no duplicate debounce
publication. Native device testing is still needed for tap/IME focus handling.

`GestureAreaSwipeTest` swipes over a pressable inside a gesture area, inside a
pressable around one, and with two fingers, and checks only `@swipe` fires. It
also checks a tap still presses, a vertical drag still scrolls an enclosing
scroll container, and a bound pan still follows the finger. `NodeView` here
stands in for core's: each child is a fixed-size box, clickable like a core
`pressable` when it has a press handler.

`GestureAreaTriggerTest` pulls a pan with a trigger point (`pan-x-trigger`):
let go past the point it fires `@trigger` and springs back, short of it or
after coming back under it it only springs back, the haptic plays each time
the pull goes out past the point, the pan follows the finger to the point
and resists past it, and a drag the other way is left to an enclosing
scroll container.

`GestureAreaBoundedPanTest` puts a `bounded` photo with both pans and a pinch
bound on the first page of a horizontal pager, inside a vertical drag to
close. At whole size, and at 1.01x where there is under 2dp of room, a drag
pages the pager or moves the drag to close and leaves the pans at rest.
Zoomed, the same drags pan the photo and leave the pager and the drag to close
still. A drag the pager or the drag to close has taken stays with it when the
photo zooms partway through, even in steps bigger than touch slop, until a
second finger makes it a pinch and the pager goes back. A pinch at whole size
zooms without paging, and a pinch in doesn't start the drag to close. A double
tap zooms and aims the bound pans, and a pinch straight after it carries on
from its zoom. A swipe straight after a double tap back out pages while the
zoom lands and reports; after a double tap in it pages if it passes slop
before the zoom's first frame, and once the zoom has room it pans and stops
the zoom there. The pager
is Compose's `HorizontalPager`, which the production pager renders, and the
drag to close is `detectVerticalDragGestures`, which a gesture area with a
lone `pan-y-id` runs: `NodeView` here can't hold a gesture area.

`TextInputCaretTest` pushes a new value into the outlined, filled and bare
editors and checks where the caret lands: where the `selection` props say
(code points, clamped), at the end when they don't, never on an echo of what
was typed or in a secure field, and that the placed caret is what
`@selectionChange` reports. It also presses a separate Button straight after
typing and checks the caret's last move reaches PHP before the press does.

`ListAutoScrollTest` exercises both list renderers through Compose semantics.
It checks that an out-of-range request waits for its row, shrinking or emptying
the list doesn't repeat an applied request, disabling then restoring an index
re-arms it, and saved-state restoration keeps the reader's position unless the
request changed while it was saved. Assertions check which row is at the
viewport's top, not just that a scroll was invoked.

`LazyStackPositionTest` checks that a reader at the top of a lazy stack sees
children added above, a reader scrolled down keeps their child in place through
prepends and trims, content padding and gap place the children, and a stack
inside a scroll view falls back to a plain column instead of throwing.

`BottomSheetCloseTest` closes an open sheet and checks its content leaves
composition: when its detents change in the same render, and when a finger
grabs it while it slides away. It also shows a sheet again while it slides
away and checks it comes back up to where it opened. `RenderNode` here draws
each child as `NodeView` does.

`DrawerFillHeightTest` opens a modal drawer from its menu button and checks
an `h-full` child reaches the bottom of the drawer, a sibling without it
keeps its own height, and a child taller than the drawer still scrolls.
`NodeView` here wraps its box in the modifier the drawer passes, so these
check the sizes the drawer hands out, not `justify-between` itself.

`BackgroundLayerStyleTest` puts a column with a background colour, a gradient
and a dark-mode background at the top of a background layer and checks the
pixels drawn, then checks a top element's padding and safe-area insets leave
its background showing around its content. The renderers here draw only the
modifier they are given; core's `nodeStyle` and `nodeLayout` are compiled from
the Mobile checkout.

`DatePickerClearTest` taps the X of a clearable compact picker and checks it
sends `''` with the dialog left closed, that a tap elsewhere on the field and
an accessibility click both open the dialog, and that no X is drawn without a
value, without `clearable` or on a disabled picker.

These are JVM checks; SwiftUI and native device behaviour need separate testing.
