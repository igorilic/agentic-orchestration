#!/usr/bin/env bats
# Tests for COP-2: install_project_copilot_hooks()
# Runs `ai-native-workflow install project` into a sandbox directory.

load 'lib/copilot-payload-helpers'
load 'lib/confidence-helpers'

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-copilot-hooks-install-XXXXXX)"
}

teardown() {
  rm -rf "$SANDBOX"
}

# ---------------------------------------------------------------------------
# Step 2: installer creates .github/hooks/ skeleton directories
# ---------------------------------------------------------------------------

@test "install project: .github/hooks/ directory is created" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -d "$SANDBOX/.github/hooks" ]
}

@test "install project: .github/hooks/scripts/ directory is created" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -d "$SANDBOX/.github/hooks/scripts" ]
}

# ---------------------------------------------------------------------------
# Step 3: confidence.sh is vendored into .github/hooks/scripts/
# ---------------------------------------------------------------------------

@test "install project: .github/hooks/scripts/confidence.sh exists after install" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -f "$SANDBOX/.github/hooks/scripts/confidence.sh" ]
}

@test "install project: .github/hooks/scripts/confidence.sh has executable bit set" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -x "$SANDBOX/.github/hooks/scripts/confidence.sh" ]
}

@test "install project: .github/hooks/scripts/confidence.sh is byte-identical to repo scripts/confidence.sh" {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  cmp -s "$REPO_DIR/scripts/confidence.sh" "$SANDBOX/.github/hooks/scripts/confidence.sh"
}

# ---------------------------------------------------------------------------
# Step 4: dispatcher skeleton is created with correct content
# ---------------------------------------------------------------------------

@test "install project: .github/hooks/copilot-cli-dispatcher.sh exists after install" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -f "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh" ]
}

@test "install project: .github/hooks/copilot-cli-dispatcher.sh has mode 0755" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -x "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh" ]
}

@test "install project: dispatcher contains trap emit_deny ERR pattern" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  grep -q "trap 'emit_deny" "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
}

@test "install project: dispatcher contains permissionDecisionReason" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  grep -q "permissionDecisionReason" "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
}

@test "install project: dispatcher contains toolName != bash filter" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  grep -q 'toolName != "bash"' "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
}

# ---------------------------------------------------------------------------
# Step 6: policy JSON writer — fresh-install path
# ---------------------------------------------------------------------------

@test "install project: copilot-cli-policy.json is created on fresh install" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -f "$SANDBOX/.github/hooks/copilot-cli-policy.json" ]
}

@test "install project: copilot-cli-policy.json is valid JSON" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  jq -e . < "$SANDBOX/.github/hooks/copilot-cli-policy.json" >/dev/null
}

@test "install project: copilot-cli-policy.json has version 1" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq -r '.version' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" = "1" ]
}

@test "install project: copilot-cli-policy.json preToolUse has exactly 1 entry on fresh install" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq '.hooks.preToolUse | length' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" -eq 1 ]
}

@test "install project: copilot-cli-policy.json preToolUse[0].bash is ./copilot-cli-dispatcher.sh" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq -r '.hooks.preToolUse[0].bash' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" = "./copilot-cli-dispatcher.sh" ]
}

@test "install project: copilot-cli-policy.json preToolUse[0].cwd is .github/hooks" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq -r '.hooks.preToolUse[0].cwd' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" = ".github/hooks" ]
}

@test "install project: copilot-cli-policy.json preToolUse[0].timeoutSec is 15" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq -r '.hooks.preToolUse[0].timeoutSec' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" -eq 15 ]
}

@test "install project: copilot-cli-policy.json preToolUse[0].type is command" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq -r '.hooks.preToolUse[0].type' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" = "command" ]
}

@test "install project: copilot-cli-policy.json preToolUse[0].comment is non-empty" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  local comment
  comment="$(jq -r '.hooks.preToolUse[0].comment' "$SANDBOX/.github/hooks/copilot-cli-policy.json")"
  [ -n "$comment" ] && [ "$comment" != "null" ]
}

# ---------------------------------------------------------------------------
# Step 7: policy JSON writer — merge path
# ---------------------------------------------------------------------------

@test "install project: re-install merges dispatcher into existing preToolUse" {
  # Pre-populate with a user-added entry
  mkdir -p "$SANDBOX/.github/hooks"
  jq -n '{version:1,hooks:{preToolUse:[{bash:"./scripts/audit-log.sh",cwd:".github/hooks",timeoutSec:10}]}}' \
    > "$SANDBOX/.github/hooks/copilot-cli-policy.json"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq '.hooks.preToolUse | length' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" -eq 2 ]
}

@test "install project: re-install preserves user-added audit-log.sh entry" {
  mkdir -p "$SANDBOX/.github/hooks"
  jq -n '{version:1,hooks:{preToolUse:[{bash:"./scripts/audit-log.sh",cwd:".github/hooks",timeoutSec:10}]}}' \
    > "$SANDBOX/.github/hooks/copilot-cli-policy.json"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  jq -e '.hooks.preToolUse[] | select(.bash == "./scripts/audit-log.sh")' \
    "$SANDBOX/.github/hooks/copilot-cli-policy.json" >/dev/null
}

