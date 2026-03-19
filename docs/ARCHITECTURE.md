# Workflow Architecture v3.0

For the full technical specification, see [PAPER.md](../PAPER.md).

## Three-Layer Architecture

```
┌────────────────────────────────────────────────────────────┐
│  ENFORCEMENT LAYER (Hooks — Deterministic)                 │
│  SessionStart → load context, detect stack                 │
│  PreToolUse   → TDD gate (blocks commits without tests)   │
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
│  requirements-engineer (Opus 4.6) → elicit, formalize reqs │
│  architect             (Opus 4.6) → design, spec, plan     │
│  tdd-developer         (Sonnet 4.6) → implement via TDD   │
│  qa                    (Haiku 4.5) → run affected tests    │
│  reviewer              (Sonnet 4.6) → code review + triage │
│  troubleshooter        (Opus 4.6) → incident investigation │
└────────────────────────────────────────────────────────────┘
```

## Pipelines

### Pipeline 1: GitLab Feature Development (Copilot CLI + Jira)

```
Jira Ticket
  │
  ├─ 1. requirements-engineer (Opus 4.6)
  │     Fetch Jira ticket → structured requirements
  │     → .context/specs/<id>-requirements.md
  │
  ├─ 2. qa (Haiku 4.5) — test planning
  │     Requirements → testing plan with scenarios
  │
  ├─ 3. architect (Opus 4.6)
  │     Requirements + test plan → spec.md + todo.md
  │     → User approves plan
  │
  ├─ 4. tdd-developer (Sonnet 4.6) — per step
  │     RED → GREEN → REFACTOR → commit
  │
  ├─ 5. qa (Haiku 4.5) — test execution
  │     Run affected tests → pass/fail
  │
  ├─ 6. reviewer (Sonnet 4.6) — MR review
  │     Review → triage → max 3 fix loops
  │
  └─ 7. glab mr create → merge request
```

**Platform**: GitLab + Copilot CLI + Jira
**Agents**: All run via `copilot --agent=<name>`

### Pipeline 2: GitLab Incident Response (Copilot CLI + Jira + Troubleshooter)

```
Jira Incident Ticket
  │
  ├─ 1. troubleshooter (Opus 4.6)
  │     Jira → ArgoCD → App Insights → kubectl
  │     → Key findings + next action
  │
  ├─ 2. USER DECISION POINT
  │     ├─ A: Document only → add findings to Jira → END
  │     └─ B: Fix the issue → continue
  │
  ├─ 3. tdd-developer (Sonnet 4.6)
  │     Step 1: reproduce bug as failing test
  │     Step 2+: implement fix
  │
  ├─ 4. qa (Haiku 4.5) → verify fix
  │
  ├─ 5. reviewer (Sonnet 4.6) → review MR
  │
  └─ 6. glab mr create + update Jira
```

**Platform**: GitLab + Copilot CLI + Jira + Azure
**Key feature**: User decides whether to fix or just document findings

### Pipeline 3: GitHub Feature Development (Claude LLMs)

```
specs.md / User Input
  │
  ├─ 1. requirements-engineer (Opus 4.6)
  │     Specs or input → structured requirements
  │     → .context/specs/<id>-requirements.md
  │
  ├─ 2. gh issue create
  │     Requirements → GitHub issue (feature request)
  │
  ├─ 3. architect (Opus 4.6)
  │     Requirements → spec.md + todo.md
  │     → User approves plan
  │
  ├─ 4. tdd-developer (Sonnet 4.6) — per step
  │     RED → GREEN → REFACTOR → commit
  │
  ├─ 5. qa (Haiku 4.5) → run affected tests
  │
  ├─ 6. reviewer (Sonnet 4.6) — PR review
  │     Review → triage → max 3 fix loops
  │
  └─ 7. gh pr create → pull request (Closes #issue)
```

**Platform**: GitHub + Claude Code
**Agents**: All run as Claude Code subagents

## Generic Pipeline (Legacy)

```
/plan "add user authentication"
  │
  ├─ 1. architect (Opus 4.6)
  │     Reads codebase → creates spec.md + todo.md
  │     Each step: what to test, what to implement, which files
  │     → User approves the plan
  │
  ├─ 2. tdd-developer (Sonnet 4.6) — per step
  │     RED: writes failing tests → commits
  │     GREEN: minimum code → commits
  │     REFACTOR: improve → commits
  │
  ├─ 3. qa (Haiku 4.5)
  │     Runs only affected unit + integration tests
  │     Reports pass/fail with exact errors
  │
  ├─ 4. reviewer (Sonnet 4.6)
  │     Reviews against checklist
  │     🔴 MUST FIX / 🟡 SHOULD FIX / 🟢 SUGGESTION
  │     → User triages: [F]ix / [T]ech debt / [I]gnore
  │
  └─ 5. Fix loop (max 3) → then next step
```

## Agent Roster

| Agent | Model | Role | Writes Code? |
|-------|-------|------|-------------|
| requirements-engineer | Opus 4.6 | Elicit & formalize requirements | No |
| architect | Opus 4.6 | Design solutions, create plans | No |
| tdd-developer | Sonnet 4.6 | Implement via strict TDD | Yes |
| qa | Haiku 4.5 | Run tests, create test plans | No |
| reviewer | Sonnet 4.6 | Code review, quality gate | No |
| troubleshooter | Opus 4.6 | Incident investigation, diagnosis | No |

## Key Design Decisions

- **Hooks for enforcement**: TDD gate is a shell script (exit code 2 = block), not a prompt instruction
- **Filesystem as message bus**: Agents communicate through spec.md/todo.md files, not conversation
- **One step at a time**: tdd-developer executes exactly one step per invocation
- **User in the loop**: Reviewer presents findings, user triages — no automatic overrides
- **Model tiering**: Opus for design/diagnosis, Sonnet for implementation/review, Haiku for test execution
- **Pipeline per platform**: GitLab uses Copilot CLI agents, GitHub uses Claude Code subagents
- **Requirements first**: requirements-engineer runs before architect to ensure clear, testable inputs
- **Decision points**: Incident pipeline lets user choose between documenting findings or implementing a fix
