# Android focused-input regression tests

This standalone Robolectric/Compose module compiles the production filled and
outlined editors, their shared dispatcher, and the production Button renderer.
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
