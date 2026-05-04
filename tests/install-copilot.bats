#!/usr/bin/env bats

# COP-1: Symmetric Copilot CLI harness verification.
# Grown incrementally across steps; Step 1 creates this file.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-cop-XXXXXX)"
  CLAUDE_HOME_DIR="$(mktemp -d /tmp/aw-claude-XXXXXX)"
  STUB_BIN="$(mktemp -d /tmp/aw-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/copilot"
  chmod +x "$STUB_BIN/copilot"
  export PATH="$STUB_BIN:$PATH"
  export COPILOT_HOME="$SANDBOX"
  export CLAUDE_HOME="$CLAUDE_HOME_DIR"
}

teardown() {
  rm -rf "$SANDBOX" "$CLAUDE_HOME_DIR" "$STUB_BIN"
}

run_install_global() {
  CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    PATH="$STUB_BIN:$PATH" \
    "$INSTALLER" install global "$@"
}

# ---------------------------------------------------------------------------
# Step 1: COPILOT_* top-level constants
# ---------------------------------------------------------------------------

@test "installer: COPILOT_DIR / COPILOT_SKILLS_DIR / COPILOT_INSTRUCTIONS_FILE / COPILOT_SETTINGS_FILE are top-level constants" {
  grep -qE '^COPILOT_DIR="\$\{COPILOT_HOME:-\$HOME/\.copilot\}"' "$INSTALLER"
  grep -qE '^COPILOT_AGENTS_DIR=' "$INSTALLER"
  grep -qE '^COPILOT_SKILLS_DIR=' "$INSTALLER"
  grep -qE '^COPILOT_INSTRUCTIONS_FILE=' "$INSTALLER"
  grep -qE '^COPILOT_SETTINGS_FILE=' "$INSTALLER"
  # And: no function-local COPILOT_DIR redefinitions remain
  ! grep -q 'local COPILOT_DIR=' "$INSTALLER"
}

# ---------------------------------------------------------------------------
# Step 2: install_global_copilot_skills — copy every skill
# ---------------------------------------------------------------------------

@test "install global: copies every skill from source to \$COPILOT_HOME/skills/" {
  run_install_global
  for d in "$REPO_ROOT/skills"/*/; do
    name="$(basename "$d")"
    [ -f "$SANDBOX/skills/$name/SKILL.md" ] || { echo "missing: $name"; return 1; }
  done
}

@test "install global: copies override-confidence/skill.bash to \$COPILOT_HOME/skills/" {
  run_install_global
  [ -f "$SANDBOX/skills/override-confidence/skill.bash" ]
}
