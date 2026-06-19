#!/usr/bin/env bash
# lib/pipeline-core.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

audit_log() {
  local level="$1"
  shift
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$(dirname "$AUDIT_LOG")"
  echo "[$timestamp] [$level] $*" >> "$AUDIT_LOG"
}

# Called on ERR or EXIT when a pipeline is active
pipeline_on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]:-unknown}"

  # Only act if there's an active pipeline
  [ ! -f "$STATE_FILE" ] && return 0
  [ "$exit_code" -eq 0 ] && return 0

  # Stop spinner if running
  spinner_stop 2>/dev/null

  # Load state for context
  # shellcheck source=/dev/null
  source "$STATE_FILE" 2>/dev/null || true

  local pipeline="${PIPELINE:-unknown}"
  local id="${ID:-unknown}"
  local step="${CURRENT_STEP:-unknown}"
  local status="${STATUS:-unknown}"

  # Write audit log
  audit_log "ERROR" "Pipeline=$pipeline ID=$id Step=$step Status=$status ExitCode=$exit_code Line=$line_no"
  audit_log "ERROR" "Last state: step $step ($status)"

  # Capture recent git state
  local git_branch
  git_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  local git_status
  git_status=$(git status --porcelain 2>/dev/null | head -10 || echo "unknown")
  audit_log "CONTEXT" "Branch=$git_branch"
  if [ -n "$git_status" ]; then
    audit_log "CONTEXT" "Uncommitted changes: $git_status"
  fi

  # Print user-friendly message
  echo ""
  error "Pipeline crashed at step ${step} (exit code ${exit_code})"
  echo ""
  echo -e "  ${BOLD}Pipeline${NC}:  $pipeline"
  echo -e "  ${BOLD}ID${NC}:        $id"
  echo -e "  ${BOLD}Step${NC}:      $step ($status)"
  echo -e "  ${BOLD}Branch${NC}:    $git_branch"
  echo -e "  ${BOLD}Exit Code${NC}: $exit_code"
  echo -e "  ${BOLD}Audit Log${NC}: $AUDIT_LOG"
  echo ""
  info "State preserved. To resume: ${BOLD}ai-native-workflow run resume${NC}"
  info "To see full log: ${BOLD}cat $AUDIT_LOG${NC}"
}

# Install error trap (only active during pipeline runs)
enable_pipeline_error_trap() {
  trap 'pipeline_on_error' ERR
  # Also catch signals
  trap 'audit_log "SIGNAL" "Pipeline interrupted (SIGINT)"; pipeline_on_error' INT
  trap 'audit_log "SIGNAL" "Pipeline terminated (SIGTERM)"; pipeline_on_error' TERM
}

disable_pipeline_error_trap() {
  trap - ERR INT TERM
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     PIPELINE STATE MANAGEMENT                   ║
# ╚══════════════════════════════════════════════════════════════════╝

save_state() {
  local pipeline="$1" id="$2" current_step="$3" status="$4"
  mkdir -p "$(dirname "$STATE_FILE")"
  audit_log "STATE" "Pipeline=$pipeline ID=$id Step=$current_step Status=$status"
  cat > "$STATE_FILE" << EOF
PIPELINE=$pipeline
ID=$id
CURRENT_STEP=$current_step
STATUS=$status
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  dim "State saved: step $current_step ($status)"
}

load_state() {
  if [ ! -f "$STATE_FILE" ]; then
    error "No pipeline state found. Start a pipeline first."
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$STATE_FILE"
}

clear_state() {
  rm -f "$STATE_FILE"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     PIPELINE HELPERS                            ║
# ╚══════════════════════════════════════════════════════════════════╝

confirm() {
  local prompt="$1"
  ask "$prompt [Y/n]"
  read -r answer
  case "$answer" in
    [Nn]*) return 1 ;;
    *) return 0 ;;
  esac
}

wait_for_review() {
  local artifact="$1"
  echo ""
  info "Review the output: ${BOLD}$artifact${NC}"
  ask "Continue to next step? [Y/n/q(uit)]"
  read -r answer
  case "$answer" in
    [Nn]*) warn "Paused. Run ${BOLD}ai-native-workflow run resume${NC} to continue."; exit 0 ;;
    [Qq]*) warn "Pipeline aborted."; clear_state; exit 0 ;;
    *) return 0 ;;
  esac
}

