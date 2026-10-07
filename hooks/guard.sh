#!/usr/bin/env bash
# guard.sh — one pre-tool gate for Claude Code (PreToolUse) and Copilot CLI (preToolUse).
#
# Contract (both tools): the hook payload arrives as JSON on STDIN.
#   Claude : {"tool_name":"Bash","tool_input":{"command":"..."},"cwd":"..."}
#   Copilot: {"toolName":"bash","toolArgs":"{\"command\":\"...\"}","cwd":"..."}
# Output: a deny/ask decision as JSON on stdout, or nothing (= no opinion; the
# tool's normal permission flow applies). Never emits "allow" — "allow" would
# auto-approve the call and silently bypass the user's permission rules.
# Fail-closed: if this script crashes, the call is denied.
set -Eeuo pipefail

flavor=claude
crash() {
  if [ "$flavor" = copilot ]; then
    printf '%s\n' '{"permissionDecision":"deny","permissionDecisionReason":"guard.sh crashed; failing closed"}'
    exit 0
  fi
  echo "guard.sh crashed; failing closed" >&2
  exit 2 # Claude: only exit 2 blocks — any other non-zero exit lets the call through
}
trap crash ERR

payload="$(cat)"
jq -e 'has("toolName")' <<<"$payload" >/dev/null && flavor=copilot

decide() { # $1 = deny|ask, $2 = reason shown to the model (deny) or the human (ask)
  if [ "$flavor" = copilot ]; then
    jq -nc --arg d "$1" --arg r "$2" '{permissionDecision:$d, permissionDecisionReason:$r}'
  else
    jq -nc --arg d "$1" --arg r "$2" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
  fi
  exit 0
}

tool="$(jq -r '(.tool_name // .toolName // "") | ascii_downcase' <<<"$payload")"
args="$(jq -c '(.tool_input // .toolArgs // {}) | if type == "string" then (fromjson? // {}) else . end' <<<"$payload")"
cwd="$(jq -r '.cwd // .workingDirectory // empty' <<<"$payload")"
cd "${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}" 2>/dev/null

# Test files, by path convention (not substring: "latest.md" and "inspector.ts" are not tests).
TEST_RE='(^|/)(tests?|__tests__|specs?)/|(^|/)test_[^/]*$|[._-](test|spec)s?\.[^/]+$|Tests?\.[^/]+$|(^|/)conftest\.py$'
# Added lines that skip or focus tests (jest/vitest/mocha, pytest, unittest, go, rust, xunit, junit, xctest).
SKIP_RE='\.(skip|only|todo)\(|(^|[^.[:alnum:]_])(xit|xdescribe|xtest|fit|fdescribe)\(|@pytest\.mark\.(skip|xfail)|pytest\.(skip|xfail)\(|unittest\.skip|(^|[^[:alnum:]_])t\.Skip(Now|f)?\(|#\[ignore\]|Skip[[:space:]]*=[[:space:]]*"|@Disabled|@Ignore([^[:alnum:]_]|$)|XCTSkip'
ASSERT_RE='assert|expect\(|\.should|Assert\.|XCTAssert|require\.|\.Should\(\)|t\.(Error|Fatal)'

check_path() { # $1 = a path an edit tool is about to write
  local path="$1"
  # shellcheck disable=SC2088 # matching the literal "~/" an agent may send
  case "$path" in "~/"*) path="$HOME/${path#\~/}" ;; /*) ;; *) path="$PWD/$path" ;; esac
  case "$path" in
      "$HOME/.claude/"hooks/* | "$HOME/.claude/"skills/* | "$HOME/.claude/"agents/* | "$HOME/.claude/"commands/* | \
      "$HOME/.claude/"anw/* | "$HOME/.claude/"plugins/* | "$HOME/.claude/CLAUDE.md" | \
      "$HOME/.copilot/"hooks/* | "$HOME/.copilot/"skills/* | "$HOME/.copilot/"agents/* | "$HOME/.copilot/"installed-plugins/* | \
      "$HOME/.copilot/"settings.json | "$HOME/.copilot/"config.json | "$HOME/.copilot/"mcp-config.json | \
      "$HOME/.copilot/"permissions-config.json | "$HOME/.copilot/copilot-instructions.md" | \
      */.claude/settings.json | */.claude/settings.local.json | */.git/* | */.github/hooks/* | */.anw/*)
        decide deny "Protected harness path: $path. Agents may not edit their own guardrails, hooks, or gate state." ;;
      "$HOME/.claude/"* | "$HOME/.copilot/"*)
        ;; # the tools' own working files (memory, plans, transcripts, session state)
      */.github/workflows/* | */.gitlab-ci.yml)
        decide ask "Edits CI config ($path). CI is the ground truth for tests — approve only if intended." ;;
      */AGENTS.md | */CLAUDE.md | */.github/copilot-instructions.md | */.github/instructions/* | */.github/agents/* | */.github/skills/* | */.claude/* | */.mcp.json | */.vscode/tasks.json)
        decide ask "Edits agent instructions or agent config ($path). This changes how future agents and reviewers behave — approve only if intended." ;;
  esac
}

