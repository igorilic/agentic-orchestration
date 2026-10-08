#!/usr/bin/env bats
# HARNESS-2 P1-5: `install project` and `trust`.
# Each repo gets a tracked .anw/verify (its full test command). The Stop hooks run
# it only if you trusted that exact content at that exact path.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
HOOKS="$BATS_TEST_DIRNAME/../hooks"

setup() {
  SANDBOX="$(cd "$(mktemp -d "$BATS_TMPDIR/aw-proj-XXXXXX")" && pwd -P)"
  P="$SANDBOX/repo"; mkdir -p "$P"; git -C "$P" init -q
  export ANW_TRUST_FILE="$SANDBOX/trusted-verify"
}
teardown() { rm -rf "$SANDBOX"; }

anw() { "$INSTALLER" "$@"; }
verify_lines() { grep -v '^#' "$P/.anw/verify"; }
trusted() { grep -qxF "$(shasum -a 256 "$P/.anw/verify")" "$ANW_TRUST_FILE" 2>/dev/null; }

# --- .anw/verify -------------------------------------------------------------------
@test "verify: each stack gets its full test command, and a Makefile test target wins" {
  check() { # $1 = files to create, $2 = expected script body
    rm -rf "$P"; mkdir -p "$P"; (cd "$P" && eval "$1")
    anw install project "$P" </dev/null >/dev/null
    [ -x "$P/.anw/verify" ] && [ "$(verify_lines)" = "$2" ] || { echo "for [$1] got:"; cat "$P/.anw/verify"; return 1; }
  }
  check 'printf "test:\n\tgo test ./...\n" > Makefile; touch go.mod' 'exec make test'
  check 'touch go.mod'                                              'exec go test ./...'
  check 'touch Cargo.toml'                                          'exec cargo test'
  check 'touch app.sln'                                             'exec dotnet test'
  check 'touch pyproject.toml uv.lock'                              'exec uv run pytest'
  check 'touch pyproject.toml poetry.lock'                          'exec poetry run pytest'
  check 'touch requirements.txt'                                    'exec python3 -m pytest'
  check 'echo "{\"scripts\":{\"test\":\"vitest run\"}}" > package.json; touch pnpm-lock.yaml' 'exec pnpm test'
  check 'echo "{\"scripts\":{\"test\":\"jest\"}}" > package.json; touch yarn.lock'            'exec yarn test'
  check 'echo "{\"scripts\":{\"test\":\"jest\"}}" > package.json'                             'exec npm test'
  check 'touch Package.swift'                                       'exec swift test'
  check 'touch go.mod; echo "{\"scripts\":{\"test\":\"jest\"}}" > package.json' "$(printf 'set -e\ngo test ./...\nnpm test')"
}
@test "verify: no runnable test command means no script, plus a hint (npm's placeholder test doesn't count)" {
  echo '{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}' > "$P/package.json"
  run anw install project "$P" </dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$P/.anw/verify" ]
  [[ "$output" == *"ai-native-workflow trust"* ]] || false
}
@test "verify: an existing .anw/verify is never overwritten" {
  mkdir -p "$P/.anw"; printf '#!/bin/sh\nexec ./my-checks\n' > "$P/.anw/verify"; chmod +x "$P/.anw/verify"; touch "$P/go.mod"
  anw install project "$P" </dev/null >/dev/null
  [ "$(verify_lines)" = 'exec ./my-checks' ]
}

# --- trust -------------------------------------------------------------------------
@test "trust: install project shows the script and trusts it only on y" {
  touch "$P/go.mod"
  run anw install project "$P" <<<"n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exec go test ./..."* && "$output" == *"sandbox"* ]] || false
  ! trusted || false
  run anw trust "$P" <<<"y"
  [ "$status" -eq 0 ]
  [ "$(cat "$ANW_TRUST_FILE")" = "$(shasum -a 256 "$P/.anw/verify")" ]
}
@test "trust: declining exits non-zero and writes nothing" {
  touch "$P/go.mod"; anw install project "$P" </dev/null >/dev/null
  run anw trust "$P" <<<"n"
  [ "$status" -ne 0 ]
  [ ! -s "$ANW_TRUST_FILE" ]
}
@test "trust: re-trusting replaces this repo's entry, drops legacy hash-only lines, keeps other repos" {
  touch "$P/go.mod"; anw install project "$P" <<<"y" >/dev/null
  printf '%064d\n' 0 >> "$ANW_TRUST_FILE"
  printf '%064d  /elsewhere/.anw/verify\n' 1 >> "$ANW_TRUST_FILE"
  echo "# edited" >> "$P/.anw/verify"
  anw trust "$P" <<<"y" >/dev/null
  [ "$(wc -l < "$ANW_TRUST_FILE")" -eq 2 ]
  trusted
  grep -q '  /elsewhere/.anw/verify$' "$ANW_TRUST_FILE"
}
@test "trust: refuses a missing or non-executable script" {
  run anw trust "$P" <<<"y"
  [ "$status" -ne 0 ]
  mkdir -p "$P/.anw"; echo 'exit 0' > "$P/.anw/verify"
  run anw trust "$P" <<<"y"
  [ "$status" -ne 0 ]
  [ ! -s "$ANW_TRUST_FILE" ]
}
@test "trust + hook: verify.sh runs the trusted script, but not a byte-identical copy in another repo" {
  Q="$SANDBOX/clone"; mkdir -p "$Q"; git -C "$Q" init -q
  for r in "$P" "$Q"; do mkdir -p "$r/.anw"; printf '#!/bin/sh\ntouch ran\n' > "$r/.anw/verify"; chmod +x "$r/.anw/verify"; done
  anw trust "$P" <<<"y" >/dev/null
  export TMPDIR="$SANDBOX/tmp"; mkdir -p "$TMPDIR"
  for r in "$P" "$Q"; do
    touch "$TMPDIR/anw-edited-s"
    jq -nc --arg d "$r" '{session_id:"s",hook_event_name:"Stop",cwd:$d}' | bash "$HOOKS/verify.sh" >/dev/null
  done
  [ -e "$P/ran" ] && [ ! -e "$Q/ran" ] || false
}

