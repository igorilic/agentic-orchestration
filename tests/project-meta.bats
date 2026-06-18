#!/usr/bin/env bats

# Project-hygiene + caveman-skill coverage (issues #14, caveman).

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-meta-XXXXXX)"
  STUB="$(mktemp -d /tmp/aw-meta-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/copilot"; chmod +x "$STUB/copilot"
}

teardown() {
  rm -rf "$SANDBOX" "$STUB"
}

# --- Developer-experience scaffolding (issue #14) ---

@test "ci: bats test workflow exists and runs the suite on a matrix" {
  [ -f "$REPO_ROOT/.github/workflows/test.yml" ]
  grep -q 'bats tests/' "$REPO_ROOT/.github/workflows/test.yml"
  grep -q 'macos-latest' "$REPO_ROOT/.github/workflows/test.yml"
}

@test "make: Makefile exposes test/lint/install targets" {
  [ -f "$REPO_ROOT/Makefile" ]
  grep -qE '^test:'    "$REPO_ROOT/Makefile"
  grep -qE '^lint:'    "$REPO_ROOT/Makefile"
  grep -qE '^install:' "$REPO_ROOT/Makefile"
}

@test "docs: CONTRIBUTING.md exists and documents the test command + path split" {
  [ -f "$REPO_ROOT/CONTRIBUTING.md" ]
  grep -q 'make test' "$REPO_ROOT/CONTRIBUTING.md"
  grep -q 'docs/context/' "$REPO_ROOT/CONTRIBUTING.md"
  grep -q '\.context/' "$REPO_ROOT/CONTRIBUTING.md"
}

# --- caveman skill ---

@test "caveman: source skill exists, slash-only, terse-mode framing" {
  [ -f "$REPO_ROOT/skills/caveman/SKILL.md" ]
  grep -q 'disable-model-invocation: true' "$REPO_ROOT/skills/caveman/SKILL.md"
  grep -qi 'caveman' "$REPO_ROOT/skills/caveman/SKILL.md"
}

@test "caveman: installs to both tracks (auto-copied by the skill loop)" {
  PATH="$STUB:$PATH" CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" \
    "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/claude/skills/caveman/SKILL.md" ]
  [ -f "$SANDBOX/copilot/skills/caveman/SKILL.md" ]
}

@test "status: lists the caveman skill" {
  PATH="$STUB:$PATH" CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" \
    "$INSTALLER" install global >/dev/null 2>&1
  run env CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" "$INSTALLER" status
  [[ "$output" == *"caveman"* ]]
}
