#!/usr/bin/env bats
# Tests for COP-2: install_project_copilot_hooks()
# Runs `ai-native-workflow install project` into a sandbox directory.

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
