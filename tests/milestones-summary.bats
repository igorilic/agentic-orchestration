#!/usr/bin/env bats

# SDK-1 Step B-8 (spec OQ-7/AC-12): scripts/milestones-summary.sh — delegation
# cost/quality summary derived from a milestones.jsonl fixture via jq.
#
# Metric definitions (per OQ-7's "derive from JSONL" decision, AC-12):
#   - total delegations = count of event=="deleg" lines
#   - rejected          = count of event=="deleg_reject" lines
#   - accepted          = total delegations - rejected (ponytail: the OQ-2
#     schema has no dedicated "accept" event — the parent contract
#     (spec ~line 173-177) guarantees every `deleg` resolves via either an
#     accepting `step|ok` milestone or a `deleg_reject`, so accepted is
#     derived, not matched by scanning free-text)
#   - per-agent delegation counts = deleg events grouped by `.agent` (the
#     delegating parent agent — not `.delegated_to`, which is the sidekick
#     tier)
#
# Fixture tests/fixtures/sdk-1/summary.jsonl: 4 deleg, 2 deleg_reject across
# 3 agents (tdd-developer: 2 deleg/1 reject, qa: 1 deleg/0 reject,
# reviewer: 1 deleg/1 reject) => total=4, accepted=2, rejected=2,
# per-agent: tdd-developer=2, qa=1, reviewer=1.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/milestones-summary.sh"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/sdk-1/summary.jsonl"

@test "milestones-summary: reports total delegation count" {
  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total delegations: 4"* ]]
}

@test "milestones-summary: reports accepted count" {
  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Accepted: 2"* ]]
}

@test "milestones-summary: reports rejected count" {
  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rejected: 2"* ]]
}

@test "milestones-summary: reports per-agent delegation counts" {
  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tdd-developer: 2"* ]]
  [[ "$output" == *"qa: 1"* ]]
  [[ "$output" == *"reviewer: 1"* ]]
}

@test "milestones-summary: missing file reports zeros, exits 0" {
  run "$SCRIPT" "/no/such/file/milestones.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total delegations: 0"* ]]
  [[ "$output" == *"Accepted: 0"* ]]
  [[ "$output" == *"Rejected: 0"* ]]
}

@test "milestones-summary: empty file reports zeros, exits 0" {
  local empty
  empty="$(mktemp "$BATS_TMPDIR/aw-summary-empty-XXXXXX")"
  run "$SCRIPT" "$empty"
  rm -f "$empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total delegations: 0"* ]]
  [[ "$output" == *"Accepted: 0"* ]]
  [[ "$output" == *"Rejected: 0"* ]]
}

@test "milestones-summary: no path argument reports zeros, exits 0" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total delegations: 0"* ]]
}

# ---------------------------------------------------------------------------
# No install-side-effects: this script only reads a fixture path, must never
# touch the real ~/.copilot (mirrors tests/milestones.bats's guard).
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
