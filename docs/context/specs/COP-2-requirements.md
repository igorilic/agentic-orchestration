# COP-2: Install Copilot CLI hooks per-project

> Source: User request (2026-05-02), follow-up to COP-1.
> Repo integration point: `ai-native-workflow install project` →
> `install_project_copilot()` in `/Users/igorilic/open-source/agentic-orchestration/ai-native-workflow`
> (lines 3882–4022).
> Reference Claude implementation:
> `install_global_hooks()` (lines 1938–2077) and the `Bash` PreToolUse entries
> in `install_global_settings()` (lines 1752–1936).

## 1. Goal Statement

Extend `ai-native-workflow install project` so that, for any repo where the
user runs the per-project installer, the same two enforcement gates that
already protect Claude Code (`tdd-gate` and `confidence-gate`) also fire
when an engineer drives the workflow with **GitHub Copilot CLI**. Because
Copilot CLI's hooks are repository-scoped (no `~/.copilot/hooks.json`
analogue), this work cannot live in `install_global_*` — it must be a
per-project installer step.

The installed gates must be **functionally equivalent** to the Claude
versions: same block decisions, same bypass mechanisms (`/skip-tdd`,
`/override-confidence`), same audit-log writes, same exit semantics for
the user. Two AI tools, one policy.

## 2. Background — Copilot Hook Mechanics (Research Findings)

Captured from:
- https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks
- https://docs.github.com/en/copilot/reference/hooks-configuration
- https://docs.github.com/en/copilot/tutorials/copilot-cli-hooks
- https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-hooks

### 2.1 Discovery and file location

- Hooks live in **`.github/hooks/`** of the repository. The directory is
  conventional and discovered automatically when Copilot CLI runs from
  inside the repo.
- The configuration filename is **flexible** — the docs say "Create a new
  `hooks.json` file with the name of your choice in `.github/hooks/`."
  Copilot loads `.github/hooks/*.json`. We will standardise on
  **`.github/hooks/copilot-cli-policy.json`** to match the user's
  request and the cloud-agent tutorial example.
- For Copilot Cloud Agent the file must exist on the default branch.
  For Copilot CLI the file is loaded from CWD, so the script must be
  **committed** (or at minimum present at runtime) for hooks to fire.
- There is **no global / user-level hook mechanism**. Repo-scoped only.
  This is why COP-2 is per-project, not global.

### 2.2 Configuration schema (verbatim shape)

```json
{
  "version": 1,
  "hooks": {
    "sessionStart":        [ <hookEntry>, ... ],
    "sessionEnd":          [ <hookEntry>, ... ],
    "userPromptSubmitted": [ <hookEntry>, ... ],
    "preToolUse":          [ <hookEntry>, ... ],
    "postToolUse":         [ <hookEntry>, ... ],
    "agentStop":           [ <hookEntry>, ... ],
    "subagentStop":        [ <hookEntry>, ... ],
    "errorOccurred":       [ <hookEntry>, ... ]
  }
}
```

`<hookEntry>` shape:

| Field         | Type     | Notes                                                |
|---------------|----------|------------------------------------------------------|
| `type`        | string   | Currently only `"command"`.                          |
| `bash`        | string   | Path to bash script. Resolved relative to `cwd`.     |
| `powershell`  | string   | PowerShell variant (optional for our use).           |
| `cwd`         | string   | Working directory for the command. Repo-relative.    |
| `timeoutSec`  | number   | Default 30. We will set per-hook explicitly.         |
| `env`         | object   | Static env vars passed to the script.                |
| `comment`     | string   | Optional human description.                          |

**No `matcher` field exists** (unlike Claude). Filtering by command
(e.g. only fire on `git commit`) must be done **inside the hook script**
by parsing the JSON payload. This is already how the Claude scripts are
written, so the porting cost is low.

### 2.3 Invocation contract

Copilot invokes the hook command **with the JSON event payload on stdin**
and reads exit code + stdout. There are **no pre-set environment variables**
equivalent to `CLAUDE_PROJECT_DIR` or `CLAUDE_TOOL_INPUT`. Scripts must:

1. Read stdin.
2. Parse JSON with `jq`.
3. Determine project dir from the `cwd` field of the payload (or `pwd`).
4. Determine the command being gated from `toolArgs` (a **JSON-stringified**
   blob — must be `jq`-parsed twice).

### 2.4 `preToolUse` payload (the one we care about)

