#!/usr/bin/env bats

# Sandbox install verification for Task 13: hook registration & installer.
# Runs `ai-native-workflow install global` into a temp dir and checks that
# confidence-gate artifacts are present and the settings.json hook count is 2.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-confidence-install-XXXXXX)"
  LINKDIR=""
}

teardown() {
  rm -rf "$SANDBOX"
  if [ -n "$LINKDIR" ]; then rm -rf "$LINKDIR"; fi
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

@test "install: merge preserves user-added PreToolUse hooks" {
  # Pre-populate sandbox with an existing settings.json that has a custom hook
  mkdir -p "$SANDBOX"
  cat > "$SANDBOX/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/tdd-gate.sh", "timeout": 10},
          {"type": "command", "command": "bash ~/.claude/hooks/my-custom-hook.sh", "timeout": 5}
        ]
      }
    ]
  }
}
EOF

  # Run install
  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1

  # Collect all hook commands from the merged settings.json
  output="$(jq -r '.hooks.PreToolUse[0].hooks[].command' "$SANDBOX/settings.json")"

  # Assert: user's custom hook is still present
  [[ "$output" == *"my-custom-hook.sh"* ]]

  # Assert: both expected hooks are present
  [[ "$output" == *"tdd-gate.sh"* ]]
  [[ "$output" == *"confidence-gate.sh"* ]]

  # Assert: tdd-gate appears exactly once (deduplication worked)
  count="$(echo "$output" | grep -c 'tdd-gate.sh' || true)"
  [ "$count" -eq 1 ]

  # Assert: total hook count is 3 (tdd, confidence, custom)
  total="$(jq '.hooks.PreToolUse[0].hooks | length' "$SANDBOX/settings.json")"
  [ "$total" = "3" ]
}

# ---------------------------------------------------------------------------
# Fix 4: settings merge preserves multiple user-defined matchers
# ---------------------------------------------------------------------------

@test "install: merge preserves user's multiple matchers in PreToolUse" {
  mkdir -p "$SANDBOX"
  cat > "$SANDBOX/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tdd-gate.sh", "timeout": 10}]
      },
      {
        "matcher": "UserPromptSubmit",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/my-prompt-hook.sh", "timeout": 5}]
      }
    ]
  }
}
EOF

  CLAUDE_HOME="$SANDBOX" "$INSTALLER" install global >/dev/null 2>&1
  [ "$?" -eq 0 ]

  # Both matchers must be present after merge
  matchers="$(jq -r '.hooks.PreToolUse[].matcher' "$SANDBOX/settings.json")"
  [[ "$matchers" == *"Bash"* ]]
  [[ "$matchers" == *"UserPromptSubmit"* ]]

  # User's UserPromptSubmit hook must still be present
  run jq -r '.hooks.PreToolUse[] | select(.matcher=="UserPromptSubmit") | .hooks[].command' "$SANDBOX/settings.json"
  [[ "$output" == *"my-prompt-hook.sh"* ]]
}

# ---------------------------------------------------------------------------
# BREW-1 Step 2: install global survives symlink invocation (brew layout)
# ---------------------------------------------------------------------------

@test "install: install global succeeds when invoked via a symlink (brew layout)" {
  LINKDIR="$(mktemp -d /tmp/aw-brew-link-XXXXXX)"
  ln -s "$INSTALLER" "$LINKDIR/ai-native-workflow"

  run env CLAUDE_HOME="$SANDBOX" "$LINKDIR/ai-native-workflow" install global
  [ "$status" -eq 0 ]

  [ -f "$SANDBOX/hooks/confidence-gate.sh" ]
  [ -f "$SANDBOX/scripts/confidence-cli.sh" ]
  [ -f "$SANDBOX/scripts/confidence.sh" ]
  [ -f "$SANDBOX/skills/override-confidence/SKILL.md" ]
  [ -f "$SANDBOX/skills/override-confidence/skill.bash" ]
}

# ---------------------------------------------------------------------------
# CTX-1 Steps 1+2: new docs/context/ layout and runtime-only .gitignore
# ---------------------------------------------------------------------------

@test "install project: creates docs/context/CURRENT_SPRINT.md" {
  SANDBOX_PROJECT="$(mktemp -d /tmp/aw-project-XXXXXX)"
  "$INSTALLER" install project "$SANDBOX_PROJECT" >/dev/null 2>&1
  [ -f "$SANDBOX_PROJECT/docs/context/CURRENT_SPRINT.md" ]
  rm -rf "$SANDBOX_PROJECT"
}

