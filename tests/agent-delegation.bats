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
#
# SDK-1 Step A-4: per-agent delegation allowlist + parent-review-gate
# contract (spec OQ-3 / OQ-4). Each of the 3 MVP heavy agents' BODY must
# carry a `## Delegating to the sidekick` section containing (1) that
# agent's OWN mechanical allowlist (OQ-3 differs per agent — tdd-developer's
# allowlist is not qa's) and (2) the parent-review-gate clause (OQ-4, soft
# contract): vet the sidekick's output before accepting; on accept, emit an
# accept milestone; on reject, emit `deleg_reject` and redo the work itself;
# never accept unreviewed sidekick output.
#
# Applying the A-2 lesson proactively (qa burned this file-wide-grep class
# twice already): every assertion below is scoped to the delegation
# section, not the whole body, via the SAME body()/section()/gut_section()
# awk-slicer pattern from tests/sidekick-agent.bats (copied verbatim), and
# each is backed by a mutation-guard test that guts the section (heading
# kept, content removed) and asserts the scoped check rejects it.
# reviewer.md and requirements-engineer.md are asserted to gain NO
# delegation section — delegation stays scoped to the 3 MVP agents.

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
# A-4 helpers: body()/section()/gut_section() copied verbatim from
# tests/sidekick-agent.bats so delegation-contract assertions can be scoped
# to exactly the `## Delegating to the sidekick` section (never the whole
# body, never another section) — closing the A-1/A-2 foolable-grep class.
# ---------------------------------------------------------------------------

DELEGATION_HEADING="Delegating to the sidekick"

# Extract the prompt BODY (everything strictly after the second `---`
# delimiter), so frontmatter content can never satisfy a body-only
# assertion (and vice versa). Copied verbatim from tests/sidekick-agent.bats.
body() {
  awk '
    /^---$/ { c++; next }
    c>=2
  ' "$1"
}

# Extract one `## <heading>` section from the BODY: the heading line itself
# plus every line up to (not including) the next `## ` heading. Copied
# verbatim from tests/sidekick-agent.bats.
section() {
  local file="$1" want="## $2"
  awk -v want="$want" '
    /^---$/ { c++; next }
    c<2 { next }
    /^## / {
      if ($0 == want) { infield=1 } else { infield=0 }
      if (infield) print
      next
    }
    infield { print }
  ' "$file"
}

# Build a mutant copy of $1 with the named section's content blanked (its
# `## <heading>` line kept, every line under it up to the next `## `
# heading removed). Copied verbatim from tests/sidekick-agent.bats.
gut_section() {
  local src="$1" want="## $2"
  awk -v want="$want" '
    $0 == want { print; skip=1; next }
    /^## / { skip=0 }
    skip { next }
    { print }
  ' "$src"
}

# --- Per-agent allowlist assertions (OQ-3: allowlist differs per agent) ----
# Each takes section() output (the agent's OWN Delegating section) and
# asserts every allowlist item from the spec's OQ-3 table is present WITHIN
# it, plus at least one item the agent explicitly keeps (never delegates).

assert_tdd_developer_allowlist() {
  local sec="$1"
  echo "$sec" | grep -qiE 'scaffold' &&
  echo "$sec" | grep -qiE 'boilerplate|template' &&
  echo "$sec" | grep -qiE 'lint|format|type-fix' &&
  echo "$sec" | grep -qiE 'fixture' &&
  echo "$sec" | grep -qiE 'mock' &&
  echo "$sec" | grep -qiE 'find-replace|find/replace|find and replace' &&
  echo "$sec" | grep -qiE 'assertion' &&
  echo "$sec" | grep -qiE 'refactor'
}

assert_qa_allowlist() {
  local sec="$1"
  echo "$sec" | grep -qiE 'probe' &&
  echo "$sec" | grep -qiE 'skeleton' &&
  echo "$sec" | grep -qiE 'boundary' &&
  echo "$sec" | grep -qiE 'test.data|test-data' &&
  echo "$sec" | grep -qiE 'pass.fail|pass/fail' &&
  echo "$sec" | grep -qiE 'security'
}

assert_architect_allowlist() {
  local sec="$1"
  echo "$sec" | grep -qiE 'scaffold' &&
  echo "$sec" | grep -qiE 'spec' &&
  echo "$sec" | grep -qiE 'todo' &&
  echo "$sec" | grep -qiE 'ADR' &&
  echo "$sec" | grep -qiE 'skeleton|template' &&
  echo "$sec" | grep -qiE 'status.checklist|status-checklist' &&
  echo "$sec" | grep -qiE 'design' &&
  echo "$sec" | grep -qiE 'requirements'
}

# --- Parent-review-gate assertion (OQ-4, soft prompt-level contract) ------
# Same clause shape is required in all 3 agents' own sections: vet before
# accepting, emit an accept milestone on accept, emit deleg_reject + redo on
# reject, never accept unreviewed output.