```jsonc
{
  "timestamp": 1714694400000,
  "cwd": "/abs/path/to/repo",
  "toolName": "bash",          // for shell commands
  "toolArgs": "{\"command\":\"git commit -m ...\"}"  // JSON STRING
}
```

`toolName` for shell execution is **`"bash"`**. (Other tool names exist
for file reads, etc., but our gates only care about bash.)

### 2.5 Decision shape

To **block**: hook prints to stdout a single-line JSON object:

```json
{"permissionDecision":"deny","permissionDecisionReason":"<message>"}
```

To **allow**: print nothing (or anything other than `deny`) and exit 0.
Currently only `"deny"` is processed; `"allow"` and `"ask"` are no-ops.

**Exit code does not block by itself.** This is a critical departure
from Claude — see §6.1.

### 2.6 Order, merging, sequencing

The docs are silent on:
- Whether multiple files in `.github/hooks/*.json` are merged.
- Whether multiple entries in the same event array short-circuit on
  the first `deny`.
- Hook execution order within an array.

We assume (and must verify in QA) that:
- Entries in a `preToolUse` array run sequentially in declaration order.
- Any `deny` from any entry blocks the action.
- A single file is sufficient — we will not split into multiple JSONs.

These assumptions become **OQ-1, OQ-2, OQ-3** in §10.

## 3. Hook Capability Matrix (Claude → Copilot)

| Capability                        | Claude Code                                        | Copilot CLI (target)                                                         |
|-----------------------------------|----------------------------------------------------|------------------------------------------------------------------------------|
| Config scope                      | Global: `~/.claude/settings.json`                  | Per-repo: `.github/hooks/copilot-cli-policy.json`                            |
| Hook script location              | Global: `~/.claude/hooks/*.sh`                     | Per-repo: `.github/hooks/scripts/*.sh`                                       |
| Schema version                    | n/a                                                | `"version": 1`                                                               |
| Pre-bash event name               | `PreToolUse` with `matcher: "Bash"`                | `preToolUse` (filter by `toolName == "bash"` in script)                      |
| Project dir source                | Env: `CLAUDE_PROJECT_DIR`                          | Stdin JSON: `.cwd`                                                           |
| Tool input source                 | Env: `CLAUDE_TOOL_INPUT` (raw command string)      | Stdin JSON: `.toolArgs` (JSON-stringified, parse `.command`)                 |
| Block mechanism                   | `exit 2`                                           | Stdout `{"permissionDecision":"deny","permissionDecisionReason":"..."}`      |
| Allow mechanism                   | `exit 0`                                           | `exit 0` with no `deny` JSON                                                 |
| Hook timeout default              | n/a (we set 10–15s)                                | 30s default; we set 10s (tdd) / 15s (confidence)                             |
| Confidence scorer location        | `~/.claude/scripts/confidence.sh` (global)         | TBD — see §7 Open question OQ-4 (global vs vendored)                         |
| TDD bypass marker                 | `$PROJECT_DIR/.tdd-skip`                           | Same — `$PROJECT_DIR/.tdd-skip` (project-local file, tool-agnostic)          |
| Override marker                   | `$PROJECT_DIR/.git/aw/override-<spec>`             | Same                                                                         |
| Active-spec pointer               | `$PROJECT_DIR/.git/aw/active-spec`                 | Same                                                                         |
| Confidence event log              | `$PROJECT_DIR/.context/specs/<id>-confidence.jsonl`| Same                                                                         |

The right column gives us identical bypass/override UX across both AIs:
the user only learns one set of files.

## 4. Environment / Payload Translation Table

For porting `tdd-gate.sh` and `confidence-gate.sh`:

| Claude reference                                | Copilot equivalent                                                                                          |
|-------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"`        | `PAYLOAD="$(cat)"; PROJECT_DIR="$(echo "$PAYLOAD" \| jq -r '.cwd // "."')"`                                 |
| `TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"`           | `TOOL_NAME="$(echo "$PAYLOAD" \| jq -r '.toolName // ""')"; TOOL_INPUT="$(echo "$PAYLOAD" \| jq -r '.toolArgs // "{}" \| fromjson? // {} \| .command // ""')"` |
| Early-return on non-bash tool                   | `[ "$TOOL_NAME" = "bash" ] \|\| exit 0`                                                                     |
| `exit 2` (block)                                | `jq -nc --arg r "<msg>" '{permissionDecision:"deny",permissionDecisionReason:$r}'; exit 0`                  |
| `exit 0` (allow)                                | `exit 0` (no stdout JSON)                                                                                   |
| Stderr messages (visible to Claude UI)          | Stderr messages — Copilot surfaces `permissionDecisionReason` in UI; stderr also captured in audit log      |

