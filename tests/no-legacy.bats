#!/usr/bin/env bats
# HARNESS-2 P1-7: the custom agents, the confidence gate, the bypass skills and the sentinel
# protocol are gone from the code. Docs are P1-9. The installer still names the old files,
# but only in its RETIRED_* lists, to clean them out of homes that an older version set up.

ROOT="$BATS_TEST_DIRNAME/.."

@test "the legacy files and directories are gone" {
  for p in agents scripts demo templates config/settings.json \
           skills/tdd skills/skip-tdd skills/override-confidence skills/brainstorm \
           skills/pipeline-github-feature skills/pipeline-gitlab-feature skills/pipeline-gitlab-incident \
           hooks/tdd-gate.sh hooks/confidence-gate.sh hooks/session-start.sh \
           lib/render-stream.sh lib/milestones.sh tests/fixtures tests/lib; do
    [ ! -e "$ROOT/$p" ] || { echo "still here: $p"; false; }
  done
}
@test "no code mentions the old gates, bypass files, sidekick or sentinels (outside the retire lists)" {
  run bash -c 'cd "$1" && grep -rn -E "CLAUDE_TOOL_INPUT|confidence\.jsonl|\.tdd-skip|override-confidence|sidekick|@@ANW|render_pipeline_and_stacks_md" \
    lib hooks skills config instructions ai-native-workflow Makefile .github .gitignore | grep -v "^lib/install-global.sh:[0-9]*:RETIRED_"' _ "$ROOT"
  [ -z "$output" ] || { echo "$output"; false; }
}
@test "CI and lint only check files that exist" {
  ! grep -qE 'scripts/\*\.sh|skills/\*/\*\.bash' "$ROOT/Makefile" "$ROOT/.github/workflows/test.yml" || false
}

# P1-9: the docs match the code. History stays in PAPER's erratum, ADR-003 and the old specs.
@test "README, ARCHITECTURE and CONTRIBUTING describe no removed component" {
  run bash -c 'cd "$1" && grep -n -E "skip-tdd|override-confidence|tdd-gate|confidence-gate|confidence\.jsonl|\.tdd-skip|--agent|requirements-engineer|tdd-developer|diff-reviewer|troubleshooter|sidekick|@@ANW|copilot-cli-dispatcher|session-start\.sh" \
    README.md docs/ARCHITECTURE.md CONTRIBUTING.md' _ "$ROOT"
  [ -z "$output" ] || { echo "$output"; false; }
}
@test "PAPER carries the erratum and drops the claims that were never true" {
  grep -q '^## Erratum' "$ROOT/PAPER.md" || false
  ! grep -q 'automatically deleted after the next commit' "$ROOT/PAPER.md" || false
  ! grep -qi 'does not support user-global hooks' "$ROOT/PAPER.md" "$ROOT/docs/ARCHITECTURE.md" || false
}
@test "ADR-003 supersedes ADR-001 and ADR-002" {
  grep -q '^- \*\*Supersedes\*\*: ADR-001.*ADR-002' "$ROOT/docs/decisions/ADR-003-native-first-harness.md" || false
  for a in 001 002; do grep -q '^- \*\*Status\*\*: Superseded by ADR-003' "$ROOT"/docs/decisions/ADR-$a-*.md || { echo "ADR-$a"; false; }; done
}
