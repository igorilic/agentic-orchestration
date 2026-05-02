# TODO — Tech Debt

Items deferred from reviewer triage. Each entry includes the originating context.

## Confidence gate

- **AC_NOT_TESTED behavior at per-step scope** — at `--scope=step --step=N`, the gate fires whenever step N's `ac_items_tested` doesn't cover every AC in the spec. Since most steps cover only a subset of ACs by design, per-step verdicts will frequently be RED for this reason alone. The gate is correct behavior at aggregate scope (final state must cover all AC), but it's noisy at per-step.
  - Origin: reviewer of commit `634e8ea` (Task 3, six hard gates)
  - Revisit during Task 6 (per-step scoping tests) — likely fix is to skip structural gates (NO_AC, AC_NOT_TESTED) at per-step scope and only fire them at aggregate.
