# AGENTS.md

> Cross-tool agent instructions. Read by Claude Code, GitHub Copilot, and other AI agents.

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
- Update `.context/CURRENT_SPRINT.md` when task status changes
- Note architecture decisions in commit messages
- Flag documentation that needs updating

## Before Starting Any Work
1. Read the spec in `.context/specs/` if one exists
2. Scan `.context/ARCHITECTURE.md` for system context
3. Check `.context/CONVENTIONS.md` for stack patterns
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
3. Update `.context/CURRENT_SPRINT.md`
4. Use `/session-report` to generate Obsidian report
