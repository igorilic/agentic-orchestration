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
#
# A-4 fix loop (F1 — polarity, not just presence): qa + reviewer both proved
# the section()-scoped assertions above pin keyword *presence* within the
# `## Delegating to the sidekick` section, not *polarity* — a fully
# polarity-inverted section (allowlist items relabeled "never delegate";
# forbidden items promoted to "may delegate"; the gate rewritten to "always
# accept, no vetting" while keeping a decoy "never accept" substring
# elsewhere) satisfies every one of the old flat `&&`-chains because all the
# required keywords are still present SOMEWHERE in the section — just under
# the wrong heading. Hardening:
#   - `subsection()`: a second-level awk slicer (mirrors section(), one
#     `### ` boundary down) so allowlist assertions can be scoped to
#     exactly the "What you may delegate" / "What you never delegate"
#     sub-list, and the gate assertion to exactly the "Parent-review gate"
#     sub-list — never a sibling sub-list within the same `## ` section.
#   - `assert_section_contains_all()`: the shared helper the 4 near-identical
#     `&&`-chains now funnel through (allowlist × 3 agents + the gate).
#   - The gate check is additionally anchored on the literal sentence
#     "Never accept unreviewed sidekick output." (verbatim in all 3 files)
#     instead of independent `vet` / `never accept` tokens an inverted
#     mutant can satisfy via an unrelated decoy sentence.
#   - `invert_delegation_mutant()`: builds a full polarity-inverted copy of
#     a real agent file (may/never sub-list bodies swapped, heading kept;
#     gate's governing sentence replaced with an inverted decoy that still
#     contains every token the OLD checks looked for) and a regression test
#     per agent asserts the hardened checks reject it.
#
# SDK-1 Step A-5: sentinel-emission contract (spec OQ-1, the frozen sentinel
# grammar). Each of the 3 MVP heavy agents' BODY must carry a `## Emitting
# milestone sentinels` section documenting the five event types (`phase`,
# `step`, `deleg`, `deleg_reject`, `done`) and the `run|ok|fail` step
# statuses, using the compositional/redacted-prefix convention the spec's
# OQ-1 decision requires: the literal `@@ANW|` token must never appear
# anywhere in the file (a printed literal would self-trigger a fake event
# when the orchestrator parses this agent's own stdout). Applies the A-4
# lessons proactively:
#   - Every assertion is scoped to the new section via the SAME
#     section()/gut_section() awk-slicer helpers A-4 already defined (no
#     re-definition), so content in another section (e.g. the Delegating
#     section's allowlist) can never satisfy a sentinel-grammar assertion.
#   - A gutted-section mutation guard (heading kept, content removed) per
#     agent, reusing gut_section() verbatim.
#   - A polarity-inversion mutation guard per agent: OQ-1's redaction rule
#     ("never print the literal prefix") is the may/never aspect here,
#     mirroring A-4 F1's review-gate anchor. The check is anchored on the
#     exact governing sentence (`SENTINEL_REDACTION_SENTENCE`), not
#     independent "never"/"literal"/"prefix" tokens, so a mutant that flips
#     the rule to "you may print it" while leaving the five event-type
#     keywords intact elsewhere in the section (which a presence-only check
#     would still accept) is correctly rejected.
#   - The OQ-1 collision rule itself — no literal `@@ANW|` substring
#     anywhere in the body — is asserted per agent, mirroring
#     tests/sidekick-agent.bats's "sidekick body: contains no literal
#     sentinel prefix" test verbatim (same `body()` scope, same `grep -qF`).
#   - reviewer.md / requirements-engineer.md are asserted to gain NO
#     sentinel-emission section, mirroring A-4's no-Delegating-section guard.

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

# Extract one `### <heading>` sub-section from a `## `-section's TEXT (as
# produced by section()): the heading line itself plus every line up to
# (not including) the next `### ` heading. Mirrors section()'s slicing
# logic one level down, so an assertion can be scoped to e.g. the "What you
# may delegate" sub-list without also matching "What you never delegate" or
# the Parent-review-gate clause living in the SAME `## ` section (the A-4 F1
# fix: presence-only assertions couldn't tell which sub-list a keyword was
# actually under).
subsection() {
  local text="$1" want="### $2"
  awk -v want="$want" '
    /^### / {
      if ($0 == want) { infield=1 } else { infield=0 }
      if (infield) print
      next
    }
    infield { print }
  ' <<<"$text"
}

