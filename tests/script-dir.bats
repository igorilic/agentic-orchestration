#!/usr/bin/env bats
# Tests for _ANW_SCRIPT_DIR symlink resolution (BREW-1 / AC-1..AC-4).
# Exercises the __print-script-dir internal subcommand.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"

# The canonical real directory that contains ai-native-workflow.
REAL_SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

setup() {
  TMPDIR1="$(mktemp -d)"
  TMPDIR2="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR1" "$TMPDIR2"
}

# AC-1: Canonical invocation (no symlinks involved) resolves to the real parent dir.
@test "script-dir: canonical invocation matches script directory" {
  run "$INSTALLER" __print-script-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL_SCRIPT_DIR" ]
}

# AC-2: Single-level symlink — symlink lives in TMPDIR1, target is the real script.
@test "script-dir: single-level symlink resolves to real parent dir" {
  ln -s "$INSTALLER" "$TMPDIR1/ai-native-workflow"
  run "$TMPDIR1/ai-native-workflow" __print-script-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL_SCRIPT_DIR" ]
}

# AC-3: Two-hop symlink chain: TMPDIR1/cli -> TMPDIR2/cli -> real script.
@test "script-dir: symlink chain (a -> b -> real) resolves to real parent dir" {
  ln -s "$INSTALLER" "$TMPDIR2/ai-native-workflow"
  ln -s "$TMPDIR2/ai-native-workflow" "$TMPDIR1/ai-native-workflow"
  run "$TMPDIR1/ai-native-workflow" __print-script-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL_SCRIPT_DIR" ]
}

# AC-4: Pure-bash fallback works when realpath and greadlink are not on PATH.
# Shadow realpath and greadlink with stubs that always exit non-zero so the
# pure-bash loop is actually exercised.  macOS 12.3+ ships /bin/realpath,
# so restricting PATH alone is insufficient.
@test "script-dir: pure-bash fallback works without realpath/greadlink on PATH" {
  mkdir -p "$TMPDIR2/stubs"
  printf '#!/bin/sh\nexit 127\n' > "$TMPDIR2/stubs/realpath"
  printf '#!/bin/sh\nexit 127\n' > "$TMPDIR2/stubs/greadlink"
  chmod +x "$TMPDIR2/stubs/realpath" "$TMPDIR2/stubs/greadlink"

  ln -s "$INSTALLER" "$TMPDIR1/ai-native-workflow"
  run env PATH="$TMPDIR2/stubs:/usr/bin:/bin" "$TMPDIR1/ai-native-workflow" __print-script-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL_SCRIPT_DIR" ]
}

# Guard: a legitimate symlink chain resolves correctly (proves the
# 100-iteration cap does not fire prematurely).
# macOS ELOOP fires when execve traverses ~17+ symlinks before bash even
# starts, so we use 15 hops — well above any typical brew-style chain but
# safely below the kernel limit.
@test "script-dir: long symlink chain (15 hops) still resolves under guard" {
  mkdir -p "$TMPDIR1/chain"
  prev="$INSTALLER"
  for i in $(seq 1 15); do
    next="$TMPDIR1/chain/link-$i"
    ln -s "$prev" "$next"
    prev="$next"
  done
  run "$prev" __print-script-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL_SCRIPT_DIR" ]
}

# Fix 2 regression: resolution must return the PHYSICAL path (pwd -P), not
# the logical path.  On macOS, /tmp is a symlink to /private/tmp, so a script
# copied into a mktemp dir has a logical path starting with /tmp and a physical
# path starting with /private/tmp.  The pure-bash fallback and the outer
# _ANW_SCRIPT_DIR assignment must both use pwd -P.
# This test exercises the fallback tier by shadowing realpath and greadlink.
@test "script-dir: pure-bash fallback returns physical path (pwd -P)" {
  # /tmp -> /private/tmp on macOS; skip if not present
  if [ ! -L /tmp ]; then
    skip "/tmp is not a symlink on this OS; cannot exercise pwd -P difference"
  fi

  mkdir -p "$TMPDIR2/stubs"
  printf '#!/bin/sh\nexit 127\n' > "$TMPDIR2/stubs/realpath"
  printf '#!/bin/sh\nexit 127\n' > "$TMPDIR2/stubs/greadlink"
  chmod +x "$TMPDIR2/stubs/realpath" "$TMPDIR2/stubs/greadlink"

  # Place a copy of the script under a logical /tmp path
  LOGICAL_DIR="$(mktemp -d /tmp/anw-pwdp-XXXXXX)"
  PHYSICAL_DIR="$(cd "$LOGICAL_DIR" && pwd -P)"

  # Sanity: paths must differ; if they don't, skip
  if [ "$LOGICAL_DIR" = "$PHYSICAL_DIR" ]; then
    rm -rf "$LOGICAL_DIR"
    skip "mktemp returned an already-physical path; cannot exercise pwd -P difference"
  fi

  cp "$INSTALLER" "$LOGICAL_DIR/ai-native-workflow"
  run env PATH="$TMPDIR2/stubs:/usr/bin:/bin" "$LOGICAL_DIR/ai-native-workflow" __print-script-dir
  rm -rf "$LOGICAL_DIR"
  [ "$status" -eq 0 ]
  # Must be the PHYSICAL path, not the logical /tmp/... one
  [ "$output" = "$PHYSICAL_DIR" ]
}
