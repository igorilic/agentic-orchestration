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

# Hard gates — appended in canonical order: NO_AC, TEST_FAILED, BUILD_BROKEN, MUST_FIX, AC_NOT_TESTED, TDD_BYPASSED_NO_REASON
# --- Hard gates ---
ac_count="$(jq '[.[] | select(.event=="spec")] | (.[0].ac_items // []) | length' <<<"$events")"
if [ "$SCOPE" = "aggregate" ]; then
  [ "$ac_count" -gt 0 ] || gates+=("NO_AC")
fi

failed_total="$(jq '[.[] | select(.event=="qa") | .tests_failed] | add // 0' <<<"$events")"
[ "$failed_total" -eq 0 ] || gates+=("TEST_FAILED")

broken="$(jq '[.[] | select(.event=="qa" and .build_status != "ok")] | length' <<<"$events")"
[ "$broken" -eq 0 ] || gates+=("BUILD_BROKEN")

must_fix_total="$(jq '[.[] | select(.event=="review") | .must_fix | length] | add // 0' <<<"$events")"
[ "$must_fix_total" -eq 0 ] || gates+=("MUST_FIX")

spec_acs="$(jq '[.[] | select(.event=="spec")][0].ac_items // [] | map(.id)' <<<"$events")"
tested_acs="$(jq '[.[] | select(.event=="qa") | (.ac_items_tested // [])[]] | unique' <<<"$events")"
missing_acs="$(jq -n --argjson s "$spec_acs" --argjson t "$tested_acs" '$s - $t')"
missing_count="$(jq 'length' <<<"$missing_acs")"
if [ "$SCOPE" = "aggregate" ]; then
  [ "$missing_count" -eq 0 ] || gates+=("AC_NOT_TESTED")
fi

bypass_no_reason="$(jq '[.[] | select(.event=="tdd_bypassed" and ((.reason // "") == ""))] | length' <<<"$events")"
[ "$bypass_no_reason" -eq 0 ] || gates+=("TDD_BYPASSED_NO_REASON")

# --- Scored penalties ---
should_fix_count="$(jq '[.[] | select(.event=="review") | .should_fix | length] | add // 0' <<<"$events")"
penalties_should_fix=$(( -5 * should_fix_count ))

suggestion_count="$(jq '[.[] | select(.event=="review") | .suggestion | length] | add // 0' <<<"$events")"
penalties_suggestion=$(( -1 * suggestion_count ))

loops2="$(jq '[.[] | select(.event=="review" and .loops_used >= 2)] | length' <<<"$events")"
loops3="$(jq '[.[] | select(.event=="review" and .loops_used >= 3)] | length' <<<"$events")"
penalties_loops=$(( -5 * loops2 + -10 * loops3 ))

td_count="$(jq '[.[] | select(.event=="review") | .tech_debt_deferrals | length] | add // 0' <<<"$events")"
penalties_tech_debt=$(( -3 * td_count ))

# AC coverage penalty (the gate already handles 100% missing; this scores partial misses).
if [ "$SCOPE" = "aggregate" ]; then
  penalties_ac_coverage=$(( -2 * missing_count ))
  [ "$penalties_ac_coverage" -lt -20 ] && penalties_ac_coverage=-20
fi

total_diff="$(jq '[.[] | select(.event=="review") | .diff_lines] | add // 0' <<<"$events")"
if [ "$total_diff" -gt 1000 ]; then
  penalties_diff=-15
elif [ "$total_diff" -gt 400 ]; then
  penalties_diff=-5
fi

score=$(( score + penalties_should_fix + penalties_suggestion + penalties_loops + penalties_tech_debt + penalties_ac_coverage + penalties_diff ))
[ "$score" -lt 0 ] && score=0

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
