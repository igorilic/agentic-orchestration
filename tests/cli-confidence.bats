#!/usr/bin/env bats

load 'lib/confidence-helpers'

SCRIPTS_DIR="$BATS_TEST_DIRNAME/../scripts"

setup() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR"
  git init -q
  mkdir -p .context/specs .git/aw
  CLI_HELPER="$BATS_TEST_DIRNAME/../scripts/confidence-cli.sh"
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

# ---------------------------------------------------------------------------
# write_active_spec
# ---------------------------------------------------------------------------

@test "write_active_spec creates .git/aw/active-spec with correct content" {
  source "$CLI_HELPER"
  write_active_spec "PROJ-42"
  [ -f ".git/aw/active-spec" ]
  [ "$(cat .git/aw/active-spec)" = "PROJ-42" ]
}

@test "write_active_spec overwrites pre-existing active-spec" {
  echo "OLD-1" > .git/aw/active-spec
  source "$CLI_HELPER"
  write_active_spec "NEW-99"
  [ "$(cat .git/aw/active-spec)" = "NEW-99" ]
}

@test "write_active_spec creates .git/aw directory if missing" {
  rm -rf .git/aw
  source "$CLI_HELPER"
  write_active_spec "PROJ-1"
  [ -f ".git/aw/active-spec" ]
}

# ---------------------------------------------------------------------------
# build_pr_body
# ---------------------------------------------------------------------------

@test "build_pr_body injects ## Confidence section into base body" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "Initial body")"
  [[ "$result" == *"## Confidence"* ]]
}

@test "build_pr_body shows GREEN for clean log" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "Initial body")"
  [[ "$result" == *"GREEN"* ]]
}

@test "build_pr_body shows RED with failing gate names in body" {
  source "$CLI_HELPER"
  # No spec event → NO_AC gate fires → RED
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "Initial body")"
  [[ "$result" == *"RED"* ]]
}

@test "build_pr_body preserves the base body text" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body "PROJ-1" "My PR summary here")"
  [[ "$result" == *"My PR summary here"* ]]
}

@test "build_pr_body does not mutate the log file" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  before_lines=$(wc -l < .context/specs/PROJ-1-confidence.jsonl)
  build_pr_body "PROJ-1" "body" >/dev/null
  after_lines=$(wc -l < .context/specs/PROJ-1-confidence.jsonl)
  [ "$before_lines" -eq "$after_lines" ]
}

# ---------------------------------------------------------------------------
# emit_step_verdict
# ---------------------------------------------------------------------------

@test "emit_step_verdict appends a step-scope verdict event to the log" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  before_lines=$(wc -l < .context/specs/PROJ-1-confidence.jsonl)
  # Feed 'go' to skip the interactive prompt (band will be GREEN, no prompt)
  emit_step_verdict "PROJ-1" 1 >/dev/null
  after_lines=$(wc -l < .context/specs/PROJ-1-confidence.jsonl)
  [ "$after_lines" -gt "$before_lines" ]
}

@test "emit_step_verdict appended event has scope=step and correct step number" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  emit_step_verdict "PROJ-1" 1 >/dev/null
  # Last line of the log should be the verdict event
  last="$(tail -1 .context/specs/PROJ-1-confidence.jsonl)"
  echo "$last" | jq -e '.event == "verdict"'
  echo "$last" | jq -e '.scope == "step"'
  echo "$last" | jq -e '.step == 1'
}

@test "emit_step_verdict prints band and score to stdout" {
  source "$CLI_HELPER"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(emit_step_verdict "PROJ-1" 1)"
  [[ "$result" == *"confidence"* ]]
  [[ "$result" == *"GREEN"* ]]
}

# ---------------------------------------------------------------------------
# CLI dry-run: pipeline start writes active-spec
# ---------------------------------------------------------------------------

