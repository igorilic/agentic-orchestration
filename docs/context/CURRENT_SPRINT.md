# Current sprint

## In progress

- **SDK-1** — Sidekick model-routing + live pipeline visualization
  - Brainstorm: `docs/context/specs/SDK-1-brainstorm.md`
  - Spec: `docs/context/specs/SDK-1-spec.md`
  - Todo: `docs/context/specs/SDK-1-todo.md`
  - ADR: `docs/decisions/ADR-002-sentinel-stream-and-sidekick-delegation.md`
  - Spike (de-risked): `spikes/sdk-1-renderer/FINDINGS.md`
  - Phase: **Track A complete** (A-1→A-6): sidekick delegation capability + full-pipeline sentinel emission. Every step qa+reviewer-hardened (section-scoped, mutation/field-order/polarity-guarded tests). Next: Track B (live renderer + milestones JSONL).
  - Steps: 6 / 15 (Track A: 6 ✓ · Track B: 9). A-1 GO/NO-GO gate passed; Track B depends on A only at B-9 integration.
  - Driver: tdd-developer
  - Scope: GitHub/Claude pipeline only; GitLab/Copilot, replay, whitepaper figure, hard review-gate deferred
  - Tech debt (deferred from A-2 qa/reviewer): F5 — tighten "apply lint/format/type-fix output" wording in BOTH `sidekick.md` and `tdd-developer.md:50` (type-checkers emit diagnostics, not edits — the imprecise phrasing was propagated from sidekick's allowlist into tdd-developer's own allowlist bullet); F6 — add sidekick warning against reading/echoing secret file contents
  - Tech debt (deferred from A-4 qa/reviewer fix loop): F2 — the 3 heavy agents' delegation allowlists (OQ-3) aren't carved against the sidekick's forbidden write-paths (OQ-6) — a parent can delegate a task the sidekick is contractually bound to refuse (e.g. scaffold a CI workflow, a `.git`-touching rename). Not a security hole (the sidekick's own refusal is the safety net), but a spec-coherence gap → architect/spec follow-up; F3 — the parent-review-gate clause names accept/reject of *produced* sidekick output but not the sidekick *refusal-with-no-artifact* path → OQ-4/A-5/orchestrator follow-up

- **COP-2** — Install Copilot CLI hooks per-project (TDD + confidence gates)
  - Requirements: `docs/context/specs/COP-2-requirements.md`
  - Spec: `docs/context/specs/COP-2-spec.md`
  - Todo: `docs/context/specs/COP-2-todo.md`
  - ADR: `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`
  - Phase: Steps 12/12 done; in PR #5 review/fix-loop
  - Steps: 12 / 12
  - Driver: tdd-developer
  - Open questions OQ-1 / OQ-2 / OQ-3 / OQ-4 / OQ-5 / OQ-6: resolved (defaults accepted)

## Done

- **COP-1** — Symmetric Copilot CLI harness for `install global`
  - Spec: `docs/context/specs/COP-1-spec.md`
  - Todo: `docs/context/specs/COP-1-todo.md`
  - Steps: 11 / 11 complete (merged via PR #4)
  - Out of scope (tracked): COP-2 — project-level Copilot hooks; Copilot CLI scopes hooks per-repo only

- **BREW-1** — Resolve `_ANW_SCRIPT_DIR` through symlinks
  - Spec: `docs/context/specs/BREW-1-anw-script-dir-symlink.md`
  - Todo: `docs/context/specs/BREW-1-todo.md`
  - Steps: 2 / 2 complete
  - Unblocks: brew tap rollout (`spikes/brew-packaging/`); enables `cp` from `$_ANW_SCRIPT_DIR/skills/` in COP-1

- **CTX-1** — Split tracked specs from runtime state (option G)
  - Spec: `docs/context/specs/CTX-1-spec.md`
  - Todo: `docs/context/specs/CTX-1-todo.md`
  - Steps: 13 / 13 complete
  - All 131 bats tests passing; fresh install produces new `docs/context/` layout
