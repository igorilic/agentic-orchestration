# Agentic Orchestration

A small, verified harness for **Claude Code** and **GitHub Copilot CLI**: two fail-closed hooks,
five workflow skills, an OS-sandboxed policy and a trusted per-repo finish line. The tools' own
agents do the work; this repo makes sure the work is checked and contained.

## Why

Coding agents with tests in reach will sometimes make the check pass instead of making the code
right, especially when the task is impossible or the check is weak. Prompts lower that rate but
don't remove it. So the rules that must hold are enforced outside the agent's reach, and the agent
gets an honest way out: `BLOCKED: <evidence>`.

The first version of this project used eight custom agents and a hook-enforced TDD gate. An audit
found that the Claude-side gates had never fired (see the erratum in [PAPER.md](PAPER.md)). This
version replaces all of it with the native features of both tools and checks the enforcement
against their real hook payloads.

## How it works

| Mechanism | What it does |
|---|---|
| `guard.sh` (before every command and edit) | Denies hook bypasses (`--no-verify`, …), nested agents without permissions, and writes to the harness itself. **Asks you** before a commit that deletes or weakens tests or changes code with no test, before a new dependency, and before CI or instruction edits. |
| `verify.sh` (when an editing turn ends) | Runs the repo's `.anw/verify`, your full fast suite, but only a script you approved by hash and path, and on macOS inside a sandbox. While it's red, the agent keeps working or ends with `BLOCKED:`. |
| Settings (merged into Claude's `settings.json`) | OS sandbox with an egress allowlist; secrets unreadable; asks before push, PR/MR and comments; denies force-push and mutating cluster commands. In Copilot, turn its sandbox on with `/sandbox`. |
| Skills | `/plan`, `/check` (fresh context, read-only), `/verify`, `/incident` (read-only), `/pr` |
| Agents | Native only: the main session, plan mode, built-in subagents. No custom agents. |

Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) ·
decision: [ADR-003](docs/decisions/ADR-003-native-first-harness.md).

## Quick start

```bash
make install                      # = ./ai-native-workflow install global (both tools)
ai-native-workflow doctor         # exits 1 on drift, a custom agent or an untrusted finish line

cd ~/code/my-project
ai-native-workflow install project .   # writes .anw/verify, shows it, asks you to trust it
```

`install global` merges the policy into your settings and keeps your own keys, skills and files.
Anything an older version installed moves to `<home>/anw-backup/<stamp>/`. To try it in a sandbox
first, set `CLAUDE_HOME` and `COPILOT_HOME` to empty directories.

## Day to day

- **Small change (1–2 files):** just ask. The agent writes a failing test, then the fix. The hooks
  gate the commit and the end of the turn. Then `/check`, then `/pr`.
- **Feature or unclear work:** `/plan PROJ-123` writes `docs/context/specs/PROJ-123.md`, and you
  approve it. Implement one step per session ("implement step 1 of …"), committing each. Then
  `/check` and `/pr`.
- **Incident:** `/incident PROJ-456` investigates read-only and writes a report. You decide what to
  post. Fix in a fresh session.
- **Review a PR/MR:** the built-in `/code-review` (Claude) or `/review` (Copilot).
- **Copilot:** plan in plan mode, and follow `/check` with `/rubber-duck`.

Edited `.anw/verify`? Review it, then `ai-native-workflow trust`. Until then it doesn't run.

## Pipelines

The same flow, headless. Each stage is a fresh `claude -p` or `copilot -p` session with no bypass
flags. In Claude, planning and `/check` run Opus-tier and each step Sonnet-tier, through floating
aliases, never pinned versions; Copilot stages use its session default. Only the script pushes,
opens the PR/MR or posts to Jira, each on your yes (Enter means no).

```bash
ai-native-workflow run github-feature specs.md   # Claude: /plan → approve → steps → /check → verify → PR
ai-native-workflow run github-issue 42           # planned from issue #42; the PR closes it
ai-native-workflow run gitlab-feature PROJ-123   # Copilot + Jira ticket → MR
ai-native-workflow run gitlab-incident PROJ-456  # Copilot: read-only /incident → you decide → fix
ai-native-workflow run status                    # or: run resume
```

## What gets installed

| Where | What |
|---|---|
| `~/.claude/` | `hooks/guard.sh`, `hooks/verify.sh`, the policy merged into `settings.json`, a managed block in `CLAUDE.md`, `skills/` |
| `~/.copilot/` | `hooks/guard.sh`, `hooks/verify.sh`, `~/.copilot/hooks/anw.json` wiring them, a managed block in `~/.copilot/copilot-instructions.md`, `~/.copilot/skills/` |
| your project | `.anw/verify` (tracked; `.gitignore` gets `.anw/*` + `!.anw/verify`), a short `AGENTS.md` that `CLAUDE.md` imports, `docs/context/`, `docs/decisions/` |

`.anw/verify` comes from the detected stack. A Makefile `test:` target wins; otherwise
`go test ./...`, `cargo test`, `dotnet test`, `uv run pytest` / `poetry run pytest` /
`python3 -m pytest`, `pnpm test` / `yarn test` / `bun run test` / `npm test`, or `swift test`.
An existing script is never overwritten.

## Keeping it honest

- `make test` runs the bats suite. The hooks are driven with each tool's real payloads.
- `make smoke` (`ai-native-workflow doctor --smoke`) runs live canaries against the installed
  harness: bypasses, containment, an honest fix, an impossible finish line ×3, and `/check` on a
  gamed change. It spends model calls, so run it in a plain terminal after every model or tool update.
- Add a rule only after you have seen the same failure twice.

## Requirements

- [Claude Code](https://code.claude.com) and/or [GitHub Copilot CLI](https://github.com/features/copilot/cli)
- `jq`, `git`, and `make`. The verify sandbox needs macOS `sandbox-exec`; elsewhere the check runs unsandboxed, and `trust` says so.
- Pipelines: `gh` or `glab`; optional `jira` CLI. Incidents: `kubectl`, `az` (read-only)
- Development: `bats-core` (`brew install bats-core`)

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): components, flows, hooks, pipelines
- [PAPER.md](PAPER.md): design rationale (a whitepaper, not an empirical study), with the erratum
- [docs/decisions/](docs/decisions/): ADRs · [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
