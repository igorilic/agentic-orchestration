#!/usr/bin/env bats
# HARNESS-2 P1-4: native-first global install.
# Two hooks and the skills (copies, so editing this repo never changes live
# enforcement), a merged settings policy, managed instructions, and no agents.
# Anything earlier versions installed is retired into <home>/anw-backup/,
# never deleted, and your own skills/agents/hooks stay.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
RETIRED_SKILLS="tdd skip-tdd override-confidence brainstorm pipeline-github-feature pipeline-gitlab-feature pipeline-gitlab-incident"

setup() {
  SANDBOX="$(mktemp -d "$BATS_TMPDIR/aw-native-XXXXXX")"
  STUB="$SANDBOX/stub"; mkdir -p "$STUB" "$SANDBOX/home"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/copilot"; chmod +x "$STUB/copilot"
  C="$SANDBOX/claude"; P="$SANDBOX/copilot"
}
teardown() { rm -rf "$SANDBOX"; }

anw() { HOME="$SANDBOX/home" PATH="$STUB:$PATH" CLAUDE_HOME="$C" COPILOT_HOME="$P" "$INSTALLER" "$@"; }
installed_skills() { local d n; for d in "$REPO"/skills/*/; do n="$(basename "$d")"; case " $RETIRED_SKILLS " in *" $n "*) ;; *) echo "$n" ;; esac; done; }
cmds() { jq -r '[.hooks // {} | .[][] | .hooks[]?.command] | .[]' "$C/settings.json"; }
# Append to an installed file, but never through a link into the repo: if the
# installer regressed to symlinks, a plain >> would corrupt the source files.
edit_installed() {
  case "$(cd "$(dirname "$1")" && pwd -P)/" in "$(cd "$SANDBOX" && pwd -P)"/*) ;; *) echo "refusing to write outside the sandbox: $1"; return 1 ;; esac
  [ ! -L "$1" ] || { echo "refusing to write through a link: $1"; return 1; }
  echo "$2" >> "$1"
}

# --- hooks ---------------------------------------------------------------------
@test "hooks: guard.sh and verify.sh are regular files, byte-identical to the repo, in both homes" {
  anw install global
  for d in "$C/hooks" "$P/hooks"; do
    for f in guard.sh verify.sh; do
      [ -f "$d/$f" ] && [ ! -L "$d/$f" ] && [ -x "$d/$f" ] || { echo "missing/not a copy: $d/$f"; false; }
      cmp -s "$REPO/hooks/$f" "$d/$f" || { echo "drift: $d/$f"; false; }
    done
  done
}
@test "hooks: the old gates, session-start and confidence scripts are retired to anw-backup" {
  mkdir -p "$C/hooks" "$C/scripts"
  for f in hooks/session-start.sh hooks/tdd-gate.sh hooks/confidence-gate.sh scripts/confidence.sh scripts/confidence-cli.sh; do echo old > "$C/$f"; done
  anw install global
  for f in hooks/session-start.sh hooks/tdd-gate.sh hooks/confidence-gate.sh scripts/confidence.sh scripts/confidence-cli.sh; do
    [ ! -e "$C/$f" ] || { echo "still live: $f"; false; }
    ls "$C"/anw-backup/*/"$f" >/dev/null || { echo "not backed up: $f"; false; }
  done
}

# --- Claude settings -------------------------------------------------------------
@test "settings: PreToolUse runs the guard fail-closed; Stop runs verify; paths follow CLAUDE_HOME" {
  anw install global
  jq -e --arg g "bash $C/hooks/guard.sh || exit 2" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash|Edit|Write|MultiEdit|NotebookEdit") | .hooks[] | select(.command == $g)' "$C/settings.json"
  jq -e --arg v "bash $C/hooks/verify.sh" '.hooks.Stop[].hooks[] | select(.command == $v and .timeout == 600)' "$C/settings.json"
}
@test "settings: old gate entries are removed, your own hooks are kept" {
  mkdir -p "$C"
  cat > "$C/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/tdd-gate.sh"},{"type":"command","command":"bash ~/.claude/hooks/confidence-gate.sh"},{"type":"command","command":"my-hook.sh"}]}],
 "SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/session-start.sh"},{"type":"command","command":"my-start.sh"}]}]}}
