#!/usr/bin/env bats

load 'lib/confidence-helpers'

setup() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR"
  git init -q
  mkdir -p .git/aw .context/specs
  echo "PROJ-1" > .git/aw/active-spec
  LOG=".context/specs/PROJ-1-confidence.jsonl"
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

# Helper: run hook with a given proposed command.
run_hook() {
  CLAUDE_PROJECT_DIR="$TESTDIR" \
  CLAUDE_TOOL_INPUT="$1" \
    bash "$BATS_TEST_DIRNAME/../hooks/confidence-gate.sh"
}

@test "non-PR commands pass through (exit 0)" {
  make_log "$LOG" "$(spec_event '[]')"
  run run_hook "git status"
  [ "$status" -eq 0 ]
}

@test "GREEN aggregate: gh pr create proceeds (exit 0)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "gh pr create --title x --body y"
  [ "$status" -eq 0 ]
}

@test "RED aggregate: gh pr create blocked (exit 2)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "gh pr create --title x --body y"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RED"* ]]
  [[ "$output" == *"TEST_FAILED"* ]]
}

@test "RED aggregate: glab mr create blocked (exit 2)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "glab mr create --title x"
  [ "$status" -eq 2 ]
}

@test "YELLOW aggregate: pr create proceeds with warning (exit 0)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 0 1 0 100)"
  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YELLOW"* ]]
}

@test "missing active-spec pointer: exit 2 with clear error" {
  rm .git/aw/active-spec
  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [[ "$output" == *"active-spec"* ]]
}

@test "verdict event appended to log on every gate fire" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  run jq -s '[.[] | select(.event=="verdict" and .scope=="aggregate")] | length' "$LOG"
  [ "$output" = "1" ]
}

@test "command filter: gh pr create-fork does NOT trigger gate (false positive guard)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  # Despite the log being RED-worthy, this command should bypass the gate entirely.
  run run_hook "gh pr create-fork"
  [ "$status" -eq 0 ]
}

@test "scorer returns unexpected band: fail closed (exit 2)" {
  STUB_DIR="$(mktemp -d)"
  cat > "$STUB_DIR/confidence.sh" <<'STUB'
#!/usr/bin/env bash
echo '{"band":"WAT","score":0,"gates":[]}'
STUB
  chmod +x "$STUB_DIR/confidence.sh"

  mkdir -p "$TESTDIR/hooks-stub" "$TESTDIR/scripts"
  cp "$BATS_TEST_DIRNAME/../hooks/confidence-gate.sh" "$TESTDIR/hooks-stub/confidence-gate.sh"
  cp "$STUB_DIR/confidence.sh" "$TESTDIR/scripts/confidence.sh"

  make_log "$LOG" "$(spec_event '[{"id":"AC-1","text":"x"}]')"

  run env CLAUDE_PROJECT_DIR="$TESTDIR" \
    CLAUDE_TOOL_INPUT="gh pr create" \
    bash "$TESTDIR/hooks-stub/confidence-gate.sh"
  [ "$status" -eq 2 ]
}

@test "missing log file: exit 2 with actionable error" {
  # active-spec is present (set in setup) but the log file was never created.
  rm -f "$LOG"
  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [[ "$output" == *"log not found"* ]] || [[ "$output" == *"$LOG"* ]]
}

@test "RED with override marker: proceeds, marker deleted, override event logged" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  echo '{"reason":"valid reason text here that is long enough","branch":"x","ts":"2026-05-02T00:00:00Z","user":"u"}' \
    > .git/aw/override-PROJ-1

  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  hook_output="$output"
  [ ! -f ".git/aw/override-PROJ-1" ]

  # stderr message: override was consumed
  [[ "$hook_output" == *"override"* ]]

  # one override event in log
  run jq -s '[.[] | select(.event=="override" and .trigger=="manual")] | length' "$LOG"
  [ "$output" = "1" ]

  # reason passed through
  run jq -rs '[.[] | select(.event=="override")] | .[0].reason' "$LOG"
  [ "$output" = "valid reason text here that is long enough" ]

  # gates captured
  run jq -rs '[.[] | select(.event=="override")] | .[0].gates_bypassed | join(",")' "$LOG"
  [[ "$output" == *"TEST_FAILED"* ]]
}

