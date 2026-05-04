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

# ---------------------------------------------------------------------------
# Step 3: Pipeline-skill rewrite — claude --agent= → copilot --agent=
# ---------------------------------------------------------------------------

@test "install global: pipeline-gitlab-feature SKILL.md uses copilot --agent= (not claude)" {
  run_install_global
  grep -q 'copilot --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
  ! grep -q 'claude --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
}

@test "install global: pipeline-gitlab-incident SKILL.md uses copilot --agent=" {
  run_install_global
  grep -q 'copilot --agent=' "$SANDBOX/skills/pipeline-gitlab-incident/SKILL.md"
  ! grep -q 'claude --agent=' "$SANDBOX/skills/pipeline-gitlab-incident/SKILL.md"
}

@test "install global: explore SKILL.md uses copilot --agent= in copilot install path" {
  run_install_global
  grep -q 'copilot --agent=' "$SANDBOX/skills/explore/SKILL.md"
  ! grep -q 'claude --agent=' "$SANDBOX/skills/explore/SKILL.md"
}

@test "install global: Claude side keeps claude --agent= (rewrite is Copilot-only)" {
  run_install_global
  grep -q 'claude --agent=' "$CLAUDE_HOME/skills/pipeline-gitlab-feature/SKILL.md"
}

# ---------------------------------------------------------------------------
# Step 4: install_global_copilot_instructions — global instructions file
# ---------------------------------------------------------------------------

@test "install global: writes copilot-instructions.md with required marker substrings" {
  run_install_global
  [ -f "$SANDBOX/copilot-instructions.md" ]
  grep -q 'Stack Detection'  "$SANDBOX/copilot-instructions.md"
  grep -q 'Agent Pipeline'   "$SANDBOX/copilot-instructions.md"
  grep -q '/plan'            "$SANDBOX/copilot-instructions.md"
  # Negative: no Claude-specific phrasing
  ! grep -q '~/.claude/'           "$SANDBOX/copilot-instructions.md"
  ! grep -q 'Claude Code session'  "$SANDBOX/copilot-instructions.md"
}

