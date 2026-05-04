# COP-2: Install Copilot CLI hooks per-project (TDD + confidence gates)

> Source: `docs/context/specs/COP-2-requirements.md` (requirements-engineer)
> Defaults accepted by user on 2026-05-02 (`go`).
> ADR: `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`

## 1. Problem statement

Engineers using GitHub Copilot CLI in a repo today have **no enforcement**
of the TDD gate or the confidence gate. The Claude side has these gates
(global `~/.claude/hooks/*.sh` registered in `settings.json`), but
Copilot CLI hooks are **repo-scoped only** — they live under
`.github/hooks/` and have a different payload contract (JSON on stdin,
stdout `permissionDecision` instead of exit code).

`ai-native-workflow install project` already creates Copilot
**instructions** (`.github/copilot-instructions.md`,
`.github/instructions/*`), but does NOT create hook artifacts. We need
to extend `install_project` so that, for any repo where the user runs
the per-project installer, an equivalent enforcement path exists for
Copilot CLI driving the same workflow.

## 2. Context

### 2.1 Hook contract differences (Claude vs Copilot)

| Aspect            | Claude (global)                         | Copilot CLI (per-repo)                                                     |
|-------------------|------------------------------------------|----------------------------------------------------------------------------|
| Config location   | `~/.claude/settings.json`               | `.github/hooks/copilot-cli-policy.json`                                    |
| Script location   | `~/.claude/hooks/*.sh`                  | `.github/hooks/<script>.sh` + `.github/hooks/scripts/<helpers>`            |
| Payload           | Env vars (`CLAUDE_TOOL_INPUT`, etc.)    | JSON on stdin; `toolArgs` is a JSON-stringified blob (parse twice)         |
| Filter            | `matcher: "Bash"` in JSON               | None — script-side filter on `toolName == "bash"`                          |
| Block             | `exit 2`                                | Print `{"permissionDecision":"deny","permissionDecisionReason":"..."}`     |
| Crash → default   | Block (exit non-zero treated as block)  | **Allow** (no JSON printed → action proceeds)                              |
| Timeout           | We set 10–15s                           | Default 30s; we set 10–15s explicitly                                      |

The crash-default difference is the load-bearing safety concern.
ADR-001 records the dispatcher + trap pattern that fixes it.

### 2.2 Source-of-truth files

- Hook to port: `hooks/tdd-gate.sh`, `hooks/confidence-gate.sh`
- Scorer to vendor per-project: `scripts/confidence.sh`
- Integration point: `ai-native-workflow` lines 3465–3518 (`install_project`)
  and lines 3882–4022 (`install_project_copilot`).
- Test fixtures pattern: `tests/install.bats`, `tests/confidence-gate-hook.bats`,
  `tests/lib/confidence-helpers.bash`.

## 3. Proposed solution

### 3.1 Architecture decisions (recorded in ADR-001)

The user accepted defaults on the open questions:

- **OQ-1 → single dispatcher.** One script handles both gates. Rationale:
  Copilot's short-circuit behavior is undocumented; folding both gates
  into one script gives deterministic ordering (TDD gate first, then
  confidence gate) and one trap/filter site to maintain.
- **OQ-2 → single canonical policy file.** No multi-file merging.
- **OQ-3 → cwd resolution: payload first, fallback `git rev-parse
  --show-toplevel`.** If the payload `cwd` doesn't sit inside a repo,
  fall back to walking up.
- **OQ-4 → vendor `confidence.sh` per-project.** Copy from
  `$_ANW_SCRIPT_DIR/scripts/confidence.sh` to
  `.github/hooks/scripts/confidence.sh` at install time. Self-contained;
  works for Copilot-only users with no Claude install.
- **OQ-5 → write deny reason to BOTH stdout JSON and stderr.** Belt-and-
  suspenders for surfacing.
- **OQ-6 → ship a `.github/hooks/README.md` stub** so reviewers don't
  delete what looks like config noise.

### 3.2 File layout produced by the installer

```
<project>/
└── .github/
    └── hooks/
        ├── README.md                       # stub explaining the hooks
        ├── copilot-cli-policy.json         # registers the dispatcher
        ├── copilot-cli-dispatcher.sh       # single dispatcher script
        └── scripts/
            └── confidence.sh               # vendored copy of scorer
```

### 3.3 Dispatcher script — control flow

```
read stdin payload (once)
trap ERR -> emit_deny "Copilot hook crashed unexpectedly"
parse toolName
if toolName != "bash": print allow JSON, exit 0
parse toolArgs.command (double jq)
resolve PROJECT_DIR:
  - try payload .cwd
  - if not a git repo: cd into .cwd (or pwd) and `git rev-parse --show-toplevel`
  - if still not resolvable: emit_deny "cannot resolve project dir"

# Gate 1: TDD
if command matches 'git\s+commit' and not '--amend':
  if .tdd-skip exists: allow
  elif staged-files all-spike: allow
  elif staged-files include test: allow
  else: emit_deny "TDD GATE: ..."

# Gate 2: confidence
if command matches '(gh\s+pr\s+create|glab\s+mr\s+create)':
  read .git/aw/active-spec
  invoke vendored confidence.sh on log
  on RED + structural-only + .tdd-skip: log auto-bypass, allow
  on RED + behavioral + .tdd-skip: emit_deny "use /override-confidence"
  on RED + valid override marker: consume marker, log, allow
  on RED + malformed override: rm marker, emit_deny
  on RED + nothing: emit_deny "RED ..."
  on YELLOW: print warning to stderr, allow
  on GREEN: allow

# fall-through (any other bash command)
print allow JSON, exit 0
```

