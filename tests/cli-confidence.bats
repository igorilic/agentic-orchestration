#!/usr/bin/env bats

load 'lib/confidence-helpers'

SCRIPTS_DIR="$BATS_TEST_DIRNAME/../scripts"

setup() {
  TESTDIR="$(mktemp -d "$BATS_TMPDIR/tmp.XXXXXX")"
  cd "$TESTDIR"
  git init -q
  mkdir -p .anw/specs .git/aw
  CLI_HELPER="$BATS_TEST_DIRNAME/../scripts/confidence-cli.sh"
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

# ---------------------------------------------------------------------------
# write_active_spec
# ---------------------------------------------------------------------------

@test "write_active_spec creates .git/aw/active-spec with correct content" {
  source "$CLI_HELPER"
  write_active_spec "PROJ-42"
  [ -f ".git/aw/active-spec" ]
  [ "$(cat .git/aw/active-spec)" = "PROJ-42" ]
}

@test "write_active_spec overwrites pre-existing active-spec" {
  echo "OLD-1" > .git/aw/active-spec
  source "$CLI_HELPER"
  write_active_spec "NEW-99"
  [ "$(cat .git/aw/active-spec)" = "NEW-99" ]
}

@test "write_active_spec creates .git/aw directory if missing" {
  rm -rf .git/aw
  source "$CLI_HELPER"
  write_active_spec "PROJ-1"
  [ -f ".git/aw/active-spec" ]
}

# Fix 3: write_active_spec validates spec id pattern
@test "write_active_spec: rejects spec id with path traversal characters" {
  source "$CLI_HELPER"
  run bash -c "source $CLI_HELPER && write_active_spec '../../etc/passwd'"
  [ "$status" -ne 0 ]
}

@test "write_active_spec: rejects spec id with slashes" {
  source "$CLI_HELPER"
  run bash -c "source $CLI_HELPER && write_active_spec 'PROJ/123'"
  [ "$status" -ne 0 ]
}

@test "write_active_spec: accepts valid alphanumeric-dot-dash-underscore id" {
  source "$CLI_HELPER"
  run bash -c "source $CLI_HELPER && write_active_spec 'PROJ-42.feature_1'"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# build_pr_body
# ---------------------------------------------------------------------------

@test "build_pr_body injects ## Confidence section into base body" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "Initial body")"
  [[ "$result" == *"## Confidence"* ]]
}

@test "build_pr_body shows GREEN for clean log" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "Initial body")"
  [[ "$result" == *"GREEN"* ]]
}

@test "build_pr_body shows RED with failing gate names in body" {
  source "$CLI_HELPER"
  # No spec event → NO_AC gate fires → RED
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "Initial body")"
  [[ "$result" == *"RED"* ]]
}

@test "build_pr_body preserves the base body text" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "My PR summary here")"
  [[ "$result" == *"My PR summary here"* ]]
}

@test "build_pr_body does not mutate the log file" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  before_lines=$(wc -l < .anw/specs/PROJ-1-confidence.jsonl)
  build_pr_body "PROJ-1" "body" >/dev/null
  after_lines=$(wc -l < .anw/specs/PROJ-1-confidence.jsonl)
  [ "$before_lines" -eq "$after_lines" ]
}

# ---------------------------------------------------------------------------
# emit_step_verdict
# ---------------------------------------------------------------------------

@test "emit_step_verdict appends a step-scope verdict event to the log" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  before_lines=$(wc -l < .anw/specs/PROJ-1-confidence.jsonl)
  # Feed 'go' to skip the interactive prompt (band will be GREEN, no prompt)
  emit_step_verdict "PROJ-1" 1 >/dev/null
  after_lines=$(wc -l < .anw/specs/PROJ-1-confidence.jsonl)
  [ "$after_lines" -gt "$before_lines" ]
}

@test "emit_step_verdict appended event has scope=step and correct step number" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  emit_step_verdict "PROJ-1" 1 >/dev/null
  # Last line of the log should be the verdict event
  last="$(tail -1 .anw/specs/PROJ-1-confidence.jsonl)"
  echo "$last" | jq -e '.event == "verdict"'
  echo "$last" | jq -e '.scope == "step"'
  echo "$last" | jq -e '.step == 1'
}

@test "emit_step_verdict prints band and score to stdout" {
  source "$CLI_HELPER"
  make_log ".anw/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(emit_step_verdict "PROJ-1" 1)"
  [[ "$result" == *"confidence"* ]]
  [[ "$result" == *"GREEN"* ]]
}

# Fix 1: emit_step_verdict must not prompt — purely informational
@test "emit_step_verdict: does not prompt — runs to completion non-interactively" {
  # No stdin redirection; if the function tried to prompt, the test would hang.
  source "$CLI_HELPER"

  mkdir -p .anw/specs
  make_log ".anw/specs/SMOKE-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 5 0 1 0 100)"

  local testdir="$TESTDIR"
  run timeout 3 bash -c "cd '$testdir' && source '$CLI_HELPER' && emit_step_verdict SMOKE 1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YELLOW"* ]]
}

# Fix 5: build_pr_body includes failing gate names when RED
@test "build_pr_body: includes failing gate names when RED" {
  source "$CLI_HELPER"
  mkdir -p .anw/specs
  make_log ".anw/specs/X-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body X "Initial body")"
  [[ "$result" == *"## Confidence"* ]]
  [[ "$result" == *"RED"* ]]
  [[ "$result" == *"TEST_FAILED"* ]]
}

@test "build_pr_body: omits failing-gates line when GREEN" {
  source "$CLI_HELPER"
  mkdir -p .anw/specs
  make_log ".anw/specs/X-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body X "Initial body")"
  [[ "$result" == *"GREEN"* ]]
  [[ "$result" != *"Failing gates"* ]]
}