# Assert every regex pattern in $2.. is found (grep -qiE, ANDed) within
# text $1. The shared home for the 4 near-identical `&&`-chains below
# (3 per-agent allowlists + the review-gate clause).
assert_section_contains_all() {
  local text="$1"
  shift
  local pattern
  for pattern in "$@"; do
    echo "$text" | grep -qiE "$pattern" || return 1
  done
  return 0
}

# Build a full mutant copy of $1 with its `## Delegating to the sidekick`
# section polarity-inverted, writing the result to $2. Reproduces the A-4 F1
# counter-example qa/reviewer found: the "What you may delegate" and "What
# you never delegate" sub-list BODY content is swapped (headings stay put,
# so every allowlist item ends up mislabeled under the wrong heading), and
# the gate's literal governing sentence ("Never accept unreviewed sidekick
# output.") is replaced with an inverted "always accept, no vetting" decoy
# that still contains every individual keyword the OLD flat checks looked
# for (vet, accept milestone, deleg_reject, redo, and a decoy "never
# accept" substring) — so the mutant fools presence-only checks while being
# semantically inverted.
invert_delegation_mutant() {
  local src="$1" dst="$2" sec may never may_file never_file
  sec="$(section "$src" "$DELEGATION_HEADING")"
  may="$(subsection "$sec" "What you may delegate")"
  never="$(subsection "$sec" "What you never delegate")"
  may_file="$(mktemp /tmp/aw-agent-delegation-may-XXXXXX)"
  never_file="$(mktemp /tmp/aw-agent-delegation-never-XXXXXX)"
  printf '%s\n' "$may" | tail -n +2 > "$may_file"
  printf '%s\n' "$never" | tail -n +2 > "$never_file"
  # Bodies are injected via getline-from-file (not an awk -v string) because
  # macOS's /usr/bin/awk (BWK awk, not gawk) rejects embedded newlines in a
  # -v value ("newline in string").
  awk -v may_hdr="### What you may delegate" \
      -v never_hdr="### What you never delegate" \
      -v never_file="$never_file" \
      -v may_file="$may_file" \
      -v gate_old="Never accept unreviewed sidekick output." \
      -v gate_new="Always accept unreviewed sidekick output without vetting — you never accept delays." '
    $0 == may_hdr {
      print
      while ((getline line < never_file) > 0) print line
      close(never_file)
      skip=1
      next
    }
    $0 == never_hdr {
      print
      while ((getline line < may_file) > 0) print line
      close(may_file)
      skip=1
      next
    }
    /^### / || /^## / { skip=0 }
    skip { next }
    index($0, gate_old) { sub(gate_old, gate_new); print; next }
    { print }
  ' "$src" > "$dst"
  rm -f "$may_file" "$never_file"
}

# --- Per-agent allowlist assertions (OQ-3: allowlist differs per agent) ----
# Each takes section() output (the agent's OWN Delegating section) and
# asserts every allowlist item from the spec's OQ-3 table is present WITHIN
# it, plus at least one item the agent explicitly keeps (never delegates).

# A-4 F1: each check is now scoped to its OWN `### ` sub-list via
# subsection() — the allowlist-keyword patterns run ONLY against "What you
# may delegate", and the forbidden-keyword patterns ONLY against "What you
# never delegate" — so an inverted mutant (keywords present but under the
# wrong heading) fails, where the old whole-section flat grep passed.

assert_tdd_developer_allowlist() {
  local sec="$1" may never
  may="$(subsection "$sec" "What you may delegate")"
  never="$(subsection "$sec" "What you never delegate")"
  assert_section_contains_all "$may" \
    'scaffold' 'boilerplate|template' 'lint|format|type-fix' 'fixture' \
    'mock' 'find-replace|find/replace|find and replace' &&
  assert_section_contains_all "$never" 'assertion' 'refactor'
}

assert_qa_allowlist() {
  local sec="$1" may never
  may="$(subsection "$sec" "What you may delegate")"
  never="$(subsection "$sec" "What you never delegate")"
  assert_section_contains_all "$may" \
    'probe' 'skeleton' 'boundary' 'test.data|test-data' &&
  assert_section_contains_all "$never" 'pass.fail|pass/fail' 'security'
}

