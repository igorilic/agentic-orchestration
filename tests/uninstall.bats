#!/usr/bin/env bats

# uninstall global must be a true inverse of install global (issue #17 part 4):
#  - remove ALL installed agents/skills (the list is derived from source, so it
#    can't go stale and leak diff-reviewer/explorer/caveman/etc. as it used to),
#  - strip the installer's hook entries from settings.json (no dangling refs to
#    deleted hook scripts), while preserving any user-added hooks.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-uninstall-XXXXXX)"
  STUB="$(mktemp -d /tmp/aw-uninstall-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/copilot"; chmod +x "$STUB/copilot"
  CL="$SANDBOX/claude"
  CO="$SANDBOX/copilot"
}

teardown() { rm -rf "$SANDBOX" "$STUB"; }

_install() {
  PATH="$STUB:$PATH" CLAUDE_HOME="$CL" COPILOT_HOME="$CO" \
    "$INSTALLER" install global >/dev/null 2>&1
}
_uninstall() {
  PATH="$STUB:$PATH" CLAUDE_HOME="$CL" COPILOT_HOME="$CO" \
    "$INSTALLER" uninstall global >/dev/null 2>&1
}

# --- agents/skills are fully removed (no stale-list leaks) ---

@test "uninstall: removes every Claude agent, including diff-reviewer + explorer" {
  _install
  [ -f "$CL/agents/diff-reviewer.md" ]    # sanity: was installed
  _uninstall
  for a in requirements-engineer architect tdd-developer qa reviewer \
           troubleshooter diff-reviewer explorer; do
    [ ! -e "$CL/agents/$a.md" ]
  done
}

@test "uninstall: removes previously-leaked skills (caveman, gh-cli, glab-cli, brainstorm, explore)" {
  _install
  [ -d "$CL/skills/caveman" ]             # sanity
  _uninstall
  for s in caveman gh-cli glab-cli brainstorm explore clusters tdd plan \
           pipeline-gitlab-feature; do
    [ ! -e "$CL/skills/$s" ]
  done
}

@test "uninstall: removes every Copilot agent, including diff-reviewer + explorer" {
  _install
  [ -f "$CO/agents/diff-reviewer.agent.md" ]
  _uninstall
  for a in requirements-engineer architect tdd-developer qa reviewer \
           troubleshooter diff-reviewer explorer; do
    [ ! -e "$CO/agents/$a.agent.md" ]
  done
}

# --- settings.json: installer hooks stripped, user hooks preserved ---

@test "uninstall: strips installer hook entries from settings.json (no dangling refs)" {
  _install
  _uninstall
  # None of the installer's hook scripts may still be referenced
  ! grep -q 'tdd-gate.sh'       "$CL/settings.json"
  ! grep -q 'confidence-gate.sh' "$CL/settings.json"
  ! grep -q 'session-start.sh'  "$CL/settings.json"
  ! grep -q 'Claude Code needs your attention' "$CL/settings.json"
}

@test "uninstall: preserves a user-added hook in settings.json" {
  _install
  # User adds their own PreToolUse hook (same Bash matcher) + a SessionStart hook
  jq '.hooks.PreToolUse[0].hooks += [{"type":"command","command":"bash ~/.claude/hooks/my-user-hook.sh"}]
      | .hooks.SessionStart += [{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/my-session.sh"}]}]' \
     "$CL/settings.json" > "$CL/s.tmp" && mv "$CL/s.tmp" "$CL/settings.json"

  _uninstall

  # User hooks survive; installer hooks are gone
  grep -q 'my-user-hook.sh' "$CL/settings.json"
  grep -q 'my-session.sh'   "$CL/settings.json"
  ! grep -q 'tdd-gate.sh'   "$CL/settings.json"
  ! grep -q 'session-start.sh' "$CL/settings.json"
}

@test "uninstall: settings.json remains valid JSON after the strip" {
  _install
  _uninstall
  jq empty "$CL/settings.json"
}

# --- non-destructive to user-owned files ---

@test "uninstall: preserves CLAUDE.md (file kept; managed block updates on re-install)" {
  _install
  [ -f "$CL/CLAUDE.md" ]
  _uninstall
  [ -f "$CL/CLAUDE.md" ]
  grep -q '## Identity' "$CL/CLAUDE.md"   # user preamble intact
}
