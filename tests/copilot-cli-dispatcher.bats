#!/usr/bin/env bats
# Tests for COP-2: copilot-cli-dispatcher.sh behaviour
# Steps 4, 5, 8, 9, 10: skeleton + gates.

load 'lib/copilot-payload-helpers'
load 'lib/confidence-helpers'

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-dispatcher-XXXXXX)"
  # Initialize git repo so git-based gate logic works
  git -C "$SANDBOX" init -q
  git -C "$SANDBOX" config user.email "test@example.com"
  git -C "$SANDBOX" config user.name "Test"
  # Install the dispatcher into the sandbox
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  DISPATCHER="$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
  # Standard directories for confidence gate
  mkdir -p "$SANDBOX/.git/aw" "$SANDBOX/.context/specs"
  LOG="$SANDBOX/.context/specs/PROJ-1-confidence.jsonl"
}

teardown() {
  rm -rf "$SANDBOX"
}

# Helper: pipe a payload JSON string to the dispatcher via temp file.
# Uses a temp file to avoid all shell quoting issues with JSON.
run_dispatcher() {
  local payload="$1"
  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  run bash -c "cat '$tmpfile' | bash '$DISPATCHER'"
  rm -f "$tmpfile"
}

# Helper: pipe a payload and extra env vars to the dispatcher.
run_dispatcher_env() {
  local payload="$1"
  local env_prefix="$2"
  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  run bash -c "$env_prefix cat '$tmpfile' | bash '$DISPATCHER'"
  rm -f "$tmpfile"
}

# ---------------------------------------------------------------------------
# Step 4: trap + filter skeleton
# ---------------------------------------------------------------------------

@test "dispatcher: non-bash toolName (read_file) -> permissionDecision allow" {
  local payload
  payload="$(mk_payload "read_file" "cat /etc/hosts" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "dispatcher: bash toolName with any command -> permissionDecision allow (skeleton, no gates)" {
  # SANDBOX must be a git repo for cwd resolution to succeed
  git -C "$SANDBOX" init -q
  local payload
  payload="$(mk_payload "bash" "git status" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "dispatcher: empty stdin (no JSON) -> permissionDecision deny with crashed reason" {
  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '' > "$tmpfile"
  run bash -c "cat '$tmpfile' | bash '$DISPATCHER' 2>/dev/null"
  rm -f "$tmpfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("crash")' >/dev/null
}

# ---------------------------------------------------------------------------
# Step 5: cwd resolution
# ---------------------------------------------------------------------------

@test "dispatcher: payload cwd is sandbox subdir -> resolves to git toplevel (ANW_DEBUG trace)" {
  # Make SANDBOX a git repo so git rev-parse works
  git -C "$SANDBOX" init -q
  mkdir -p "$SANDBOX/subdir"

  # Resolve the physical path (macOS /tmp -> /private/tmp symlink)
  local real_sandbox
  real_sandbox="$(cd "$SANDBOX" && pwd -P)"

  local payload
  payload="$(mk_payload "bash" "git status" "$SANDBOX/subdir")"

  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  # env var must be set on the dispatcher process itself, not on cat.
  # Use input redirection to avoid pipe breaking the env assignment.
  run bash -c "ANW_DEBUG=1 bash '$DISPATCHER' < '$tmpfile' 2>&1"
  rm -f "$tmpfile"
  # Dispatcher must succeed and trace must include the resolved sandbox root
  [ "$status" -eq 0 ]
  [[ "$output" == *"$real_sandbox"* ]]
}

@test "dispatcher: payload missing cwd and not in git repo -> deny with project dir reason" {
  # Build a payload without cwd field
  local payload
  payload='{"toolName":"bash","toolArgs":"{\"command\":\"git status\"}","timestamp":1714694400000}'

  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  # cd /tmp to be outside any git repo; suppress stderr to keep output as clean JSON
  run bash -c "cd /tmp && cat '$tmpfile' | bash '$DISPATCHER' 2>/dev/null"
  rm -f "$tmpfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("project dir")' >/dev/null
}

