#!/usr/bin/env bats

load 'lib/confidence-helpers'

@test "helpers: make_log writes one event per line" {
  tmp="$(mktemp)"
  make_log "$tmp" "$(spec_event '[]')"
  run wc -l < "$tmp"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "helpers: spec_event with one AC produces valid JSON" {
  evt="$(spec_event '[{"id":"AC-1","text":"x"}]')"
  echo "$evt" | jq -e '.ac_items[0].id == "AC-1"'
}
