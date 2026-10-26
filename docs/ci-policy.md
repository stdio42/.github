# CI policy for every stdio42 project

Start here and in [AGENTS.md](../AGENTS.md) before adding or diagnosing CI.
**Only self-hosted runners. No GitHub artifact storage. No hosted fallback.**
This applies to public and private projects alike.

## Shared implementations

| Need | Shared source |
| --- | --- |
| Node/web checks | [`node-check.yml`](../.github/workflows/node-check.yml) |
| Workflow/artifact policy | [`ci-policy.yml`](../.github/workflows/ci-policy.yml) |
| Dynamic runner validation | [`validate-runner.yml`](../.github/workflows/validate-runner.yml) |
| Apple simulator build/signing/releases | [stdio42/appstore-ci](https://github.com/stdio42/appstore-ci) |
| Mobile screenshots | [stdio42/mobile-ci](https://github.com/stdio42/mobile-ci) |
| Fleet labels, capabilities, queue investigation | [stdio42/gha-runners-infra](https://github.com/stdio42/gha-runners-infra) |
| S3 upload action | [`upload-s3`](../actions/upload-s3/action.yml) |

Read the selected workflow's current inputs, secrets and access requirements.
Do not replace Apple signing/versioning/release logic with copied inline steps.
Linux jobs use `[self-hosted, linux]`; Apple jobs normally use
`[self-hosted, macOS, ARM64]`. Specialist workloads may add verified labels.

## Make agents encounter the rule

From a checkout of this repo:

```bash
python3 scripts/bootstrap_ci.py /path/to/project            # preview
python3 scripts/bootstrap_ci.py /path/to/project --apply    # install
```

This preserves existing instructions, adds an idempotent section to root
`AGENTS.md`, imports it from `CLAUDE.md`, and installs a thin policy workflow.
It refuses to overwrite a different existing policy caller. Put this command
in project-creation tooling/templates. Run it once for existing projects too;
this change does not silently modify every repository in the organization.
GitHub workflow templates alone cannot install a root AGENTS.md file.

Point future assistants at `stdio42/.github/AGENTS.md`. No durable chat-memory
capability is assumed. A repository-local pointer is the portable, reviewable
reminder; this organization file is not automatically inherited by other repos.

## Reuse general checks

```yaml
jobs:
  web:
    uses: stdio42/.github/.github/workflows/node-check.yml@main
    with:
      node-version: '22'
      playwright: true
      checks: npm run lint && npm test && npm run build && npm run test:e2e
    secrets:
      S3_ACCESS_KEY: ${{ secrets.S3_ACCESS_KEY }}
      S3_SECRET_KEY: ${{ secrets.S3_SECRET_KEY }}
```

Node dependencies use `npm ci`. Provision browser system dependencies on the
runner; shared CI installs Chromium without running sudo/apt on a shared host.
Repository-specific commands must come from trusted workflow code, never PR
text or user-controlled dispatch input. Apple callers use appstore-ci's existing
build-check interface, as documented there.

## Enforce routing, including expressions

Run locally:

```bash
python3 -m pip install -r scripts/requirements.txt
python3 scripts/ci_policy.py /path/to/project
```

The checker scans workflows and composite actions. It rejects hosted scalar
labels, arrays without literal self-hosted/OS labels, unsafe runner groups,
finite matrix choices containing hosted labels (including `include` overrides),
unknown dynamic routing, and GitHub upload/download-artifact actions. Literal
runner overrides in reusable callers are checked too.

Free-form reusable input selectors cannot be proved safe from their defaults:
a caller can override a safe default. Route them through a prerequisite instead:

```yaml
jobs:
  runner-policy:
    uses: stdio42/.github/.github/workflows/validate-runner.yml@main
    with:
      labels: ${{ inputs.runner-labels }}
  build:
    needs: runner-policy
    runs-on: ${{ fromJSON(needs.runner-policy.outputs.labels) }}
    steps:
      - run: echo build
```

The validator runs on fixed self-hosted Linux, rejects invalid labels and exposes
outputs only after validation. The build cannot be scheduled on an arbitrary
hosted runner first. A step inside the build would be too late.

The checker recognizes this validator wiring. It does not recursively inspect
arbitrary external reusable workflows/actions; review their implementation and
protect/pin their source. It is not a general shell-code analyzer or a replacement
for GitHub workflow validation. Protect this repo's policy/validator changes.

## Organization-wide protection and remaining setup

Installing a workflow creates a check; it does not make it mandatory or stop a
sibling workflow from scheduling before the check fails. Repository/org admins
must activate the corresponding ruleset/required workflow on protected branches
where their GitHub plan supports it. Require the policy check for merges and
protect the caller/policy files from removal; use an organization-required
workflow, where available, to prevent a PR deleting its own check. Protect the
shared validator/workflow sources as well. Do not advertise enforcement across
all repos until rollout and settings are verified.

If the organization's Actions settings expose a control to disable GitHub-hosted
runners, disable them as defense in depth. Availability depends on the GitHub
plan; this repository does not claim that control exists or changed it. Neither
rulesets nor runner groups, infrastructure, billing, or secret bindings are
changed by the bootstrap script.

The org `.github` repository is public. Existing workflow comments reported that
the runner group excluded public repos. Never work around this with hosted
runners: an administrator must provide appropriate self-hosted access/isolation,
or run the checks locally until that is resolved. Public PR code must not run
on privileged persistent hosts with secrets; use an appropriately isolated
self-hosted fleet. No public runner-group access was enabled by this change.

## Artifact storage and queued jobs

Use the org S3 action from the root README, with explicitly passed credentials.
Never add `actions/upload-artifact` or `actions/download-artifact`. Do not print
credential values. A queued self-hosted job is not evidence of a billing issue;
check access, all requested labels, capacity and provisioning using the fleet
repo. Report queued/blocked checks accurately and do not register runners, alter
billing, change runner groups, or apply Terraform without authorization.
