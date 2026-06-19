# Agentic Orchestration for Test-Driven Development: A Multi-Agent Pipeline Architecture for Solo Full-Stack Development

**Igor Ilic**

March 2026

---

> **Note on scope and method.** This is a *design and architecture whitepaper*
> describing a working open-source system, not an empirical study. It reports
> no controlled evaluation. Claims about behavioral drift, TDD discipline, and
> reliability are design rationale and informal observation from single-developer
> use, not measured results; statements that a mechanism is "probabilistic" or
> "guaranteed" describe intended behavior of the underlying tools, not benchmarked
> rates. Read it as an engineering description of how the system is built and why,
> with the contributions below understood as design contributions.

---

## Abstract

This paper presents a multi-agent orchestration architecture designed for solo full-stack developers managing polyglot codebases across distributed Kubernetes environments. The system coordinates eight specialized AI agents — requirements engineer, architect, test-driven developer, quality assurance, code reviewer, diff reviewer, troubleshooter, and explorer — through a deterministic pipeline enforced by lifecycle hooks, with probabilistic skill activation for workflow flexibility. The architecture operates across two primary AI coding platforms (Claude Code and GitHub Copilot CLI) using a shared instruction layer (AGENTS.md) to ensure behavioral consistency. We describe how separating concerns between deterministic enforcement (hooks), probabilistic workflows (skills), and specialized reasoning (agents with model-tier selection) creates a development system where test-driven discipline is guaranteed by machinery rather than developer memory, while maintaining the flexibility needed for real-world incident response across multi-region cloud infrastructure. The system is delivered as a self-contained CLI installer with automatic stack detection for .NET, Go, Rust, Python, React/TypeScript, React Native, and Swift codebases.

**Keywords:** multi-agent orchestration, test-driven development, AI-assisted software engineering, Claude Code, GitHub Copilot, DevOps, Kubernetes, agentic workflows

---

## 1. Introduction

### 1.1 Problem Statement

Solo full-stack developers face a compounding productivity challenge: they must maintain discipline across multiple technology stacks, testing frameworks, and deployment environments while simultaneously designing, implementing, reviewing, and operating their software. The cognitive load of context-switching between architectural thinking, test writing, implementation, code review, and production troubleshooting degrades the quality of each activity.

AI coding assistants have shown significant promise in augmenting developer productivity, but they introduce their own category of problems. Current AI assistants exhibit what we term *behavioral drift* — the tendency to gradually deprioritize system-level instructions (such as TDD requirements) over the course of a conversation as the model's attention shifts to the most recent context. A developer who establishes a "tests first" rule at the beginning of a session frequently finds the AI skipping directly to implementation 30 minutes later.

Additionally, existing approaches typically rely on a single monolithic instruction file (e.g., `CLAUDE.md`) to encode all behavioral rules, workflow protocols, and project context. This conflation of concerns — enforcement, workflow, and context — means that everything operates at the same priority level: suggestion. Nothing is guaranteed.

### 1.2 Proposed Solution

We propose a **separation-of-concerns architecture** for AI-assisted development that divides the workflow into three distinct mechanism types:

1. **Deterministic enforcement** via lifecycle hooks that execute shell scripts at specific points in the AI agent's workflow (session start, pre-tool-use, post-tool-use). These cannot be skipped or overridden by the AI model.

2. **Probabilistic workflows** via skills — reusable instruction sets that the AI model loads when contextually relevant, providing structured procedures for common tasks.

3. **Specialized reasoning** via purpose-built agents, each configured with a specific model tier, tool set, and behavioral prompt optimized for a single responsibility.

The system is further designed around a **pipeline pattern** where agents hand off work products to each other through the filesystem (specification files, todo plans, test files, code), creating an auditable chain of artifacts.

### 1.3 Contributions

This paper makes the following contributions:

