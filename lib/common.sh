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
