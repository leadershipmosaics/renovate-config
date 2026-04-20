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

Encodes the two-tier dependency currency model from
[ADR-0005](https://github.com/leadershipmosaics/ai-governance/blob/main/docs/decisions/0005-dependency-currency-practice.md):

- **Tier 1 (within-range):** patch updates auto-merge for post-1.0
  packages; minor updates grouped per package manager
- **Tier 2 (cross-major):** major updates require Dependency Dashboard
  approval (governed decision)
- **GitHub Actions:** SHA-pinned via `helpers:pinGitHubActionDigests`;
  minor/patch updates grouped and auto-merged
- **Schedule:** weekly, Monday mornings (Europe/Amsterdam)
- **Rate limiting:** max 3 PRs/hour, 5 concurrent
- **npm lockfile stability:** `npmInstallTwice` — runs `npm install` twice
  after each dependency update so the lockfile stabilizes before Renovate
  commits. Documented Renovate workaround for the class of npm bugs where
  a single install produces a non-idempotent lockfile
  ([npm/cli#8726](https://github.com/npm/cli/issues/8726)). Consumer repos
  should additionally set `constraints.npm` locally to match their pinned
  npm version; see `leadershipmosaics/lm_app` ADR-0059 for the full model.
