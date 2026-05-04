# CTX-1 — Split tracked specs from runtime state (option G)

**Status:** Proposed
**Date:** 2026-05-04
**Owner:** architect → tdd-developer
**Source:** `spikes/context-sharing/FINDINGS.md`, `spikes/context-sharing/option-g-migration.md`, `spikes/context-sharing/EVALUATION.md`
**Branch:** `feat/context-split`

---

## Problem Statement

`.context/` today mixes two categorically different artifacts:

1. **Reviewable artifacts** — `CURRENT_SPRINT.md`, feature specs (`<id>-<n>.md`), todo plans (`<id>-todo.md`), requirements docs (`<id>-requirements.md`). These are human-readable architecture decisions and sprint state. Reviewers want them in PRs. They survive across machines and developers.
2. **Runtime artifacts** — `.pipeline-state` (single-writer cursor), `.pipeline-audit.log` (dense operational log), `<id>-confidence.jsonl` (append-only event log written constantly by agents). These are local-only, single-writer, and merge-unfriendly.

The repo's `.gitignore` currently ignores `.context/` wholesale (commit `2b7a274`). That was a defensible reaction to "all tracked" polluting `main`, but it lost the "specs are reviewable architecture" half. The result: cross-machine work loses specs (boundary B3 in the explorer's matrix), and PRs hide the design.

The spike's recommendation (`FINDINGS.md`) is **option G — split tracked vs runtime**. This spec implements G.

## Context

- Repo is `agentic-orchestration`, a CLI that ships hooks/skills/agents for AI-native dev workflows.
- The `architect`, `qa`, `reviewer`, `requirements-engineer`, `troubleshooter` agents (×2 — Claude Code variant + Copilot CLI variant) all reference `.context/specs/` and `.context/CURRENT_SPRINT.md` directly in their prompt templates.
- The `ai-native-workflow` script ships these prompts as heredocs into `~/.claude/agents/` and `~/.copilot/agents/` during `install global`. Both source files (`agents/*/...md`) AND the embedded heredocs in `ai-native-workflow` need updating.
- Hooks: `hooks/session-start.sh` reads `.context/CURRENT_SPRINT.md`. `hooks/confidence-gate.sh` reads `.context/specs/<id>-confidence.jsonl` (unchanged path).
- Scripts: `scripts/confidence-cli.sh` references `.context/specs/<id>-confidence.jsonl` (unchanged path).
- Tests: 105 bats tests pass today. `tests/cli-confidence.bats` and `tests/confidence-gate-hook.bats` mkdir `.context/specs/` and write jsonl logs there. Those paths are RUNTIME — they stay.
- Existing similar pattern in repo: `docs/superpowers/specs/` and `docs/superpowers/plans/` already live under `docs/`. The new `docs/context/` slots in alongside.
- Local in-flight spec: `BREW-1` (CURRENT_SPRINT.md, BREW-1-anw-script-dir-symlink.md, BREW-1-todo.md) currently in `.context/`. Untracked. Must migrate as part of this work.

## Decisions Resolved (from the request's open questions)

### D1. Where do tracked specs live? → `docs/context/`

Justification:
- Matches existing `docs/superpowers/specs/` and `docs/superpowers/plans/` convention; reviewers already look in `docs/` for design docs.
- Keeps `.context/` semantically clean: after this change, `.context/` contains per-project installer-seeded reference docs (ARCHITECTURE, CONVENTIONS, GLOSSARY — tracked in consumer projects) and runtime artifacts (.pipeline-state, .pipeline-audit.log, *.jsonl — gitignored). Sprint board and spec markdown move to `docs/context/` where they are always tracked.
- A flatter `docs/specs/` would collide with any future per-feature specs the project itself ships (e.g., a "user docs" section). `docs/context/` is purpose-named and bounded.
- Keeping the old `.context/` path "now that it's no longer fully gitignored" was considered and rejected: the current `.gitignore` line `.context/` is already in `main`. Changing it to a multi-line allow-list works, but mixes tracked and runtime files in the same directory, which makes `git status` noisier and weakens the conceptual split that's the whole point of option G.

### D2. Confidence audit jsonl → stays at `.context/specs/<id>-confidence.jsonl`

Justification:
- It's a runtime artifact (append-only, written by agents during a pipeline run). It belongs with the other runtime files in `.context/`.
- Hook (`hooks/confidence-gate.sh:29`), CLI helper (`scripts/confidence-cli.sh:28,54,64,76`), and 38 test references in `tests/cli-confidence.bats` already use this path. Moving it is pure churn.
- The `option-g-migration.md` table explicitly keeps it at the existing path.

