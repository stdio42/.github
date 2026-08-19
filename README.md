# stdio42/.github

Org-wide defaults. The two workflows here are **reusable** (`on: workflow_call`)
— they do nothing on their own; repos call them.

    .github/workflows/claude-code-review.yml   PR review (reusable)
    .github/workflows/claude.yml               @claude responder (reusable)
    .github/workflows/self-review.yml          runs the above on this repo's own PRs
    review/prompt.md                           what the reviewer is told to do
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
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
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
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Pass the token explicitly rather than `secrets: inherit`. These workflows declare
exactly one required secret and act on PR, issue and comment text that anyone can
influence; `inherit` would hand them every secret the calling repo holds, for no
functional gain.

Each repo still needs its own `CLAUDE_CODE_OAUTH_TOKEN`. Org-level secrets need
Team/Enterprise for private repos and stdio42 is on the free plan, so per-repo is
the only option:

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
| `claude-args` | `''` | Appended to `claude_args`, e.g. `--model claude-sonnet-4-6`. |
| `require-linked-issue` | `false` | Blocking gate: PR must reference an issue. |
| `require-checklist-complete` | `false` | Blocking gate: every task-list item checked. |
| `allowed-bots` | `''` | Bot actors whose PRs may be reviewed, or `*` for all. **Set to `github-actions` in any repo that also runs `claude.yml`** — see below. |

## Running both workflows in one repo

A repo that runs `claude.yml` alongside `claude-code-review.yml` has a gap by
default: PRs the responder opens are authored by `app/github-actions`, and the
review action refuses non-human actors outright —

```text
Workflow initiated by non-human actor: github-actions (type: Bot).
Add bot to allowed_bots list or use '*' to allow all bots.
```

So the responder raises pull requests that the reviewer never looks at, and the
failure is quiet unless someone checks the run. Pass `allowed-bots: github-actions`
in the review caller to close it.

There is a second, separate gate GitHub itself applies: runs on bot-authored PRs
land in `action_required` and wait for a human to approve them under Actions →
"Approve and run". `allowed-bots` does not remove that — it is repo policy, not
action config. Expect one click per responder PR unless the repo's Actions
approval setting is relaxed.

## Responder permissions

`claude.yml` runs with `contents: write`, `issues: write`, `pull-requests: write`
— it can push to PR branches, not just comment. A repo that deliberately keeps
its `@claude` responder read-only (for isolation from the cluster, say) cannot
express that here and should keep its responder inline. `kitten-quest` does.

## Adding a stack

Drop `review/<name>.md` in this repo and pass `stack: <name>`. No workflow change
— the overlay is concatenated onto `core.md` at review time.
