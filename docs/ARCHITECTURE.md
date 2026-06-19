# Workflow Architecture v3.0

For the full technical specification, see [PAPER.md](../PAPER.md).

## Three-Layer Architecture

```
┌────────────────────────────────────────────────────────────┐
│  ENFORCEMENT LAYER (Hooks — Deterministic)                 │
│  SessionStart → load context, detect stack                 │
│  PreToolUse   → TDD gate (blocks commits without tests)   │
│  PreToolUse   → Confidence gate (blocks PR/MR on RED)     │
│  Notification → macOS native alerts                        │
├────────────────────────────────────────────────────────────┤
│  WORKFLOW LAYER (Skills — Probabilistic)                   │
│  /plan                    → generic pipeline orchestration │
│  /pipeline-gitlab-feature → GitLab + Copilot + Jira       │
│  /pipeline-gitlab-incident→ GitLab + Troubleshooter + Jira│
│  /pipeline-github-feature → GitHub + Claude LLMs          │
│  /tdd     → RED→GREEN→REFACTOR cycle                      │
│  /ticket  → Jira/GitHub issue → spec + test stubs          │
│  /adr     → Architecture Decision Record                   │
│  /pr      → Pull request creation (gh/glab)                │
│  /clusters → Multi-region reference data                   │
├────────────────────────────────────────────────────────────┤
│  REASONING LAYER (Agents — Specialized)                    │
│  requirements-engineer (Opus-tier) → elicit, formalize reqs │
│  architect             (Opus-tier) → design, spec, plan     │
│  tdd-developer         (Sonnet-tier) → implement via TDD   │
│  qa                    (Haiku-tier) → run affected tests    │
│  reviewer              (Sonnet-tier) → code review + triage │
│  diff-reviewer         (Opus-tier) → PR/MR review + comment │
│  troubleshooter        (Opus-tier) → incident investigation │
└────────────────────────────────────────────────────────────┘
```

## Pipelines

### Pipeline 1: GitLab Feature Development (Copilot CLI + Jira)

```
Jira Ticket
  │
  ├─ 1. requirements-engineer (Opus-tier)
  │     Fetch Jira ticket → structured requirements
  │     → docs/context/specs/<id>-requirements.md
  │
  ├─ 2. qa (Haiku-tier) — test planning
  │     Requirements → testing plan with scenarios
  │
  ├─ 3. architect (Opus-tier)
  │     Requirements + test plan → spec.md + todo.md
  │     → User approves plan
  │     → emits spec event to <id>-confidence.jsonl
  │
  ├─ 4. tdd-developer (Sonnet-tier) — per step
  │     RED → GREEN → REFACTOR → commit
  │
  ├─ 5. qa (Haiku-tier) — test execution
  │     Run affected tests → pass/fail
  │     → emits qa event
  │
  ├─ 6. reviewer (Sonnet-tier) — MR review
  │     Review → triage → max 3 fix loops
  │     → emits review event
  │     → confidence per-step verdict (pauses on YELLOW/RED)
  │
  ├─ 7. confidence (aggregate verdict — hook enforces RED at MR step)
  │
  ├─ 8. glab mr create → merge request (body includes ## Confidence section)
  │
  └─ 9. diff-reviewer (Opus-tier) — whole-MR diff review (optional)
        Review diff + Jira AC → rank by severity → preview + confirm
        → post inline comments + threads + verdict via glab
```

**Platform**: GitLab + Copilot CLI + Jira
**Agents**: All run via `copilot --agent=<name>`

### Pipeline 2: GitLab Incident Response (Copilot CLI + Jira + Troubleshooter)

```
Jira Incident Ticket
  │
  ├─ 1. troubleshooter (Opus-tier)
  │     Jira → ArgoCD → App Insights → kubectl
  │     → Key findings + next action
  │
  ├─ 2. USER DECISION POINT
  │     ├─ A: Document only → add findings to Jira → END
  │     └─ B: Fix the issue → continue
  │
  ├─ 3. tdd-developer (Sonnet-tier)
  │     Step 1: reproduce bug as failing test
  │     Step 2+: implement fix
  │
  ├─ 4. qa (Haiku-tier) → verify fix
  │     → emits qa event
  │
  ├─ 5. reviewer (Sonnet-tier) → review MR
  │     → emits review event
  │     → confidence per-step verdict (pauses on YELLOW/RED)
  │
  ├─ 6. confidence (aggregate verdict — hook enforces RED at MR step)
  │
  └─ 7. glab mr create + update Jira (body includes ## Confidence section)
```

