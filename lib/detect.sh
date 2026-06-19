#!/usr/bin/env bash
# lib/detect.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash


# ╔══════════════════════════════════════════════════════════════════╗
# ║                     STACK DETECTION                             ║
# ╚══════════════════════════════════════════════════════════════════╝

detect_stacks() {
  local project_dir="${1:-.}"
  local stacks=()

  # .NET
  if compgen -G "$project_dir"/*.sln > /dev/null 2>&1 || \
     find "$project_dir" -maxdepth 3 -name "*.csproj" -print -quit 2>/dev/null | grep -q .; then
    stacks+=("dotnet")
  fi

  # Go (check root + subdirectories)
  if find "$project_dir" -maxdepth 3 -name "go.mod" -not -path "*/vendor/*" -print -quit 2>/dev/null | grep -q .; then
    stacks+=("go")
  fi

  # Rust (check root + subdirectories for workspace members)
  if find "$project_dir" -maxdepth 3 -name "Cargo.toml" -not -path "*/target/*" -print -quit 2>/dev/null | grep -q .; then
    stacks+=("rust")
  fi

  # Python (check root + subdirectories)
  if find "$project_dir" -maxdepth 3 \( -name "pyproject.toml" -o -name "requirements.txt" -o -name "setup.py" \) \
     -not -path "*/.venv/*" -not -path "*/venv/*" -print -quit 2>/dev/null | grep -q .; then
    stacks+=("python")
  fi

  # React Native (check before React — it also has react in package.json)
  if [ -f "$project_dir/package.json" ] && grep -q '"react-native"' "$project_dir/package.json" 2>/dev/null; then
    stacks+=("react-native")
  # React / TypeScript
  elif [ -f "$project_dir/package.json" ] && grep -q '"react"' "$project_dir/package.json" 2>/dev/null; then
    stacks+=("react-ts")
  # Plain TypeScript / Node
  elif [ -f "$project_dir/package.json" ] || [ -f "$project_dir/tsconfig.json" ]; then
    stacks+=("typescript")
  fi

  # Swift
  if [ -f "$project_dir/Package.swift" ] || \
     compgen -G "$project_dir"/*.xcodeproj > /dev/null 2>&1 || \
     compgen -G "$project_dir"/*.xcworkspace > /dev/null 2>&1; then
    stacks+=("swift")
  fi

  # Return unique stacks. Guard the empty case: under `set -u` on bash 3.2,
  # "${stacks[@]}" on an empty array throws "unbound variable", which (as the
  # function's terminal command) would abort `install project` on a stackless
  # repo. Return nothing so the generic-fallback path stays reachable.
  [ ${#stacks[@]} -eq 0 ] && return 0
  printf '%s\n' "${stacks[@]}" | sort -u
}

detect_platform() {
  local project_dir="${1:-.}"
  if [ -f "$project_dir/.gitlab-ci.yml" ] || \
     (git -C "$project_dir" remote -v 2>/dev/null | grep -q gitlab); then
    echo "gitlab"
  else
    echo "github"
  fi
}

detect_e2e_runner() {
  local project_dir="${1:-.}"
  if [ -f "$project_dir/package.json" ]; then
    if grep -q '"playwright"' "$project_dir/package.json" 2>/dev/null || \
       [ -f "$project_dir/playwright.config.ts" ] || [ -f "$project_dir/playwright.config.js" ]; then
      echo "playwright"
    elif grep -q '"cypress"' "$project_dir/package.json" 2>/dev/null || \
         [ -d "$project_dir/cypress" ]; then
      echo "cypress"
    fi
  fi
}

detect_test_runner() {
  local project_dir="${1:-.}"
  if [ -f "$project_dir/package.json" ]; then
    if grep -q '"vitest"' "$project_dir/package.json" 2>/dev/null || \
       [ -f "$project_dir/vitest.config.ts" ] || [ -f "$project_dir/vitest.config.js" ]; then
      echo "vitest"
    elif grep -q '"jest"' "$project_dir/package.json" 2>/dev/null || \
         [ -f "$project_dir/jest.config.ts" ] || [ -f "$project_dir/jest.config.js" ]; then
      echo "jest"
    fi
  fi
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     CLI DETECTION                               ║
# ╚══════════════════════════════════════════════════════════════════╝

require_copilot() {
  if ! command -v copilot &>/dev/null; then
    error "GitHub Copilot CLI not found. Install: https://docs.github.com/en/copilot/github-copilot-in-the-cli"
    exit 1
  fi
}

require_claude() {
  if ! command -v claude &>/dev/null; then
    error "Claude Code CLI not found. Install: npm install -g @anthropic-ai/claude-code"
    exit 1
  fi
}

require_glab() {
  if ! command -v glab &>/dev/null; then
    error "glab CLI not found. Install: brew install glab"
    exit 1
  fi
}

require_gh() {
  if ! command -v gh &>/dev/null; then
    error "gh CLI not found. Install: brew install gh"
    exit 1
  fi
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     ERROR HANDLING & AUDIT LOG                  ║
# ╚══════════════════════════════════════════════════════════════════╝

AUDIT_LOG="${RUNTIME_DIR}/.pipeline-audit.log"

