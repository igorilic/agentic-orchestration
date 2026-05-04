# ADR-001 — Copilot CLI hooks: single dispatcher with fail-closed trap

- **Status**: Accepted
- **Date**: 2026-05-02
- **Related spec**: `docs/context/specs/COP-2-spec.md`
- **Drivers**: requirements-engineer (R-1, R-2 findings); user accepted
  defaults on OQ-1 / OQ-3 / OQ-4 / OQ-5 / OQ-6.

## Context

GitHub Copilot CLI hooks differ from Claude Code hooks in three ways
that affect enforcement guarantees:

1. **Crash → allow.** Copilot reads the `permissionDecision` from
   stdout JSON, not the exit code. A script that crashes or returns
   without printing JSON results in the action being **allowed**. This
   is the opposite of Claude's `exit 2 = block` semantic.
2. **No `matcher` field.** Every `preToolUse` entry fires on every
   tool use (file reads, edits, bash). Filtering must happen inside
   the script.
3. **Undocumented short-circuit and ordering** within a `preToolUse`
   array. The docs do not specify whether multiple entries run in
   declaration order, nor whether a `deny` from entry N stops entry N+1.

We must port two Claude gates (`tdd-gate.sh`, `confidence-gate.sh`) into
Copilot's per-repo `.github/hooks/` mechanism while preserving the same
enforcement guarantees engineers rely on today.

## Decision

We will install a **single dispatcher script**
(`.github/hooks/copilot-cli-dispatcher.sh`) registered as the only
`preToolUse` entry the `ai-native-workflow` installer adds. The
dispatcher:

1. Installs a `trap '... emit_deny ...' ERR` as the very first thing
   after `set -euo pipefail`. Any unexpected error (parse failure,
   missing dependency, `set -u` triggering, scorer crash) prints a
   `deny` JSON and exits 0 — Copilot then blocks the action.
2. Reads stdin once and filters on `toolName == "bash"`. Non-bash tool
   uses get an immediate `allow` JSON with no further work.
3. Resolves the project directory from the payload `cwd` first, then
   falls back to `git -C <cwd> rev-parse --show-toplevel`.
4. Sequences the TDD gate and the confidence gate internally (TDD
   first, since `git commit` is a more local concern than `gh pr
   create`). This sidesteps the unknown short-circuit semantic — we
   own the ordering.
5. **Deny reasons surface only via `permissionDecisionReason` in the
   stdout JSON.** Earlier drafts of the ADR specified a belt-and-suspenders
   pattern with both JSON and stderr; that was removed because bats `run`
   merges stderr into stdout, and stderr emoji banners broke `jq -e`
   parsing of `$output` in tests. The JSON reason is sufficient.

The vendored confidence scorer lives at
`.github/hooks/scripts/confidence.sh`, copied per-project from
`scripts/confidence.sh` at install time. The dispatcher resolves the
scorer at `$PROJECT_DIR/.github/hooks/scripts/confidence.sh` — no
dependency on a global Claude install.

## Consequences

### Positive

- **Fail-closed.** Crashes block actions instead of allowing them,
  matching Claude's exit-2 semantics.
- **Deterministic ordering.** TDD before confidence; we own the
  sequencing rather than depending on undocumented Copilot behavior.
- **Self-contained per project.** Vendored scorer means the gate works
  for Copilot-only users with no Claude install.
- **One file to maintain.** All gate logic in one dispatcher heredoc
  inside `ai-native-workflow`, mirroring how the Claude gates are
  shipped.
- **Idempotent install.** Backup-on-mismatch + jq merge of the policy
  JSON preserves user customizations.

### Negative

- **Drift risk.** The vendored scorer can fall behind brew-managed
  updates. Mitigated by FR-5 (re-running `install project` refreshes
  the vendored copy). A user who hand-edits `.github/hooks/scripts/
  confidence.sh` will lose those edits on next install — same policy
  as the dispatcher script, surfaced via the backup file.
- **Heredoc maintenance.** The dispatcher is shipped as a heredoc
  inside `ai-native-workflow`, so changes touch the installer rather
  than a standalone script. This matches the existing pattern for
  `tdd-gate.sh` and `session-start.sh` heredocs.
- **No file-level reuse with Claude hooks.** The Copilot dispatcher
  duplicates ~80% of the Claude gates' logic. We accept this because
  payload parsing and decision emission diverge irreducibly between
  the two tools — a "shared" script would be 80% conditionals.

### Risks

- **R-1 (HIGH, mitigated)** — Copilot crash defaults to allow. The
  trap is the load-bearing safety mechanism; AC-15 enforces it via
  test.
- **R-2 (HIGH, mitigated)** — non-bash tool calls don't get filtered
  by Copilot. The `toolName` filter is the literal first work in the
  dispatcher; AC-16 enforces it.
- **R-5 (MEDIUM, mitigated)** — `cwd` may not be the repo root. The
  `git rev-parse --show-toplevel` fallback handles this; AC-17 enforces.

## Alternatives considered

### A. Two separate scripts (`tdd-gate.sh` + `confidence-gate.sh`) registered as two `preToolUse` entries

- **Reason rejected**: Copilot's short-circuit and ordering behavior
  within the array is undocumented (OQ-1). If the order isn't
  guaranteed, or if a deny doesn't short-circuit, behavior is
  unpredictable. Single dispatcher gives us deterministic control.

### B. Use the global `~/.claude/scripts/confidence.sh` from the Copilot script

- **Reason rejected**: Couples Copilot enforcement to a Claude install.
  Breaks for engineers who only use Copilot. Cross-tool coupling smell.

### C. Symlink the scorer instead of copying

- **Reason rejected**: Symlink target may not exist on machines without
  the global CLI installed. `cp` is also more `git`-friendly (the
  vendored copy can be committed and reviewed).

### D. Refactor the Claude hooks to share a library file

- **Reason rejected**: Out of scope per requirements. Payload parsing
  and decision emission diverge irreducibly between tools, so a shared
  library would be 80% conditionals on `${TOOL_FAMILY}`. Port today,
  consider unifying when the divergence narrows.

### E. Skip fail-closed and rely on `set -e` to crash early

- **Reason rejected**: Without the trap, a crash before the JSON is
  printed results in **allow**, not block. This is the single most
  important safety property of the design.

## References

- `docs/context/specs/COP-2-requirements.md` (R-1, R-2, OQ-1..6)
- `docs/context/specs/COP-2-spec.md` (sections 3.1, 3.4)
- GitHub Copilot CLI hooks reference:
  https://docs.github.com/en/copilot/reference/hooks-configuration
