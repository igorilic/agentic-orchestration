#!/usr/bin/env bats

# The gh-cli / glab-cli review skills: they exist, and they document the
# verified posting mechanics (GitHub's bundled reviews endpoint, GitLab's
# position object).

REPO_ROOT="$BATS_TEST_DIRNAME/.."
GH_SKILL="$REPO_ROOT/skills/gh-cli/SKILL.md"
GLAB_SKILL="$REPO_ROOT/skills/glab-cli/SKILL.md"

# ---------------------------------------------------------------------------
# Source artifacts exist
# ---------------------------------------------------------------------------

@test "source: gh-cli and glab-cli skills exist" {
  [ -f "$GH_SKILL" ]
  [ -f "$GLAB_SKILL" ]
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