JSON
  anw install global
  run cmds
  [[ "$output" != *tdd-gate* && "$output" != *confidence-gate* && "$output" != *session-start* ]] || false
  [[ "$output" == *my-hook.sh* && "$output" == *my-start.sh* ]] || false
}
@test "settings: the policy is a union — your keys and rules survive, ours are added" {
  mkdir -p "$C"
  echo '{"model":"opus","statusLine":{"type":"command","command":"x"},"permissions":{"allow":["Bash(make:*)"],"additionalDirectories":["/vault"]}}' > "$C/settings.json"
  anw install global
  jq -e '.model == "opus" and .statusLine.command == "x" and (.permissions.additionalDirectories == ["/vault"])' "$C/settings.json"
  jq -e '(.permissions.allow | index("Bash(make:*)")) and (.permissions.allow | index("Bash(kubectl get:*)"))' "$C/settings.json"
  jq -e '(.permissions.deny | index("Read(**/.env)")) and (.permissions.ask | index("Bash(git push:*)"))' "$C/settings.json"
  jq -e '.permissions.disableBypassPermissionsMode == "disable" and .sandbox.enabled == true' "$C/settings.json"
}
@test "settings: re-install is idempotent, and a stale guard entry is replaced, not duplicated" {
  mkdir -p "$C"
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/guard.sh"}]}]}}' > "$C/settings.json"
  anw install global; cp "$C/settings.json" "$SANDBOX/first.json"
  anw install global
  cmp "$SANDBOX/first.json" "$C/settings.json"
  [ "$(cmds | grep -c 'hooks/guard.sh')" -eq 1 ]
}

# --- Copilot hooks -----------------------------------------------------------------
@test "copilot: hooks/anw.json wires preToolUse→guard (15s) and agentStop→verify (600s), absolute paths" {
  anw install global
  jq -e --arg g "$P/hooks/guard.sh" '.version == 1 and (.hooks.preToolUse[0] | (.bash | contains($g)) and .timeoutSec == 15)' "$P/hooks/anw.json"
  jq -e --arg v "$P/hooks/verify.sh" '.hooks.agentStop[0] | (.bash | contains($v)) and .timeoutSec == 600' "$P/hooks/anw.json"
}

# --- skills ----------------------------------------------------------------------
@test "skills: every non-retired repo skill is a real copy identical to the repo, in both homes" {
  anw install global
  for n in $(installed_skills); do
    for d in "$C/skills" "$P/skills"; do
      [ -d "$d/$n" ] && [ ! -L "$d/$n" ] && diff -rq "$REPO/skills/$n" "$d/$n" || { echo "not a faithful copy: $d/$n"; false; }
    done
  done
  for n in plan check verify incident pr explore; do [ -f "$C/skills/$n/SKILL.md" ]; done
}
@test "skills: retired skills are never installed and old copies are retired" {
  mkdir -p "$C/skills/tdd" "$P/skills/skip-tdd" "$P/skills/plan.bak.20260713T123006Z"
  anw install global
  for n in $RETIRED_SKILLS; do [ ! -e "$C/skills/$n" ] && [ ! -e "$P/skills/$n" ] || { echo "installed: $n"; false; }; done
  [ ! -e "$P/skills/plan.bak.20260713T123006Z" ]
  ls -d "$P"/anw-backup/*/skills/plan.bak.20260713T123006Z >/dev/null
}
@test "skills: an outdated copy or a link into the repo is replaced (backed up); your own skills are untouched" {
  mkdir -p "$C/skills/plan" "$C/skills/kibana"; echo old > "$C/skills/plan/SKILL.md"; echo mine > "$C/skills/kibana/SKILL.md"
  mkdir -p "$P/skills"; ln -s "$REPO/skills/check" "$P/skills/check"
  anw install global
  diff -rq "$REPO/skills/plan" "$C/skills/plan"
  [ -d "$P/skills/check" ] && [ ! -L "$P/skills/check" ] || false
  grep -q old "$C"/anw-backup/*/skills/plan/SKILL.md
  [ ! -L "$C/skills/kibana" ] && grep -q mine "$C/skills/kibana/SKILL.md" || false
}

# --- agents ------------------------------------------------------------------------
@test "agents: none installed; agents this repo used to ship are retired; yours are untouched" {
  mkdir -p "$C/agents" "$P/agents"
  echo x > "$C/agents/architect.md"; echo x > "$C/agents/sidekick.md"; echo mine > "$C/agents/my-agent.md"
  echo x > "$P/agents/qa.agent.md"; echo mine > "$P/agents/mine.agent.md"
  anw install global
  [ ! -e "$C/agents/architect.md" ] && [ ! -e "$C/agents/sidekick.md" ] && [ ! -e "$P/agents/qa.agent.md" ] || false
  [ -f "$C/agents/my-agent.md" ] && [ -f "$P/agents/mine.agent.md" ] || false
  ls "$C"/anw-backup/*/agents/architect.md "$P"/anw-backup/*/agents/qa.agent.md >/dev/null
}

