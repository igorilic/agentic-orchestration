# Architecture v4: native-first

The tools' own agent loops do the agent work. This repo ships only what they lack: two
fail-closed hooks, five workflow skills, a sandboxed settings policy, short instructions, and a
CLI that installs them and runs headless pipelines.

- Why: [PAPER.md](../PAPER.md) · Decision: [ADR-003](decisions/ADR-003-native-first-harness.md) ·
  Spec: [HARNESS-2](context/specs/HARNESS-2-spec.md)

```
┌───────────────────────────────────────────────────────────────────────────┐
│  ENFORCEMENT  hooks, user-global in both tools, fail closed               │
│    guard.sh   before every command and edit: deny bypasses and harness    │
│               writes; ask about weakened tests, new deps, CI edits        │
│    verify.sh  when an editing turn ends: run the trusted .anw/verify      │
│               (sandboxed); red → keep working or end with BLOCKED:        │
├───────────────────────────────────────────────────────────────────────────┤
│  CONTAINMENT  settings: OS sandbox, egress allowlist, secrets unreadable, │
│               ask before push/PR/comments, deny force-push and prod edits │
├───────────────────────────────────────────────────────────────────────────┤
│  WORKFLOW     skills: /plan /check /incident /pr (you), /verify (model)   │
├───────────────────────────────────────────────────────────────────────────┤
│  AGENTS       native: the main session, plan mode, built-in subagents     │
│               (no custom agents)                                          │
└───────────────────────────────────────────────────────────────────────────┘
```

## The development flow

| Work | Flow |
|---|---|
| Small change (1–2 files) | Ask in the main session. A failing test first, then the fix. The hooks gate the commit and the end of the turn. `/check`, then `/pr`. |
| Feature or unclear work | `/plan <ticket>` writes `docs/context/specs/<id>.md`; **you approve**. Implement one step per session, committing each. `/check`, then `/pr`. |
| Incident | `/incident <ticket>` investigates read-only and writes a report. You decide what to post; the fix starts in a fresh session. |
| PR/MR review | The built-in `/code-review` (Claude) or `/review` (Copilot). |

In Copilot, plan in plan mode (`/model plan` picks the planner) and follow `/check` with
`/rubber-duck`.

## Enforcement: the two hooks

Both scripts read either tool's stdin JSON, and both are installed **user-global**: in Claude Code
through `~/.claude/settings.json`, and in Copilot CLI through `~/.copilot/hooks/anw.json`.

**`guard.sh`** (Claude `PreToolUse` as `guard.sh || exit 2`; Copilot `preToolUse`):

| Rule | Decision |
|---|---|
| `--no-verify`, `commit -n`, `core.hooksPath`, `HUSKY=0`, `SKIP=` | deny |
| A nested `claude`/`copilot` with permissions or hooks disabled | deny |
| Edits to `~/.claude`, `~/.copilot` (including the trust list), `.claude/settings*.json`, `.git/`, `.github/hooks/`, `.anw/`; shell writes to the hooks, settings, trust list and finish line | deny |
| A commit that deletes tests, adds skip/focus markers, removes or rewrites assertions, or changes source with no test, judged on what it will commit (`git add … && git commit` and `commit -a` included) | ask |
| A new dependency name; edits to CI config, instruction files or `.claude/` | ask |
| Any edit | marks the session as edited, which arms `verify.sh` |

It never emits `allow`. A crash, malformed input or a missing script denies. Headless, an ask
becomes a denial.

**`verify.sh`** (Claude `Stop`; Copilot `agentStop`; `--run` for scripts) acts only when the session
edited files and the repo has an executable `.anw/verify` that you trusted:

- **Trust.** `ai-native-workflow trust` shows you the script and, on your `y`, records its
  `shasum -a 256` line (hash and physical path) in `~/.claude/anw/trusted-verify`. A cloned,
  copied or edited script is never run. Agents can't write the trust list.
- **Sandbox.** Hooks run outside the agent's sandbox, and the trusted script runs repo code the
  agent may have just written. So on macOS it runs under `sandbox-exec` with the agent's file
  limits: writes only to the repo, temp and caches; never to git hooks, agent config or the
  finish line; no reading keys. The network stays open.
- **Outcome.** Green ends the turn. Red blocks it with the failure output and the honest-exit
  instruction. A reply with a `BLOCKED:` line (bold allowed), or a second red stop in a row, ends
  the turn and is flagged to you.

## Skills