## Superseded by ADR-001

> **The two-script design described in §5, FR-2, FR-3, and FR-4 below was
> superseded by ADR-001 before implementation began.** The accepted
> architecture uses a **single dispatcher script**
> (`copilot-cli-dispatcher.sh`) as the sole `preToolUse` entry, rather than
> two separate hook scripts. The reasons are documented in
> `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md` (primarily:
> undocumented Copilot short-circuit ordering, and the fail-closed requirement
> which needs a single trap point).
>
> The sections below are preserved for design history. Do not use them as the
> source of truth for implementation — use ADR-001 and
> `docs/context/specs/COP-2-spec.md` instead.

## 5. `.github/hooks/copilot-cli-policy.json` — Target Schema (superseded)

> **Superseded by ADR-001.** The actual policy has one `preToolUse` entry
> pointing to `copilot-cli-dispatcher.sh`, not the two entries below.
> See `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`.

The installer writes the file below verbatim (with project-aware values
where noted). The two `preToolUse` entries map 1:1 to the Claude
`PreToolUse / matcher: Bash` entries.

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "bash": "./scripts/tdd-gate.sh",
        "cwd": ".github/hooks",
        "timeoutSec": 10,
        "comment": "Block git commit without staged test files. Mirror of ~/.claude/hooks/tdd-gate.sh"
      },
      {
        "type": "command",
        "bash": "./scripts/confidence-gate.sh",
        "cwd": ".github/hooks",
        "timeoutSec": 15,
        "comment": "Block gh pr create / glab mr create on RED confidence verdict. Mirror of ~/.claude/hooks/confidence-gate.sh"
      }
    ]
  }
}
```

The installer should not write `sessionStart`, `userPromptSubmitted`,
`postToolUse`, etc. Adding them is out of scope (see §9).

## 6. Functional Requirements

### FR-1 — Installer extension
`install_project()` MUST call a new helper `install_project_copilot_hooks()`
**after** `install_project_copilot()` and **before** `install_project_gitignore()`.
The new helper takes `$project_dir` as its sole argument.

### FR-2 — Hook script files (superseded by ADR-001)

> **Superseded by ADR-001.** The implementation installs a single
> `copilot-cli-dispatcher.sh` instead of the two separate scripts below.
> See `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`.

The installer MUST create the following files relative to `$project_dir`:

- `.github/hooks/scripts/tdd-gate.sh` — Copilot-flavored TDD gate.
- `.github/hooks/scripts/confidence-gate.sh` — Copilot-flavored confidence gate.
- `.github/hooks/copilot-cli-policy.json` — registration JSON from §5.

All three must be created with mode `0755` (or `0644` for the JSON).
Scripts MUST start with `#!/usr/bin/env bash` and include `set -euo pipefail`.

### FR-3 — TDD gate behavior parity (superseded by ADR-001)

> **Superseded by ADR-001.** TDD gate logic is now embedded directly in
> `copilot-cli-dispatcher.sh` rather than a separate `tdd-gate.sh` script.
> The behavioral requirements below still apply — they were ported into the
> dispatcher. See `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`.

`.github/hooks/scripts/tdd-gate.sh` MUST replicate every behavioral branch
of the Claude `tdd-gate.sh` (lines 2022–2069 of `ai-native-workflow`):

- Only fire when `toolName == "bash"` AND `toolArgs.command` matches `git\s+commit`.
- Allow `--amend` commits unconditionally.
- Allow when `$PROJECT_DIR/.tdd-skip` exists.
- Allow when all staged paths start with `spikes/`.
- Allow when staged file list contains a path matching the test pattern
  `(test|spec|_test\.|\.test\.|\.spec\.|tests/|__tests__/|Tests/|Test\.)`.
- Otherwise deny with the same human message text (Options 1 & 2,
  common-reasons line).

### FR-4 — Confidence gate behavior parity (superseded by ADR-001)

> **Superseded by ADR-001.** Confidence gate logic is now embedded directly in
> `copilot-cli-dispatcher.sh` rather than a separate `confidence-gate.sh`
> script. The behavioral requirements below still apply — they were ported into
> the dispatcher. See `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`.