build_ni_suffix() {
  if [ "$ALLOWED_QUESTIONS" -gt 0 ]; then
    echo "You are running in a pipeline. If you need clarification before you can produce high-quality output, you may ask up to $ALLOWED_QUESTIONS questions. Format EACH question on its own line prefixed with 'QUESTION: '. After listing your questions, STOP — do not guess the answers. For non-critical ambiguities, document them in the Assumptions section."
  else
    echo "You are running non-interactively — do NOT ask questions. Make reasonable assumptions and document them in the Assumptions section. Flag any critical ambiguities in Open Questions."
  fi
}

# --- Spinner ---
SPINNER_PID=""

spinner_start() {
  local label="${1:-Working}"
  (
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local elapsed=0
    while true; do
      local frame="${frames[$((i % ${#frames[@]}))]}"
      local mins=$((elapsed / 60))
      local secs=$((elapsed % 60))
      local time_str
      if [ "$mins" -gt 0 ]; then
        time_str="${mins}m ${secs}s"
      else
        time_str="${secs}s"
      fi
      printf "\r  ${MAGENTA}%s${NC} ${BOLD}%s${NC} ${DIM}(%s)${NC}  " "$frame" "$label" "$time_str"
      sleep 1
      elapsed=$((elapsed + 1))
      i=$((i + 1))
    done
  ) &
  SPINNER_PID=$!
  # Ensure spinner is cleaned up on script exit
  trap 'spinner_stop 2>/dev/null' EXIT
}

spinner_stop() {
  if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    printf "\r%80s\r" ""  # clear the spinner line
  fi
  SPINNER_PID=""
}

run_copilot_agent() {
  local agent="$1"
  local prompt="$2"
  LAST_AGENT_TOOL="copilot"
  LAST_AGENT_NAME="$agent"
  LAST_AGENT_PROMPT="$prompt"
  header "Running: $agent (Copilot CLI)"
  dim "Prompt: $prompt"
  echo ""

  local output_file
  output_file=$(mktemp)

  spinner_start "$agent"

  copilot --agent="$agent" \
    --allow-all-tools \
    --allow-all-paths \
    -p "$prompt" > "$output_file" 2>&1
  local exit_code=$?

  spinner_stop

  # Show output and save for question detection
  LAST_AGENT_OUTPUT=""
  if [ -s "$output_file" ]; then
    cat "$output_file"
    LAST_AGENT_OUTPUT=$(cat "$output_file")
  fi

  if [ "$exit_code" -ne 0 ]; then
    audit_log "AGENT_ERROR" "Agent=$agent ExitCode=$exit_code"
    audit_log "AGENT_ERROR" "Output (last 20 lines): $(tail -20 "$output_file" 2>/dev/null)"
    rm -f "$output_file"
    error "Agent $agent failed (exit code $exit_code)"
    return "$exit_code"
  fi
  rm -f "$output_file"
  audit_log "AGENT_OK" "Agent=$agent completed"
  success "$agent completed"
}

run_claude_agent() {
  local agent="$1"
  local prompt="$2"
  LAST_AGENT_TOOL="claude"
  LAST_AGENT_NAME="$agent"
  LAST_AGENT_PROMPT="$prompt"
  header "Running: $agent (Claude Code)"
  dim "Prompt: $prompt"
  echo ""

  local output_file
  output_file=$(mktemp)

  spinner_start "$agent"

  claude --agent="$agent" \
    --dangerously-skip-permissions \
    -p "$prompt" > "$output_file" 2>&1
  local exit_code=$?

  spinner_stop

  # Show output and save for question detection
  LAST_AGENT_OUTPUT=""
  if [ -s "$output_file" ]; then
    cat "$output_file"
    LAST_AGENT_OUTPUT=$(cat "$output_file")
  fi

  if [ "$exit_code" -ne 0 ]; then
    audit_log "AGENT_ERROR" "Agent=$agent ExitCode=$exit_code"
    audit_log "AGENT_ERROR" "Output (last 20 lines): $(tail -20 "$output_file" 2>/dev/null)"
    rm -f "$output_file"
    error "Agent $agent failed (exit code $exit_code)"
    return "$exit_code"
  fi
  rm -f "$output_file"
  audit_log "AGENT_OK" "Agent=$agent completed"
  success "$agent completed"
}