@test "install project: creates docs/context/specs/templates/feature-spec.md" {
  SANDBOX_PROJECT="$(mktemp -d /tmp/aw-project-XXXXXX)"
  "$INSTALLER" install project "$SANDBOX_PROJECT" >/dev/null 2>&1
  [ -f "$SANDBOX_PROJECT/docs/context/specs/templates/feature-spec.md" ]
  rm -rf "$SANDBOX_PROJECT"
}

@test "install project: project .gitignore contains runtime ignore entries" {
  SANDBOX_PROJECT="$(mktemp -d /tmp/aw-project-XXXXXX)"
  "$INSTALLER" install project "$SANDBOX_PROJECT" >/dev/null 2>&1
  grep -qF '.context/.pipeline-state' "$SANDBOX_PROJECT/.gitignore"
  grep -qF '.context/.pipeline-audit.log' "$SANDBOX_PROJECT/.gitignore"
  grep -qF '.context/specs/*.jsonl' "$SANDBOX_PROJECT/.gitignore"
  rm -rf "$SANDBOX_PROJECT"
}

@test "install project: project .gitignore does NOT contain bare .context/" {
  SANDBOX_PROJECT="$(mktemp -d /tmp/aw-project-XXXXXX)"
  "$INSTALLER" install project "$SANDBOX_PROJECT" >/dev/null 2>&1
  ! grep -qE '^\.context/$' "$SANDBOX_PROJECT/.gitignore"
  rm -rf "$SANDBOX_PROJECT"
}

# ---------------------------------------------------------------------------
# CTX-1 Step 3: repo-level .gitignore shape guard
# ---------------------------------------------------------------------------

@test "repo .gitignore: does NOT contain bare .context/" {
  ! grep -qE '^\.context/$' "$BATS_TEST_DIRNAME/../.gitignore"
}

@test "repo .gitignore: contains the three runtime entries" {
  grep -qF '.context/.pipeline-state'    "$BATS_TEST_DIRNAME/../.gitignore"
  grep -qF '.context/.pipeline-audit.log' "$BATS_TEST_DIRNAME/../.gitignore"
  grep -qF '.context/specs/*.jsonl'      "$BATS_TEST_DIRNAME/../.gitignore"
}

# ---------------------------------------------------------------------------
# CTX-1 Step 5: Claude Code agent prompts use docs/context/
# ---------------------------------------------------------------------------

@test "agents/claude-code: no spec/todo/requirements paths under .context/specs/" {
  # Spec, todo, requirements, bugfix, brainstorm, testplan artifacts must reference docs/context/
  # Confidence jsonl stays under .context/specs/ — excluded by the negative lookahead pattern below
  ! rg -q '\.context/specs/[^$]*-(spec|todo|requirements|bugfix|brainstorm|testplan)' \
    "$BATS_TEST_DIRNAME/../agents/claude-code/"
}

@test "agents/claude-code: confidence jsonl path under .context/specs/ remains" {
  rg -q '\.context/specs/.*-confidence\.jsonl' \
    "$BATS_TEST_DIRNAME/../agents/claude-code/qa.md" \
    "$BATS_TEST_DIRNAME/../agents/claude-code/reviewer.md" \
    "$BATS_TEST_DIRNAME/../agents/claude-code/architect.md"
}

@test "agents/claude-code: ARCHITECTURE and CONVENTIONS reads stay under .context/" {
  rg -q '\.context/ARCHITECTURE\.md' "$BATS_TEST_DIRNAME/../agents/claude-code/architect.md"
}

# ---------------------------------------------------------------------------
# CTX-1 Step 6: Copilot CLI agent prompts use docs/context/
# ---------------------------------------------------------------------------

@test "agents/copilot-cli: no spec/todo/requirements paths under .context/specs/" {
  ! rg -q '\.context/specs/[^$]*-(spec|todo|requirements|bugfix|brainstorm|testplan)' \
    "$BATS_TEST_DIRNAME/../agents/copilot-cli/"
}

@test "agents/copilot-cli: confidence jsonl path under .context/specs/ remains" {
  rg -q '\.context/specs/.*-confidence\.jsonl' \
    "$BATS_TEST_DIRNAME/../agents/copilot-cli/qa.agent.md" \
    "$BATS_TEST_DIRNAME/../agents/copilot-cli/reviewer.agent.md" \
    "$BATS_TEST_DIRNAME/../agents/copilot-cli/architect.agent.md"
}
