#!/usr/bin/env bash
# lib/pipelines.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

pipeline_gitlab_feature() {
  local jira_id="$1"
  require_copilot
  require_glab

  header "Pipeline: GitLab Feature Development"
  info "Jira ticket: ${BOLD}$jira_id${NC}"
  info "Agents: Copilot CLI | Platform: GitLab"
  echo ""
  enable_pipeline_error_trap

  mkdir -p "$CONTEXT_DIR"
  write_active_spec "$jira_id"
  local NI_SUFFIX
  NI_SUFFIX=$(build_ni_suffix)

  # --- Create/checkout feature branch ---
  # GitLab convention: feature/PROJ-123 (uppercase ticket ID, "feature" prefix).
  # Reuse current branch if it already references this jira id, e.g.:
  #   feature/PROJ-123, feature/PROJ-123-short-desc, feature/PROJ-123_desc,
  #   fix/PROJ-123, bugfix/PROJ-123, hotfix/PROJ-123, PROJ-123, PROJ-123-desc
  local jira_id_upper
  jira_id_upper=$(echo "$jira_id" | tr '[:lower:]' '[:upper:]')
  local feature_branch="feature/${jira_id_upper}"
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")
  if echo "$current_branch" | grep -qiE "(^|/)${jira_id_upper}([-_].*)?$"; then
    info "Reusing current branch: ${BOLD}${current_branch}${NC} (matches ${jira_id_upper})"
  elif [ -n "${RESUME_FROM_STEP:-}" ]; then
    git checkout "$feature_branch" 2>/dev/null || true
  else
    local base
    base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    info "Creating branch: ${BOLD}${feature_branch}${NC} from ${base}"
    git checkout -b "$feature_branch" 2>/dev/null || git checkout "$feature_branch"
  fi

  # --- Step 1: Requirements Engineering ---
  if ! should_skip_step 1; then
    pstep 1 "Requirements Engineering"
    save_state "gitlab-feature" "$jira_id" 1 "running"
    run_copilot_agent "requirements-engineer" "Analyze Jira ticket $jira_id. Create structured requirements at $CONTEXT_DIR/${jira_id}-requirements.md. $NI_SUFFIX"
    handle_agent_questions
    save_state "gitlab-feature" "$jira_id" 1 "done"
    wait_for_review "$CONTEXT_DIR/${jira_id}-requirements.md"
  fi

  # --- Step 2: Test Planning ---
  if ! should_skip_step 2; then
    pstep 2 "Test Planning"
    save_state "gitlab-feature" "$jira_id" 2 "running"
    run_copilot_agent "qa" "Create test plan from $CONTEXT_DIR/${jira_id}-requirements.md. Save to $CONTEXT_DIR/${jira_id}-testplan.md"
    save_state "gitlab-feature" "$jira_id" 2 "done"
    wait_for_review "$CONTEXT_DIR/${jira_id}-testplan.md"
  fi

  # --- Step 3: Architecture & Planning ---
  if ! should_skip_step 3; then
    pstep 3 "Architecture & Planning"
    save_state "gitlab-feature" "$jira_id" 3 "running"
    run_copilot_agent "architect" "Design solution for $jira_id using $CONTEXT_DIR/${jira_id}-requirements.md and $CONTEXT_DIR/${jira_id}-testplan.md. $NI_SUFFIX Write the spec and todo files directly. If unclear, document assumptions in the spec."
    handle_agent_questions
    save_state "gitlab-feature" "$jira_id" 3 "done"
    wait_for_review "$CONTEXT_DIR/${jira_id}-todo.md"
  fi

  # --- Step 3.5: Plan Review Rounds (2 mandatory, up to 3) ---
  # Reviewer critiques the plan; architect updates it. Repeat 2x; offer optional 3rd round.
  local plan_rounds="${PLAN_REVIEW_ROUNDS:-2}"
  if [ "$plan_rounds" -lt 2 ]; then plan_rounds=2; fi
  if [ "$plan_rounds" -gt 3 ]; then plan_rounds=3; fi
  for ((r = 1; r <= plan_rounds; r++)); do
    if ! should_skip_step "3.$r"; then
      pstep "3.$r" "Plan Review Round $r/$plan_rounds"
      save_state "gitlab-feature" "$jira_id" "3.$r" "running"
      local review_file="$CONTEXT_DIR/${jira_id}-plan-review-${r}.md"
      run_copilot_agent "reviewer" "Review the implementation plan for $jira_id. Read $CONTEXT_DIR/${jira_id}-spec.md and $CONTEXT_DIR/${jira_id}-todo.md against $CONTEXT_DIR/${jira_id}-requirements.md and $CONTEXT_DIR/${jira_id}-testplan.md. Identify gaps, risks, missing steps, ambiguous acceptance criteria, and ordering issues. Write findings to $review_file. $NI_SUFFIX"
      handle_agent_questions
      run_copilot_agent "architect" "Update the spec and todo for $jira_id based on review findings in $review_file. Revise $CONTEXT_DIR/${jira_id}-spec.md and $CONTEXT_DIR/${jira_id}-todo.md directly. $NI_SUFFIX"
      handle_agent_questions
      save_state "gitlab-feature" "$jira_id" "3.$r" "done"
      wait_for_review "$CONTEXT_DIR/${jira_id}-todo.md"
    fi
    # After 2 mandatory rounds, optionally do a 3rd
    if [ "$r" -eq 2 ] && [ "$plan_rounds" -eq 2 ]; then
      if confirm "Run an optional 3rd plan review round?"; then
        plan_rounds=3
      fi
    fi
  done

  # --- Step 4-6: TDD Loop (per step in todo) ---
  local todo_file="$CONTEXT_DIR/${jira_id}-todo.md"
  local total_steps
  total_steps=$(count_steps "$todo_file")
  info "Todo has $total_steps steps"

  for ((i = 1; i <= total_steps; i++)); do
    if ! should_skip_step "4.$i"; then
      pstep "4.$i" "TDD: Implement Step $i/$total_steps"
      save_state "gitlab-feature" "$jira_id" "4.$i" "running"
      run_copilot_agent "tdd-developer" "Step $i of ${jira_id}-todo.md"
      save_state "gitlab-feature" "$jira_id" "4.$i" "dev-done"
    fi

    if ! should_skip_step "5.$i"; then
      pstep "5.$i" "QA: Test Step $i/$total_steps"
      run_copilot_agent "qa" "Run tests for Step $i of $jira_id"
      save_state "gitlab-feature" "$jira_id" "5.$i" "qa-done"
    fi

    if ! should_skip_step "6.$i"; then
      pstep "6.$i" "Review: Step $i/$total_steps"
      run_copilot_agent "reviewer" "Review Step $i of $jira_id"
      save_state "gitlab-feature" "$jira_id" "6.$i" "review-done"

      emit_step_verdict "$jira_id" "$i"
      run_triage "copilot" "$jira_id" "$i"
    fi
  done

  # --- Step 7: Create Merge Request ---
  if ! should_skip_step 7; then
    pstep 7 "Create Merge Request"
    if confirm "Create merge request on GitLab?"; then
      local branch
      branch=$(git branch --show-current)
      local base
      base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
      git push -u origin "$branch"

      local mr_base_desc="Closes $jira_id

## Pipeline
Generated with \`ai-native-workflow run gitlab-feature $jira_id\`

## Artifacts
- Requirements: \`$CONTEXT_DIR/${jira_id}-requirements.md\`
- Test Plan: \`$CONTEXT_DIR/${jira_id}-testplan.md\`
- Spec: \`$CONTEXT_DIR/${jira_id}-spec.md\`
- Todo: \`$CONTEXT_DIR/${jira_id}-todo.md\`"

      local mr_desc
      mr_desc="$(build_pr_body "$jira_id" "$mr_base_desc")"

      glab mr create \
        --source-branch "$branch" \
        --target-branch "$base" \
        --title "feat: $jira_id" \
        --description "$mr_desc"
      success "Merge request created!"
    fi
  fi

  save_state "gitlab-feature" "$jira_id" 7 "complete"

  pipeline_finish "gitlab-feature" "$jira_id" "copilot"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║              PIPELINE 2: GITLAB INCIDENT                        ║
# ╚══════════════════════════════════════════════════════════════════╝

pipeline_gitlab_incident() {
  local jira_id="$1"
  require_copilot
  require_glab

  header "Pipeline: GitLab Incident Response"
  info "Jira ticket: ${BOLD}$jira_id${NC}"
  info "Agents: Copilot CLI + Troubleshooter | Platform: GitLab"
  echo ""
  enable_pipeline_error_trap

  mkdir -p "$CONTEXT_DIR"
  write_active_spec "$jira_id"
  local NI_SUFFIX
  NI_SUFFIX=$(build_ni_suffix)

  # --- Step 1: Troubleshoot ---
  if ! should_skip_step 1; then
    pstep 1 "Investigation (Troubleshooter)"
    save_state "gitlab-incident" "$jira_id" 1 "running"
    run_copilot_agent "troubleshooter" "Investigate Jira incident $jira_id. Check all regions. Produce diagnosis at $CONTEXT_DIR/${jira_id}-bugfix.md. $NI_SUFFIX"
    handle_agent_questions
    save_state "gitlab-incident" "$jira_id" 1 "done"

    echo ""
    info "Review diagnosis: ${BOLD}$CONTEXT_DIR/${jira_id}-bugfix.md${NC}"
  fi

  # --- Step 2: User Decision Point ---
  if ! should_skip_step 2; then
    pstep 2 "Decision Point"
    echo ""
    echo -e "  ${BOLD}A${NC} — Document only (add findings to Jira, no code fix)"
    echo -e "  ${BOLD}B${NC} — Fix the issue (TDD pipeline)"
    echo -e "  ${BOLD}Q${NC} — Quit"
    echo ""
    ask "Choose action [A/B/Q]: "
    read -r decision

    case "$decision" in
      [Aa]*)
        pstep "2A" "Adding findings to Jira"
        save_state "gitlab-incident" "$jira_id" "2A" "running"
        if [ -f "$CONTEXT_DIR/${jira_id}-bugfix.md" ]; then
          run_copilot_agent "troubleshooter" "Add the diagnosis from $CONTEXT_DIR/${jira_id}-bugfix.md as a comment on Jira ticket $jira_id. Include key findings, root cause, and recommended next action."
          success "Findings added to Jira ticket $jira_id"
        else
          warn "No diagnosis file found. Add findings manually."
        fi
        save_state "gitlab-incident" "$jira_id" "2A" "complete"
        pipeline_finish "gitlab-incident-doconly" "$jira_id" "copilot"
        return
        ;;
      [Bb]*)
        info "Continuing to fix..."
        # GitLab convention: fix/PROJ-123 (uppercase ticket ID).
        # Reuse current branch if it already references this jira id.
        local jira_id_upper
        jira_id_upper=$(echo "$jira_id" | tr '[:lower:]' '[:upper:]')
        local fix_branch="fix/${jira_id_upper}"
        local current_branch
        current_branch=$(git branch --show-current 2>/dev/null || echo "")
        if echo "$current_branch" | grep -qiE "(^|/)${jira_id_upper}([-_].*)?$"; then
          info "Reusing current branch: ${BOLD}${current_branch}${NC} (matches ${jira_id_upper})"
        else
          local base
          base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
          info "Creating branch: ${BOLD}${fix_branch}${NC} from ${base}"
          git checkout -b "$fix_branch" 2>/dev/null || git checkout "$fix_branch"
        fi
        ;;
      [Qq]*)
        warn "Pipeline aborted."
        clear_state
        return
        ;;
      *)
        error "Invalid choice. Aborting."
        exit 1
        ;;
    esac
  else
    # On resume past step 2, ensure we're on the fix branch (or a branch that matches the jira id)
    local jira_id_upper
    jira_id_upper=$(echo "$jira_id" | tr '[:lower:]' '[:upper:]')
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if ! echo "$current_branch" | grep -qiE "(^|/)${jira_id_upper}([-_].*)?$"; then
      git checkout "fix/${jira_id_upper}" 2>/dev/null || true
    fi
  fi

  # --- Step 2.5: Plan Review Rounds (2 mandatory, up to 3) ---
  # Reviewer critiques the fix plan; troubleshooter updates it. Repeat 2x; offer optional 3rd round.
  local plan_rounds="${PLAN_REVIEW_ROUNDS:-2}"
  if [ "$plan_rounds" -lt 2 ]; then plan_rounds=2; fi
  if [ "$plan_rounds" -gt 3 ]; then plan_rounds=3; fi
  for ((r = 1; r <= plan_rounds; r++)); do
    if ! should_skip_step "2.$r"; then
      pstep "2.$r" "Fix Plan Review Round $r/$plan_rounds"
      save_state "gitlab-incident" "$jira_id" "2.$r" "running"
      local review_file="$CONTEXT_DIR/${jira_id}-plan-review-${r}.md"
      run_copilot_agent "reviewer" "Review the fix plan for incident $jira_id. Read $CONTEXT_DIR/${jira_id}-bugfix.md and $CONTEXT_DIR/${jira_id}-todo.md. Identify gaps, risks, missing regression tests, root-cause coverage, and ordering issues. Write findings to $review_file. $NI_SUFFIX"
      handle_agent_questions
      run_copilot_agent "troubleshooter" "Update the fix plan for $jira_id based on review findings in $review_file. Revise $CONTEXT_DIR/${jira_id}-bugfix.md and $CONTEXT_DIR/${jira_id}-todo.md directly. $NI_SUFFIX"
      handle_agent_questions
      save_state "gitlab-incident" "$jira_id" "2.$r" "done"
      wait_for_review "$CONTEXT_DIR/${jira_id}-todo.md"
    fi
    if [ "$r" -eq 2 ] && [ "$plan_rounds" -eq 2 ]; then
      if confirm "Run an optional 3rd plan review round?"; then
        plan_rounds=3
      fi
    fi
  done

  # --- Step 3: TDD Fix ---
  local todo_file="$CONTEXT_DIR/${jira_id}-todo.md"
  local total_steps
  total_steps=$(count_steps "$todo_file")
  info "Fix plan has $total_steps steps"

  for ((i = 1; i <= total_steps; i++)); do
    if ! should_skip_step "3.$i"; then
      pstep "3.$i" "TDD Fix: Step $i/$total_steps"
      save_state "gitlab-incident" "$jira_id" "3.$i" "running"
      run_copilot_agent "tdd-developer" "Step $i of ${jira_id}-todo.md"
      save_state "gitlab-incident" "$jira_id" "3.$i" "dev-done"
    fi

    if ! should_skip_step "4.$i"; then
      pstep "4.$i" "QA: Verify Step $i/$total_steps"
      run_copilot_agent "qa" "Run tests for Step $i of $jira_id bugfix"
      save_state "gitlab-incident" "$jira_id" "4.$i" "qa-done"
    fi

    if ! should_skip_step "5.$i"; then
      pstep "5.$i" "Review: Step $i/$total_steps"
      run_copilot_agent "reviewer" "Review Step $i of $jira_id bugfix"
      save_state "gitlab-incident" "$jira_id" "5.$i" "review-done"

      emit_step_verdict "$jira_id" "$i"
      run_triage "copilot" "$jira_id" "$i"
    fi
  done

  # --- Step 6: Create MR + Update Jira ---
  if ! should_skip_step 6; then
    pstep 6 "Create Merge Request"
    if confirm "Create merge request and update Jira?"; then
      local branch
      branch=$(git branch --show-current)
      local base
      base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
      git push -u origin "$branch"

      local mr_base_desc="Fixes $jira_id

## Root Cause
See \`$CONTEXT_DIR/${jira_id}-bugfix.md\`

## Pipeline
Generated with \`ai-native-workflow run gitlab-incident $jira_id\`"

      local mr_desc
      mr_desc="$(build_pr_body "$jira_id" "$mr_base_desc")"

      glab mr create \
        --source-branch "$branch" \
        --target-branch "$base" \
        --title "fix: $jira_id" \
        --description "$mr_desc"
      success "Merge request created!"

      # Update Jira status
      run_copilot_agent "troubleshooter" "Transition Jira ticket $jira_id to 'In Review' and add a comment with the MR link."
    fi
  fi

  save_state "gitlab-incident" "$jira_id" 6 "complete"

  pipeline_finish "gitlab-incident" "$jira_id" "copilot"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║              PIPELINE 3: GITHUB FEATURE                         ║
# ╚══════════════════════════════════════════════════════════════════╝

pipeline_github_feature() {
  local specs_file="${1:-}"

  # In dry-run mode, skip tool availability checks and agent invocations.
  # Write the active-spec marker and return immediately.
  if [ "${AW_DRY_RUN:-0}" = "1" ]; then
    mkdir -p "$CONTEXT_DIR" .git/aw
    local dry_spec_id="${AW_SPEC_ID:-dry-run}"
    write_active_spec "$dry_spec_id"
    return 0
  fi

  require_claude
  require_gh

  header "Pipeline: GitHub Feature Development"
  info "Agents: Claude Code | Platform: GitHub"
  enable_pipeline_error_trap

  mkdir -p "$CONTEXT_DIR"

  local id
  local issue_title="New feature request"
  local issue_num=""
  local NI_SUFFIX
  NI_SUFFIX=$(build_ni_suffix)

  # --- On resume, recover ID from state; otherwise generate new ---
  if [ -n "${RESUME_FROM_STEP:-}" ] && [ -f "$STATE_FILE" ]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    id="$ID"
    info "Resuming with ID: ${BOLD}$id${NC}"
    # Make sure we're on the right branch
    local expected_branch
    expected_branch=$(echo "feat/$id" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9\/_-]/-/g')
    git checkout "$expected_branch" 2>/dev/null || true
  else
    # --- Determine input source ---
    local req_prompt
    if [ -n "$specs_file" ] && [ -f "$specs_file" ]; then
      info "Specs file: ${BOLD}$specs_file${NC}"
      req_prompt="Read the specs file at $specs_file and create structured requirements at $CONTEXT_DIR/requirements.md. $NI_SUFFIX"
    elif [ -f "specs.md" ]; then
      info "Specs file: ${BOLD}specs.md${NC} (auto-detected)"
      req_prompt="Read the specs file at specs.md and create structured requirements at $CONTEXT_DIR/requirements.md. $NI_SUFFIX"
    else
      info "No specs file provided. Enter requirements interactively."
      echo ""
      ask "Describe the feature:"
      echo ""
      read -r feature_desc
      req_prompt="Create structured requirements from this description: $feature_desc. Save to $CONTEXT_DIR/requirements.md. $NI_SUFFIX"
    fi
    echo ""

    id="feature-$(date +%Y%m%d-%H%M%S)"

    # --- Create feature branch ---
    create_feature_branch "feat" "$id"
  fi

  write_active_spec "$id"

  # --- Step 1: Requirements Engineering ---
  if ! should_skip_step 1; then
    pstep 1 "Requirements Engineering"
    save_state "github-feature" "$id" 1 "running"
    run_claude_agent "requirements-engineer" "${req_prompt:-Continue requirements engineering for $id. Read existing files in $CONTEXT_DIR/ and complete requirements at $CONTEXT_DIR/requirements.md. $NI_SUFFIX}"
    handle_agent_questions
    save_state "github-feature" "$id" 1 "done"
    wait_for_review "$CONTEXT_DIR/requirements.md"
  fi

  # --- Step 2: Create GitHub Issue ---
  if ! should_skip_step 2; then
    pstep 2 "Create GitHub Issue"
    save_state "github-feature" "$id" 2 "running"

    if confirm "Create GitHub issue from requirements?"; then
      if [ -f "$CONTEXT_DIR/requirements.md" ]; then
        issue_title=$(grep -m1 '^# ' "$CONTEXT_DIR/requirements.md" 2>/dev/null | sed 's/^# //' || echo "New feature request")
      fi

      local issue_url
      issue_url=$(run_claude_agent "requirements-engineer" \
        "Format $CONTEXT_DIR/requirements.md as a GitHub issue body and create it using gh issue create. The title should be: feat: $issue_title. Add the label 'feature-request'. Output ONLY the issue URL." 2>&1 | tail -1)

      if [ -n "$issue_url" ]; then
        success "GitHub issue created: $issue_url"
        issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$' || echo "")
      fi
    fi

    save_state "github-feature" "$id" 2 "done"
  fi

  # --- Step 3: Architecture & Planning ---
  if ! should_skip_step 3; then
    pstep 3 "Architecture & Planning"
    save_state "github-feature" "$id" 3 "running"
    run_claude_agent "architect" "Design solution using requirements from $CONTEXT_DIR/requirements.md. Create spec and todo in $CONTEXT_DIR/. $NI_SUFFIX Write the spec and todo files directly. If unclear, document assumptions in the spec."
    handle_agent_questions
    save_state "github-feature" "$id" 3 "done"
  fi

  # Find the todo file
  local todo_file
  todo_file=$(find "$CONTEXT_DIR" -name "*-todo.md" 2>/dev/null | sort -r | head -1)

  if [ -z "$todo_file" ]; then
    error "No todo file found in $CONTEXT_DIR. Architect may have failed."
    exit 1
  fi

  if ! should_skip_step 3; then
    wait_for_review "$todo_file"
  fi

  # --- Step 4-6: TDD Loop ---
  local total_steps
  total_steps=$(count_steps "$todo_file")
  info "Todo has $total_steps steps"
  local todo_basename
  todo_basename=$(basename "$todo_file" .md)

  for ((i = 1; i <= total_steps; i++)); do
    if ! should_skip_step "4.$i"; then
      pstep "4.$i" "TDD: Implement Step $i/$total_steps"
      save_state "github-feature" "$id" "4.$i" "running"
      run_claude_agent "tdd-developer" "Step $i of $todo_file"
      save_state "github-feature" "$id" "4.$i" "dev-done"
    fi

    if ! should_skip_step "5.$i"; then
      pstep "5.$i" "QA: Test Step $i/$total_steps"
      run_claude_agent "qa" "Run tests for Step $i of $todo_basename"
      save_state "github-feature" "$id" "5.$i" "qa-done"
    fi

    if ! should_skip_step "6.$i"; then
      pstep "6.$i" "Review: Step $i/$total_steps"
      run_claude_agent "reviewer" "Review Step $i of $todo_basename"
      save_state "github-feature" "$id" "6.$i" "review-done"

      emit_step_verdict "$id" "$i"
      run_triage "claude" "$id" "$i"
    fi
  done

  # --- Step 7: Create Pull Request ---
  if ! should_skip_step 7; then
    pstep 7 "Create Pull Request"
    if confirm "Create pull request on GitHub?"; then
      local branch
      branch=$(git branch --show-current)
      local base
      base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
      git push -u origin "$branch"

      local pr_body="## Summary
Generated with \`ai-native-workflow run github-feature\`

## Artifacts
- Requirements: \`$CONTEXT_DIR/requirements.md\`
- Todo: \`$todo_file\`"

      if [ -n "$issue_num" ]; then
        pr_body="Closes #$issue_num

$pr_body"
      fi

      pr_body="$(build_pr_body "$id" "$pr_body")"

      gh pr create \
        --title "feat: $issue_title" \
        --body "$pr_body"

      success "Pull request created!"
    fi
  fi

  save_state "github-feature" "$id" 7 "complete"

  pipeline_finish "github-feature" "$id" "claude"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║              PIPELINE 4: GITHUB ISSUE                           ║
# ╚══════════════════════════════════════════════════════════════════╝

pipeline_github_issue() {
  local input_id="$1"
  require_claude
  require_gh

  mkdir -p "$CONTEXT_DIR"
  local NI_SUFFIX
  NI_SUFFIX=$(build_ni_suffix)
  local id issue_id

  # --- On resume, recover state; otherwise set up fresh ---
  if [ -n "${RESUME_FROM_STEP:-}" ] && [ -f "$STATE_FILE" ]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    id="$ID"
    # Extract numeric issue ID from pipeline ID (e.g. "issue-42" → "42")
    issue_id="${id#issue-}"
    info "Resuming with ID: ${BOLD}$id${NC} (issue #${issue_id})"
    local expected_branch
    expected_branch=$(echo "fix/$id" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9\/_-]/-/g')
    git checkout "$expected_branch" 2>/dev/null || true
  else
    issue_id="$input_id"
    id="issue-${issue_id}"
    create_feature_branch "fix" "$id"
  fi

  write_active_spec "$id"

  header "Pipeline: GitHub Issue Investigation & Fix"
  info "Issue: ${BOLD}#${issue_id}${NC}"
  info "Agents: Claude Code | Platform: GitHub"
  echo ""
  enable_pipeline_error_trap

  # --- Step 1: Fetch issue + sub-issues ---
  if ! should_skip_step 1; then
    pstep 1 "Fetch Issue & Sub-Issues"
    save_state "github-issue" "$id" 1 "running"

    info "Reading issue #${issue_id}..."
    local issue_body
    issue_body=$(gh issue view "$issue_id" --json title,body,labels,state,comments,assignees 2>&1)

    # Fetch sub-issues (tasklist items / linked issues)
    local sub_issues=""
    # GitHub sub-issues via tasklist
    local sub_issue_ids
    sub_issue_ids=$(gh issue view "$issue_id" --json body --jq '.body' 2>/dev/null \
      | grep -oE '#[0-9]+' | sed 's/#//' | sort -u || true)

    if [ -n "$sub_issue_ids" ]; then
      info "Found sub-issue references: $(echo "$sub_issue_ids" | tr '\n' ' ')"
      for sub_id in $sub_issue_ids; do
        local sub_body
        sub_body=$(gh issue view "$sub_id" --json title,body,labels,state,comments 2>/dev/null || echo "Could not fetch #$sub_id")
        sub_issues="${sub_issues}

--- Sub-Issue #${sub_id} ---
${sub_body}"
      done
    fi

    # Also check for sub-issues via GitHub's sub-issue API
    local api_sub_issues
    api_sub_issues=$(gh api "repos/{owner}/{repo}/issues/${issue_id}/sub_issues" 2>/dev/null \
      | jq -r '.[] | "- #\(.number): \(.title) [\(.state)]"' 2>/dev/null || true)

    if [ -n "$api_sub_issues" ]; then
      info "Found sub-issues via API"
      for sub_id in $(echo "$api_sub_issues" | grep -oE '#[0-9]+' | sed 's/#//'); do
        if ! echo "$sub_issues" | grep -q "Sub-Issue #${sub_id}"; then
          local sub_body
          sub_body=$(gh issue view "$sub_id" --json title,body,labels,state,comments 2>/dev/null || echo "Could not fetch #$sub_id")
          sub_issues="${sub_issues}

--- Sub-Issue #${sub_id} ---
${sub_body}"
        fi
      done
    fi

    # Save all issue context to a file for agents to read
    cat > "$CONTEXT_DIR/${id}-issue-context.md" << ISSUE_EOF
# GitHub Issue #${issue_id}

## Main Issue
${issue_body}

## Sub-Issues
${sub_issues:-No sub-issues found.}
ISSUE_EOF

    success "Issue context saved: $CONTEXT_DIR/${id}-issue-context.md"
    save_state "github-issue" "$id" 1 "done"
  fi

  # --- Step 2: Troubleshooter investigates ---
  if ! should_skip_step 2; then
    pstep 2 "Investigation (Troubleshooter)"
    save_state "github-issue" "$id" 2 "running"
    run_claude_agent "troubleshooter" "Investigate GitHub issue #${issue_id}. Read the issue context at $CONTEXT_DIR/${id}-issue-context.md. Scan the codebase to understand the problem. Check git history for recent changes. Create a diagnosis spec at $CONTEXT_DIR/${id}-bugfix.md with: Problem Statement, Root Cause Analysis, Affected Files, Evidence (from code/git), and a recommended fix approach. Also create $CONTEXT_DIR/${id}-todo.md with atomic fix steps (Step 1 must reproduce the bug as a failing test). $NI_SUFFIX"
    handle_agent_questions
    save_state "github-issue" "$id" 2 "done"
    wait_for_review "$CONTEXT_DIR/${id}-bugfix.md"
  fi

  # --- Step 3: Architect creates plan ---
  if ! should_skip_step 3; then
    pstep 3 "Architecture & Planning"
    save_state "github-issue" "$id" 3 "running"
    run_claude_agent "architect" "Review the troubleshooter diagnosis at $CONTEXT_DIR/${id}-bugfix.md and the todo at $CONTEXT_DIR/${id}-todo.md. Refine the plan if needed — ensure each step is atomic, testable, and follows TDD. Update $CONTEXT_DIR/${id}-todo.md with the final plan. Read $CONTEXT_DIR/${id}-issue-context.md for original issue details. $NI_SUFFIX Write files directly. If unclear, document assumptions in the spec."
    handle_agent_questions
    save_state "github-issue" "$id" 3 "done"
    wait_for_review "$CONTEXT_DIR/${id}-todo.md"
  fi

  # --- Step 4-6: TDD Loop ---
  local todo_file="$CONTEXT_DIR/${id}-todo.md"
  local total_steps
  total_steps=$(count_steps "$todo_file")
  info "Todo has $total_steps steps"

  for ((i = 1; i <= total_steps; i++)); do
    if ! should_skip_step "4.$i"; then
      pstep "4.$i" "TDD: Implement Step $i/$total_steps"
      save_state "github-issue" "$id" "4.$i" "running"
      run_claude_agent "tdd-developer" "Step $i of $todo_file"
      save_state "github-issue" "$id" "4.$i" "dev-done"
    fi

    if ! should_skip_step "5.$i"; then
      pstep "5.$i" "QA: Test Step $i/$total_steps"
      run_claude_agent "qa" "Run tests for Step $i of ${id}-todo"
      save_state "github-issue" "$id" "5.$i" "qa-done"
    fi

    if ! should_skip_step "6.$i"; then
      pstep "6.$i" "Review: Step $i/$total_steps"
      run_claude_agent "reviewer" "Review Step $i of ${id}-todo"
      save_state "github-issue" "$id" "6.$i" "review-done"

      emit_step_verdict "$id" "$i"
      run_triage "claude" "$id" "$i"
    fi
  done

  # --- Step 7: Create Pull Request ---
  if ! should_skip_step 7; then
    pstep 7 "Create Pull Request"
    if confirm "Create pull request on GitHub?"; then
      local branch
      branch=$(git branch --show-current)
      local base
      base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
      git push -u origin "$branch"

      # Extract issue title for PR
      local issue_title
      issue_title=$(gh issue view "$issue_id" --json title --jq '.title' 2>/dev/null || echo "Fix issue #$issue_id")

      local pr_base_body
      pr_base_body="$(cat <<PR_EOF
Closes #${issue_id}

## Summary
Generated with \`ai-native-workflow run github-issue ${issue_id}\`

## Diagnosis
See \`$CONTEXT_DIR/${id}-bugfix.md\`

## Artifacts
- Issue context: \`$CONTEXT_DIR/${id}-issue-context.md\`
- Diagnosis: \`$CONTEXT_DIR/${id}-bugfix.md\`
- Todo: \`$CONTEXT_DIR/${id}-todo.md\`
PR_EOF
)"

      gh pr create \
        --title "fix: $issue_title" \
        --body "$(build_pr_body "$id" "$pr_base_body")"
      success "Pull request created!"
    fi
  fi

  save_state "github-issue" "$id" 7 "complete"

  pipeline_finish "github-issue" "$id" "claude"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║              PIPELINE STATUS & RESUME                           ║
# ╚══════════════════════════════════════════════════════════════════╝

pipeline_status() {
  if [ ! -f "$STATE_FILE" ]; then
    info "No active pipeline."
    return
  fi

  load_state

  header "Pipeline Status"
  echo -e "  Pipeline:     ${BOLD}${PIPELINE}${NC}"
  echo -e "  ID:           ${BOLD}${ID}${NC}"
  echo -e "  Current Step: ${BOLD}${CURRENT_STEP}${NC}"
  echo -e "  Status:       ${BOLD}${STATUS}${NC}"
  echo -e "  Last Updated: ${DIM}${TIMESTAMP}${NC}"
}

pipeline_resume() {
  if [ ! -f "$STATE_FILE" ]; then
    error "No active pipeline to resume."
    exit 1
  fi

  load_state

  info "Resuming pipeline: ${BOLD}$PIPELINE${NC} for ${BOLD}$ID${NC} at step ${BOLD}$CURRENT_STEP${NC} (${STATUS})"

  # Export resume step so pipeline functions can skip completed steps
  export RESUME_FROM_STEP="$CURRENT_STEP"

  case "$PIPELINE" in
    "gitlab-feature")
      pipeline_gitlab_feature "$ID"
      ;;
    "gitlab-incident")
      pipeline_gitlab_incident "$ID"
      ;;
    "github-feature")
      pipeline_github_feature "$ID"
      ;;
    "github-issue")
      pipeline_github_issue "$ID"
      ;;
    *)
      error "Unknown pipeline: $PIPELINE"
      exit 1
      ;;
  esac
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     GLOBAL INSTALLATION                         ║
# ╚══════════════════════════════════════════════════════════════════╝

