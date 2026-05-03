#!/usr/bin/env bats

# Sandbox install verification for Task 13: hook registration & installer.
# Runs `ai-native-workflow install global` into a temp dir and checks that
# confidence-gate artifacts are present and the settings.json hook count is 2.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-confidence-install-XXXXXX)"
}

teardown() {
  rm -rf "$SANDBOX"
}

# Note: CLAUDE_HOME is the target .claude directory itself (not its parent).
# The installer sets CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}", so CLAUDE_HOME
# IS the install root (e.g. /tmp/sandbox maps to /tmp/sandbox/hooks/, not
# /tmp/sandbox/.claude/hooks/).

@test "install: confidence-gate.sh is copied to hooks/" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/hooks/confidence-gate.sh" ]
}

@test "install: confidence.sh is copied to scripts/" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/scripts/confidence.sh" ]
}

@test "install: confidence-cli.sh is copied to scripts/" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/scripts/confidence-cli.sh" ]
}

@test "install: override-confidence/SKILL.md is copied to skills/" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/skills/override-confidence/SKILL.md" ]
}

@test "install: override-confidence/skill.bash is copied to skills/" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/skills/override-confidence/skill.bash" ]
}

@test "install: settings.json PreToolUse Bash hooks array has 2 entries (tdd-gate + confidence-gate)" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  count="$(jq '.hooks.PreToolUse[0].hooks | length' "$SANDBOX/settings.json")"
  [ "$count" = "2" ]
}

@test "install: tdd-gate.sh is still present (no regression)" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/hooks/tdd-gate.sh" ]
}

@test "install: settings.json first hook is tdd-gate (order preserved)" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SANDBOX/settings.json")"
  [[ "$cmd" == *"tdd-gate.sh"* ]]
}

@test "install: settings.json second hook is confidence-gate" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  cmd="$(jq -r '.hooks.PreToolUse[0].hooks[1].command' "$SANDBOX/settings.json")"
  [[ "$cmd" == *"confidence-gate.sh"* ]]
}