# handle_agent_questions — detect QUESTION: lines in LAST_AGENT_OUTPUT,
# collect answers from user, re-run the agent with answers appended.
# Reads from globals: ALLOWED_QUESTIONS, LAST_AGENT_OUTPUT, LAST_AGENT_TOOL,
#                     LAST_AGENT_NAME, LAST_AGENT_PROMPT
handle_agent_questions() {
  # Skip if questions not enabled or no output
  if [ "$ALLOWED_QUESTIONS" -eq 0 ] || [ -z "$LAST_AGENT_OUTPUT" ]; then
    return 0
  fi

  # Extract QUESTION: lines from output
  local questions
  questions=$(echo "$LAST_AGENT_OUTPUT" | grep -E '^QUESTION: ' || true)

  if [ -z "$questions" ]; then
    return 0
  fi

  # Count and display questions
  local q_count
  q_count=$(echo "$questions" | wc -l | tr -d ' ')
  echo ""
  header "$LAST_AGENT_NAME has $q_count question(s):"
  echo ""

  local i=1
  local answers=""
  while IFS= read -r question; do
    local q_text="${question#QUESTION: }"
    echo -e "  ${BOLD}Q${i}:${NC} $q_text"
    ask "A${i}:"
    local answer
    read -r answer
    answers="${answers}
Q: ${q_text}
A: ${answer}"
    i=$((i + 1))
  done <<< "$questions"

  echo ""
  info "Re-running ${BOLD}$LAST_AGENT_NAME${NC} with your answers..."

  # Re-run agent with original prompt + answers
  local followup_prompt="Continue your previous task. Original instructions: ${LAST_AGENT_PROMPT}

The user answered your clarifying questions:
${answers}

Use these answers to complete your work. Update any artifacts you already created. Do NOT ask more questions."

  "run_${LAST_AGENT_TOOL}_agent" "$LAST_AGENT_NAME" "$followup_prompt"
}

run_triage() {
  local tool="$1"  # "copilot" or "claude"
  local id="$2"
  local step_num="$3"
  local max_loops=3
  local loop=0
  local triage=""
  local invalid_count=0

  while [ "$loop" -lt "$max_loops" ]; do
    echo ""
    ask "Triage findings — [F]ix / [T]ech debt / [I]gnore / [D]one? "

    # Read with timeout — if no input in 30s or EOF, auto-done
    if ! read -r -t 30 triage; then
      warn "No input (timeout or EOF) — auto-proceeding."
      break
    fi

    # Guard against empty input loops
    if [ -z "$triage" ]; then
      invalid_count=$((invalid_count + 1))
      if [ "$invalid_count" -ge 3 ]; then
        warn "Too many empty inputs — auto-proceeding."
        break
      fi
      warn "Empty input. Use F/T/I/D."
      continue
    fi
    invalid_count=0

    case "$triage" in
      [Ff]*)
        loop=$((loop + 1))
        info "Fix loop $loop/$max_loops"
        if [ "$tool" = "copilot" ]; then
          run_copilot_agent "tdd-developer" "Fix reviewer findings for Step $step_num of ${id}-todo.md" || true
          run_copilot_agent "qa" "Run tests after fix for Step $step_num of $id" || true
          run_copilot_agent "reviewer" "Re-review Step $step_num of $id after fix (loop $loop/$max_loops)" || true
        else
          run_claude_agent "tdd-developer" "Fix reviewer findings for Step $step_num of ${id}-todo.md" || true
          run_claude_agent "qa" "Run tests after fix for Step $step_num of $id" || true
          run_claude_agent "reviewer" "Re-review Step $step_num of $id after fix (loop $loop/$max_loops)" || true
        fi
        ;;
      [Tt]*)
        info "Added to tech debt in CURRENT_SPRINT.md"
        break
        ;;
      [Ii]*)
        info "Ignored."
        break
        ;;
      [Dd]*)
        break
        ;;
      *)
        invalid_count=$((invalid_count + 1))
        if [ "$invalid_count" -ge 3 ]; then
          warn "Too many invalid inputs — auto-proceeding."
          break
        fi
        warn "Invalid choice. Use F/T/I/D."
        ;;
    esac
  done

  if [ "$loop" -ge "$max_loops" ]; then
    warn "Max fix loops ($max_loops) reached. Remaining issues → tech debt."
  fi
}

count_steps() {
  local todo_file="$1"
  if [ ! -f "$todo_file" ]; then
    echo "0"
    return
  fi
  grep -c '^### Step' "$todo_file" 2>/dev/null || echo "0"
}

