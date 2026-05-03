#!/usr/bin/env bats

load 'lib/confidence-helpers'

@test "helpers: make_log writes one event per line" {
  tmp="$(mktemp)"
  make_log "$tmp" "$(spec_event '[]')"
  run wc -l < "$tmp"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
  [ "$(jq -r '.event' < "$tmp")" = "spec" ]
  rm -f "$tmp"
}

@test "helpers: spec_event with one AC produces valid JSON" {
  evt="$(spec_event '[{"id":"AC-1","text":"x"}]')"
  echo "$evt" | jq -e '.ac_items[0].id == "AC-1"'
}

@test "helpers: review_event with zero counts produces empty arrays" {
  evt="$(review_event 1 0 0 0 1 0 100)"
  [ "$(echo "$evt" | jq '.must_fix | length')" = "0" ]
  [ "$(echo "$evt" | jq '.should_fix | length')" = "0" ]
  [ "$(echo "$evt" | jq '.suggestion | length')" = "0" ]
  [ "$(echo "$evt" | jq '.tech_debt_deferrals | length')" = "0" ]
}

@test "helpers: review_event output is single-line JSON (JSONL-safe)" {
  evt="$(review_event 1 2 3 1 2 1 250)"
  # Single line means: no embedded newlines.
  line_count="$(echo "$evt" | wc -l | tr -d ' ')"
  [ "$line_count" = "1" ]
  [ "$(echo "$evt" | jq '.must_fix | length')" = "2" ]
  [ "$(echo "$evt" | jq '.should_fix | length')" = "3" ]
}
