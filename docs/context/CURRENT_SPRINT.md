# Current sprint

## In progress

- **COP-1** — Symmetric Copilot CLI harness for `install global`
  - Requirements: `docs/context/specs/COP-1-requirements.md`
  - Spec: `docs/context/specs/COP-1-spec.md`
  - Todo: `docs/context/specs/COP-1-todo.md`
  - Steps: 11 (8 implementation + 1 docs + 1 integration smoke + 1 constants hoist)
  - Driver: tdd-developer
  - Hand-off: `Use tdd-developer on Step 1 of COP-1-todo.md`
  - Out of scope (tracked): COP-2 — project-level Copilot hooks (`.github/hooks/*.json`); Copilot CLI scopes hooks per-repo only

## Done

- **BREW-1** — Resolve `_ANW_SCRIPT_DIR` through symlinks
  - Spec: `docs/context/specs/BREW-1-anw-script-dir-symlink.md`
  - Todo: `docs/context/specs/BREW-1-todo.md`
  - Steps: 2 / 2 complete
  - Unblocks: brew tap rollout (`spikes/brew-packaging/`); enables `cp` from `$_ANW_SCRIPT_DIR/skills/` in COP-1

- **CTX-1** — Split tracked specs from runtime state (option G)
  - Spec: `docs/context/specs/CTX-1-spec.md`
  - Todo: `docs/context/specs/CTX-1-todo.md`
  - Steps: 13 / 13 complete
  - Branch: `feat/context-split` (ready to PR)
  - All 131 bats tests passing; fresh install produces new `docs/context/` layout
