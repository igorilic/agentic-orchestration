#!/usr/bin/env bats

load 'lib/confidence-helpers'

setup() {
  TMPLOG="$(mktemp)"
}

teardown() {
  rm -f "$TMPLOG"
}

@test "all-green log: score 100, band GREEN, no gates" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 100'
  echo "$output" | jq -e '.band == "GREEN"'
  echo "$output" | jq -e '.gates == []'
}

@test "output JSON has all required fields" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("score") and has("band") and has("gates") and has("penalties") and has("verdict_text")'
}

@test "empty log file: does not crash, returns valid JSON" {
  : > "$TMPLOG"  # zero-byte file
  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("score") and has("band") and has("gates")'
}

@test "NO_AC: missing spec event triggers RED" {
  make_log "$TMPLOG" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.band == "RED"'
  echo "$output" | jq -e '.gates | index("NO_AC") != null'
}

@test "NO_AC: empty ac_items array triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("NO_AC") != null'
}

@test "TEST_FAILED: any qa event with tests_failed > 0 triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 3 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("TEST_FAILED") != null'
}

@test "BUILD_BROKEN: qa event with build_status != ok triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 broken '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("BUILD_BROKEN") != null'
}

@test "MUST_FIX: any review with non-empty must_fix triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("MUST_FIX") != null'
}

@test "AC_NOT_TESTED: AC-2 in spec but not in any ac_items_tested triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("AC_NOT_TESTED") != null'
}

@test "TDD_BYPASSED_NO_REASON: explicit event in log triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)" \
    '{"ts":"2026-05-02T18:00:03Z","event":"tdd_bypassed","reason":""}'

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("TDD_BYPASSED_NO_REASON") != null'
}
