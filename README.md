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
