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

  PIPELINE COMMANDS
    run gitlab-feature <ID>     GitLab feature development pipeline
                                Jira → requirements-engineer → qa (test plan)
                                → architect → tdd-developer → qa → reviewer → MR

    run gitlab-incident <ID>    GitLab incident response pipeline
                                Jira → troubleshooter → [document OR fix]
                                → tdd-developer → qa → reviewer → MR

    run github-feature [file]   GitHub feature development pipeline
                                specs.md/input → requirements-engineer
                                → GitHub issue → architect → tdd-developer
                                → qa → reviewer → PR

    run github-issue <ID>       GitHub issue investigation & fix pipeline
                                Issue #ID → troubleshooter (investigate)
                                → architect (plan) → tdd-developer → qa
                                → reviewer → PR (Closes #ID)

    run status                  Show active pipeline state
    run resume                  Resume pipeline from last checkpoint

  FLAGS (for pipeline commands)
    --allowed-questions [N]     Let agents ask up to N clarifying questions
                                (default N=3). Agents pause and prompt for
                                answers before continuing. Without this flag,
                                agents make assumptions and document them.

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
    ai-native-workflow run github-feature           # interactive input
    ai-native-workflow run github-issue 42           # investigate & fix issue #42
    ai-native-workflow run github-feature --allowed-questions    # agents can ask 3 Qs
    ai-native-workflow run gitlab-feature PROJ-123 --allowed-questions 5
    ai-native-workflow run status
    ai-native-workflow run resume
    ai-native-workflow detect ~/code/my-frontend
    ai-native-workflow status

  PREREQUISITES
    run gitlab-feature:    copilot, glab, jira MCP
    run gitlab-incident:   copilot, glab, az, kubectl
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

  AGENT ROSTER

    requirements-engineer (Opus-tier)  → elicit & formalize requirements
    architect (Opus-tier)              → design, spec, atomic plan
    tdd-developer (Sonnet-tier)        → RED→GREEN→REFACTOR per step
    qa (Opus-tier)                     → adversarial test + gap hunt
    reviewer (Sonnet-tier)             → code review, user triages
    troubleshooter (Opus-tier)         → incident investigation + diagnosis

  COPILOT CLI USAGE

    Copilot CLI agents mirror Claude Code agents with .agent.md format.
    Installed to ~/.copilot/agents/ (or $COPILOT_HOME/agents/).

    Interactive:
      copilot                               # start session
      /agent                                # pick from agent list

    Direct:
      copilot --agent=requirements-engineer --prompt "Analyze PROJ-123"
      copilot --agent=architect --prompt "Plan JWT auth feature"
      copilot --agent=tdd-developer --prompt "Step 1 of PROJ-123-todo.md"
      copilot --agent=qa --prompt "Verify the changes"
      copilot --agent=reviewer --prompt "Review the changes"
      copilot --agent=troubleshooter --prompt "Investigate PROJ-456"

HELP
}

