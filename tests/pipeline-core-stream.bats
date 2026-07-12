#!/usr/bin/env bats

# SDK-1 Step B-5: lib/pipeline-core.sh::agent_tier — agent name -> model tier.
#
# Single source of truth (ponytail): the tier already lives in each agent's
# frontmatter (`model: opus|sonnet|haiku` in agents/claude-code/<agent>.md).
# agent_tier() reads it from there rather than duplicating the mapping in a
# hardcoded case statement, so the badge injected via AW_TIER can never drift
# from the agent that's actually running.
#
# Pure function: reads a file, echoes a value, no side effects — safe to call
# directly after sourcing lib/pipeline-core.sh (mirrors tests/milestones.bats;
# pipeline-core.sh defines no top-level side effects beyond `SPINNER_PID=""`,
# so it's source-safe standalone, unlike the main dispatcher).

PIPELINE_CORE="$BATS_TEST_DIRNAME/../lib/pipeline-core.sh"
COMMON_LIB="$BATS_TEST_DIRNAME/../lib/common.sh"
FAKE_CLAUDE="$BATS_TEST_DIRNAME/fixtures/sdk-1/fake-claude.sh"

setup() {
  # shellcheck source=lib/pipeline-core.sh disable=SC1091
  source "$PIPELINE_CORE"
}

teardown() {
  # SDK-1 Step B-6: only the streamed-agent tests below set STUB_BIN/SANDBOX
  # (via run_streamed_claude_agent) -- clean up here so every other test's
  # setup/teardown in this file stays untouched.
  [ -n "${STUB_BIN:-}" ] && rm -rf "$STUB_BIN"
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
  unset STUB_BIN SANDBOX
}

# ---------------------------------------------------------------------------
# Core mapping (spec table).
# ---------------------------------------------------------------------------

@test "agent_tier architect -> opus" {
  [ "$(agent_tier architect)" = "opus" ]
}

@test "agent_tier qa -> opus" {
  [ "$(agent_tier qa)" = "opus" ]
}

@test "agent_tier tdd-developer -> sonnet" {
  [ "$(agent_tier tdd-developer)" = "sonnet" ]
}

@test "agent_tier sidekick -> haiku" {
  [ "$(agent_tier sidekick)" = "haiku" ]
}

@test "agent_tier reviewer -> sonnet (frontmatter, not just the 4 spec examples)" {
  [ "$(agent_tier reviewer)" = "sonnet" ]
}

# ---------------------------------------------------------------------------
# Unknown agent -> sensible default.
# ---------------------------------------------------------------------------

@test "agent_tier unknown agent -> default tier (sonnet)" {
  [ "$(agent_tier bogus-agent)" = "sonnet" ]
}

# ---------------------------------------------------------------------------
# Single-source-of-truth: reads frontmatter, doesn't hardcode a duplicate
# mapping. A hardcoded case statement would still pass the tests above but
# fail this one the moment the fixture agent's model: line disagrees with
# any baked-in guess.
# ---------------------------------------------------------------------------

@test "agent_tier reads the frontmatter (no drift): a fixture agents dir wins over any hardcoded guess" {
  fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/aw-agent-tier-XXXXXX")"
  mkdir -p "$fixture_dir/agents/claude-code"
  cat > "$fixture_dir/agents/claude-code/tdd-developer.md" <<'EOF'
---
name: tdd-developer
model: haiku
tools: Read
---
body
EOF
  _ANW_SCRIPT_DIR="$fixture_dir" run agent_tier tdd-developer
  rm -rf "$fixture_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "haiku" ]
}

# ---------------------------------------------------------------------------
# Purity: no filesystem writes, no ~/.copilot install side effects.
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# SDK-1 Step B-6: run_claude_agent streams through an errexit/PIPESTATUS-
# safe pipe instead of blocking-capture-to-a-file (spikes/sdk-1-renderer/
# FINDINGS.md "Exit-code landmine"). Mechanism only -- the `cat` passthrough
# below is a stand-in for the sentinel renderer wired in Step B-7; the
# spinner is untouched here.
#
# Each test drives run_claude_agent in its OWN `bash "$SCRIPT"` subprocess
# under `set -euo pipefail` (mirroring ai-native-workflow:25) with a fake
# `claude` shim first on PATH -- not the bats test process itself, so a
# script that dies via errexit can't take the test runner down with it.
# The call to run_claude_agent inside that script is BARE (no `|| true`),
# matching the PRIMARY call sites in lib/pipelines.sh (e.g.
# `run_claude_agent "tdd-developer" "Step $i of $todo_file"`) -- that's
# where the landmine actually bites, unlike run_triage's already-guarded
# `run_claude_agent ... || true` fix-loop calls. A bare call inside a
# `set -euo pipefail` script means the subprocess lives or dies with
# run_claude_agent's own return value, which is exactly what bats' `run`
# captures as $status below.
# ---------------------------------------------------------------------------

run_streamed_claude_agent() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-XXXXXX")"
  cp "$FAKE_CLAUDE" "$STUB_BIN/claude"
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
AUDIT_LOG="$SANDBOX/audit.log"
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
run_claude_agent tdd-developer "do a thing"
EOF

  run env PATH="$STUB_BIN:$PATH" FAKE_CLAUDE_EXIT_CODE="${FAKE_CLAUDE_EXIT_CODE:-0}" bash "$SCRIPT"
}

@test "run_claude_agent (streamed): agent stdout is shown" {
  FAKE_CLAUDE_EXIT_CODE=0 run_streamed_claude_agent
  [[ "$output" == *"fake-claude: stdout line 1"* ]]
  [[ "$output" == *"fake-claude: stdout line 2"* ]]
}

@test "run_claude_agent (streamed): non-zero shim exit propagates via PIPESTATUS -- returns non-zero and logs AGENT_ERROR" {
  FAKE_CLAUDE_EXIT_CODE=13 run_streamed_claude_agent
  [ "$status" -eq 13 ]
  grep -qF "[AGENT_ERROR] Agent=tdd-developer ExitCode=13" "$SANDBOX/audit.log"
}

@test "run_claude_agent (streamed): zero shim exit returns 0 and logs AGENT_OK" {
  FAKE_CLAUDE_EXIT_CODE=0 run_streamed_claude_agent
  [ "$status" -eq 0 ]
  grep -qF "[AGENT_OK] Agent=tdd-developer completed" "$SANDBOX/audit.log"
}
