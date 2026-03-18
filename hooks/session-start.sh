#!/usr/bin/env bash
# Injects project context into Claude Code session on start
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CONTEXT=""

detect_stack() {
  local stack=""
  if compgen -G "$PROJECT_DIR"/*.sln > /dev/null 2>&1 || \
     find "$PROJECT_DIR" -maxdepth 3 -name "*.csproj" -print -quit 2>/dev/null | grep -q . 2>/dev/null; then
    stack="dotnet (xUnit + FluentAssertions)"
  elif [ -f "$PROJECT_DIR/go.mod" ]; then
    stack="go (testing + testify)"
  elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
    stack="rust (built-in + tokio-test)"
  elif [ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/requirements.txt" ]; then
    stack="python (pytest)"
  elif [ -f "$PROJECT_DIR/package.json" ]; then
    if grep -q '"react-native"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      stack="react-native (Jest + RNTL, E2E: Detox)"
    elif grep -q '"react"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      local tr="Vitest" e2e=""
      grep -q '"jest"' "$PROJECT_DIR/package.json" 2>/dev/null && tr="Jest"
      grep -q '"playwright"' "$PROJECT_DIR/package.json" 2>/dev/null && e2e=", E2E: Playwright"
      grep -q '"cypress"' "$PROJECT_DIR/package.json" 2>/dev/null && e2e=", E2E: Cypress"
      stack="react-ts ($tr + Testing Library$e2e)"
    else
      stack="typescript"
    fi
  elif [ -f "$PROJECT_DIR/Package.swift" ] || compgen -G "$PROJECT_DIR"/*.xcodeproj > /dev/null 2>&1; then
    stack="swift (XCTest)"
  fi
  echo "$stack"
}

STACK=$(detect_stack)
[ -n "$STACK" ] && CONTEXT="📦 Detected stack: $STACK\n"

if [ -f "$PROJECT_DIR/.context/CURRENT_SPRINT.md" ]; then
  SPRINT=$(head -20 "$PROJECT_DIR/.context/CURRENT_SPRINT.md")
  CONTEXT="${CONTEXT}\n📋 Current Sprint:\n${SPRINT}\n"
fi

if git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  RECENT=$(git -C "$PROJECT_DIR" log --oneline -5 2>/dev/null || echo "No commits yet")
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "detached")
  DIRTY=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  CONTEXT="${CONTEXT}\n🌿 Branch: ${BRANCH}"
  [ "$DIRTY" -gt 0 ] && CONTEXT="${CONTEXT} (${DIRTY} uncommitted changes)"
  CONTEXT="${CONTEXT}\n📝 Recent commits:\n${RECENT}\n"
fi

if [ -f "$PROJECT_DIR/.tdd-skip" ]; then
  REASON=$(grep "^Reason:" "$PROJECT_DIR/.tdd-skip" 2>/dev/null | sed 's/^Reason: //' || echo "unknown")
  CONTEXT="${CONTEXT}\n⚠️ TDD bypass ACTIVE — Reason: ${REASON}\n"
fi

if [ -f "$PROJECT_DIR/.gitlab-ci.yml" ]; then
  CONTEXT="${CONTEXT}\n🏢 Platform: GitLab (use glab for MRs)\n"
elif [ -d "$PROJECT_DIR/.github" ]; then
  CONTEXT="${CONTEXT}\n🐙 Platform: GitHub (use gh for PRs)\n"
fi

[ -f "$PROJECT_DIR/AGENTS.md" ] && CONTEXT="${CONTEXT}\n📖 Read AGENTS.md for project rules.\n"

echo -e "$CONTEXT"
