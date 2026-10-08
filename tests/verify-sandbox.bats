#!/usr/bin/env bats
# HARNESS-2 P1-5b (spec R14): Claude Code runs hooks outside its sandbox, so verify.sh runs
# .anw/verify inside one with the agent's own file limits; network stays open.
# The confinement tests need sandbox-exec outside any other sandbox. Inside one (an agent's
# Bash tool, or verify itself running `make test`) they skip. Run them in a plain terminal:
#   make test-file FILE=tests/verify-sandbox.bats
bats_require_minimum_version 1.5.0

HOOKS="$BATS_TEST_DIRNAME/../hooks"
POLICY="$BATS_TEST_DIRNAME/../config/claude-settings.json"

needs_sandbox() {
  /usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null \
    || skip "needs sandbox-exec outside any sandbox: make test-file FILE=tests/verify-sandbox.bats"
  # "Elsewhere in your home" must be outside the always-writable temp dirs, so HOME lives in the checkout.
  case "$(cd "$BATS_TEST_DIRNAME" && pwd -P)" in /private/tmp/*|/private/var/folders/*) skip "checkout is inside a temp dir" ;; esac
  OUT="$BATS_TEST_DIRNAME/.verify-sandbox.$$.$BATS_TEST_NUMBER"
  export HOME="$OUT/home" TMPDIR="$BATS_TEST_TMPDIR/tmp" ANW_TRUST_FILE="$BATS_TEST_TMPDIR/trust"
  mkdir -p "$HOME/.ssh" "$TMPDIR"; echo SECRET-KEY > "$HOME/.ssh/id_test"
  REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO"; cd "$REPO"; git init -q
  echo TOKEN=SECRET-ENV > .env
}
teardown() { if [ -n "${OUT:-}" ]; then rm -rf "$OUT"; fi; }

# Trust $1 as this repo's .anw/verify, then run the real Stop hook for an editing session.
check() {
  mkdir -p .anw; printf '#!/bin/sh\n%s\n' "$1" > .anw/verify; chmod +x .anw/verify
  shasum -a 256 "$(pwd -P)/.anw/verify" >> "$ANW_TRUST_FILE"; touch "$TMPDIR/anw-edited-s"
  run --separate-stderr bash "$HOOKS/verify.sh" <<<"$(jq -nc --arg d "$REPO" '{session_id:"s",hook_event_name:"Stop",cwd:$d}')"
}
blocked() { [ "$(jq -r .decision <<<"$output")" = block ]; }

@test "policy sync: the verify sandbox mirrors the agent sandbox in config/claude-settings.json" {
  for p in $(jq -r '.sandbox.filesystem.allowWrite[] | sub("^~"; "")' "$POLICY"); do
    grep -qF "(home \"$p\")" "$HOOKS/verify.sh" || { echo "verify can't write ~$p"; false; }
  done
  for p in $(jq -r '.permissions.deny[] | capture("^Read\\(~(?<p>[^*]*)/\\*\\*\\)$").p' "$POLICY"); do
    grep -qF "(home \"$p\")" "$HOOKS/verify.sh" || { echo "verify may read ~$p"; false; }
  done
  for r in '/\.env$' '/\.env\.[^/]*$' '\.pem$' '\.key$'; do
    grep -qF "(regex #\"$r\")" "$HOOKS/verify.sh" || { echo "verify may read $r"; false; }
  done
}
@test "sandbox: the check can write the repo, temp and your caches" {
  needs_sandbox
  check 'touch built && touch "$TMPDIR/t" && mkdir -p "$HOME/.cache/x" && touch "$HOME/.cache/x/y"'
  [ -z "$output" ]
  [ -e built ] && [ -e "$TMPDIR/t" ] && [ -e "$HOME/.cache/x/y" ] || false
}
@test "sandbox: the check cannot write anywhere else in your home" {
  needs_sandbox
  check 'touch "$HOME/.zshrc"'
  blocked
  [ ! -e "$HOME/.zshrc" ]
}
@test "sandbox: the check cannot plant git hooks, agent config or a new finish line in the repo" {
  needs_sandbox
  for t in .git/hooks/pre-commit .git/config .claude/settings.json .anw/verify2 .github/hooks/x.json .vscode/tasks.json .mcp.json; do
    before="$(cat "$t" 2>/dev/null || true)"
    check "mkdir -p \"\$(dirname '$t')\" 2>/dev/null; echo planted >> '$t'"
    blocked || { echo "not blocked: $t"; false; }
    [ "$(cat "$t" 2>/dev/null || true)" = "$before" ] || { echo "written: $t"; false; }
  done
}
@test "sandbox: the check cannot read your keys or .env files" {
  needs_sandbox
  check 'cat "$HOME/.ssh/id_test" .env'
  blocked
  [[ "$output" != *SECRET* ]] || false
}
