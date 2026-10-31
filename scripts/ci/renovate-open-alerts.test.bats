#!/usr/bin/env bats
# Bats tests for renovate-open-alerts.sh
# Run: bats scripts/ci/renovate-open-alerts.test.bats
#
# Input is the JSON array from `gh api repos/{owner}/{repo}/dependabot/alerts
# ?state=open`, fed on stdin. NOW is fixed (2026-10-22T12:00:00Z) so ages are
# deterministic.

SCRIPT="scripts/ci/renovate-open-alerts.sh"
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

# alert <number> <created_at> <patched-or-null> [name]: one alert object.
alert() {
  local patched="null"
  if [ "$3" != "null" ]; then
    patched="{\"identifier\":\"$3\"}"
  fi
  printf '{"number":%s,"created_at":"%s","html_url":"https://github.com/o/r/security/dependabot/%s","dependency":{"package":{"name":"%s"},"manifest_path":"package-lock.json","scope":"development"},"security_advisory":{"severity":"high","ghsa_id":"GHSA-aaaa-bbbb-cccc"},"security_vulnerability":{"first_patched_version":%s}}' \
    "$1" "$2" "$1" "${4:-re2js}" "$patched"
}

@test "empty array exits 0 with no output" {
  run_script '[]' --hours 48
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "old patched alert is flagged with all fields" {
  run_script "[$(alert 405 2026-10-10T12:00:00Z 2.8.7)]" --hours 48
  [ "$status" -eq 1 ]
  [[ "$output" == "- #405 re2js (high, package-lock.json, development) patched in 2.8.7, open since 2026-10-10T12:00:00Z, GHSA-aaaa-bbbb-cccc https://github.com/o/r/security/dependabot/405" ]]
}

@test "young patched alert is not flagged" {
  run_script "[$(alert 406 2026-10-21T12:00:00Z 2.8.7)]" --hours 48
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an alert exactly --hours old is not flagged" {
  run_script "[$(alert 407 2026-10-20T12:00:00Z 2.8.7)]" --hours 48
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "old alert without a patch is not flagged" {
  run_script "[$(alert 408 2026-09-01T12:00:00Z null)]" --hours 48
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mixed set flags only old patched alerts, oldest first" {
  local json
  json="[$(alert 3 2026-10-05T12:00:00Z 1.2.3 b),$(alert 4 2026-10-21T12:00:00Z 1.0.0 young),$(alert 5 2026-09-02T12:00:00Z null nopatch),$(alert 6 2026-09-02T12:00:00Z 9.9.9 oldest)]"
  run_script "$json" --hours 48
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "- #6 oldest "* ]]
  [[ "${lines[1]}" == "- #3 b "* ]]
}

@test "hours override is honored" {
  local json="[$(alert 9 2026-10-22T06:00:00Z 1.0.1)]"
  run_script "$json" --hours 48
  [ "$status" -eq 0 ]
  run_script "$json" --hours 5
  [ "$status" -eq 1 ]
}

@test "invalid JSON exits 2" {
  run_script 'not json {' --hours 48
  [ "$status" -eq 2 ]
}

@test "empty stdin exits 2" {
  run_script '' --hours 48
  [ "$status" -eq 2 ]
}

@test "a JSON object instead of an array exits 2" {
  run_script '{"number":1}' --hours 48
  [ "$status" -eq 2 ]
}

@test "missing --hours exits 2" {
  run_script '[]'
  [ "$status" -eq 2 ]
}

@test "non-integer --hours exits 2" {
  run_script '[]' --hours abc
  [ "$status" -eq 2 ]
}

@test "zero --hours flags every old patched alert" {
  run_script "[$(alert 11 2026-10-10T12:00:00Z 2.8.7)]" --hours 0
  [ "$status" -eq 1 ]
  [[ "$output" == "- #11 re2js "* ]]
}

@test "negative --hours exits 2" {
  run_script '[]' --hours -1
  [ "$status" -eq 2 ]
}

@test "a non-object element exits 2" {
  run_script '[1]' --hours 48
  [ "$status" -eq 2 ]
}

@test "an alert without security_vulnerability is not flagged" {
  run_script '[{"number":12,"created_at":"2026-09-01T12:00:00Z"}]' --hours 48
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an old alert whose first_patched_version has a null identifier is not flagged" {
  run_script '[{"number":14,"created_at":"2026-09-01T12:00:00Z","security_vulnerability":{"first_patched_version":{"identifier":null}}}]' --hours 48
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unparseable created_at on an unpatched alert exits 2" {
  run_script "[$(alert 15 yesterday null)]" --hours 48
  [ "$status" -eq 2 ]
}

@test "null scope and missing severity print as unknown" {
  run_script '[{"number":13,"created_at":"2026-09-01T12:00:00Z","html_url":"u","dependency":{"package":{"name":"p"},"manifest_path":"m","scope":null},"security_advisory":{"ghsa_id":"G"},"security_vulnerability":{"first_patched_version":{"identifier":"1.0.0"}}}]' --hours 48
  [ "$status" -eq 1 ]
  [[ "$output" == "- #13 p (unknown, m, unknown) patched in 1.0.0, open since 2026-09-01T12:00:00Z, G u" ]]
}

@test "an element missing number exits 2" {
  run_script '[{"created_at":"2026-09-01T12:00:00Z"}]' --hours 48
  [ "$status" -eq 2 ]
}

@test "an element missing created_at exits 2" {
  run_script '[{"number":1}]' --hours 48
  [ "$status" -eq 2 ]
}

@test "unparseable created_at exits 2" {
  run_script "[$(alert 10 yesterday 1.0.0)]" --hours 48
  [ "$status" -eq 2 ]
}

@test "invalid --now exits 2" {
  run_script '[]' --hours 48 --now abc
  [ "$status" -eq 2 ]
}

@test "bad option exits 2" {
  run_script '[]' --hours 48 --bogus
  [ "$status" -eq 2 ]
}

@test "help exits 0" {
  run bash "$REPO_ROOT/$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}
