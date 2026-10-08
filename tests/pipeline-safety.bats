#!/usr/bin/env bats
# HARNESS-2 P1-6: native pipelines. Each stage is a fresh `claude -p` / `copilot -p` session
# running a skill, with no bypass flags. Only the script pushes, opens PRs/MRs or posts to
# Jira, and only after you confirm. Stub CLIs record their arguments and play the stage.
bats_require_minimum_version 1.5.0

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  SANDBOX="$(cd "$(mktemp -d "$BATS_TMPDIR/aw-pipe-XXXXXX")" && pwd -P)"
  STUB="$SANDBOX/bin"; export STUB_LOG="$SANDBOX/log"; mkdir -p "$STUB" "$STUB_LOG" "$SANDBOX/home"
  export HOME="$SANDBOX/home" ANW_TRUST_FILE="$SANDBOX/trusted" COPILOT_HOME="$SANDBOX/copilot" CLAUDE_HOME="$SANDBOX/claude"
  git init -q --bare "$SANDBOX/remote.git"
  REPO="$SANDBOX/repo"; git init -q -b main "$REPO"; cd "$REPO"
  git config user.email t@t; git config user.name t
  printf '.anw/*\n!.anw/verify\n' > .gitignore; echo toy > README.md
  mkdir -p .anw; printf '#!/bin/sh\ntouch "%s/verified"\nexit "${VERIFY_EXIT:-0}"\n' "$SANDBOX" > .anw/verify; chmod +x .anw/verify
  git add -A; git commit -qm init; git remote add origin "$SANDBOX/remote.git"; git push -q origin main
  shasum -a 256 "$REPO/.anw/verify" > "$ANW_TRUST_FILE"
  printf '# Toy feature\nGreet the user.\n' > toy.md
  mk_stubs; export PATH="$STUB:$PATH"
}
teardown() { rm -rf "$SANDBOX"; }

mk_stubs() {
  # claude/copilot: record argv and stdin, then play the stage named by the prompt ($2, after -p).
  cat > "$STUB/agent" <<'EOF'
#!/usr/bin/env bash
tool="$(basename "$0")"; n=$(( $(cat "$STUB_LOG/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_LOG/n"
printf '%s\n' "$@" > "$STUB_LOG/$n.$tool"; cat > "$STUB_LOG/$n.stdin"
say() { if [ "$tool" = claude ]; then jq -nc --arg t "$1" '{type:"result",subtype:"success",is_error:false,result:$t}'; else echo "$1"; fi; }
case "$2" in
  /incident*) f="${2##* }"; mkdir -p "$(dirname "$f")"; printf '# Incident\nRoot cause: a null config.\n' > "$f"; say "Report: $f" ;;
  /plan*) f="${2##* }"; mkdir -p "$(dirname "$f")"; printf '# Toy feature\n### Step 1\n### Step 2\n' > "$f"; say "Plan: $f" ;;
  Implement\ step*) s="$(sed -n 's/^Implement step \([0-9]*\).*/\1/p' <<<"$2")"
    if [ "${STUB_BLOCK_STEP:-}" = "$s" ]; then say "${STUB_BLOCK_WORD:-BLOCKED:} step $s contradicts AC-1"; exit 0; fi
    echo "step $s" >> impl.txt; git add -A; git commit -qm "feat: step $s"; say "Step $s done" ;;
  /check*) say "No merge-blocking problems." ;;
esac
EOF
  # gh/glab/jira: record argv; PR/MR creation prints a URL.
  cat > "$STUB/forge" <<'EOF'
#!/usr/bin/env bash
tool="$(basename "$0")"; n=$(( $(cat "$STUB_LOG/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_LOG/n"
printf '%s\n' "$@" > "$STUB_LOG/$n.$tool"
case "$tool $1 $2" in "gh pr create") echo "https://github.com/o/r/pull/7" ;; "glab mr create") echo "https://gitlab.example/o/r/-/merge_requests/7" ;; esac
EOF
  chmod +x "$STUB/agent" "$STUB/forge"
  for t in claude copilot; do ln -s agent "$STUB/$t"; done
  for t in gh glab; do ln -s forge "$STUB/$t"; done
}