### 3.4 `emit_deny` helper (the safety pattern)

```bash
emit_deny() {
  local reason="${1:-hook crashed; failing closed}"
  jq -nc --arg r "$reason" '{permissionDecision:"deny", permissionDecisionReason:$r}'
  # Note: no stderr output. bats merges stderr into stdout, and emoji banners
  # in stderr break jq -e parsing of $output in tests. The JSON reason is
  # sufficient for Copilot UI surfacing. See ADR-001 §Decision point 5.
  exit 0   # exit 0; Copilot reads decision from stdout JSON
}
trap 'emit_deny "Copilot hook crashed unexpectedly"' ERR
```

### 3.5 `copilot-cli-policy.json` schema

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "bash": "./copilot-cli-dispatcher.sh",
        "cwd": ".github/hooks",
        "timeoutSec": 15,
        "comment": "ai-native-workflow TDD + confidence gate dispatcher"
      }
    ]
  }
}
```

### 3.6 Idempotency strategy

- **Dispatcher script + vendored scorer + README**: overwrite on every
  install (these are tool-owned). If user has hand-edited the dispatcher,
  back up to `<file>.bak.<ts>` then overwrite (mirrors `backup_if_exists`
  pattern at line 64 of `ai-native-workflow`).
- **`copilot-cli-policy.json`**: `jq` merge. If the file exists with
  user-added `preToolUse` entries, merge our dispatcher entry in,
  deduping by `bash` field path. Mirrors the `install_global_settings`
  jq-merge at line 1818–1828.

## 4. Acceptance criteria

All criteria are testable. Tests live in
`tests/install-project-copilot-hooks.bats` (installer) and
`tests/copilot-cli-dispatcher.bats` (script behavior).

| ID    | Criterion                                                                                                                                                          |
|-------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| AC-1  | After `install project`, `.github/hooks/copilot-cli-policy.json` exists, parses as JSON, and has exactly one `preToolUse` entry with `bash` = `./copilot-cli-dispatcher.sh`. |
| AC-2  | After `install project`, `.github/hooks/copilot-cli-dispatcher.sh` exists, has mode `0755`, contains the `trap 'emit_deny ...' ERR` line and the `toolName == "bash"` filter. |
| AC-3  | After `install project`, `.github/hooks/scripts/confidence.sh` exists with mode `0755` and is byte-identical to `<repo>/scripts/confidence.sh`.                     |
| AC-4  | TDD gate path: dispatcher run with payload `{toolName:"bash", toolArgs:"{\"command\":\"git commit -m x\"}", cwd:<repo>}`, no test files staged → stdout JSON has `permissionDecision: "deny"`, reason contains `TDD GATE`. |
| AC-5  | TDD gate path: same setup, `.tdd-skip` present → stdout JSON has no `deny` (allow); stderr mentions bypass.                                                          |
| AC-6  | TDD gate path: command is `git commit --amend` → allow.                                                                                                              |
| AC-7  | TDD gate path: staged files include `foo_test.go` → allow.                                                                                                           |
| AC-8  | TDD gate path: spike-only commit (all paths under `spikes/`) → allow.                                                                                                |
| AC-9  | Confidence gate path: payload command `gh pr create`, RED aggregate verdict, no override → deny with reason containing `RED` and gate names; verdict event appended to log. |
| AC-10 | Confidence gate path: GREEN verdict → allow; verdict event appended to log.                                                                                          |
| AC-11 | Confidence gate path: RED + override marker present with valid reason → marker file removed, override event appended, allow.                                         |
| AC-12 | Confidence gate path: RED + `.tdd-skip` + structural-only gates (`NO_AC`, `AC_NOT_TESTED`) → auto-bypass event logged, allow.                                        |
| AC-13 | Confidence gate path: RED + `.tdd-skip` + behavioral gate (`TEST_FAILED`) → deny with reason containing "use /override-confidence".                                  |
| AC-14 | Confidence gate path: command is `glab mr create` (not `gh pr create`) and verdict RED → deny (parity).                                                              |
| AC-15 | Fail-closed: dispatcher invoked with malformed JSON (`set -u` triggers ERR trap) → stdout JSON has `permissionDecision: "deny"` with reason `Copilot hook crashed unexpectedly`. |
| AC-16 | Filter: payload `toolName: "read_file"` → stdout JSON has `permissionDecision: "allow"`, no scorer/git invocations (assert by trace logging or by absence of `.context/specs/*.jsonl` updates). |
| AC-17 | `cwd` resolution: payload `.cwd` is a sub-directory of the repo → dispatcher resolves to repo root via `git rev-parse --show-toplevel`.                              |
| AC-18 | Idempotency: re-running `install project` produces no diff in working tree on second run (`git status --porcelain` empty after first run committed).                  |
| AC-19 | Idempotency / merge: pre-existing `copilot-cli-policy.json` with a custom `preToolUse` entry preserves the custom entry AND adds our dispatcher entry, deduped by `bash` path. |
| AC-20 | Backup-on-content-mismatch: hand-edited `copilot-cli-dispatcher.sh` is backed up to `<file>.bak.<ts>` before being overwritten.                                       |
| AC-21 | `.github/hooks/README.md` exists and mentions both gates.                                                                                                            |
| AC-22 | All existing 160 bats tests still pass — no regression on Claude-side install or hooks.                                                                              |
| AC-23 | Both deny and stderr surfaces carry the same human-readable reason text (OQ-5).                                                                                      |

## 5. Technical design

### 5.1 New installer function

```bash
# In ai-native-workflow, called from install_project() after install_project_copilot
# and before install_project_gitignore.
install_project_copilot_hooks() {
  local project_dir="$1"
  local hooks_dir="$project_dir/.github/hooks"
  local scripts_dir="$hooks_dir/scripts"

  mkdir -p "$scripts_dir"

  # 1. Vendor confidence.sh
  cp "$_ANW_SCRIPT_DIR/scripts/confidence.sh" "$scripts_dir/confidence.sh"
  chmod 0755 "$scripts_dir/confidence.sh"

  # 2. Write dispatcher (heredoc; backup on mismatch)
  local dispatcher="$hooks_dir/copilot-cli-dispatcher.sh"
  write_dispatcher_with_backup "$dispatcher"
  chmod 0755 "$dispatcher"

  # 3. Write/merge policy JSON
  write_or_merge_copilot_policy "$hooks_dir/copilot-cli-policy.json"

  # 4. Write README stub if missing
  [ -f "$hooks_dir/README.md" ] || write_copilot_hooks_readme "$hooks_dir/README.md"

  # 5. jq-not-found warning (FR-6)
  command -v jq >/dev/null 2>&1 || warn "jq not found — Copilot hooks need jq at runtime"
}
```

### 5.2 Dispatcher script structure (high level)

The dispatcher lives in the installer as a heredoc (mirrors how
`install_global_hooks` ships `tdd-gate.sh`). The heredoc body imports
its bypass-marker logic verbatim from the Claude scripts but adapts
input parsing and output emission. See section 3.3 for control flow
and 3.4 for the trap.

### 5.3 Policy JSON merge

Reuses the same `jq` recipe `install_global_settings` uses for
`PreToolUse[].hooks` deduplication, but adapted to the Copilot schema:

```bash
# Pseudocode
existing="$(jq -e . copilot-cli-policy.json 2>/dev/null || echo '{"version":1,"hooks":{}}')"
merged="$(echo "$existing" | jq --slurpfile new <(echo "$ours") '
  .hooks.preToolUse = (
    ((.hooks.preToolUse // []) + ($new[0].hooks.preToolUse))
    | unique_by(.bash)
  )
  | .version = 1
')"
echo "$merged" | jq -e . > copilot-cli-policy.json.tmp
mv copilot-cli-policy.json.tmp copilot-cli-policy.json
```

### 5.4 Test fixtures

New helper file: `tests/lib/copilot-payload-helpers.bash`
```bash
mk_payload() {
  local tool_name="$1"; local command="$2"; local cwd="$3"
  jq -nc \
    --arg t "$tool_name" --arg c "$command" --arg d "$cwd" \
    '{toolName:$t, toolArgs:({command:$c} | tojson), cwd:$d, timestamp:1714694400000}'
}
```
Plus a `mock_confidence_scorer` helper that writes a stub `confidence.sh`
emitting a configured verdict JSON.

## 6. Risks (from requirements §12)

- **R-1 (HIGH)** — fail-closed via stdout JSON. Mitigated by `trap ERR`.
- **R-2 (HIGH)** — no `matcher` filter. Mitigated by the script's first
  filter line (AC-16 enforces it).
- **R-5 (MEDIUM)** — `cwd` payload semantics. Mitigated by
  `git rev-parse --show-toplevel` fallback (AC-17 enforces it).
- **R-6 (LOW)** — `toolArgs` is double-encoded. Reviewer should verify
  both `jq` parses are present.
- **R-8 (LOW)** — short-circuit unknown. Single-dispatcher design dodges
  this (one entry, internal sequencing controlled by us).

## 7. Out of scope

- Global Copilot hooks (no such mechanism).
- PowerShell variants (Mac/Linux only per `CLAUDE.md`).
- Refactoring Claude-side hooks for shared logic. Port, don't refactor.
- Additional event hooks (`sessionStart`, `userPromptSubmitted`, etc.).
- CI check for the policy JSON's existence in downstream repos.

## 8. Hand-off

After this spec is approved:

> Use tdd-developer on Step 1 of `docs/context/specs/COP-2-todo.md`.