**Platform**: GitLab + Copilot CLI + Jira + Azure
**Key feature**: User decides whether to fix or just document findings

### Pipeline 3: GitHub Feature Development (Claude LLMs)

```
specs.md / User Input
  │
  ├─ 1. requirements-engineer (Opus-tier)
  │     Specs or input → structured requirements
  │     → docs/context/specs/<id>-requirements.md
  │
  ├─ 2. gh issue create
  │     Requirements → GitHub issue (feature request)
  │
  ├─ 3. architect (Opus-tier)
  │     Requirements → spec.md + todo.md
  │     → User approves plan
  │     → emits spec event to <id>-confidence.jsonl
  │
  ├─ 4. tdd-developer (Sonnet-tier) — per step
  │     RED → GREEN → REFACTOR → commit
  │
  ├─ 5. qa (Haiku-tier) → run affected tests
  │     → emits qa event
  │
  ├─ 6. reviewer (Sonnet-tier) — PR review
  │     Review → triage → max 3 fix loops
  │     → emits review event
  │     → confidence per-step verdict (pauses on YELLOW/RED)
  │
  ├─ 7. confidence (aggregate verdict — hook enforces RED at PR step)
  │
  ├─ 8. gh pr create → pull request (Closes #issue; body includes ## Confidence section)
  │
  └─ 9. diff-reviewer (Opus-tier) — whole-PR diff review (optional)
        Review diff + issue AC → rank by severity → preview + confirm
        → post inline comments + threads + verdict via gh
```

**Platform**: GitHub + Claude Code
**Agents**: All run as Claude Code subagents

## Generic Pipeline (Legacy)

```
/plan "add user authentication"
  │
  ├─ 1. architect (Opus-tier)
  │     Reads codebase → creates spec.md + todo.md
  │     Each step: what to test, what to implement, which files
  │     → User approves the plan
  │     → emits spec event to <id>-confidence.jsonl
  │
  ├─ 2. tdd-developer (Sonnet-tier) — per step
  │     RED: writes failing tests → commits
  │     GREEN: minimum code → commits
  │     REFACTOR: improve → commits
  │
  ├─ 3. qa (Haiku-tier)
  │     Runs only affected unit + integration tests
  │     Reports pass/fail with exact errors
  │     → emits qa event
  │
  ├─ 4. reviewer (Sonnet-tier)
  │     Reviews against checklist
  │     🔴 MUST FIX / 🟡 SHOULD FIX / 🟢 SUGGESTION
  │     → User triages: [F]ix / [T]ech debt / [I]gnore
  │     → emits review event
  │     → confidence per-step verdict (pauses on YELLOW/RED)
  │
  └─ 5. Fix loop (max 3) → then next step
```

## Agent Roster

| Agent | Model | Role | Writes Code? |
|-------|-------|------|-------------|
| requirements-engineer | Opus-tier | Elicit & formalize requirements | No |
| architect | Opus-tier | Design solutions, create plans | No |
| tdd-developer | Sonnet-tier | Implement via strict TDD | Yes |
| qa | Haiku-tier | Run tests, create test plans | No |
| reviewer | Sonnet-tier | Per-step code review, quality gate | No |
| diff-reviewer | Opus-tier | Whole-PR/MR diff review; posts inline comments + threads | No (posts review comments) |
| troubleshooter | Opus-tier | Incident investigation, diagnosis | No |

## Path Conventions

The project uses a deliberate split between tracked spec artifacts and runtime state:

