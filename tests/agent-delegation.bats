#!/usr/bin/env bats

# SDK-1 Step A-3: `Task` tool grant scoped to the 3 MVP heavy agents (AC-10).
#
# Verifies:
#   - agents/claude-code/{tdd-developer,qa,architect}.md each have `Task`
#     present in their `tools:` frontmatter line;
#   - agents/claude-code/{reviewer,requirements-engineer}.md do NOT — the
#     Task-tool grant (delegation to the sidekick) is scoped to exactly the
#     3 MVP heavy agents per AC-10, not granted repo-wide.
#
# Test-hardening (mirrors tests/sidekick-agent.bats's frontmatter() pattern,
# closing the foolable-grep class qa flagged on A-1/A-2): assertions are
# scoped to the YAML frontmatter block (between the first two `---`
# delimiters) via the same frontmatter() awk helper, so a `Task` word
# appearing in an agent's prompt BODY (e.g. narrating "the Task tool") can
# never satisfy a frontmatter-only assertion, and a file-wide grep can never
# produce a false negative either.

AGENTS_DIR="$BATS_TEST_DIRNAME/../agents/claude-code"

TDD_DEVELOPER="$AGENTS_DIR/tdd-developer.md"
QA="$AGENTS_DIR/qa.md"
ARCHITECT="$AGENTS_DIR/architect.md"
REVIEWER="$AGENTS_DIR/reviewer.md"
REQUIREMENTS_ENGINEER="$AGENTS_DIR/requirements-engineer.md"

# Extract just the YAML frontmatter block (the lines strictly between the
# first two `---` delimiters), so BODY content can never satisfy a
# frontmatter-only assertion. Copied verbatim from tests/sidekick-agent.bats.
frontmatter() {
  awk '
    /^---$/ { c++; next }
    c==1
  ' "$1"
}

# Assert the frontmatter `tools:` line of $1 contains `Task` as a
# comma-separated tool name (not a substring match).
assert_has_task_tool() {
  local file="$1" fm tools_line
  fm="$(frontmatter "$file")"
  tools_line="$(grep -E '^tools:' <<<"$fm")"
  [ -n "$tools_line" ]
  printf '%s' "${tools_line#tools: }" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qxF 'Task'
}

# Assert the frontmatter `tools:` line of $1 does NOT contain `Task`.
assert_no_task_tool() {
  local file="$1" fm tools_line
  fm="$(frontmatter "$file")"
  tools_line="$(grep -E '^tools:' <<<"$fm")"
  [ -n "$tools_line" ]
  ! (printf '%s' "${tools_line#tools: }" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qxF 'Task')
}

# ---------------------------------------------------------------------------
# Task tool granted to the 3 MVP heavy agents (AC-10)
# ---------------------------------------------------------------------------

@test "tdd-developer frontmatter grants Task tool (scoped)" {
  assert_has_task_tool "$TDD_DEVELOPER"
}

@test "qa frontmatter grants Task tool (scoped)" {
  assert_has_task_tool "$QA"
}

@test "architect frontmatter grants Task tool (scoped)" {
  assert_has_task_tool "$ARCHITECT"
}

# ---------------------------------------------------------------------------
# Task tool NOT granted outside the 3 MVP heavy agents
# ---------------------------------------------------------------------------

@test "reviewer frontmatter does not grant Task tool (scoped)" {
  assert_no_task_tool "$REVIEWER"
}

@test "requirements-engineer frontmatter does not grant Task tool (scoped)" {
  assert_no_task_tool "$REQUIREMENTS_ENGINEER"
}

# ---------------------------------------------------------------------------
# Regression guard: a decoy "Task" word in the BODY must not satisfy the
# frontmatter-scoped assertion (the foolable-grep class qa flagged on A-1/A-2).
# ---------------------------------------------------------------------------

@test "hardened Task check ignores a decoy Task mention in the BODY (frontmatter-scoped)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/decoy.md"
  cat > "$mutant" <<'EOF'
---
name: decoy
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
---

You may dispatch work using the Task tool when delegating.
EOF
  run assert_has_task_tool "$mutant"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}
