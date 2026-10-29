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
  auto-merge for post-1.0 packages, except security PRs (below); minor
  updates grouped per package manager. A grouped PR auto-merges only
  when every update in it qualifies, so one pre-1.0 package holds the
  group for a human
- **Tier 2 (cross-major):** major updates require Dependency Dashboard
  approval (governed decision)
- **Security updates:** a PR Renovate opens for a vulnerability alert is
  never auto-merged, whatever its update type; a human merges it
  (ruling 2026-10-23, `leadershipmosaics/lm_app#1718`). This needs the
  Renovate app to have access to the repository's vulnerability alerts;
  without it the fix arrives as an ordinary Tier 1 PR
- **GitHub Actions:** SHA-pinned via `helpers:pinGitHubActionDigests`;
  minor/patch/digest updates of actions, reusable workflows and workflow
  images grouped and auto-merged. Tool and runtime versions passed through
  `with:` blocks (depType `uses-with`, e.g. `python-version`) are never
  auto-merged
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
