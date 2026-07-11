#!/usr/bin/env bash
# lib/milestones.sh — part of ai-native-workflow. Sourced by the
# orchestrator (lib/pipeline-core.sh / lib/render-stream.sh, wired in SDK-1
# Step B-4) and by tests/milestones.bats. Defines no top-level side effects
# beyond the function below — safe to `source` from a strict-mode caller.
# shellcheck shell=bash

# SDK-1 Step B-3 (spec OQ-2): orchestrator-side milestones JSONL writer.
#
# The orchestrator is the SOLE writer of .anw/specs/<id>-milestones.jsonl —
# one JSON object per finalized sentinel event, appended (never rewritten).
# Reuses only confidence.jsonl's *conventions* (ISO-8601 UTC `ts`, one
# object per line, append-only, built with `jq -n --arg`); this is new
# orchestrator-side code, not an agent-written log.
#
# append_milestone <event> <spec_id> <pipeline_step> <agent> <tier> \
#                   <status> <text> <delegated_to> <parent_text>
#
# Field order matches the OQ-2 table (minus `ts`, generated here). Pass ""
# for any field the spec types as `string｜null` when it doesn't apply to
# this event (status, delegated_to, parent_text) — it is persisted as JSON
# `null`, never the literal empty string, so downstream jq consumers can
# rely on `.status == null` rather than string-matching "".
#
# The JSON object is built entirely with `jq -n --arg` — never string
# interpolation — so `text` / `parent_text` may safely contain embedded
# `|`, double quotes, or backslashes and still round-trip byte-intact;
# `jq --arg` handles all JSON escaping, so no caller-side quoting is needed.
append_milestone() {
  local event="${1:-}"
  local spec_id="${2:-}"
  local pipeline_step="${3:-}"
  local agent="${4:-}"
  local tier="${5:-}"
  local status="${6:-}"
  local text="${7:-}"
  local delegated_to="${8:-}"
  local parent_text="${9:-}"

  # ponytail: return 1 (not ${var:?}, which would kill a strict-mode caller
  # mid-pipeline and bypass its `|| recover`) — consistent with the spec_id
  # guard below. Empty spec_id falls through to that regex, which rejects it.
  [ -n "$event" ] || { echo "append_milestone: event is required" >&2; return 1; }

  # Guard the path we build from spec_id — mirrors the confidence-gate's
  # active-spec regex (lib/install-project.sh) so a malformed/malicious
  # spec_id can never traverse out of .anw/specs/.
  if ! [[ "$spec_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "append_milestone: invalid spec_id '$spec_id' — must match [A-Za-z0-9._-]+" >&2
    return 1
  fi

  local log=".anw/specs/${spec_id}-milestones.jsonl"
  mkdir -p "$(dirname "$log")" || return 1

  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg event "$event" \
    --arg spec_id "$spec_id" \
    --arg pipeline_step "$pipeline_step" \
    --arg agent "$agent" \
    --arg tier "$tier" \
    --arg status "$status" \
    --arg text "$text" \
    --arg delegated_to "$delegated_to" \
    --arg parent_text "$parent_text" \
    '{
      ts: $ts,
      event: $event,
      spec_id: $spec_id,
      pipeline_step: $pipeline_step,
      agent: $agent,
      tier: $tier,
      status: (if $status == "" then null else $status end),
      text: $text,
      delegated_to: (if $delegated_to == "" then null else $delegated_to end),
      parent_text: (if $parent_text == "" then null else $parent_text end)
    }' >> "$log"
}