`.github/hooks/scripts/confidence-gate.sh` MUST replicate every behavioral
branch of the Claude `confidence-gate.sh` (lines 2074 / source at
`hooks/confidence-gate.sh`):

- Only fire when `toolName == "bash"` AND `toolArgs.command` matches
  `(gh\s+pr\s+create(\s|$)|glab\s+mr\s+create(\s|$))`.
- Read `$PROJECT_DIR/.git/aw/active-spec`; deny if missing or invalid.
- Read `$PROJECT_DIR/.context/specs/<id>-confidence.jsonl`; deny if missing.
- Invoke the confidence scorer (see §7), parse `band`, `score`, `gates`.
- Append `{ts, event:"verdict", scope:"aggregate", ...}` to the log.
- GREEN → allow. YELLOW → allow with caution message.
- RED + structural-only gates + `.tdd-skip` → log auto-bypass, allow.
- RED + behavioral gates + `.tdd-skip` → deny with "use /override-confidence".
- RED + valid override marker → consume marker, log override, allow.
- RED + malformed override → delete marker, deny.
- RED + no override → deny with options message.

The denial **text** sent in `permissionDecisionReason` MUST match the
stderr text the Claude version emits, line for line, so users see the
same UX.

### FR-5 — Idempotency
Re-running `ai-native-workflow install project` MUST be safe:
- If `.github/hooks/copilot-cli-policy.json` already exists, the installer
  MUST merge our two `preToolUse` entries with any existing entries,
  deduping by the `bash` script path. This mirrors the
  `install_global_settings` jq-merge behavior (lines 1818–1828).
- If `.github/hooks/scripts/tdd-gate.sh` or `confidence-gate.sh` already
  exists with **different content**, the installer MUST back it up
  (`<name>.bak.<timestamp>`) and overwrite. (Same policy as
  `backup_if_exists` already used elsewhere.)
- If the existing file content matches what we would write, no change
  and no backup.

