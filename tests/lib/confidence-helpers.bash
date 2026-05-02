#!/usr/bin/env bash
# Helpers for confidence-gate tests.

# make_log <path> <events...>
# Each event arg is a JSON string written as one line.
make_log() {
  local path="$1"; shift
  : > "$path"
  for evt in "$@"; do
    printf '%s\n' "$evt" >> "$path"
  done
}

# Standard event builders. ts is fixed for deterministic tests.
spec_event() {
  local ac_json="${1:-[]}"
  printf '{"ts":"2026-05-02T18:00:00Z","event":"spec","spec_path":"x","ac_items":%s}' "$ac_json"
}

qa_event() {
  local step="$1" passed="$2" failed="$3" build="${4:-ok}" tested="${5:-[]}"
  printf '{"ts":"2026-05-02T18:00:01Z","event":"qa","step":%s,"tests_passed":%s,"tests_failed":%s,"build_status":"%s","ac_items_tested":%s}' \
    "$step" "$passed" "$failed" "$build" "$tested"
}

review_event() {
  local step="$1" must="${2:-0}" should="${3:-0}" sugg="${4:-0}" loops="${5:-1}" td="${6:-0}" diff="${7:-100}"
  local must_arr should_arr sugg_arr td_arr
  must_arr=$(  [ "$must"   -eq 0 ] && echo '[]' || seq 1 "$must"   | jq -Rcn '[inputs | {file:"f.go",line:1,msg:"x"}]')
  should_arr=$([ "$should" -eq 0 ] && echo '[]' || seq 1 "$should" | jq -Rcn '[inputs | {file:"f.go",line:1,msg:"x"}]')
  sugg_arr=$(  [ "$sugg"   -eq 0 ] && echo '[]' || seq 1 "$sugg"   | jq -Rcn '[inputs | {file:"f.go",line:1,msg:"x"}]')
  td_arr=$(    [ "$td"     -eq 0 ] && echo '[]' || seq 1 "$td"     | jq -Rcn '[inputs | {item:"x"}]')
  printf '{"ts":"2026-05-02T18:00:02Z","event":"review","step":%s,"must_fix":%s,"should_fix":%s,"suggestion":%s,"loops_used":%s,"tech_debt_deferrals":%s,"diff_lines":%s}' \
    "$step" "$must_arr" "$should_arr" "$sugg_arr" "$loops" "$td_arr" "$diff"
}