assert_architect_allowlist() {
  local sec="$1" may never
  may="$(subsection "$sec" "What you may delegate")"
  never="$(subsection "$sec" "What you never delegate")"
  assert_section_contains_all "$may" \
    'scaffold' 'spec' 'todo' 'ADR' 'skeleton|template' \
    'status.checklist|status-checklist' &&
  assert_section_contains_all "$never" 'design' 'requirements'
}

# --- Parent-review-gate assertion (OQ-4, soft prompt-level contract) ------
# Same clause shape is required in all 3 agents' own sections: vet before
# accepting, emit an accept milestone on accept, emit deleg_reject + redo on
# reject, never accept unreviewed output.
#
# A-4 F1: scoped to the "Parent-review gate" sub-list (not the whole
# Delegating section) AND anchored on the literal governing sentence "Never
# accept unreviewed sidekick output." (verbatim in all 3 agent files)
# instead of independent `vet` / `never accept` tokens — a mutant that
# rewrites the gate to "always accept, no vetting" behind an unrelated
# decoy "never accept" substring elsewhere in the section no longer fools
# this check, because the exact governing sentence itself must be intact.

assert_review_gate_section() {
  local sec="$1" gate
  gate="$(subsection "$sec" "Parent-review gate (before accepting sidekick output)")"
  [ -n "$gate" ] || return 1
  assert_section_contains_all "$gate" \
    'Never accept unreviewed sidekick output\.' \
    'accept milestone' 'deleg_reject' 'redo'
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
# Step A-4 fix loop (F1): inversion-mutant regression guards. A gutted
# section (all content removed) is the A-2-style probe; a POLARITY-INVERTED
# section (all keywords still present, just relabeled/flipped) is the
# distinct F1 counter-example qa/reviewer found — presence-only checks are
# fooled by it. Each test below builds the full inverted mutant via
# invert_delegation_mutant() (real file, only the Delegating section
# touched) and asserts the hardened, subsection-scoped/anchored checks
# reject it for BOTH the allowlist and the review-gate clause.
# ---------------------------------------------------------------------------

@test "tdd-developer: hardened delegation checks reject a polarity-inverted Delegating section (may/never swapped, gate inverted)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/tdd-developer.md"
  invert_delegation_mutant "$TDD_DEVELOPER" "$mutant"
  sec="$(section "$mutant" "$DELEGATION_HEADING")"
  run assert_tdd_developer_allowlist "$sec"
  allowlist_status="$status"
  run assert_review_gate_section "$sec"
  gate_status="$status"
  rm -rf "$mutant_dir"
  [ "$allowlist_status" -ne 0 ]
  [ "$gate_status" -ne 0 ]
}

@test "qa: hardened delegation checks reject a polarity-inverted Delegating section (may/never swapped, gate inverted)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/qa.md"
  invert_delegation_mutant "$QA" "$mutant"
  sec="$(section "$mutant" "$DELEGATION_HEADING")"
  run assert_qa_allowlist "$sec"
  allowlist_status="$status"
  run assert_review_gate_section "$sec"
  gate_status="$status"
  rm -rf "$mutant_dir"
  [ "$allowlist_status" -ne 0 ]
  [ "$gate_status" -ne 0 ]
}

@test "architect: hardened delegation checks reject a polarity-inverted Delegating section (may/never swapped, gate inverted)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/architect.md"
  invert_delegation_mutant "$ARCHITECT" "$mutant"
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
# Step A-5: sentinel-emission contract (spec OQ-1, frozen sentinel grammar).
# Scoped via the SAME section()/gut_section() helpers A-4 defined above.
# ---------------------------------------------------------------------------

SENTINEL_HEADING="Emitting milestone sentinels"

# The exact governing sentence every agent's redaction clause must contain,
# verbatim (mirrors A-4's anchor on "Never accept unreviewed sidekick
# output."). Anchoring on the full sentence — not independent "never" /
# "literal" / "prefix" tokens — closes the same polarity-inversion bypass
# A-4's F1 fix closed for the review-gate clause: a mutant that flips the
# rule to "you may print the literal prefix" but leaves the individual
# grammar keywords (phase/step/deleg/deleg_reject/done/run/ok/fail) intact
# elsewhere in the section would still fool a presence-only check.
SENTINEL_REDACTION_SENTENCE="Never print the literal reserved prefix in this file or in narrated output."