@test "install global: copilot-instructions.md is backed up on re-install" {
  run_install_global
  run_install_global
  # Exactly one backup file should exist after the second run
  backups=( "$SANDBOX"/copilot-instructions.md.bak.* )
  [ "${#backups[@]}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Step 5: install_global_copilot_settings — fresh install path
# ---------------------------------------------------------------------------

@test "install global: settings.json fresh install seeds renderMarkdown/theme/beep" {
  run_install_global
  [ -f "$SANDBOX/settings.json" ]
  [ "$(jq -r '.renderMarkdown' "$SANDBOX/settings.json")" = "true" ]
  [ "$(jq -r '.theme'          "$SANDBOX/settings.json")" = "auto" ]
  [ "$(jq -r '.beep'           "$SANDBOX/settings.json")" = "true" ]
}

@test "install global: settings.json fresh install has no hooks key" {
  run_install_global
  ! jq -e '.hooks' "$SANDBOX/settings.json" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Step 6: install_global_copilot_settings — merge path preserves user keys
# ---------------------------------------------------------------------------

@test "install global: settings.json merge preserves user-set model/effortLevel/allowedUrls" {
  mkdir -p "$SANDBOX"
  cat > "$SANDBOX/settings.json" <<'JSON'
{"model": "gpt-5", "effortLevel": "high", "allowedUrls": ["https://example.com"]}
JSON
  run_install_global
  [ "$(jq -r '.model'           "$SANDBOX/settings.json")" = "gpt-5" ]
  [ "$(jq -r '.effortLevel'     "$SANDBOX/settings.json")" = "high" ]
  [ "$(jq -r '.allowedUrls[0]'  "$SANDBOX/settings.json")" = "https://example.com" ]
  # Defaults filled in for missing keys:
  [ "$(jq -r '.renderMarkdown'  "$SANDBOX/settings.json")" = "true" ]
  [ "$(jq -r '.theme'           "$SANDBOX/settings.json")" = "auto" ]
  # And exactly one backup of the pre-merge file:
  backups=( "$SANDBOX"/settings.json.bak.* )
  [ "${#backups[@]}" -eq 1 ]
}

@test "install global: settings.json merge does NOT overwrite existing user value" {
  mkdir -p "$SANDBOX"
  echo '{"theme":"dark","beep":false}' > "$SANDBOX/settings.json"
  run_install_global
  [ "$(jq -r '.theme' "$SANDBOX/settings.json")" = "dark" ]
  [ "$(jq -r '.beep'  "$SANDBOX/settings.json")" = "false" ]
}

# ---------------------------------------------------------------------------
# Step 7: Graceful skip when Copilot CLI absent + closing-banner caveat
# ---------------------------------------------------------------------------

@test "install global: skips Copilot section when copilot is not on PATH" {
  EMPTY_BIN="$(mktemp -d /tmp/aw-empty-XXXXXX)"
  PATH="$EMPTY_BIN:/usr/bin:/bin" \
    CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" install global >/dev/null 2>&1
  rm -rf "$EMPTY_BIN"
  [ ! -d "$SANDBOX/skills" ]
  [ ! -f "$SANDBOX/copilot-instructions.md" ]
  [ ! -f "$SANDBOX/settings.json" ]
}

@test "install global: closing banner mentions hooks-not-globally-installed caveat" {
  output="$(run_install_global 2>&1)"
  [[ "$output" == *"Copilot hooks are NOT installed globally"* ]]
}

@test "install global: closing banner caveat prints even when copilot is absent" {
  EMPTY_BIN="$(mktemp -d /tmp/aw-empty-XXXXXX)"
  output="$(PATH="$EMPTY_BIN:/usr/bin:/bin" \
    CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" install global 2>&1)"
  rm -rf "$EMPTY_BIN"
  [[ "$output" == *"Copilot hooks are NOT installed globally"* ]]
}

# ---------------------------------------------------------------------------
# Step 8: Status command surfaces Copilot artifacts
# ---------------------------------------------------------------------------

@test "status: lists every installed Copilot skill with ✓" {
  run_install_global
  output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" status 2>&1)"
  # Extract only the Copilot CLI section (lines after the "Copilot CLI" header)
  copilot_section="$(echo "$output" | awk '/Copilot CLI/,0')"
  for d in "$REPO_ROOT/skills"/*/; do
    name="$(basename "$d")"
    [[ "$copilot_section" == *"skills/$name"* ]] || { echo "missing in Copilot section: $name"; return 1; }
  done
}

@test "status: lists copilot-instructions.md and settings.json" {
  run_install_global
  output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" status 2>&1)"
  # Extract only the Copilot CLI section (lines after the "Copilot CLI" header)
  copilot_section="$(echo "$output" | awk '/Copilot CLI/,0')"
  [[ "$copilot_section" == *"copilot-instructions.md"* ]]
  [[ "$copilot_section" == *"settings.json"* ]]
}

# ---------------------------------------------------------------------------
# Step 9: Uninstall removes Copilot skills, preserves user files
# ---------------------------------------------------------------------------

@test "uninstall global: removes ~/.copilot/skills/ tree" {
  run_install_global
  [ -d "$SANDBOX/skills" ]
  CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" uninstall global >/dev/null 2>&1
  [ ! -d "$SANDBOX/skills" ]
}

@test "uninstall global: preserves copilot-instructions.md (warns instead)" {
  run_install_global
  output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" uninstall global 2>&1)"
  [ -f "$SANDBOX/copilot-instructions.md" ]
  [[ "$output" == *"copilot-instructions.md preserved"* ]] || \
    [[ "$output" == *"copilot-instructions.md"*"preserved"* ]]
}

@test "uninstall global: preserves settings.json (warns instead)" {
  run_install_global
  CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" uninstall global >/dev/null 2>&1
  [ -f "$SANDBOX/settings.json" ]
}

# ---------------------------------------------------------------------------
# Step 10: Documentation — README + ARCHITECTURE updates
# ---------------------------------------------------------------------------

@test "docs: README mentions ~/.copilot/skills/" {
  rg -q '~/\.copilot/skills/' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: README mentions ~/.copilot/copilot-instructions.md" {
  rg -q '~/\.copilot/copilot-instructions\.md' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: README mentions ~/.copilot/settings.json" {
  rg -q '~/\.copilot/settings\.json' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: ARCHITECTURE notes hooks asymmetry (Claude global, Copilot repo-scope)" {
  rg -qi 'copilot.*(repo|repository)[- ]scope|repo[- ]scope.*copilot' \
    "$BATS_TEST_DIRNAME/../docs/ARCHITECTURE.md"
}

# ---------------------------------------------------------------------------
# Step 11: Integration smoke — fresh install end-to-end + idempotency
# ---------------------------------------------------------------------------

@test "integration smoke: install global twice produces full Copilot harness, one backup per file per re-run" {
  run_install_global
  # Snapshot first-run state
  first_skills_count=$(find "$SANDBOX/skills" -name 'SKILL.md' | wc -l | tr -d ' ')
  [ "$first_skills_count" -ge 14 ]
  [ -f "$SANDBOX/copilot-instructions.md" ]
  [ -f "$SANDBOX/settings.json" ]
  # Re-run
  run_install_global
  # Backups exist for each rewritten file
  [ "$(find "$SANDBOX" -maxdepth 2 -name 'copilot-instructions.md.bak.*' | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(find "$SANDBOX" -maxdepth 2 -name 'settings.json.bak.*' | wc -l | tr -d ' ')" -eq 1 ]
  # Pipeline rewrite still in place after re-run
  grep -q 'copilot --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
  ! grep -q 'claude --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
  # Status reflects the install
  output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" status 2>&1)"
  [[ "$output" == *"copilot-instructions.md"* ]]
  [[ "$output" == *"settings.json"* ]]
}

@test "integration smoke: COPILOT_HOME=/tmp/cop-test redirects all writes" {
  ALT="$(mktemp -d /tmp/aw-cop-alt-XXXXXX)"
  PATH="$STUB_BIN:$PATH" CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$ALT" \
    "$INSTALLER" install global >/dev/null 2>&1
  [ -d "$ALT/skills" ]
  [ -f "$ALT/copilot-instructions.md" ]
  [ -f "$ALT/settings.json" ]
  rm -rf "$ALT"
}
