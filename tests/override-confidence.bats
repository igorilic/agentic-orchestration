#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR"
  git init -q
  mkdir -p .git/aw
  echo "PROJ-1" > .git/aw/active-spec
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

# Simulate the skill body. The skill itself is markdown that Claude executes,
# so we factor the bash logic into a sourceable function for testing.
source_skill() {
  source "$BATS_TEST_DIRNAME/../skills/override-confidence/skill.bash"
}

@test "override-confidence: writes marker with reason" {
  source_skill
  override_confidence "Reviewer flagged perf issue tracked in PERF-42; not blocking"
  [ -f ".git/aw/override-PROJ-1" ]
  run jq -r '.reason' ".git/aw/override-PROJ-1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PERF-42"* ]]
}

@test "override-confidence: rejects empty reason" {
  source_skill
  run override_confidence ""
  [ "$status" -ne 0 ]
  [ ! -f ".git/aw/override-PROJ-1" ]
}

@test "override-confidence: rejects boilerplate reason" {
  source_skill
  run override_confidence "fix"
  [ "$status" -ne 0 ]
  run override_confidence "."
  [ "$status" -ne 0 ]
  run override_confidence "override"
  [ "$status" -ne 0 ]
}

@test "override-confidence: refuses if no active-spec" {
  source_skill
  rm .git/aw/active-spec
  run override_confidence "valid reason text here"
  [ "$status" -ne 0 ]
}