# Assert the section documents all five event types and the three step
# statuses. Presence-only by design (mirrors assert_section_contains_all
# usage elsewhere in this file); the redaction-clause anchor below is what
# specifically guards the may/never polarity.
assert_sentinel_section() {
  local sec="$1"
  assert_section_contains_all "$sec" \
    '\bphase\b' '\bstep\b' '\bdeleg\b' '\bdeleg_reject\b' '\bdone\b' \
    '\brun\b' '\bok\b' '\bfail\b'
}

# Assert the section's redaction rule is the exact governing sentence
# (fixed-string match), not a "never"/"literal" keyword soup a
# polarity-inverted mutant could still satisfy.
assert_sentinel_redaction_clause() {
  local sec="$1"
  echo "$sec" | grep -qF "$SENTINEL_REDACTION_SENTENCE"
}

# Build a mutant copy of $1 with ONLY the governing redaction sentence
# flipped to its polarity-inverted opposite — grammar keywords elsewhere in
# the section are left untouched, so a presence-only check on the five
# event types would still pass on this mutant; only the anchored
# redaction-clause check must reject it.
invert_sentinel_mutant() {
  local src="$1" dst="$2"
  awk -v old="$SENTINEL_REDACTION_SENTENCE" \
      -v new="You may print the literal reserved prefix directly in this file or in narrated output whenever it helps illustrate the grammar." '
    index($0, old) { sub(old, new); print; next }
    { print }
  ' "$src" > "$dst"
}

# ---------------------------------------------------------------------------
# A-5 fix loop (F2 — field order, not just presence): qa + reviewer both
# proved assert_sentinel_section() pins keyword *presence* (phase, step,
# deleg_reject, agent, tier, status, text, reason all appear SOMEWHERE in the
# section) but never *order* — a mutant that reverses a described field
# order (`step` to "text, then status", or `phase` to "tier, then agent")
# still contains every one of those keywords, so it still satisfies the old
# presence-only `&&`-chain even though the grammar it describes is now
# backwards. Hardening mirrors A-4 F1's anchored-sentence technique (and
# this file's own SENTINEL_REDACTION_SENTENCE guard), applied to field order
# instead of may/never polarity: fixed-string anchors on the EXACT ordering
# phrase each event type's bullet uses.
# ---------------------------------------------------------------------------

# Collapse embedded newlines / runs of whitespace to single spaces. The
# deleg_reject order phrase straddles a markdown hard-wrap in the source
# ("...a free-text\n  reason."), so a single-line grep -F needs the text
# normalized first to match regardless of exactly where the source wraps.
normalize_ws() {
  tr '\n' ' ' <<<"$1" | tr -s ' '
}

# The three field-order anchor phrases (frozen wording, verbatim in all 3
# agent files): the exact clause each bullet uses to state which field comes
# first. A field-order-reversed mutant fails these order-sensitive
# fixed-string checks even though it still satisfies assert_sentinel_section
# ()'s bag-of-keywords check.
PHASE_ORDER_PHRASE="your agent name, then your model tier"
STEP_ORDER_PHRASE="a status, then free text"
DELEG_REJECT_ORDER_PHRASE="the sidekick's tier, then a free-text reason"

# Assert the section's three field-order anchor phrases are present
# verbatim (fixed-string, order-sensitive) — mirrors
# assert_sentinel_redaction_clause()'s fixed-string technique, applied to
# field order instead of the may/never redaction rule.
assert_sentinel_field_order() {
  local sec="$1" flat
  flat="$(normalize_ws "$sec")"
  grep -qF "$PHASE_ORDER_PHRASE" <<<"$flat" &&
  grep -qF "$STEP_ORDER_PHRASE" <<<"$flat" &&
  grep -qF "$DELEG_REJECT_ORDER_PHRASE" <<<"$flat"
}

