#!/usr/bin/env bats

# Guards the model-strategy decision (issue #17 part 3): the repo selects model
# *tiers* via floating aliases, never a specific model version. So no pinned
# "<Model> <major>.<minor>" version strings in tracked docs/config, and the
# Claude agent frontmatter uses the floating tier aliases opus/sonnet/haiku.
#
# NOTE: this file must not itself contain a literal pinned-version string, or
# the first test would match its own source. Keep examples abstract.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

@test "model-strategy: no pinned model-version prose anywhere (use <Tier>-tier instead)" {
  # Capitalised "<Model> <major>.<minor>" is a pinned version; policy is tiers.
  # Functional lowercase IDs (e.g. claude-<model>-<ver> in Copilot frontmatter)
  # are a separate concern and intentionally don't match this prose pattern.
  ! rg -q '\b(Opus|Sonnet|Haiku) [0-9]+\.[0-9]+' "$REPO_ROOT"
}

@test "model-strategy: Claude agent frontmatter uses floating tier aliases" {
  for f in "$REPO_ROOT"/agents/claude-code/*.md; do
    model="$(grep -m1 '^model:' "$f" | awk '{print $2}')"
    case "$model" in
      opus|sonnet|haiku) ;;
      *) echo "non-floating model in $(basename "$f"): '$model'"; return 1 ;;
    esac
  done
}

@test "model-strategy: PAPER + README describe agents by tier, not version" {
  grep -q -- '-tier' "$REPO_ROOT/PAPER.md"
  grep -q -- '-tier' "$REPO_ROOT/README.md"
}
