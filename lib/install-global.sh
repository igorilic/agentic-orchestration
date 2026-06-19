#!/usr/bin/env bash
# lib/install-global.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

install_global() {
  header "Installing AI-native workflow (v${VERSION})"
  echo ""

  # --- CLAUDE.md ---
  install_global_claude_md

  # --- settings.json (hooks) ---
  install_global_settings

  # --- Hook scripts ---
  install_global_hooks

  # --- Scripts ---
  install_global_scripts

  # --- Skills ---
  install_global_skills

  # --- Agents ---
  install_global_agents

  # --- Copilot CLI agents ---
  install_copilot_agents

  # --- Copilot CLI skills ---
  install_global_copilot_skills

  # --- Copilot CLI global instructions ---
  install_global_copilot_instructions

  # --- Copilot CLI settings ---
  install_global_copilot_settings

  echo ""
  header "Global installation complete"
  echo ""
  info "Claude Code → ${CLAUDE_DIR}/"
  if command -v copilot >/dev/null 2>&1; then
    info "Copilot CLI → ${COPILOT_DIR/$HOME/~}/"
    dim "   Items written:"
    dim "     agents/                   agent definitions"
    dim "     skills/                   skill definitions"
    dim "     copilot-instructions.md"
    dim "     settings.json"
  else
    dim "Copilot CLI not found — Copilot-side artifacts skipped"
  fi
  info "Run ${BOLD}ai-native-workflow status${NC} to verify"
  info "Start a new Claude Code or Copilot CLI session to activate"
  echo ""
  dim "▸ Copilot hooks are NOT installed globally — Copilot CLI scopes"
  dim "  hooks per-repo. Run \`ai-native-workflow install project\` in"
  dim "  trusted folders for repo-level hooks (COP-2; not yet shipped)."
}

