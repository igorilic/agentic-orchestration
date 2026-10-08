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
phys="$(cd "$root" && pwd -P)"

# Hooks run OUTSIDE the sandbox, so only run a .anw/verify whose exact content you approved at
# this exact path (like `direnv allow`). A cloned, copied or agent-modified script is never executed.
trust="${ANW_TRUST_FILE:-$HOME/.claude/anw/trusted-verify}"
if ! grep -qxF "$(shasum -a 256 "$phys/.anw/verify")" "$trust" 2>/dev/null; then
  jq -nc --arg p "$root/.anw/verify" --arg r "$root" '{systemMessage:("⚠️ Not run: " + $p + " is new or changed, or trusted only for another repo. Review it, then run: ai-native-workflow trust " + ($r | @sh))}'
  exit 0
fi

# What a trusted script runs (tests, Makefile) may be code the agent just wrote, so it runs in a
# sandbox with the agent's own file limits (config/claude-settings.json, kept in sync by
# tests/verify-sandbox.bats): writes only to the repo, temp and caches, never to the repo's git
# hooks, agent config or finish line; no reading keys and credentials. Network stays open.
profile='(version 1)
(define (home p) (subpath (string-append (param "HOME") p)))
(define (home-file p) (literal (string-append (param "HOME") p)))
(define (repo p) (subpath (string-append (param "REPO") p)))
(define (repo-file p) (literal (string-append (param "REPO") p)))
(allow default)
(deny file-write*)
(allow file-write* (subpath (param "REPO")) (subpath (param "TMP")) (subpath "/private/tmp") (subpath "/private/var/folders")
  (literal "/dev/null") (literal "/dev/zero") (literal "/dev/tty") (literal "/dev/ptmx") (literal "/dev/stdout")
  (literal "/dev/stderr") (literal "/dev/dtracehelper") (literal "/dev/autofs_nowait") (regex #"^/dev/fd/") (regex #"^/dev/ttys[0-9]+$")
  (home "/.npm") (home "/.cache") (home "/Library/Caches") (home "/.nuget") (home "/.dotnet") (home "/go") (home "/.cargo")
  (home "/Library/Developer/Xcode/DerivedData"))
(deny file-write* (repo "/.git/hooks") (repo-file "/.git/config") (repo "/.claude") (repo "/.anw") (repo "/.github/hooks")
  (repo "/.vscode") (repo-file "/.mcp.json"))
(deny file-read* (home "/.ssh") (home "/.aws") (home "/.azure") (home "/.kube") (home "/.gnupg") (home "/.config/gh")
  (home "/.config/glab-cli") (home-file "/.netrc") (home-file "/.git-credentials")
  (regex #"/\.env$") (regex #"/\.env\.[^/]*$") (regex #"\.pem$") (regex #"\.key$"))'
sandboxed() {
  # Sandboxes don't nest: inside one (Copilot runs its hooks sandboxed) that one already contains
  # the check. Without sandbox-exec (not macOS) the check runs unsandboxed, as trust warned.
  if /usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
    /usr/bin/sandbox-exec -D REPO="$phys" -D HOME="$(cd ~ && pwd -P)" -D TMP="$(cd "${TMPDIR:-/tmp}" && pwd -P)" -p "$profile" "$@"
  else
    "$@"
  fi
}

if out="$(cd "$root" && sandboxed ./.anw/verify 2>&1)"; then rm -f "$marker"; exit 0; fi

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
