# Copilot Instructions

> Repository-wide instructions for GitHub Copilot agent mode.
> For detailed rules, see AGENTS.md at the project root.

## TDD Workflow (Non-Negotiable)
1. Write failing tests FIRST — your first output must be test code
2. Implement minimum code to pass tests
3. Refactor while keeping tests green

## Before Coding
- Check `.context/specs/` for feature specifications
- Read `.context/CONVENTIONS.md` for stack patterns
- Read `.context/ARCHITECTURE.md` for system context

## When Uncertain
Stop and ask. Present options with tradeoffs.

## Commit Messages
Conventional Commits: `<type>(<scope>): <description>`
Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `ci`, `perf`

## Code Standards
- Explicit over implicit
- Small functions (< 20 lines)
- Meaningful names (purpose, not implementation)
- Fail fast (validate early, return early)
- No magic numbers
- Type annotations on all signatures