install_global_claude_md() {
  local target="$CLAUDE_DIR/CLAUDE.md"
  mkdir -p "$CLAUDE_DIR"

  # CLAUDE.md is split into a user-owned preamble (Identity / Personal
  # Preferences — seeded once, never overwritten) and an installer-managed
  # block (skills, pipelines, agents, stack detection) wrapped in markers and
  # regenerated on every install. This stops re-install from clobbering a
  # user's customised CLAUDE.md (issue #12).
  local begin='<!-- >>> ai-native-workflow managed block — do not edit; regenerated on install >>> -->'
  local end='<!-- <<< ai-native-workflow managed block <<< -->'

  local managed_temp
  managed_temp="$(mktemp /tmp/aw-claudemd-XXXXXX.md)"
  {
    echo "$begin"
    cat << 'MANAGED_EOF'
## Available Global Skills
- /plan — Start new work (orchestrates full agent pipeline)
- /tdd — Strict TDD workflow (RED → GREEN → REFACTOR)
- /ticket — Jira/GitHub issue → spec + test scaffold
- /skip-tdd — Bypass TDD gate with logged reason
- /session-report — Obsidian session report
- /adr — Architecture Decision Record (repo + Confluence)
- /pr — Create PR/MR (auto-detects gh/glab)
- /gh-cli · /glab-cli — review a PR/MR diff (inline comments + threads)
- /caveman — ultra-terse "caveman speak" replies (token-saver; slash-only)

Plus the **diff-reviewer** agent (Opus-tier) — whole-PR/MR review: quality,
correctness, security, landmines. It previews findings, then (on your
confirm) posts severity-ranked inline comments + threads with a verdict.
Invoke after a PR/MR exists: `Use diff-reviewer to review PR #<n>`.

## Pipelines (CLI)
Run full agent pipelines from the terminal:
- `ai-native-workflow run gitlab-feature PROJ-123` — Copilot CLI + Jira → MR
- `ai-native-workflow run gitlab-incident PROJ-456` — Troubleshooter + Jira → MR
- `ai-native-workflow run github-feature specs.md` — Claude Code → GitHub issue → PR

## Agent Pipeline
All new work starts with `/plan`. The pipeline:
1. **requirements-engineer** (Opus-tier) — elicits & formalizes requirements
2. **architect** (Opus-tier) — designs spec + atomic todo plan
3. **tdd-developer** (Sonnet-tier) — implements one step via TDD
4. **qa** (Haiku-tier) — runs affected tests
5. **reviewer** (Sonnet-tier) — reviews code, user triages findings
Max 3 fix loops per step, then remaining issues go to tech debt.

For production incidents, use **troubleshooter** (Opus-tier):
- Pulls Jira ticket, ArgoCD logs, Azure Application Insights
- Produces diagnosis + TDD fix plan for tdd-developer

## Stack Detection
Detect the active stack from project files and auto-apply conventions:
- `*.csproj` or `*.sln` → .NET (xUnit, FluentAssertions, NSubstitute)
- `go.mod` → Go (testing + testify, table-driven)
- `Cargo.toml` → Rust (built-in + tokio-test, axum)
- `pyproject.toml` or `requirements.txt` → Python (pytest, Pydantic)
- `package.json` with react → React/TS (Vitest + Testing Library)
- `package.json` with react-native → React Native (Jest + RNTL)
- `Package.swift` or `*.xcodeproj` → Swift (XCTest)
MANAGED_EOF
    echo "$end"
  } > "$managed_temp"

  if [ ! -f "$target" ]; then
    # Fresh install: seed the user preamble once, then the managed block.
    {
      cat << 'PREAMBLE_EOF'
# Global Claude Code Defaults

## Identity
- Solo full-stack developer
- Shell: fish (macOS)
- CLI tools: glab, gh, kubectl, az, docker, make

## Personal Preferences
- Commit messages: Conventional Commits
- Always explain before making destructive changes
- Prefer asking over assuming

PREAMBLE_EOF
      cat "$managed_temp"
    } > "$target"
    rm -f "$managed_temp"
    success "~/.claude/CLAUDE.md (seeded)"
    return 0
  fi

  if grep -qF "$begin" "$target" && grep -qF "$end" "$target"; then
    # Markers present: replace ONLY the managed region, preserving everything
    # else (including a user-customised preamble) verbatim.
    local out_temp
    out_temp="$(mktemp /tmp/aw-claudemd-out-XXXXXX.md)"
    awk -v begin="$begin" -v end="$end" -v mf="$managed_temp" '
      $0 == begin { while ((getline line < mf) > 0) print line; close(mf); skip=1; next }
      $0 == end   { skip=0; next }
      skip != 1   { print }
    ' "$target" > "$out_temp"
    mv "$out_temp" "$target"
    rm -f "$managed_temp"
    success "~/.claude/CLAUDE.md (managed block updated)"
    return 0
  fi

  # Legacy file, no markers: never clobber. Back it up, append a managed block,
  # and warn that the old unmarked copy may now be duplicated.
  backup_if_exists "$target"
  {
    echo ""
    cat "$managed_temp"
  } >> "$target"
  rm -f "$managed_temp"
  warn "~/.claude/CLAUDE.md had no managed markers — appended one and backed up the original. If you see duplicated 'Available Global Skills'/'Stack Detection' sections, delete the older unmarked copy; future installs update only the marked block."
}

