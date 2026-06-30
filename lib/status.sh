#!/usr/bin/env bash
# lib/status.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

show_status() {
  header "AI-Native Workflow v${VERSION} — Installation Status"
  echo ""

  header "Global (~/.claude/)"
  check_file "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
  check_file "$CLAUDE_DIR/settings.json" "settings.json (hooks)"
  check_file "$CLAUDE_DIR/hooks/session-start.sh" "hooks/session-start.sh"
  check_file "$CLAUDE_DIR/hooks/tdd-gate.sh" "hooks/tdd-gate.sh"
  check_file "$CLAUDE_DIR/hooks/confidence-gate.sh" "hooks/confidence-gate.sh"
  check_file "$CLAUDE_DIR/scripts/confidence.sh" "scripts/confidence.sh"
  check_file "$CLAUDE_DIR/scripts/confidence-cli.sh" "scripts/confidence-cli.sh"
  check_file "$CLAUDE_DIR/skills/tdd/SKILL.md" "skills/tdd"
  check_file "$CLAUDE_DIR/skills/ticket/SKILL.md" "skills/ticket"
  check_file "$CLAUDE_DIR/skills/skip-tdd/SKILL.md" "skills/skip-tdd"
  check_file "$CLAUDE_DIR/skills/override-confidence/SKILL.md" "skills/override-confidence"
  check_file "$CLAUDE_DIR/skills/session-report/SKILL.md" "skills/session-report"
  check_file "$CLAUDE_DIR/skills/adr/SKILL.md" "skills/adr"
  check_file "$CLAUDE_DIR/skills/pr/SKILL.md" "skills/pr"
  check_file "$CLAUDE_DIR/skills/explore/SKILL.md" "skills/explore"
  check_file "$CLAUDE_DIR/skills/brainstorm/SKILL.md" "skills/brainstorm"
  check_file "$CLAUDE_DIR/skills/plan/SKILL.md" "skills/plan (orchestration)"
  check_file "$CLAUDE_DIR/skills/clusters/SKILL.md" "skills/clusters (multi-region)"
  check_file "$CLAUDE_DIR/skills/pipeline-gitlab-feature/SKILL.md" "skills/pipeline-gitlab-feature"
  check_file "$CLAUDE_DIR/skills/pipeline-gitlab-incident/SKILL.md" "skills/pipeline-gitlab-incident"
  check_file "$CLAUDE_DIR/skills/pipeline-github-feature/SKILL.md" "skills/pipeline-github-feature"
  check_file "$CLAUDE_DIR/skills/gh-cli/SKILL.md" "skills/gh-cli (PR review)"
  check_file "$CLAUDE_DIR/skills/glab-cli/SKILL.md" "skills/glab-cli (MR review)"
  check_file "$CLAUDE_DIR/skills/caveman/SKILL.md" "skills/caveman (terse mode)"
  check_file "$CLAUDE_DIR/agents/requirements-engineer.md" "agents/requirements-engineer (Opus)"
  check_file "$CLAUDE_DIR/agents/architect.md" "agents/architect (Opus)"
  check_file "$CLAUDE_DIR/agents/tdd-developer.md" "agents/tdd-developer (Sonnet)"
  check_file "$CLAUDE_DIR/agents/qa.md" "agents/qa (Opus)"
  check_file "$CLAUDE_DIR/agents/reviewer.md" "agents/reviewer (Sonnet)"
  check_file "$CLAUDE_DIR/agents/diff-reviewer.md" "agents/diff-reviewer (Opus)"
  check_file "$CLAUDE_DIR/agents/troubleshooter.md" "agents/troubleshooter (Opus)"
  check_file "$CLAUDE_DIR/agents/explorer.md" "agents/explorer (Sonnet)"

  if command -v copilot &> /dev/null || [ -d "$COPILOT_DIR/agents" ] || [ -d "$COPILOT_SKILLS_DIR" ]; then
    echo ""
    header "Copilot CLI ($COPILOT_DIR/)"
    check_file "$COPILOT_INSTRUCTIONS_FILE" "copilot-instructions.md"
    check_file "$COPILOT_SETTINGS_FILE" "settings.json"
    check_file "$COPILOT_DIR/agents/requirements-engineer.agent.md" "agents/requirements-engineer"
    check_file "$COPILOT_DIR/agents/architect.agent.md" "agents/architect"
    check_file "$COPILOT_DIR/agents/tdd-developer.agent.md" "agents/tdd-developer"
    check_file "$COPILOT_DIR/agents/qa.agent.md" "agents/qa"
    check_file "$COPILOT_DIR/agents/reviewer.agent.md" "agents/reviewer"
    check_file "$COPILOT_DIR/agents/diff-reviewer.agent.md" "agents/diff-reviewer"
    check_file "$COPILOT_DIR/agents/troubleshooter.agent.md" "agents/troubleshooter"
    check_file "$COPILOT_DIR/agents/explorer.agent.md" "agents/explorer"
    if [ -d "$COPILOT_SKILLS_DIR" ]; then
      for d in "$COPILOT_SKILLS_DIR"/*/; do
        [ -d "$d" ] || continue
        local skill_name
        skill_name="$(basename "$d")"
        check_file "$d/SKILL.md" "skills/$skill_name"
      done
    fi
  fi

  echo ""
  header "Current Directory ($(pwd))"
  check_file "AGENTS.md" "AGENTS.md"
  check_file "CLAUDE.md" "CLAUDE.md"
  check_file "$SPRINT_FILE" "docs/context/"
  check_file ".github/copilot-instructions.md" ".github/copilot-instructions.md"
  check_dir ".github/instructions" ".github/instructions/"

  if [ -f ".tdd-skip" ]; then
    warn "TDD bypass is ACTIVE"
    dim "$(cat .tdd-skip)"
  fi

  # Check for active pipeline
  if [ -f "$STATE_FILE" ]; then
    echo ""
    header "Active Pipeline"
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    echo -e "  Pipeline:     ${BOLD}${PIPELINE}${NC}"
    echo -e "  ID:           ${BOLD}${ID}${NC}"
    echo -e "  Current Step: ${BOLD}${CURRENT_STEP}${NC}"
    echo -e "  Status:       ${BOLD}${STATUS}${NC}"
    echo -e "  Last Updated: ${DIM}${TIMESTAMP}${NC}"
  fi

  echo ""
  local stacks
  stacks=$(detect_stacks ".")
  if [ -n "$stacks" ]; then
    info "Detected stacks: $(echo "$stacks" | tr '\n' ', ' | sed 's/,$//')"
  fi
  info "Platform: $(detect_platform ".")"
}

check_file() {
  local path="$1" label="$2"
  if [ -f "$path" ]; then
    success "$label"
  else
    echo -e "  ${DIM}○${NC} ${DIM}$label (missing)${NC}"
  fi
}

check_dir() {
  local path="$1" label="$2"
  if [ -d "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" ]; then
    local count
    count=$(ls -1 "$path" 2>/dev/null | wc -l | tr -d ' ')
    success "$label ($count files)"
  else
    echo -e "  ${DIM}○${NC} ${DIM}$label (empty/missing)${NC}"
  fi
}

show_detect() {
  local project_dir="${1:-.}"
  header "Stack Detection: $project_dir"
  echo ""

  local stacks
  stacks=$(detect_stacks "$project_dir")

  if [ -z "$stacks" ]; then
    warn "No stacks detected"
    return
  fi

  while IFS= read -r stack; do
    case "$stack" in
      dotnet)       info ".NET — xUnit + FluentAssertions + NSubstitute" ;;
      go)           info "Go — testing + testify (table-driven)" ;;
      rust)         info "Rust — built-in + tokio-test" ;;
      python)       info "Python — pytest + Pydantic" ;;
      react-ts)
        local tr e2e
        tr=$(detect_test_runner "$project_dir")
        e2e=$(detect_e2e_runner "$project_dir")
        info "React/TypeScript — ${tr:-Vitest} + Testing Library${e2e:+ + $e2e}"
        ;;
      react-native) info "React Native — Jest + RNTL + Detox" ;;
      typescript)   info "TypeScript/Node" ;;
      swift)        info "Swift — XCTest + MVVM" ;;
    esac
  done <<< "$stacks"

  echo ""
  info "Platform: $(detect_platform "$project_dir")"
}

