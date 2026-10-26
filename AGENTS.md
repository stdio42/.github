# Instructions for stdio42 projects

For every repository owned by `stdio42`, read this file and
[CI policy](docs/ci-policy.md) before implementing work. This is the canonical
organization entry point; consuming projects install a root `AGENTS.md` pointer
using `scripts/bootstrap_ci.py`. GitHub does not automatically inherit AGENTS.md
across repositories, and a workspace file is not a durable chat memory.

## Mandatory CI rules

- Use only self-hosted runners with literal `self-hosted` and explicit OS labels.
  Linux: `[self-hosted, linux]`; Apple: `[self-hosted, macOS, ARM64]`. Add specialist
  labels only after verifying them in the relevant shared repository.
- Never use GitHub-hosted runners, including public-repository exceptions.
  Queued jobs require diagnosing fleet/access/provisioning, not a hosted fallback
  or billing changes. Do not change runner registrations or org access without
  authorization for that operational change.
- Never use GitHub artifact storage. Use `stdio42/.github/actions/upload-s3` and
  the documented S3 paths with explicitly scoped credential bindings.
- Use thin callers of shared workflows rather than duplicating CI implementation.
  Before changing a shared workflow, read its callers and retain compatible
  defaults. Validate caller-provided runner labels before scheduling any job.
- Run the policy checker and targeted tests before pushing workflow changes.
  Do not imply that a queued job, skipped test or unavailable device passed.

## Shared repositories to consult

1. `stdio42/.github`: organization policy, agent instructions, general CI, review,
   S3 artifacts and project bootstrap.
2. `stdio42/appstore-ci`: Xcode simulator checks, signing, TestFlight/App Store
   builds and releases. Read its README before creating Apple workflows.
3. `stdio42/mobile-ci`: screenshot capture and mobile test infrastructure.
4. `stdio42/gha-runners-infra`: documented fleet labels/capabilities and queue
   diagnostics. Reading this does not authorize Terraform or infrastructure edits.

## Working in this repository

Run `python3 -m pip install -r scripts/requirements.txt`, then
`python3 -m unittest discover -s tests -p 'test_*.py'`,
`python3 scripts/ci_policy.py .`, and relevant `tests/test-*.sh` checks.
The root README describes the existing S3 action checks. No sub-agent delegation
is required by these instructions.
