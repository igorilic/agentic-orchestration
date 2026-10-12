#!/usr/bin/env bash
# lib/install-global.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

# HARNESS-2: the harness is the native Claude Code / Copilot CLI agent loop plus
# two hooks, a settings policy, short instructions and a few skills. No agents.
# What earlier versions installed is retired into <home>/anw-backup/<stamp>/,
# never deleted; your own skills, agents and hooks are left alone.
RETIRED_SKILLS=(tdd skip-tdd override-confidence brainstorm pipeline-github-feature pipeline-gitlab-feature pipeline-gitlab-incident)
RETIRED_AGENTS=(requirements-engineer architect tdd-developer qa reviewer diff-reviewer troubleshooter explorer sidekick)
RETIRED_FILES=(hooks/session-start.sh hooks/tdd-gate.sh hooks/confidence-gate.sh scripts/confidence.sh scripts/confidence-cli.sh)
MANAGED_BEGIN='<!-- >>> ai-native-workflow managed block — do not edit; regenerated on install >>> -->'
MANAGED_END='<!-- <<< ai-native-workflow managed block <<< -->'
# jq, shared with uninstall: drop settings.json hook entries that run our scripts (current or retired).
ANW_JQ_STRIP='
  def ours: (.command // "") | test("hooks/(guard|verify|session-start|tdd-gate|confidence-gate)\\.sh");
  def strip: if .hooks then .hooks |= (
      with_entries(.value |= [ .[] | .hooks |= (. // [] | map(select(ours | not))) | select((.hooks | length) > 0) ])
      | with_entries(select(.value | length > 0))) else . end;'
# jq: objects merge key by key, arrays gain the missing items, policy scalars win.
ANW_JQ_UNION='
  def union($a; $b):
    if ($a | type) == "object" and ($b | type) == "object" then
      reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = union($a[$k]; $b[$k]))
    elif ($a | type) == "array" and ($b | type) == "array" then
      $a + [ $b[] | select(. as $x | any($a[]; . == $x) | not) ]
    else $b end;'
# jq: union-merge the policy ($p, hook paths rebased onto $hd) into the input.
ANW_JQ_MERGE="$ANW_JQ_UNION"'
  ($p[0] | .hooks |= walk(if type == "string" then sub("~/\\.claude/hooks"; $hd) else . end)) as $policy
  | union(strip; $policy)'

install_global() {
  header "Installing AI-native workflow (v${VERSION})"
  ANW_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  install_claude_harness
  if command -v copilot >/dev/null 2>&1; then
    install_copilot_harness
  else
    dim "Copilot CLI not found — Copilot side skipped"
  fi
  echo ""
  header "Global installation complete"
  info "Start a new Claude Code or Copilot CLI session to activate · ${BOLD}ai-native-workflow status${NC} to verify"
}

install_claude_harness() {
  header "Claude Code → ${CLAUDE_DIR/#$HOME/~}/"
  install_hooks "$CLAUDE_DIR"
  local f
  for f in "${RETIRED_FILES[@]}"; do retire "$CLAUDE_DIR" "$f"; done
  merge_claude_settings
  install_instructions "$CLAUDE_DIR" CLAUDE.md "$_ANW_SCRIPT_DIR/instructions/CLAUDE.md"
  install_skills "$CLAUDE_DIR"
  retire_agents "$CLAUDE_DIR" .md
}

install_copilot_harness() {
  header "Copilot CLI → ${COPILOT_DIR/#$HOME/~}/"
  install_hooks "$COPILOT_DIR"
  jq -n --arg g "$COPILOT_DIR/hooks/guard.sh" --arg v "$COPILOT_DIR/hooks/verify.sh" '{version: 1, hooks: {
      preToolUse: [{type: "command", bash: ("bash " + ($g | @sh)), timeoutSec: 15}],
      agentStop:  [{type: "command", bash: ("bash " + ($v | @sh)), timeoutSec: 600}]}}' > "$COPILOT_DIR/hooks/anw.json"
  success "${COPILOT_DIR/#$HOME/~}/hooks/anw.json"
  # Copilot can't exempt a command from its sandbox, so it is off: every CLI runs with your logins.
  rewrite_settings "$COPILOT_DIR" --slurpfile p "$_ANW_SCRIPT_DIR/config/copilot-settings.json" "$ANW_JQ_UNION"' union(.; $p[0])'
  success "${COPILOT_DIR/#$HOME/~}/settings.json (sandbox off, so every CLI uses your logins; your settings kept)"
  install_instructions "$COPILOT_DIR" copilot-instructions.md "$_ANW_SCRIPT_DIR/instructions/copilot-instructions.md"
  install_skills "$COPILOT_DIR"
  retire_agents "$COPILOT_DIR" .agent.md
}

# Move <home>/<rel> (file, dir or symlink) to <home>/anw-backup/<stamp>/<rel>.
retire() {
  local home="$1" rel="$2"
  [ -e "$home/$rel" ] || [ -L "$home/$rel" ] || return 0
  mkdir -p "$home/anw-backup/$ANW_STAMP/$(dirname "$rel")"
  mv "$home/$rel" "$home/anw-backup/$ANW_STAMP/$rel"
  dim "Retired ${home/#$HOME/~}/$rel → anw-backup/$ANW_STAMP/"
}

# Copy <home>/<rel> to the backup before rewriting it in place.
backup_copy() {
  local home="$1" rel="$2"
  [ -f "$home/$rel" ] || return 0
  mkdir -p "$home/anw-backup/$ANW_STAMP/$(dirname "$rel")"
  cp "$home/$rel" "$home/anw-backup/$ANW_STAMP/$rel"
}

# Hooks are copies, never links: editing this repo must not change live enforcement.
install_hooks() {
  local home="$1" f
  mkdir -p "$home/hooks"
  for f in guard.sh verify.sh; do install -m 0755 "$_ANW_SCRIPT_DIR/hooks/$f" "$home/hooks/$f"; done
  success "${home/#$HOME/~}/hooks/guard.sh, verify.sh"
}

# Skills are copies too: an edit in this repo (e.g. by an agent working here)
# goes live only via `install global`. `status` flags drift.
install_skills() {
  local home="$1" src name
  mkdir -p "$home/skills"
  for src in "$_ANW_SCRIPT_DIR"/skills/*/; do
    src="${src%/}"; name="$(basename "$src")"
    is_retired_skill "$name" && continue
    is_installed_copy "$src" "$home/skills/$name" && continue
    retire "$home" "skills/$name"
    cp -R "$src" "$home/skills/$name"
  done
  for name in "${RETIRED_SKILLS[@]}"; do retire "$home" "skills/$name"; done
  # Old installs left <skill>.bak.<ts> copies, which both tools load as duplicate skills.
  for src in "$home"/skills/*.bak.*; do
    [ -e "$src" ] || continue
    retire "$home" "skills/$(basename "$src")"
  done
  success "${home/#$HOME/~}/skills/"
}

# True if $2 is a real directory (not a link) identical to $1.
is_installed_copy() { [ ! -L "$2" ] && diff -rq "$1" "$2" >/dev/null 2>&1; }

is_retired_skill() {
  local s
  for s in "${RETIRED_SKILLS[@]}"; do [ "$s" = "$1" ] && return 0; done
  return 1
}

retire_agents() {
  local home="$1" ext="$2" a
  for a in "${RETIRED_AGENTS[@]}"; do retire "$home" "agents/$a$ext"; done
}

# The shipped file is your preamble (everything before the first "## " heading,
# seeded once) followed by the managed section (regenerated between markers).
install_instructions() {
  local home="$1" rel="$2" source="$3" target="$1/$2" managed tmp
  mkdir -p "$(dirname "$target")"
  managed="$(mktemp "${TMPDIR:-/tmp}/aw-managed-XXXXXX")"
  { echo "$MANAGED_BEGIN"; awk 'f || /^## /{f=1; print}' "$source"; echo "$MANAGED_END"; } > "$managed"
  if [ ! -f "$target" ] || cmp -s "$target" "$source"; then
    # Fresh, or an unmarked copy of exactly what we ship: write the marked form.
    backup_copy "$home" "$rel"
    { awk '/^## /{exit} {print}' "$source"; cat "$managed"; } > "$target"
  elif grep -qF "$MANAGED_BEGIN" "$target" && grep -qF "$MANAGED_END" "$target"; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/aw-instr-XXXXXX")"
    awk -v b="$MANAGED_BEGIN" -v e="$MANAGED_END" -v mf="$managed" '
      $0 == b { while ((getline l < mf) > 0) print l; close(mf); skip=1; next }
      $0 == e { skip=0; next }
      !skip   { print }' "$target" > "$tmp" && mv "$tmp" "$target"
  else
    backup_copy "$home" "$rel"
    { echo ""; cat "$managed"; } >> "$target"
    warn "${target/#$HOME/~} had no managed markers — appended the managed block (original in anw-backup/). Remove duplicated sections by hand."
  fi
  rm -f "$managed"
  success "${target/#$HOME/~}"
}

# rewrite_settings <home> <jq args…>: rewrite <home>/settings.json through a jq filter
# (a missing file reads as null); back up only on change.
rewrite_settings() {
  local home="$1" target="$1/settings.json" tmp
  shift
  tmp="$(mktemp "${TMPDIR:-/tmp}/aw-settings-XXXXXX")"
  if [ -f "$target" ]; then set -- "$@" "$target"; else set -- -n "$@"; fi
  if ! jq "$@" > "$tmp"; then
    rm -f "$tmp"; error "${target/#$HOME/~} is not valid JSON — left unchanged"; return 1
  fi
  if cmp -s "$tmp" "$target"; then rm -f "$tmp"; else backup_copy "$home" settings.json; mv "$tmp" "$target"; fi
}

# Union-merge the policy: your keys, rules and hooks survive; our hook entries
# (any version) are replaced, so re-running is a no-op. Policy scalars win.
merge_claude_settings() {
  local hooks_dir
  mkdir -p "$CLAUDE_DIR"
  # shellcheck disable=SC2088 # literal ~: Claude Code expands it, and it is what the shipped policy uses
  if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then hooks_dir='~/.claude/hooks'; else hooks_dir="$CLAUDE_DIR/hooks"; fi
  rewrite_settings "$CLAUDE_DIR" --slurpfile p "$_ANW_SCRIPT_DIR/config/claude-settings.json" --arg hd "$hooks_dir" "$ANW_JQ_STRIP$ANW_JQ_MERGE"
  success "${CLAUDE_DIR/#$HOME/~}/settings.json (policy merged; your settings kept)"
}
