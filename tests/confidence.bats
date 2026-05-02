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
