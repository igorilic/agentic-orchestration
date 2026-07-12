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
#
# SDK-1 Step B-7: run_claude_agent now writes `.anw/specs/<id>-*` (the debug
# log, and -- via the renderer -- milestones.jsonl), so every probe script
# below `cd`s into its own $SANDBOX first (mirrors tests/milestones.bats /
# tests/render-stream.bats) -- never the real project tree. AW_SPEC_ID
# defaults to SDK-1 so the debug-log/milestones paths below are predictable.
# ---------------------------------------------------------------------------

run_streamed_claude_agent() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-XXXXXX")"
  cp "$FAKE_CLAUDE" "$STUB_BIN/claude"
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"
  DEBUG_LOG="$SANDBOX/.anw/specs/${AW_SPEC_ID:-SDK-1}-tdd-developer-debug.log"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
cd "$SANDBOX"
AUDIT_LOG="$SANDBOX/audit.log"
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
run_claude_agent tdd-developer "do a thing"
EOF

  run env PATH="$STUB_BIN:$PATH" FAKE_CLAUDE_EXIT_CODE="${FAKE_CLAUDE_EXIT_CODE:-0}" \
      AW_SPEC_ID="${AW_SPEC_ID:-SDK-1}" bash "$SCRIPT"
}

@test "run_claude_agent (streamed): non-sentinel agent stdout is suppressed from the live view but captured in the debug log (AC-8)" {
  FAKE_CLAUDE_EXIT_CODE=0 run_streamed_claude_agent
  [[ "$output" != *"fake-claude: stdout line 1"* ]]
  [[ "$output" != *"fake-claude: stdout line 2"* ]]
  [ -f "$DEBUG_LOG" ]
  grep -qF "fake-claude: stdout line 1" "$DEBUG_LOG"
  grep -qF "fake-claude: stdout line 2" "$DEBUG_LOG"
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

# ---------------------------------------------------------------------------
# SDK-1 Step B-6 follow-up (qa/reviewer F2), adapted for B-7: the 3 tests
# above only ever vary the AGENT's exit code -- the downstream stage always
# succeeds, so under `pipefail` its exit status IS the agent's exit status
# and `$?` reads the same as `${PIPESTATUS[0]}` by coincidence. That means
# those 3 tests stay green even if run_agent_streamed's else-branch is
# reverted from `exit_code="${PIPESTATUS[0]}"` back to the buggy
# `exit_code=$?` (both gates reproduced this). This test breaks the
# coincidence: the AGENT succeeds but the DOWNSTREAM renderer stage fails --
# exactly the shape of a B-7 renderer crash. Only `${PIPESTATUS[0]}` gets
# this right. `cat`, B-6's downstream stand-in, is gone as of B-7; the
# failure is now injected via a fake `lib/render-stream.sh` under a fake
# _ANW_SCRIPT_DIR, so run_claude_agent resolves $RENDER to a script that
# drains stdin (never blocking the agent) then exits non-zero.
# ---------------------------------------------------------------------------

@test "run_claude_agent (streamed): agent exits 0 but downstream (renderer) fails -- returns 0 (PIPESTATUS[0], the agent's code), not the downstream's" {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-XXXXXX")"
  cp "$FAKE_CLAUDE" "$STUB_BIN/claude"
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"

  FAKE_SCRIPT_DIR="$SANDBOX/fake-root"
  mkdir -p "$FAKE_SCRIPT_DIR/lib"
  # Writes a marker BEFORE failing -- proves this exact fake script is the
  # one actually wired into the pipe (not, say, an old `cat` passthrough
  # that never resolves $RENDER at all and would leave no marker behind).
  cat > "$FAKE_SCRIPT_DIR/lib/render-stream.sh" << EOF
#!/bin/sh
cat >/dev/null
touch "$SANDBOX/renderer-was-invoked"
exit 42
EOF
  chmod +x "$FAKE_SCRIPT_DIR/lib/render-stream.sh"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
cd "$SANDBOX"
AUDIT_LOG="$SANDBOX/audit.log"
_ANW_SCRIPT_DIR="$FAKE_SCRIPT_DIR"
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
run_claude_agent tdd-developer "do a thing"
EOF

  run env PATH="$STUB_BIN:$PATH" FAKE_CLAUDE_EXIT_CODE=0 AW_SPEC_ID=SDK-1 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "[AGENT_OK] Agent=tdd-developer completed" "$SANDBOX/audit.log"
  [ -f "$SANDBOX/renderer-was-invoked" ]
}

# ---------------------------------------------------------------------------
# SDK-1 Step B-7: attach the renderer + milestones; remove the generic
# spinner; capture a debug log; restore LAST_AGENT_OUTPUT.
#
# This shim emits real sentinel lines (for live-render + milestones
# assertions) interleaved with one non-sentinel line (for the AC-8
# suppression assertion) -- mirroring the shape a real agent stream has:
# narration/tool-noise plus machine-readable milestones together.
# ---------------------------------------------------------------------------

run_streamed_claude_agent_with_sentinels() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-sentinel-XXXXXX")"
  cat > "$STUB_BIN/claude" << 'SHIM_EOF'
#!/bin/sh
printf '@@ANW|phase|tdd-developer|sonnet\n'
printf '@@ANW|step|run|Writing tests\n'
printf 'internal chatter that must never reach the live view\n'
printf '@@ANW|step|ok|Writing tests\n'
printf '@@ANW|done|All done\n'
exit 0
SHIM_EOF
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"
  DEBUG_LOG="$SANDBOX/.anw/specs/SDK-1-tdd-developer-debug.log"
  MILESTONES_LOG="$SANDBOX/.anw/specs/SDK-1-milestones.jsonl"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
cd "$SANDBOX"
AUDIT_LOG="$SANDBOX/audit.log"
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
run_claude_agent tdd-developer "do a thing"
EOF

  run env PATH="$STUB_BIN:$PATH" AW_SPEC_ID=SDK-1 AW_PIPELINE_STEP=4.2 bash "$SCRIPT"
}

