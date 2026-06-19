#!/usr/bin/env bash
# lib/common.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Helpers ---
info()    { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
error()   { echo -e "${RED}✗${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }
pstep()   { echo -e "\n${BOLD}${MAGENTA}▸ Step $1:${NC} $2"; }
dim()     { echo -e "${DIM}  $*${NC}"; }
ask()     { echo -en "${YELLOW}?${NC} $* "; }

backup_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "${file}${BACKUP_SUFFIX}"
    dim "Backed up existing $(basename "$file")"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  local description="${3:-}"
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
  if [ -n "$description" ]; then
    success "$description"
  fi
}

# Canonical "## Agent Pipeline" + "## Stack Detection" markdown. This block is
# byte-identical in the global CLAUDE.md managed block and the Copilot
# instructions, so it lives in one place to stop the two from drifting (#15).
# Tool-specific sections (skills list, diff-reviewer invocation) stay inline at
# each call site because they legitimately differ between Claude and Copilot.
render_pipeline_and_stacks_md() {
  cat << 'PIPELINE_STACKS_EOF'
## Agent Pipeline
All new work starts with `/plan`. The pipeline:
1. **requirements-engineer** (Opus-tier) — elicits & formalizes requirements
2. **architect** (Opus-tier) — designs spec + atomic todo plan
3. **tdd-developer** (Sonnet-tier) — implements one step via TDD
4. **qa** (Haiku-tier) — runs affected tests
5. **reviewer** (Sonnet-tier) — reviews code, user triages findings
Max 3 fix loops per step, then remaining issues go to tech debt.

For production incidents, use **troubleshooter** (Opus-tier):
- Pulls Jira ticket, ArgoCD logs, Azure Application Insights
- Produces diagnosis + TDD fix plan for tdd-developer

## Stack Detection
Detect the active stack from project files and auto-apply conventions:
- `*.csproj` or `*.sln` → .NET (xUnit, FluentAssertions, NSubstitute)
- `go.mod` → Go (testing + testify, table-driven)
- `Cargo.toml` → Rust (built-in + tokio-test, axum)
- `pyproject.toml` or `requirements.txt` → Python (pytest, Pydantic)
- `package.json` with react → React/TS (Vitest + Testing Library)
- `package.json` with react-native → React Native (Jest + RNTL)
- `Package.swift` or `*.xcodeproj` → Swift (XCTest)
PIPELINE_STACKS_EOF
}
