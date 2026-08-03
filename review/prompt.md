In addition to the plugin's default checks, apply the shared review guidelines in
`.review-guidelines.md` at the repository root and cite any violations. That file
is generated for this run and is not part of the diff — do not review it.

If it contains a "## Mandatory gates" section, those gates are blocking: when one
fails you MUST request changes and name every failing gate, however good the code
is otherwise.

## Submit a formal verdict

Post a real GitHub review with `gh pr review`, not just a comment. Exactly one of:

- `gh pr review <n> --approve` — no blocking findings. Say so plainly rather than
  inventing reservations to look thorough. Non-blocking observations belong in the
  body of an approving review.
- `gh pr review <n> --request-changes` — at least one finding you would genuinely
  hold a merge for: a correctness bug, a security regression, a broken build, a
  failing mandatory gate, or a claim in the description the diff does not support.
- `gh pr review <n> --comment` — you could not reach a verdict, e.g. the diff
  depends on a private repo or a CI result you cannot read. Say what you could not
  check and why.

Approve when the change is right. A reviewer that never approves teaches people to
merge without reading the review, and a reviewer that approves everything is worth
nothing — the verdict has to carry information.

Apply the same standard every time. If a finding blocks one pull request, the same
finding blocks the next one; if it does not, do not raise it as blocking anywhere.

If `--approve` fails because the review would be on your own pull request, fall
back to `--comment`, state the verdict you would have given, and note why you could
not submit it. Do not silently skip the verdict.

## Labels

After the verdict, set exactly one of `approved for merge` or `changes requested`,
removing the other. Labels must agree with the verdict you just submitted.
