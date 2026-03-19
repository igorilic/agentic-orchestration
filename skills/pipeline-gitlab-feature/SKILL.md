---
name: pipeline-gitlab-feature
description: >
  Full feature development pipeline for GitLab repositories using
  Copilot CLI agents and Jira integration. Takes a Jira item through
  requirements engineering, test planning, architecture, TDD development,
  testing, and MR review.
  Triggers on: gitlab pipeline, gitlab feature, copilot pipeline.
disable-model-invocation: true
---

## Pipeline: GitLab Feature Development (Copilot CLI + Jira)

```
Jira Ticket
  │
  ├─ 1. requirements-engineer (Opus 4.6)
  │     Fetch Jira ticket → analyze → structured requirements
  │     → .context/specs/<id>-requirements.md
  │     → User validates requirements
  │
  ├─ 2. qa (Haiku 4.5) — test planning
  │     Read requirements → create testing plan
  │     → Unit, integration, edge case scenarios
  │     → .context/specs/<id>-testplan.md
  │
  ├─ 3. architect (Opus 4.6)
  │     Read requirements + test plan → design solution
  │     → .context/specs/<id>-spec.md + <id>-todo.md
  │     → User approves plan
  │
  ├─ 4. tdd-developer (Sonnet 4.6) — per step
  │     RED: write failing tests → commit
  │     GREEN: minimum code → commit
  │     REFACTOR: improve → commit
  │
  ├─ 5. qa (Haiku 4.5) — test execution
  │     Run affected unit + integration tests
  │     Report pass/fail with exact errors
  │
  ├─ 6. reviewer (Sonnet 4.6) — MR review
  │     Review code against requirements + conventions
  │     🔴 MUST FIX / 🟡 SHOULD FIX / 🟢 SUGGESTION
  │     → User triages: [F]ix / [T]ech debt / [I]gnore
  │     → Max 3 fix loops per step
  │
  └─ 7. Create MR (glab mr create)
        Push branch → create merge request → link Jira ticket
```

### Prerequisites
- GitLab repository with `glab` CLI configured
- Jira MCP server or `jira` CLI configured
- GitHub Copilot CLI installed (`copilot` command available)

### Usage

#### Step 1: Start with a Jira ticket
```bash
copilot --agent=requirements-engineer --prompt "Analyze Jira ticket PROJ-123"
```
Review the generated `.context/specs/PROJ-123-requirements.md`.
Validate acceptance criteria and assumptions.

#### Step 2: Create test plan
```bash
copilot --agent=qa --prompt "Create test plan from PROJ-123-requirements.md"
```

#### Step 3: Design the solution
```bash
copilot --agent=architect --prompt "Design solution for PROJ-123 using requirements and test plan"
```
Review the spec and todo. Approve before proceeding.

#### Step 4: Implement step by step
```bash
copilot --agent=tdd-developer --prompt "Step 1 of PROJ-123-todo.md"
```

#### Step 5: Test after each step
```bash
copilot --agent=qa --prompt "Run tests for Step 1 of PROJ-123"
```

#### Step 6: Review after each step
```bash
copilot --agent=reviewer --prompt "Review Step 1 of PROJ-123"
```
Triage findings: [F]ix / [T]ech debt / [I]gnore.

#### Step 7: Create Merge Request
```bash
glab mr create --title "feat(scope): description" --description "Closes PROJ-123"
```
Or use the `/pr` skill for auto-generated MR description.

### Notes
- Each step can be run independently — agents communicate via `.context/specs/` files
- The tdd-developer → qa → reviewer cycle repeats for each step in the todo
- Max 3 fix loops per step, then remaining issues go to tech debt
- All agents use Copilot CLI (`copilot --agent=<name>`)
