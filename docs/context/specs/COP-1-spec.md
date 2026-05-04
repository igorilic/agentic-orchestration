# COP-1 — Symmetric Copilot CLI harness for `install global`

**Status:** Accepted (architect)
**Date:** 2026-05-02
**Owner:** architect → tdd-developer
**Source:**
- Requirements: `docs/context/specs/COP-1-requirements.md`
- User instruction: this thread (`go` accept-all-defaults on OQ-1..OQ-6)
- Related code:
  - `ai-native-workflow:1659` (`install_global`)
  - `ai-native-workflow:3157` (`install_copilot_agents`)
  - `ai-native-workflow:4054` (`show_status`)
  - `ai-native-workflow:4191` (`uninstall_global`)
  - `Formula/ai-native-workflow.rb` (brew formula, packages `libexec/skills/`)

---

## 1. Problem statement

`install global` already gives Claude Code a full harness — global
instructions (`CLAUDE.md`), `settings.json` with hooks, helper scripts,
all 14 skills as `<name>/SKILL.md` directories, and 7 agents. The Copilot
CLI side gets only **agents**. After running `install global`, a fresh
`copilot` session has no skills, no global instructions, and no seeded
settings — every prior user has had to populate those by hand.

COP-1 closes the symmetry gap for everything that has a global Copilot
equivalent. Hooks are explicitly out of scope (Copilot CLI scopes hooks
per-repo only, deferred to COP-2).

## 2. Context

### What the Claude side does today

`install_global` orchestrates six sub-functions
(`install_global_claude_md`, `install_global_settings`,
`install_global_hooks`, `install_global_scripts`,
`install_global_skills`, `install_global_agents`) that all write under
`CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"`. Each uses
`backup_if_exists` (`ai-native-workflow:64`) before overwriting and
honors `CLAUDE_HOME` for hermetic sandbox testing (this is how the bats
suite at `tests/install.bats` runs the installer into `mktemp -d`).

### What the Copilot side does today

Only `install_copilot_agents` (`ai-native-workflow:3157`) runs. It:

- guards on `command -v copilot` (skips if absent, exit 0)
- writes 7 `*.agent.md` files into `${COPILOT_HOME:-$HOME/.copilot}/agents/`
- does **not** call `backup_if_exists` (silent overwrite — see fix below)
- defines `COPILOT_DIR` as a function-local variable

The skills source dir (`skills/<name>/SKILL.md`, plus the
`override-confidence/skill.bash` helper) is already shipped by the brew
formula via `libexec.install Dir["skills", ...]` (formula L36) and the
CLI's `_ANW_SCRIPT_DIR` (post-BREW-1) resolves through symlinks to find
it. So we can `cp -R` from `$_ANW_SCRIPT_DIR/skills/` for the Copilot
install (OQ-1 default — option **b**).

### What the user actually has on disk

The repo's `skills/` directory contains exactly **14** subdirectories:

```
adr  brainstorm  clusters  explore  override-confidence
pipeline-github-feature  pipeline-gitlab-feature  pipeline-gitlab-incident
plan  pr  session-report  skip-tdd  tdd  ticket
```

The requirements doc speculatively listed 17 skills (`security-review`,
`k8s`, `kibana`, `app-insights` are aspirational and not present in the
repo today). **This spec ships the 14 that exist.** If new skills are
added later, the install logic — which iterates the source directory —
picks them up automatically with no code change.

### Constraint inherited from CTX-1

CTX-1 introduced top-level constants (`SPEC_DIR`, `SPRINT_FILE`) at the
top of the script. We extend the same pattern: introduce `COPILOT_DIR`
(promoted from a function-local), `COPILOT_SKILLS_DIR`,
`COPILOT_INSTRUCTIONS_FILE`, `COPILOT_SETTINGS_FILE`, `COPILOT_AGENTS_DIR`
as top-level constants alongside the existing `CLAUDE_DIR`. This keeps
the install/status/uninstall paths consistent and grep-able.

### Constraint inherited from BREW-1