### D3. In-flight migration → one-time `git mv` of BREW-1 files

The local untracked files at `.context/CURRENT_SPRINT.md`, `.context/specs/BREW-1-anw-script-dir-symlink.md`, `.context/specs/BREW-1-todo.md` move to `docs/context/...` paths in Step 7 of the todo. Done as part of this branch so the BREW-1 work is unblocked the moment this lands.

### D4. Backwards compatibility → hard-cut

Per the request's recommendation. Solo developer, single in-flight spec, agents are template prompts (no runtime fallback to "old path"). Hard-cut keeps the implementation small and the model behavior unambiguous.

## Proposed Solution

### Final layout

```
docs/
  context/
    CURRENT_SPRINT.md                      # tracked, PR-reviewable
    specs/
      <id>-<n>.md                          # tracked — feature spec
      <id>-todo.md                         # tracked — atomic plan
      <id>-requirements.md                 # tracked — requirements doc
      templates/
        feature-spec.md                    # tracked — installer-seeded template
.context/
  .pipeline-state                          # gitignored — single-writer cursor
  .pipeline-audit.log                      # gitignored — operational log
  ARCHITECTURE.md                          # tracked NOTE: stays in .context/ (per-project doc, installer-seeded)
  CONVENTIONS.md                           # tracked NOTE: stays in .context/ (per-project doc, installer-seeded)
  GLOSSARY.md                              # tracked NOTE: stays in .context/ (per-project doc, installer-seeded)
  specs/
    <id>-confidence.jsonl                  # gitignored — append-only audit log
```

**Note on `ARCHITECTURE.md` / `CONVENTIONS.md` / `GLOSSARY.md`:** These three are installer-seeded "fill in for your project" docs. They are NOT pipeline artifacts. They live under `.context/` today. We DO NOT move them in this spec — they're per-project documentation, not pipeline state. Agent prompts that read them (`Read .context/ARCHITECTURE.md`) keep that exact path. The split is specifically about the three pipeline-produced artifacts: sprint, specs, todos, plus the runtime files.

This is consistent with FINDINGS: the recommendation is to move `CURRENT_SPRINT.md` and spec markdown files. ARCHITECTURE/CONVENTIONS/GLOSSARY are not in scope for option G.

### `.gitignore` change

Currently:
```
.context/
```

After (replace that single line):
```
.context/.pipeline-state
.context/.pipeline-audit.log
.context/specs/*.jsonl
.context/specs/templates/
```

(The `templates/` entry is defensive — when the project installer seeds `.context/specs/templates/feature-spec.md` for a fresh project, that file is also runtime/local boilerplate. The actual canonical template moves to `docs/context/specs/templates/`. See Step 4.)

