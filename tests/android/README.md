# Android renderer regression tests

This standalone Robolectric/Compose module compiles the production filled and
outlined editors, their shared dispatcher, the production Button renderer and
the production gesture area, list, virtual list and pager renderers.
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
These are JVM checks; SwiftUI and native device behaviour need separate testing.