`_ANW_SCRIPT_DIR` (`ai-native-workflow:118`) resolves through symlink
chains, so `$_ANW_SCRIPT_DIR/skills/<name>/SKILL.md` works whether the
CLI is invoked from the repo, from `brew --prefix`, or from a symlink.
The new install functions rely on this without further work.

## 3. Proposed solution

### 3.1 New top-level constants

Add immediately below the existing `CLAUDE_DIR` line at the top of the
script:

```bash
COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"
COPILOT_AGENTS_DIR="$COPILOT_DIR/agents"
COPILOT_SKILLS_DIR="$COPILOT_DIR/skills"
COPILOT_INSTRUCTIONS_FILE="$COPILOT_DIR/copilot-instructions.md"
COPILOT_SETTINGS_FILE="$COPILOT_DIR/settings.json"
```

The existing function-local `local COPILOT_DIR=...` declarations in
`install_copilot_agents` (`ai-native-workflow:3165`), `show_status`
(`ai-native-workflow:4088`), and `uninstall_global`
(`ai-native-workflow:4233`) are removed in favor of the global constant.

### 3.2 New install functions

Three new functions, all gated by the same `command -v copilot` check
that `install_copilot_agents` already uses (FR-5 — graceful when Copilot
CLI absent). All three honor `COPILOT_HOME` via the constants above.

#### `install_global_copilot_skills`

- Iterate every immediate subdirectory of `$_ANW_SCRIPT_DIR/skills/`.
- For each `<name>`, ensure `$COPILOT_SKILLS_DIR/<name>/` exists, run
  `backup_if_exists` on the target SKILL.md, then `cp -R` source files.
- The only post-copy transform is for skills that contain
  `claude --agent=` — those get sed-rewritten to `copilot --agent=` so
  hand-off lines work in a Copilot session (FR-2 last paragraph).
  Currently affects 3 skills: `pipeline-gitlab-feature`,
  `pipeline-gitlab-incident`, `explore`.
- Print a `success "/<name> skill"` line per skill.

#### `install_global_copilot_instructions`

- Target `$COPILOT_INSTRUCTIONS_FILE`.
- `backup_if_exists` then write a heredoc with content semantically
  equivalent to `~/.claude/CLAUDE.md` but with Copilot-neutral phrasing
  (no `Claude Code session`, no `~/.claude/`, slash-skill examples
  written generically).
- Single source of truth principle: the spec acknowledges these two
  files have parallel content. To prevent drift over time, the
  `install_global_claude_md` and `install_global_copilot_instructions`
  functions are placed adjacent in the script and the heredocs are kept
  side-by-side so any future edit surfaces both.

#### `install_global_copilot_settings`

Mirrors `install_global_settings` but without the `hooks` key (Copilot
CLI scopes hooks per-repo, FR-4 last paragraph).

- Fresh install (target absent): write
  `{"renderMarkdown": true, "theme": "auto", "beep": true}` (OQ-5
  default — seed `beep: true`).
- Re-install with existing target: `backup_if_exists`, then if `jq`
  available, additive merge (preserve existing keys, only add missing
  ones; mirrors the Claude `*` deep-merge but no array union since
  there are no arrays in scope).
- `jq` absent: warn, leave file alone (mirrors Claude fallback).

### 3.3 Wiring

`install_global` (`ai-native-workflow:1659`) gains three new lines after
the existing `install_copilot_agents` call:

```bash
install_copilot_agents              # existing
install_global_copilot_skills       # NEW
install_global_copilot_instructions # NEW
install_global_copilot_settings     # NEW
```

The closing banner is restructured per OQ-6 (one banner, two
sub-sections):

```
Global installation complete

  Claude Code → ~/.claude/
    [list of installed Claude artifacts]

  Copilot CLI → ~/.copilot/
    [list of installed Copilot artifacts, or "Copilot CLI not found — skipped"]

  ▸ Copilot hooks are NOT installed globally — Copilot CLI scopes hooks
    per-repo. Run `ai-native-workflow install project` in each trusted
    folder to set up repo-level hooks (COP-2; not yet shipped).
```