@test "dispatcher: payload cwd inside git repo -> allow (cwd resolves successfully)" {
  local payload
  payload="$(mk_payload "bash" "git status" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

# ---------------------------------------------------------------------------
# Step 8: TDD gate port
# ---------------------------------------------------------------------------

@test "tdd-gate: git commit with no test files staged -> deny with TDD GATE and Options" {
  # Stage a non-test file
  touch "$SANDBOX/main.go"
  git -C "$SANDBOX" add main.go
  local payload
  payload="$(mk_payload "bash" "git commit -m x" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("TDD")' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("Options")' >/dev/null
}

@test "tdd-gate: git commit with .tdd-skip present -> allow" {
  touch "$SANDBOX/main.go"
  git -C "$SANDBOX" add main.go
  printf 'TDD bypass active\nReason: docs-only\nBranch: main\nTime: 2026-05-02T00:00:00Z\n' \
    > "$SANDBOX/.tdd-skip"
  local payload
  payload="$(mk_payload "bash" "git commit -m x" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "tdd-gate: git commit --amend -> allow regardless" {
  local payload
  payload="$(mk_payload "bash" "git commit --amend --no-edit" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "tdd-gate: git commit with staged test file (foo_test.go) -> allow" {
  touch "$SANDBOX/foo_test.go"
  git -C "$SANDBOX" add foo_test.go
  local payload
  payload="$(mk_payload "bash" "git commit -m x" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "tdd-gate: git commit with all staged paths under spikes/ -> allow" {
  mkdir -p "$SANDBOX/spikes"
  touch "$SANDBOX/spikes/prototype.go"
  git -C "$SANDBOX" add spikes/prototype.go
  local payload
  payload="$(mk_payload "bash" "git commit -m x" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "tdd-gate: git status (not a commit) -> allow" {
  local payload
  payload="$(mk_payload "bash" "git status" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

# ---------------------------------------------------------------------------
# Step 9: Confidence gate happy paths
# ---------------------------------------------------------------------------

@test "confidence-gate: GREEN aggregate + gh pr create -> allow; verdict event appended" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  local payload
  payload="$(mk_payload "bash" "gh pr create --title x --body y" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
  # verdict event appended
  run jq -s '[.[] | select(.event=="verdict" and .scope=="aggregate")] | length' "$LOG"
  [ "$output" = "1" ]
}

@test "confidence-gate: RED aggregate (TEST_FAILED) + no bypass + gh pr create -> deny with RED and TEST_FAILED; verdict appended" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  local payload
  payload="$(mk_payload "bash" "gh pr create --title x --body y" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("RED")' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("TEST_FAILED")' >/dev/null
  # verdict event appended
  run jq -s '[.[] | select(.event=="verdict" and .scope=="aggregate")] | length' "$LOG"
  [ "$output" = "1" ]
}

@test "confidence-gate: YELLOW aggregate + gh pr create -> allow with stderr warning" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 0 1 0 100)"
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  run bash -c "bash '$DISPATCHER' < '$tmpfile' 2>&1"
  rm -f "$tmpfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null || \
    { echo "$output" | grep -q '"allow"'; }
  [[ "$output" == *"YELLOW"* ]]
}

@test "confidence-gate: missing active-spec pointer -> deny" {
  # No .git/aw/active-spec written
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("active-spec")' >/dev/null
}

@test "confidence-gate: glab mr create with RED -> deny (parity)" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  local payload
  payload="$(mk_payload "bash" "glab mr create --title x" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
}

@test "confidence-gate: git push (not a PR command) -> allow without scorer invocation" {
  # No active-spec or log: if scorer were invoked this would deny
  local payload
  payload="$(mk_payload "bash" "git push origin main" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

# ---------------------------------------------------------------------------
# Step 10: Confidence gate bypass paths
# ---------------------------------------------------------------------------

@test "confidence-gate bypass: RED + .tdd-skip + structural-only gates -> allow; auto-bypass event appended" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  # NO_AC fires when spec has no ACs
  make_log "$LOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  printf 'TDD bypass active\nReason: docs-only change\nBranch: main\nTime: 2026-05-02T00:00:00Z\n' \
    > "$SANDBOX/.tdd-skip"
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
  # auto-bypass override event appended
  run jq -s '[.[] | select(.event=="override" and .trigger=="skip-tdd-auto")] | length' "$LOG"
  [ "$output" = "1" ]
}