- A formalization of the **hooks/skills/agents** separation principle for AI-assisted development workflows
- An **eight-agent system**: a linear feature pipeline (requirements-engineer → architect → tdd-developer → qa → reviewer) plus specialist agents — troubleshooter (incidents), diff-reviewer (whole-PR/MR review), and explorer (spikes) — each with model-tier optimization per role
- A **cross-tool instruction layer** (AGENTS.md) that provides behavioral consistency across Claude Code and GitHub Copilot CLI
- A **deterministic TDD gate** that blocks commits without test files, with an accountable bypass mechanism
- A **confidence gate** that scores step readiness from a per-spec log and blocks commits that fail hard gates (e.g., failing or absent tests), with an accountable `/override-confidence` bypass
- A **multi-cluster troubleshooting workflow** for distributed Kubernetes environments with ArgoCD, Azure Application Insights, and kubectl
- A **self-contained CLI installer** with automatic polyglot stack detection

---

## 2. Background and Related Work

### 2.1 AI Coding Assistants

The landscape of AI-assisted development has evolved from autocomplete (GitHub Copilot, 2021) to conversational code generation (ChatGPT, 2022) to agentic coding (Claude Code, Copilot CLI agent mode, 2025). The key transition is from *suggestion* to *execution* — modern tools can read files, run commands, edit code, and commit changes autonomously.

Claude Code introduced three extension points that enable the architecture described in this paper: **hooks** (deterministic lifecycle scripts, September 2025), **skills** (reusable instruction sets, October 2025), and **subagents** (isolated context windows with custom system prompts, July 2025). GitHub Copilot CLI subsequently added support for custom agents (.agent.md files) and AGENTS.md instruction files, creating the opportunity for cross-tool behavioral consistency.

### 2.2 Test-Driven Development Enforcement

TDD's effectiveness is well-documented but its adoption remains low, even among developers who believe in its value. The primary barrier is not technical but cognitive — writing tests first requires sustained discipline that competes with the immediate gratification of writing implementation code. AI assistants exacerbate this by making implementation "feel free" while tests still require careful specification of expected behavior.

Previous approaches to TDD enforcement relied on CI/CD pipeline gates (rejecting PRs without test coverage) or IDE plugins (prompting for tests). Both operate *after* the developer has already written implementation code, making them corrective rather than preventive. Our approach operates *before* code is committed, at the AI agent level, making TDD the only available path.

### 2.3 Multi-Agent Systems in Software Engineering

The concept of specialized agents collaborating on software tasks has been explored in academic literature but practical implementations have been limited by the lack of runtime infrastructure. The introduction of subagent support in Claude Code and custom agents in Copilot CLI provides, for the first time, a production-ready platform for multi-agent software engineering workflows with separate context windows, tool restrictions, and model selection per agent.

---

## 3. Architecture

### 3.1 Design Principles

The architecture is governed by four principles:

**P1: Determinism over suggestion.** Any rule that must be followed 100% of the time is implemented as a hook (exit code 2 blocks the action), not as an instruction in a prompt.

**P2: Single responsibility per agent.** Each agent has one job. The architect never writes code. The developer never designs. The reviewer never modifies. The QA agent never interprets — only reports.

**P3: Filesystem as message bus.** Agents communicate through files (spec.md, todo.md, test files, code files), not through conversational context. This creates an auditable artifact trail and survives context window compaction.

**P4: Cross-tool consistency.** Behavioral rules are defined once in AGENTS.md and consumed by both Claude Code and Copilot CLI, eliminating the need to maintain parallel instruction sets.

