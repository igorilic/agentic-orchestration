#!/usr/bin/env bash
# lib/help.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

show_help() {
  cat << 'HELP'

  ╔════════════════════════════════════════════════════════════╗
  ║       ai-native-workflow — AI-Native Development CLI       ║
  ╚════════════════════════════════════════════════════════════╝

  USAGE
    ai-native-workflow <command> [options]

  INSTALL COMMANDS
    install global              Install hooks, policy, instructions, skills (~/.claude, ~/.copilot)
    install project [path]      Write .anw/verify (the finish line, trusted on your y),
                                AGENTS.md, CLAUDE.md and docs/context/ (stack auto-detected)
    install all [path]          Install both global + project

  PIPELINE COMMANDS (each stage is a fresh claude -p / copilot -p session; no bypass flags)
    run github-feature [file]   Claude: /plan → you approve → one session per step → /check
                                (read-only) → trusted .anw/verify → push + PR on your yes
    run github-issue <N>        The same, planned from GitHub issue #N; the PR closes it
    run gitlab-feature <ID>     Copilot: the same, planned from Jira ticket <ID>; MR via glab
    run gitlab-incident <ID>    Copilot: read-only /incident → you decide → the fix flow above
    run status                  Show the active pipeline
    run resume                  Continue it from the last finished stage
                                Agents never push or post: the script does, after you confirm.

  OTHER COMMANDS
    detect [path]               Show detected stacks without installing
    status                      Show installation status + pipeline state
    doctor                      Like status, but exits 1 on drift, a custom agent,
                                or an untrusted .anw/verify in this repo
    trust [path]                Review a repo's .anw/verify and approve it for the Stop hook
    uninstall global            Remove our hooks, hook wiring and unmodified skills
    uninstall project [path]    Remove the old per-project Copilot hooks
    help                        Show this message
    version                     Show version

  EXAMPLES
    ai-native-workflow install all .
    ai-native-workflow run gitlab-feature PROJ-123
    ai-native-workflow run gitlab-incident PROJ-456
    ai-native-workflow run github-feature specs.md
    ai-native-workflow run github-feature           # describe it interactively
    ai-native-workflow run github-issue 42
    ai-native-workflow run status
    ai-native-workflow run resume
    ai-native-workflow detect ~/code/my-frontend
    ai-native-workflow status

  PREREQUISITES
    run gitlab-feature:    copilot (Jira MCP to read the ticket), glab; jira CLI to post the MR link
    run gitlab-incident:   copilot, glab, az, kubectl (read-only); jira CLI optional
    run github-issue:      claude, gh
    run github-feature:    claude, gh

  WHAT GETS INSTALLED

    Global (~/.claude/ and ~/.copilot/; replaced files go to anw-backup/):
      hooks/guard.sh            Pre-tool gate: denies hook bypass and harness edits,
                                asks on test-weakening commits, new deps, CI edits
      hooks/verify.sh           Stop gate: runs the repo's trusted .anw/verify
      settings.json             Claude: permissions, sandbox, hook wiring (merged)
      hooks/anw.json            Copilot: preToolUse + agentStop wiring
      CLAUDE.md                 Claude: your preamble + managed working agreements
      copilot-instructions.md   Copilot: your preamble + managed working agreements
      skills/*                  Copies: plan, check, verify, incident, pr, explore,
                                ticket, adr, gh-cli, glab-cli, ...

    Per-Project:
      .anw/verify               Finish line: the full test suite (tracked; rest of .anw/ ignored)
      AGENTS.md                 Commands, then Always / Ask first / Never (≤ 80 lines)
      CLAUDE.md                 Imports AGENTS.md
      docs/context/             Architecture, conventions, specs, sprint
      docs/decisions/           ADR directory

  DAY TO DAY (interactive, both tools; no custom agents)
    /plan <ticket> → implement one step at a time → /check → /pr    (Copilot: plus /rubber-duck)
    /incident <ticket> investigates read-only; you decide what happens next

HELP
}

