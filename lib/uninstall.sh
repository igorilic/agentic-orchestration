#!/usr/bin/env bash
# lib/uninstall.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

uninstall_global() {
  header "Uninstalling AI-native workflow"
  echo ""

  local items=(
    "$CLAUDE_DIR/hooks/session-start.sh"
    "$CLAUDE_DIR/hooks/tdd-gate.sh"
    "$CLAUDE_DIR/hooks/confidence-gate.sh"
    "$CLAUDE_DIR/scripts/confidence.sh"
    "$CLAUDE_DIR/scripts/confidence-cli.sh"
    "$CLAUDE_DIR/skills/tdd"
    "$CLAUDE_DIR/skills/ticket"
    "$CLAUDE_DIR/skills/skip-tdd"
    "$CLAUDE_DIR/skills/override-confidence"
    "$CLAUDE_DIR/skills/session-report"
    "$CLAUDE_DIR/skills/adr"
    "$CLAUDE_DIR/skills/pr"
    "$CLAUDE_DIR/skills/plan"
    "$CLAUDE_DIR/skills/clusters"
    "$CLAUDE_DIR/skills/pipeline-gitlab-feature"
    "$CLAUDE_DIR/skills/pipeline-gitlab-incident"
    "$CLAUDE_DIR/skills/pipeline-github-feature"
    "$CLAUDE_DIR/agents/requirements-engineer.md"
    "$CLAUDE_DIR/agents/architect.md"
    "$CLAUDE_DIR/agents/tdd-developer.md"
    "$CLAUDE_DIR/agents/qa.md"
    "$CLAUDE_DIR/agents/reviewer.md"
    "$CLAUDE_DIR/agents/troubleshooter.md"
  )

  for item in "${items[@]}"; do
    if [ -e "$item" ]; then
      rm -rf "$item"
      success "Removed $(echo "$item" | sed "s|$HOME|~|")"
    fi
  done

  # Don't delete settings.json or CLAUDE.md — just warn
  warn "~/.claude/settings.json and ~/.claude/CLAUDE.md preserved"
  warn "Remove hooks config from settings.json manually if needed"

  # Copilot CLI agents
  local copilot_agents=(
    "$COPILOT_DIR/agents/requirements-engineer.agent.md"
    "$COPILOT_DIR/agents/architect.agent.md"
    "$COPILOT_DIR/agents/tdd-developer.agent.md"
    "$COPILOT_DIR/agents/qa.agent.md"
    "$COPILOT_DIR/agents/reviewer.agent.md"
    "$COPILOT_DIR/agents/troubleshooter.agent.md"
  )
  for item in "${copilot_agents[@]}"; do
    if [ -e "$item" ]; then
      rm -f "$item"
      success "Removed $(echo "$item" | sed "s|$HOME|~|")"
    fi
  done

  # Remove Copilot CLI skills tree
  if [ -d "$COPILOT_SKILLS_DIR" ]; then
    rm -rf "$COPILOT_SKILLS_DIR"
    success "Removed $(echo "$COPILOT_SKILLS_DIR" | sed "s|$HOME|~|")"
  fi

  # Don't delete copilot-instructions.md or settings.json — just warn
  warn "${COPILOT_INSTRUCTIONS_FILE/$HOME/~} and ${COPILOT_SETTINGS_FILE/$HOME/~} preserved"

  echo ""
  success "Global uninstall complete"
}

uninstall_project() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  header "Uninstalling project files from: $project_dir"
  echo ""

  local items=(
    "$project_dir/.github/instructions"
    "$project_dir/.github/copilot-instructions.md"
  )

  for item in "${items[@]}"; do
    if [ -e "$item" ]; then
      rm -rf "$item"
      success "Removed $(basename "$item")"
    fi
  done

  warn "AGENTS.md, CLAUDE.md, and .context/ preserved (contain project data)"
  echo ""
  success "Project uninstall complete"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     CLI ENTRY POINT                             ║
# ╚══════════════════════════════════════════════════════════════════╝