# Check if a step should be skipped during resume.
# Returns 0 (true) if the step should be skipped, 1 (false) if it should run.
# Steps use format: "1", "2", "4.1", "5.2", "7"
# A step is skipped if it was completed (status=done/dev-done/qa-done/review-done/complete)
# The step matching RESUME_FROM_STEP runs again (it may have been interrupted).
should_skip_step() {
  local step="$1"
  local resume="${RESUME_FROM_STEP:-}"

  # No resume in progress — run everything
  [ -z "$resume" ] && return 1

  # Parse major.minor for comparison
  local step_major step_minor resume_major resume_minor
  step_major=$(echo "$step" | cut -d. -f1)
  step_minor=$(echo "$step" | cut -d. -f2 -s)
  resume_major=$(echo "$resume" | cut -d. -f1)
  resume_minor=$(echo "$resume" | cut -d. -f2 -s)

  # Handle non-numeric steps (like "2A")
  # Strip letters for comparison
  step_major=$(echo "$step_major" | sed 's/[^0-9]//g')
  resume_major=$(echo "$resume_major" | sed 's/[^0-9]//g')
  [ -z "$step_major" ] && return 1
  [ -z "$resume_major" ] && return 1

  step_minor=${step_minor:-0}
  resume_minor=${resume_minor:-0}

  # Skip if step is strictly before the resume point
  if [ "$step_major" -lt "$resume_major" ]; then
    dim "Skipping step $step (already done)"
    return 0
  elif [ "$step_major" -eq "$resume_major" ] && [ "$step_minor" -lt "$resume_minor" ]; then
    dim "Skipping step $step (already done)"
    return 0
  fi

  # Clear the resume flag once we've caught up
  if [ "$step_major" -ge "$resume_major" ]; then
    unset RESUME_FROM_STEP
  fi

  return 1
}

