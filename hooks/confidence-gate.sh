#!/usr/bin/env bash
# Confidence gate: blocks PR/MR creation on RED aggregate verdict.
# Modeled on hooks/tdd-gate.sh — exit 2 to block.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"

# Filter: only fire on PR/MR creation commands.
if ! echo "$TOOL_INPUT" | grep -qE '(gh\s+pr\s+create(\s|$)|glab\s+mr\s+create(\s|$))'; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTIVE_SPEC_FILE="$PROJECT_DIR/.git/aw/active-spec"
if [ ! -f "$ACTIVE_SPEC_FILE" ]; then
  echo "🚫 Confidence gate: no .git/aw/active-spec pointer." >&2
  echo "  The pipeline driver writes this file. If you ran agents manually," >&2
  echo "  set it explicitly: echo PROJ-123 > .git/aw/active-spec" >&2
  exit 2
fi

SPEC_ID="$(cat "$ACTIVE_SPEC_FILE")"
LOG="$PROJECT_DIR/.context/specs/${SPEC_ID}-confidence.jsonl"

if [ ! -f "$LOG" ]; then
  echo "🚫 Confidence gate: log not found at $LOG" >&2
  exit 2
fi

# Compute verdict.
VERDICT_JSON="$("$SCRIPT_DIR/../scripts/confidence.sh" "$LOG")"
BAND="$(echo "$VERDICT_JSON" | jq -r '.band')"
SCORE="$(echo "$VERDICT_JSON" | jq -r '.score')"
GATES="$(echo "$VERDICT_JSON" | jq -c '.gates')"

# Append aggregate verdict to log.
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg ts "$TS" \
  --arg band "$BAND" \
  --argjson score "$SCORE" \
  --argjson gates "$GATES" \
  '{ts:$ts, event:"verdict", scope:"aggregate", band:$band, score:$score, gates:$gates}' \
  >> "$LOG"

case "$BAND" in
  GREEN)
    echo "✅ Confidence: GREEN ($SCORE/100) — proceeding." >&2
    exit 0
    ;;
  YELLOW)
    echo "⚠ Confidence: YELLOW ($SCORE/100) — proceeding with caution." >&2
    exit 0
    ;;
  RED)
    OVERRIDE_FILE="$PROJECT_DIR/.git/aw/override-${SPEC_ID}"
    if [ -f "$OVERRIDE_FILE" ]; then
      OVERRIDE_REASON="$(jq -r '.reason' "$OVERRIDE_FILE")"
      jq -n \
        --arg ts "$TS" \
        --arg reason "$OVERRIDE_REASON" \
        --argjson gates "$GATES" \
        '{ts:$ts, event:"override", trigger:"manual", reason:$reason, gates_bypassed:$gates}' \
        >> "$LOG"
      rm -f "$OVERRIDE_FILE"
      echo "⚠ Confidence: RED ($SCORE/100) — override consumed: \"$OVERRIDE_REASON\"" >&2
      exit 0
    fi

    echo "🚫 Confidence: RED ($SCORE/100) — gates: $GATES" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Address the failing gates and retry" >&2
    echo "  2. /override-confidence \"<reason>\" to bypass (logged)" >&2
    exit 2
    ;;
  *)
    echo "🚫 Confidence gate: unexpected band value '$BAND' — blocking as safety default." >&2
    exit 2
    ;;
esac
