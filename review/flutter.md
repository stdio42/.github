
# Flutter / Dart review guidelines (shared — stdio42 apps)

## Async and BuildContext
- A `BuildContext` used after an `await` needs a `mounted` check. Flag
  `Navigator`/`ScaffoldMessenger`/`Theme.of` on a context that crossed an async
  gap without one.
- `setState` after `dispose` throws. Flag a callback or timer that can fire after
  the widget is gone without a `mounted` guard or a cancel in `dispose`.
- Fire-and-forget `Future`s (`save();` with no `await` and no `unawaited`) hide
  errors and race each other. Flag them where ordering or failure matters.

## Lifecycle and leaks
- Every `TextEditingController`, `ScrollController`, `AnimationController`,
  `StreamSubscription`, `Timer` and `ValueNotifier` created by a State is
  disposed or cancelled in `dispose()`.
- A widget that replaces a shared/global callback should restore the previous one
  in `dispose()`, not leave it clobbered for whoever set it first.
- Plugin resources (camera, player, peer connection, renderers) are released on
  every exit path, including when the screen is popped mid-setup.

## Null-safety in practice
- `!` on anything produced asynchronously by a plugin is a crash waiting for a
  slow device. Flag force-unwraps on state that a still-running `Future` fills
  in, especially when the screen renders before setup completes.
- UI state that mirrors plugin state (muted, paused, torch on) must survive that
  setup gap, or the control lies about the hardware. Prefer holding it on the
  object that owns the resource and re-applying it once the resource exists.

## Data and persistence
- `shared_preferences` is one blob per key: unbounded lists rewrite an
  ever-growing string on every append. Flag missing caps on history-style data.
- Hand-rolled `jsonDecode` cast chains (`as Map`, `.cast<...>()`) have no
  compiler check behind them. They need a round-trip test, especially for nested
  and trimmed shapes.

## Platform reality
- Anything reached from a background isolate (push handlers, background fetch)
  cannot see in-memory state and must re-read from disk.
- iOS VoIP/PushKit pushes must be reported to CallKit immediately — using one to
  deliver anything that is not a call risks the app's push privileges.
- Permission denial and plugin-unavailable are normal paths, not exceptional
  ones. Flag code that assumes a plugin initialised.

## Tests
- `flutter analyze` passing is not test coverage. Logic reachable from a pure
  `flutter test` (storage, parsing, pure helpers) should have one.
- Widget-level races that genuinely need a device should be named as uncovered
  rather than left implied.