# --- .gitignore, AGENTS.md, CLAUDE.md --------------------------------------------------
@test "gitignore: .anw/ runtime files are ignored but .anw/verify stays tracked; an old bare .anw/ is migrated" {
  printf 'node_modules/\n.anw/\n' > "$P/.gitignore"
  touch "$P/go.mod"; anw install project "$P" </dev/null >/dev/null
  git -C "$P" check-ignore -q .anw/.pipeline-state
  ! git -C "$P" check-ignore -q .anw/verify || false
  grep -qx 'node_modules/' "$P/.gitignore"
  anw install project "$P" </dev/null >/dev/null
  [ "$(grep -cxF '.anw/*' "$P/.gitignore")" -eq 1 ] && [ "$(grep -cxF '!.anw/verify' "$P/.gitignore")" -eq 1 ] || false
}
@test "gitignore: a last line without a newline is not glued to ours" {
  printf 'dist' > "$P/.gitignore"
  anw install project "$P" </dev/null >/dev/null
  grep -qx 'dist' "$P/.gitignore" && grep -qxF '.anw/*' "$P/.gitignore" || false
}
@test "AGENTS.md: at most 80 lines; commands first (with the finish line), then Always / Ask first / Never" {
  touch "$P/go.mod"; anw install project "$P" </dev/null >/dev/null
  [ "$(wc -l < "$P/AGENTS.md")" -le 80 ]
  [ "$(grep '^## ' "$P/AGENTS.md" | head -1)" = "## Commands" ]
  [ "$(grep -E '^## (Always|Ask first|Never)$' "$P/AGENTS.md" | paste -sd, -)" = "## Always,## Ask first,## Never" ]
  sed -n '/^## Commands/,/^## [^C]/p' "$P/AGENTS.md" > "$SANDBOX/cmds"
  grep -qF 'go test ./...' "$SANDBOX/cmds" && grep -qF './.anw/verify' "$SANDBOX/cmds" || false
  grep -q 'BLOCKED:' "$P/AGENTS.md"
}
@test "CLAUDE.md imports AGENTS.md; existing AGENTS.md and CLAUDE.md are never overwritten" {
  anw install project "$P" </dev/null >/dev/null
  grep -qx '@AGENTS.md' "$P/CLAUDE.md"
  echo mine > "$P/AGENTS.md"; echo mine > "$P/CLAUDE.md"
  anw install project "$P" </dev/null >/dev/null
  [ "$(cat "$P/AGENTS.md")" = mine ] && [ "$(cat "$P/CLAUDE.md")" = mine ] || false
}
@test "no Copilot-only files are generated: AGENTS.md serves both tools, the global guard replaces repo hooks" {
  touch "$P/go.mod"; anw install project "$P" </dev/null >/dev/null
  [ ! -e "$P/.github" ]
}

# --- legacy ------------------------------------------------------------------------
@test "legacy: install project removes the old per-project Copilot hook layer and keeps your hook entries" {
  H="$P/.github/hooks"; mkdir -p "$H/scripts"
  echo x > "$H/copilot-cli-dispatcher.sh"; echo x > "$H/scripts/confidence.sh"
  printf '# .github/hooks — AI-Native Workflow: Copilot CLI Hook Layer\n' > "$H/README.md"
  echo '{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"./copilot-cli-dispatcher.sh","cwd":".github/hooks"},{"type":"command","bash":"./mine.sh"}]}}' > "$H/copilot-cli-policy.json"
  anw install project "$P" </dev/null >/dev/null
  [ ! -e "$H/copilot-cli-dispatcher.sh" ] && [ ! -e "$H/scripts" ] && [ ! -e "$H/README.md" ] || false
  [ "$(jq -c '[.hooks.preToolUse[].bash]' "$H/copilot-cli-policy.json")" = '["./mine.sh"]' ]
}
@test "legacy: uninstall project removes it too, including a policy that only had our entry" {
  H="$P/.github/hooks"; mkdir -p "$H"; echo x > "$H/copilot-cli-dispatcher.sh"
  echo '{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"./copilot-cli-dispatcher.sh"}]}}' > "$H/copilot-cli-policy.json"
  echo keep > "$P/AGENTS.md"
  anw uninstall project "$P" >/dev/null
  [ ! -e "$P/.github" ]
  [ "$(cat "$P/AGENTS.md")" = keep ]
}
