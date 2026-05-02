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
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.band == "RED"'
  echo "$output" | jq -e '.gates | index("NO_AC") != null'
}

@test "NO_AC: empty ac_items array triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("NO_AC") != null'
}

@test "TEST_FAILED: any qa event with tests_failed > 0 triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 3 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("TEST_FAILED") != null'
}

@test "BUILD_BROKEN: qa event with build_status != ok triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 broken '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("BUILD_BROKEN") != null'
}

@test "MUST_FIX: any review with non-empty must_fix triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("MUST_FIX") != null'
}

@test "AC_NOT_TESTED: AC-2 in spec but not in any ac_items_tested triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("AC_NOT_TESTED") != null'
}

@test "TDD_BYPASSED_NO_REASON: explicit event in log triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)" \
    '{"ts":"2026-05-02T18:00:03Z","event":"tdd_bypassed","reason":""}'

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("TDD_BYPASSED_NO_REASON") != null'
}

@test "AC_NOT_TESTED: handles qa event with missing ac_items_tested field" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    '{"ts":"2026-05-02T18:00:01Z","event":"qa","step":1,"tests_passed":5,"tests_failed":0,"build_status":"ok"}'

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("AC_NOT_TESTED") != null'
}

@test "penalty: should_fix is -5 each" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 2 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 90'
  echo "$output" | jq -e '.penalties.should_fix == -10'
}

@test "penalty: suggestion is -1 each" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 3 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 97'
  echo "$output" | jq -e '.penalties.suggestion == -3'
}

@test "penalty: loops_used 2 is -5, loops_used 3 is -15 cumulative" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 5 0 ok '["AC-2"]')" \
    "$(review_event 1 0 0 0 2 0 100)" \
    "$(review_event 2 0 0 0 3 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 80'
  echo "$output" | jq -e '.penalties.loops == -20'
}

@test "penalty: tech_debt_deferrals is -3 each" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 2 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 94'
}

@test "penalty: diff > 400 lines is -5" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 500)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 95'
  echo "$output" | jq -e '.penalties.diff == -5'
}

@test "penalty: diff > 1000 lines is -15 (replaces -5)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 1500)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 85'
  echo "$output" | jq -e '.penalties.diff == -15'
}

@test "score floor is 0, never negative" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 30 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 0'
}

@test "penalty: ac_coverage cap is -20 (does not exceed) when many ACs missing" {
  # 11 ACs in spec; 0 covered by qa. Without cap, penalty would be -22.
  spec_acs='[
    {"id":"AC-1","text":"x"},{"id":"AC-2","text":"x"},{"id":"AC-3","text":"x"},
    {"id":"AC-4","text":"x"},{"id":"AC-5","text":"x"},{"id":"AC-6","text":"x"},
    {"id":"AC-7","text":"x"},{"id":"AC-8","text":"x"},{"id":"AC-9","text":"x"},
    {"id":"AC-10","text":"x"},{"id":"AC-11","text":"x"}
  ]'
  make_log "$TMPLOG" \
    "$(spec_event "$spec_acs")" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.penalties.ac_coverage == -20'
  # Score: 100 + (-20) = 80 (band would be RED via AC_NOT_TESTED gate, but score is still 80).
  echo "$output" | jq -e '.score == 80'
}

@test "band: score 80 is GREEN (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 4 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 80'
  echo "$output" | jq -e '.band == "GREEN"'
}

@test "band: score 79 is YELLOW (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 4 1 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 79'
  echo "$output" | jq -e '.band == "YELLOW"'
}

@test "band: score 60 is YELLOW (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 60'
  echo "$output" | jq -e '.band == "YELLOW"'
}

@test "band: score 59 is RED (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 1 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 59'
  echo "$output" | jq -e '.band == "RED"'
}

@test "band: any hard gate forces RED regardless of score" {
  make_log "$TMPLOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  # score before gate would be 100, but NO_AC fires
  echo "$output" | jq -e '.band == "RED"'
}

@test "scope=step: only events for that step are considered" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 5 0 ok '["AC-2"]')" \
    "$(review_event 1 0 0 0 1 0 100)" \
    "$(review_event 2 0 4 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 100'

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 80'
}

@test "scope=aggregate (default): all events considered" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 5 0 ok '["AC-2"]')" \
    "$(review_event 1 0 2 0 1 0 100)" \
    "$(review_event 2 0 2 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  # 4 should-fix total = -20 = score 80
  echo "$output" | jq -e '.score == 80'
}

@test "scope=step: NO_AC gate does NOT fire even with empty spec" {
  make_log "$TMPLOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("NO_AC") == null'
  echo "$output" | jq -e '.band != "RED"'
}

@test "scope=step: AC_NOT_TESTED does NOT fire when spec has more ACs than this step covers" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("AC_NOT_TESTED") == null'
  echo "$output" | jq -e '.score == 100'
}

@test "scope=step: TEST_FAILED gate STILL fires (behavioral, scope-independent)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("TEST_FAILED") != null'
  echo "$output" | jq -e '.band == "RED"'
}

@test "scope=step: MUST_FIX gate STILL fires (behavioral, scope-independent)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("MUST_FIX") != null'
  echo "$output" | jq -e '.band == "RED"'
}

@test "scope=step: BUILD_BROKEN gate STILL fires (behavioral, scope-independent)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 broken '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("BUILD_BROKEN") != null'
  echo "$output" | jq -e '.band == "RED"'
}

@test "scope=step: TDD_BYPASSED_NO_REASON gate STILL fires (behavioral, scope-independent)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)" \
    '{"ts":"2026-05-02T18:00:03Z","event":"tdd_bypassed","reason":"","step":1}'

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gates | index("TDD_BYPASSED_NO_REASON") != null'
  echo "$output" | jq -e '.band == "RED"'
}
