# Contributing

Thanks for helping out with NativePHP!

Everything you need to know about contributing, from opening a pull request
to our Code of Conduct, is at
[nativephp.com/contributing](https://nativephp.com/contributing).

Please don't report security vulnerabilities in public issues. Follow the
security policy at [nativephp.com/security](https://nativephp.com/security)
instead.

## Component contract

Every element in this package should meet the rules below, and UI plugins
built on it should too. Each rule is something an app author relies on
without checking, so breaking one is a bug. When a pull request adds or
changes a component, say how it meets each rule that applies.

### Values and state

- A bound value is what PHP stores: a stable value, never a display label or
  a row index. `null` means nothing is selected, and a control never picks
  the first option on its own.
- PHP owns the value. A user change is sent straight away, and the control
  settles on whatever PHP publishes next.
- A value PHP publishes never comes back to PHP as a change event, and a
  value PHP sets is never reported as the user's change.
- Text inputs keep what the person typed when PHP publishes an earlier value
  late. Use `TextEchoTracker` (Android) or `NativeUITextEchoTracker` (iOS).
- A disabled control, or a disabled option, sends nothing.

### Both platforms

- iOS and Android ship together, with the same documented props, events and
  behaviour. They needn't look the same: SwiftUI controls on iOS and
  Material 3 on Android.
- A prop that only one platform reads ends in `-ios` or `-android`, as icon
  props do.

### Accessibility

- Every control has an accessible name, from its visible label or
  `a11y-label`, reads `a11y-hint`, and exposes its role, value, and selected
  and disabled state to VoiceOver and TalkBack.
- Touch targets are at least 44 pt on iOS and 48 dp on Android.
- Text grows with Dynamic Type and Android's font size.
- Decorative icons are hidden from screen readers.

### Theme and layout

- Colours come from theme tokens, in light and dark. Renderers don't
  hard-code colours.
- `class` sizes and places the element. A renderer fills the width the host
  gives it: `w-full`, `flex-1` in a row, and fixed or percentage widths.

### Renderer hooks

- A text input registers with `KeyboardFocusPolicy.fieldFocused(…, flush:)`
  while it has focus, so a pending `.blur` or `.debounce` change reaches PHP
  before a separate press.
- A control that sends a press goes through the policy first:
  `KeyboardFocusPolicy.dispatchPress` on iOS and
  `KeyboardFocusPolicy.dismissForInteractiveTap()` on Android.
- An element presented over the whole window, such as a sheet or a modal,
  closes when its screen navigates away.

### Tests

- PHP: attribute parsing and the props each element publishes, in `tests/`.
- Android: behaviour that depends on Compose state, in the Robolectric
  module in `tests/android`.
- iOS: this repository has no iOS test target yet. Say how you checked the
  change, for example on which simulator or device and in which states.
