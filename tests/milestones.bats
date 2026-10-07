#!/usr/bin/env bats

# SDK-1 Step B-3: lib/milestones.sh — orchestrator-side milestones JSONL writer.
#
# append_milestone() is the SOLE writer of .anw/specs/<id>-milestones.jsonl
# (spec OQ-2). Field set (order per the spec's table, `ts` auto-generated):
#   ts, event, spec_id, pipeline_step, agent, tier, status, text,
#   delegated_to, parent_text
# Built with `jq -n --arg` (never string interpolation) so `text` /
# `parent_text` can safely embed `|`, double quotes, and backslashes and
# round-trip byte-intact through the JSON. `status` / `delegated_to` /
# `parent_text` are `string｜null` per OQ-2 — the writer accepts an empty
# string from the caller for "not applicable to this event" and persists
# JSON `null` (never a literal empty-string), so downstream jq consumers can
# rely on `.status == null` rather than string-matching "".
#
# Hermetic: every test `cd`s into a throwaway sandbox dir first, so the
# relative `.anw/specs/` path this writer builds internally never touches
# the real project's `.anw/` (gitignored, orchestrator-owned).

MILESTONES_LIB="$BATS_TEST_DIRNAME/../lib/milestones.sh"
LOGFILE=".anw/specs/SDK-1-milestones.jsonl"

setup() {
  ORIG_PWD="$PWD"
  SANDBOX="$(mktemp -d "$BATS_TMPDIR/aw-milestones-XXXXXX")"
  cd "$SANDBOX"
  # shellcheck source=lib/milestones.sh disable=SC1091
  source "$MILESTONES_LIB"
}

teardown() {
  cd "$ORIG_PWD"
  rm -rf "$SANDBOX"
}

# ---------------------------------------------------------------------------
# Core contract: one call -> one valid JSONL line.
# ---------------------------------------------------------------------------

@test "append_milestone writes exactly one jq -e-valid JSON line" {
  append_milestone "step" "SDK-1" "4.2" "tdd-developer" "sonnet" "ok" "Wrote foo.go" "" ""
  [ -f "$LOGFILE" ]
  [ "$(wc -l < "$LOGFILE" | tr -d ' ')" -eq 1 ]
  jq -e . "$LOGFILE"
}

@test "append_milestone: every OQ-2 field round-trips via jq -r" {
  append_milestone "step" "SDK-1" "4.2" "tdd-developer" "sonnet" "ok" "Wrote foo.go" "" ""
  line="$(cat "$LOGFILE")"
  [ "$(jq -r '.event'         <<<"$line")" = "step" ]
  [ "$(jq -r '.spec_id'       <<<"$line")" = "SDK-1" ]
  [ "$(jq -r '.pipeline_step' <<<"$line")" = "4.2" ]
  [ "$(jq -r '.agent'         <<<"$line")" = "tdd-developer" ]
  [ "$(jq -r '.tier'          <<<"$line")" = "sonnet" ]
  [ "$(jq -r '.status'        <<<"$line")" = "ok" ]
  [ "$(jq -r '.text'          <<<"$line")" = "Wrote foo.go" ]
  [ "$(jq -r '.delegated_to'  <<<"$line")" = "null" ]
  [ "$(jq -r '.parent_text'   <<<"$line")" = "null" ]
  jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' <<<"$line"
}

# ---------------------------------------------------------------------------
# Append-only.
# ---------------------------------------------------------------------------

@test "append_milestone: two calls append two lines (not an overwrite)" {
  append_milestone "phase" "SDK-1" "4.2" "tdd-developer" "sonnet" "" "first" "" ""
  append_milestone "done"  "SDK-1" "4.2" "tdd-developer" "sonnet" "" "second" "" ""
  [ "$(wc -l < "$LOGFILE" | tr -d ' ')" -eq 2 ]
  [ "$(sed -n '1p' "$LOGFILE" | jq -r '.text')" = "first" ]
  [ "$(sed -n '2p' "$LOGFILE" | jq -r '.text')" = "second" ]
}

@test "append_milestone: appending never truncates the existing file" {
  append_milestone "phase" "SDK-1" "4.2" "tdd-developer" "sonnet" "" "first" "" ""
  size1="$(wc -c < "$LOGFILE" | tr -d ' ')"
  append_milestone "done" "SDK-1" "4.2" "tdd-developer" "sonnet" "" "second" "" ""
  size2="$(wc -c < "$LOGFILE" | tr -d ' ')"
  [ "$size2" -gt "$size1" ]
}

