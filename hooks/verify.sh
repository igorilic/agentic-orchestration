#!/usr/bin/env bash
# verify.sh — Stop (Claude Code) and agentStop (Copilot CLI) hook.
# If this session edited files (guard.sh leaves a marker), the agent may not finish while the
# project's own check is red. Turns that edited nothing (Q&A, reviews) are never touched.
#
# Opt-in per repo: runs only if <repo>/.anw/verify is executable (e.g. `exec make test`).
# guard.sh denies agent edits to .anw/, so the agent cannot rewrite its own finish line.
set -uo pipefail

payload="$(cat)"
field() { jq -r "($1) // empty" <<<"$payload" 2>/dev/null; }

marker="${TMPDIR:-/tmp}/anw-edited-$(field '.session_id // .sessionId')"
[ -f "$marker" ] || exit 0

cd "$(field '.cwd // .workingDirectory')" 2>/dev/null || cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -x "$root/.anw/verify" ] || exit 0

# Hooks run OUTSIDE the sandbox, so only run a .anw/verify whose exact content you approved at
# this exact path (like `direnv allow`). A cloned, copied or agent-modified script is never executed.
trust="${ANW_TRUST_FILE:-$HOME/.claude/anw/trusted-verify}"
if ! grep -qxF "$(shasum -a 256 "$(cd "$root" && pwd -P)/.anw/verify")" "$trust" 2>/dev/null; then
  jq -nc --arg p "$root/.anw/verify" --arg r "$root" '{systemMessage:("⚠️ Not run: " + $p + " is new or changed, or trusted only for another repo. Review it, then run: ai-native-workflow trust " + ($r | @sh))}'
  exit 0
fi

if out="$(cd "$root" && ./.anw/verify 2>&1)"; then rm -f "$marker"; exit 0; fi

# Honest exits: an explicit "BLOCKED:" report, or a second red stop in a row. Tell the human; stop pushing.
# (Escalation channels cut reward hacking 23.6% -> 5.3%; pressure on impossible tasks raises it 3-6x.)
if grep -q '^BLOCKED:' <<<"$(field '.last_assistant_message')"; then
  rm -f "$marker"
  jq -nc '{systemMessage:"⚠️ The agent escalated with BLOCKED: and .anw/verify is failing — needs your decision."}'
  exit 0
fi
if [ "$(field '.stop_hook_active // .stopHookActive')" = true ]; then
  rm -f "$marker"
  jq -nc '{systemMessage:"⚠️ .anw/verify is still failing — treat any \"done\" claim in this turn as false."}'
  exit 0
fi

jq -nc --arg r "$(printf '%s\n%s' \
  'The project check (.anw/verify) is failing, so this is not done. Fix the code, not the tests. If a test or the spec is wrong, or the task is impossible, end your reply with a line starting "BLOCKED:" and the evidence — that is always preferable to gaming the check.' \
  "$(tail -n 30 <<<"$out")")" '{decision:"block", reason:$r}'