install_global_settings() {
  local target="$CLAUDE_DIR/settings.json"

  # If settings.json exists, merge hooks into it
  if [ -f "$target" ]; then
    backup_if_exists "$target"

    # Check if jq is available for merging
    if command -v jq &> /dev/null; then
      local hooks_json
      hooks_json=$(cat << 'HOOKS_JSON_EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tdd-gate.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/confidence-gate.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code needs your attention\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
HOOKS_JSON_EOF
      )
      # Deep merge: existing settings + new hooks
      # Union PreToolUse entries by matcher, and within each matcher union hooks
      # by .command, so user matchers and hooks are preserved on re-install.
      # ALL three installer hook types (PreToolUse, SessionStart, Notification)
      # are concat-merged the same way, so a user-customised hook of any type
      # survives re-install instead of being silently replaced (issue #12).
      local new_temp
      new_temp="$(mktemp /tmp/aw-hooks-new-XXXXXX.json)"
      echo "$hooks_json" > "$new_temp"
      jq -s '
        . as [$existing, $new] |
        ($existing * $new) as $merged |
        reduce ["PreToolUse","SessionStart","Notification"][] as $k ($merged;
          .hooks[$k] = (
            (($existing.hooks[$k] // []) + ($new.hooks[$k] // []))
            | group_by(.matcher)
            | map({
                matcher: .[0].matcher,
                hooks: (map(.hooks) | add | unique_by(.command))
              })
          )
        )
      ' "$target" "$new_temp" > "${target}.tmp"
      rm -f "$new_temp"
      mv "${target}.tmp" "$target"
      success "~/.claude/settings.json (merged hooks into existing)"
    else
      warn "jq not found — cannot merge settings.json safely"
      warn "Please manually add hooks from the backup file"
      # Write to a separate file for manual merging
      cat > "${target}.hooks-to-merge.json" << 'HOOKS_MERGE_EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tdd-gate.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/confidence-gate.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code needs your attention\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
HOOKS_MERGE_EOF
      warn "Hooks written to ${target}.hooks-to-merge.json"
    fi
  else
    # No existing settings — write fresh
    mkdir -p "$CLAUDE_DIR"
    cat > "$target" << 'SETTINGS_EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tdd-gate.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/confidence-gate.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code needs your attention\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
    success "~/.claude/settings.json (created fresh)"
  fi
}

install_global_hooks() {
  mkdir -p "$CLAUDE_DIR/hooks"

  # --- session-start.sh ---
  cat > "$CLAUDE_DIR/hooks/session-start.sh" << 'SESSION_START_EOF'
#!/usr/bin/env bash
# Injects project context into Claude Code session on start
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CONTEXT=""

detect_stack() {
  local stack=""
  if compgen -G "$PROJECT_DIR"/*.sln > /dev/null 2>&1 || \
     find "$PROJECT_DIR" -maxdepth 3 -name "*.csproj" -print -quit 2>/dev/null | grep -q . 2>/dev/null; then
    stack="dotnet (xUnit + FluentAssertions)"
  elif [ -f "$PROJECT_DIR/go.mod" ]; then
    stack="go (testing + testify)"
  elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
    stack="rust (built-in + tokio-test)"
  elif [ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/requirements.txt" ]; then
    stack="python (pytest)"
  elif [ -f "$PROJECT_DIR/package.json" ]; then
    if grep -q '"react-native"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      stack="react-native (Jest + RNTL, E2E: Detox)"
    elif grep -q '"react"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      local tr="Vitest" e2e=""
      grep -q '"jest"' "$PROJECT_DIR/package.json" 2>/dev/null && tr="Jest"
      grep -q '"playwright"' "$PROJECT_DIR/package.json" 2>/dev/null && e2e=", E2E: Playwright"
      grep -q '"cypress"' "$PROJECT_DIR/package.json" 2>/dev/null && e2e=", E2E: Cypress"
      stack="react-ts ($tr + Testing Library$e2e)"
    else
      stack="typescript"
    fi
  elif [ -f "$PROJECT_DIR/Package.swift" ] || compgen -G "$PROJECT_DIR"/*.xcodeproj > /dev/null 2>&1; then
    stack="swift (XCTest)"
  fi
  echo "$stack"
}

STACK=$(detect_stack)
[ -n "$STACK" ] && CONTEXT="📦 Detected stack: $STACK\n"

if [ -f "$PROJECT_DIR/$SPRINT_FILE" ]; then
  SPRINT=$(head -20 "$PROJECT_DIR/$SPRINT_FILE")
  CONTEXT="${CONTEXT}\n📋 Current Sprint:\n${SPRINT}\n"
fi

if git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  RECENT=$(git -C "$PROJECT_DIR" log --oneline -5 2>/dev/null || echo "No commits yet")
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "detached")
  DIRTY=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  CONTEXT="${CONTEXT}\n🌿 Branch: ${BRANCH}"
  [ "$DIRTY" -gt 0 ] && CONTEXT="${CONTEXT} (${DIRTY} uncommitted changes)"
  CONTEXT="${CONTEXT}\n📝 Recent commits:\n${RECENT}\n"
fi

if [ -f "$PROJECT_DIR/.tdd-skip" ]; then
  REASON=$(grep "^Reason:" "$PROJECT_DIR/.tdd-skip" 2>/dev/null | sed 's/^Reason: //' || echo "unknown")
  CONTEXT="${CONTEXT}\n⚠️ TDD bypass ACTIVE — Reason: ${REASON}\n"
fi

if [ -f "$PROJECT_DIR/.gitlab-ci.yml" ]; then
  CONTEXT="${CONTEXT}\n🏢 Platform: GitLab (use glab for MRs)\n"
elif [ -d "$PROJECT_DIR/.github" ]; then
  CONTEXT="${CONTEXT}\n🐙 Platform: GitHub (use gh for PRs)\n"
fi

# Check for active pipeline
if [ -f "$PROJECT_DIR/.context/.pipeline-state" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/.context/.pipeline-state"
  CONTEXT="${CONTEXT}\n🔄 Active pipeline: ${PIPELINE} (${ID}) — step ${CURRENT_STEP} (${STATUS})\n"
fi

[ -f "$PROJECT_DIR/AGENTS.md" ] && CONTEXT="${CONTEXT}\n📖 Read AGENTS.md for project rules.\n"

echo -e "$CONTEXT"
SESSION_START_EOF
  chmod +x "$CLAUDE_DIR/hooks/session-start.sh"
  success "~/.claude/hooks/session-start.sh"

  # --- tdd-gate.sh ---
  cat > "$CLAUDE_DIR/hooks/tdd-gate.sh" << 'TDD_GATE_EOF'
#!/usr/bin/env bash
# Blocks git commits without test files. Exit code 2 = block action.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"

# Only gate git commit
echo "$TOOL_INPUT" | grep -qE 'git\s+commit' || exit 0

# Allow amend
echo "$TOOL_INPUT" | grep -qE -- '--amend' && exit 0

# Check bypass
if [ -f "$PROJECT_DIR/.tdd-skip" ]; then
  echo "⚠️ TDD bypass active — commit allowed." >&2
  exit 0
fi

# Spike-only commits skip the TDD gate. Commits that touch any path
# outside spikes/ fall through to the test-files check below.
STAGED_FILES=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null || true)
NON_SPIKE_FILES=$(echo "$STAGED_FILES" | grep -v '^spikes/' | grep -v '^$' || true)
if [ -n "$STAGED_FILES" ] && [ -z "$NON_SPIKE_FILES" ]; then
  echo "🧪 Spike-only commit (spikes/ paths only) — TDD gate skipped." >&2
  exit 0
fi

# Check for test files in staged changes
TEST_PATTERNS='(test|spec|_test\.|\.test\.|\.spec\.|tests/|__tests__/|Tests/|Test\.)'
TEST_FILES=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | grep -iE "$TEST_PATTERNS" || true)

if [ -z "$TEST_FILES" ]; then
  echo "🚫 TDD GATE: No test files in staged changes." >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  1. Write tests first, stage them, commit together" >&2
  echo "  2. /skip-tdd 'reason' to bypass (logged)" >&2
  echo "" >&2
  echo "Common reasons: 'docs-only' | 'CI config' | 'dependency update' | 'hotfix'" >&2
  exit 2
fi

TEST_COUNT=$(echo "$TEST_FILES" | wc -l | tr -d ' ')
echo "✅ TDD gate passed: $TEST_COUNT test file(s)." >&2
exit 0
TDD_GATE_EOF
  chmod +x "$CLAUDE_DIR/hooks/tdd-gate.sh"
  success "~/.claude/hooks/tdd-gate.sh"

  # --- confidence-gate.sh ---
  cp "$_ANW_SCRIPT_DIR/hooks/confidence-gate.sh" "$CLAUDE_DIR/hooks/confidence-gate.sh"
  chmod +x "$CLAUDE_DIR/hooks/confidence-gate.sh"
  success "~/.claude/hooks/confidence-gate.sh"
}

install_global_scripts() {
  header "Installing scripts"

  mkdir -p "$CLAUDE_DIR/scripts"

  cp "$_ANW_SCRIPT_DIR/scripts/confidence.sh" "$CLAUDE_DIR/scripts/confidence.sh"
  chmod +x "$CLAUDE_DIR/scripts/confidence.sh"
  success "~/.claude/scripts/confidence.sh"

  cp "$_ANW_SCRIPT_DIR/scripts/confidence-cli.sh" "$CLAUDE_DIR/scripts/confidence-cli.sh"
  chmod +x "$CLAUDE_DIR/scripts/confidence-cli.sh"
  success "~/.claude/scripts/confidence-cli.sh"
}

install_global_skills() {
  header "Installing skills"

  mkdir -p "$CLAUDE_DIR/skills"

  # Copy every non-pipeline skill from source so the installed copy never
  # drifts from skills/<name>/ (single source of truth — issue #8). Pipeline
  # skills get Claude-flavored abbreviated stubs below.
  local skill_src skill_name
  for skill_src in "$_ANW_SCRIPT_DIR/skills"/*/; do
    [ -d "$skill_src" ] || continue
    skill_name="$(basename "$skill_src")"
    case "$skill_name" in pipeline-*) continue ;; esac
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    cp -R "$skill_src". "$CLAUDE_DIR/skills/$skill_name/"
    success "/$skill_name skill"
  done

  # --- Pipeline skills (reference only, actual execution is via CLI) ---
  mkdir -p "$CLAUDE_DIR/skills/pipeline-gitlab-feature"
  cat > "$CLAUDE_DIR/skills/pipeline-gitlab-feature/SKILL.md" << 'SKILL_EOF'
---
name: pipeline-gitlab-feature
description: >
  GitLab feature development pipeline. Run from CLI:
  ai-native-workflow run gitlab-feature <JIRA-ID>
  Jira → requirements-engineer → qa (test plan) → architect →
  tdd-developer → qa → reviewer → MR, then a manual diff-reviewer pass.
disable-model-invocation: true
---

## GitLab Feature Pipeline

Run from terminal: `ai-native-workflow run gitlab-feature <JIRA-ID>`

This pipeline uses Copilot CLI agents and requires: copilot, glab, Jira MCP.
See `ai-native-workflow help` for details.

### Manual agent invocations (Claude Code)
```bash
claude --agent=requirements-engineer --prompt "Analyze Jira ticket PROJ-123"
claude --agent=architect --prompt "Design solution for PROJ-123"
claude --agent=tdd-developer --prompt "Step 1 of PROJ-123-todo.md"
claude --agent=reviewer --prompt "Review Step 1 of PROJ-123"
claude --agent=diff-reviewer --prompt "Review MR !12 for PROJ-123"
```
SKILL_EOF
  success "/pipeline-gitlab-feature skill"

  mkdir -p "$CLAUDE_DIR/skills/pipeline-gitlab-incident"
  cat > "$CLAUDE_DIR/skills/pipeline-gitlab-incident/SKILL.md" << 'SKILL_EOF'
---
name: pipeline-gitlab-incident
description: >
  GitLab incident response pipeline. Run from CLI:
  ai-native-workflow run gitlab-incident <JIRA-ID>
  Jira → troubleshooter → user decides (document or fix) →
  tdd-developer → qa → reviewer → MR.
disable-model-invocation: true
---

## GitLab Incident Pipeline

Run from terminal: `ai-native-workflow run gitlab-incident <JIRA-ID>`

This pipeline uses Copilot CLI agents and requires: copilot, glab, az, kubectl.
See `ai-native-workflow help` for details.
SKILL_EOF
  success "/pipeline-gitlab-incident skill"

  mkdir -p "$CLAUDE_DIR/skills/pipeline-github-feature"
  cat > "$CLAUDE_DIR/skills/pipeline-github-feature/SKILL.md" << 'SKILL_EOF'
---
name: pipeline-github-feature
description: >
  GitHub feature development pipeline. Run from CLI:
  ai-native-workflow run github-feature [specs-file]
  specs.md/input → requirements-engineer → GitHub issue → architect →
  tdd-developer → qa → reviewer → PR, then a manual diff-reviewer pass.
disable-model-invocation: true
---

## GitHub Feature Pipeline

Run from terminal: `ai-native-workflow run github-feature [specs-file]`

This pipeline uses Claude Code agents and requires: claude, gh.
See `ai-native-workflow help` for details.
SKILL_EOF
  success "/pipeline-github-feature skill"
}

install_global_agents() {
  header "Installing agents"

  mkdir -p "$CLAUDE_DIR/agents"

  # Copy every Claude Code agent from source (single source of truth — the
  # installed copy can never drift from agents/claude-code/<name>.md, issue #8).
  local agent_src agent_name
  for agent_src in "$_ANW_SCRIPT_DIR/agents/claude-code"/*.md; do
    [ -f "$agent_src" ] || continue
    agent_name="$(basename "$agent_src")"
    cp "$agent_src" "$CLAUDE_DIR/agents/$agent_name"
    success "${agent_name%.md} agent"
  done
}

install_copilot_agents() {
  # Check if copilot CLI is installed
  if ! command -v copilot &> /dev/null; then
    dim "Copilot CLI not found — skipping Copilot agent installation"
    dim "Install with: npm install -g @github/copilot"
    return
  fi

  header "Installing Copilot CLI agents"

  mkdir -p "$COPILOT_AGENTS_DIR"

  # Copy every Copilot agent from source (single source of truth — issue #8).
  local agent_src agent_name
  for agent_src in "$_ANW_SCRIPT_DIR/agents/copilot-cli"/*.agent.md; do
    [ -f "$agent_src" ] || continue
    agent_name="$(basename "$agent_src")"
    cp "$agent_src" "$COPILOT_AGENTS_DIR/$agent_name"
    success "$agent_name"
  done

  info "Copilot CLI agents installed to: $COPILOT_DIR/agents/"
  dim "Use: copilot --agent=architect --prompt \"...\""
  dim " or: /agent in interactive mode"
}

install_global_copilot_skills() {
  command -v copilot &>/dev/null || return 0

  header "Installing Copilot CLI skills"

  mkdir -p "$COPILOT_SKILLS_DIR"

  for skill_src_dir in "$_ANW_SCRIPT_DIR/skills"/*/; do
    local skill_name
    skill_name="$(basename "$skill_src_dir")"
    local skill_dest_dir="$COPILOT_SKILLS_DIR/$skill_name"
    if [ -d "$skill_dest_dir" ]; then
      local ts
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      cp -R "$skill_dest_dir" "${skill_dest_dir}.bak.${ts}"
    fi
    mkdir -p "$skill_dest_dir"
    cp -R "$skill_src_dir". "$skill_dest_dir/"
    success "$skill_name skill"
  done

  # Rewrite any claude --agent= references to copilot --agent= in the
  # installed copies. Uses .tmp suffix for cross-platform sed -i portability
  # (BSD macOS vs GNU Linux both require an explicit backup extension).
  for skill_md in "$COPILOT_SKILLS_DIR"/*/SKILL.md; do
    if grep -q 'claude --agent=' "$skill_md" 2>/dev/null; then
      sed -i.tmp 's/claude --agent=/copilot --agent=/g' "$skill_md"
      rm -f "${skill_md}.tmp"
    fi
  done
}

install_global_copilot_instructions() {
  command -v copilot &>/dev/null || return 0

  local target="$COPILOT_INSTRUCTIONS_FILE"
  mkdir -p "$COPILOT_DIR"
  backup_if_exists "$target"

  cat > "$target" << 'COPILOT_INSTRUCTIONS_EOF'
# Global Copilot CLI Defaults

## Identity
- Solo full-stack developer
- Shell: fish (macOS)
- CLI tools: glab, gh, kubectl, az, docker, make

## Personal Preferences
- Commit messages: Conventional Commits
- Always explain before making destructive changes
- Prefer asking over assuming

## Available Global Skills
- /plan — Start new work (orchestrates full Agent Pipeline)
- /tdd — Strict TDD workflow (RED → GREEN → REFACTOR)
- /ticket — Jira/GitHub issue → spec + test scaffold
- /skip-tdd — Bypass TDD gate with logged reason
- /session-report — Obsidian session report
- /adr — Architecture Decision Record (repo + Confluence)
- /pr — Create PR/MR (auto-detects gh/glab)
- /gh-cli · /glab-cli — review a PR/MR diff (inline comments + threads)

Plus the **diff-reviewer** agent (Opus-tier) — whole-PR/MR review: quality,
correctness, security, landmines. It previews findings, then (on your
confirm) posts severity-ranked inline comments + threads with a verdict.
Invoke after a PR/MR exists: `copilot --agent=diff-reviewer --prompt "Review MR !<iid>"`.

## Pipelines (CLI)
Run full agent pipelines from the terminal:
- `ai-native-workflow run gitlab-feature PROJ-123` — Copilot CLI + Jira → MR
- `ai-native-workflow run gitlab-incident PROJ-456` — Troubleshooter + Jira → MR
- `ai-native-workflow run github-feature specs.md` — GitHub issue → PR

## Agent Pipeline
All new work starts with `/plan`. The pipeline:
1. **requirements-engineer** (Opus-tier) — elicits & formalizes requirements
2. **architect** (Opus-tier) — designs spec + atomic todo plan
3. **tdd-developer** (Sonnet-tier) — implements one step via TDD
4. **qa** (Haiku-tier) — runs affected tests
5. **reviewer** (Sonnet-tier) — reviews code, user triages findings
Max 3 fix loops per step, then remaining issues go to tech debt.

For production incidents, use **troubleshooter** (Opus-tier):
- Pulls Jira ticket, ArgoCD logs, Azure Application Insights
- Produces diagnosis + TDD fix plan for tdd-developer

## Stack Detection
Detect the active stack from project files and auto-apply conventions:
- `*.csproj` or `*.sln` → .NET (xUnit, FluentAssertions, NSubstitute)
- `go.mod` → Go (testing + testify, table-driven)
- `Cargo.toml` → Rust (built-in + tokio-test, axum)
- `pyproject.toml` or `requirements.txt` → Python (pytest, Pydantic)
- `package.json` with react → React/TS (Vitest + Testing Library)
- `package.json` with react-native → React Native (Jest + RNTL)
- `Package.swift` or `*.xcodeproj` → Swift (XCTest)
COPILOT_INSTRUCTIONS_EOF
  success "${COPILOT_INSTRUCTIONS_FILE/$HOME/~}"
}

install_global_copilot_settings() {
  command -v copilot &>/dev/null || return 0

  local fresh_json='{"renderMarkdown": true, "theme": "auto", "beep": true}'

  # Fresh install path — target does not exist yet
  if [ ! -f "$COPILOT_SETTINGS_FILE" ]; then
    mkdir -p "$COPILOT_DIR"
    if command -v jq &>/dev/null; then
      echo "$fresh_json" | jq '.' > "$COPILOT_SETTINGS_FILE"
    else
      echo "$fresh_json" > "$COPILOT_SETTINGS_FILE"
    fi
    success "${COPILOT_SETTINGS_FILE/$HOME/~} (fresh install with beep:true)"
    return
  fi

  # Merge path — target already exists; preserve user keys, fill gaps
  backup_if_exists "$COPILOT_SETTINGS_FILE"

  if ! command -v jq &>/dev/null; then
    warn "jq not found — leaving ${COPILOT_SETTINGS_FILE/$HOME/~} untouched"
    return
  fi

  # Additive merge: defaults first, existing user keys win.
  # `$defaults * $existing[0]` means existing values overwrite defaults.
  echo "$fresh_json" \
    | jq --slurpfile existing "$COPILOT_SETTINGS_FILE" \
         '. * $existing[0]' \
    > "$COPILOT_SETTINGS_FILE.tmp"
  mv "$COPILOT_SETTINGS_FILE.tmp" "$COPILOT_SETTINGS_FILE"
  success "${COPILOT_SETTINGS_FILE/$HOME/~} (merged with existing)"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     PROJECT INSTALLATION                        ║
# ╚══════════════════════════════════════════════════════════════════╝

