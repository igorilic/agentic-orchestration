#!/usr/bin/env bats

# COP-1 docs checks. The Copilot install itself is tested in
# tests/install-native.bats; HARNESS-2 P1-9 rewrites these with the docs.

@test "docs: README mentions ~/.copilot/skills/" {
  rg -q '~/\.copilot/skills/' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: README mentions ~/.copilot/copilot-instructions.md" {
  rg -q '~/\.copilot/copilot-instructions\.md' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: README mentions ~/.copilot/settings.json" {
  rg -q '~/\.copilot/settings\.json' "$BATS_TEST_DIRNAME/../README.md"
}

@test "docs: ARCHITECTURE notes hooks asymmetry (Claude global, Copilot repo-scope)" {
  rg -qi 'copilot.*(repo|repository)[- ]scope|repo[- ]scope.*copilot' \
    "$BATS_TEST_DIRNAME/../docs/ARCHITECTURE.md"
}
