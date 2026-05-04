# COP-1 — Symmetric Copilot CLI harness for `install global`

**Status:** Proposed (requirements only — awaiting architect)
**Date:** 2026-05-02
**Owner:** requirements-engineer → architect
**Source:** User request (this conversation), thread `ticket COP-1`
**Related:**
- `ai-native-workflow install global` (script `ai-native-workflow`, `install_global` at L1659, `install_copilot_agents` at L3157)
- `ai-native-workflow install project` (`install_project_copilot` at L3882)

---

## 1. Goal

`ai-native-workflow install global` currently installs a full harness for
**Claude Code** (hooks, skills, agents, helper scripts, settings.json) but
only installs **agents** for Copilot CLI. Bring the Copilot CLI side to
parity by installing every Copilot-CLI-supported equivalent of the Claude
primitives — and explicitly document every Claude primitive that has no
Copilot equivalent so the gap is intentional, not accidental.

The user-visible outcome: after `ai-native-workflow install global`, a
fresh `copilot` interactive session has the same skills, agents, custom
instructions, settings, and (where supported) lifecycle behavior as a
fresh `claude` session.

## 2. Capability matrix — Claude Code → Copilot CLI

This matrix is the load-bearing artifact. Every "N/A" row carries an
explicit reason that the requirements lock in.

