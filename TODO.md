# TODO — Tech Debt

Items deferred from reviewer triage. Each entry includes the originating context.

## Resolved

- ~~AC_NOT_TESTED behavior at per-step scope~~ — resolved in Task 6. NO_AC, AC_NOT_TESTED, and the ac_coverage penalty are now suppressed at `--scope=step`. Behavioral gates still fire per-step.
