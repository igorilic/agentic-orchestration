# AGENTS.md

> Cross-tool agent instructions. Read by Claude Code, GitHub Copilot, and other AI agents.

## Two Tracks: Production and Exploration

### Production (`/plan`)
For tickets, features, bug fixes, anything that ships. Pipeline:
**requirements-engineer → architect → tdd-developer → qa → reviewer**
(troubleshooter replaces requirements-engineer + architect for incidents).

### Exploration (`/explore`, `/brainstorm`)
For spikes, prototypes, API learning, vague ideas. Throwaway code under
`spikes/<topic>/` (gitignored). The TDD gate skips spike-only commits.
End with `FINDINGS.md`. To promote findings to production, re-enter
via `/plan`.

### When to skip both
Trivial only: typo, single-line config, comment-only, local rename.
Anything touching logic, types, public APIs, or 2+ files is non-trivial.
When in doubt, ask.

## Shorthand

- `go` — proceed with the proposed plan as-is
- `fix` — triage and address the issues just identified
- `f` / `t` / `i` — per-item triage on a numbered list:
  - `f` = fix now
  - `t` = log to tech debt (append to `docs/context/CURRENT_SPRINT.md`)
  - `i` = ignore, not a real issue
- Positional mapping: `f t i f` against a 4-item list maps 1→f, 2→t, 3→i, 4→f.

## Tool Preferences (decision order; negative rules are hard)

- Search content: `rg`. Never `grep` or `find | xargs grep`.
- Find files: `fd`. Never `find`.
- JSON: `jq`. Never sed/awk on JSON.
- CSV/TSV: `python` (csv module) or `mlr`. Never awk on CSV.
- Multi-step text processing: Python script, not chained sed/awk.
- Source-code edits: editor tool, never `sed -i`.
- Python one-offs: `uv run --with <pkg> python ...`. Never `pip install` to system.
- Git: never `git add -A` / `git add .`; list files. Never `--force`,
  use `--force-with-lease`. Never amend or rebase commits not yours.

## Core Rules

### 1. TDD is Mandatory
Every code change follows RED → GREEN → REFACTOR:
1. **RED**: Write failing test(s) FIRST. Run them. Confirm failure.
2. **GREEN**: Write MINIMUM code to pass. One test at a time.
3. **REFACTOR**: Improve code while keeping tests green.

Your first output for any feature request MUST be test code.
To bypass: use `/skip-tdd` with a reason (logged for accountability).

### 2. Stop and Ask When Uncertain
Do NOT guess. Stop and present options when:
- Requirements are ambiguous
- Multiple valid approaches exist
- Spec contradicts existing code
- Business logic is unclear

### 3. Document As You Go
- Update `docs/context/CURRENT_SPRINT.md` when task status changes
- Note architecture decisions in commit messages
- Flag documentation that needs updating

## Before Starting Any Work
1. Read the spec in `docs/context/specs/` if one exists
2. Scan `docs/context/ARCHITECTURE.md` for system context
3. Check `docs/context/CONVENTIONS.md` for stack patterns
4. Identify ALL affected components before writing code

## Commit Messages
Conventional Commits: `<type>(<scope>): <description>`
Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `ci`, `perf`

## Test Organization
```
tests/
├── unit/           # Fast, isolated, mocked dependencies
├── integration/    # Real DB via TestContainers
└── fixtures/       # Shared test data
```

## Stack Conventions
<!-- The installer tailors this section to your detected stack -->

### Database (PostgreSQL)
- **Tables**: snake_case, plural (`users`, `order_items`)
- **Primary keys**: `id` (UUID or serial)
- **Foreign keys**: `{table_singular}_id`
- **Migrations**: Always reversible, one concern per migration

## Error Reporting
```
❌ ERROR: [What happened]
Context: [What was being attempted]
Location: [File/function]
Possible causes:
1. [Cause and fix]
Suggested action: [What to do next]
```

## Session End Protocol
1. Ensure all tests pass
2. Commit pending changes
3. Update `docs/context/CURRENT_SPRINT.md`
4. Use `/session-report` to generate Obsidian report
