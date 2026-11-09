# Current sprint

## In progress

- **HARNESS-2**: native-first, minimal, verifiable harness for Claude Code and Copilot CLI
  - Spec: `docs/context/specs/HARNESS-2-spec.html`
  - Todo: `docs/context/specs/HARNESS-2-todo.html`
  - ADR: `docs/decisions/ADR-003-native-first-harness.html`
  - Phase: P0 and P1 done on `feat/harness-2-native-first` (local, not pushed). P2 hardening is optional.
  - Live: `make smoke` passed 8/8 on 2026-10-08, its second run. The first run found a guard gap,
    now fixed. Both runs are in ADR-003.
  - Next: `/check` on the branch, then `/pr` when you say so.

## Done

- **COP-1**: symmetric Copilot CLI harness for `install global`
  - Spec: `docs/context/specs/COP-1-spec.html`
  - Todo: `docs/context/specs/COP-1-todo.html`
  - Steps: 11 / 11 complete (merged via PR #4)

- **BREW-1**: resolve `_ANW_SCRIPT_DIR` through symlinks
  - Spec: `docs/context/specs/BREW-1-anw-script-dir-symlink.html`
  - Todo: `docs/context/specs/BREW-1-todo.html`
  - Steps: 2 / 2 complete
  - Unblocks: the brew tap rollout (`spikes/brew-packaging/`)

- **CTX-1**: split tracked specs from runtime state (option G)
  - Spec: `docs/context/specs/CTX-1-spec.html`
  - Todo: `docs/context/specs/CTX-1-todo.html`
  - Steps: 13 / 13 complete

## Superseded by HARNESS-2 (ADR-003)

- **SDK-1**: live pipeline rendering and model-routed delegation. The pipeline now renders
  Claude's own `stream-json` events, and the custom agents and the protocol behind the delegation
  are gone. History: `docs/context/specs/SDK-1-*.html`, ADR-002.
- **COP-2**: per-project Copilot hooks. Copilot CLI supports user-global hooks, so both tools now
  share the same two global hooks. History: `docs/context/specs/COP-2-*.html`, ADR-001.