### FR-6 — Graceful degradation when `jq` is missing
If `jq` is not on `PATH` at install time, the installer MUST:
- Still create the script files (they will use `jq` at runtime — that
  is the user's responsibility to install `jq` for hook execution).
- Print a `warn`: "jq not found — Copilot hooks require jq at runtime.
  Install with: brew install jq".
- Continue rather than fail. (Mirrors line 1834.)

### FR-7 — `.gitignore` adjustments
`install_project_gitignore()` MUST be extended to ignore:
- `.github/hooks/logs/` (audit-log directory used by Copilot tutorial conventions, even though we don't use it directly today — future-proofing).

`.github/hooks/copilot-cli-policy.json` and `.github/hooks/scripts/*` MUST
**stay tracked** — they are project policy.

### FR-8 — Confidence scorer resolution (decision pending — see §7)
The Copilot `confidence-gate.sh` MUST locate `confidence.sh` via one of:
- (A) the globally-installed copy at `~/.claude/scripts/confidence.sh`
  (since the Claude installer puts it there);
- (B) a vendored copy at `.github/hooks/scripts/confidence.sh` written
  by the installer;
- (C) a `$ANW_CONFIDENCE_SCORER` env var set by the policy `env` block,
  defaulting to (A).

Recommendation: **(B) vendored copy**. Rationale in §7. Final choice
is the architect's; this requirement just demands a single deterministic
resolution path documented at the top of `confidence-gate.sh`.

## 7. Confidence Scorer Resolution — Trade-offs

The Claude version uses a path relative to its own location:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
... "$SCRIPT_DIR/../scripts/confidence.sh" ...
```
That works because `~/.claude/scripts/confidence.sh` is sibling to
`~/.claude/hooks/`. In the per-project Copilot layout there is no
sibling `scripts/` directory automatically.

| Option                                  | Pros                                                                                       | Cons                                                                                                                       |
|-----------------------------------------|--------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------|
| **(A) Use global ~/.claude/scripts**    | Single source of truth; brew updates propagate automatically.                              | Couples Copilot policy to Claude install; breaks for users who have only Copilot. Cross-tool coupling smell.                |
| **(B) Vendor into `.github/hooks/scripts/confidence.sh`** | Self-contained per-project; works without Claude installed; commit history visible. | Drift: scorer logic can fall behind the brew-managed copy. Re-running installer would need to refresh it.                   |
| **(C) Env-var with default**            | Flexible; testable.                                                                        | Complexity surface; users have to know the var.                                                                             |

**Recommended: (B).** It matches the spirit of "per-project hooks =
per-project enforcement," makes the gate work for Copilot-only users,
and FR-5 (idempotency / refresh-on-reinstall) covers the drift concern.
The `_ANW_SCRIPT_DIR` BREW-1 work makes copying this file at install
time as cheap as the existing Claude scorer copy on line 2084.

## 8. Non-Functional Requirements

### NFR-1 — Hook scripts executable
Both shell scripts created under `.github/hooks/scripts/` MUST have the
executable bit set after the installer runs. This is verified by:
`test -x .github/hooks/scripts/tdd-gate.sh && test -x .github/hooks/scripts/confidence-gate.sh`.

### NFR-2 — JSON validity
`copilot-cli-policy.json` MUST be parseable by `jq -e .` after the
installer runs (no trailing commas, valid UTF-8). The installer SHOULD
pipe the generated content through `jq` before writing.

### NFR-3 — Hooks fire on the right event only
The Copilot `preToolUse` entry triggers on **every** tool use (file
reads, etc.), not only bash. The very first lines of each script MUST
short-circuit (`exit 0`) when `toolName != "bash"`, before doing any
work. Performance budget: each gate should add < 100 ms to non-bash
tool calls.

### NFR-4 — No external network
Neither hook script MAY perform network I/O. (Same constraint Claude's
hooks already meet.)

### NFR-5 — Atomicity of file writes
The installer MUST write `copilot-cli-policy.json` atomically (write
to `<file>.tmp` then `mv`). This already matches the pattern at line
1829.

### NFR-6 — Cross-platform tooling
Scripts use only POSIX-portable bash + `jq` + `git` + `grep`. No GNU-only
flags. (The Claude versions already meet this.)

### NFR-7 — Deterministic output for the same input
Two installer runs over the same project directory MUST produce
byte-identical hook scripts and a `copilot-cli-policy.json` that
differs only in the order of entries iff there were no prior entries.

## 9. Out of Scope

- **Global Copilot hooks.** Copilot has no global hook concept. Do not
  attempt to write `~/.copilot/hooks.json`.
- **Other event types.** `sessionStart`, `userPromptSubmitted`,
  `agentStop`, etc. — none are needed for COP-2. Future work can add
  audit logging via `userPromptSubmitted` if desired.
- **PowerShell variants.** Mac/Linux is the target platform (per
  `CLAUDE.md` profile). The `powershell` field is omitted from the
  policy JSON.
- **Updating Copilot CLI to gate `gh`/`glab` directly via its own
  permission prompt UI.** Use the hook mechanism only.
- **Modifying the Claude hooks** to share logic with Copilot. We are
  porting, not refactoring.
- **Tests for the scripts themselves at the unit level beyond what
  bats already covers for the Claude versions.** New bats coverage
  for COP-2 is in scope (see §11.4).

## 10. Open Questions / Blockers

- **OQ-1 (medium)**: Does Copilot CLI short-circuit `preToolUse` on the
  first `deny`, or does it run all entries in declaration order? The
  docs do not say. **Resolution path**: spike during architect step —
  manually craft a two-entry policy where entry 1 denies and entry 2
  has `set -e; exit 1`, observe behavior. If it does NOT short-circuit,
  we may need to fold both gates into a single dispatcher script.
- **OQ-2 (low)**: Are multiple files in `.github/hooks/*.json` merged
  by Copilot, or does only one win? Not relevant for v1 (we use a
  single file) but informs FR-5 idempotency design if we ever need to
  coexist with hooks the user added themselves.
- **OQ-3 (medium)**: Is `cwd` in the stdin payload **always** the repo
  root, or is it the user's actual `pwd` when they invoked Copilot?
  If the latter, `PROJECT_DIR` resolution must walk up to the
  enclosing `.git/`.
- **OQ-4 (low)**: §7 — confirm with user that the recommended scorer
  resolution is option (B) vendored.
- **OQ-5 (medium)**: Does Copilot's `permissionDecisionReason` get
  surfaced to the user with the same prominence Claude's stderr does?
  If not, we may need to also `>&2 echo` the message so the user sees
  it in the terminal regardless of Copilot's UI choices.
- **OQ-6 (low)**: Should we also write a stub `.github/hooks/README.md`
  explaining what these files are, so engineers reviewing the PR don't
  delete them? Recommend yes; out of FR scope.

## 11. Acceptance Criteria

All criteria are testable. Tests live in
`tests/install-project-copilot-hooks.bats` (new file, follows the
pattern of existing `tests/*.bats` in this repo).

### 11.1 Installer creates the files

- **AC-1 (Given/When/Then)**:
  - **Given** an empty git repo without `.github/hooks/`,
  - **When** I run `ai-native-workflow install project`,
  - **Then** `.github/hooks/copilot-cli-policy.json` exists,
    `.github/hooks/scripts/tdd-gate.sh` exists and is executable,
    `.github/hooks/scripts/confidence-gate.sh` exists and is
    executable, and (if option B) `.github/hooks/scripts/confidence.sh`
    exists and is executable.

- **AC-2**: The generated `copilot-cli-policy.json` parses as valid
  JSON (`jq -e . < .github/hooks/copilot-cli-policy.json` returns 0)
  and has exactly two entries under `.hooks.preToolUse`, with `bash`
  values `./scripts/tdd-gate.sh` and `./scripts/confidence-gate.sh`.

### 11.2 Idempotency

- **AC-3**: Running the installer twice in a row produces no diff in
  the working tree on the second run (`git status --porcelain` empty
  after second invocation, given a clean state after the first).

- **AC-4**: If a user has pre-existing entries in
  `copilot-cli-policy.json` under `preToolUse` (e.g. a custom
  audit-log hook), running the installer preserves those entries
  AND adds our two, deduping by `bash` path.

- **AC-5**: If a user has hand-edited `.github/hooks/scripts/tdd-gate.sh`,
  running the installer creates a backup `tdd-gate.sh.bak.<ts>` and
  overwrites with the canonical script.

### 11.3 TDD gate parity

- **AC-6 (Given/When/Then)**:
  - **Given** the Copilot TDD gate is installed and no test files are
    staged,
  - **When** Copilot tries to run `bash` with command
    `git commit -m "feat: thing"`,
  - **Then** the hook returns
    `{"permissionDecision":"deny","permissionDecisionReason":"…TDD GATE…"}`
    and Copilot does not run the commit.

- **AC-7**: Same setup but `.tdd-skip` exists → no `deny`, command
  proceeds.

- **AC-8**: Same setup but a staged file matches the test pattern →
  no `deny`.

- **AC-9**: Command is `git commit --amend` → no `deny`.

- **AC-10**: Command is `git status` → hook exits 0 with no JSON
  (allow path).

- **AC-11**: `toolName` is not `bash` (e.g. file read tool) → hook
  exits 0 with no JSON, no `jq` parsing of `toolArgs` happens.

### 11.4 Confidence gate parity

- **AC-12 (Given/When/Then)**:
  - **Given** an active spec `FOO-1` with a confidence log whose
    aggregate verdict is GREEN (mock the scorer),
  - **When** Copilot tries to run `bash` with command `gh pr create`,
  - **Then** the hook exits 0 with no `deny` and the log gets a new
    `{event:"verdict",band:"GREEN"}` line.

- **AC-13**: Same with RED and no `.tdd-skip` and no override marker
  → hook returns `deny` with the "RED" message and lists gates.

- **AC-14**: RED + override marker present → marker consumed (file
  removed), log appended, allow.

- **AC-15**: RED + `.tdd-skip` + structural-only gates → auto-bypass,
  allow.

- **AC-16**: RED + `.tdd-skip` + behavioral gates → deny with
  "use /override-confidence" text.

- **AC-17**: Command is `git push` (not `gh pr create` or
  `glab mr create`) → allow.

- **AC-18**: No active-spec pointer → deny with the missing-pointer
  message.

### 11.5 End-to-end with real Copilot CLI (smoke; manual)

- **AC-19**: Manual smoke — install in a sample repo, set up an active
  spec, run `copilot --agent=tdd-developer …` driving a commit attempt
  without test files; confirm Copilot UI surfaces the deny reason.
  (Documented in `tests/manual/COP-2-smoke.md`. Not in CI.)

## 12. Risks & Surprises

These are aspects where Copilot's hook semantics differ from Claude's
in ways that affect enforcement guarantees. Surface to architect.

### R-1 (HIGH) — `deny` is communicated via stdout, not exit code
This is a semantic departure. If the hook script crashes (e.g. `set -e`
kills it before printing the JSON), the **action is allowed**, not
blocked. Claude's `exit 2` is the safer default-deny. **Mitigation**:
the script must `trap` errors and emit a `deny` JSON in the trap, so
crashes fail closed.

### R-2 (HIGH) — No `matcher` field
Every `preToolUse` hook fires on every tool use, including file
reads, edits, etc. The script-side filter `toolName == "bash"` MUST
be the literal first line of work. If we forget, we slow every tool
use by tens of ms and risk false denies.

### R-3 (MEDIUM) — Repo-scoped only
Engineers cloning the repo for the first time may run Copilot CLI
before our installer has run, meaning the gates do not exist. Unlike
Claude (global), the hooks travel with the repo as committed files.
**Mitigation**: docs MUST explain "commit `.github/hooks/` after install
or your team is unprotected."

### R-4 (MEDIUM) — Per-project means N installs
Every repo needs its own install. Fix is operational, not technical:
a `pre-commit` of an org-wide template, or a CI check that
`copilot-cli-policy.json` exists with our two entries. Both are out
of scope for COP-2.

### R-5 (MEDIUM) — `cwd` payload field semantics unconfirmed (OQ-3)
If `cwd` is not the repo root, `PROJECT_DIR` resolution is wrong,
and `git diff --cached` will fail in unexpected ways. Mitigation:
fall back to `git -C "$cwd" rev-parse --show-toplevel` and use the
result.

### R-6 (LOW) — `toolArgs` is double-encoded JSON
Easy to miss. Documentation calls it "a JSON string." First `jq` parse
extracts the string; second parse extracts `.command`. The translation
table in §4 covers it but reviewers should verify both `jq` calls.

### R-7 (LOW) — Hook timeout is 30s default; long-running git operations
If the user has a slow `git diff --cached` (huge repo) the TDD gate
could time out. We set 10s explicitly. **Mitigation**: same as Claude,
which sets 10s. Document it.

### R-8 (LOW) — Order/short-circuit unconfirmed (OQ-1)
If Copilot does NOT short-circuit on the first `deny`, the
confidence gate might still run after the TDD gate denied. Worst case:
extra log writes. Best case: confidence gate just exits 0 because the
command is not `gh pr create`. No correctness risk identified, but
worth confirming.

## 13. Test Plan Outline (for QA agent)

### 13.1 Unit tests (bats) — installer behavior
- Files created with correct paths and modes (covers AC-1).
- JSON validity (covers AC-2).
- Idempotency single re-run (covers AC-3).
- Idempotency with pre-existing custom hook (covers AC-4).
- Backup-on-content-mismatch (covers AC-5).
- Behavior when `jq` is absent at install time (FR-6 — should warn but
  not abort).

### 13.2 Unit tests (bats) — script behavior in isolation
Each script is invoked with a synthetic stdin payload and the exit code
+ stdout JSON is asserted. Covers AC-6 through AC-18. Test fixtures:

- A function `mk_payload` that produces stdin JSON for a given
  toolName + command + cwd.
- A temp git repo with controllable staged files.
- A mock `confidence.sh` that emits a configurable verdict JSON
  (GREEN/YELLOW/RED + gates).

### 13.3 Integration tests (bats)
- End-to-end install in a tmp dir, then run each hook script with a
  real payload, assert behavior.

### 13.4 Manual smoke test
- AC-19 — documented but not automated.

### 13.5 Edge cases to exercise
- Payload with missing `cwd` — script should default to `.` and
  log a warning.
- Payload with malformed `toolArgs` — script should fail closed
  (`deny` with reason "malformed payload").
- `.tdd-skip` with no `Reason:` line in confidence-gate auto-bypass
  path.
- Override marker file with no `reason` field (should delete + deny;
  parity with Claude line 100–103).
- Active-spec ID containing `..` or `/` (regex rejection — AC for
  the same exists for Claude).
- Confidence log path that resolves to a symlink outside the repo
  (low priority; document only).

## 14. Hand-off

When this spec is approved:

> Use architect to design the solution based on
> `docs/context/specs/COP-2-requirements.md`.

The architect should resolve OQ-1, OQ-3, OQ-4 before writing the todo
plan, and decide between port / wrap / shared-script for code reuse
(see user's prompt — three options). My recommendation: **port with
shared confidence-scorer file (option B)**, because (a) the Claude and
Copilot scripts have to diverge anyway on payload parsing and decision
shape, so a "shared" script would be 80% conditionals; (b) a vendored
`confidence.sh` keeps the Copilot path self-contained.