| Path | Tracked in git? | Contents |
|------|----------------|----------|
| `docs/context/` | Yes | Sprint board (`CURRENT_SPRINT.md`), specs, todos, requirements, test plans, plus installer-seeded `ARCHITECTURE.md` / `CONVENTIONS.md` / `GLOSSARY.md` (tracked in consumer projects, not generated in this repo) |
| `.anw/specs/*.jsonl` | No (gitignored) | Confidence event logs (runtime state) |
| `.anw/.pipeline-state` | No (gitignored) | Pipeline run state |
| `.anw/.pipeline-audit.log` | No (gitignored) | Audit trail |

The `docs/context/` path is version-controlled so spec reviews happen in pull requests. The `.context/` runtime artifacts are gitignored to prevent churn from pipeline state files.

## Symmetric Harness (COP-1)

`install global` writes a symmetric set of artifacts for both Claude Code
(`~/.claude/`) and GitHub Copilot CLI (`~/.copilot/`). Skills, agents, and
global instructions are identical in purpose across both tools; pipeline skills
have `claude --agent=` invocations rewritten to `copilot --agent=` in the
Copilot copy. There is one intentional asymmetry: Claude Code hooks are
installed globally and fire on every session, while Copilot CLI scopes hooks
per-repository — Copilot repo-scope hooks are installed by `install project`
and ship via COP-2 (see Hook Surfaces below).

## Hook Surfaces

The system enforces quality gates through two distinct hook surfaces:

### Claude Code global hooks (`~/.claude/hooks/`)

| Hook | Trigger | Gate |
|------|---------|------|
| `session-start.sh` | Session open | Load context, detect stack |
| `tdd-gate.sh` | `PreToolUse` | Blocks `git commit` without staged test files |
| `confidence-gate.sh` | `PreToolUse` | Blocks `gh pr create` / `glab mr create` on RED confidence |

These are **user-global** — installed once and apply to all projects opened with Claude Code.

### Copilot CLI per-project hooks (`.github/hooks/`)

| File | Purpose |
|------|---------|
| `copilot-cli-dispatcher.sh` | Single `preToolUse` entry point; enforces both TDD + confidence gates |
| `scripts/confidence.sh` | Vendored scorer copy (self-contained; no dependency on `~/.claude/`) |
| `copilot-cli-policy.json` | Registers the dispatcher; merged idempotently on `install project` |
| `README.md` | Explains the hooks, bypass paths, and audit trail to contributors |

These are **per-project** because Copilot CLI does not support user-global hooks — only
repository-scoped ones registered in `copilot-cli-policy.json`.

**Asymmetry summary**:

| Dimension | Claude Code | Copilot CLI |
|-----------|-------------|-------------|
| Scope | Global (`~/.claude/hooks/`) | Per-project (`.github/hooks/`) |
| TDD gate | `tdd-gate.sh` | `copilot-cli-dispatcher.sh` (combined) |
| Confidence gate | `confidence-gate.sh` | `copilot-cli-dispatcher.sh` (combined) |
| Scorer path | `~/.claude/scripts/confidence.sh` | `.github/hooks/scripts/confidence.sh` (vendored) |
| Hook registration | `~/.claude/settings.json` | `.github/hooks/copilot-cli-policy.json` |

## Key Design Decisions

- **Hooks for enforcement**: TDD gate is a shell script (exit code 2 = block), not a prompt instruction
- **Filesystem as message bus**: Agents communicate through spec.md/todo.md files, not conversation
- **One step at a time**: tdd-developer executes exactly one step per invocation
- **User in the loop**: Reviewer presents findings, user triages — no automatic overrides
- **Model tiering**: Opus for design/diagnosis, Sonnet for implementation/review, Haiku for test execution
- **Pipeline per platform**: GitLab uses Copilot CLI agents, GitHub uses Claude Code subagents
- **Requirements first**: requirements-engineer runs before architect to ensure clear, testable inputs
- **Decision points**: Incident pipeline lets user choose between documenting findings or implementing a fix
- **Symmetric harness**: Skills/agents/instructions are symmetric across Claude Code and Copilot CLI; hooks are Claude-global, Copilot repo-scope (per-project via `install project`)
- **Copilot hooks are per-project**: Copilot CLI lacks user-global hook support; the dispatcher is vendored into each repo so enforcement is self-contained and portable