# Build a mutant copy of $1 with the three field-order phrases REVERSED,
# writing the result to $2. Heading, event-type keywords, and everything
# else are left untouched, so every keyword assert_sentinel_section() checks
# for (phase/step/deleg_reject/run/ok/fail/done/deleg) is still present
# SOMEWHERE in the section — only the order of the two named fields per
# bullet is flipped. The deleg_reject order phrase is matched/rewritten as
# two whole physical lines (not one -v string) because it straddles a
# markdown hard-wrap and macOS's BWK awk rejects embedded newlines in a -v
# value (same constraint invert_delegation_mutant() documents above).
invert_field_order_mutant() {
  local src="$1" dst="$2"
  awk -v phase_old="your agent name, then your model tier" \
      -v phase_new="your model tier, then your agent name" \
      -v step_old="a status, then free text" \
      -v step_new="free text, then a status" \
      -v deleg1_old="two fields: the sidekick's tier, then a free-text" \
      -v deleg1_new="two fields: a free-text reason, then the sidekick's tier." \
      -v deleg2_old="reason. Emit instead of an accept milestone when you reject sidekick" \
      -v deleg2_new="Emit instead of an accept milestone when you reject sidekick" '
    index($0, phase_old)  { sub(phase_old, phase_new); print; next }
    index($0, step_old)   { sub(step_old, step_new); print; next }
    index($0, deleg1_old) { sub(deleg1_old, deleg1_new); print; next }
    index($0, deleg2_old) { sub(deleg2_old, deleg2_new); print; next }
    { print }
  ' "$src" > "$dst"
}

# --- Sentinel grammar section exists + documents the frozen grammar -------

@test "tdd-developer body: Emitting milestone sentinels section documents the frozen grammar (scoped)" {
  sec="$(section "$TDD_DEVELOPER" "$SENTINEL_HEADING")"
  [ -n "$sec" ]
  assert_sentinel_section "$sec"
  assert_sentinel_redaction_clause "$sec"
  assert_sentinel_field_order "$sec"
}

@test "qa body: Emitting milestone sentinels section documents the frozen grammar (scoped)" {
  sec="$(section "$QA" "$SENTINEL_HEADING")"
  [ -n "$sec" ]
  assert_sentinel_section "$sec"
  assert_sentinel_redaction_clause "$sec"
  assert_sentinel_field_order "$sec"
}

@test "architect body: Emitting milestone sentinels section documents the frozen grammar (scoped)" {
  sec="$(section "$ARCHITECT" "$SENTINEL_HEADING")"
  [ -n "$sec" ]
  assert_sentinel_section "$sec"
  assert_sentinel_redaction_clause "$sec"
  assert_sentinel_field_order "$sec"
}

# --- No sentinel-emission section outside the 3 MVP heavy agents ----------

@test "reviewer body: no Emitting milestone sentinels section (sentinel emission not granted)" {
  sec="$(section "$REVIEWER" "$SENTINEL_HEADING")"
  [ -z "$sec" ]
}

@test "requirements-engineer body: no Emitting milestone sentinels section (sentinel emission not granted)" {
  sec="$(section "$REQUIREMENTS_ENGINEER" "$SENTINEL_HEADING")"
  [ -z "$sec" ]
}

# ---------------------------------------------------------------------------
# Collision rule (OQ-1): no literal sentinel prefix anywhere in the body of
# any of the 3 agent files. Mirrors tests/sidekick-agent.bats's "sidekick
# body: contains no literal sentinel prefix" test verbatim (same body()
# scope, same grep -qF).
# ---------------------------------------------------------------------------

@test "tdd-developer body: contains no literal sentinel prefix (OQ-1 redaction rule)" {
  bd="$(body "$TDD_DEVELOPER")"
  ! echo "$bd" | grep -qF '@@ANW|'
}

@test "qa body: contains no literal sentinel prefix (OQ-1 redaction rule)" {
  bd="$(body "$QA")"
  ! echo "$bd" | grep -qF '@@ANW|'
}

@test "architect body: contains no literal sentinel prefix (OQ-1 redaction rule)" {
  bd="$(body "$ARCHITECT")"
  ! echo "$bd" | grep -qF '@@ANW|'
}

# ---------------------------------------------------------------------------
# Mutation guards: gutted section (heading kept, content removed). Reuses
# gut_section() verbatim from the A-4 helpers above.
# ---------------------------------------------------------------------------

