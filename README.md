# renovate-config

Shared [Renovate](https://docs.renovatebot.com/) configuration presets for
leadershipmosaics repositories.

## Usage

Add to your repository's `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>leadershipmosaics/renovate-config"]
}
```

## What this config does

Encodes the two-tier dependency currency model from lm_app
[ADR-0004](https://github.com/leadershipmosaics/lm_app/blob/main/docs/decisions/governance/0004-dependency-currency-practice.md).
The policy table in lm_app
[update-cadence.md](https://github.com/leadershipmosaics/lm_app/blob/main/docs/specifications/governance/dependency-currency/update-cadence.md)
is the org policy; this preset encodes it, and each consuming repo records
its own divergences locally. What the preset does:

- **Tier 1 (within-range):** patch updates, and npm minor updates,
  auto-merge for post-1.0 packages, except security PRs, `uses-with`
  versions and mise-managed tools (below); minor updates grouped per
  package manager. A grouped PR auto-merges only when every update in
  it qualifies, so one pre-1.0 package holds the group for a human
- **Tier 2 (cross-major):** major updates require Dependency Dashboard
  approval (governed decision)
- **Security updates:** a PR Renovate opens for a vulnerability alert is
  never auto-merged, whatever its update type; a human merges it
  (ruling 2026-10-23, `leadershipmosaics/lm_app#1718`). This needs the
  Renovate app to have access to the repository's vulnerability alerts;
  without it the fix arrives as an ordinary Tier 1 PR
- **GitHub Actions:** SHA-pinned via `helpers:pinGitHubActionDigests`;
  minor/patch/digest updates of actions, reusable workflows, runner labels
  and container, service and Docker-action images grouped and auto-merged;
  the group is an explicit depType allow-list, so a new Renovate depType is
  not grouped until added there. Tool and runtime versions passed through
  `with:` blocks (depType `uses-with`, e.g. `python-version`) are never
  auto-merged
- **mise-managed tools:** every version pinned in `.mise.toml` (mise
  manager) is runtime tooling and is never auto-merged, whatever the
  update type; a consumer group that contains a mise update turns
  manual with it
