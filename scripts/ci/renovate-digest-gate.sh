#!/usr/bin/env bash
# renovate-digest-gate.sh: decide whether the weekly Renovate digest run goes red.
#
# Reads on stdin the JSON array from:
#   gh pr list --author app/renovate --state open --json number,title,createdAt,mergeStateStatus,statusCheckRollup
# It makes no gh call itself.
#
# Red (exit 1) when any of these holds:
#   - an open Renovate PR is older than --stale-days
#   - a [security] PR is older than --security-hours (renovate-stale-security.sh)
#   - --fail-on-pending is given and the Dashboard body (--dashboard-file) has an
#     approval checkbox (approve-branch=) under "## Pending Approval"
# Each reason is printed as one markdown line.
#
# Exit codes: 0 nothing flagged, 1 something flagged, 2 bad input or option.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: gh pr list ... | renovate-digest-gate.sh [--now <epoch>] [--stale-days <n>]
         [--security-hours <n>] [--fail-on-pending] [--dashboard-file <path>]

Exit codes: 0 nothing flagged, 1 something flagged, 2 bad input or option.
USAGE
}

now=""
stale_days=7
security_hours=48
fail_on_pending=0
dashboard_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --help | -h) usage; exit 0 ;;
    --now) [ $# -ge 2 ] || { echo "ERROR: --now needs a value" >&2; exit 2; }; now="$2"; shift 2 ;;
    --stale-days) [ $# -ge 2 ] || { echo "ERROR: --stale-days needs a value" >&2; exit 2; }; stale_days="$2"; shift 2 ;;
    --security-hours) [ $# -ge 2 ] || { echo "ERROR: --security-hours needs a value" >&2; exit 2; }; security_hours="$2"; shift 2 ;;
    --fail-on-pending) fail_on_pending=1; shift ;;
    --dashboard-file) [ $# -ge 2 ] || { echo "ERROR: --dashboard-file needs a value" >&2; exit 2; }; dashboard_file="$2"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$stale_days" =~ ^[0-9]+$ ]] || { echo "ERROR: --stale-days must be a whole number, got: $stale_days" >&2; exit 2; }
[[ "$security_hours" =~ ^[0-9]+$ ]] || { echo "ERROR: --security-hours must be a whole number, got: $security_hours" >&2; exit 2; }
if [ -z "$now" ]; then now="$(date -u +%s)"; fi
[[ "$now" =~ ^[0-9]+$ ]] || { echo "ERROR: --now must be epoch seconds, got: $now" >&2; exit 2; }
if [ "$fail_on_pending" -eq 1 ] && { [ -z "$dashboard_file" ] || [ ! -f "$dashboard_file" ] || [ ! -r "$dashboard_file" ]; }; then
  echo "ERROR: --fail-on-pending needs a readable --dashboard-file" >&2
  exit 2
fi

input="$(cat)"
if [ -z "$input" ] || ! printf '%s' "$input" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "ERROR: stdin is not a JSON array" >&2
  exit 2
fi

red=0

stale="$(printf '%s' "$input" | jq -r --argjson now "$now" --argjson days "$stale_days" '
  .[] | ((.createdAt | fromdateiso8601) as $c
         | select(($now - $c) > ($days * 86400))
         | "- #\(.number) \(.title): open \((($now - $c) / 86400) | floor) days, over \($days)")
')" || { echo "ERROR: could not evaluate the PR list" >&2; exit 2; }
if [ -n "$stale" ]; then
  red=1
  printf 'Open over %s days:\n%s\n' "$stale_days" "$stale"
fi

sec_rc=0
sec_out="$(printf '%s' "$input" | bash "${here:?}/renovate-stale-security.sh" --now "$now" --hours "$security_hours")" || sec_rc=$?
if [ "$sec_rc" -eq 1 ]; then
  red=1
  printf 'Security fixes open over %s hours:\n%s\n' "$security_hours" "$sec_out"
elif [ "$sec_rc" -ne 0 ]; then
  echo "ERROR: the security check failed (exit ${sec_rc})" >&2
  exit 2
fi

if [ "$fail_on_pending" -eq 1 ]; then
  section="$(awk '/^## Pending Approval/{f=1;next} /^## /{f=0} f' "${dashboard_file:?}")" \
    || { echo "ERROR: could not read the Dashboard file" >&2; exit 2; }
  # grep exits 1 on no match, which is a valid "nothing pending"; any other code is a failure.
  grep_rc=0
  pending="$(printf '%s\n' "$section" | grep -oE 'approve-branch=[^ ]+ -->.*')" || grep_rc=$?
  if [ "$grep_rc" -gt 1 ]; then
    echo "ERROR: the pending-section search failed (exit ${grep_rc})" >&2
    exit 2
  fi
  if [ -n "$pending" ]; then
    red=1
    printf 'Dashboard has items pending approval:\n%s\n' "$pending"
  fi
fi

exit "$red"