@test "tdd-developer: hardened sentinel-grammar check rejects a gutted Emitting milestone sentinels section" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/tdd-developer.md"
  gut_section "$TDD_DEVELOPER" "$SENTINEL_HEADING" > "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "qa: hardened sentinel-grammar check rejects a gutted Emitting milestone sentinels section" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/qa.md"
  gut_section "$QA" "$SENTINEL_HEADING" > "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "architect: hardened sentinel-grammar check rejects a gutted Emitting milestone sentinels section" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/architect.md"
  gut_section "$ARCHITECT" "$SENTINEL_HEADING" > "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Mutation guards: polarity-inverted redaction clause. Grammar keywords
# elsewhere in the section are left untouched by invert_sentinel_mutant(),
# so only the anchored redaction-clause check may catch it (the A-4 F1
# lesson applied to OQ-1's may/never rule) — the grammar_status assertion
# below proves a presence-only check would have been fooled.
# ---------------------------------------------------------------------------

@test "tdd-developer: hardened redaction-clause check rejects a polarity-inverted governing sentence" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/tdd-developer.md"
  invert_sentinel_mutant "$TDD_DEVELOPER" "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_redaction_clause "$sec"
  redaction_status="$status"
  run assert_sentinel_section "$sec"
  grammar_status="$status"
  rm -rf "$mutant_dir"
  [ "$redaction_status" -ne 0 ]
  [ "$grammar_status" -eq 0 ]
}

@test "qa: hardened redaction-clause check rejects a polarity-inverted governing sentence" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/qa.md"
  invert_sentinel_mutant "$QA" "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_redaction_clause "$sec"
  redaction_status="$status"
  run assert_sentinel_section "$sec"
  grammar_status="$status"
  rm -rf "$mutant_dir"
  [ "$redaction_status" -ne 0 ]
  [ "$grammar_status" -eq 0 ]
}

@test "architect: hardened redaction-clause check rejects a polarity-inverted governing sentence" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/architect.md"
  invert_sentinel_mutant "$ARCHITECT" "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_redaction_clause "$sec"
  redaction_status="$status"
  run assert_sentinel_section "$sec"
  grammar_status="$status"
  rm -rf "$mutant_dir"
  [ "$redaction_status" -ne 0 ]
  [ "$grammar_status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# A-5 fix loop (F2): field-order-reversed mutation guards. Grammar keywords
# elsewhere in the section are left untouched by invert_field_order_mutant(),
# so the OLD presence-only assert_sentinel_section() still passes on this
# mutant (proven by grammar_status below) — only the new order-anchored
# assert_sentinel_field_order() may catch it.
# ---------------------------------------------------------------------------

@test "tdd-developer: hardened field-order check rejects a field-order-reversed mutant (old presence-only check still passes on it)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/tdd-developer.md"
  invert_field_order_mutant "$TDD_DEVELOPER" "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_field_order "$sec"
  order_status="$status"
  run assert_sentinel_section "$sec"
  grammar_status="$status"
  rm -rf "$mutant_dir"
  [ "$order_status" -ne 0 ]
  [ "$grammar_status" -eq 0 ]
}

@test "qa: hardened field-order check rejects a field-order-reversed mutant (old presence-only check still passes on it)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/qa.md"
  invert_field_order_mutant "$QA" "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_field_order "$sec"
  order_status="$status"
  run assert_sentinel_section "$sec"
  grammar_status="$status"
  rm -rf "$mutant_dir"
  [ "$order_status" -ne 0 ]
  [ "$grammar_status" -eq 0 ]
}

@test "architect: hardened field-order check rejects a field-order-reversed mutant (old presence-only check still passes on it)" {
  mutant_dir="$(mktemp -d /tmp/aw-agent-delegation-mutant-XXXXXX)"
  mutant="$mutant_dir/architect.md"
  invert_field_order_mutant "$ARCHITECT" "$mutant"
  sec="$(section "$mutant" "$SENTINEL_HEADING")"
  run assert_sentinel_field_order "$sec"
  order_status="$status"
  run assert_sentinel_section "$sec"
  grammar_status="$status"
  rm -rf "$mutant_dir"
  [ "$order_status" -ne 0 ]
  [ "$grammar_status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# No install-side-effects: this file is source-file-only (no `install
# global`), so it must never touch the real ~/.copilot.
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
