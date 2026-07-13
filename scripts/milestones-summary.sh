#!/usr/bin/env bash
# scripts/milestones-summary.sh — SDK-1 Step B-8 (spec OQ-7/AC-12): delegation
# cost/quality summary derived from a milestones.jsonl file. One jq slurp
# does all the counting — no hand-rolled parsing loop.
#
# Usage: scripts/milestones-summary.sh <path-to-milestones.jsonl>
#
# ponytail: "accepted" has no dedicated event in the OQ-2 schema (event ∈
# phase|step|deleg|deleg_reject|verdict|done — lib/milestones.sh). Per the
# spec's parent-review-gate contract (OQ-1: every `deleg` MUST be followed by
# either an accepting `step|ok` milestone or a `deleg_reject`), accepted is
# derived as total_deleg - rejected rather than pattern-matched against
# free-text step milestones, which the spec never mandates specific wording
# for.
set -euo pipefail

FILE="${1:-}"

print_zero_summary() {
  cat <<'EOF'
Total delegations: 0
Accepted: 0
Rejected: 0

Per-agent delegation counts:
  (none)
EOF
}

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  print_zero_summary
  exit 0
fi

jq -s -r '
  (map(select(.event == "deleg")))                                as $delegs
  | (map(select(.event == "deleg_reject")) | length)               as $rejected
  | ($delegs | length)                                              as $total
  | ($total - $rejected)                                            as $accepted
  | ($delegs | group_by(.agent)
     | map({agent: .[0].agent, count: length})
     | sort_by(.agent))                                             as $per_agent
  | "Total delegations: \($total)",
    "Accepted: \($accepted)",
    "Rejected: \($rejected)",
    "",
    "Per-agent delegation counts:",
    (if ($per_agent | length) == 0
     then "  (none)"
     else ($per_agent[] | "  \(.agent): \(.count)")
     end)
' "$FILE"
