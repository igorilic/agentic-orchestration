# Contributing

Thanks for contributing to **agentic-orchestration**. This is a bash-based,
test-driven harness, so the bar is: every change ships with passing tests.

## Prerequisites

- `bash` (the suite runs on macOS bash 3.2 and modern bash — keep both happy)
- [`bats-core`](https://github.com/bats-core/bats-core) — `brew install bats-core`
  or `npm install -g bats`
- `jq`, `git`, `ripgrep` (`rg`) — the suite uses all three
- On macOS, GNU `timeout` (`brew install coreutils` → `gtimeout`) for one
  non-interactive test
- Optional: `gh` / `glab` CLIs (for the PR/MR skills), `copilot` (Copilot track)

## Running the tests

```bash
make test                              # full suite (bats tests/)
make test-file FILE=tests/confidence.bats
make lint                              # bash -n on the installer, hooks, scripts
```

CI (`.github/workflows/test.yml`) runs the same suite on ubuntu + macOS for
every push and PR. **PRs must be green.** macOS is in the matrix on purpose: it
runs bash 3.2, where `set -u` empty-array expansions (`"${arr[@]}"`) crash — a
class of bug that won't show up on modern bash.

## How the harness is structured

| Layer | Where | Guarantee |
|-------|-------|-----------|
| **Hooks** | `hooks/*.sh` | deterministic — block actions via exit code / `permissionDecision` |
| **Skills** | `skills/*/SKILL.md` | model-loaded workflow instructions |
| **Agents** | `agents/{claude-code,copilot-cli}/` | scoped LLM specialists |
| **Installer + runner** | `ai-native-workflow` | installs the above + drives the pipelines |

**Single source of truth:** agents and skills are installed via `cp` from
`agents/`/`skills/` — the installer no longer embeds heredoc copies. Edit the
source file; the `install global … byte-match source (no drift)` test enforces
that the installed copy matches. (The 3 `pipeline-*` skills are the one
exception: the Claude side ships an abbreviated `claude --agent=` stub.)

When you add an agent or skill, drop the file under `agents/…` or `skills/…`
and add a `check_file` line to `show_status` in `ai-native-workflow`.

## Path conventions (important, and easy to trip on)

- `docs/context/specs/` — **tracked** spec/todo/requirements artifacts (reviewed
  in PRs). Agents write specs here as `<id>-spec.md` / `<id>-todo.md`.
- `.context/` — **gitignored** runtime state: pipeline state, audit log, and the
  per-spec confidence log `.context/specs/<id>-confidence.jsonl`.

Two near-identical roots; don't cross them. The confidence log is local-only
(gitignored), not committed.

## Commit & PR conventions

- **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`…).
- Branch off `main`; never commit to `main` directly.
- The **TDD gate** (`hooks/tdd-gate.sh`) blocks `git commit` unless a test file
  is staged. For docs/config-only commits, bypass with `/skip-tdd "<reason>"`
  (logged) — never for code.
- Reference issues in the commit/PR body (`Closes #N`).

## Adding a skill

A skill is a directory `skills/<name>/SKILL.md` with YAML frontmatter
(`name`, `description`, optional `disable-model-invocation: true` for
slash-only skills). It's auto-copied to both `~/.claude` and `~/.copilot` on
install. Give it a clear `Triggers on:` list in the description so it
auto-activates reliably.
