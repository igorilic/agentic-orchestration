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

# Regression: a stackless project must NOT crash `install project`.
# detect_stacks expanded an empty array under `set -u` (bash 3.2), aborting
# the whole install before any file was written. (issue #7)
@test "install project: stackless repo installs cleanly (exit 0 + dispatcher written)" {
  SANDBOX_PROJECT="$(mktemp -d /tmp/aw-project-XXXXXX)"
  # No go.mod/package.json/etc. — detect_stacks returns empty.
  run "$INSTALLER" install project "$SANDBOX_PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_PROJECT/.github/hooks/copilot-cli-dispatcher.sh" ]
  [ -f "$SANDBOX_PROJECT/docs/context/CURRENT_SPRINT.md" ]
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
  rg -q '\.context/CONVENTIONS\.md' "$BATS_TEST_DIRNAME/../agents/claude-code/architect.md"
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

# ---------------------------------------------------------------------------
# CTX-1 Step 8: ai-native-workflow embedded heredocs use docs/context/
# ---------------------------------------------------------------------------

@test "cli: ai-native-workflow heredocs use docs/context/ for spec/sprint paths (no .context/specs/<id>-...)" {
  # Spec, todo, requirements, bugfix, brainstorm artifacts in heredocs must reference docs/context/
  # Confidence jsonl stays under .context/specs/ — matched separately below
  ! rg -q '\.context/specs/[^*]*-(spec|todo|requirements|bugfix|brainstorm|testplan)' \
    "$BATS_TEST_DIRNAME/../ai-native-workflow"
}

@test "cli: ai-native-workflow heredocs use docs/context/ for CURRENT_SPRINT (no .context/CURRENT_SPRINT)" {
  # All CURRENT_SPRINT references in heredocs must point to docs/context/
  ! rg -q '\.context/CURRENT_SPRINT' \
    "$BATS_TEST_DIRNAME/../ai-native-workflow"
}

# ---------------------------------------------------------------------------
# CTX-1 Step 9: hooks/session-start.sh reads sprint from docs/context/
# ---------------------------------------------------------------------------

@test "hooks: session-start reads sprint from docs/context/CURRENT_SPRINT.md" {
  local proj
  proj="$(mktemp -d /tmp/aw-session-start-XXXXXX)"
  mkdir -p "$proj/docs/context"
  echo "SPRINT_MARKER_XYZ" > "$proj/docs/context/CURRENT_SPRINT.md"
  output=$(CLAUDE_PROJECT_DIR="$proj" bash "$BATS_TEST_DIRNAME/../hooks/session-start.sh" 2>/dev/null)
  rm -rf "$proj"
  echo "$output" | grep -q "SPRINT_MARKER_XYZ"
}

@test "hooks: session-start does NOT read sprint from old .context/CURRENT_SPRINT.md (hard-cut)" {
  local proj
  proj="$(mktemp -d /tmp/aw-session-start-XXXXXX)"
  mkdir -p "$proj/.context"
  echo "OLD_SPRINT_MARKER_XYZ" > "$proj/.context/CURRENT_SPRINT.md"
  output=$(CLAUDE_PROJECT_DIR="$proj" bash "$BATS_TEST_DIRNAME/../hooks/session-start.sh" 2>/dev/null)
  rm -rf "$proj"
  ! echo "$output" | grep -q "OLD_SPRINT_MARKER_XYZ"
}

@test "hooks: session-start.sh source references docs/context/CURRENT_SPRINT.md" {
  rg -q 'docs/context/CURRENT_SPRINT\.md' "$BATS_TEST_DIRNAME/../hooks/session-start.sh"
}

@test "hooks: session-start.sh source does NOT reference .context/CURRENT_SPRINT.md" {
  ! rg -q '\.context/CURRENT_SPRINT\.md' "$BATS_TEST_DIRNAME/../hooks/session-start.sh"
}

# ---------------------------------------------------------------------------
# CTX-1 Step 10: templates/AGENTS.md and skills/ reference docs/context/
# ---------------------------------------------------------------------------

@test "docs: templates/AGENTS.md does not reference .context/CURRENT_SPRINT.md" {
  ! rg -q '\.context/CURRENT_SPRINT\.md' "$BATS_TEST_DIRNAME/../templates/AGENTS.md"
}

@test "docs: templates/AGENTS.md does not reference .context/specs/ for spec/todo paths" {
  # Allow .context/ARCHITECTURE.md and .context/CONVENTIONS.md (those stay)
  ! rg -q '\.context/specs/' "$BATS_TEST_DIRNAME/../templates/AGENTS.md"
}

