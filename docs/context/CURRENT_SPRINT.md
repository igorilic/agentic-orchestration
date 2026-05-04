# Current sprint

## In progress

- **BREW-1** — Resolve `_ANW_SCRIPT_DIR` through symlinks
  - Spec: `docs/context/specs/BREW-1-anw-script-dir-symlink.md`
  - Todo: `docs/context/specs/BREW-1-todo.md`
  - Steps: 2
  - Driver: tdd-developer
  - Unblocks: brew tap rollout (`spikes/brew-packaging/`)

- **COP-2** — Install Copilot CLI hooks per-project (TDD + confidence gates)
  - Requirements: `docs/context/specs/COP-2-requirements.md`
  - Spec: `docs/context/specs/COP-2-spec.md`
  - Todo: `docs/context/specs/COP-2-todo.md`
  - ADR: `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`
  - Phase: spec + todo plan complete; ready for tdd-developer
  - Steps: 0 / 12
  - Driver: tdd-developer (next — Step 1)
  - Open questions OQ-1 / OQ-2 / OQ-3 / OQ-4 / OQ-5 / OQ-6: resolved (defaults accepted)

## Done

- **CTX-1** — Split tracked specs from runtime state (option G)
  - Spec: `docs/context/specs/CTX-1-spec.md`
  - Todo: `docs/context/specs/CTX-1-todo.md`
  - Steps: 13 / 13 complete
  - Branch: `feat/context-split` (ready to PR)
  - All 131 bats tests passing; fresh install produces new `docs/context/` layout
