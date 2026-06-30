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
    install global              Install hooks, skills, agents to ~/.claude/
    install project [path]      Install AGENTS.md, Copilot config, docs/context/
                                (auto-detects stack from project files)
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
    uninstall global            Remove global hooks and skills
    uninstall project [path]    Remove project Copilot instructions
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

    Global (~/.claude/):
      CLAUDE.md                 Personal defaults + pipeline reference
      settings.json             SessionStart + TDD gate + confidence gate hooks
      hooks/session-start.sh    Auto-loads context + detects stack
      hooks/tdd-gate.sh         Blocks commits without tests
      hooks/confidence-gate.sh  Blocks PR/MR on RED confidence verdict
      scripts/confidence.sh     Confidence scorer (deterministic)
      scripts/confidence-cli.sh Confidence CLI helpers for pipeline
      skills/tdd/               /tdd — RED → GREEN → REFACTOR
      skills/ticket/            /ticket — Jira issue → spec + tests
      skills/skip-tdd/          /skip-tdd — Bypass TDD with reason
      skills/override-confidence/ /override-confidence — Bypass confidence gate
      skills/session-report/    /session-report — Obsidian notes
      skills/adr/               /adr — Architecture Decision Records
      skills/pr/                /pr — Create PR/MR (gh/glab)
      skills/plan/              /plan — Pipeline orchestration entry point
      skills/clusters/          /clusters — Multi-region reference
      skills/pipeline-*/        Pipeline reference skills
      agents/requirements-engineer.md  Opus-tier — elicit requirements
      agents/architect.md       Opus-tier — design, spec, todo plan
      agents/tdd-developer.md   Sonnet-tier — strict TDD implementation
      agents/qa.md              Opus-tier — adversarial test + gap hunt
      agents/reviewer.md        Sonnet-tier — code review + triage
      agents/troubleshooter.md  Opus-tier — incident diagnosis + fix plan

    Per-Project:
      AGENTS.md                 Cross-tool rules (Claude + Copilot)
      CLAUDE.md                 Project context
      docs/context/             Architecture, conventions, specs, sprint
      .anw/                     Runtime pipeline state + confidence logs (gitignored)
      .github/copilot-instructions.md   Copilot repo-wide rules
      .github/instructions/*.md          Stack-specific Copilot rules
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

