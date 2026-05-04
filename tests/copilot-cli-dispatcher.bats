#!/usr/bin/env bats
# Tests for COP-2: copilot-cli-dispatcher.sh behaviour
# Steps 4 and 5: trap+filter skeleton and cwd resolution.

load 'lib/copilot-payload-helpers'

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-dispatcher-XXXXXX)"
  # Install the dispatcher into the sandbox
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  DISPATCHER="$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
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
  run bash -c "cat '$tmpfile' | bash '$DISPATCHER'"
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

  local payload
  payload="$(mk_payload "bash" "git status" "$SANDBOX/subdir")"

  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  # Run with ANW_DEBUG=1; stderr (and combined output) should show resolved dir
  run bash -c "ANW_DEBUG=1 cat '$tmpfile' | bash '$DISPATCHER' 2>&1"
  rm -f "$tmpfile"
  # Dispatcher must exist (not exit 127) and trace must mention sandbox root
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SANDBOX"* ]]
}

@test "dispatcher: payload missing cwd and not in git repo -> deny with project dir reason" {
  # Build a payload without cwd field
  local payload
  payload='{"toolName":"bash","toolArgs":"{\"command\":\"git status\"}","timestamp":1714694400000}'

  local tmpfile
  tmpfile="$(mktemp /tmp/dispatcher-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  # Run with HOME=/tmp/nonexistent to avoid picking up any real repo
  run bash -c "cd /tmp && cat '$tmpfile' | bash '$DISPATCHER'"
  rm -f "$tmpfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("project dir")' >/dev/null
}

@test "dispatcher: payload cwd inside git repo -> allow (cwd resolves successfully)" {
  git -C "$SANDBOX" init -q
  local payload
  payload="$(mk_payload "bash" "git status" "$SANDBOX")"
  run_dispatcher "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}