@test "CLI pipeline start writes .git/aw/active-spec when AW_SPEC_ID set" {
  CLI="$BATS_TEST_DIRNAME/../ai-native-workflow"
  # AW_DRY_RUN=1 skips agent invocations; AW_SPEC_ID provides the spec id.
  AW_DRY_RUN=1 AW_SPEC_ID=PROJ-42 "$CLI" run github-feature 2>/dev/null || true
  [ -f ".git/aw/active-spec" ]
  [ "$(cat .git/aw/active-spec)" = "PROJ-42" ]
}

# ---------------------------------------------------------------------------
# Pipeline wiring: emit_step_verdict called after reviewer in TDD loop
# ---------------------------------------------------------------------------
# These tests call the actual pipeline_github_feature function with all
# external dependencies stubbed. They verify that the pipeline itself calls
# emit_step_verdict (by checking side effects on the confidence log) and
# build_pr_body (by capturing what is passed to gh pr create).

_setup_pipeline_stubs() {
  # Source the workflow CLI to get all pipeline functions
  # shellcheck disable=SC1090
  source "$BATS_TEST_DIRNAME/../ai-native-workflow"

  require_claude() { return 0; }
  require_gh()     { return 0; }
  enable_pipeline_error_trap()  { return 0; }
  disable_pipeline_error_trap() { return 0; }
  save_state()  { return 0; }
  clear_state() { return 0; }
  audit_log()   { return 0; }
  spinner_start() { return 0; }
  spinner_stop()  { return 0; }
  handle_agent_questions() { return 0; }
  wait_for_review() { return 0; }
  pipeline_finish() { return 0; }
  confirm() { return 0; }
  build_ni_suffix() { echo ""; }
  create_feature_branch() { echo "feat/test"; }
  git() {
    case "$1" in
      branch)       echo "feat/test-branch" ;;
      symbolic-ref) echo "main" ;;
      push|checkout|add|commit) return 0 ;;
      rev-list) echo "1" ;;
      log)      echo "abc feat: test" ;;
      diff)     echo "file.go | 5 +" ;;
      *) return 0 ;;
    esac
  }
  run_claude_agent() { return 0; }
  run_triage()       { return 0; }
}

@test "pipeline wiring: github-feature TDD loop calls emit_step_verdict — verdict event appears in confidence log" {
  local spec_id="PROJ-wiring-01"

  mkdir -p .context/specs
  # A 1-step todo file so the loop runs once
  printf '### Step 1\nDo thing\n' > ".context/specs/${spec_id}-todo.md"
  # Seed the confidence log so emit_step_verdict can score
  make_log ".context/specs/${spec_id}-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  _setup_pipeline_stubs

  # count_steps returns 1 so the loop runs once
  count_steps() { echo 1; }
  # find returns our todo file
  find() {
    if [[ "$*" == *"-todo.md"* ]]; then
      echo ".context/specs/${spec_id}-todo.md"
    else
      command find "$@"
    fi
  }
  # Skip all steps except 6.1 (reviewer step)
  should_skip_step() {
    local s="$1"
    [ "$s" = "6.1" ] && return 1
    return 0
  }
  # Stub interactive input for "Describe the feature:"
  # pipeline_github_feature tries to read from stdin if no specs_file
  gh() { return 0; }

  # Run the actual pipeline function (no specs file → id is generated internally)
  # We override AW_SPEC_ID so write_active_spec uses the right name;
  # the todo path is discovered via find() which we stubbed above.
  # The pipeline generates its own id (feature-YYYYMMDD-HHMMSS).
  # We stub count_steps and find to use our pre-seeded spec_id.
  # emit_step_verdict uses the id from the pipeline; we can't control it directly.
  # Instead, override emit_step_verdict to write to our known log path.
  emit_step_verdict() {
    local sid="$1" step="$2"
    local log=".context/specs/${spec_id}-confidence.jsonl"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -cn --arg ts "$ts" --argjson step "$step" --arg band "GREEN" --argjson score 100 \
      '{ts:$ts, event:"verdict", scope:"step", step:$step, band:$band, score:$score}' \
      >> "$log"
    echo "[step $step] confidence: GREEN (100/100)"
  }
  # Provide non-interactive input for "Describe the feature:" prompt
  exec 0</dev/null 2>/dev/null || true

  # Use a specs file to bypass interactive input
  printf '# Test feature\nDo something useful.\n' > specs.md

  # Run the pipeline (will call emit_step_verdict at step 6.1)
  pipeline_github_feature "specs.md" 2>/dev/null || true

  # The verdict event should have been appended by the (possibly stubbed)
  # emit_step_verdict call site inside the pipeline.
  grep -q '"event":"verdict"' ".context/specs/${spec_id}-confidence.jsonl"
}

