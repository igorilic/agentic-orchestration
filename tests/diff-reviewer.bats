#!/usr/bin/env bats

# Verification for the diff-reviewer agent (whole-PR/MR review) and the
# gh-cli / glab-cli review skills it drives. Covers: source files exist,
# the content invariants the agent promises (severity ranking, preview→
# confirm gate, inline + thread placement, verdict, required review
# dimensions), and that both the Claude Code and Copilot CLI installs ship
# the new artifacts.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

CLAUDE_AGENT="$REPO_ROOT/agents/claude-code/diff-reviewer.md"
COPILOT_AGENT="$REPO_ROOT/agents/copilot-cli/diff-reviewer.agent.md"
GH_SKILL="$REPO_ROOT/skills/gh-cli/SKILL.md"
GLAB_SKILL="$REPO_ROOT/skills/glab-cli/SKILL.md"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-dr-XXXXXX)"
  STUB_BIN="$(mktemp -d /tmp/aw-dr-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/copilot"
  chmod +x "$STUB_BIN/copilot"
}

teardown() {
  rm -rf "$SANDBOX" "$STUB_BIN"
}

# Run a Claude-only global install into the sandbox. COPILOT_HOME is pointed
# at a sandbox subdir so a copilot binary on the real PATH can never pollute
# the user's ~/.copilot during tests.
claude_install() {
  CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" \
    "$INSTALLER" install global "$@"
}

# ---------------------------------------------------------------------------
# Source artifacts exist
# ---------------------------------------------------------------------------

@test "source: diff-reviewer agent exists for both tracks" {
  [ -f "$CLAUDE_AGENT" ]
  [ -f "$COPILOT_AGENT" ]
}

@test "source: gh-cli and glab-cli skills exist" {
  [ -f "$GH_SKILL" ]
  [ -f "$GLAB_SKILL" ]
}

# ---------------------------------------------------------------------------
# Agent content invariants (same checks across both tracks)
# ---------------------------------------------------------------------------

@test "agent: ranks findings by severity (CRITICAL/MAJOR/MINOR/NIT)" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    for sev in CRITICAL MAJOR MINOR NIT; do
      grep -q "$sev" "$f" || { echo "severity '$sev' missing in $f"; return 1; }
    done
  done
}

@test "agent: enforces a preview-then-confirm gate before posting" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -qi 'preview' "$f"            || { echo "no preview step in $f"; return 1; }
    grep -qi 'never post before' "$f"  || { echo "no never-post-before-confirm rule in $f"; return 1; }
  done
}

@test "agent: places findings inline OR as conceptual threads" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -qi 'inline' "$f"  || { echo "no inline placement in $f"; return 1; }
    grep -qi 'thread' "$f"  || { echo "no thread placement in $f"; return 1; }
  done
}

@test "agent: produces a verdict" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -qi 'verdict' "$f"          || { echo "no verdict in $f"; return 1; }
    grep -q 'REQUEST CHANGES' "$f"   || { echo "no REQUEST CHANGES verdict in $f"; return 1; }
  done
}

@test "agent: covers the required review dimensions" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -qi 'correctness'   "$f" || { echo "missing correctness in $f"; return 1; }
    grep -qi 'security'      "$f" || { echo "missing security in $f"; return 1; }
    grep -qi 'conventions'   "$f" || { echo "missing conventions in $f"; return 1; }
    grep -qi 'landmines'     "$f" || { echo "missing landmines in $f"; return 1; }
    grep -qi 'best practices' "$f" || { echo "missing best practices in $f"; return 1; }
  done
}

@test "agent: drives the gh-cli and glab-cli skills" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -q 'gh-cli' "$f"   || { echo "no gh-cli reference in $f"; return 1; }
    grep -q 'glab-cli' "$f" || { echo "no glab-cli reference in $f"; return 1; }
  done
}

@test "agent: reads acceptance criteria from the linked issue/ticket" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -qi 'acceptance criteria' "$f" || { echo "no AC reference in $f"; return 1; }
  done
}

@test "agent: never modifies code (review/comment only)" {
  for f in "$CLAUDE_AGENT" "$COPILOT_AGENT"; do
    grep -qi 'never modify code' "$f" || { echo "no never-modify-code rule in $f"; return 1; }
  done
}

