#!/usr/bin/env bash
# lib/pipeline-core.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

# HARNESS-2 flow F. Each stage is a fresh `claude -p` / `copilot -p` session running a skill:
# /plan, "implement step N", /check (read-only), and /incident. No custom agents, no bypass flags.
# What a stage may never run comes from the same policy as your interactive sessions (the
# "ask" and "deny" Bash rules in config/claude-settings.json): Claude gets them as
# --disallowedTools and headless denies anything else that would prompt; Copilot gets them as
# --deny-tool rules. Only this script pushes, opens PRs/MRs or posts to Jira, after your yes.

# Stripped from Copilot's shell and MCP environments, and redacted from its output.
SECRET_ENV_VARS="GH_TOKEN,GITHUB_TOKEN,GITLAB_TOKEN,JIRA_API_TOKEN,ANTHROPIC_API_KEY,OPENAI_API_KEY"

# The honest exit, as hooks/verify.sh reads it: a line starting "BLOCKED:", also markdown-bold.
BLOCKED_RE='^[*_[:space:]]*BLOCKED[*_]*:'

policy_bash_rules() {
  jq -r '(.permissions.ask + .permissions.deny)[] | select(startswith("Bash("))' "$_ANW_SCRIPT_DIR/config/claude-settings.json"
}

# run_stage <tool> <plan|incident|implement|check> <name> <prompt>
# One fresh session. Its transcript goes to $RUN_DIR/<name>.log. Fails if the session fails or
# ends with "BLOCKED:", which is shown to you.
run_stage() {
  local tool="$1" kind="$2" name="$3" prompt="$4" log="$RUN_DIR/$3.log" rc=0 result rule args=()
  header "▸ $name ($tool)"
  dim "$prompt"
  if [ "$tool" = claude ]; then
    while IFS= read -r rule; do args+=("$rule"); done <<<"$(policy_bash_rules)"
    [ "$kind" = check ] && args+=(Edit Write MultiEdit NotebookEdit)
    # --disallowedTools takes the rest of the line, so it goes last.
    claude -p "$prompt" --model "$([ "$kind" = implement ] && echo sonnet || echo opus)" \
      --permission-mode acceptEdits --permission-prompts none --output-format stream-json --verbose \
      --disallowedTools "${args[@]}" </dev/null 2>>"$log.err" | tee "$log" | render_claude || rc="${PIPESTATUS[0]}"
    result="$(jq -r 'select(.type == "result") | .result // empty' "$log" 2>/dev/null || true)"
  else
    while IFS= read -r rule; do
      args+=("--deny-tool=$(sed -E 's/^Bash\(([^:)]*)(:\*)?\)$/shell(\1)/' <<<"$rule")")
    done <<<"$(policy_bash_rules)"
    [ "$kind" = check ] && args+=(--deny-tool=write)
    # Every stage keeps all your MCP servers; what their tools may do is set in your mcp-config.json.
    copilot -p "$prompt" --allow-all-tools --no-ask-user -s --no-color --secret-env-vars="$SECRET_ENV_VARS" \
      "${args[@]}" </dev/null 2>&1 | tee "$log" || rc="${PIPESTATUS[0]}"
    result="$(cat "$log")"
  fi
  if grep -qE "$BLOCKED_RE" <<<"$result"; then warn "$name stopped: $(grep -m1 -E "$BLOCKED_RE" <<<"$result")"; return 1; fi
  [ "$rc" -eq 0 ] || { error "$name failed (exit $rc). Transcript: $log"; return 1; }
}

# Live progress from Claude's event stream (D1): each tool call on one line, then the answer.
# Lines are parsed one by one, so a stray non-JSON line is skipped instead of ending the pipe.
render_claude() {
  jq -R -j --unbuffered 'fromjson? |
    if .type == "assistant" then .message.content[]? | select(.type == "tool_use")
      | "  → \(.name) \(.input | (.command // .file_path // .pattern // .description // "") | tostring | gsub("\\s+"; " ") | .[0:110])\n"
    elif .type == "result" then "\n\(.result // "")\n"
    else empty end' 2>/dev/null || true
}

# --- state: .anw/.pipeline-state is parsed, never sourced (it lives in the repo) ---------------
save_state() {  # <pipeline> <id> <last stage done>
  mkdir -p "$(dirname "$STATE_FILE")"
  printf 'PIPELINE=%s\nID=%s\nSTAGE=%s\nTIMESTAMP=%s\n' "$1" "$2" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"
}
state_get() { sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | head -1; }
clear_state() { rm -f "$STATE_FILE"; }

# Stages run in order: plan, step-1 … step-N, check. A stage is done if it is at or before $DONE.
stage_rank() { case "$1" in plan) echo 0 ;; step-*) echo "${1#step-}" ;; check) echo 9999 ;; *) echo -1 ;; esac; }
stage_done() { [ "$(stage_rank "$1")" -le "$(stage_rank "$DONE")" ]; }