case "$tool" in
  write|edit|multiedit|notebookedit|create|str_replace_editor|apply_patch)
    # Remember that this session edited files: verify.sh runs the project check only for such sessions.
    # ponytail: Bash-only edits (sed/python) don't mark; the pre-push verify and CI still catch those.
    touch "${TMPDIR:-/tmp}/anw-edited-$(jq -r '.session_id // .sessionId // empty' <<<"$payload")" 2>/dev/null || true
    if [ "$tool" = apply_patch ]; then
      # Copilot's file writes: toolArgs is a raw patch ("*** Add File: x", "*** Update File: y", "*** Move to: z").
      patch="$(jq -r '(.toolArgs // .tool_input // "") | if type == "string" then (fromjson? // .) else . end
                      | if type == "string" then . else (.input // .patch // "") end' <<<"$payload")"
      while IFS= read -r p; do
        if [ -n "$p" ]; then check_path "$p"; fi
      done < <(sed -n -E 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p; s/^\*\*\* Move to: (.*)$/\1/p' <<<"$patch")
    else
      path="$(jq -r '.file_path // .path // .notebook_path // .filePath // empty' <<<"$args")"
      if [ -n "$path" ]; then check_path "$path"; fi
    fi
    exit 0
    ;;
  bash) ;;
  *) exit 0 ;;
esac

cmd="$(jq -r '.command // empty' <<<"$args")"
[ -n "$cmd" ] || exit 0

# Hook bypasses are never OK for an agent. (Global settings also deny these; this covers Copilot.)
if grep -qE 'git[[:space:]].*(commit|push|merge|rebase).*--no-verify|git[[:space:]]+commit[^|;&]*[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)|core\.hooksPath|(^|[[:space:]])(HUSKY=0|SKIP=)[^[:space:]]*[[:space:]].*git' <<<"$cmd"; then
  decide deny "Bypassing git hooks (--no-verify / -n / core.hooksPath / HUSKY=0 / SKIP=) is not allowed for agents."
fi

# A nested agent launched without hooks/permissions escapes every guard in this file.
if grep -qE '(^|[^[:alnum:]_-])(claude|copilot)([[:space:]]|$).*(--bare|--dangerously-skip-permissions|bypassPermissions|--yolo|--allow-all([[:space:]=]|$)|--allow-all-tools|--allow-all-paths)' <<<"$cmd"; then
  decide deny "Launching a nested agent with hooks or permissions disabled is not allowed."
fi

# Shell writes to the guardrails themselves.
# ponytail: regex heuristic catches the naive tamper; the real control is the OS sandbox (denyWrite).
writes="$(sed -E 's/[0-9&]*>>?[[:space:]]*(\/dev\/null|&[0-9])//g' <<<"$cmd")" # ignore 2>/dev/null, 2>&1
if grep -qE '(\.claude|\.copilot)/(hooks|settings|agents|skills|commands|anw|plugins|installed-plugins|CLAUDE\.md|copilot-instructions|mcp-config|permissions-config|config\.json)|\.github/hooks|\.git/hooks|(^|/)\.anw/' <<<"$cmd" &&
   grep -qE '(^|[^[:alnum:]_])(rm|mv|cp|tee|ln|chmod|truncate|install|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|python3?|node|ruby)([^[:alnum:]_]|$)|>' <<<"$writes"; then
  decide deny "Shell write to a protected harness path. Agents may not modify their own hooks, settings, or gate state."
fi

# A new dependency is a supply-chain decision (slopsquatting, look-alike packages): a human approves the name.
# ponytail: lockfile installs (`npm ci`, bare `npm install`, `pip install -r`) pass; npx one-offs are not covered.
if grep -qE '(^|[;&|[:space:]])((npm|pnpm|yarn|bun)[[:space:]]+(install|i|add)|pip3?[[:space:]]+install|uv[[:space:]]+(add|pip[[:space:]]+install)|(cargo|poetry)[[:space:]]+add|go[[:space:]]+get|dotnet[[:space:]]+add[[:space:]].*package)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]]' <<<"$cmd" &&
   ! grep -qE 'install[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-r[[:space:]]' <<<"$cmd"; then
  decide ask "Adds a new dependency ($cmd). Check the exact package name, publisher and age before approving — agents install look-alike packages."
fi

grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' <<<"$cmd" || exit 0
# No --amend exemption: amending can fold a test deletion into an existing commit just as well.

staged="$(git diff --cached --name-only --diff-filter=ACMR)"
deleted_tests="$(git diff --cached --name-only --diff-filter=D | grep -E "$TEST_RE" || true)"
test_files="$(grep -E "$TEST_RE" <<<"$staged" || true)"
src_files="$(grep -vE "$TEST_RE" <<<"$staged" | grep -vE '\.(md|txt|rst|adoc|lock)$|(^|/)(docs|spikes)/|^\.github/|(^|/)(LICENSE|CHANGELOG)' || true)"

problems=""
[ -n "$deleted_tests" ] && problems="${problems}deletes test files: $(tr '\n' ' ' <<<"$deleted_tests"); "

if [ -n "$staged" ]; then
  added_skips="$(git diff --cached -U0 -- . ':(exclude)*.md' | grep -E '^\+[^+]' | grep -E "$SKIP_RE" || true)"
  [ -n "$added_skips" ] && problems="${problems}adds skip/focus markers: $(head -3 <<<"$added_skips" | tr '\n' ' '); "
fi

if [ -n "$test_files" ]; then
  # A removed assertion line in an already-committed test is the classic reward hack
  # (weaken the check instead of fixing the code). Brand-new tests have no removed lines.
  # shellcheck disable=SC2086 # one pathspec per test file; ponytail: paths with spaces split
  removed_asserts="$(git diff --cached -U0 -- $test_files | grep -E '^-[^-]' | grep -cE "$ASSERT_RE" || true)"
  [ "${removed_asserts:-0}" -gt 0 ] && problems="${problems}removes or rewrites $removed_asserts assertion line(s) in existing tests; "
fi

if [ -n "$src_files" ] && [ -z "$test_files" ]; then
  problems="${problems}changes source without touching any test (TDD expects a test with every behavior change); "
fi

[ -n "$problems" ] && decide ask "Test-integrity check: ${problems}Approve only if this is intentional (e.g. a pure refactor or a test that was genuinely wrong)."
exit 0