- **Schedule:** weekly, Monday mornings (Europe/Amsterdam)
- **Rate limiting:** max 3 PRs/hour, 5 concurrent
- **npm lockfile stability:** `npmInstallTwice` — runs `npm install` twice
  after each dependency update so the lockfile stabilizes before Renovate
  commits. Documented Renovate workaround for the class of npm bugs where
  a single install produces a non-idempotent lockfile
  ([npm/cli#8726](https://github.com/npm/cli/issues/8726)). Consumer repos
  should additionally set `constraints.npm` locally to match their pinned
  npm version; see `leadershipmosaics/lm_app` ADR-0059 for the full model.
- **Lockfile maintenance:** weekly refresh of lockfiles without changes to
  manifest version ranges, auto-merged after CI passes. Closes the
  transitive-vulnerability gap where a patched version is published but
  no top-level manifest change pulls it through. Safe to auto-merge:
  resolved versions move within ranges already accepted by maintainers.

## Renovate triage workflow

`.github/workflows/renovate-triage.yml` is a reusable workflow
(`workflow_call`) that gives every repo the same Renovate triage. It
surfaces state and decides or merges nothing. Two jobs, chosen by the
caller through the `job` input:

- `alarm` (run daily): fails the run when a Renovate `[security]` PR has
  been open longer than `security_stale_hours`, or when an open Dependabot
  alert of the calling repo has a patched version and is older than
  `security_stale_hours`. The second check covers an alert Renovate never
  turned into a PR.
- `digest` (run weekly and on manual dispatch): posts a digest comment on
  the triage issue (open Renovate PRs, stuck PRs, stale security PRs,
  majors pending approval), then fails the run when an open Renovate PR is
  older than `stale_days`, a security PR is over `security_stale_hours`, or
  `fail_on_pending` is true and the Dependency Dashboard has items under
  `## Pending Approval`. The comment is posted before the failure, so a red
  run always has its evidence on the triage issue.

The caller owns its schedule. `github.event.schedule` is the caller's
event, so the workflow does not route on cron text; the caller maps its
crons to `job`.

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `job` | yes | none | `alarm` or `digest` |
| `dashboard_issue` | yes | none | Dashboard issue number in the calling repo |
| `triage_issue` | yes | none | Rolling issue that receives the digest |
| `policy_url` | no | lm_app `update-cadence.md` | Policy the digest cites |
| `runbook_url` | no | empty | Runbook linked when a security PR is stuck or an alert has no fix PR |
| `stale_days` | no | `7` | Days an open Renovate PR may wait |
| `security_stale_hours` | no | `48` | Hours a security PR, or a Dependabot alert with a patch, may stay open |
| `fail_on_pending` | no | `false` | Go red on a non-empty Pending Approval |

Caller example (`.github/workflows/renovate-triage.yml` in the calling
repo):

```yaml
name: Renovate triage
on:
  schedule:
    - cron: "0 8 * * 1"   # Mondays, digest
    - cron: "30 8 * * *"  # daily, alarm
  workflow_dispatch: {}
jobs:
  digest:
    if: github.event_name == 'workflow_dispatch' || github.event.schedule == '0 8 * * 1'
    permissions:
      contents: read
      issues: write
      pull-requests: read
      checks: read
      statuses: read
      actions: read
      vulnerability-alerts: read
    uses: leadershipmosaics/renovate-config/.github/workflows/renovate-triage.yml@<full commit SHA> # main
    with:
      job: digest
      dashboard_issue: "40"
      triage_issue: "117"
      fail_on_pending: true
  alarm:
    if: github.event.schedule == '30 8 * * *'
    permissions:
      contents: read
      pull-requests: read
      checks: read
      statuses: read
      actions: read
      vulnerability-alerts: read
    uses: leadershipmosaics/renovate-config/.github/workflows/renovate-triage.yml@<full commit SHA> # main
    with:
      job: alarm
      dashboard_issue: "40"
      triage_issue: "117"
```

The caller states the permissions per job. GitHub checks every job of
the called workflow against the calling job's permissions, whatever that
job's `if`, so the `digest` job declares none and runs with the calling
job's, while the `alarm` job declares a read-only set and needs no
`issues: write`. The `alarm` job needs `vulnerability-alerts: read` to list
Dependabot alerts (`read-all` includes it), and because of that check every
calling job must hold it, the `digest` caller job included. A caller missing
the scope fails at startup with a workflow-level nested-job permission error,
not in the alerts step. The alerts step itself fails with a message naming
Dependabot alerts disabled on the repo, a token or rate-limit failure, or a
network failure. A first `validate` job fails the run with a
clear message when `job` is neither `alarm` nor `digest`.

The scripts are fetched by an explicit checkout of this repo at
`job.workflow_sha`, the commit of the workflow file that defines the
running job, since a called workflow's `actions/checkout` fetches the
caller's repo. The repo is public, so no token is needed. actionlint
1.7.12 does not know `job.workflow_sha` yet (rhysd/actionlint#707), nor
the `vulnerability-alerts` permission scope; run it with
`-ignore 'property "workflow_sha" is not defined' -ignore 'unknown permission scope "vulnerability-alerts"'`.

Pinning: callers reference the workflow by full commit SHA. That
reference is a `uses:` of a reusable workflow (Renovate depType
`workflow`), so the preset's "GitHub Actions updates" group is expected
to keep it current and auto-merge the digest bump like any other action
digest. This is expected, not verified: the first Renovate run on a
caller confirms it.
The pin covers the workflow YAML and the scripts alike, since the
scripts are checked out at the same commit.

Next step: lm_app migrates its in-repo `renovate-triage.yml` and
`renovate-stale-security.sh` to this workflow and drops its own copies.
