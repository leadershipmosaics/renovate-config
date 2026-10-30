#!/usr/bin/env bats
# Bats tests for renovate-stale-security.sh
# Run: bats scripts/ci/renovate-stale-security.test.bats
#
# Input is the JSON array from `gh pr list --author app/renovate --json
# number,title,createdAt,mergeStateStatus,statusCheckRollup`, fed on stdin.
# NOW is fixed (2026-10-22T12:00:00Z) so ages are deterministic.

SCRIPT="scripts/ci/renovate-stale-security.sh"
NOW=1792670400

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export REPO_ROOT
}

# run_script <json> [args...]: feed json on stdin, fixed clock.
run_script() {
  local json="$1"
  shift
  run bash -c 'printf "%s" "$1" | bash "$2" --now "$3" "${@:4}"' _ "$json" "$REPO_ROOT/$SCRIPT" "$NOW" "$@"
}

@test "old security PR with a red CheckRun is flagged with the red name" {
  run_script '[{"number":10,"title":"fix(deps): update dependency vitest [security]","createdAt":"2026-10-10T12:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","conclusion":"FAILURE"},{"__typename":"CheckRun","name":"lint","conclusion":"SUCCESS"}]}]'
  [ "$status" -eq 1 ]
  [[ "$output" == "- #10 fix(deps): update dependency vitest [security]: open 12 days, red: ci" ]]
}

@test "old security PR with a red StatusContext shows the context" {
  run_script '[{"number":11,"title":"update x [security]","createdAt":"2026-10-20T11:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"StatusContext","context":"Vercel – marketing","state":"FAILURE"},{"__typename":"StatusContext","context":"Vercel – leader","state":"SUCCESS"}]}]'
  [ "$status" -eq 1 ]
  [[ "$output" == "- #11 update x [security]: open 2 days, red: Vercel – marketing" ]]
}

@test "several red entries are comma separated" {
  run_script '[{"number":12,"title":"update y [security]","createdAt":"2026-10-01T12:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"CheckRun","name":"a","conclusion":"TIMED_OUT"},{"__typename":"StatusContext","context":"b","state":"ERROR"},{"__typename":"CheckRun","name":"c","conclusion":"CANCELLED"}]}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"red: a, b, c" ]]
}

@test "old green security PR is flagged as not merged with its merge state" {
  run_script '[{"number":13,"title":"update z [security]","createdAt":"2026-09-09T12:00:00Z","mergeStateStatus":"CLEAN","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","conclusion":"SUCCESS"}]}]'
  [ "$status" -eq 1 ]
  [[ "$output" == "- #13 update z [security]: open 43 days, not merged, CLEAN" ]]
}

@test "young red security PR is not flagged" {
  run_script '[{"number":14,"title":"update q [security]","createdAt":"2026-10-21T12:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","conclusion":"FAILURE"}]}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "old red PR without the security marker is not flagged" {
  run_script '[{"number":15,"title":"chore(deps): update npm non-major updates","createdAt":"2026-09-01T12:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","conclusion":"FAILURE"}]}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty array exits 0 with no output" {
  run_script '[]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing statusCheckRollup is treated as not red" {
  run_script '[{"number":16,"title":"w [security]","createdAt":"2026-09-01T12:00:00Z","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not merged, UNKNOWN" ]]
}

@test "malformed JSON exits 2" {
  run_script 'not json {'
  [ "$status" -eq 2 ]
}

@test "non-array JSON exits 2" {
  run_script '{"number":1}'
  [ "$status" -eq 2 ]
}

@test "empty stdin exits 2" {
  run_script ''
  [ "$status" -eq 2 ]
}

@test "hours override is honored" {
  local json='[{"number":17,"title":"v [security]","createdAt":"2026-10-22T06:00:00Z","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  run_script "$json"
  [ "$status" -eq 0 ]
  run_script "$json" --hours 5
  [ "$status" -eq 1 ]
  [[ "$output" == "- #17 v [security]: open 0 days, not merged, CLEAN" ]]
}

@test "bad option exits 2" {
  run_script '[]' --bogus
  [ "$status" -eq 2 ]
  run_script '[]' --hours abc
  [ "$status" -eq 2 ]
}

@test "help exits 0" {
  run bash "$REPO_ROOT/$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "in-progress CheckRun with null conclusion is not red" {
  run_script '[{"number":18,"title":"u [security]","createdAt":"2026-09-01T12:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":null}]}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not merged, BLOCKED" ]]
}

@test "ACTION_REQUIRED and STARTUP_FAILURE conclusions are red" {
  run_script '[{"number":19,"title":"t [security]","createdAt":"2026-09-01T12:00:00Z","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"__typename":"CheckRun","name":"p","conclusion":"ACTION_REQUIRED"},{"__typename":"CheckRun","name":"q","conclusion":"STARTUP_FAILURE"}]}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"red: p, q" ]]
}

@test "a PR exactly --hours old is not flagged" {
  run_script '[{"number":20,"title":"s [security]","createdAt":"2026-10-20T12:00:00Z","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "invalid --now exits 2" {
  run_script '[]' --now abc
  [ "$status" -eq 2 ]
}

@test "unparseable createdAt exits 2" {
  run_script '[{"number":21,"title":"r [security]","createdAt":"yesterday","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$status" -eq 2 ]
}