| # | Claude Code primitive | Copilot CLI equivalent | Install location | Status today | Action |
|---|---|---|---|---|---|
| 1 | `~/.claude/agents/*.md` (7 agents) | Custom agents `.agent.md` | `~/.copilot/agents/` (override: `$COPILOT_HOME/agents/`) | **Already installed** by `install_copilot_agents` | Keep as-is. Optionally extend frontmatter (`license`, `tools`) — see FR-7. |
| 2 | `~/.claude/skills/*/SKILL.md` (16 skills: tdd, ticket, plan, brainstorm, adr, pr, session-report, skip-tdd, override-confidence, security-review, k8s, kibana, app-insights, clusters, pipeline-github-feature, pipeline-gitlab-feature, pipeline-gitlab-incident) | Agent skills `SKILL.md` (officially supported, identical frontmatter, same `/<name>` invocation) | `~/.copilot/skills/<name>/SKILL.md` | **Not installed** by the CLI today (the skills present in the user's `~/.copilot/skills/` were placed there manually) | **NEW:** install all 16 skills. See FR-2. |
| 3 | `~/.claude/CLAUDE.md` (global instructions) | `copilot-instructions.md` at home root | `~/.copilot/copilot-instructions.md` | **Not installed** | **NEW:** install symmetric global instructions. See FR-3. |
| 4 | `~/.claude/settings.json` (hooks registration + Notification + user config) | `~/.copilot/settings.json` (no hooks key — Copilot CLI hooks are repo-scoped only; see row 5) | `~/.copilot/settings.json` | **Exists** (hand-managed by user with `model`, `effortLevel`, `allowedUrls`) | **NEW (limited):** seed/merge a minimal `settings.json` only if absent; preserve user values. See FR-4 and the trim-down note in §6. |
| 5 | `~/.claude/hooks/{session-start.sh,tdd-gate.sh,confidence-gate.sh}` registered via `~/.claude/settings.json` | Hooks (`sessionStart`, `preToolUse`, `postToolUse`, `userPromptSubmitted`, `sessionEnd`, `errorOccurred`) — but **scoped to the current working directory only** via `.github/hooks/*.json` | repository-local `.github/hooks/copilot-cli-policy.json` (not `~/.copilot/`) | **N/A for `install global`** — Copilot CLI does not expose a global/user-level hooks file. | **No global install for hooks.** Document this in caveats. Provide a project-level hooks installer instead under `install project` (out-of-scope for COP-1; track as follow-up COP-2). See §7 Open Questions. |
| 6 | `~/.claude/scripts/{confidence.sh,confidence-cli.sh}` (helpers called by hooks) | Same shell scripts (Copilot CLI shells out to `bash`/`pwsh` from hook entries) | `~/.copilot/scripts/` (consistent symmetric path) | **Not installed** | **NEW (conditional):** install scripts to `~/.copilot/scripts/` only if a project-level Copilot hooks installer ships them. If COP-2 ships, install. If we ship hooks-free, skip. See FR-6. |
| 7 | `~/.claude/CLAUDE.md` per-project (different from global) | Per-project `.github/copilot-instructions.md` + `.github/instructions/<lang>.instructions.md` | per-project | **Already installed** by `install_project_copilot` at L3882 | Out of scope for COP-1 (this is `install project`, not `install global`). |
| 8 | Notifications hook (osascript on attention required) | `beep: true` in `settings.json` (Copilot CLI built-in attention notification) | N/A — built-in | **N/A** — handled by Copilot CLI itself, no hook needed | No install needed. Optionally seed `beep: true` in FR-4. |

### Three findings that shape this matrix

1. **Hooks are repo-scoped, not user-scoped, in Copilot CLI.** Confirmed by
   the official "Using hooks with Copilot CLI" tutorial: hook config files
   live at `.github/hooks/*.json` in the repository's working directory,
   not under `~/.copilot/`. There is no documented user-global hooks file.
   This means our Claude-side `tdd-gate.sh` and `confidence-gate.sh` —
   which today are registered globally via `~/.claude/settings.json` —
   cannot be globally registered for Copilot CLI. They can only be
   installed per-project (a future `install project` extension).
2. **Skills are first-class in Copilot CLI** with the same `SKILL.md` +
   YAML-frontmatter format as Claude Code, the same directory layout
   (`~/.copilot/skills/<name>/SKILL.md`), and the same `/<name>` slash-
   invocation. This is the cleanest 1:1 mapping in the matrix and is
   where most of the new install work lives.
3. **Global instructions exist** at `$HOME/.copilot/copilot-instructions.md`
   (officially documented). This is the direct analog to `~/.claude/CLAUDE.md`.

## 3. Functional Requirements

### FR-1 — Preserve existing Copilot agent install
The current behavior of `install_copilot_agents` (writing 7 `.agent.md`
files to `$COPILOT_HOME/agents/`, default `~/.copilot/agents/`) MUST
remain unchanged. Re-running the installer MUST timestamp-backup any
existing `.agent.md` files using the existing `backup_if_exists` helper.

### FR-2 — Install Copilot CLI skills (NEW)
The installer MUST write a `SKILL.md` for every skill that Claude Code
gets to `$COPILOT_HOME/skills/<skill-name>/SKILL.md`. Required skills:
`tdd`, `ticket`, `plan`, `brainstorm`, `adr`, `pr`, `session-report`,
`skip-tdd`, `override-confidence`, `security-review`, `k8s`, `kibana`,
`app-insights`, `clusters`, `pipeline-github-feature`,
`pipeline-gitlab-feature`, `pipeline-gitlab-incident` (full set as
present in `skills/` in the repo at install time).

The skill content for Copilot CLI MAY be identical to the Claude Code
content where the skill is platform-agnostic (TDD workflow, ticket-to-spec
flow, ADR template). For pipeline skills that mention `claude --agent=...`
the Copilot variant MUST substitute `copilot --agent=...` so the
hand-off lines work in a Copilot session.

Each `SKILL.md` MUST have YAML frontmatter with the required `name` and
`description` fields. Optional `license` and `allowed-tools` fields MAY
be added (decision deferred to architect — see Open Question OQ-3).

### FR-3 — Install global Copilot instructions (NEW)
The installer MUST write `$COPILOT_HOME/copilot-instructions.md` with
content semantically equivalent to `~/.claude/CLAUDE.md`. The two files
SHOULD share the same source-of-truth template so they cannot drift.
The Copilot variant MUST replace `Claude Code`-specific phrasing (e.g.,
"Claude Code session", `~/.claude/`, `/<skill>` examples that say
"Claude") with neutral or Copilot-specific phrasing.

If `$COPILOT_HOME/copilot-instructions.md` already exists, the
installer MUST timestamp-backup it before overwriting (same rule as
`~/.claude/CLAUDE.md`).

### FR-4 — Seed Copilot settings.json safely (NEW, conservative)
The installer MUST NOT overwrite `$COPILOT_HOME/settings.json` if it
already exists with non-default user keys (e.g., `model`, `effortLevel`,
`allowedUrls`).

When `$COPILOT_HOME/settings.json` is absent:
- Write a minimal default with `{"renderMarkdown": true, "theme": "auto"}`.
- DO NOT seed `model` (let Copilot pick its default; the user can override).
- DO NOT seed `allowedUrls` (user-specific).

When it exists:
- Use `jq` to merge in only keys that are missing (additive merge, no
  overwrite of existing values), guarded by `command -v jq`.
- If `jq` is absent, leave the file alone and warn (mirrors the existing
  Claude `install_global_settings` jq-absent fallback).

Note: `settings.json` does NOT carry hooks — hooks for Copilot CLI live
in `.github/hooks/*.json` per repo. Do not attempt to write a `hooks` key
to `~/.copilot/settings.json`.

### FR-5 — Graceful handling when Copilot CLI is not installed
The installer MUST keep its current behavior of skipping the entire
Copilot section when `command -v copilot` returns non-zero, logging a
single dim line `"Copilot CLI not found — skipping Copilot installation"`
and an install hint. The user MUST still see a successful Claude-side
install when Copilot CLI is absent. Exit code MUST remain 0.

### FR-6 — Helper scripts directory (CONDITIONAL)
If and only if the architect decides to ship a project-level Copilot
hooks installer in COP-1 (currently scoped OUT, see §6), the installer
MUST also copy `confidence.sh` and `confidence-cli.sh` to
`$COPILOT_HOME/scripts/` so future repo-level hook scripts can reference
them via `bash ~/.copilot/scripts/...`. If COP-2 takes hooks instead,
this requirement deactivates.

Default decision for COP-1: **skip helper scripts** (no hooks → no
helpers needed yet).

### FR-7 — Agent frontmatter alignment with Copilot CLI conventions
The 7 agent files written by `install_copilot_agents` SHOULD be
reviewed against the official Copilot CLI custom-agent docs and
extended with optional frontmatter fields (`tools` allowlist) where it
clarifies intent — e.g., the `architect` agent already has prose saying
"Shell access is for READ-ONLY context fetching only", which can be
expressed as `tools: [read, search, shell(git:*), shell(gh:*)]` (exact
syntax to be confirmed by architect via Copilot docs).

This is a soft requirement: existing files work; this is polish.

### FR-8 — Idempotency and backup parity with Claude side
Every file the installer writes to `~/.copilot/` MUST go through the
same `backup_if_exists` path that the Claude side uses (timestamp suffix
`.bak.YYYYMMDDHHMMSS`). Re-running `install global` twice in a row MUST
produce identical end state and one backup per write per run.

### FR-9 — Status command coverage
`ai-native-workflow status` (the existing diagnostics command at L4088)
MUST be extended to verify the new files: `~/.copilot/skills/<each>/SKILL.md`,
`~/.copilot/copilot-instructions.md`, and `~/.copilot/settings.json`
(presence only, no value check). Missing files render as ✗, present as
✓. This MUST follow the existing `check_file` pattern (no new logic).

### FR-10 — Caveats output
`install_global` MUST print a closing block listing every Copilot
target it touched, plus an explicit one-line statement that hooks were
NOT installed globally because Copilot CLI scopes hooks per-repo, with
a forward reference (`run install project for repo-scoped Copilot
hooks`, gated on COP-2 shipping).

## 4. Non-Functional Requirements

### NFR-1 — Honor `COPILOT_HOME`
Every read/write MUST go through `COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"`,
matching the existing pattern in `install_copilot_agents` (L3165) and
the `caveats` block in the brew formula. Sandboxed `COPILOT_HOME=/tmp/foo`
installs MUST work identically.

### NFR-2 — Idempotent
Two consecutive `install global` runs MUST converge to the same final
state. Each run MUST produce at most one backup per file.

### NFR-3 — Bash 4 compatibility
The installer must continue to run under brew's bash 5 and any system
bash >= 4.0 (no bash 3 features required, no zsh-only constructs). The
existing shebang patching in the brew formula handles this.

### NFR-4 — No new external dependencies
The Copilot harness install MUST NOT require any tool not already
declared by the brew formula (`bash`, `jq`; `gh`/`glab` recommended).

### NFR-5 — Performance
The full `install global` (Claude + Copilot harness) MUST complete in
under 5 seconds on a warm filesystem. Skill content is small heredocs;
this should be trivially met.

### NFR-6 — Test coverage
New install logic MUST have bats tests under `tests/` mirroring the
existing patterns (`install-global.bats`, etc.). Required cases:
fresh install, re-install (idempotency), `COPILOT_HOME` override,
Copilot CLI absent, partial existing state (some files exist, some
don't).

## 5. Acceptance Criteria

Each AC is testable in isolation. Format: Given / When / Then.

### AC-1 — Skills install
**Given** a clean `$COPILOT_HOME` (or `~/.copilot/`) and Copilot CLI is on PATH,
**When** the user runs `ai-native-workflow install global`,
**Then** every skill present in the repo's `skills/<name>/SKILL.md`
source MUST exist at `$COPILOT_HOME/skills/<name>/SKILL.md` with
matching content (or Copilot-adapted content for pipeline skills),
AND `copilot --help`'s `/skills list` (when run interactively) lists
each one.

### AC-2 — Global instructions installed
**Given** a clean `$COPILOT_HOME`,
**When** the user runs `ai-native-workflow install global`,
**Then** `$COPILOT_HOME/copilot-instructions.md` exists, is non-empty,
and contains the skill list, agent pipeline description, and stack
detection table from `~/.claude/CLAUDE.md` (semantic equivalence).

### AC-3 — Settings.json preserved
**Given** an existing `$COPILOT_HOME/settings.json` containing
`{"model": "claude-opus-4.6", "effortLevel": "high"}`,
**When** the user runs `ai-native-workflow install global`,
**Then** the file STILL contains those two keys with their values
unchanged afterward, AND a single `.bak.<timestamp>` exists alongside.

### AC-4 — Settings.json fresh install
**Given** no `$COPILOT_HOME/settings.json`,
**When** the user runs `ai-native-workflow install global`,
**Then** `$COPILOT_HOME/settings.json` exists, parses as valid JSON,
contains `renderMarkdown: true`, and does NOT contain a `hooks` key.

### AC-5 — Idempotent re-run
**Given** `install global` has been run once,
**When** the user runs `install global` again,
**Then** every file under `$COPILOT_HOME/` matches its repo-source
content byte-for-byte, AND exactly one new `.bak.<timestamp>` per
written file exists from the second run.

### AC-6 — Copilot CLI absent
**Given** `command -v copilot` returns non-zero,
**When** the user runs `ai-native-workflow install global`,
**Then** the command exits 0, prints
`"Copilot CLI not found — skipping Copilot installation"`, leaves
`$COPILOT_HOME/` untouched, AND completes the Claude side normally.

### AC-7 — `COPILOT_HOME` override
**Given** `COPILOT_HOME=/tmp/cop-test` and Copilot CLI on PATH,
**When** the user runs `COPILOT_HOME=/tmp/cop-test ai-native-workflow install global`,
**Then** all new artifacts are written under `/tmp/cop-test/` and
`~/.copilot/` is untouched.

### AC-8 — Status command reflects the new state
**Given** a successful `install global` run,
**When** the user runs `ai-native-workflow status`,
**Then** the Copilot CLI section lists each skill, the global
instructions file, and `settings.json` with ✓ markers.

### AC-9 — No global hooks claim
**Given** a successful `install global` run,
**When** the user inspects `$COPILOT_HOME/`,
**Then** there is no `hooks/` directory, no `hooks` key in
`settings.json`, and no `.github/hooks/` artifact (those would be
project-scope and out of `install global`'s remit).

### AC-10 — Caveat printed
**Given** Copilot CLI is on PATH,
**When** `install global` finishes,
**Then** the closing output contains a one-line note that global
Copilot hooks are not supported by Copilot CLI and hooks are
project-scoped (visible to the user even if they don't read docs).

## 6. Constraints & Out-of-Scope

### Constraints
- C-1: Cannot install Copilot CLI itself; the user is responsible.
- C-2: Cannot register hooks at the user/global scope (Copilot CLI
  product limitation as of 2026-05). Repo-scope hooks via
  `.github/hooks/*.json` are out of scope for `install global`.
- C-3: Skill content is shipped as bash heredocs in
  `ai-native-workflow` (matches the existing pattern). Skills are NOT
  copied from the repo's `skills/` source dir at runtime — they are
  re-emitted from heredocs. Architect MUST decide whether to refactor
  to "copy from `$_ANW_SCRIPT_DIR/skills/<name>/SKILL.md`" or keep
  parallel heredocs (see OQ-1).
- C-4: All new behavior must be backward-compatible: existing users
  re-running `install global` must not lose their hand-managed
  `~/.copilot/settings.json` keys.

### Out of scope (explicit)
- OOS-1: **Project-level Copilot hooks installer.** Track as follow-up
  spec **COP-2** (scope: extend `install project` to write
  `.github/hooks/copilot-cli-policy.json` referencing
  `confidence-gate.sh` and `tdd-gate.sh`, plus install those scripts
  to a per-repo `.github/hooks/scripts/` dir or to `~/.copilot/scripts/`
  if FR-6 activates).
- OOS-2: **MCP server config** (`~/.copilot/mcp-config.json`). Out of
  scope. The user manages this manually today; symmetric MCP install
  is a separate concern (Claude side doesn't fully solve this either).
- OOS-3: **Authentication / `copilot login`.** Out of scope.
- OOS-4: **Plugins (`/plugin`).** Out of scope; experimental surface
  on Copilot CLI side.
- OOS-5: **Per-stack Copilot instructions globally** (analog of
  `.github/instructions/<lang>.instructions.md`, but global). Copilot
  CLI does not document a global per-stack mechanism; covered today
  per-project by `install project`.

## 7. Open Questions / Blockers

These need a decision before architect can lock the spec. Tag them
`f`/`t`/`i` per the user's per-item triage convention (or just answer).

### OQ-1 — Skill content source: heredoc or copy?
The existing Claude install emits skill SKILL.md as bash heredocs. The
Copilot install of skills can either:

- **(a)** Add new heredocs (parallel to Claude — same content
  duplicated twice in the script). Pros: keeps the script
  self-contained, matches existing pattern. Cons: drift risk, doubles
  the script size.
- **(b)** `cp` from `$_ANW_SCRIPT_DIR/skills/<name>/SKILL.md` (single
  source of truth, repo's `skills/` directory). Pros: no duplication.
  Cons: changes the existing pattern. Brew installs to `libexec/skills`
  (already done — see formula L36 `libexec.install Dir["skills", ...]`).
- **(c)** Refactor BOTH Claude and Copilot to use approach (b) (riskier
  but cleanest).

Architect to decide. Default if undecided: **(b)** — content is already
in `libexec/skills/` thanks to the brew formula, and the new install
function can `cp -R` from there. Pipeline skills that need
`copilot --agent=` substitution can use a `sed -i.bak` post-copy.

### OQ-2 — Are Copilot-side skill triggers compatible with Copilot's slash-skill model?
Claude Code's `description: triggers on:` field is informal — both
agents and skills can be triggered by description matching. Copilot
CLI's documented invocation is `/<skill-name>`. Verify that
`description` text in SKILL.md is purely advisory on Copilot side and
won't cause auto-loading semantics surprise. Default assumption:
identical behavior to Claude. Architect to verify with a quick
`copilot --help` smoke test.

### OQ-3 — Should we add `allowed-tools` to skills?
Optional `allowed-tools` field skips per-tool confirmation prompts on
Copilot CLI. Adding `allowed-tools: [bash, read, write]` to `tdd` skill
would let the workflow run smoother under default permissions.
Trade-off: pre-approves tools without the user opting in.

Default if undecided: **do not add** (conservative — let the user
opt-in via `--allow-tool` flags or `/permissions` interactive
toggles).

### OQ-4 — Should `install global` recommend `copilot init` for the user's open repos?
The user has 20+ trusted folders in `~/.copilot/config.json`. None of
them currently have `.github/copilot-instructions.md` written by the
CLI's `install project`. Should `install global`'s caveats nudge the
user to run `install project` in their main repos? Default:
**yes, single line in caveats**.

### OQ-5 — Does the user want the Copilot symmetric harness to include
the same Notification mechanism (osascript)?
Claude's `install_global_settings` writes a `Notification` hook that
runs `osascript -e 'display notification ...'`. Copilot CLI has a
built-in `beep: true` setting. They are not equivalent (beep is audio
only; osascript is a macOS notification banner). Should we set
`beep: true` in the seeded settings.json?

Default: **yes, seed `beep: true` in the fresh-install path** of
FR-4. Skip in the merge path (don't override user's choice).

### OQ-6 — Versioning the harness install
The Claude side prints `"Installing AI-native workflow (v${VERSION})"`
and runs through to a single completion banner. Should the Copilot
section have its own sub-header, or roll into the same one? Default:
**one banner, two sub-sections** (one for Claude, one for Copilot,
each with its own ✓ list). Mirrors existing `install_copilot_agents`
which already prints its own sub-header.

## 8. Assumptions

- A-1: Copilot CLI version installed on the user's machine supports
  agent skills (introduced 2025-12 per the GitHub Changelog). The
  installer does NOT need to detect the Copilot CLI version; if a
  user has an older Copilot, skills will simply not be loaded — no
  install error. Document in caveats.
- A-2: User's existing `~/.copilot/skills/` directory was populated by
  hand and SHOULD be backed up by the installer's `backup_if_exists`
  path (which matches our user's stated install — see the contents
  listed in §3 of the user's request). The installer must not delete
  user-authored skills; only the named set in FR-2 are written.
- A-3: `copilot --agent=<name>` invocation syntax is stable (already
  used in agent hand-off lines of installed agents).
- A-4: `~/.copilot/copilot-instructions.md` is loaded automatically by
  `copilot` interactive sessions (per docs). No registration needed.

## 9. Test Plan Outline

For the `qa` agent and bats test suite. Each row maps to one bats `@test`.

### Unit / install behavior
- T-1: AC-1 — fresh install creates every expected SKILL.md with valid
  YAML frontmatter (parse with `yq` or grep for `^name:` and `^description:`).
- T-2: AC-2 — `copilot-instructions.md` present and contains expected
  marker strings (skill list, agent pipeline names).
- T-3: AC-3 — settings.json merge preserves user keys (seed file with
  `model`+`effortLevel`, run installer, assert keys still present).
- T-4: AC-4 — settings.json fresh install produces valid JSON with
  `renderMarkdown: true` and no `hooks` key.
- T-5: AC-5 — idempotency: run installer twice; assert exactly N
  backups (one per file) and final content matches source.
- T-6: AC-6 — Copilot absent: stub `command -v copilot` to fail
  (prepend a temp dir to `PATH` with no `copilot` shim); assert exit
  code 0 and `~/.copilot/` untouched.
- T-7: AC-7 — `COPILOT_HOME=/tmp/cop-test` redirects all writes.
- T-8: AC-9 — assert no `hooks/` dir or `hooks` JSON key after install.

### Integration
- T-9: end-to-end after `install global`, run `copilot -p "/skills list"
  --allow-all-tools` (gated on Copilot CLI being present in CI; skip
  test otherwise) and assert all installed skill names appear.
- T-10: `ai-native-workflow status` post-install lists ✓ for every new
  Copilot artifact (AC-8).

### Edge / negative
- T-11: User has hand-edited `~/.copilot/skills/<name>/SKILL.md` with
  custom content; installer overwrites it but creates a `.bak.*`. The
  test asserts: backup exists with old content, file has new content.
- T-12: `jq` absent during settings.json merge — assert installer
  warns and does NOT corrupt the file.
- T-13: `$COPILOT_HOME` points to a path requiring `mkdir -p` (deep
  nested) — assert success.

## 10. References

- [GitHub Copilot CLI — Adding agent skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)
- [GitHub Copilot CLI — Creating and using custom agents](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli)
- [GitHub Copilot CLI — Adding custom instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions)
- [GitHub Copilot CLI — Using hooks](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks)
- [GitHub Copilot CLI — Hooks configuration reference](https://docs.github.com/en/copilot/reference/hooks-configuration)
- [GitHub Copilot CLI — Hooks tutorial (repo-scope confirmation)](https://docs.github.com/en/copilot/tutorials/copilot-cli-hooks)
- [GitHub Changelog — Copilot now supports Agent Skills (2025-12-18)](https://github.blog/changelog/2025-12-18-github-copilot-now-supports-agent-skills/)
- [About agent skills (concepts)](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- Local: `ai-native-workflow` lines 1659–1691 (`install_global`),
  3157–3459 (`install_copilot_agents`), 3882–3923
  (`install_project_copilot`), 4088–4108 (`status` Copilot section).
- Local: brew formula `Formula/ai-native-workflow.rb` (caveats block
  documents `COPILOT_HOME`).