@test "pipeline wiring: github-feature TDD loop calls emit_step_verdict with correct step number" {
  local spec_id="PROJ-wiring-02"

  mkdir -p .context/specs
  printf '### Step 1\nDo thing\n' > ".context/specs/${spec_id}-todo.md"
  make_log ".context/specs/${spec_id}-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  _setup_pipeline_stubs
  count_steps() { echo 1; }
  find() {
    [[ "$*" == *"-todo.md"* ]] && echo ".context/specs/${spec_id}-todo.md" || command find "$@"
  }
  should_skip_step() {
    local s="$1"; [ "$s" = "6.1" ] && return 1; return 0
  }
  gh() { return 0; }
  emit_step_verdict() {
    local sid="$1" step="$2"
    local log=".context/specs/${spec_id}-confidence.jsonl"
    local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -cn --arg ts "$ts" --argjson step "$step" --arg band "GREEN" --argjson score 100 \
      '{ts:$ts, event:"verdict", scope:"step", step:$step, band:$band, score:$score}' >> "$log"
    echo "[step $step] confidence: GREEN (100/100)"
  }
  printf '# Test\nDo thing.\n' > specs.md
  exec 0</dev/null 2>/dev/null || true

  pipeline_github_feature "specs.md" 2>/dev/null || true

  last="$(grep '"event":"verdict"' ".context/specs/${spec_id}-confidence.jsonl" | tail -1)"
  echo "$last" | jq -e '.step == 1'
}

# ---------------------------------------------------------------------------
# Pipeline wiring: build_pr_body injects ## Confidence into gh pr create
# ---------------------------------------------------------------------------

@test "pipeline wiring: github-feature PR step passes body through build_pr_body — ## Confidence present" {
  local spec_id="PROJ-wiring-pr"
  local captured_body_file
  captured_body_file="$(mktemp)"

  mkdir -p .context/specs
  # No steps todo so the TDD loop is empty; we only want step 7 to run
  printf '' > ".context/specs/${spec_id}-todo.md"
  make_log ".context/specs/${spec_id}-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  _setup_pipeline_stubs
  count_steps() { echo 0; }
  find() {
    [[ "$*" == *"-todo.md"* ]] && echo ".context/specs/${spec_id}-todo.md" || command find "$@"
  }
  should_skip_step() {
    local s="$1"; [ "$s" = "7" ] && return 1; return 0
  }
  # Stub gh to capture the --body argument
  gh() {
    local body_next=0
    for arg in "$@"; do
      if [ "$body_next" = "1" ]; then
        printf '%s' "$arg" > "$captured_body_file"
        body_next=0
      fi
      [ "$arg" = "--body" ] && body_next=1
    done
    return 0
  }
  # Override build_pr_body to inject a recognizable marker so we can confirm
  # the pipeline calls it (rather than bypassing it).
  build_pr_body() {
    local sid="$1" base="$2"
    printf '%s\n\n## Confidence\n**GREEN: 100/100**\n\nPenalties: (none)\nAudit: stub\n' "$base"
  }
  printf '# Test\nDo thing.\n' > specs.md
  exec 0</dev/null 2>/dev/null || true

  pipeline_github_feature "specs.md" 2>/dev/null || true

  # The captured body should contain ## Confidence if the pipeline called build_pr_body
  [ -f "$captured_body_file" ]
  grep -q '## Confidence' "$captured_body_file"
  rm -f "$captured_body_file"
}
