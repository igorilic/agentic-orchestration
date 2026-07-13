#!/usr/bin/env bats

# SDK-1 Step B-9 (Integration + reviewer-F0 close-out).
#
# B-4/B-7's renderer-level tests (tests/render-stream.bats,
# tests/pipeline-core-stream.bats) prove the renderer/run_claude_agent
# plumbing works -- but they hand-inject AW_SPEC_ID/AW_PIPELINE_STEP as test
# env, which can never catch a gap in the ORCHESTRATOR code that's supposed
# to set those vars in the first place. Reviewer-F0: lib/pipelines.sh never
# exported AW_SPEC_ID/AW_PIPELINE_STEP anywhere, so append_milestone's
# spec_id guard silently dropped every write in production --
# milestones.jsonl only ever existed under those hand-injected test envs.
#
# This file drives the REAL, unmodified production path: the
# `ai-native-workflow` entrypoint itself (not a sourced-and-poked function),
# `run github-feature`, which calls `pipeline_github_feature` exactly as a
# real user invocation would. Nothing here sets AW_SPEC_ID/AW_PIPELINE_STEP
# -- if lib/pipelines.sh doesn't wire them, milestones.jsonl stays empty (or
# missing) and assertion #2 below fails. That's the F0 regression guard.
#
# Externals stubbed (minimally, to isolate from network/interactivity):
#   - `claude`: a fake shim on PATH that cats a fixture sentinel stream
#     (tests/fixtures/sdk-1/e2e.sentinels: phase -> step run -> step ok ->
#     deleg haiku -> step ok "reviewed & accepted" -> done) and exits with
#     $FAKE_CLAUDE_EXIT_CODE.
#   - `gh`: a no-op stub. require_gh only checks presence
#     (`command -v gh`) on this path -- `gh issue create` (Step 2) is never
#     reached because the run pauses at Step 1's wait_for_review.
# NOT stubbed:
#   - `git`: a real (local-only, no remote) repo is `git init`'d per test in
#     an isolated sandbox -- create_feature_branch's own `git checkout -b`
#     needs a real repo, and this never touches the real project's `.git`.
#   - `wait_for_review`/confirm: not stubbed, just answered. Piping "n" on
#     stdin answers wait_for_review's "Continue to next step? [Y/n/q]" pause
#     after Step 1, which is what stops the run after exactly ONE streamed
#     agent call without reaching Step 2's `confirm` (gh) or Step 3
#     (architect) or the TDD loop (no todo file exists yet anyway).
#   - the "confidence gate" (emit_step_verdict/build_pr_body): never
#     reached either -- both only run from Step 6+ (per-TDD-step review) and
#     Step 7 (PR body), well past the single Step-1 pause point here.
#
# Sandboxed: every test `cd`s into its own tmp SANDBOX (mirrors
# tests/pipeline-core-stream.bats) before invoking the real
# ai-native-workflow binary, so `.anw/`, `.git/`, `docs/context/specs/` are
# all sandbox-relative -- the real project's `.anw/` is never touched.
#
# ponytail: assertions below use grep -qF / `[` (POSIX test) rather than
# bare `[[ ... ]]` glob matches. macOS's system bash is 3.2, which has a
# confirmed quirk in THIS environment: a bare failing `[[ ... ]]` does not
# trip `errexit` even under bats-core's own `set -eET`, so only the LAST
# statement in a multi-assertion test body would actually gate pass/fail --
# every earlier `[[ ... ]]` failure gets silently skipped over. `grep -qF`
# and `[ ]` are plain simple-command / builtin exits, which DO trip errexit
# reliably on this bash (verified empirically), so every assertion below
# independently fails the test if false, not just the last one.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
ANW="$REPO_ROOT/ai-native-workflow"
FIXTURE="$REPO_ROOT/tests/fixtures/sdk-1/e2e.sentinels"
SUMMARY_SCRIPT="$REPO_ROOT/scripts/milestones-summary.sh"

setup() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/aw-e2e-stub-XXXXXX")"

  cat > "$STUB_BIN/claude" << 'SHIM_EOF'
#!/bin/sh
cat "$E2E_FIXTURE"
exit "${FAKE_CLAUDE_EXIT_CODE:-0}"
SHIM_EOF
  chmod +x "$STUB_BIN/claude"

  cat > "$STUB_BIN/gh" << 'SHIM_EOF'
#!/bin/sh
exit 0
SHIM_EOF
  chmod +x "$STUB_BIN/gh"

  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aw-e2e-sandbox-XXXXXX")"
  ( cd "$SANDBOX" && git init -q && echo "# Feature" > specs.md )
}

teardown() {
  rm -rf "$STUB_BIN" "$SANDBOX"
}

# Drives `ai-native-workflow run github-feature specs.md` for real, from
# inside the sandbox. "n" on stdin answers the Step-1 wait_for_review pause.
run_pipeline() {
  ( cd "$SANDBOX" && printf 'n\n' | env PATH="$STUB_BIN:$PATH" \
      E2E_FIXTURE="$FIXTURE" FAKE_CLAUDE_EXIT_CODE="${FAKE_CLAUDE_EXIT_CODE:-0}" \
      "$ANW" run github-feature specs.md )
}

