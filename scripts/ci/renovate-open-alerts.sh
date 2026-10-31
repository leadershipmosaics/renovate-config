#!/usr/bin/env bash
# renovate-open-alerts.sh: flag open Dependabot alerts that have a patch and sit too long.
#
# Renovate may open no PR for an alert. An alert with a published patch that no
# Renovate PR covers is invisible to renovate-stale-security.sh, so the alarm job of
# .github/workflows/renovate-triage.yml runs this script as a second check and
# fails when it flags anything.
#
# Reads on stdin the JSON array from:
#   gh api "repos/<owner>/<repo>/dependabot/alerts?state=open&per_page=100" --paginate
# merged into one array. It makes no gh call itself.
#
# Exit codes: 0 nothing flagged, 1 something flagged, 2 bad input or option.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: <dependabot alerts JSON array> | renovate-open-alerts.sh --hours <n> [--now <epoch-seconds>]

Prints one markdown line per open alert that has a patched version and is
older than --hours (required, a whole number; 0 flags every patched alert created before now), oldest first:
  - #N <package> (<severity>, <manifest>, <scope>) patched in <version>, open since <created_at>, <GHSA> <url>

Alerts without a patched version are never flagged.

Exit codes: 0 nothing flagged, 1 something flagged, 2 bad input or option.
USAGE
}

now=""
hours=""

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

[ -n "$hours" ] || { echo "ERROR: --hours is required" >&2; exit 2; }
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
if ! printf '%s' "$input" | jq -e 'all(.[]; type == "object" and has("number") and has("created_at"))' > /dev/null 2>&1; then
  echo "ERROR: an element lacks number or created_at" >&2
  exit 2
fi

lines="$(printf '%s' "$input" | jq -r --argjson now "$now" --argjson hours "$hours" '
  [ .[]
    | (.created_at | fromdateiso8601) as $created
    # An object with a null identifier counts as unpatched.
    | select(.security_vulnerability.first_patched_version.identifier != null)
    | select(($now - $created) > ($hours * 3600))
    | { created: $created, line:
        "- #\(.number) \(.dependency.package.name // "unknown") (\(.security_advisory.severity // "unknown"), \(.dependency.manifest_path // "unknown"), \(.dependency.scope // "unknown")) patched in \(.security_vulnerability.first_patched_version.identifier), open since \(.created_at), \(.security_advisory.ghsa_id // "unknown") \(.html_url // "unknown")" } ]
  | sort_by(.created) | .[].line
')" || { echo "ERROR: could not evaluate the alert list" >&2; exit 2; }

if [ -n "$lines" ]; then
  printf '%s\n' "$lines"
  exit 1
fi
exit 0
