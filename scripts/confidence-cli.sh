#!/usr/bin/env bash
# CLI helper functions for confidence gate integration.
# Sourced by ai-native-workflow and by tests/cli-confidence.bats.

# Resolve the directory containing this script so we can find confidence.sh
# regardless of the caller's working directory.
_CONFIDENCE_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# write_active_spec <spec_id>
# Records the active spec ID so hooks can find it.
# Rejects spec IDs that don't match [A-Za-z0-9._-]+ to prevent path traversal.
write_active_spec() {
  local spec_id="$1"
  if ! echo "$spec_id" | grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "error: invalid spec id '$spec_id' — must match [A-Za-z0-9._-]+" >&2
    return 1
  fi
  mkdir -p .git/aw
  printf '%s\n' "$spec_id" > .git/aw/active-spec
}

# build_pr_body <spec_id> <base_body>
# Appends a ## Confidence section to the base PR body.
# Reads the confidence log but does NOT mutate it.
build_pr_body() {
  local spec_id="$1"
  local base_body="$2"
  local log=".context/specs/${spec_id}-confidence.jsonl"
  local verdict band score penalties_summary

  verdict="$("$_CONFIDENCE_CLI_DIR/confidence.sh" "$log" 2>/dev/null)" || verdict='{"band":"UNKNOWN","score":0,"penalties":{}}'
  band="$(jq -r '.band' <<<"$verdict")"
  score="$(jq -r '.score' <<<"$verdict")"
  penalties_summary="$(jq -r '.penalties | to_entries | map(select(.value != 0)) | map("\(.value) \(.key)") | join(", ")' <<<"$verdict")"
  [ -z "$penalties_summary" ] && penalties_summary="(none)"

  local gates gates_line
  gates="$(jq -r '.gates | join(", ")' <<<"$verdict")"
  gates_line=""
  if [ "$band" = "RED" ] && [ -n "$gates" ]; then
    gates_line="Failing gates: $gates"
  fi

  if [ -n "$gates_line" ]; then
    cat <<EOF
$base_body

## Confidence
**$band: $score/100**

$gates_line

Penalties: $penalties_summary
Audit: \`.context/specs/${spec_id}-confidence.jsonl\`
EOF
  else
    cat <<EOF
$base_body

## Confidence
**$band: $score/100**

Penalties: $penalties_summary
Audit: \`.context/specs/${spec_id}-confidence.jsonl\`
EOF
  fi
}

# emit_step_verdict <spec_id> <step>
# Invokes the scorer at scope=step, appends a verdict event to the log,
# and prints band/score to stdout.
# Purely informational — does not prompt. run_triage owns the fix/abort flow.
emit_step_verdict() {
  local spec_id="$1"
  local step="$2"
  local log=".context/specs/${spec_id}-confidence.jsonl"
  local verdict

  verdict="$("$_CONFIDENCE_CLI_DIR/confidence.sh" "$log" --scope=step --step="$step" 2>/dev/null)" \
    || verdict='{"band":"UNKNOWN","score":0,"penalties":{}}'

  local ts band score
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  band="$(jq -r '.band' <<<"$verdict")"
  score="$(jq -r '.score' <<<"$verdict")"

  # Append verdict event to the log (compact, one line per event).
  jq -cn --arg ts "$ts" --argjson step "$step" --arg band "$band" --argjson score "$score" \
    '{ts:$ts, event:"verdict", scope:"step", step:$step, band:$band, score:$score}' \
    >> "$log"

  # Surface to user.
  echo "[step $step] confidence: $band ($score/100)"
}