Effect: `.context/specs/*.md` is no longer ignored, but in this repo nothing under `.context/` other than the runtime files exists after migration. ARCHITECTURE.md / CONVENTIONS.md / GLOSSARY.md are tracked and remain so (they're not under any of the four ignore patterns).

### Path constants in `ai-native-workflow`

Currently (lines 30-31):
```
CONTEXT_DIR=".context/specs"
STATE_FILE=".context/.pipeline-state"
```

After:
```
SPEC_DIR="docs/context/specs"             # tracked specs, todos, requirements
SPRINT_FILE="docs/context/CURRENT_SPRINT.md"
RUNTIME_DIR=".context"                    # gitignored runtime root
STATE_FILE="${RUNTIME_DIR}/.pipeline-state"
AUDIT_LOG="${RUNTIME_DIR}/.pipeline-audit.log"
CONFIDENCE_LOG_DIR="${RUNTIME_DIR}/specs" # confidence jsonl path (unchanged)
```

(`CONTEXT_DIR` is renamed to `SPEC_DIR` for clarity — the variable was always about spec markdown, never confidence logs. Keep an alias `CONTEXT_DIR="$SPEC_DIR"` for one release if any external script references it, but `rg` shows none — drop the alias.)

The audit log path in `ai-native-workflow:246` (`AUDIT_LOG=".context/.pipeline-audit.log"`) becomes the new `AUDIT_LOG` constant defined at the top.

## Acceptance Criteria

- **AC-1:** `docs/context/` exists and is tracked. After migration it contains `CURRENT_SPRINT.md`, `specs/BREW-1-anw-script-dir-symlink.md`, `specs/BREW-1-todo.md` (the in-flight files), and `specs/templates/feature-spec.md`. Verified by sandbox install (see Step 12 smoke test). Running `ai-native-workflow install project` materializes the file in the consumer project's `docs/context/specs/templates/`.

- **AC-2:** `.gitignore` no longer contains the bare line `.context/`. It DOES contain `.context/.pipeline-state`, `.context/.pipeline-audit.log`, and `.context/specs/*.jsonl`. Verified: `grep -E '^\.context/' .gitignore` shows the three explicit entries and not the bare directory.

- **AC-3:** All 6 agent prompt files under `agents/claude-code/{architect,qa,reviewer}.md` and `agents/copilot-cli/{architect,qa,reviewer}.agent.md` read/write specs from `docs/context/specs/` for `<id>-spec.md`, `<id>-todo.md`, and `<id>-requirements.md`. Confidence jsonl path stays `.context/specs/<id>-confidence.jsonl`. Verified: `rg '\.context/specs/.*-(spec|todo|requirements)\.md' agents/` returns no matches; `rg 'docs/context/specs' agents/` returns matches for both flavors.

- **AC-4:** `requirements-engineer` agent files (`agents/claude-code/requirements-engineer.md`, `agents/copilot-cli/requirements-engineer.agent.md`) write requirements to `docs/context/specs/<id>-requirements.md`.

- **AC-5:** `troubleshooter` agent file (`agents/claude-code/troubleshooter.md`) writes bugfix specs and todos to `docs/context/specs/`.

- **AC-6:** The `ai-native-workflow` CLI uses `SPEC_DIR=docs/context/specs` and `SPRINT_FILE=docs/context/CURRENT_SPRINT.md` everywhere it references those artifacts. The runtime constants `STATE_FILE`, `AUDIT_LOG`, and confidence-jsonl directory remain under `.context/`. Verified: `rg '\.context/specs/.*-(spec|todo|requirements)\.md' ai-native-workflow` returns no matches; `rg '\.context/CURRENT_SPRINT' ai-native-workflow` returns no matches.

- **AC-7:** All embedded agent prompts inside `ai-native-workflow` heredocs (the ones used to install agent files into `~/.claude/agents/` and `~/.copilot/agents/`) reference the new paths. Verified: same `rg` checks as AC-6 cover the heredoc bodies.

- **AC-8:** `templates/AGENTS.md` references `docs/context/CURRENT_SPRINT.md` for sprint updates and `docs/context/specs/` for spec lookups. The "Read `.context/ARCHITECTURE.md`" / "Read `.context/CONVENTIONS.md`" lines stay unchanged (those files don't move).

- **AC-9:** The installer's `install_project_agents_md` heredoc (which generates per-project `AGENTS.md`) emits the new paths to match `templates/AGENTS.md`.

- **AC-10:** The installer's `install_project_context` (line 3770) creates `docs/context/CURRENT_SPRINT.md` and `docs/context/specs/templates/feature-spec.md` instead of `.context/CURRENT_SPRINT.md` and `.context/specs/templates/feature-spec.md`. The ARCHITECTURE/CONVENTIONS/GLOSSARY seeding in `.context/` stays unchanged (per Decision D-scope).

- **AC-11:** `install_project_gitignore` adds `.context/.pipeline-state`, `.context/.pipeline-audit.log`, `.context/specs/*.jsonl` to the per-project `.gitignore` instead of relying on the user already ignoring `.context/`. (In this repo's own `.gitignore`, the same change is applied directly.)

- **AC-12:** `hooks/session-start.sh` reads sprint from `docs/context/CURRENT_SPRINT.md` (with fallback-free behavior — if missing, it just skips, same as today). The same heredoc embedded in `ai-native-workflow` (line ~1979) is updated.

- **AC-13:** README.md and `docs/ARCHITECTURE.md` reflect the new convention. Pipeline diagrams show `docs/context/specs/<id>-requirements.md` etc. The per-project "what gets installed" tables name `docs/context/` as the tracked location alongside `.context/` for runtime.

- **AC-14:** All 105 existing bats tests still pass. `cli-confidence.bats` and `confidence-gate-hook.bats` continue to use `.context/specs/<id>-confidence.jsonl` (runtime path is unchanged).

- **AC-15:** A new bats test (in `tests/install.bats`) verifies that `install project` into a sandbox creates `docs/context/CURRENT_SPRINT.md` and `docs/context/specs/templates/feature-spec.md`, and that the per-project `.gitignore` written by the installer contains the three runtime ignore entries (not the bare `.context/`).

- **AC-16:** A new bats test verifies that the in-repo `.gitignore` does NOT match the bare line `.context/` — instead it lists the three runtime patterns. (This guards against regression on this repo specifically.)

- **AC-17:** The skill files under `skills/` that mention `.context/specs/` or `.context/CURRENT_SPRINT.md` for spec/sprint work (not `ARCHITECTURE.md`/`CONVENTIONS.md`) are updated: `skills/ticket/SKILL.md`, `skills/session-report/SKILL.md`, `skills/brainstorm/SKILL.md`, `skills/pipeline-{gitlab,github}-{feature,incident}/SKILL.md`. These ship via the installer and must match the agent prompts.

- **AC-18:** The skip-tdd file marker (`docs(context): migrate ...` commit) carries `.tdd-skip` for the doc-only migration step (Step 7) per the request's constraint.

## Risks

- **R1: Heredoc churn.** `ai-native-workflow` embeds copies of the agent prompts (lines 2293, 2463, 2707, 2769, 2774, 2779, 2798, 3075-3076, 3197, 3199, 3226, 3238, 3241-3244, 3635, 3670, 3675-3677, 3713, 3740, 3743, 3746, 3762, 3890-3892). Every one needs review. **Mitigation:** Step 9 runs `rg` checks listed in AC-6/AC-7 as a smoke test. Manually diff before committing.

- **R2: Existing 105 tests rely on `.context/specs/`.** They use that path correctly — for confidence jsonl. We must NOT change those tests. **Mitigation:** clear separation in Step 1: the `.gitignore` change only adds entries for `.pipeline-state`, `.pipeline-audit.log`, `*.jsonl`, NOT `.context/specs/*.md`.

- **R3: User may have local `.context/specs/` files NOT tracked elsewhere.** `git status` shows BREW-1 + sprint board are the only ones today; verify before Step 7's `git mv`.

- **R4: External users with installed `~/.claude/agents/architect.md` from a prior version.** They re-run `install global` to update. We surface this in commit message + README.

- **R5: Confidence-gate hook path resolution.** Hook uses `$PROJECT_DIR/.context/specs/${SPEC_ID}-confidence.jsonl`. Unchanged. Verified by running existing `confidence-gate-hook.bats` post-migration.

## Out of Scope

- Option H (CLI runtime-sync helper, `aw context push/pull`). Spike has the prototype; FINDINGS says build only when cross-machine resume becomes a real workflow. Not now.
- Moving `.context/ARCHITECTURE.md`, `.context/CONVENTIONS.md`, `.context/GLOSSARY.md`. They're per-project installer-seeded files, not pipeline artifacts. The agent prompts' `Read .context/ARCHITECTURE.md` lines stay intact.
- Adding `.gitattributes export-ignore` for `docs/context/` (FINDINGS notes this for if-the-repo-goes-public). Repo is private; defer.
- Creating an ADR for this decision. The spike's three markdown files (FINDINGS, EVALUATION, option-g-migration) already serve that role; an ADR adds churn without new info. If a reviewer asks for one, follow up in a separate one-step plan.

## Technical Design

### Components touched

| Component | File(s) | Change |
|---|---|---|
| Agent prompts | `agents/claude-code/{architect,qa,reviewer,requirements-engineer,troubleshooter}.md` | sed `\.context/specs/` → `docs/context/specs/` for spec/todo/requirements/bugfix paths; `\.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`. KEEP `\.context/specs/<id>-confidence.jsonl`, `.context/ARCHITECTURE.md`, `.context/CONVENTIONS.md`. |
| Agent prompts | `agents/copilot-cli/{architect,qa,reviewer,requirements-engineer}.agent.md` | Same. |
| CLI | `ai-native-workflow` | New constants `SPEC_DIR`, `SPRINT_FILE`, `RUNTIME_DIR`. Update embedded heredocs in agent install blocks and the `install_project_agents_md` AGENTS.md heredoc. Update `install_project_context` to create `docs/context/` instead of `.context/CURRENT_SPRINT.md`. Update `install_project_gitignore` to write the three explicit ignore lines. |
| Templates | `templates/AGENTS.md` | Replace `.context/CURRENT_SPRINT.md` and `.context/specs/` references for spec/sprint work. KEEP `.context/ARCHITECTURE.md`, `.context/CONVENTIONS.md`. |
| Hooks | `hooks/session-start.sh` | `\.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`. |
| Hooks | `hooks/confidence-gate.sh` | Unchanged (confidence jsonl path is unchanged). |
| Scripts | `scripts/confidence-cli.sh` | Unchanged. |
| Skills | `skills/ticket/SKILL.md`, `skills/session-report/SKILL.md`, `skills/brainstorm/SKILL.md`, `skills/pipeline-*/SKILL.md` | Replace spec/sprint paths. |
| Repo gitignore | `.gitignore` | Replace `.context/` with three explicit entries. |
| Repo docs | `README.md`, `docs/ARCHITECTURE.md` | Update path mentions in tables and pipeline diagrams. |
| Tests | `tests/install.bats` | Add 3 new tests (AC-15, AC-16, plus per-project gitignore content). |
| In-flight files | `.context/CURRENT_SPRINT.md`, `.context/specs/BREW-1-*.md` | `git mv` to `docs/context/...`. |

### Sed-style mapping (audit reference, not a literal command)

```
# spec/todo/requirements/bugfix paths (TRACKED)
\.context/specs/<id>-<n>\.md                  → docs/context/specs/<id>-<n>.md
\.context/specs/<id>-spec\.md                 → docs/context/specs/<id>-spec.md
\.context/specs/<id>-todo\.md                 → docs/context/specs/<id>-todo.md
\.context/specs/<id>-requirements\.md         → docs/context/specs/<id>-requirements.md
\.context/specs/<id>-bugfix\.md               → docs/context/specs/<id>-bugfix.md
\.context/specs/<id>-brainstorm\.md           → docs/context/specs/<id>-brainstorm.md
\.context/specs/<id>-testplan\.md             → docs/context/specs/<id>-testplan.md
\.context/specs/<short-name>\.md              → docs/context/specs/<short-name>.md
\.context/specs/templates/feature-spec\.md    → docs/context/specs/templates/feature-spec.md
\.context/specs/                               → docs/context/specs/    (when followed by spec/todo/requirements text)
\.context/CURRENT_SPRINT\.md                  → docs/context/CURRENT_SPRINT.md

# UNCHANGED (runtime / per-project docs)
\.context/specs/<id>-confidence\.jsonl        → (no change — runtime)
\.context/\.pipeline-state                     → (no change — runtime)
\.context/\.pipeline-audit\.log                → (no change — runtime)
\.context/ARCHITECTURE\.md                     → (no change — per-project doc)
\.context/CONVENTIONS\.md                      → (no change — per-project doc)
\.context/GLOSSARY\.md                         → (no change — per-project doc)
```

When a string is `.context/specs/` without a filename suffix (e.g., "Check `.context/specs/` for feature specifications"), apply judgment: if the surrounding sentence is about spec/todo/requirements documents, change to `docs/context/specs/`; if it's specifically about confidence jsonl, leave it. The Edit tool with surrounding context is the right approach, not a blunt sed.

### Migration of in-flight files

```bash
mkdir -p docs/context/specs
git mv .context/CURRENT_SPRINT.md docs/context/CURRENT_SPRINT.md
git mv .context/specs/BREW-1-anw-script-dir-symlink.md docs/context/specs/
git mv .context/specs/BREW-1-todo.md docs/context/specs/
# .context/specs/ may now be empty; leave the directory itself — runtime files still expected here
```

### Test Strategy

- **Existing tests (105):** must still pass. Run `bats tests/` after each step.
- **New tests in `tests/install.bats`:**
  1. `install project` writes `docs/context/CURRENT_SPRINT.md`.
  2. `install project` writes `docs/context/specs/templates/feature-spec.md`.
  3. `install project` writes a project `.gitignore` containing the three runtime ignore entries.
  4. `install project` does NOT write a bare `.context/` to the project `.gitignore`.

These four assertions land as a single bats test file or as additions to `install.bats`. Step 8 in todo handles this.

- **Manual smoke in Step 9:** run `rg '\.context/(specs/[^c]|CURRENT_SPRINT)' .` (excluding `.git`, `spikes/`, the confidence-jsonl path, and architecture/conventions/glossary mentions) and confirm zero matches outside the explicitly-allowed list.

## Open Questions

None blocking. The four decision points (D1–D4 above) are resolved in this spec.
