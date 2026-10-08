# Contributing

Thanks for contributing to **agentic-orchestration**. It's a bash harness that is mostly
enforcement, so the bar is high: every behavior change ships with a test that failed first.

## Prerequisites

- `bash` (the suite runs on macOS bash 3.2 and modern bash; keep both happy)
- [`bats-core`](https://github.com/bats-core/bats-core): `brew install bats-core` or `npm install -g bats`
- `jq`, `git` and `ripgrep` (`rg`)
- Optional: `shellcheck`; `claude` / `copilot` for `make smoke`

## Running the tests

```bash
make test                              # the full suite (also this repo's .anw/verify)
make test-file FILE=tests/guard.bats   # one file
make lint                              # bash -n on the CLI, lib/ and hooks/
make smoke                             # live canaries against your installed harness (real model calls)
```

CI (`.github/workflows/test.yml`) runs the suite on ubuntu and macOS for every push and PR, and
**PRs must be green**. macOS is in the matrix on purpose: bash 3.2 crashes on `set -u` empty-array
expansions, and a mid-test `[[ … ]]` or `! cmd` never fails a test there. So end those with
`|| false`.

The suite runs inside agent sandboxes. Use `mktemp` with a template under `$TMPDIR`, never a bare
`/tmp`; `tests/tmpdir-hygiene.bats` enforces it.

## Layout

| Path | What |
|---|---|
| `hooks/guard.sh`, `hooks/verify.sh` | the two hooks, shared by Claude Code and Copilot CLI |
| `skills/*/SKILL.md` | workflow skills (`plan`, `check`, `verify`, `incident`, `pr`) and knowledge skills |
| `config/claude-settings.json` | the policy merged into `~/.claude/settings.json`, and the pipelines' deny list |
| `instructions/` | the global instruction blocks for both tools |
| `ai-native-workflow` + `lib/*.sh` | the CLI: install, trust, doctor, pipelines |
| `tests/` | bats tests; `tests/smoke.sh` holds the live canaries |

`ai-native-workflow` is a thin dispatcher. It resolves its own path through symlinks, sources the
`lib/*.sh` modules and runs the subcommand. The modules only define functions and use the
constants the dispatcher sets.

## Changing the harness

- **Hooks:** add a contract test to `tests/guard.bats` using the payload shape the tool really
  sends, not an environment variable. Hooks must fail closed, and `guard.sh` must never emit `allow`.
- **The verify sandbox profile** must stay in sync with the sandbox settings; `tests/verify-sandbox.bats` checks it.
- **Skills:** keep workflow skills at 30 lines or less, and the global instructions at 25 or less. A
  skill is a directory `skills/<name>/SKILL.md` with frontmatter (`name`, `description`, and
  `disable-model-invocation: true` for slash-only skills).
- **Installed copies:** `install global` copies hooks and skills rather than linking them, so your
  edits only go live after `make install`. Until then, `doctor` reports drift.
- **After a model or tool update:** run `make smoke` and record the result in ADR-003.

Mutation-check new tests: seed a mutant into a scratch copy and make sure the test goes red. A
test that can't fail proves nothing.

## Path conventions

- `docs/context/`: **tracked** context (the sprint board and the specs and plans under `specs/`),
  reviewed in PRs.
- `.anw/verify`: **tracked**, the repo's finish line.
- `.anw/*` (everything else): **gitignored** runtime state (pipeline state, stage transcripts).

## Commits and PRs

- **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, …).
- Branch off `main`, and never commit to `main` directly.
- If a commit deletes or weakens a test, or changes code without one, the guard asks you to
  approve. Approve only if it's intentional (a pure refactor, a test that was really wrong), and
  say why in the commit message.
- Reference issues in the commit or PR body (`Closes #N`).
