#!/usr/bin/env bash
# lib/uninstall.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

# Strip the installer's own hook entries from settings.json — the true inverse
# of install_global_settings' additive merge. User-added hooks (any command we
# didn't install) and every other matcher/key are preserved (#17.4).
remove_global_hooks_from_settings() {
  local target="$CLAUDE_DIR/settings.json"
  [ -f "$target" ] || return 0
  if ! command -v jq &>/dev/null; then
    warn "jq not found — installer hooks left in settings.json (remove manually)"
    return 0
  fi
  backup_if_exists "$target"
  local tmp
  tmp="$(mktemp /tmp/aw-uninstall-settings-XXXXXX.json)"
  # For each installer hook type, drop hooks whose command matches one we wrote,
  # then drop now-empty matcher groups and now-empty hook-type arrays.
  jq '
    def strip($k; $pats):
      if (.hooks // {} | has($k)) then
        .hooks[$k] = ([ .hooks[$k][]
          | .hooks = [ .hooks[]? | select((.command // "") as $c
              | ($pats | any(. as $p | $c | contains($p))) | not) ]
          | select((.hooks | length) > 0) ])
        | (if (.hooks[$k] | length) == 0 then .hooks |= del(.[$k]) else . end)
      else . end;
    strip("PreToolUse";   ["tdd-gate.sh", "confidence-gate.sh"])
    | strip("SessionStart"; ["session-start.sh"])
    | strip("Notification"; ["Claude Code needs your attention"])
    | (if (.hooks // {} | length) == 0 then del(.hooks) else . end)
  ' "$target" > "$tmp" && mv "$tmp" "$target" \
    && success "Cleaned installer hooks from ${target/#$HOME/~} (user hooks kept)" \
    || { rm -f "$tmp"; warn "Could not rewrite ${target/#$HOME/~}; left unchanged"; }
}

uninstall_global() {
  header "Uninstalling AI-native workflow"
  echo ""

  # Fixed set: hook scripts + confidence tooling the installer writes.
  local items=(
    "$CLAUDE_DIR/hooks/session-start.sh"
    "$CLAUDE_DIR/hooks/tdd-gate.sh"
    "$CLAUDE_DIR/hooks/confidence-gate.sh"
    "$CLAUDE_DIR/scripts/confidence.sh"
    "$CLAUDE_DIR/scripts/confidence-cli.sh"
  )
  # Agents + skills are derived from the source tree so the removal list can
  # never go stale as new agents/skills are added (#17.4 — previously this list
  # was hand-maintained and leaked diff-reviewer, explorer, gh-cli, etc.).
  local src
  for src in "$_ANW_SCRIPT_DIR"/agents/claude-code/*.md; do
    [ -e "$src" ] || continue
    items+=("$CLAUDE_DIR/agents/$(basename "$src")")
  done
  for src in "$_ANW_SCRIPT_DIR"/skills/*/; do
    [ -e "$src" ] || continue
    items+=("$CLAUDE_DIR/skills/$(basename "$src")")
  done

  local item
  for item in "${items[@]}"; do
    if [ -e "$item" ]; then
      rm -rf "$item"
      success "Removed ${item/#$HOME/~}"
    fi
  done

  # Remove the installer's hook entries from settings.json (the actual fix —
  # otherwise settings.json keeps pointing at the hook scripts we just deleted).
  remove_global_hooks_from_settings
  # CLAUDE.md is preserved on purpose: its managed-block markers let a re-install
  # cleanly region-replace it, and the user preamble is theirs to keep.
  warn "${CLAUDE_DIR/#$HOME/~}/CLAUDE.md preserved (managed block updates on re-install)"

  # Copilot CLI agents — also derived from source so they don't leak.
  if [ -d "$COPILOT_AGENTS_DIR" ]; then
    for src in "$_ANW_SCRIPT_DIR"/agents/copilot-cli/*.agent.md; do
      [ -e "$src" ] || continue
      local cot="$COPILOT_AGENTS_DIR/$(basename "$src")"
      if [ -e "$cot" ]; then rm -f "$cot"; success "Removed ${cot/#$HOME/~}"; fi
    done
  fi

  # Remove Copilot CLI skills tree
  if [ -d "$COPILOT_SKILLS_DIR" ]; then
    rm -rf "$COPILOT_SKILLS_DIR"
    success "Removed ${COPILOT_SKILLS_DIR/#$HOME/~}"
  fi

  # Copilot instructions/settings have no marker system and may carry user
  # edits — preserve them (Copilot settings get no installer hooks).
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

