# Shared review guidelines (all stdio42 repos)

Apply these in addition to the standard code-review plugin checks. Report
concrete, actionable issues and cite `file:line`. Skip pure style nits a
formatter or linter would already catch — they cost review attention and find
nothing.

## Correctness
- Trace the actual flow before flagging. A finding that does not survive reading
  the callers is noise, and noise trains people to skip reviews.
- Error paths are handled, not swallowed. Flag a bare `except:` / `catch {}` /
  `if err != nil { }` that hides a real failure behind an empty or default value.
- Flag a fix applied at one call site when the same bug exists in sibling callers
  of the same function — the fix belongs where they all route through.
- Off-by-one, unbounded growth, and unchecked external input on paths that parse
  network or file data.

## Security
- No secrets, tokens, keys, or signing material in source, and none in a URL
  query string — access logs capture full paths, so a query-string credential is
  a credential written to disk in plaintext.
- Endpoints that cost money or bandwidth (relays, transcoders, upload targets)
  are authenticated. Flag any that a bare `curl` can drive.
- Authorization is checked against the authenticated identity, never against a
  value the client supplied in the same request.
- Anything served on a public ingress should not leak presence, identity, or
  membership — including from health and debug endpoints.

## Resource lifecycle
- Files, sockets, subscriptions, observers and timers are closed or cancelled on
  every path, including the error path.
- In-memory maps and caches keyed by an unbounded identifier (a device id, a
  session id, a user id) need an eviction or expiry rule. A per-key cap is not a
  bound on the number of keys.

## Dependencies and builds
- A lockfile that exists must actually be used by the build, or it is decoration
  and the build is not reproducible.
- New dependencies need justification when a few lines of stdlib would do.

## Tests
- New non-trivial logic (a branch, a loop, a parser, a money or auth path) leaves
  behind one runnable check that fails if the logic breaks.
- A test that cannot fail is worse than no test. Flag assertions that hold
  regardless of the behaviour under review.
- Where a change genuinely cannot be tested in CI (needs a device, a real
  credential, hardware), say so explicitly rather than implying coverage.

## Honesty of the change
- Docs, comments and README claims updated by the change should match what the
  code now does. A stale comment asserting an invariant the code dropped is a
  future bug.
- Flag a PR description that claims verification which the diff or CI does not
  show.
