#!/usr/bin/env bash
# Computes a deterministic confidence verdict from an event log.
# Usage: scripts/confidence.sh <log-path> [--scope=aggregate|step] [--step=N]
set -euo pipefail

LOG="${1:?usage: confidence.sh <log-path> [--scope=...] [--step=N]}"
SCOPE="aggregate"
STEP=""
shift || true
for arg in "$@"; do
  case "$arg" in
    --scope=*) SCOPE="${arg#--scope=}" ;;
    --step=*)  STEP="${arg#--step=}" ;;
  esac
done

[ -f "$LOG" ] || { echo "log not found: $LOG" >&2; exit 1; }

# Slurp into an array. Strip irrelevant events for scope=step.
if [ -s "$LOG" ]; then
  events="$(jq -s '.' "$LOG")"
else
  events="[]"
fi
if [ "$SCOPE" = "step" ] && [ -n "$STEP" ]; then
  events="$(jq --argjson s "$STEP" '[.[] | select((.step // 0) == $s or .event == "spec")]' <<<"$events")"
fi

score=100
gates=()
penalties_should_fix=0
penalties_loops=0
penalties_tech_debt=0
penalties_ac_coverage=0
penalties_diff=0
penalties_suggestion=0

# (Hard gates and scored penalties added in subsequent tasks.)

# Determine band.
if [ "${#gates[@]}" -gt 0 ]; then
  band="RED"
elif [ "$score" -ge 80 ]; then
  band="GREEN"
elif [ "$score" -ge 60 ]; then
  band="YELLOW"
else
  band="RED"
fi

verdict_text="$band: ${score}/100"

jq -n \
  --arg band "$band" \
  --argjson score "$score" \
  --argjson gates "$(printf '%s\n' "${gates[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson penalties "$(jq -n \
      --argjson should_fix "$penalties_should_fix" \
      --argjson suggestion "$penalties_suggestion" \
      --argjson loops "$penalties_loops" \
      --argjson tech_debt "$penalties_tech_debt" \
      --argjson ac_coverage "$penalties_ac_coverage" \
      --argjson diff "$penalties_diff" \
      '{should_fix:$should_fix, suggestion:$suggestion, loops:$loops, tech_debt:$tech_debt, ac_coverage:$ac_coverage, diff:$diff}')" \
  --arg verdict_text "$verdict_text" \
  '{band:$band, score:$score, gates:$gates, penalties:$penalties, verdict_text:$verdict_text}'