| Skill | Invoked by | What it does |
|---|---|---|
| `plan` | you | ticket → testable ACs and small test-first steps, then stops for your approval |
| `check` | you | fresh context, read-only, Opus tier: runs the check, reads the diff, audits integrity, reports merge blockers with repros, ends with `Verdict: block` or `Verdict: pass` |
| `verify` | the model (Claude runs it before each commit) | runs `.anw/verify` and quotes the real result |
| `incident` | you | read-only investigation → diagnosis and fix plan; never posts |
| `pr` | you | verify, then push and open the PR/MR (each asks you) |

Knowledge skills (`clusters`, `gh-cli`, `glab-cli`, `ticket`, `adr`, `explore`, …) are optional.
Hooks and skills are installed as **copies**, never symlinks, so an agent editing this repo can't
change live enforcement; `doctor` reports drift.

## Pipelines (`ai-native-workflow run …`)

Each stage is a fresh headless session with stdin closed, running a skill:

| Stage | Claude (`github-feature`, `github-issue`) | Copilot (`gitlab-feature`, `gitlab-incident`) |
|---|---|---|
| plan | `/plan` on opus, then you approve | `/plan`, then you approve |
| each step | "implement step N" on sonnet | the same, MCP servers disabled |
| check | `/check` on opus, edit tools disallowed | `/check` with `--deny-tool=write` |

- Claude runs with `--permission-mode acceptEdits --permission-prompts none`. Copilot runs with
  `--allow-all-tools --no-ask-user`.
- Neither gets a bypass flag. The policy's ask and deny rules (push, PR/MR, Jira writes, `gh`/`glab`
  `api`, mutating kubectl) are passed as disallowed tools.
- A `BLOCKED:` stage stops the pipeline.
- The script runs the trusted `.anw/verify` (`verify.sh --run`, same sandbox). Then, each on your
  yes (Enter means no), it pushes, opens the PR/MR and posts to Jira.
- State lives in `.anw/.pipeline-state`, parsed and never sourced. `run resume` continues from the
  last finished stage.

## What gets installed

| Where | What |
|---|---|
| `~/.claude/` | `hooks/guard.sh`, `hooks/verify.sh`; the policy merged into `settings.json` (your keys kept); a managed block in `CLAUDE.md`; `skills/` |
| `~/.copilot/` | the same two hooks plus `hooks/anw.json`; a managed block in `copilot-instructions.md`; `skills/` |
| a project (`install project`) | `.anw/verify` for the detected stack (never overwritten; trusted on your `y`); a short `AGENTS.md` that `CLAUDE.md` imports; `.gitignore` rules `.anw/*` + `!.anw/verify`; `docs/context/`, `docs/decisions/` |

Older installs are cleaned up: retired agents, skills and hooks move to `<home>/anw-backup/<stamp>/`.

## Path conventions

| Path | Tracked | Contents |
|---|---|---|
| `docs/context/` | yes | sprint board, specs and plans, reviewed in PRs |
| `.anw/verify` | yes | the finish line |
| `.anw/*` (everything else) | no | pipeline state and stage transcripts |
| `~/.claude/anw/trusted-verify` | — | the trust list; agents can't write it |

## Verifying the harness

- `make test` runs the bats suite. The hooks are driven with each tool's real payload shapes, and
  the pipelines with stub CLIs and a local bare remote.
- `make smoke` (`ai-native-workflow doctor --smoke`) runs live canaries against the installed
  harness. It covers bypasses, containment, an honest fix, an impossible finish line ×3 and `/check`
  on a gamed change. It spends model calls, so run it after every model or tool update.

## Key design decisions

- **Enforce outside the agent's reach.** Must-hold rules live in hooks and settings that fail
  closed and that the agent can't edit. Prompts only state intent.
- **Ground truth comes from execution.** The hooks run the check themselves; no self-reported scores.
- **Every gate has an honest exit.** `BLOCKED: <evidence>` is a success path, and you are the only bypass.
- **Strong finish lines.** `.anw/verify` runs the whole fast suite, so no cheap hack passes it.
- **One writer, one fresh-context reviewer.** No role-based agent teams.
- **Contain the blast radius.** The OS sandbox is the security boundary. Hooks are a guardrail.
- **Floating model aliases** (`opus`, `sonnet`), never pinned versions.

## Architecture Decision Records

- [ADR-003](decisions/ADR-003-native-first-harness.md): native-first harness. It supersedes ADR-001
  and ADR-002, which stay in [decisions/](decisions/) as history.
