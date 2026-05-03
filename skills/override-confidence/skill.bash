#!/usr/bin/env bash
# Sourceable function — used by SKILL.md and tests.

override_confidence() {
  local reason="$1"
  local boilerplate_re='^(\.|fix|override|x|y|skip|bypass|no|none)$'

  # Trim whitespace.
  reason="${reason#"${reason%%[![:space:]]*}"}"
  reason="${reason%"${reason##*[![:space:]]}"}"

  if [ -z "$reason" ]; then
    echo "🚫 /override-confidence requires a non-empty reason." >&2
    return 1
  fi

  # Reject boilerplate single tokens.
  if echo "$reason" | grep -qiE "$boilerplate_re"; then
    echo "🚫 /override-confidence reason looks like boilerplate. Be specific." >&2
    return 1
  fi

  # Require minimum length to discourage low-effort reasons.
  if [ "${#reason}" -lt 12 ]; then
    echo "🚫 /override-confidence reason must be at least 12 characters." >&2
    return 1
  fi

  if [ ! -f ".git/aw/active-spec" ]; then
    echo "🚫 /override-confidence: no .git/aw/active-spec pointer." >&2
    return 1
  fi

  local spec_id branch ts user
  spec_id="$(cat .git/aw/active-spec)"
  branch="$(git branch --show-current 2>/dev/null || echo unknown)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  user="$(git config user.email 2>/dev/null || git config user.name 2>/dev/null || echo unknown)"

  jq -n \
    --arg reason "$reason" \
    --arg branch "$branch" \
    --arg ts "$ts" \
    --arg user "$user" \
    '{reason:$reason, branch:$branch, ts:$ts, user:$user}' \
    > ".git/aw/override-${spec_id}"

  echo "✅ /override-confidence active for spec $spec_id. Auto-clears after next PR/MR creation." >&2
}