The hooks caveat (OQ-4 default — yes, nudge user) is printed
unconditionally even when Copilot CLI is absent so users learn of the
boundary.

### 3.4 Status command additions

`show_status` (`ai-native-workflow:4054`) gains, immediately after the
existing `agents/troubleshooter.agent.md` and `agents/explorer.agent.md`
checks (around L4098):

```bash
check_file "$COPILOT_INSTRUCTIONS_FILE" "copilot-instructions.md"
check_file "$COPILOT_SETTINGS_FILE" "settings.json"
for d in "$COPILOT_SKILLS_DIR"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  check_file "$d/SKILL.md" "skills/$name"
done
```

(The dynamic skills loop avoids hardcoding 14 names that drift from
`skills/` source.)

### 3.5 Uninstall additions

`uninstall_global` (`ai-native-workflow:4191`) gains `COPILOT_INSTRUCTIONS_FILE`
and `COPILOT_SETTINGS_FILE` in the explicit removal list (skills go via
`rm -rf "$COPILOT_SKILLS_DIR"`, mirroring how the Claude side removes
`$CLAUDE_DIR/skills/<name>` per-name today). Settings.json is removed
to match the Claude side's "we warn, we don't delete settings" policy
— EXCEPT: the Claude side keeps `settings.json` and `CLAUDE.md` and
just warns (`ai-native-workflow:4229`). For symmetry, the Copilot side
also keeps `copilot-instructions.md` and `settings.json` and warns.
Only skills and (existing) agents are removed.

### 3.6 Documentation updates

- **README.md**: extend the "Quick Start" / "What gets installed"
  section to list the new Copilot artifacts. One short paragraph noting
  the hooks asymmetry (repo-scope only on Copilot side).
- **docs/ARCHITECTURE.md**: extend the three-layer diagram caption to
  call out which layers exist for which CLI. Add a one-paragraph
  "Symmetric harness" subsection under "Workflow Architecture" that
  states: skills + agents + global instructions are symmetric; hooks
  are asymmetric (Claude global, Copilot repo-scope per COP-2).

## 4. Acceptance criteria

These extend the requirement-level ACs in `COP-1-requirements.md` with
specific test fixtures. Every AC maps to one or more bats `@test`
cases.

### AC-1 — Skills install (every skill in source)

**Given** a clean `COPILOT_HOME=$SANDBOX` and `command -v copilot`
returns 0 (the test stubs a fake `copilot` shim in PATH),
**When** `ai-native-workflow install global` runs,
**Then** for every immediate subdirectory `<name>` in
`$_ANW_SCRIPT_DIR/skills/` (currently 14: adr, brainstorm, clusters,
explore, override-confidence, pipeline-github-feature,
pipeline-gitlab-feature, pipeline-gitlab-incident, plan, pr,
session-report, skip-tdd, tdd, ticket), the file
`$SANDBOX/skills/<name>/SKILL.md` exists and is non-empty.

### AC-2 — Pipeline skills are Copilot-rewritten

**Given** the source `skills/pipeline-gitlab-feature/SKILL.md` contains
the literal `claude --agent=`,
**When** `install global` runs into a sandbox,
**Then** the installed copy at
`$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md` contains
`copilot --agent=` and contains zero occurrences of `claude --agent=`.
Same assertion for `pipeline-gitlab-incident` and `explore`.

### AC-3 — Global instructions installed

**Given** a clean sandbox,
**When** `install global` runs,
**Then** `$SANDBOX/copilot-instructions.md` exists and contains the
marker substrings `Stack Detection`, `Agent Pipeline`, and `/plan`
(presence-only check — verifies semantic equivalence to CLAUDE.md
without locking byte-for-byte).

### AC-4 — Settings.json fresh install

**Given** no `$SANDBOX/settings.json` (Copilot side),
**When** `install global` runs,
**Then** `$SANDBOX/settings.json` exists, parses as JSON,
`jq -r '.renderMarkdown'` returns `true`, `jq -r '.beep'` returns
`true`, and `jq -e '.hooks'` returns non-zero (no hooks key).

