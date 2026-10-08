#!/usr/bin/env bash
# lib/status.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

show_status() {
  header "AI-Native Workflow v${VERSION} — Installation Status"
  echo ""

  status_home "Claude Code" "$CLAUDE_DIR" CLAUDE.md
  if command -v copilot &> /dev/null || [ -d "$COPILOT_DIR" ]; then
    echo ""
    status_home "Copilot CLI" "$COPILOT_DIR" copilot-instructions.md
  fi

  echo ""
  header "Current Directory ($(pwd))"
  check_file "AGENTS.md" "AGENTS.md"
  check_file "CLAUDE.md" "CLAUDE.md"
  check_file "$SPRINT_FILE" "docs/context/"
  if [ ! -e .anw/verify ]; then missing ".anw/verify (finish line)"
  elif verify_is_trusted .; then success ".anw/verify (trusted)"
  else warn ".anw/verify is not trusted — review it, then: ai-native-workflow trust"; fi

  # Shown, never sourced: the file lives in the (possibly untrusted) repo.
  if [ -f "$STATE_FILE" ]; then
    echo ""
    header "Active Pipeline"
    grep -E '^(PIPELINE|ID|STAGE|TIMESTAMP)=' "$STATE_FILE" | sed 's/^/  /' || true
  fi

  echo ""
  local stacks
  stacks=$(detect_stacks ".")
  if [ -n "$stacks" ]; then
    info "Detected stacks: $(echo "$stacks" | tr '\n' ', ' | sed 's/,$//')"
  fi
  info "Platform: $(detect_platform ".")"
}

status_home() {
  local label="$1" home="$2" instr="$3" f src name
  header "$label (${home/#$HOME/~}/)"
  for f in guard.sh verify.sh; do
    if cmp -s "$_ANW_SCRIPT_DIR/hooks/$f" "$home/hooks/$f"; then success "hooks/$f"
    elif [ -f "$home/hooks/$f" ]; then problem "hooks/$f differs from this version — run install global"
    else missing "hooks/$f"; fi
  done
  if [ "$instr" = CLAUDE.md ]; then
    if jq -e '[.hooks[]?[]?.hooks[]?.command // ""] | any(test("hooks/guard\\.sh")) and any(test("hooks/verify\\.sh"))' \
        "$home/settings.json" >/dev/null 2>&1; then success "settings.json runs guard.sh + verify.sh"
    else missing "settings.json hook wiring"; fi
  else
    check_file "$home/hooks/anw.json" "hooks/anw.json (preToolUse → guard.sh, agentStop → verify.sh)"
  fi
  if grep -qF "$MANAGED_BEGIN" "$home/$instr" 2>/dev/null; then success "$instr (managed block)"; else missing "$instr managed block"; fi
  for src in "$_ANW_SCRIPT_DIR"/skills/*/; do
    src="${src%/}"; name="$(basename "$src")"
    is_retired_skill "$name" && continue
    if is_installed_copy "$src" "$home/skills/$name"; then success "skills/$name"
    elif [ -e "$home/skills/$name" ]; then problem "skills/$name differs from this version — run install global"
    else missing "skills/$name"; fi
  done
}

# Exit 1, naming each path, if the install drifted, a custom agent exists, or this
# repo's finish line isn't trusted. `status` shows the same checks without failing.
doctor() {
  local f root
  ANW_PROBLEMS=0
  header "AI-Native Workflow v${VERSION} — doctor"
  status_home "Claude Code" "$CLAUDE_DIR" CLAUDE.md
  if command -v copilot &> /dev/null || [ -d "$COPILOT_DIR" ]; then
    echo ""
    status_home "Copilot CLI" "$COPILOT_DIR" copilot-instructions.md
  fi
  for f in "$CLAUDE_DIR"/agents/*.md "$COPILOT_DIR"/agents/*.md; do
    [ -e "$f" ] || continue
    problem "custom agent ${f/#$HOME/~} (the harness uses the tools' native agents)"
  done
  if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -e "$root/.anw/verify" ]; then
    echo ""
    header "This repo ($root)"
    if verify_is_trusted "$root"; then success ".anw/verify trusted"
    else problem "$root/.anw/verify is not trusted — review it, then: ai-native-workflow trust"; fi
  fi
  echo ""
  if [ "$ANW_PROBLEMS" -eq 0 ]; then success "No problems found"; return 0; fi
  error "$ANW_PROBLEMS problem(s) found"
  return 1
}

ANW_PROBLEMS=0
problem() { ANW_PROBLEMS=$((ANW_PROBLEMS + 1)); warn "$*"; }
missing() { ANW_PROBLEMS=$((ANW_PROBLEMS + 1)); echo -e "  ${DIM}○ $1 (missing)${NC}"; }

check_file() {
  if [ -f "$1" ]; then success "$2"; else missing "$2"; fi
}

show_detect() {
  local project_dir="${1:-.}"
  header "Stack Detection: $project_dir"
  echo ""

  local stacks
  stacks=$(detect_stacks "$project_dir")

  if [ -z "$stacks" ]; then
    warn "No stacks detected"
    return
  fi

  while IFS= read -r stack; do
    case "$stack" in
      dotnet)       info ".NET — xUnit + FluentAssertions + NSubstitute" ;;
      go)           info "Go — testing + testify (table-driven)" ;;
      rust)         info "Rust — built-in + tokio-test" ;;
      python)       info "Python — pytest + Pydantic" ;;
      react-ts)
        local tr e2e
        tr=$(detect_test_runner "$project_dir")
        e2e=$(detect_e2e_runner "$project_dir")
        info "React/TypeScript — ${tr:-Vitest} + Testing Library${e2e:+ + $e2e}"
        ;;
      react-native) info "React Native — Jest + RNTL + Detox" ;;
      typescript)   info "TypeScript/Node" ;;
      swift)        info "Swift — XCTest + MVVM" ;;
    esac
  done <<< "$stacks"

  echo ""
  info "Platform: $(detect_platform "$project_dir")"
}

