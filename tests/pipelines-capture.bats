#!/usr/bin/env bats

# SDK-1 Step B-10 (closes the reviewer/qa B-9 ship-blocker).
#
# Since B-7, run_claude_agent's stdout is the renderer's rendered glyph
# stream (lib/render-stream.sh) plus its own header()/success() lines
# (lib/common.sh) -- NOT the agent's raw text. pipeline_github_feature's
# Step 2 (lib/pipelines.sh) used to capture the GitHub issue URL by piping
# run_claude_agent's stdout through `2>&1 | tail -1`, which after B-7 grabs
# "✓ requirements-engineer completed" instead of the URL -> issue_num
# (grep -oE '[0-9]+$') comes back empty -> Step 7 silently drops
# "Closes #N" from the PR body.
#
# Worse, requirements-engineer now narrates @@ANW|... sentinel lines
# (AC-14), so even the raw LAST_AGENT_OUTPUT can't safely be `tail -1`'d --
# a sentinel `done` line can legitimately be the LAST line of a real run,
# with the URL buried earlier in the stream.
#
# The fix greps the URL PATTERN out of LAST_AGENT_OUTPUT (the raw agent
# text, restored from the tee'd debug log by B-7 -- see the ponytail: note
# at lib/pipeline-core.sh:342) rather than trusting line position.
#
# This tests extract_issue_url() directly (extracted into lib/pipelines.sh
# for testability) rather than driving all of pipeline_github_feature --
# cheaper than extending tests/sdk-1-integration.bats past its Step-1
# wait_for_review pause.

PIPELINES_LIB="$BATS_TEST_DIRNAME/../lib/pipelines.sh"

setup() {
  # shellcheck source=lib/pipelines.sh disable=SC1091
  source "$PIPELINES_LIB"
}

@test "extract_issue_url: URL is the only line" {
  LAST_AGENT_OUTPUT="https://github.com/o/r/issues/42"
  [ "$(extract_issue_url)" = "https://github.com/o/r/issues/42" ]
}

@test "extract_issue_url: URL is not the last line (sentinel lines follow it)" {
  LAST_AGENT_OUTPUT="$(printf '%s\n' \
    '@@ANW|phase|Drafting issue' \
    'https://github.com/o/r/issues/42' \
    '@@ANW|step|run|Formatting issue body')"
  [ "$(extract_issue_url)" = "https://github.com/o/r/issues/42" ]
}

@test "extract_issue_url: sentinel done is the literal last line -- the exact case that fools tail -1" {
  LAST_AGENT_OUTPUT="$(printf '%s\n' \
    '@@ANW|phase|Drafting issue' \
    '@@ANW|step|run|Formatting issue body' \
    'https://github.com/o/r/issues/42' \
    '@@ANW|done|Issue created')"
  [ "$(extract_issue_url)" = "https://github.com/o/r/issues/42" ]
  # Prove the naive `tail -1` on raw output would have grabbed the sentinel
  # line, not the URL -- i.e. this extraction is NOT just `tail -1`.
  [ "$(printf '%s\n' "$LAST_AGENT_OUTPUT" | tail -1)" != "$(extract_issue_url)" ]
}

@test "extract_issue_url: downstream issue_num is correctly derived from the extracted URL" {
  LAST_AGENT_OUTPUT="$(printf '%s\n' \
    '@@ANW|phase|Drafting issue' \
    '@@ANW|step|run|Formatting issue body' \
    'https://github.com/o/r/issues/42' \
    '@@ANW|done|Issue created')"
  issue_url="$(extract_issue_url)"
  issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$' || echo "")
  [ "$issue_num" = "42" ]
}

@test "extract_issue_url: multiple URL-shaped lines -- the last URL wins" {
  LAST_AGENT_OUTPUT="$(printf '%s\n' \
    'https://github.com/o/r/issues/41' \
    '@@ANW|step|ok|Retitled' \
    'https://github.com/o/r/issues/42' \
    '@@ANW|done|Issue created')"
  [ "$(extract_issue_url)" = "https://github.com/o/r/issues/42" ]
}

@test "extract_issue_url: no URL present -- returns empty (exit 0), not a sentinel line" {
  LAST_AGENT_OUTPUT="$(printf '%s\n' \
    '@@ANW|phase|Drafting issue' \
    '@@ANW|done|no issue created')"
  run extract_issue_url
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no install side effects: real ~/.copilot has zero .bak.* artifacts" {
  count="$(find "$HOME/.copilot" -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