@test "run_claude_agent (streamed): rendered milestones appear live from the shim's sentinel lines" {
  run_streamed_claude_agent_with_sentinels
  [ "$status" -eq 0 ]
  # Rendered glyphs (⏺/✓), not raw sentinel text -- proves the stream went
  # through the renderer's event handler, not a raw `cat` passthrough
  # (which would show the literal "@@ANW|step|ok|Writing tests" line).
  [[ "$output" == *"⏺ Writing tests"* ]]
  [[ "$output" == *"✓ All done"* ]]
  [[ "$output" != *"@@ANW|"* ]]
}

@test "run_claude_agent (streamed): non-sentinel shim lines suppressed from the live view but present in the debug log (AC-8)" {
  run_streamed_claude_agent_with_sentinels
  [[ "$output" != *"internal chatter"* ]]
  [ -f "$DEBUG_LOG" ]
  grep -qF "internal chatter that must never reach the live view" "$DEBUG_LOG"
  grep -qF '@@ANW|step|ok|Writing tests' "$DEBUG_LOG"
}

@test "run_claude_agent (streamed): milestones.jsonl gains lines with injected spec_id/pipeline_step/agent/tier" {
  run_streamed_claude_agent_with_sentinels
  [ -f "$MILESTONES_LOG" ]
  [ "$(jq -r '.spec_id' "$MILESTONES_LOG" | sort -u)" = "SDK-1" ]
  [ "$(jq -r '.pipeline_step' "$MILESTONES_LOG" | sort -u)" = "4.2" ]
  [ "$(jq -r '.agent' "$MILESTONES_LOG" | sort -u)" = "tdd-developer" ]
  [ "$(jq -r '.tier' "$MILESTONES_LOG" | sort -u)" = "sonnet" ]
}

# ---------------------------------------------------------------------------
# SDK-1 Step B-7: "replace, not coexist" (spikes/sdk-1-renderer/FINDINGS.md
# "Spinner conflict") -- the generic spinner must be gone from this path,
# and no feeder/ticker/spinner process may survive a run, including one
# where the agent shim dies mid-stream.
# ---------------------------------------------------------------------------

@test "run_claude_agent source: no spinner_start/spinner_stop calls on the streamed path" {
  body="$(awk '/^run_claude_agent\(\)/,/^}/' "$PIPELINE_CORE")"
  [ -n "$body" ]
  [[ "$body" != *"spinner_start"* ]]
  [[ "$body" != *"spinner_stop"* ]]
}

