#!/usr/bin/env bash
# Blocks git commits without test files. Exit code 2 = block action.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"

# Only gate git commit
echo "$TOOL_INPUT" | grep -qE 'git\s+commit' || exit 0

# Allow amend
echo "$TOOL_INPUT" | grep -qE -- '--amend' && exit 0

# Check bypass
if [ -f "$PROJECT_DIR/.tdd-skip" ]; then
  echo "⚠️ TDD bypass active — commit allowed." >&2
  exit 0
fi

# Check for test files in staged changes
TEST_PATTERNS='(test|spec|_test\.|\.test\.|\.spec\.|tests/|__tests__/|Tests/|Test\.)'
TEST_FILES=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | grep -iE "$TEST_PATTERNS" || true)

if [ -z "$TEST_FILES" ]; then
  echo "🚫 TDD GATE: No test files in staged changes." >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  1. Write tests first, stage them, commit together" >&2
  echo "  2. /skip-tdd 'reason' to bypass (logged)" >&2
  echo "" >&2
  echo "Common reasons: 'docs-only' | 'CI config' | 'dependency update' | 'hotfix'" >&2
  exit 2
fi

TEST_COUNT=$(echo "$TEST_FILES" | wc -l | tr -d ' ')
echo "✅ TDD gate passed: $TEST_COUNT test file(s)." >&2
exit 0