# --- instructions -------------------------------------------------------------------
@test "instructions: fresh install = your preamble + a marked managed block, in both tools" {
  anw install global
  for f in "$C/CLAUDE.md" "$P/copilot-instructions.md"; do
    grep -q 'Solo full-stack developer' "$f"
    grep -q '^<!-- >>> ai-native-workflow managed block' "$f"
    grep -q '^## Working agreements' "$f" && grep -q 'BLOCKED:' "$f" || false
    [ "$(grep -n 'Solo full-stack' "$f" | cut -d: -f1)" -lt "$(grep -n '^<!-- >>> ai-native' "$f" | cut -d: -f1)" ]
  done
  grep -q '/rubber-duck' "$P/copilot-instructions.md"
}
@test "instructions: a file without markers is backed up and appended to, never overwritten" {
  mkdir -p "$C"; printf '# Mine\nLEGACY_KEEP_ME\n' > "$C/CLAUDE.md"
  anw install global
  grep -q LEGACY_KEEP_ME "$C/CLAUDE.md"
  grep -q '^## Working agreements' "$C/CLAUDE.md"
  grep -q LEGACY_KEEP_ME "$C"/anw-backup/*/CLAUDE.md
  anw install global
  [ "$(grep -c '^## Working agreements' "$C/CLAUDE.md")" -eq 1 ]
}
@test "instructions: an unmarked copy of the shipped file is converted in place (no duplicate block)" {
  mkdir -p "$C"; cp "$REPO/instructions/CLAUDE.md" "$C/CLAUDE.md"
  anw install global
  [ "$(grep -c '^## Working agreements' "$C/CLAUDE.md")" -eq 1 ]
  grep -q '^<!-- >>> ai-native-workflow managed block' "$C/CLAUDE.md"
}
@test "instructions: copilot re-install keeps your preamble edits and refreshes the managed block" {
  anw install global
  perl -pi -e 's/Solo full-stack developer/Solo developer (MINE)/; s/^- Ticket, issue.*$/- STALE/' "$P/copilot-instructions.md"
  anw install global
  grep -q 'Solo developer (MINE)' "$P/copilot-instructions.md"
  ! grep -q -- '- STALE' "$P/copilot-instructions.md" || false
  grep -q '^- Ticket, issue' "$P/copilot-instructions.md"
}

# --- environment ----------------------------------------------------------------------
@test "install works through a symlinked entrypoint (brew layout)" {
  mkdir -p "$SANDBOX/bin"; ln -s "$INSTALLER" "$SANDBOX/bin/ai-native-workflow"
  HOME="$SANDBOX/home" PATH="$STUB:$PATH" CLAUDE_HOME="$C" COPILOT_HOME="$P" "$SANDBOX/bin/ai-native-workflow" install global
  diff -rq "$REPO/skills/plan" "$C/skills/plan"
  cmp -s "$REPO/hooks/guard.sh" "$C/hooks/guard.sh"
}
@test "the Copilot side is skipped when copilot is not on PATH" {
  HOME="$SANDBOX/home" PATH="/usr/bin:/bin" CLAUDE_HOME="$C" COPILOT_HOME="$P" "$INSTALLER" install global
  [ -f "$C/hooks/guard.sh" ] && [ ! -e "$P/hooks" ] && [ ! -e "$P/skills" ] || false
}
@test "nothing is written outside CLAUDE_HOME / COPILOT_HOME" {
  anw install global
  [ -z "$(ls -A "$SANDBOX/home")" ]
}
@test "Copilot's own config files are never touched" {
  mkdir -p "$P"; for f in settings.json config.json mcp-config.json; do echo '{"mine":1}' > "$P/$f"; done
  anw install global
  for f in settings.json config.json mcp-config.json; do [ "$(cat "$P/$f")" = '{"mine":1}' ] || { echo "touched: $f"; false; }; done
}
@test "a fresh install backs nothing up, and a re-install with nothing changed writes no backup" {
  anw install global
  [ ! -e "$C/anw-backup" ] && [ ! -e "$P/anw-backup" ] || false
  mkdir -p "$C/agents"; echo x > "$C/agents/qa.md"
  anw install global; ls -R "$C/anw-backup" > "$SANDBOX/b1"
  anw install global; ls -R "$C/anw-backup" > "$SANDBOX/b2"
  cmp "$SANDBOX/b1" "$SANDBOX/b2"
}

# --- uninstall + status -----------------------------------------------------------------
@test "uninstall: removes our hooks, skill copies and settings entries; keeps yours, and any copy you edited" {
  anw install global
  mkdir -p "$C/skills/mine" "$P/skills/kibana" "$C/agents"; echo m > "$C/agents/my-agent.md"
  edit_installed "$P/skills/adr/SKILL.md" "my note"
  jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"my-hook.sh"}]}]' "$C/settings.json" > "$SANDBOX/s" && mv "$SANDBOX/s" "$C/settings.json" || false
  anw uninstall global
  for d in "$C" "$P"; do [ ! -e "$d/hooks/guard.sh" ] && [ ! -e "$d/hooks/verify.sh" ] && [ ! -e "$d/skills/plan" ] || false; done
  [ ! -e "$C/skills/adr" ] && grep -q "my note" "$P/skills/adr/SKILL.md" || false
  [ ! -e "$P/hooks/anw.json" ]
  [ -d "$C/skills/mine" ] && [ -d "$P/skills/kibana" ] && [ -f "$C/agents/my-agent.md" ] || false
  run cmds
  [[ "$output" != *guard.sh* && "$output" != *verify.sh* && "$output" == *my-hook.sh* ]] || false
  [ -f "$C/CLAUDE.md" ] && [ -f "$P/copilot-instructions.md" ] || false
}
@test "status: reports hooks, settings wiring, instructions and skills for both tools" {
  anw install global
  run anw status
  [ "$status" -eq 0 ]
  for s in guard.sh verify.sh anw.json copilot-instructions.md CLAUDE.md caveman plan check; do [[ "$output" == *"$s"* ]] || { echo "missing: $s"; false; }; done
  [[ "$output" != *differs* ]] || false
}
@test "status: flags an installed hook or skill that drifted from the repo" {
  anw install global
  edit_installed "$C/skills/verify/SKILL.md" "# edited"; edit_installed "$P/hooks/guard.sh" "# edited"
  run anw status
  [[ "$output" == *"skills/verify differs"* && "$output" == *"hooks/guard.sh differs"* ]] || false
}
@test "status: shows a repo's pipeline state without executing it" {
  mkdir -p "$SANDBOX/proj/.anw"; cd "$SANDBOX/proj"
  printf 'PIPELINE=demo\ntouch "%s/PWNED"\n' "$SANDBOX" > .anw/.pipeline-state
  run anw status
  [ ! -e "$SANDBOX/PWNED" ]
  [[ "$output" == *"PIPELINE=demo"* ]] || false
}

# --- doctor -------------------------------------------------------------------------------
@test "doctor: a clean install passes" {
  anw install global
  cd "$SANDBOX"
  run anw doctor
  [ "$status" -eq 0 ]
}
@test "doctor: fails and names the path for a drifted skill, a custom agent, or missing hook wiring" {
  anw install global; cd "$SANDBOX"
  edit_installed "$C/skills/plan/SKILL.md" "# edited"
  run anw doctor
  [ "$status" -eq 1 ] && [[ "$output" == *"skills/plan differs"* ]] || false
  anw install global
  mkdir -p "$P/agents"; echo x > "$P/agents/helper.agent.md"
  run anw doctor
  [ "$status" -eq 1 ] && [[ "$output" == *"agents/helper.agent.md"* ]] || false
  rm "$P/agents/helper.agent.md"
  jq 'del(.hooks.Stop)' "$C/settings.json" > "$SANDBOX/s" && mv "$SANDBOX/s" "$C/settings.json" || false
  run anw doctor
  [ "$status" -eq 1 ] && [[ "$output" == *"settings.json"* ]] || false
}
@test "doctor: flags this repo's .anw/verify until you trust it" {
  anw install global
  R="$SANDBOX/repo"; mkdir -p "$R/.anw"; git -C "$R" init -q
  printf '#!/bin/sh\nexit 0\n' > "$R/.anw/verify"; chmod +x "$R/.anw/verify"; cd "$R"
  run anw doctor
  [ "$status" -eq 1 ] && [[ "$output" == *"not trusted"* ]] || false
  anw trust "$R" <<<"y" >/dev/null
  run anw doctor
  [ "$status" -eq 0 ]
}