assert_review_gate_section() {
  local sec="$1"
  echo "$sec" | grep -qiE 'vet' &&
  echo "$sec" | grep -qiE 'before accepting' &&
  echo "$sec" | grep -qiE 'accept milestone' &&
  echo "$sec" | grep -qiE 'deleg_reject' &&
  echo "$sec" | grep -qiE 'redo' &&
  echo "$sec" | grep -qiE 'never accept'
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

# ---------------------------------------------------------------------------
# Step A-4: per-agent delegation allowlist (scoped to each agent's OWN
# `## Delegating to the sidekick` section)
# ---------------------------------------------------------------------------

@test "tdd-developer body: Delegating section exists and carries its own OQ-3 allowlist (scoped)" {
  sec="$(section "$TDD_DEVELOPER" "$DELEGATION_HEADING")"
  [ -n "$sec" ]
  assert_tdd_developer_allowlist "$sec"
}

@test "qa body: Delegating section exists and carries its own OQ-3 allowlist (scoped)" {
  sec="$(section "$QA" "$DELEGATION_HEADING")"
  [ -n "$sec" ]
  assert_qa_allowlist "$sec"
}

@test "architect body: Delegating section exists and carries its own OQ-3 allowlist (scoped)" {
  sec="$(section "$ARCHITECT" "$DELEGATION_HEADING")"
  [ -n "$sec" ]
  assert_architect_allowlist "$sec"
}

# ---------------------------------------------------------------------------
# Step A-4: parent-review-gate clause (OQ-4, soft contract) within each
# agent's OWN Delegating section
# ---------------------------------------------------------------------------

@test "tdd-developer body: Delegating section carries the parent-review-gate clause (scoped)" {
  sec="$(section "$TDD_DEVELOPER" "$DELEGATION_HEADING")"
  [ -n "$sec" ]
  assert_review_gate_section "$sec"
}

@test "qa body: Delegating section carries the parent-review-gate clause (scoped)" {
  sec="$(section "$QA" "$DELEGATION_HEADING")"
  [ -n "$sec" ]
  assert_review_gate_section "$sec"
}

@test "architect body: Delegating section carries the parent-review-gate clause (scoped)" {
  sec="$(section "$ARCHITECT" "$DELEGATION_HEADING")"
  [ -n "$sec" ]
  assert_review_gate_section "$sec"
}

# ---------------------------------------------------------------------------
# Step A-4: delegation section scoped to exactly the 3 MVP heavy agents —
# reviewer and requirements-engineer must NOT gain one (mirrors the
# Task-tool scoping tests above).
# ---------------------------------------------------------------------------

@test "reviewer body: no Delegating to the sidekick section (delegation not granted)" {
  sec="$(section "$REVIEWER" "$DELEGATION_HEADING")"
  [ -z "$sec" ]
}

@test "requirements-engineer body: no Delegating to the sidekick section (delegation not granted)" {
  sec="$(section "$REQUIREMENTS_ENGINEER" "$DELEGATION_HEADING")"
  [ -z "$sec" ]
}

# ---------------------------------------------------------------------------
# Step A-4 / OQ-1: no literal sentinel prefix in the delegation section —
# the frozen grammar itself is Step A-5's job, A-4 only names the milestone
# concepts (accept milestone, deleg_reject).
# ---------------------------------------------------------------------------

@test "tdd-developer body: Delegating section has no literal sentinel prefix (OQ-1)" {
  sec="$(section "$TDD_DEVELOPER" "$DELEGATION_HEADING")"
  ! echo "$sec" | grep -qF '@@ANW|'
}

@test "qa body: Delegating section has no literal sentinel prefix (OQ-1)" {
  sec="$(section "$QA" "$DELEGATION_HEADING")"
  ! echo "$sec" | grep -qF '@@ANW|'
}

@test "architect body: Delegating section has no literal sentinel prefix (OQ-1)" {
  sec="$(section "$ARCHITECT" "$DELEGATION_HEADING")"
  ! echo "$sec" | grep -qF '@@ANW|'
}

# ---------------------------------------------------------------------------
# Step A-4 mutation guards: reproduce the A-2 fix-loop probe (gut a named
# section's content, heading kept) against a full copy of each REAL agent
# file, so the rest of the file (e.g. the No-Bash/forbidden-actions prose
# elsewhere) stays intact and would fool an unscoped, file-wide grep. The
# section()-scoped assert_*() helpers — the SAME helpers the real tests
# above use — must reject the gutted mutant for BOTH the allowlist and the
# review-gate clause.
# ---------------------------------------------------------------------------

@test "tdd-developer: hardened delegation checks reject a gutted Delegating section (heading kept, content removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/tdd-developer.md"
  gut_section "$TDD_DEVELOPER" "$DELEGATION_HEADING" > "$mutant"
  sec="$(section "$mutant" "$DELEGATION_HEADING")"
  run assert_tdd_developer_allowlist "$sec"
  allowlist_status="$status"
  run assert_review_gate_section "$sec"
  gate_status="$status"
  rm -rf "$mutant_dir"
  [ "$allowlist_status" -ne 0 ]
  [ "$gate_status" -ne 0 ]
}

@test "qa: hardened delegation checks reject a gutted Delegating section (heading kept, content removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/qa.md"
  gut_section "$QA" "$DELEGATION_HEADING" > "$mutant"
  sec="$(section "$mutant" "$DELEGATION_HEADING")"
  run assert_qa_allowlist "$sec"
  allowlist_status="$status"
  run assert_review_gate_section "$sec"
  gate_status="$status"
  rm -rf "$mutant_dir"
  [ "$allowlist_status" -ne 0 ]
  [ "$gate_status" -ne 0 ]
}

@test "architect: hardened delegation checks reject a gutted Delegating section (heading kept, content removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/architect.md"
  gut_section "$ARCHITECT" "$DELEGATION_HEADING" > "$mutant"
  sec="$(section "$mutant" "$DELEGATION_HEADING")"
  run assert_architect_allowlist "$sec"
  allowlist_status="$status"
  run assert_review_gate_section "$sec"
  gate_status="$status"
  rm -rf "$mutant_dir"
  [ "$allowlist_status" -ne 0 ]
  [ "$gate_status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# No install-side-effects: this file is source-file-only (no `install
# global`), so it must never touch the real ~/.copilot.
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
