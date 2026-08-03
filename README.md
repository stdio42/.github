# stdio42/.github

Org-wide defaults. The two workflows here are **reusable** (`on: workflow_call`)
— they do nothing on their own; repos call them.

    .github/workflows/claude-code-review.yml   PR review
    .github/workflows/claude.yml               @claude responder
    review/core.md                             rules applied to every repo
    review/ios.md                              stack overlay: iOS / tvOS
    review/flutter.md                          stack overlay: Flutter / Dart

This repo is **public**, which is load-bearing: a caller's default `GITHUB_TOKEN`
can read it, so the rulesets are real files fetched at review time instead of a
heredoc copy-pasted into every consumer.

## Wiring up a repo

`.github/workflows/claude-code-review.yml`:

```yaml
name: Claude Code Review
on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]
jobs:
  review:
    uses: stdio42/.github/.github/workflows/claude-code-review.yml@main
    secrets: inherit
    with:
      stack: flutter        # omit for core rules only
```

`.github/workflows/claude.yml`:

```yaml
name: Claude Code
on:
  issue_comment: {types: [created]}
  pull_request_review_comment: {types: [created]}
  issues: {types: [opened, assigned]}
  pull_request_review: {types: [submitted]}
jobs:
  claude:
    uses: stdio42/.github/.github/workflows/claude.yml@main
    secrets: inherit
```

Each repo still needs its own `CLAUDE_CODE_OAUTH_TOKEN` secret. `secrets: inherit`
passes the *caller's* secrets, and org-level secrets need Team/Enterprise for
private repos — stdio42 is on the free plan, so per-repo is the only option:

```sh
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo stdio42/<repo>
```

## Inputs (claude-code-review.yml)

| Input | Default | What it does |
|---|---|---|
| `stack` | `''` | Basename of a `review/*.md` overlay. Unknown value warns and falls back to core. |
| `runs-on` | `["self-hosted", "linux"]` | Runner labels. Be specific where a fleet mixes platforms, so a review never starves the shared macOS build runner. |
| `allowed-tools` | `gh pr/issue/api` | Passed to `--allowedTools`. |
| `extra-prompt` | `''` | Repo-specific instructions appended to the prompt. |
| `require-linked-issue` | `false` | Blocking gate: PR must reference an issue. |
| `require-checklist-complete` | `false` | Blocking gate: every task-list item checked. |

## Adding a stack

Drop `review/<name>.md` in this repo and pass `stack: <name>`. No workflow change
— the overlay is concatenated onto `core.md` at review time.
