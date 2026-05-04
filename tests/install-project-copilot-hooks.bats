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
