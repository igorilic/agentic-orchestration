# Current sprint

## In progress

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