@test "run_claude_agent (streamed): spinner_start is never invoked and no leftover render process after a clean run" {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-XXXXXX")"
  cp "$FAKE_CLAUDE" "$STUB_BIN/claude"
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
cd "$SANDBOX"
AUDIT_LOG="$SANDBOX/audit.log"
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
# Dynamic proof (complements the static source-scan test above): shadow
# spinner_start with a marker-writing stand-in AFTER sourcing
# pipeline-core.sh -- bash resolves function calls at call time, so if
# run_claude_agent's body still called spinner_start internally, THIS
# definition would run and leave the marker file behind.
spinner_start() { touch "$SANDBOX/spinner-was-called"; }
run_claude_agent tdd-developer "do a thing"
EOF

  run env PATH="$STUB_BIN:$PATH" FAKE_CLAUDE_EXIT_CODE=0 AW_SPEC_ID=SDK-1 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$SANDBOX/spinner-was-called" ]
  [ "$(pgrep -f 'render-stream\.sh' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "run_claude_agent (streamed): spinner_start is never invoked and no leftover render process when the shim dies mid-stream" {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-die-XXXXXX")"
  cat > "$STUB_BIN/claude" << 'SHIM_EOF'
#!/bin/sh
printf '@@ANW|phase|tdd-developer|sonnet\n'
printf '@@ANW|step|run|Doing a thing\n'
kill -9 $$
SHIM_EOF
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
cd "$SANDBOX"
AUDIT_LOG="$SANDBOX/audit.log"
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
spinner_start() { touch "$SANDBOX/spinner-was-called"; }
run_claude_agent tdd-developer "do a thing" || true
EOF

  run env PATH="$STUB_BIN:$PATH" AW_SPEC_ID=SDK-1 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$SANDBOX/spinner-was-called" ]
  [ "$(pgrep -f 'render-stream\.sh' | wc -l | tr -d ' ')" -eq 0 ]
}

# ---------------------------------------------------------------------------
# SDK-1 Step B-7: restore LAST_AGENT_OUTPUT from the tee'd debug-log capture
# so handle_agent_questions' --allowed-questions QUESTION: scan (dead since
# B-6 streaming) works again on the streamed path.
# ---------------------------------------------------------------------------

@test "run_claude_agent (streamed): --allowed-questions detects a non-sentinel QUESTION: line via restored LAST_AGENT_OUTPUT" {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-fake-claude-question-XXXXXX")"
  cat > "$STUB_BIN/claude" << 'SHIM_EOF'
#!/bin/sh
printf 'Some preamble narration.\n'
printf 'QUESTION: What should the button say?\n'
printf 'more agent chatter\n'
exit 0
SHIM_EOF
  chmod +x "$STUB_BIN/claude"
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-pipeline-audit-XXXXXX")"

  SCRIPT="$SANDBOX/probe.sh"
  cat > "$SCRIPT" << EOF
set -euo pipefail
cd "$SANDBOX"
AUDIT_LOG="$SANDBOX/audit.log"
ALLOWED_QUESTIONS=1
# shellcheck source=lib/common.sh disable=SC1091
source "$COMMON_LIB"
# shellcheck source=lib/pipeline-core.sh disable=SC1091
source "$PIPELINE_CORE"
run_claude_agent tdd-developer "do a thing"
# SDK-1 Step B-7: stub the recursive re-run (reuses the stub-override
# pattern from tests/cli-confidence.bats:249) so this test isolates
# handle_agent_questions' QUESTION: detection from a second real streamed
# invocation.
run_claude_agent() { echo "STUBBED_RERUN_CALLED agent=\$1"; }
handle_agent_questions
EOF

  printf 'A rocket ship\n' > "$SANDBOX/answer.txt"
  run env PATH="$STUB_BIN:$PATH" AW_SPEC_ID=SDK-1 bash "$SCRIPT" < "$SANDBOX/answer.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has 1 question(s)"* ]]
  [[ "$output" == *"What should the button say?"* ]]
  [[ "$output" == *"STUBBED_RERUN_CALLED agent=tdd-developer"* ]]
}
