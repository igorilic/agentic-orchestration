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

  CLAUDE_PROJECT_DIR="$TESTDIR" \
  CLAUDE_TOOL_INPUT="gh pr create" \
    bash "$TESTDIR/hooks-stub/confidence-gate.sh"
  status=$?
  [ "$status" -eq 2 ]
}

@test "missing log file: exit 2 with actionable error" {
  # active-spec is present (set in setup) but the log file was never created.
  rm -f "$LOG"
  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [[ "$output" == *"log not found"* ]] || [[ "$output" == *"$LOG"* ]]
}
