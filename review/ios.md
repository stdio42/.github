# iOS / tvOS review guidelines (shared — stdio42 apps)

Apply these in addition to the standard code-review plugin checks. Report
concrete, actionable issues and cite `file:line`. Skip pure style nits a
formatter would catch.

## Concurrency & main thread
- UI state is mutated only on the main actor; networking/decoding/CPU work
  runs off it. Flag UI updates from background contexts missing `@MainActor`
  / `await MainActor.run`.
- Prefer `async`/`await` over nested completion handlers. Flag anything that
  blocks the main thread (sync network, large sync file I/O on the main queue).
- Check `Sendable` / actor-isolation correctness; flag data races on shared
  mutable state.

## Memory & lifecycle
- Closures that capture `self` in long-lived objects (network delegates,
  Combine sinks, AVPlayer/KVO observers) must use `[weak self]`. Flag likely
  retain cycles.
- SwiftUI property wrappers: `@StateObject` for view-owned objects,
  `@ObservedObject` for injected ones, `@State` for value-type view-local
  state. Flag `@ObservedObject` on an object the view itself creates
  (recreated every render).
- AVFoundation / KSPlayer: players, time observers, and resource-loader
  delegates are torn down on disappear. Flag leaked time observers or
  unbalanced KVO add/remove.

## Correctness
- Avoid force-unwrap (`!`) and `try!` on external data (network, parsing);
  handle nil/error paths. Flag silent failure that masks real errors.
- JSON/network decode errors are surfaced, not swallowed into empty state.
- No hard-coded server URLs or device identifiers leaking into shared code.

## Security & privacy
- No secrets, tokens, or signing material committed to source.
- ATS exceptions (NSAppTransportSecurity) stay minimal and justified — a
  specific host, never a blanket `NSAllowsArbitraryLoads`. Flag any widening.
- New data collection needs the matching Info.plist usage-description string.

## App Store / build hygiene
- Version and build numbers are stamped by the release workflow (tag ->
  CFBundleShortVersionString, run number -> CFBundleVersion). Flag hand-edited
  version/build numbers.
- Signing identity / provisioning profile in `project.yml` should not change
  casually. Flag edits to CODE_SIGN_IDENTITY / PROVISIONING_PROFILE_SPECIFIER
  unless clearly intentional.
- No private/undocumented Apple API usage.
- tvOS: focus-engine correctness — focusable elements are reachable and there
  are no focus traps.

## Tests
- New non-trivial logic in a pure/testable layer should have unit tests where
  a test target exists; note untested risk where one doesn't.