### 3.2 Three-Layer Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  ENFORCEMENT LAYER (Hooks — Deterministic)                     │
│  SessionStart → load context, detect stack                     │
│  PreToolUse   → TDD gate + confidence gate (block commits)     │
│  Notification → desktop alerts                                 │
├────────────────────────────────────────────────────────────────┤
│  WORKFLOW LAYER (Skills — Probabilistic)                       │
│  /plan    → pipeline orchestration entry point                 │
│  /tdd     → RED→GREEN→REFACTOR cycle                           │
│  /ticket  → Jira/GitHub issue → spec + test stubs              │
│  /adr · /pr → decision records, PR/MR creation                 │
│  /override-confidence → accountable confidence bypass          │
├────────────────────────────────────────────────────────────────┤
│  REASONING LAYER (Agents — Specialized)                        │
│  requirements-engineer (Opus-tier)   → elicit, formalize ACs   │
│  architect             (Opus-tier)   → design, spec, plan      │
│  tdd-developer         (Sonnet-tier) → implement via TDD       │
│  qa                    (Haiku-tier)  → run affected tests      │
│  reviewer              (Sonnet-tier) → per-step review         │
│  diff-reviewer         (Opus-tier)   → whole-PR/MR review      │
│  troubleshooter        (Opus-tier)   → incident investigation  │
│  explorer              (Sonnet-tier) → spikes & prototypes     │
└────────────────────────────────────────────────────────────────┘
```

### 3.3 Agent Pipeline

#### 3.3.1 Feature Development Pipeline

The feature development pipeline follows a strict linear progression:

1. **Requirements-Engineer** (Opus-tier) elicits and formalizes the requirement — from a Jira ticket, a `specs.md` file, or direct user input — into a structured requirements document with testable acceptance criteria. This runs before any design so the architect plans against explicit, verifiable goals rather than an ambiguous prompt.

2. **Architect** (Opus-tier) reads the requirements, analyzes the codebase, and produces two artifacts: a feature specification (`spec.md`) and an atomic todo plan (`todo.md`). Each step in the todo must be independently testable and result in a commit. The architect never writes implementation code.

3. **TDD-Developer** (Sonnet-tier) receives one step at a time from the todo plan and executes the RED→GREEN→REFACTOR cycle. It writes failing tests first (RED), implements the minimum code to pass (GREEN), refactors while keeping tests green, and commits at each phase. The PreToolUse hooks block any `git commit` that doesn't include test files in the staging area, or that fails the confidence gate's hard checks.

4. **QA** (Haiku-tier) runs after each step completes, executing only the tests affected by the changed files. It detects the appropriate test runner from project files and reports exact pass/fail results without interpretation.

5. **Reviewer** (Sonnet-tier) evaluates the changes against a checklist covering correctness, test quality, code quality, stack conventions, security, and performance. Findings are categorized as MUST FIX (automatic), SHOULD FIX (user decides), and SUGGESTION (user decides). The user triages each item as Fix, Tech Debt, or Ignore.

6. **Fix Loop** (max 3 iterations): items marked for fixing are sent back to the TDD-Developer. After three cycles, remaining issues are automatically moved to a tech debt backlog.

Two further agents operate outside this linear flow: **diff-reviewer** (Opus-tier) performs a whole-PR/MR review once a pull/merge request exists — ranking findings by severity and, after a preview-and-confirm gate, posting them as inline comments or threads — and **explorer** (Sonnet-tier) supports spikes, prototyping, and API learning, writing throwaway code under a gitignored `spikes/` directory rather than shipping it.

#### 3.3.2 Incident Response Pipeline

The troubleshooter agent (Opus-tier) handles a parallel workflow for production incidents:

1. Fetch incident context from Jira (via MCP)
2. Determine scope — query Azure Application Insights across all three regional clusters (EMEA, APAC, NAM) to determine if the issue is regional or global
3. Gather evidence from ArgoCD (app health, sync status), kubectl (pod logs, events), and Application Insights (exceptions, failed requests, dependency failures)
4. Correlate timestamps across sources to identify root cause
5. Produce a structured diagnosis and create a todo plan where Step 1 is always a test that reproduces the bug
6. Hand off to the TDD-Developer for the fix

### 3.4 Model Selection Strategy

Model selection is based on the cognitive demands of each role:

| Agent | Model | Rationale |
|-------|-------|-----------|
| Requirements-Engineer | Opus-tier | Elicits and disambiguates intent into testable acceptance criteria — high-stakes framing that the rest of the pipeline depends on |
| Architect | Opus-tier | Requires deep codebase analysis, design reasoning, and creative problem decomposition |
| TDD-Developer | Sonnet-tier | Needs strong coding ability but follows a prescribed plan — no design decisions |
| QA | Haiku-tier | Executes test commands and reports output — minimal reasoning required |
| Reviewer | Sonnet-tier | Pattern matching against conventions and best practices — moderate reasoning |
| Diff-Reviewer | Opus-tier | Whole-PR/MR review — security, logic, and landmine analysis across an entire diff |
| Troubleshooter | Opus-tier | Requires cross-system correlation, root cause analysis, and creative diagnosis |
| Explorer | Sonnet-tier | Generates and evaluates throwaway options for spikes — coding ability without ship-quality constraints |

This tiering optimizes both cost and latency. The QA agent (Haiku-tier) returns results in seconds, while the Architect and Troubleshooter (Opus-tier) take longer but produce higher-quality reasoning for tasks where that matters.

The architecturally meaningful decision is the **tier**, not a specific model version. Agents are therefore configured with floating tier aliases (`opus`, `sonnet`, `haiku`) rather than pinned version identifiers, so each role automatically tracks the current best model of its tier as new releases ship — no per-release maintenance, and no quality left on the table. We avoid naming concrete versions in this paper for the same reason: with no controlled evaluation pinned to a particular model (see §5.3), a version number would imply a reproducibility claim the system does not make. Copilot CLI is the one exception in practice: its agent frontmatter accepts a `model` field but expects a concrete model identifier and offers no floating-alias equivalent, so the Copilot-side agents are the single place a specific version is pinned — and the price is that those identifiers must be bumped by hand as new models ship.

### 3.5 Commit-Time Enforcement: TDD and Confidence Gates

Two `PreToolUse` hooks gate `git commit`. The TDD gate is the first:

```bash
# Simplified logic
if [[ "$TOOL_INPUT" matches "git commit" ]]; then
  if [[ -f ".tdd-skip" ]]; then exit 0; fi    # Bypass active
  TEST_FILES=$(git diff --cached --name-only | grep -iE "(test|spec)")
  if [[ -z "$TEST_FILES" ]]; then exit 2; fi  # Block commit