### AC-5 — Settings.json merge preserves user keys

**Given** an existing
`$SANDBOX/settings.json = {"model":"gpt-5","effortLevel":"high","allowedUrls":["https://example.com"]}`,
**When** `install global` runs,
**Then** all three user keys are preserved with original values, AND a
`settings.json.bak.<timestamp>` exists alongside, AND `renderMarkdown`,
`theme`, and `beep` are now also present (additive merge).

### AC-6 — Re-install backs up copilot-instructions.md

**Given** `install global` has run once and produced
`$SANDBOX/copilot-instructions.md`,
**When** `install global` runs a second time,
**Then** exactly one file matching `copilot-instructions.md.bak.*`
exists alongside the live file.

### AC-7 — `COPILOT_HOME` honored end-to-end

**Given** `COPILOT_HOME=/tmp/cop-test-XXX`,
**When** `install global` runs,
**Then** all new artifacts (`skills/`, `copilot-instructions.md`,
`settings.json`) are written under `/tmp/cop-test-XXX/`, AND
`~/.copilot/` (resolved at the time the test runs, BUT see test note
below) is untouched.

> Test note: the bats suite already isolates `HOME` checks by writing
> only into `$SANDBOX`. We assert "no writes outside sandbox" by
> snapshotting the sandbox parent before and after.

### AC-8 — Copilot CLI absent: graceful skip

**Given** `command -v copilot` returns non-zero (the test prepends an
empty PATH dir that shadows any real `copilot`),
**When** `install global` runs,
**Then** exit code is 0, the Claude side completes normally, and
`$SANDBOX` (set as `COPILOT_HOME`) remains empty (no `skills/`,
no `copilot-instructions.md`, no `settings.json`).

### AC-9 — Idempotent re-run

**Given** `install global` has run once,
**When** it runs a second time,
**Then** every Copilot artifact's content equals the first-run content
byte-for-byte (or, for settings.json, has the same JSON shape with
original user keys preserved), AND each writable target has gained
exactly one new `.bak.<timestamp>` from the second run.

### AC-10 — Status command lists Copilot artifacts

**Given** `install global` has run successfully,
**When** the user runs `ai-native-workflow status` (with the same
`COPILOT_HOME=$SANDBOX`),
**Then** stdout contains one ✓ line per installed Copilot skill name,
plus a ✓ line for `copilot-instructions.md` and `settings.json`.

### AC-11 — Uninstall removes the new artifacts

**Given** `install global` has run successfully,
**When** the user runs `ai-native-workflow uninstall global`,
**Then** `$SANDBOX/skills/` is empty or absent, AND
`copilot-instructions.md` and `settings.json` are **preserved** (with a
warning printed) — symmetric to the Claude side's "preserve
settings.json and CLAUDE.md" rule.

### AC-12 — Caveat about hooks is printed

**Given** any `install global` run that reaches completion (Copilot
present or absent),
**When** the closing banner prints,
**Then** stdout contains the literal substring
`Copilot hooks are NOT installed globally`.

### AC-13 — README + ARCHITECTURE updated

**Given** the repo at the merge of COP-1,
**When** the README and `docs/ARCHITECTURE.md` are read,
**Then** README mentions `~/.copilot/skills/`, `~/.copilot/copilot-instructions.md`,
and `~/.copilot/settings.json`; AND `docs/ARCHITECTURE.md` notes that
hooks are Claude-global, Copilot-repo-scope.

## 5. Technical design

### 5.1 Components

