#!/usr/bin/env bats

# Regression coverage for issue #12: `install global` must NOT clobber a user's
# customised ~/.claude/CLAUDE.md or silently drop user-added settings.json hooks.
#
# CLAUDE.md is split into a user-owned preamble (seeded once) and an
# installer-managed block wrapped in markers (regenerated on every install).
# settings.json hooks are concat-merged across PreToolUse/SessionStart/
# Notification so a user-customised hook of any type survives re-install.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-clobber-XXXXXX)"
  STUB="$(mktemp -d /tmp/aw-clobber-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/copilot"; chmod +x "$STUB/copilot"
  CLAUDE_MD="$SANDBOX/claude/CLAUDE.md"
  SETTINGS="$SANDBOX/claude/settings.json"
}

teardown() {
  rm -rf "$SANDBOX" "$STUB"
}

# Run `install global` fully isolated into the sandbox (no real ~/.claude or
# ~/.copilot touched; copilot is stubbed so the Copilot track is a no-op).
_install() {
  PATH="$STUB:$PATH" CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" \
    "$INSTALLER" install global >/dev/null 2>&1
}

BEGIN_MARKER='<!-- >>> ai-native-workflow managed block'
END_MARKER='<!-- <<< ai-native-workflow managed block'

# ---------------------------------------------------------------------------
# CLAUDE.md — fresh install
# ---------------------------------------------------------------------------

@test "claude.md: fresh install seeds preamble + a marked managed block" {
  _install
  [ -f "$CLAUDE_MD" ]
  grep -qF "$BEGIN_MARKER" "$CLAUDE_MD"
  grep -qF "$END_MARKER"   "$CLAUDE_MD"
  # User-owned preamble present
  grep -q '## Identity'          "$CLAUDE_MD"
  grep -q '## Personal Preferences' "$CLAUDE_MD"
  # Managed content present (incl. the new /caveman skill line)
  grep -q '## Stack Detection'   "$CLAUDE_MD"
  grep -q '/caveman'             "$CLAUDE_MD"
}

@test "claude.md: preamble sits ABOVE the begin marker (user-owned region first)" {
  _install
  identity_line="$(grep -n '## Identity' "$CLAUDE_MD" | head -1 | cut -d: -f1)"
  begin_line="$(grep -nF "$BEGIN_MARKER" "$CLAUDE_MD" | head -1 | cut -d: -f1)"
  [ "$identity_line" -lt "$begin_line" ]
}

# ---------------------------------------------------------------------------
# CLAUDE.md — re-install preserves user edits OUTSIDE the managed block
# ---------------------------------------------------------------------------

@test "claude.md: re-install preserves user edits outside the managed markers" {
  _install
  # User customises the preamble AND appends their own section after the block.
  printf '\n## My Custom Workflow\n- NEVER_DELETE_THIS_LINE\n' >> "$CLAUDE_MD"
  # Also edit a preamble line in place.
  sed -i.bak 's/Solo full-stack developer/Solo full-stack developer (CUSTOMISED)/' "$CLAUDE_MD"
  rm -f "${CLAUDE_MD}.bak"

  _install   # second install must not clobber the above

  grep -q 'NEVER_DELETE_THIS_LINE'                "$CLAUDE_MD"
  grep -q 'Solo full-stack developer (CUSTOMISED)' "$CLAUDE_MD"
  # Managed block still present and not duplicated
  [ "$(grep -cF "$BEGIN_MARKER" "$CLAUDE_MD")" -eq 1 ]
  [ "$(grep -cF "$END_MARKER"   "$CLAUDE_MD")" -eq 1 ]
}

@test "claude.md: re-install REGENERATES the managed block (stale content refreshed)" {
  _install
  # Simulate a stale managed block: delete the canonical /caveman line.
  sed -i.bak '/\/caveman/d' "$CLAUDE_MD"; rm -f "${CLAUDE_MD}.bak"
  ! grep -q '/caveman' "$CLAUDE_MD"

  _install   # regeneration must restore canonical managed content

  grep -q '/caveman' "$CLAUDE_MD"
  [ "$(grep -cF "$BEGIN_MARKER" "$CLAUDE_MD")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# CLAUDE.md — legacy file with no markers is never clobbered
# ---------------------------------------------------------------------------

@test "claude.md: legacy file (no markers) is backed up + appended, never overwritten" {
  mkdir -p "$SANDBOX/claude"
  printf '# My hand-written CLAUDE.md\n\nLEGACY_USER_CONTENT_KEEP_ME\n' > "$CLAUDE_MD"

  _install

  # User content survives verbatim
  grep -q 'LEGACY_USER_CONTENT_KEEP_ME' "$CLAUDE_MD"
  # A managed block was appended
  grep -qF "$BEGIN_MARKER" "$CLAUDE_MD"
  # The original was backed up (backup_if_exists -> .bak.<timestamp>)
  ls "$CLAUDE_MD".bak.* >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# settings.json — user-added hooks of every type survive re-install (issue #12)
# ---------------------------------------------------------------------------

@test "settings.json: re-install preserves a user-added SessionStart hook" {
  mkdir -p "$SANDBOX/claude"
  cat > "$SETTINGS" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/my-session-hook.sh", "timeout": 7}
        ]
      }
    ]
  }
}
EOF

  _install

  cmds="$(jq -r '.hooks.SessionStart[].hooks[].command' "$SETTINGS")"
  # User's hook survives
  [[ "$cmds" == *"my-session-hook.sh"* ]]
  # Installer's own SessionStart hook is also present
  [[ "$cmds" == *"session-start.sh"* ]]
}

@test "settings.json: re-install preserves a user-added Notification hook" {
  mkdir -p "$SANDBOX/claude"
  cat > "$SETTINGS" <<'EOF'
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/my-notify-hook.sh"}
        ]
      }
    ]
  }
}
EOF

  _install

  cmds="$(jq -r '.hooks.Notification[].hooks[].command' "$SETTINGS")"
  [[ "$cmds" == *"my-notify-hook.sh"* ]]
  # Installer's own Notification hook (osascript) is also present
  [[ "$cmds" == *"osascript"* ]]
}
