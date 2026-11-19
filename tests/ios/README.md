# iOS logic unit tests

This Swift package tests the plain Swift logic behind the iOS renderers: the
parts that need neither SwiftUI nor the core app. `Sources/NativeUILogic`
links the shipped files from `resources/ios`, so the tests run the code that
ships. It runs on macOS with Xcode 16 or later (Swift Testing). From this
repository:

```bash
swift test --package-path tests/ios
```

`NativeUIPullToRefreshTests` drives the gesture behind a list's custom
pull-to-refresh (used when a plugin registers the indicator): the pull's
progress up to the threshold, a refresh starting only when a finger lets go
past it and never during another, the room kept above the content while it
runs, and where the indicator sits in the gap the pull opens.

The SwiftUI wiring around it (scroll geometry, scroll phases, the overlay)
isn't covered here and needs testing on a simulator or device.
