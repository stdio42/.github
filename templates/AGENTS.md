<!-- stdio42-org-policy:start -->
## stdio42 organization instructions

Before working on any `stdio42` project, read the current shared instructions:
https://github.com/stdio42/.github/blob/main/AGENTS.md
and CI policy:
https://github.com/stdio42/.github/blob/main/docs/ci-policy.md

Do this before planning infrastructure, adding dependencies, creating/editing
workflows, or diagnosing CI failures. An organization README is not automatically
loaded by coding agents; this repository-local pointer is intentional.

- Only self-hosted CI runners with explicit OS labels. Never add GitHub-hosted
  runners or fall back to them when a self-hosted job queues.
- Use shared workflows: `stdio42/.github` for general checks/review,
  `stdio42/appstore-ci` for Apple builds/releases, `stdio42/mobile-ci` for mobile
  screenshots. Read the relevant README and workflow inputs before copying code.
- Never use `actions/upload-artifact` or `actions/download-artifact`; use the
  organization's S3 actions and documented artifact paths.
- Runner availability failures do not authorize billing changes, runner-group
  changes, registrations, or a switch to GitHub-hosted infrastructure.
- Honor more specific project instructions that do not weaken this policy.
  If the shared guidance cannot be read, report that gap and avoid guessing CI
  configuration. Never claim a build/test/device check that did not run.
<!-- stdio42-org-policy:end -->