fi
```

Exit code 2 is the critical mechanism — Claude Code treats it as a hard block that prevents the action. This is fundamentally different from a prompt instruction, which the model can deprioritize or forget.

The bypass mechanism (`/skip-tdd`) creates a timestamped `.tdd-skip` file with the developer's reason, which is automatically deleted after the next commit. This provides accountability without rigidity.

The second gate is a **confidence gate**. As the pipeline runs, agents append structured events to a per-spec confidence log (`.anw/specs/<id>-confidence.jsonl`) recording acceptance-criteria coverage and test outcomes. A second `PreToolUse` hook scores the active step's readiness from this log into one of three bands — GREEN, YELLOW, RED — combining *hard gates* (e.g., a failing test run, or an acceptance criterion claimed complete with zero tests) that force RED with softer scored penalties. A RED band blocks the commit. The scorer is deliberately **fail-closed**: a missing or unparseable `tests_failed` field is treated as a failure rather than waved through, so the absence of evidence never reads as success. As with the TDD gate, the bypass (`/override-confidence`) is accountable — it requires a non-boilerplate reason of meaningful length, which is logged against the active spec.

Together the two gates encode a simple invariant: a commit must carry tests, and the recorded evidence for the current step must not be in a known-bad state. Both are machinery rather than prompt instructions, so neither can be deprioritized as a conversation grows.

### 3.6 Cross-Tool Compatibility

The architecture achieves behavioral consistency across Claude Code and Copilot CLI through a layered instruction model:

| File | Claude Code | Copilot CLI |
|------|-------------|-------------|
| `AGENTS.md` | ✓ auto-loaded | ✓ auto-loaded |
| `CLAUDE.md` | ✓ auto-loaded | ✓ supported |
| `.github/copilot-instructions.md` | — | ✓ auto-loaded |
| `.github/instructions/*.instructions.md` | — | ✓ path-specific |
| `~/.claude/agents/*.md` | ✓ subagents | — |
| `~/.copilot/agents/*.agent.md` | — | ✓ custom agents |

`AGENTS.md` is the shared behavioral contract. Agent-specific files are maintained in parallel for each tool but derived from the same source of truth.

---

## 4. Implementation

### 4.1 Stack Detection

The installer performs automatic stack detection by scanning project files:

| Indicator | Stack | Test Runner |
|-----------|-------|-------------|
| `*.csproj`, `*.sln` | .NET | xUnit + FluentAssertions |
| `go.mod` | Go | testing + testify |
| `Cargo.toml` | Rust | built-in + tokio-test |
| `pyproject.toml` | Python | pytest |
| `package.json` with react | React/TS | Vitest or Jest |
| `package.json` with react-native | React Native | Jest + RNTL |
| `Package.swift` | Swift | XCTest |

Detection scans up to three directory levels deep, supporting monorepo configurations where different stacks exist in subdirectories.

### 4.2 Multi-Cluster Support

The troubleshooter agent operates across three regional Kubernetes clusters (EMEA, APAC, NAM) managed by a single ArgoCD instance. The `/clusters` skill provides a reference table mapping each region to its kubectl context, ArgoCD cluster name, and Azure Application Insights instance.

ArgoCD's Model Context Protocol (MCP) server requires only a single URL regardless of the number of managed clusters, as each application's `destination.server` field identifies the target cluster. kubectl commands use the `--context` flag to target specific clusters without switching the global context. Azure Application Insights queries require region-specific `--app` and `--resource-group` parameters.

### 4.3 CLI Installer

The system is driven by a bash entry point (`ai-native-workflow`) that handles both installation and pipeline execution. The entry point is a thin (~220-line) dispatcher: it resolves its own location through any symlink chain, sources a set of cohesive library modules under `lib/` (`common`, `detect`, `pipeline-core`, `pipelines`, `install-global`, `install-project`, `status`, `uninstall`, `help`), then dispatches the subcommand. Agent and skill definitions live as standalone files under `agents/` and `skills/` and are installed by copying from source — a single source of truth, enforced by a drift test that fails if an installed copy diverges from its source. The library modules embed the hook scripts, the confidence-scoring tooling, and the configuration templates. The CLI supports:

- `ai-native-workflow install global` — installs hooks, skills, agents, and settings to `~/.claude/` and `~/.copilot/`
- `ai-native-workflow install project <path>` — generates a stack-tailored AGENTS.md, Copilot instructions, a tracked `docs/context/` directory (architecture, conventions, glossary, specs, sprint), and a gitignored `.anw/` runtime directory
- `ai-native-workflow run <pipeline> [arg]` — drives an end-to-end pipeline: `gitlab-feature` / `gitlab-incident` (Copilot CLI + Jira → MR), `github-feature` / `github-issue` (Claude Code → PR), plus `run status` / `run resume` for checkpointed state
- `ai-native-workflow status` — health check of global and project installation
- `ai-native-workflow detect <path>` — stack detection without installation
- `ai-native-workflow uninstall global|project [path]` — removes the installation

---

## 5. Discussion

### 5.1 Determinism vs. Flexibility

The central design tension is between enforcement and developer autonomy. Hard deterministic rules (hooks) guarantee compliance but can impede legitimate workflows (documentation-only commits, config changes). The `/skip-tdd` escape hatch resolves this by allowing bypass with accountability — the reason and timestamp are logged, and the bypass auto-expires after one commit.

We found that the three-mechanism model (hooks → skills → agents) maps naturally to the certainty spectrum: rules that must never be violated become hooks, workflows that should usually be followed become skills, and decisions requiring judgment become agent responsibilities.

### 5.2 Filesystem as Communication Channel

Using the filesystem rather than conversational context as the inter-agent communication channel has several advantages:

1. **Persistence**: Artifacts survive context window compaction and session restarts
2. **Auditability**: The git history records exactly what each agent produced
3. **Composability**: Any agent can read any other agent's output without being in the same conversation
4. **Human-readability**: spec.md and todo.md files are useful documentation even without AI agents

### 5.3 Limitations

- **Model availability**: The system requires access to Opus, Sonnet, and Haiku models. If a model tier is unavailable, the pipeline degrades.
- **Skill activation reliability**: Skills are probabilistic and may not activate autonomously in all cases. The `/plan` skill uses `disable-model-invocation: true` to require explicit invocation.
- **Copilot CLI model pinning**: Copilot CLI's agent frontmatter accepts a `model` field but expects a concrete model identifier and has no floating-alias equivalent to Claude Code's `opus`/`sonnet`/`haiku`. The Copilot-side agents therefore pin specific versions and must be updated manually when a better model ships — the one place the floating-tier strategy does not reach.
- **Single developer**: The pipeline is designed for solo workflows. Multi-developer orchestration would require additional coordination mechanisms.
- **No controlled evaluation**: The claimed benefits — reduced behavioral drift, sustained TDD discipline, lower context-switching cost — are motivated by design and observed informally in single-developer use. This paper reports no A/B comparison, no measured task-completion or defect-rate data, and no benchmarked skill-activation rate. Quantifying these effects against a non-orchestrated baseline is the most important direction for future work.

---

## 6. Conclusion

We have presented a practical architecture for AI-assisted test-driven development that separates enforcement, workflow, and reasoning into distinct mechanism types. The system enforces TDD and step-confidence compliance through deterministic hooks while maintaining developer flexibility through accountable bypass mechanisms. Eight specialized agents, each optimized for a specific role with an appropriate model tier, collaborate through filesystem artifacts in a pipeline that covers the full software lifecycle from requirements and design through implementation, review, and incident response. We present this as a design contribution: the architecture is operational and in single-developer use, but the paper makes no claim of controlled empirical evaluation.

The architecture is operational today using Claude Code and GitHub Copilot CLI, requires no custom infrastructure beyond the standard AI tool installations, and is distributed as a single self-contained installer script. By making TDD the path of least resistance rather than a discipline to maintain, the system addresses the fundamental challenge of sustaining engineering rigor in AI-accelerated development workflows.

---

## References

1. Beck, K. (2003). *Test-Driven Development: By Example*. Addison-Wesley.
2. Anthropic. (2025). Claude Code Hooks Documentation. https://code.claude.com/docs/en/hooks-guide
3. Anthropic. (2025). Claude Code Skills Documentation. https://code.claude.com/docs/en/skills
4. Anthropic. (2025). Claude Code Subagents Documentation. https://code.claude.com/docs/en/sub-agents
5. GitHub. (2026). GitHub Copilot CLI Documentation. https://docs.github.com/en/copilot/how-tos/copilot-cli
6. GitHub. (2025). Copilot Coding Agent Custom Instructions. https://github.blog/changelog/2025-08-28-copilot-coding-agent-now-supports-agents-md-custom-instructions/
7. Argoproj Labs. (2025). MCP Server for ArgoCD. https://github.com/argoproj-labs/mcp-for-argocd
8. Microsoft. (2026). Azure Application Insights CLI Reference. https://learn.microsoft.com/en-us/cli/azure/monitor/app-insights
9. Model Context Protocol. (2025). MCP Specification. https://modelcontextprotocol.io/specification/2025-11-25

---

*This paper describes a system developed for personal use and shared as open-source software. The author has no commercial affiliation with Anthropic or GitHub.*