@test "agent: does not reference tracked spec artifacts under .anw/specs/" {
  # Matches the repo-wide path convention enforced for the other agents.
  ! grep -Eq '\.anw/specs/[^$]*-(spec|todo|requirements|bugfix|brainstorm|testplan)' \
    "$CLAUDE_AGENT" "$COPILOT_AGENT"
}

# ---------------------------------------------------------------------------
# Skill content invariants — the verified posting mechanics must be present
# ---------------------------------------------------------------------------

@test "gh-cli skill: documents the bundled reviews endpoint + line/side" {
  grep -q 'pulls/' "$GH_SKILL"
  grep -q 'reviews' "$GH_SKILL"
  grep -q 'REQUEST_CHANGES' "$GH_SKILL"
  grep -q 'side' "$GH_SKILL"
  # self-PR fallback must be documented
  grep -qi 'self-pr\|own PR\|own pull request' "$GH_SKILL"
}

@test "glab-cli skill: documents the position object + --form requirement" {
  grep -q 'discussions' "$GLAB_SKILL"
  grep -q 'position\[' "$GLAB_SKILL"
  grep -q -- '--form' "$GLAB_SKILL"
  grep -q 'base_sha' "$GLAB_SKILL"
  # the added/deleted/context line rule must be spelled out
  grep -qi 'new_line' "$GLAB_SKILL"
  grep -qi 'old_line' "$GLAB_SKILL"
}

# ---------------------------------------------------------------------------
# Claude Code install
# ---------------------------------------------------------------------------

@test "install global (claude): ships diff-reviewer agent + gh-cli/glab-cli skills" {
  claude_install >/dev/null 2>&1
  [ -f "$SANDBOX/claude/agents/diff-reviewer.md" ]
  [ -f "$SANDBOX/claude/skills/gh-cli/SKILL.md" ]
  [ -f "$SANDBOX/claude/skills/glab-cli/SKILL.md" ]
}

@test "install global (claude): installed agent matches the source (no drift)" {
  claude_install >/dev/null 2>&1
  diff -q "$CLAUDE_AGENT" "$SANDBOX/claude/agents/diff-reviewer.md"
  diff -q "$GH_SKILL"   "$SANDBOX/claude/skills/gh-cli/SKILL.md"
  diff -q "$GLAB_SKILL" "$SANDBOX/claude/skills/glab-cli/SKILL.md"
}

@test "status (claude): surfaces diff-reviewer agent and review skills" {
  claude_install >/dev/null 2>&1
  # `run` tolerates status's exit code (a pre-existing set -u edge in
  # detect_stacks can make `status` exit non-zero on bash 3.2); we only
  # assert the new artifacts are listed.
  run env CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" "$INSTALLER" status
  [[ "$output" == *"diff-reviewer"* ]]
  [[ "$output" == *"gh-cli"* ]]
  [[ "$output" == *"glab-cli"* ]]
}

# ---------------------------------------------------------------------------
# Copilot CLI install (copilot stubbed onto PATH)
# ---------------------------------------------------------------------------

@test "install global (copilot): ships diff-reviewer agent + review skills" {
  PATH="$STUB_BIN:$PATH" CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" \
    "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/copilot/agents/diff-reviewer.agent.md" ]
  [ -f "$SANDBOX/copilot/skills/gh-cli/SKILL.md" ]
  [ -f "$SANDBOX/copilot/skills/glab-cli/SKILL.md" ]
}

@test "install global: the diff-reviewer's ticket dependency ships on both tracks" {
  # The agent declares skills: [gh-cli, glab-cli, ticket]; gh-cli/glab-cli are
  # covered above — assert the ticket (Jira AC) skill installs too.
  PATH="$STUB_BIN:$PATH" CLAUDE_HOME="$SANDBOX/claude" COPILOT_HOME="$SANDBOX/copilot" \
    "$INSTALLER" install global >/dev/null 2>&1
  [ -f "$SANDBOX/claude/skills/ticket/SKILL.md" ]
  [ -f "$SANDBOX/copilot/skills/ticket/SKILL.md" ]
}
