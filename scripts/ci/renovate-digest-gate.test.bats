#!/usr/bin/env bats
# Bats tests for renovate-digest-gate.sh. Run: bats scripts/ci/renovate-digest-gate.test.bats
# NOW is fixed (2026-10-22T12:00:00Z). Positive control: the exit code flips 0 -> 1 per condition.

SCRIPT="scripts/ci/renovate-digest-gate.sh"
NOW=1792670400
FRESH='{"number":1,"title":"update a","createdAt":"2026-10-21T12:00:00Z","mergeStateStatus":"CLEAN","statusCheckRollup":[]}'
OLD='{"number":2,"title":"update b","createdAt":"2026-10-10T12:00:00Z","mergeStateStatus":"CLEAN","statusCheckRollup":[]}'
SEC='{"number":3,"title":"update c [security]","createdAt":"2026-10-19T12:00:00Z","mergeStateStatus":"CLEAN","statusCheckRollup":[]}'

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export REPO_ROOT
}

# run_gate <json> [args...]
run_gate() {
  local json="$1"
  shift
  run bash -c 'printf "%s" "$1" | bash "$2" --now "$3" "${@:4}"' _ "$json" "$REPO_ROOT/$SCRIPT" "$NOW" "$@"
}

@test "only a fresh PR: exit 0" {
  run_gate "[$FRESH]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty list: exit 0" {
  run_gate '[]'
  [ "$status" -eq 0 ]
}

@test "a PR older than stale days flips to exit 1" {
  run_gate "[$FRESH,$OLD]"
  [ "$status" -eq 1 ]
  [[ "$output" == *"#2 update b"* ]]
  [[ "$output" != *"#1 update a"* ]]
}

@test "stale days override is honoured" {
  run_gate "[$OLD]" --stale-days 30
  [ "$status" -eq 0 ]
}

@test "a security PR over the hours flips to exit 1 while fresh by stale days" {
  run_gate "[$SEC]"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Security fixes open over 48 hours"* ]]
  run_gate "[$SEC]" --security-hours 100
  [ "$status" -eq 0 ]
}

@test "pending section is ignored without fail-on-pending" {
  printf '## Pending Approval\n\n - [ ] <!-- approve-branch=renovate/x -->update x\n' > "$BATS_TEST_TMPDIR/d.md"
  run_gate "[$FRESH]" --dashboard-file "$BATS_TEST_TMPDIR/d.md"
  [ "$status" -eq 0 ]
}

@test "non-empty pending section flips to exit 1 with fail-on-pending" {
  printf '## Pending Approval\n\n - [ ] <!-- approve-branch=renovate/x -->update x\n\n## Open\n' > "$BATS_TEST_TMPDIR/d.md"
  run_gate "[$FRESH]" --fail-on-pending --dashboard-file "$BATS_TEST_TMPDIR/d.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"update x"* ]]
}

@test "empty pending section stays exit 0 with fail-on-pending" {
  printf '## Pending Approval\n\n## Open\n - [ ] <!-- approve-branch=renovate/y -->not pending\n' > "$BATS_TEST_TMPDIR/d.md"
  run_gate "[$FRESH]" --fail-on-pending --dashboard-file "$BATS_TEST_TMPDIR/d.md"
  [ "$status" -eq 0 ]
}

@test "fail-on-pending without a dashboard file exits 2" {
  run_gate "[$FRESH]" --fail-on-pending
  [ "$status" -eq 2 ]
}

@test "bad input and bad options exit 2" {
  run_gate 'not json'
  [ "$status" -eq 2 ]
  run_gate '[]' --stale-days abc
  [ "$status" -eq 2 ]
  run_gate '[]' --bogus
  [ "$status" -eq 2 ]
}