@test "confidence-gate bypass: RED + .tdd-skip + behavioral gate (TEST_FAILED) -> deny; reason mentions override-confidence" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  printf 'TDD bypass active\nReason: docs-only change\nBranch: main\nTime: 2026-05-02T00:00:00Z\n' \
    > "$SANDBOX/.tdd-skip"
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("override-confidence")' >/dev/null
}

@test "confidence-gate bypass: RED + valid override marker -> allow; marker removed; override event appended" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  echo '{"reason":"emergency release, audit follows","branch":"main","ts":"2026-05-02T00:00:00Z","user":"u"}' \
    > "$SANDBOX/.git/aw/override-PROJ-1"
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
  # Marker removed
  [ ! -f "$SANDBOX/.git/aw/override-PROJ-1" ]
  # Override event appended
  run jq -s '[.[] | select(.event=="override" and .trigger=="manual")] | length' "$LOG"
  [ "$output" = "1" ]
}

@test "confidence-gate bypass: RED + malformed override (no reason field) -> deny; marker removed" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  # Malformed: valid JSON but no .reason field
  echo '{"branch":"main"}' > "$SANDBOX/.git/aw/override-PROJ-1"
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  # Marker removed even on malformed
  [ ! -f "$SANDBOX/.git/aw/override-PROJ-1" ]
}

@test "confidence-gate bypass: RED + completely invalid JSON override -> deny; marker removed" {
  echo "PROJ-1" > "$SANDBOX/.git/aw/active-spec"
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  # Completely invalid JSON in override marker
  printf 'not-json\n' > "$SANDBOX/.git/aw/override-PROJ-1"
  local payload
  payload="$(mk_payload "bash" "gh pr create" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  # Marker removed even on malformed JSON
  [ ! -f "$SANDBOX/.git/aw/override-PROJ-1" ]
}

# ---------------------------------------------------------------------------
# Fix 3: jq-free emit_deny regression test
# ---------------------------------------------------------------------------

@test "dispatcher: emits deny JSON even when jq is unavailable (fail-closed)" {
  # Simulate jq absence by overriding the bash 'command' builtin in a wrapper
  # so that 'command -v jq' returns 1. This avoids PATH surgery while reliably
  # hiding jq from the dispatcher's perspective.
  local TMPDIR2
  TMPDIR2="$(mktemp -d /tmp/aw-jq-stub-XXXXXX)"

  # Wrapper script: export a command() override before running the dispatcher.
  cat > "$TMPDIR2/run.sh" << 'RUNEOF'
#!/usr/bin/env bash
command() {
  if [ "$1" = "-v" ] && [ "$2" = "jq" ]; then
    return 1
  fi
  builtin command "$@"
}
export -f command
bash "$1" < "$2"
RUNEOF
  chmod +x "$TMPDIR2/run.sh"

  local payload
  payload="$(mk_payload bash "git commit -m foo" "$SANDBOX")"
  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"

  run bash "$TMPDIR2/run.sh" "$DISPATCHER" "$tmpfile"

  rm -f "$tmpfile"
  rm -rf "$TMPDIR2"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"permissionDecision":"deny"'
  echo "$output" | grep -q 'jq not found'
}

# ---------------------------------------------------------------------------
# Fix 4: BASH_CMD extraction fail-closed regression test
# ---------------------------------------------------------------------------

@test "dispatcher: malformed toolArgs (not JSON string) -> deny fail-closed" {
  # toolArgs must be a JSON-encoded string; passing a raw number causes fromjson to fail
  local payload
  payload='{"toolName":"bash","toolArgs":12345,"cwd":"'"$SANDBOX"'","timestamp":1714694400000}'
  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  run bash -c "cat '$tmpfile' | bash '$DISPATCHER' 2>/dev/null"
  rm -f "$tmpfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
}
