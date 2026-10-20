#!/usr/bin/env bash
# lib/pipelines.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

# One ticket, issue or spec → one branch, one plan, one PR/MR. The flow is in pipeline-core.sh.

pipeline_github_feature() {  # [spec file | description]
  local input="${1:-}" id
  require_claude; require_gh; repo_root || return 1
  if [ -f "$input" ]; then
    id="$(basename "$input")"; id="${id%.*}"; id="${id//[^A-Za-z0-9._-]/-}"; input="the spec in $input"
  else
    if [ -z "$input" ]; then ask "Describe the feature:"; read -r input || true; fi
    [ -n "$input" ] || { error "Nothing to plan"; return 1; }
    id="feature-$(date +%Y%m%d-%H%M%S)"
  fi
  valid_id "$id" || return 1
  pipeline_flow github-feature claude "$id" "$input" feature ""
}

pipeline_github_issue() {  # <issue number>
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { error "Usage: ai-native-workflow run github-issue <number>"; return 1; }
  require_claude; require_gh; repo_root || return 1
  pipeline_flow github-issue claude "issue-$1" "GitHub issue #$1" fix "Closes #$1"
}

pipeline_gitlab_feature() {  # <JIRA-ID>
  valid_id "${1:-}" || return 1
  require_copilot; require_glab; repo_root || return 1
  pipeline_flow gitlab-feature copilot "$1" "Jira ticket $1" feature "Closes $1"
}

# A read-only /incident first; you decide whether it gets fixed. The fix is planned from the report.
pipeline_gitlab_incident() {  # <JIRA-ID>
  local id="${1:-}" report
  valid_id "$id" || return 1
  require_copilot; require_glab; repo_root || return 1
  report="$SPEC_DIR/$id-incident.html"
  if [ "$(state_get PIPELINE)" != gitlab-incident ] || [ "$(state_get ID)" != "$id" ]; then
    RUN_DIR=".anw/runs/$id"; mkdir -p "$RUN_DIR" "$(dirname "$report")"
    if [ -f "$report" ]; then info "Using the existing report: $report"
    else run_stage copilot incident incident "/incident $id — write the report to $report" || return 1; fi
    echo ""; show_doc "$report"; echo ""
    if ! confirm "Fix it now (plan, implement, check, then an MR)?"; then
      jira_comment "$id" "Incident report: $report"
      return 0
    fi
  fi
  pipeline_flow gitlab-incident copilot "$id" "$report" fix "Closes $id"
}

pipeline_status() {
  repo_root || return 1
  [ -f "$STATE_FILE" ] || { info "No active pipeline here."; return 0; }
  info "$(state_get PIPELINE) $(state_get ID): done through '$(state_get STAGE)' ($(state_get TIMESTAMP))"
  dim "Transcripts: .anw/runs/$(state_get ID)/ · continue with: ai-native-workflow run resume"
}

pipeline_resume() {
  local pipeline id
  repo_root || return 1
  pipeline="$(state_get PIPELINE)"; id="$(state_get ID)"
  [ -n "$pipeline" ] && valid_id "$id" || { error "No pipeline to resume here."; return 1; }
  case "$pipeline" in
    github-feature)  require_claude; require_gh; pipeline_flow github-feature claude "$id" "" feature "" ;;
    github-issue)    pipeline_github_issue "${id#issue-}" ;;
    gitlab-feature)  pipeline_gitlab_feature "$id" ;;
    gitlab-incident) pipeline_gitlab_incident "$id" ;;
    *) error "Unknown pipeline in $STATE_FILE: $pipeline"; return 1 ;;
  esac
}