@test "RED with malformed override marker: blocks (exit 2), marker deleted, no override event" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  # Marker exists but is empty
  : > .git/aw/override-PROJ-1

  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [ ! -f ".git/aw/override-PROJ-1" ]
  [[ "$output" == *"malformed"* ]] || [[ "$output" == *"missing reason"* ]]

  # No override event was logged (only the verdict event)
  run jq -s '[.[] | select(.event=="override")] | length' "$LOG"
  [ "$output" = "0" ]
}

@test "RED with override marker missing .reason field: blocks (exit 2)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  # Valid JSON but no .reason
  echo '{"branch":"x","ts":"2026-05-02T00:00:00Z","user":"u"}' > .git/aw/override-PROJ-1

  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [ ! -f ".git/aw/override-PROJ-1" ]
}

@test "RED with multiple gates + override: gates_bypassed captures all firing gates" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"
  # TEST_FAILED + MUST_FIX both fire
  echo '{"reason":"emergency hotfix delivery, audit follows","branch":"x","ts":"2026-05-02T00:00:00Z","user":"u"}' \
    > .git/aw/override-PROJ-1

  run run_hook "gh pr create"
  [ "$status" -eq 0 ]

  # gates_bypassed contains both
  run jq -rs '[.[] | select(.event=="override")] | .[0].gates_bypassed | join(",")' "$LOG"
  [[ "$output" == *"TEST_FAILED"* ]]
  [[ "$output" == *"MUST_FIX"* ]]
}

@test "skip-tdd active + only NO_AC: auto-bypass, exit 0, trigger=skip-tdd-auto" {
  printf 'TDD bypass active\nReason: docs-only change\nBranch: x\nTime: x\n' > .tdd-skip
  make_log "$LOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 0 ]

  run jq -s '[.[] | select(.event=="override" and .trigger=="skip-tdd-auto")] | length' "$LOG"
  [ "$output" = "1" ]

  # AC-6: the skip-tdd reason is reused as the override reason
  run jq -rs '[.[] | select(.event=="override")] | .[0].reason' "$LOG"
  [ "$output" = "docs-only change" ]
}

@test "skip-tdd active + MUST_FIX: still blocks (exit 2)" {
  printf 'TDD bypass active\nReason: docs-only change\nBranch: x\nTime: x\n' > .tdd-skip
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [[ "$output" == *"behavioral"* ]] || [[ "$output" == *"MUST_FIX"* ]]
}

@test "skip-tdd active + mixed (NO_AC + TEST_FAILED): blocks (exit 2)" {
  printf 'TDD bypass active\nReason: docs-only change\nBranch: x\nTime: x\n' > .tdd-skip
  make_log "$LOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 1 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
}

@test "override is one-shot: second run on same log without marker exits 2" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  echo '{"reason":"valid reason text here that is long enough","branch":"x","ts":"2026-05-02T00:00:00Z","user":"u"}' \
    > .git/aw/override-PROJ-1

  # First run: marker present, override consumed
  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  [ ! -f ".git/aw/override-PROJ-1" ]

  # Second run: no marker, RED still fires, hook blocks
  run run_hook "gh pr create"
  [ "$status" -eq 2 ]

  # Only one override event in the log (not two)
  run jq -s '[.[] | select(.event=="override")] | length' "$LOG"
  [ "$output" = "1" ]

  # Two verdict events though (one per run)
  run jq -s '[.[] | select(.event=="verdict" and .scope=="aggregate")] | length' "$LOG"
  [ "$output" = "2" ]
}

@test "skip-tdd auto-bypass: malformed .tdd-skip (no Reason: line) falls back gracefully" {
  # marker exists but is empty / has no Reason line
  printf 'TDD bypass active\nNo reason field here\n' > .tdd-skip

  make_log "$LOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 0 ]

  # Fallback reason was used; no crash
  run jq -rs '[.[] | select(.event=="override")] | .[0].reason' "$LOG"
  [ "$output" = "skip-tdd active" ]
}