@test "install project: re-install includes dispatcher entry after merge" {
  mkdir -p "$SANDBOX/.github/hooks"
  jq -n '{version:1,hooks:{preToolUse:[{bash:"./scripts/audit-log.sh",cwd:".github/hooks",timeoutSec:10}]}}' \
    > "$SANDBOX/.github/hooks/copilot-cli-policy.json"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  jq -e '.hooks.preToolUse[] | select(.bash == "./copilot-cli-dispatcher.sh")' \
    "$SANDBOX/.github/hooks/copilot-cli-policy.json" >/dev/null
}

@test "install project: running install twice dedupes dispatcher entry" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ "$(jq '.hooks.preToolUse | length' "$SANDBOX/.github/hooks/copilot-cli-policy.json")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Step 11: README stub + idempotency / backup-on-mismatch
# ---------------------------------------------------------------------------

@test "install project: .github/hooks/README.md exists after install" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  [ -f "$SANDBOX/.github/hooks/README.md" ]
}

@test "install project: .github/hooks/README.md mentions TDD gate" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  grep -qi "tdd" "$SANDBOX/.github/hooks/README.md"
}

@test "install project: .github/hooks/README.md mentions confidence gate" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  grep -qi "confidence" "$SANDBOX/.github/hooks/README.md"
}

@test "install project: second install produces no changes to dispatcher (idempotent)" {
  # First install into a temp git repo so git status works
  git -C "$SANDBOX" init -q
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  git -C "$SANDBOX" add .github/hooks
  git -C "$SANDBOX" -c user.email="test@test.com" -c user.name="Test" \
    commit -q -m "first install" --no-verify 2>/dev/null || true
  # Second install must produce no diff
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  local status
  status="$(git -C "$SANDBOX" status --porcelain .github/hooks/copilot-cli-dispatcher.sh)"
  [ -z "$status" ]
}

@test "install project: hand-edited dispatcher is backed up before overwrite" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  # Hand-edit the dispatcher
  echo "# MARKER_LINE_FOR_TEST" >> "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
  # Re-install should detect mismatch and backup
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  # A .bak.* file should exist
  local backups
  backups="$(ls "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh.bak."* 2>/dev/null | wc -l | tr -d ' ')"
  [ "$backups" -ge 1 ]
}

@test "install project: after backup overwrite, dispatcher no longer contains marker line" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  echo "# MARKER_LINE_FOR_TEST" >> "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  ! grep -q "MARKER_LINE_FOR_TEST" "$SANDBOX/.github/hooks/copilot-cli-dispatcher.sh"
}

# ---------------------------------------------------------------------------
# Step 12: End-to-end integration smoke tests
# ---------------------------------------------------------------------------

# Helper used only by smoke tests: pipe payload JSON into the installed dispatcher.
_smoke_run_dispatcher() {
  local sandbox="$1"
  local payload="$2"
  local tmpfile
  tmpfile="$(mktemp /tmp/smoke-payload-XXXXXX.json)"
  printf '%s' "$payload" > "$tmpfile"
  run bash -c "cat '$tmpfile' | bash '$sandbox/.github/hooks/copilot-cli-dispatcher.sh' 2>/dev/null"
  rm -f "$tmpfile"
}

@test "smoke: git commit payload with no staged test files is denied" {
  # Needs a real git repo for the TDD gate to read staged files
  git -C "$SANDBOX" init -q
  git -C "$SANDBOX" config user.email "smoke@test.com"
  git -C "$SANDBOX" config user.name "Smoke"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  local payload
  payload="$(mk_payload "bash" "git commit -m test" "$SANDBOX")"
  _smoke_run_dispatcher "$SANDBOX" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "deny"' >/dev/null
  echo "$output" | jq -e '.permissionDecisionReason | test("TDD")' >/dev/null
}

@test "smoke: non-bash tool payload is allowed immediately" {
  git -C "$SANDBOX" init -q
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  local payload
  payload="$(mk_payload "read_file" "cat README.md" "$SANDBOX")"
  _smoke_run_dispatcher "$SANDBOX" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "smoke: gh pr create with GREEN confidence log is allowed" {
  git -C "$SANDBOX" init -q
  git -C "$SANDBOX" config user.email "smoke@test.com"
  git -C "$SANDBOX" config user.name "Smoke"
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1

  # Set up active spec pointer
  mkdir -p "$SANDBOX/.git/aw" "$SANDBOX/.anw/specs"
  echo "SMOKE-1" > "$SANDBOX/.git/aw/active-spec"

  # Confidence log with GREEN aggregate score
  local log="$SANDBOX/.anw/specs/SMOKE-1-confidence.jsonl"
  make_log "$log" \
    "$(spec_event '["AC-1"]')" \
    "$(qa_event 1 5 0 "ok" '["AC-1"]')" \
    "$(review_event 1 0 0 0)"

  # Mock the vendored scorer to return GREEN
  mock_confidence_scorer "$SANDBOX" "GREEN" 90 '[]'

  local payload
  payload="$(mk_payload "bash" "gh pr create --title smoke" "$SANDBOX")"
  _smoke_run_dispatcher "$SANDBOX" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null
}

@test "smoke: copilot-cli-policy.json registers dispatcher as preToolUse hook" {
  "$INSTALLER" install project "$SANDBOX" >/dev/null 2>&1
  local policy="$SANDBOX/.github/hooks/copilot-cli-policy.json"
  jq -e '.hooks.preToolUse[] | select(.bash == "./copilot-cli-dispatcher.sh")' "$policy" >/dev/null
}
