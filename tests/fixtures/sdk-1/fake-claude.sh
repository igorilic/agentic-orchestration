#!/usr/bin/env bash
# tests/fixtures/sdk-1/fake-claude.sh — SDK-1 Step B-6 test fixture.
#
# Stands in for the real `claude` CLI on PATH so pipeline-core.sh tests can
# exercise run_claude_agent's streaming/exit-code plumbing without spawning
# the real Claude Code CLI. Ignores its actual argv (--agent=, -p, etc.) --
# pipeline-core.sh tests only care about two things this shim controls:
# what it prints to stdout, and what it exits with.
#
# Exit code is read from FAKE_CLAUDE_EXIT_CODE (default 0) so one fixture
# file covers both the AGENT_OK and AGENT_ERROR paths.
echo "fake-claude: stdout line 1"
echo "fake-claude: stdout line 2"
exit "${FAKE_CLAUDE_EXIT_CODE:-0}"
