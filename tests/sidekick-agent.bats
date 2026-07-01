#!/usr/bin/env bats

# SDK-1 Step A-1: sidekick agent contract + install wiring (GATE).
#
# Verifies:
#   - the source agents/claude-code/sidekick.md frontmatter is exactly the
#     OQ-6 decision: model: haiku, tools: Read, Write, Edit, Glob, Grep
#     (no Bash, no Task);
#   - `install global` into a sandbox CLAUDE_HOME picks up sidekick.md via
#     the existing agents/claude-code/*.md glob with ZERO installer changes
#     (lib/install-global.sh:593-607, install_global_agents()).
#
# Note: CLAUDE_HOME is the target .claude directory itself (not its parent),
# same convention as tests/install.bats.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
SIDEKICK_SRC="$BATS_TEST_DIRNAME/../agents/claude-code/sidekick.md"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-sidekick-install-XXXXXX)"
}

teardown() {
  rm -rf "$SANDBOX"
}

# ---------------------------------------------------------------------------
# Source frontmatter contract (OQ-6)
# ---------------------------------------------------------------------------

@test "sidekick source: agents/claude-code/sidekick.md exists" {
  [ -f "$SIDEKICK_SRC" ]
}

@test "sidekick source: frontmatter name is sidekick" {
  grep -qE '^name: sidekick$' "$SIDEKICK_SRC"
}

@test "sidekick source: frontmatter model is haiku (no pinned version)" {
  grep -qE '^model: haiku$' "$SIDEKICK_SRC"
}

@test "sidekick source: tools line is exactly Read, Write, Edit, Glob, Grep" {
  grep -qE '^tools: Read, Write, Edit, Glob, Grep$' "$SIDEKICK_SRC"
}

@test "sidekick source: tools line does not grant Bash" {
  tools_line="$(grep -E '^tools:' "$SIDEKICK_SRC")"
  [[ "$tools_line" != *Bash* ]]
}

@test "sidekick source: tools line does not grant Task" {
  tools_line="$(grep -E '^tools:' "$SIDEKICK_SRC")"
  [[ "$tools_line" != *Task* ]]
}

# ---------------------------------------------------------------------------
# Install wiring: zero installer changes, picked up by the existing glob
# ---------------------------------------------------------------------------

@test "install global: sidekick.md lands in the installed agents dir" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/agents/sidekick.md" ]
}

@test "install global: installed sidekick.md byte-matches source (no drift)" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  cmp -s "$SIDEKICK_SRC" "$SANDBOX/agents/sidekick.md"
}

@test "install global: installed sidekick.md frontmatter preserves model: haiku and exact tools" {
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  grep -qE '^model: haiku$' "$SANDBOX/agents/sidekick.md"
  grep -qE '^tools: Read, Write, Edit, Glob, Grep$' "$SANDBOX/agents/sidekick.md"
}
