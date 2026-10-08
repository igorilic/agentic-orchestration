#!/usr/bin/env bash
# lib/uninstall.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

# Inverse of install global, limited to what we own: hook files, hook wiring and
# skill links. Your skills, agents, hooks, instructions and anw-backup/ stay.
uninstall_global() {
  header "Uninstalling AI-native workflow"
  echo ""
  # shellcheck disable=SC2034 # read by backup_copy (install-global module)
  ANW_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  # Unwire before deleting: an entry pointing at a missing guard.sh blocks every tool call.
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    rewrite_settings "$ANW_JQ_STRIP"' strip | if .hooks == {} then del(.hooks) else . end'
    success "Removed our hook entries from ${CLAUDE_DIR/#$HOME/~}/settings.json"
  fi
  rm -f "$COPILOT_DIR/hooks/anw.json"
  local home src name
  for home in "$CLAUDE_DIR" "$COPILOT_DIR"; do
    rm -f "$home/hooks/guard.sh" "$home/hooks/verify.sh"
    for src in "$_ANW_SCRIPT_DIR"/skills/*/; do
      src="${src%/}"; name="$(basename "$src")"
      if is_installed_copy "$src" "$home/skills/$name"; then rm -rf "${home:?}/skills/$name"
      elif [ -e "$home/skills/$name" ]; then warn "Kept ${home/#$HOME/~}/skills/$name: it differs from this version"; fi
    done
    success "Removed hooks and unmodified skills from ${home/#$HOME/~}"
  done
  warn "Kept: CLAUDE.md / copilot-instructions.md (delete the managed block by hand), the permission and sandbox policy in settings.json (pre-install copy in anw-backup/), and anw-backup/"
  echo ""
  success "Global uninstall complete"
}

uninstall_project() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  header "Uninstalling project files from: $project_dir"
  echo ""

  remove_legacy_copilot_hooks "$project_dir"
  # Everything else may carry your edits, so it stays.
  warn "Kept: AGENTS.md, CLAUDE.md, .github/ instructions, docs/ and .anw/verify. Delete .anw/verify to stop the end-of-session check here."
  echo ""
  success "Project uninstall complete"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     CLI ENTRY POINT                             ║
# ╚══════════════════════════════════════════════════════════════════╝