# ---------------------------------------------------------------------------
# Escaping crux: jq -n --arg must guarantee valid, byte-intact round-trip
# even when the free-text fields contain characters that would corrupt a
# naively string-interpolated JSON blob.
# ---------------------------------------------------------------------------

@test "append_milestone: embedded | double-quotes and a backslash in text round-trip intact" {
  weird='Compare A | B "quoted" and C\ backslash'
  append_milestone "step" "SDK-1" "4.2" "tdd-developer" "sonnet" "ok" "$weird" "" ""
  jq -e . "$LOGFILE"
  got="$(jq -r '.text' "$LOGFILE")"
  [ "$got" = "$weird" ]
}

@test "append_milestone: embedded | double-quotes and a backslash in parent_text round-trip intact" {
  weird='Parent | text with "quotes" and \backslash\'
  append_milestone "deleg" "SDK-1" "4.2" "tdd-developer" "haiku" "" "scaffold stub" "haiku" "$weird"
  jq -e . "$LOGFILE"
  got="$(jq -r '.parent_text' "$LOGFILE")"
  [ "$got" = "$weird" ]
}

@test "append_milestone: newline-free multi-pipe text with trailing backslash round-trips intact" {
  weird='a\\|b\\|c\\'
  append_milestone "step" "SDK-1" "4.2" "tdd-developer" "sonnet" "ok" "$weird" "" ""
  jq -e . "$LOGFILE"
  got="$(jq -r '.text' "$LOGFILE")"
  [ "$got" = "$weird" ]
}

# ---------------------------------------------------------------------------
# Nullable fields (status, delegated_to, parent_text) — spec OQ-2 typing.
# ---------------------------------------------------------------------------

@test "append_milestone: delegation event carries delegated_to as the sidekick tier" {
  append_milestone "deleg" "SDK-1" "4.2" "tdd-developer" "haiku" "" "scaffold stub" "haiku" "Wrote foo.go"
  [ "$(jq -r '.delegated_to' "$LOGFILE")" = "haiku" ]
  [ "$(jq -r '.status' "$LOGFILE")" = "null" ]
  [ "$(jq -r '.parent_text' "$LOGFILE")" = "Wrote foo.go" ]
}

@test "append_milestone: status is JSON null (not empty string) for non-step events" {
  append_milestone "phase" "SDK-1" "4.2" "tdd-developer" "sonnet" "" "n/a" "" ""
  raw="$(jq -c '.status' "$LOGFILE")"
  [ "$raw" = "null" ]
}

@test "append_milestone: delegated_to and parent_text are JSON null (not empty string) for a non-delegation event" {
  append_milestone "step" "SDK-1" "4.2" "tdd-developer" "sonnet" "ok" "regular milestone" "" ""
  [ "$(jq -c '.delegated_to' "$LOGFILE")" = "null" ]
  [ "$(jq -c '.parent_text' "$LOGFILE")" = "null" ]
}

# ---------------------------------------------------------------------------
# Path/robustness hardening.
# ---------------------------------------------------------------------------

@test "append_milestone: rejects a spec_id with path-traversal characters, writes nothing" {
  run append_milestone "step" "../evil" "4.2" "tdd-developer" "sonnet" "ok" "text" "" ""
  [ "$status" -ne 0 ]
  [ ! -d ".anw" ]
}

@test "append_milestone: empty event returns 1 without killing a strict-mode caller" {
  # F1: required-arg failure must be recoverable (return 1), not ${var:?} which
  # exits the caller mid-pipeline and bypasses its `|| recover`.
  run bash -c "set -euo pipefail; source '$MILESTONES_LIB'; append_milestone '' SDK-1 s a t st tx d p || echo RECOVERED; echo DONE"
  [ "$status" -eq 0 ]
  [[ "$output" == *RECOVERED* ]]
  [[ "$output" == *DONE* ]]
}

# ---------------------------------------------------------------------------
# No install-side-effects: this file is source-file-only, must never touch
# the real ~/.copilot (mirrors tests/agent-delegation.bats's guard).
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