# write_active_spec (scripts/confidence-cli.sh) writes the real pipeline's
# own "$id" here -- reading it back is how tests find the milestones.jsonl
# path without hardcoding or hand-injecting the id themselves (the id is
# timestamp-generated: "feature-$(date +%Y%m%d-%H%M%S)").
spec_id_of_sandbox() {
  cat "$SANDBOX/.git/aw/active-spec"
}

milestones_log_of_sandbox() {
  echo "$SANDBOX/.anw/specs/$(spec_id_of_sandbox)-milestones.jsonl"
}

# See the ponytail note at the top of the file: bare `[[ ... ]]` doesn't
# reliably fail a bats test on this bash. These wrap the check in an
# explicit `if`/`return 1` (a real simple-command failure) instead.
assert_contains() {
  local haystack="$1" needle="$2"
  if ! grep -qF -- "$needle" <<< "$haystack"; then
    echo "expected output to contain: $needle" >&2
    echo "--- actual ---" >&2
    echo "$haystack" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  if grep -qF -- "$needle" <<< "$haystack"; then
    echo "expected output to NOT contain: $needle" >&2
    echo "--- actual ---" >&2
    echo "$haystack" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Assertion 1: live render output present (rendered glyphs, not raw
# sentinel text) -- proves the stream actually went through
# lib/render-stream.sh's event handler on the real pipeline call site.
# ---------------------------------------------------------------------------

@test "e2e: real pipeline_github_feature call site renders live milestones (glyphs, not raw sentinels)" {
  run run_pipeline
  [ "$status" -eq 0 ]
  assert_contains "$output" "⏺ Drafting requirements"
  assert_contains "$output" "↳ sidekick · haiku:"
  assert_contains "$output" "✓ Requirements complete"
  assert_not_contains "$output" "@@ANW|"
}

# ---------------------------------------------------------------------------
# Assertion 2 (the F0 regression guard): milestones.jsonl is non-empty and
# contains the delegation line + its accept milestone, with spec_id/agent/
# tier populated from the REAL pipeline run -- not hand-injected. Before the
# Part-1 wiring, lib/pipelines.sh never set AW_SPEC_ID/AW_PIPELINE_STEP, so
# append_milestone's spec_id guard rejected every write and this file was
# never even created (verified RED before the fix; see commit history).
# ---------------------------------------------------------------------------

@test "e2e (F0): milestones.jsonl is non-empty with the deleg + accept lines, spec_id/agent/tier from the real pipeline" {
  run run_pipeline
  [ "$status" -eq 0 ]

  local log
  log="$(milestones_log_of_sandbox)"
  [ -s "$log" ]

  local id
  id="$(spec_id_of_sandbox)"
  [ -n "$id" ]

  # spec_id/agent/tier are the same on every line -- injected once by the
  # real pipeline_github_feature/run_claude_agent call site, not per-event.
  [ "$(jq -r '.spec_id' "$log" | sort -u)" = "$id" ]
  [ "$(jq -r '.agent' "$log" | sort -u)" = "requirements-engineer" ]
  [ "$(jq -r '.tier' "$log" | sort -u)" = "opus" ]
  [ "$(jq -r '.pipeline_step' "$log" | sort -u)" = "1" ]

  # The delegation line itself.
  [ "$(jq -r 'select(.event == "deleg") | .delegated_to' "$log")" = "haiku" ]
  [ "$(jq -r 'select(.event == "deleg") | .text' "$log")" = "Generate requirements scaffold" ]

  # Its accept milestone (the step|ok immediately following the deleg, per
  # the fixture's "reviewed & accepted" text).
  [ "$(jq -r 'select(.event == "step" and .status == "ok" and .text == "reviewed & accepted")' "$log" | wc -l | tr -d ' ')" != "0" ]
}

# ---------------------------------------------------------------------------
# Assertion 3: agent exit semantics preserved through the real call site.
# ---------------------------------------------------------------------------

@test "e2e: success run returns 0 and logs AGENT_OK" {
  run run_pipeline
  [ "$status" -eq 0 ]
  grep -qF "[AGENT_OK] Agent=requirements-engineer completed" "$SANDBOX/.anw/.pipeline-audit.log"
}

@test "e2e: forced-failure shim halts the pipeline as before (non-zero exit, AGENT_ERROR logged)" {
  FAKE_CLAUDE_EXIT_CODE=13 run run_pipeline
  [ "$status" -eq 13 ]
  grep -qF "[AGENT_ERROR] Agent=requirements-engineer ExitCode=13" "$SANDBOX/.anw/.pipeline-audit.log"
  assert_contains "$output" "Pipeline crashed at step 1"
}

# ---------------------------------------------------------------------------
# Assertion 4: scripts/milestones-summary.sh over the real pipeline's own
# milestones.jsonl reports 1 delegation, 1 accept, 0 reject.
# ---------------------------------------------------------------------------

@test "e2e: milestones-summary.sh reports 1 delegation, 1 accept, 0 reject" {
  run run_pipeline
  [ "$status" -eq 0 ]

  run "$SUMMARY_SCRIPT" "$(milestones_log_of_sandbox)"
  [ "$status" -eq 0 ]
  assert_contains "$output" "Total delegations: 1"
  assert_contains "$output" "Accepted: 1"
  assert_contains "$output" "Rejected: 0"
}

# ---------------------------------------------------------------------------
# No install side effects: real ~/.copilot must stay untouched (mirrors the
# guard in every other SDK-1 bats file).
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