# Every pipeline question is about something consequential, so Enter means no.
confirm() {
  local answer
  ask "$1 [y/N]"
  read -r answer || answer=""
  case "$answer" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

valid_id() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { error "Not a ticket or feature id: '$1'"; return 1; }; }
# An HTML spec or report as indented text: tags stripped, the common entities decoded, blank runs squeezed.
show_doc() { sed -e 's/<[^>]*>//g' -e 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&amp;/\&/g' -e 's/^[[:space:]]*$//' "$1" | cat -s | sed 's/^/    /'; }
repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || { error "Run pipelines inside a git repo"; return 1; }
  cd "$root" || return 1
}
base_branch() {
  local b
  b="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"; b="${b#origin/}"
  if [ -z "$b" ]; then if git show-ref -q --verify refs/heads/main; then b=main; else b=master; fi; fi
  echo "$b"
}
start_branch() {  # <prefix> <id>: stay on a branch that already names the id, else create <prefix>/<id>
  case "$(git branch --show-current)" in
    */"$2"|*/"$2"-*|"$2") dim "On $(git branch --show-current)" ;;
    *) git checkout -q -b "$1/$2" 2>/dev/null || git checkout -q "$1/$2"; success "Branch $1/$2" ;;
  esac
}

# pipeline_flow <pipeline> <tool> <id> <plan input> <branch prefix> <closes line>
# plan → your approval → one session per step → /check → pipeline_finish.
pipeline_flow() {
  local pipeline="$1" tool="$2" id="$3" input="$4" prefix="$5" closes="$6"
  local spec="$SPEC_DIR/$3.html" steps n DONE=""
  if [ "$(state_get PIPELINE)" = "$pipeline" ] && [ "$(state_get ID)" = "$id" ]; then DONE="$(state_get STAGE)"; fi
  RUN_DIR=".anw/runs/$id"; mkdir -p "$RUN_DIR" "$(dirname "$spec")"
  start_branch "$prefix" "$id"
  save_state "$pipeline" "$id" "$DONE"

  if ! stage_done plan; then
    if [ -f "$spec" ]; then info "Using the existing plan: $spec"
    elif [ -z "$input" ]; then error "No plan at $spec, and nothing to plan from"; return 1
    else
      run_stage "$tool" plan plan "/plan $input — write the plan to $spec" || return 1
      [ -f "$spec" ] || { error "The plan stage wrote no $spec"; return 1; }
    fi
    echo ""; show_doc "$spec"; echo ""
    confirm "Approve the plan in $spec?" || { info "Not approved. Edit or delete $spec, then: ai-native-workflow run resume"; return 0; }
    DONE=plan; save_state "$pipeline" "$id" "$DONE"
  fi

  steps="$(grep -oE '<h3[^>]*>[[:space:]]*Step [0-9]+' "$spec" | grep -c . || true)"
  [ "${steps:-0}" -gt 0 ] || { error "$spec has no <h3>Step n</h3> headings"; return 1; }
  for ((n = 1; n <= steps; n++)); do
    stage_done "step-$n" && continue
    run_stage "$tool" implement "step-$n" "Implement step $n of $spec, and only that step: write its test first and watch it fail, then the minimum code. Run ./.anw/verify, and commit (Conventional Commits) once it is green. If the step can't be done as written, stop and reply BLOCKED: <evidence>." || return 1
    DONE="step-$n"; save_state "$pipeline" "$id" "$DONE"
  done

  if ! stage_done check; then
    run_stage "$tool" check check "/check $(base_branch) $spec" || return 1
    DONE=check; save_state "$pipeline" "$id" "$DONE"
  fi
  pipeline_finish "$pipeline" "$id" "$spec" "$closes"
}

# The trusted check (sandboxed, like the Stop hook), then push + PR/MR and Jira: each on your yes.
pipeline_finish() {
  local pipeline="$1" id="$2" spec="$3" closes="$4" base branch forge verified title body url
  base="$(base_branch)"; branch="$(git branch --show-current)"
  case "$pipeline" in github-*) forge=GitHub ;; *) forge=GitLab ;; esac
  header "▸ finish"
  if verify_is_trusted .; then
    if bash "$_ANW_SCRIPT_DIR/hooks/verify.sh" --run .; then
      verified="./.anw/verify passed"; success "$verified"
    else
      confirm "./.anw/verify FAILED. Push anyway?" || { info "Not pushed. Fix it, then: ai-native-workflow run resume"; return 1; }
      verified="./.anw/verify FAILED, pushed anyway"
    fi
  else
    warn "No trusted .anw/verify here, so nothing has verified this branch (ai-native-workflow trust)."
    confirm "Push without verification?" || { info "Not pushed."; return 1; }
    verified="not verified: no trusted .anw/verify"
  fi
  confirm "Push $branch and open a $forge review against $base?" || { info "Not pushed. Later: ai-native-workflow run resume"; return 0; }

  title="$id: $(sed -n 's/^# //p' "$spec" | head -1)"
  body="$(printf '%s\n\nPlan: `%s`\n\n## Commits\n%s\n\n## Verification\n%s\n' \
    "$closes" "$spec" "$(git log --format='- %s' "$base..HEAD")" "$verified")"
  git push -u origin HEAD
  if [ "$forge" = GitHub ]; then
    url="$(gh pr create --base "$base" --head "$branch" --title "$title" --body "$body" </dev/null)"
  else
    url="$(glab mr create --source-branch "$branch" --target-branch "$base" --title "$title" --description "$body" --yes </dev/null)"
  fi
  success "Opened $url"
  case "$pipeline" in gitlab-*) jira_comment "$id" "Merge request: $url" ;; esac
  clear_state
}

# Only this script writes to Jira, and only on your yes. Without a jira CLI it prints the text for you.
jira_comment() {
  if ! command -v jira >/dev/null 2>&1; then
    info "No jira CLI here. Add this to $1 yourself:"; echo "    $2"
  elif confirm "Comment on $1 in Jira: \"$2\"?"; then
    jira issue comment add "$1" "$2" </dev/null && success "Commented on $1"
  fi
  return 0
}
