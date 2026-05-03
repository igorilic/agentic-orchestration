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
# Force PATH to only stock system dirs so neither GNU tool is available.
@test "script-dir: pure-bash fallback works without realpath/greadlink on PATH" {
  ln -s "$INSTALLER" "$TMPDIR1/ai-native-workflow"
  run env PATH=/usr/bin:/bin "$TMPDIR1/ai-native-workflow" __print-script-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL_SCRIPT_DIR" ]
}
