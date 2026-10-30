#!/usr/bin/env bash
# renovate-stale-security.sh: flag Renovate [security] PRs that sit open too long.
#
# A security fix that stays open is exposure, whether it is red or green. The
# weekly digest already listed a red one for six weeks without effect, so the
# alarm job of .github/workflows/renovate-triage.yml runs this script and fails
# when it flags anything. The caller may pass a runbook_url input.
#
# Reads on stdin the JSON array from:
#   gh pr list --author app/renovate --state open \
#     --json number,title,createdAt,mergeStateStatus,statusCheckRollup
# It makes no gh call itself.
#
# Exit codes: 0 nothing flagged, 1 something flagged, 2 bad input or option.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: gh pr list ... --json number,title,createdAt,mergeStateStatus,statusCheckRollup \
         | renovate-stale-security.sh [--now <epoch-seconds>] [--hours <n>]

Prints one markdown line per open PR whose title contains [security] and that
is older than --hours (default 48):
  - #N <title>: open <D> days, red: <failing checks>
  - #N <title>: open <D> days, not merged, <mergeStateStatus>

Exit codes: 0 nothing flagged, 1 something flagged, 2 bad input or option.
USAGE
}

now=""
hours=48

while [ $# -gt 0 ]; do
  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --now)
      [ $# -ge 2 ] || { echo "ERROR: --now needs a value" >&2; exit 2; }
      now="$2"
      shift 2
      ;;
    --hours)
      [ $# -ge 2 ] || { echo "ERROR: --hours needs a value" >&2; exit 2; }
      hours="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$hours" =~ ^[0-9]+$ ]] || { echo "ERROR: --hours must be a whole number, got: $hours" >&2; exit 2; }
if [ -z "$now" ]; then
  now="$(date -u +%s)"
fi
[[ "$now" =~ ^[0-9]+$ ]] || { echo "ERROR: --now must be epoch seconds, got: $now" >&2; exit 2; }

input="$(cat)"
if [ -z "$input" ]; then
  echo "ERROR: no JSON on stdin" >&2
  exit 2
fi
if ! printf '%s' "$input" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "ERROR: stdin is not a JSON array" >&2
  exit 2
fi

lines="$(printf '%s' "$input" | jq -r --argjson now "$now" --argjson hours "$hours" '
  def red_names:
    [ (.statusCheckRollup // [])[]
      | if .__typename == "StatusContext" or has("context") then
          select(.state == "FAILURE" or .state == "ERROR") | .context
        else
          select(.conclusion as $c
                 | ["FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"]
                 | index($c)) | .name
        end ];
  .[]
  | select((.title // "") | contains("[security]"))
  | ((.createdAt | fromdateiso8601) as $created
     | select(($now - $created) > ($hours * 3600))
     | (($now - $created) / 86400 | floor) as $days
     | red_names as $red
     | "- #\(.number) \(.title): open \($days) days, "
       + (if ($red | length) > 0
          then "red: " + ($red | join(", "))
          else "not merged, \(.mergeStateStatus)" end))
')" || { echo "ERROR: could not evaluate the PR list" >&2; exit 2; }

if [ -n "$lines" ]; then
  printf '%s\n' "$lines"
  exit 1
fi
exit 0