| Component | File | Lines (approx) | Action |
|---|---|---|---|
| Top-level `COPILOT_*` constants | `ai-native-workflow` | after L28 | NEW |
| `install_global_copilot_skills` | `ai-native-workflow` | new fn after `install_copilot_agents` | NEW |
| `install_global_copilot_instructions` | `ai-native-workflow` | new fn, sibling of above | NEW |
| `install_global_copilot_settings` | `ai-native-workflow` | new fn, sibling of above | NEW |
| `install_global` orchestrator | `ai-native-workflow:1659` | edit (3 new calls + banner change) | EDIT |
| `install_copilot_agents` | `ai-native-workflow:3157` | drop `local COPILOT_DIR=...` | EDIT |
| `show_status` | `ai-native-workflow:4054` | drop `local COPILOT_DIR=...`, add 2 file checks + skills loop | EDIT |
| `uninstall_global` | `ai-native-workflow:4191` | drop `local COPILOT_DIR=...`, add skills rm-rf, warn-preserve for instructions/settings | EDIT |
| Tests | `tests/install-copilot.bats` (new) | new file | NEW |
| Docs | `README.md`, `docs/ARCHITECTURE.md` | edits | EDIT |

### 5.2 Data: skill source layout (read-only)

All data is read from `$_ANW_SCRIPT_DIR/skills/<name>/`. Each skill is
one or more files; we copy the entire directory verbatim. No SKILL.md
parsing is required (per OQ-2 and OQ-3 defaults — trust Copilot's
description semantics, do not add `allowed-tools`).

### 5.3 The `claude → copilot` rewrite

Per FR-2 last paragraph, three skills (`pipeline-gitlab-feature`,
`pipeline-gitlab-incident`, `explore`) reference `claude --agent=` in
their hand-off lines. After copy:

```bash
sed -i.tmp 's/claude --agent=/copilot --agent=/g' \
  "$COPILOT_SKILLS_DIR/<name>/SKILL.md"
rm -f "$COPILOT_SKILLS_DIR/<name>/SKILL.md.tmp"
```

The `.tmp` suffix is for cross-platform `sed -i` portability (BSD vs
GNU). We use `.tmp`, not the `BACKUP_SUFFIX` global, to avoid the bats
"exactly one backup per file" assertions seeing stray files from the
sed step.

The list of skills to rewrite is detected dynamically:

```bash
for skill_md in "$COPILOT_SKILLS_DIR"/*/SKILL.md; do
  if grep -q 'claude --agent=' "$skill_md" 2>/dev/null; then
    sed -i.tmp 's/claude --agent=/copilot --agent=/g' "$skill_md"
    rm -f "${skill_md}.tmp"
  fi
done
```

This is robust against new pipeline skills being added later.

### 5.4 settings.json merge logic

```bash
install_global_copilot_settings() {
  local fresh_json='{"renderMarkdown": true, "theme": "auto", "beep": true}'
  if [ ! -f "$COPILOT_SETTINGS_FILE" ]; then
    mkdir -p "$COPILOT_DIR"
    echo "$fresh_json" | jq '.' > "$COPILOT_SETTINGS_FILE"
    success "~/.copilot/settings.json (fresh install with beep:true)"
    return
  fi
  backup_if_exists "$COPILOT_SETTINGS_FILE"
  if ! command -v jq &>/dev/null; then
    warn "jq not found — leaving settings.json untouched"
    return
  fi
  # Additive merge: existing keys win, defaults fill the gaps.
  # `$existing * $defaults` would let defaults overwrite; we want the
  # opposite: `$defaults * $existing` — defaults first, existing wins.
  echo "$fresh_json" \
    | jq --slurpfile existing "$COPILOT_SETTINGS_FILE" \
         '. * $existing[0]' \
    > "$COPILOT_SETTINGS_FILE.tmp"
  mv "$COPILOT_SETTINGS_FILE.tmp" "$COPILOT_SETTINGS_FILE"
  success "~/.copilot/settings.json (merged with existing)"
}
```

The merge order `$defaults * $existing[0]` is the inverse of the
Claude-side merge (`$existing * $new`) because the Copilot rule is
"existing user keys win" (FR-4), whereas the Claude rule is
"installer-managed hooks always reflect the current installer".

### 5.5 Test stub for fake `copilot` binary

The bats suite needs to make `command -v copilot` return success
without requiring the real Copilot CLI. The pattern (already used
elsewhere for similar tests):