create_feature_branch() {
  local prefix="$1"  # "feat" or "fix"
  local id="$2"      # JIRA-ID or feature name
  local branch="${prefix}/${id}"

  # Sanitize branch name
  branch=$(echo "$branch" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9\/_-]/-/g')

  local base
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

  info "Creating branch: ${BOLD}$branch${NC} from ${base}"
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"
  echo "$branch"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║              PIPELINE FINISH                                    ║
# ╚══════════════════════════════════════════════════════════════════╝

pipeline_finish() {
  local pipeline_name="$1"  # e.g. "gitlab-feature"
  local id="$2"             # e.g. PROJ-123 or feature-20260320-...
  local tool="$3"           # "copilot" or "claude"

  disable_pipeline_error_trap
  header "Pipeline Wrap-Up"

  # --- Gather data for summary ---
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  local base
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  local commit_count
  commit_count=$(git rev-list --count "${base}..HEAD" 2>/dev/null || echo "0")
  local commits
  commits=$(git log --oneline "${base}..HEAD" 2>/dev/null || echo "(none)")
  local changed_files
  changed_files=$(git diff --stat "${base}..HEAD" 2>/dev/null || echo "(none)")
  local test_files
  test_files=$(git diff --name-only "${base}..HEAD" 2>/dev/null | grep -iE '(test|spec|_test\.)' || echo "(none)")
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local date_short
  date_short=$(date +%Y-%m-%d)

  # --- Collect pipeline artifacts ---
  local artifacts=()
  for f in "$CONTEXT_DIR/${id}"*.md "$CONTEXT_DIR/requirements.md"; do
    [ -f "$f" ] && artifacts+=("$f")
  done

  # --- 1. Generate summary file ---
  local summary_file="$CONTEXT_DIR/${id}-pipeline-summary.md"
  mkdir -p "$CONTEXT_DIR"

  cat > "$summary_file" << SUMMARY_EOF
# Pipeline Summary: ${pipeline_name}

## Metadata
- **ID**: ${id}
- **Pipeline**: ${pipeline_name}
- **Branch**: ${branch}
- **Date**: ${timestamp}
- **Commits**: ${commit_count}

## Commits
\`\`\`
${commits}
\`\`\`

## Changed Files
\`\`\`
${changed_files}
\`\`\`

## Test Files Touched
\`\`\`
${test_files}
\`\`\`

## Artifacts Produced
$(for f in "${artifacts[@]}"; do echo "- \`$f\`"; done)
- \`${summary_file}\` (this file)

## Pipeline Steps Completed
$(if [[ "$pipeline_name" == *"feature"* ]]; then
  echo "1. Requirements Engineering"
  echo "2. Test Planning / GitHub Issue"
  echo "3. Architecture & Planning"
  echo "4. TDD Implementation (per step)"
  echo "5. QA Testing (per step)"
  echo "6. Code Review (per step)"
  echo "7. MR/PR Creation"
elif [[ "$pipeline_name" == *"incident"* ]]; then
  echo "1. Investigation (Troubleshooter)"
  echo "2. User Decision Point"
  echo "3. TDD Fix (per step)"
  echo "4. QA Verification (per step)"
  echo "5. Code Review (per step)"
  echo "6. MR Creation + Jira Update"
fi)
SUMMARY_EOF

  success "Summary saved: ${BOLD}$summary_file${NC}"

  # --- 2. Print summary to terminal ---
  echo ""
  echo -e "  ${BOLD}Pipeline${NC}:  $pipeline_name"
  echo -e "  ${BOLD}ID${NC}:        $id"
  echo -e "  ${BOLD}Branch${NC}:    $branch"
  echo -e "  ${BOLD}Commits${NC}:   $commit_count"
  echo -e "  ${BOLD}Artifacts${NC}: ${#artifacts[@]} files"
  echo ""
  echo -e "  ${DIM}${commits}${NC}"

  # --- 3. Obsidian session report (if available) ---
  local obsidian_available=false
  if command -v claude &>/dev/null && [ "$tool" = "claude" ]; then
    # Check if obsidian MCP is reachable by looking for the write_session_report tool
    obsidian_available=true
  elif command -v copilot &>/dev/null && [ "$tool" = "copilot" ]; then
    obsidian_available=true
  fi

  if [ "$obsidian_available" = true ]; then
    echo ""
    if confirm "Generate Obsidian session report?"; then
      pstep "F" "Obsidian Session Report"
      if [ "$tool" = "claude" ]; then
        run_claude_agent "reviewer" "Generate a session report for the ${pipeline_name} pipeline run on ${id}. Summary: ${commit_count} commits on branch ${branch}. Read ${summary_file} for full details. Use the mcp__obsidian__write_session_report tool to save the report. Include: what was accomplished, commits, test files, decisions, and next steps."
      else
        run_copilot_agent "reviewer" "Generate a session report for the ${pipeline_name} pipeline run on ${id}. Summary: ${commit_count} commits on branch ${branch}. Read ${summary_file} for full details. Save the report to Obsidian if available. Include: what was accomplished, commits, test files, decisions, and next steps."
      fi
    fi
  fi

  # --- 4. Clean up pipeline artifacts (keep only summary) ---
  echo ""
  if confirm "Clean up pipeline working files? (keeps summary + code)"; then
    local cleaned=0
    for f in "${artifacts[@]}"; do
      # Don't delete the summary itself
      if [ "$f" != "$summary_file" ] && [ -f "$f" ]; then
        rm -f "$f"
        cleaned=$((cleaned + 1))
        dim "Removed $(basename "$f")"
      fi
    done

    # Remove pipeline state
    clear_state

    # Commit the cleanup
    if [ "$cleaned" -gt 0 ]; then
      git add -A "$CONTEXT_DIR/" 2>/dev/null || true
      git commit -m "chore(pipeline): clean up ${pipeline_name} artifacts for ${id}

Kept: ${summary_file}
Removed: ${cleaned} working files (requirements, specs, todos, test plans)" 2>/dev/null || true
      success "Cleaned $cleaned pipeline files, kept summary"
    else
      clear_state
      success "No working files to clean"
    fi
  else
    clear_state
    info "Pipeline files preserved in $CONTEXT_DIR/"
  fi

  header "Pipeline Complete"
  success "${pipeline_name} for ${id} finished."
  info "Summary: ${BOLD}$summary_file${NC}"
  echo ""
  dim "Next (optional): review the new PR/MR with the diff-reviewer agent."
  dim "   It posts inline comments + a verdict after a preview/confirm gate."
  dim "   Claude:  Use diff-reviewer to review the new PR/MR for ${id}"
  dim "   Copilot: copilot --agent=diff-reviewer --prompt \"Review the new PR/MR for ${id}\""
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║              PIPELINE 1: GITLAB FEATURE                         ║
# ╚══════════════════════════════════════════════════════════════════╝