anw() { "$INSTALLER" "$@"; }
calls() { ls "$STUB_LOG" | grep -E "^[0-9]+\.$1$" | sort -n | sed "s|^|$STUB_LOG/|"; }      # argv files of one tool, in order
call_with() { local f; for f in $(calls "$1"); do grep -qF -- "$2" "$f" && { echo "$f"; return; }; done; return 1; }
after() { awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }' "$1"; }                       # the value after flag $2
has() { grep -qxF -- "$2" "$1" || { echo "missing [$2] in $1:"; cat "$1"; false; }; }
pushed() { git -C "$SANDBOX/remote.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
seq_of() { basename "$1" | cut -d. -f1; }                                                   # call order

# --- static ----------------------------------------------------------------------------
@test "no bypass flags or custom agents anywhere in the CLI" {
  run grep -rnE -- '--agent[= ]|--dangerously-skip-permissions|bypassPermissions|--allow-all-(paths|urls)|--yolo|--allow-all([^-]|$)' \
    "$ROOT/lib" "$ROOT/ai-native-workflow"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

# --- github (claude) ---------------------------------------------------------------------
@test "github-feature: plan → you approve → each step → read-only check → verify → push + PR on your yes" {
  run anw run github-feature toy.md <<<$'y\ny'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  plan="$(call_with claude /plan)"; s1="$(call_with claude 'Implement step 1')"; s2="$(call_with claude 'Implement step 2')"; chk="$(call_with claude /check)"
  [ "$(seq_of "$plan")" -lt "$(seq_of "$s1")" ] && [ "$(seq_of "$s1")" -lt "$(seq_of "$s2")" ] && [ "$(seq_of "$s2")" -lt "$(seq_of "$chk")" ] || false
  for f in "$plan" "$s1" "$s2" "$chk"; do
    [ "$(head -1 "$f")" = -p ] || false
    [ "$(after "$f" --permission-mode)" = acceptEdits ] && [ "$(after "$f" --permission-prompts)" = none ] || false
    has "$f" 'Bash(git push:*)'; has "$f" 'Bash(gh pr create:*)'
  done
  [ "$(after "$plan" --model)" = opus ] && [ "$(after "$s1" --model)" = sonnet ] && [ "$(after "$chk" --model)" = opus ] || false
  for t in Edit Write MultiEdit NotebookEdit; do has "$chk" "$t"; ! grep -qxF "$t" "$s1" || false; done
  for f in "$STUB_LOG"/*.stdin; do [ ! -s "$f" ] || { echo "an agent read stdin: $f"; false; }; done
  [ -e "$SANDBOX/verified" ]
  pushed feature/toy
  pr="$(call_with gh 'pr')"; [ "$(after "$pr" --base)" = main ] || false
}
@test "github-feature: a declined plan stops before any code; resume picks up from the approved plan" {
  run anw run github-feature toy.md <<<$'n'
  [ "$status" -eq 0 ]
  ! call_with claude 'Implement step' || false
  run anw run resume <<<$'y\ny'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(calls claude | wc -l)" -eq 4 ]          # the one /plan, 2 steps, /check: no second /plan
  pushed feature/toy
}
@test "github-feature: a step that ends with BLOCKED: stops the pipeline; nothing is pushed" {
  STUB_BLOCK_STEP=1 run anw run github-feature toy.md <<<$'y\ny'
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED: step 1"* ]] || false
  ! call_with claude 'Implement step 2' || false
  ! call_with claude /check || false
  ! pushed feature/toy || false
}
@test "github-feature: a markdown-bold **BLOCKED**: step stops it too" {
  STUB_BLOCK_STEP=1 STUB_BLOCK_WORD='**BLOCKED**:' run anw run github-feature toy.md <<<$'y\ny'
  [ "$status" -ne 0 ]
  [[ "$output" == *"**BLOCKED**: step 1"* ]] || false
  ! call_with claude 'Implement step 2' || false
  ! pushed feature/toy || false
}
@test "finish: a red .anw/verify blocks the push unless you say so" {
  VERIFY_EXIT=1 run anw run github-feature toy.md <<<$'y\nn\ny'
  [ "$status" -ne 0 ] && [[ "$output" == *"./.anw/verify FAILED. Push anyway?"* ]] || false
  [ -e "$SANDBOX/verified" ]
  ! pushed feature/toy || false
  ! call_with gh pr || false
}
@test "finish: an untrusted .anw/verify is never run, and pushing without it needs an explicit yes" {
  : > "$ANW_TRUST_FILE"
  run anw run github-feature toy.md <<<$'y\n'
  [ ! -e "$SANDBOX/verified" ]
  [[ "$output" == *"No trusted .anw/verify"* && "$output" == *"Push without verification?"* ]] || false
  ! pushed feature/toy || false
}
@test "github-issue: the plan comes from the issue, and the PR closes it" {
  run anw run github-issue 42 <<<$'y\ny'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  call_with claude '/plan GitHub issue #42' >/dev/null
  pushed fix/issue-42
  grep -q 'Closes #42' "$(call_with gh pr)"
}

# --- gitlab (copilot) ---------------------------------------------------------------------
@test "gitlab-feature: copilot stages get deny rules, stripped secrets, no MCP while coding, and no bypass" {
  mkdir -p "$COPILOT_HOME"; echo '{"mcpServers":{"jira":{},"confluence":{}}}' > "$COPILOT_HOME/mcp-config.json"
  run anw run gitlab-feature PROJ-1 <<<$'y\ny\ny'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  plan="$(call_with copilot /plan)"; s1="$(call_with copilot 'Implement step 1')"; chk="$(call_with copilot /check)"
  for f in "$plan" "$s1" "$chk"; do
    has "$f" --allow-all-tools; has "$f" --no-ask-user; has "$f" '--deny-tool=shell(git push)'
    has "$f" '--deny-tool=shell(kubectl apply)'; has "$f" '--deny-tool=shell(glab mr create)'
    grep -qE -- '^--secret-env-vars=.*GITLAB_TOKEN' "$f" || false
    ! grep -qE -- '^--(agent|yolo|allow-all-paths|allow-all-urls|allow-all)(=|$)' "$f" || false
  done
  has "$chk" --deny-tool=write; ! grep -qxF -- --deny-tool=write "$s1" || false
  for f in "$s1" "$chk"; do has "$f" --disable-mcp-server=jira; has "$f" --disable-mcp-server=confluence; done
  ! grep -q -- --disable-mcp-server "$plan" || false     # the plan reads the ticket
  pushed feature/PROJ-1
  grep -q 'Closes PROJ-1' "$(call_with glab mr)"
}
@test "gitlab: no agent prompt posts to Jira; the script comments only after your yes (or prints it without a jira CLI)" {
  ln -s forge "$STUB/jira"
  run anw run gitlab-feature PROJ-2 <<<$'y\ny\nn'
  ! call_with jira comment || false
  for f in $(calls copilot); do ! sed -n 2p "$f" | grep -qiE 'jira.*(comment|transition|post)|(comment|post).*jira' || false; done   # line 2 = the prompt
  run anw run gitlab-feature PROJ-3 <<<$'y\ny\ny'
  j="$(call_with jira comment)"; has "$j" PROJ-3
  rm "$STUB/jira"
  run anw run gitlab-feature PROJ-4 <<<$'y\ny'
  [[ "$output" == *"merge_requests/7"* && "$output" == *"PROJ-4"* ]] || false
}
@test "gitlab-incident: read-only /incident first; you decide whether to fix, and the fix is planned from the report" {
  run anw run gitlab-incident INC-9 <<<$'n'
  [ "$status" -eq 0 ]
  inc="$(call_with copilot /incident)"; has "$inc" '--deny-tool=shell(kubectl delete)'
  ! call_with copilot /plan || false
  run anw run gitlab-incident INC-9 <<<$'y\ny\ny'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  call_with copilot '/plan docs/context/specs/INC-9-incident.md' >/dev/null
  [ "$(calls copilot | grep -c .)" -ge 5 ]
  pushed fix/INC-9
}
@test "the live renderer skips stray non-JSON lines instead of ending the pipe" {
  run bash -c 'source "$1/lib/common.sh"; source "$1/lib/pipeline-core.sh"
    printf "%s\n" "not json" "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"make test\"}}]}}" "{oops" "{\"type\":\"result\",\"result\":\"All green.\"}" | render_claude' _ "$ROOT"
  [ "$status" -eq 0 ] && [[ "$output" == *"→ Bash make test"* && "$output" == *"All green."* ]] || false
}
@test "ids are validated: ids git would accept but that inject options or shell syntax are refused" {
  for id in '--force' 'PROJ-1$(id)' 'a;b'; do
    run anw run gitlab-feature "$id" </dev/null
    [ "$status" -ne 0 ] || { echo "accepted: $id"; false; }
  done
  [ -z "$(calls copilot)" ]
}
