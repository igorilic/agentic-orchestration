#!/usr/bin/env bats

# SDK-1 Step B-5: lib/pipeline-core.sh::agent_tier — agent name -> model tier.
#
# Single source of truth (ponytail): the tier already lives in each agent's
# frontmatter (`model: opus|sonnet|haiku` in agents/claude-code/<agent>.md).
# agent_tier() reads it from there rather than duplicating the mapping in a
# hardcoded case statement, so the badge injected via AW_TIER can never drift
# from the agent that's actually running.
#
# Pure function: reads a file, echoes a value, no side effects — safe to call
# directly after sourcing lib/pipeline-core.sh (mirrors tests/milestones.bats;
# pipeline-core.sh defines no top-level side effects beyond `SPINNER_PID=""`,
# so it's source-safe standalone, unlike the main dispatcher).

PIPELINE_CORE="$BATS_TEST_DIRNAME/../lib/pipeline-core.sh"

setup() {
  # shellcheck source=lib/pipeline-core.sh disable=SC1091
  source "$PIPELINE_CORE"
}

# ---------------------------------------------------------------------------
# Core mapping (spec table).
# ---------------------------------------------------------------------------

@test "agent_tier architect -> opus" {
  [ "$(agent_tier architect)" = "opus" ]
}

@test "agent_tier qa -> opus" {
  [ "$(agent_tier qa)" = "opus" ]
}

@test "agent_tier tdd-developer -> sonnet" {
  [ "$(agent_tier tdd-developer)" = "sonnet" ]
}

@test "agent_tier sidekick -> haiku" {
  [ "$(agent_tier sidekick)" = "haiku" ]
}

@test "agent_tier reviewer -> sonnet (frontmatter, not just the 4 spec examples)" {
  [ "$(agent_tier reviewer)" = "sonnet" ]
}

# ---------------------------------------------------------------------------
# Unknown agent -> sensible default.
# ---------------------------------------------------------------------------

@test "agent_tier unknown agent -> default tier (sonnet)" {
  [ "$(agent_tier bogus-agent)" = "sonnet" ]
}

# ---------------------------------------------------------------------------
# Single-source-of-truth: reads frontmatter, doesn't hardcode a duplicate
# mapping. A hardcoded case statement would still pass the tests above but
# fail this one the moment the fixture agent's model: line disagrees with
# any baked-in guess.
# ---------------------------------------------------------------------------

@test "agent_tier reads the frontmatter (no drift): a fixture agents dir wins over any hardcoded guess" {
  fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/aw-agent-tier-XXXXXX")"
  mkdir -p "$fixture_dir/agents/claude-code"
  cat > "$fixture_dir/agents/claude-code/tdd-developer.md" <<'EOF'
---
name: tdd-developer
model: haiku
tools: Read
---
body
EOF
  _ANW_SCRIPT_DIR="$fixture_dir" run agent_tier tdd-developer
  rm -rf "$fixture_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "haiku" ]
}

# ---------------------------------------------------------------------------
# Purity: no filesystem writes, no ~/.copilot install side effects.
# ---------------------------------------------------------------------------

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
