# Workflow Architecture v2.1

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
│  /plan    → pipeline orchestration entry point             │
│  /tdd     → RED→GREEN→REFACTOR cycle                      │
│  /ticket  → Jira/GitHub issue → spec + test stubs          │
│  /adr     → Architecture Decision Record                   │
│  /pr      → Pull request creation (gh/glab)                │
│  /clusters → Multi-region reference data                   │
├────────────────────────────────────────────────────────────┤
│  REASONING LAYER (Agents — Specialized)                    │
│  architect       (Opus 4.6)   → design, spec, plan        │
│  tdd-developer   (Sonnet 4.6) → implement via TDD         │
│  qa              (Haiku 4.5)  → run affected tests         │
│  reviewer        (Sonnet 4.6) → code review + triage       │
│  troubleshooter  (Opus 4.6)   → incident investigation     │
└────────────────────────────────────────────────────────────┘
```

## Agent Pipeline

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

## Incident Response

```
troubleshooter (Opus 4.6)
  → Jira ticket context
  → ArgoCD app status (EMEA/APAC/NAM)
  → Azure App Insights (exceptions, failures, traces)
  → kubectl pod logs per region
  → Root cause diagnosis
  → TDD fix plan (Step 1 = reproduce the bug)
  → Hand off to tdd-developer
```

## Key Design Decisions

- **Hooks for enforcement**: TDD gate is a shell script (exit code 2 = block), not a prompt instruction
- **Filesystem as message bus**: Agents communicate through spec.md/todo.md files, not conversation
- **One step at a time**: tdd-developer executes exactly one step per invocation
- **User in the loop**: Reviewer presents findings, user triages — no automatic overrides
- **Model tiering**: Opus for design/diagnosis, Sonnet for implementation/review, Haiku for test execution
