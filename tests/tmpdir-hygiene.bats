#!/usr/bin/env bats
# Agent sandboxes (Claude Code, Copilot CLI) let commands write to $TMPDIR, not to a bare /tmp.
# A hard-coded /tmp makes the suite fail inside them, which misleads the agent into "fixing" working code.

@test "mktemp never hard-codes /tmp (honor TMPDIR so the suite runs inside agent sandboxes)" {
  cd "$BATS_TEST_DIRNAME/.."
  run grep -rn -E 'mktemp( -d)? /tmp/' tests lib hooks ai-native-workflow
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "mktemp always gets a template (macOS mktemp without one ignores TMPDIR and writes to /var/folders)" {
  cd "$BATS_TEST_DIRNAME/.."
  run grep -rn -E 'mktemp( -d)?([)"]|[[:space:]]*$)' tests lib hooks ai-native-workflow
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}