@test "docs: skills/ do not reference .context/CURRENT_SPRINT.md" {
  ! rg -q '\.context/CURRENT_SPRINT\.md' "$BATS_TEST_DIRNAME/../skills/"
}

@test "docs: skills/ do not reference .context/specs/ for tracked spec artifacts" {
  # brainstorm, requirements, spec, todo, testplan, bugfix must move to docs/context/specs/
  # Confidence jsonl stays under .context/specs/ — not matched by this pattern
  ! rg -q '\.context/specs/[^$]*-(brainstorm|requirements|spec|todo|testplan|bugfix)' \
    "$BATS_TEST_DIRNAME/../skills/"
}

@test "docs: README.md mentions docs/context/" {
  rg -q 'docs/context/' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: ARCHITECTURE.md mentions docs/context/" {
  rg -q 'docs/context/' "$BATS_TEST_DIRNAME/../docs/ARCHITECTURE.md"
}

@test "docs: README.md does not reference old .context/specs/ tracked artifact paths" {
  # Lines with confidence.jsonl (runtime artifact) are allowed to stay
  # We check specifically for the spec/todo/requirements/bugfix/testplan/brainstorm old paths
  ! rg -q '\.context/specs/<id>-(requirements|spec|todo|bugfix|testplan|brainstorm)' \
    "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: ARCHITECTURE.md does not reference old .context/specs/ tracked artifact paths" {
  # Pipeline diagrams used to show → .context/specs/<id>-requirements.md; those must now show docs/context/
  ! rg -q '\.context/specs/<id>-(requirements|spec|todo|bugfix|testplan|brainstorm)' \
    "$BATS_TEST_DIRNAME/../docs/ARCHITECTURE.md"
}

# ---------------------------------------------------------------------------
# CTX-1 Step 12: Integration smoke — fresh install produces new layout end-to-end
# ---------------------------------------------------------------------------

@test "integration smoke: install global then install project produces new docs/context/ layout" {
  local sandbox_claude sandbox_project
  sandbox_claude="$(mktemp -d /tmp/aw-smoke-claude-XXXXXX)"
  sandbox_project="$(mktemp -d /tmp/aw-smoke-project-XXXXXX)"

  # Run global install into sandbox (installs agents, hooks, skills)
  CLAUDE_HOME="$sandbox_claude" "$INSTALLER" install global >/dev/null 2>&1

  # Run project install into the project sandbox
  "$INSTALLER" install project "$sandbox_project" >/dev/null 2>&1

  # AC: tracked sprint and specs go to docs/context/
  [ -f "$sandbox_project/docs/context/CURRENT_SPRINT.md" ]
  [ -f "$sandbox_project/docs/context/specs/templates/feature-spec.md" ]

  # AC: architecture/conventions/glossary docs stay in .context/ (installer-seeded, tracked in consumer)
  [ -f "$sandbox_project/.context/ARCHITECTURE.md" ]
  [ -f "$sandbox_project/.context/CONVENTIONS.md" ]
  [ -f "$sandbox_project/.context/GLOSSARY.md" ]

  # AC: .gitignore contains runtime-only entries
  grep -qF '.context/.pipeline-state' "$sandbox_project/.gitignore"

  # AC: .gitignore does NOT contain bare .context/ (legacy blanket ignore gone)
  ! grep -qE '^\.context/$' "$sandbox_project/.gitignore"

  # AC: globally installed architect.md exists and has no old .context/specs/ tracked paths
  [ -f "$sandbox_claude/agents/architect.md" ]
  ! grep -qE '\.context/specs/[^$]*-(spec|todo|requirements)' "$sandbox_claude/agents/architect.md"

  rm -rf "$sandbox_claude" "$sandbox_project"
}

@test "installer: SPEC_DIR and SPRINT_FILE constants are referenced (not just defined)" {
  # Count uses of the constants outside their definitions
  uses_spec="$(grep -c '\${SPEC_DIR}\|\$SPEC_DIR\b' "$INSTALLER" || true)"
  uses_sprint="$(grep -c '\${SPRINT_FILE}\|\$SPRINT_FILE\b' "$INSTALLER" || true)"
  # Expect at least 2 uses of each (definition + at least one consumer)
  [ "$uses_spec" -ge 2 ]
  [ "$uses_sprint" -ge 2 ]
}