```bash
setup() {
  SANDBOX="$(mktemp -d /tmp/aw-cop-XXXXXX)"
  STUB_BIN="$(mktemp -d /tmp/aw-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/copilot"
  chmod +x "$STUB_BIN/copilot"
  export PATH="$STUB_BIN:$PATH"
  export COPILOT_HOME="$SANDBOX"
  export CLAUDE_HOME="$(mktemp -d /tmp/aw-claude-XXXXXX)"
}
teardown() {
  rm -rf "$SANDBOX" "$STUB_BIN" "$CLAUDE_HOME"
}
```

For the "Copilot absent" test (AC-8), do not stub:

```bash
@test "install global: skips Copilot section when copilot is not on PATH" {
  # Empty PATH dir prepended; system PATH retained for jq and bash
  EMPTY_BIN="$(mktemp -d /tmp/aw-empty-XXXXXX)"
  PATH="$EMPTY_BIN:/usr/bin:/bin" \
    CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    "$INSTALLER" install global >/dev/null 2>&1
  [ ! -d "$SANDBOX/skills" ]
  [ ! -f "$SANDBOX/copilot-instructions.md" ]
  [ ! -f "$SANDBOX/settings.json" ]
  rm -rf "$EMPTY_BIN"
}
```

## 6. Risks

- **R-1: `sed -i` portability.** macOS BSD sed and GNU sed disagree on
  `-i` empty-arg handling. Mitigation: always pass an explicit suffix
  (`-i.tmp`), then `rm -f` the suffixed file. Already shown in §5.3.
- **R-2: The Claude `install_global_settings` re-merges hooks on every
  re-install, generating a `.bak` per run. The Copilot
  `install_global_copilot_settings` will do the same — bats AC-9
  test must check for "exactly one new backup per second run" not
  "no backups across two runs".
- **R-3: `install_global_copilot_settings` uses `jq` to write the
  fresh-install JSON. If jq is unavailable, fresh install fails with a
  shell error. Mitigation: guard the fresh path with `command -v jq`
  the same way the merge path does, and fall back to a heredoc literal
  in the no-jq case (the JSON is short and stable).
- **R-4: A user with a hand-edited `~/.copilot/skills/<name>/` may be
  surprised to see their content overwritten. The `backup_if_exists`
  call mitigates this — the original is preserved with a `.bak.*`
  suffix. The caveats banner mentions this.
- **R-5: Single-source-of-truth drift between `CLAUDE.md` and
  `copilot-instructions.md`. Mitigation in §3.2: keep the heredoc
  functions adjacent in the script. Track a follow-up (out of scope
  here) to extract a common template.

## 7. Out of scope

Reaffirmed from the requirements doc:

- **OOS-1**: Project-level Copilot hooks (`.github/hooks/*.json`) —
  tracked as **COP-2**.
- **OOS-2**: MCP server config (`~/.copilot/mcp-config.json`).
- **OOS-3**: `copilot login` / authentication.
- **OOS-4**: Copilot plugins (`/plugin`).
- **OOS-5**: Per-stack global Copilot instructions.

Also explicitly out of scope for COP-1 (architect call):

- **OOS-6**: Refactoring the Claude install path to also `cp -R` from
  `$_ANW_SCRIPT_DIR/skills/` (OQ-1 option **c**). Today the Claude
  side uses a mix of heredocs and `cp` (`override-confidence` is
  already cp-based; the rest are heredocs). A unifying refactor is
  worthwhile but adds risk and review surface to COP-1; tracked as a
  follow-up.
- **OOS-7**: Adding `allowed-tools` or `tools:` frontmatter to skills
  or agents (OQ-3 default — conservative).
- **OOS-8**: Verifying Copilot's `description:` auto-load semantics
  (OQ-2 default — trust them; revisit if behavior surprises).

## 8. References

- Requirements: `docs/context/specs/COP-1-requirements.md`
- BREW-1 spec: `docs/context/specs/BREW-1-anw-script-dir-symlink.md`
- CTX-1 todo (path-constants pattern): `docs/context/specs/CTX-1-todo.md`
- Existing bats fixtures: `tests/install.bats`
- Brew formula (skills shipped to libexec): `Formula/ai-native-workflow.rb`
  (in `igorilic/homebrew-tools` tap repo)
