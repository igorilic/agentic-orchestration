# BREW-1 — Resolve `_ANW_SCRIPT_DIR` through symlinks

**Status:** Proposed
**Date:** 2026-05-02
**Owner:** architect → tdd-developer
**Source:** `spikes/brew-packaging/FINDINGS.md` (TL;DR + "Critical bug discovered")

---

## Problem Statement

`ai-native-workflow` line 82 sets:

```bash
_ANW_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

`${BASH_SOURCE[0]}` is the path bash was invoked with — bash does **not** dereference
symlinks before `dirname`. Consequence: when the CLI is invoked through any symlink,
`_ANW_SCRIPT_DIR` resolves to the directory containing the **symlink**, not the directory
containing the real script.

This breaks every downstream `cp "$_ANW_SCRIPT_DIR/..."` and `source "$_ANW_SCRIPT_DIR/..."`,
of which there are 6 occurrences (lines 83, 85, 2037, 2047, 2051, 2218, 2220) — all of them
load the supporting tree (`hooks/`, `scripts/`, `skills/`) that lives next to the real script.

Confirmed live in spike (`spikes/brew-packaging/FINDINGS.md`):

```
BASH_SOURCE[0]: /tmp/brewtest/bin/myscript       <- symlink, NOT resolved
dirname:        /tmp/brewtest/bin                 <- WRONG
```

### Why now

1. **Brew install layout is exactly this scenario.** `/opt/homebrew/bin/ai-native-workflow`
   is a symlink into `/opt/homebrew/Cellar/.../libexec/`. Without the fix, brew installs
   silently fail in `install global`.
2. **Developers who alias the CLI hit the same bug.** Today the user has
   `~/.local/bin/ai-native-workflow → ~/open-source/agentic-orchestration/ai-native-workflow`;
   that works only because the symlink target sits inside the real source tree. The
   moment that assumption stops holding, the same failure mode applies.
3. **Spike-recommended fix #2:** patching the production CLI is more robust than the
   alternative (`inreplace` at brew-formula install time), and removes a fragility
   from the future tap rollout.

---

## Context

- Single bash script (`ai-native-workflow`, ~2200 lines).
- Test harness is `bats-core`. 99 existing tests live in `tests/*.bats`.
- The `_ANW_SCRIPT_DIR` line runs at script-load time (line 82), **before** any other
  helpers, before the bash version check, and before dependency setup. Whatever fix
  is chosen must run on macOS system bash 3.2 because some users may invoke the CLI
  before they've installed brew bash 5 (chicken-and-egg).
- The CLI's full feature set uses bash 4 features (`declare -A`, namerefs), but the
  `_ANW_SCRIPT_DIR` line itself sits above those uses and must remain bash 3.2-safe.
- No GNU coreutils on stock macOS — `realpath` is **not** present unless the user
  installed `coreutils` via brew (which provides `greadlink` and `grealpath`).
  System `readlink` exists but lacks `-f`.

---

## Proposed Solution

Replace line 82 with a portable symlink-resolving block that:

1. Prefers `realpath` if available (Linux, or macOS with `coreutils` installed).
2. Falls back to `greadlink -f` if available (macOS with `coreutils`).
3. Falls back to a pure-bash symlink-walk loop using only `readlink`, `dirname`, `cd`, `pwd`.

The fallback handles every macOS install where neither GNU tool is present.
After resolving the symlink chain, run the existing `cd ... && pwd` to canonicalize.

```bash
# Resolve BASH_SOURCE[0] through any symlink chain so $_ANW_SCRIPT_DIR
# is always the directory containing the real script file.
_anw_resolve_source() {
  local src="${BASH_SOURCE[0]}"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$src"
    return
  fi
  if command -v greadlink >/dev/null 2>&1; then
    greadlink -f "$src"
    return
  fi
  # Pure-bash fallback (bash 3.2-safe). Walk the symlink chain manually.
  while [ -L "$src" ]; do
    local target
    target="$(readlink "$src")"
    case "$target" in
      /*) src="$target" ;;
      *)  src="$(cd "$(dirname "$src")" && pwd)/$target" ;;
    esac
  done
  echo "$src"
}
_ANW_SCRIPT_DIR="$(cd "$(dirname "$(_anw_resolve_source)")" && pwd)"
unset -f _anw_resolve_source
```

### Why a helper function vs the inlined nested-`$(...)` from the prompt

- The prompt suggested an inlined block. That works but is ~10 lines wrapped in
  `$(cd "$(dirname "$(...)")" && pwd)` and is hard to read / hard to test.
- Extracting `_anw_resolve_source` makes the resolution unit independently
  inspectable and lets the bats test source the script (or invoke it) and assert on
  `$_ANW_SCRIPT_DIR` directly without recreating the logic in test-land.
- Function is `unset` immediately after use to keep the global namespace clean —
  symmetric with the existing helper convention in the file.
- Total addition: ~17 lines including comments. Well under the "ballooned" threshold.

### Why not `realpath` only

Single-line `realpath "$src"` is cleaner but **fails on stock macOS** where coreutils
is not installed. Brew formulas can declare `depends_on "coreutils"`, but the
production CLI also runs in non-brew contexts (developer aliases, curl-piped
installs, CI). The fallback chain costs ~6 lines and removes a class of "works on my
machine" failures.

### Trade-off summary

| Option | Pros | Cons |
|---|---|---|
| `realpath` only | 1 line | Breaks on stock macOS without coreutils |
| `realpath` → `greadlink -f` → bash loop (chosen) | Works everywhere, no new deps | ~10 extra lines |
| Patch via `inreplace` in brew formula | Zero CLI change | Fragile to script edits, doesn't help non-brew users |

Chosen option matches spike recommendation (fix #2).

---

## Acceptance Criteria

- **AC-1:** When `ai-native-workflow` is invoked at its canonical path (no symlinks),
  `$_ANW_SCRIPT_DIR` equals the directory containing the script file. (Unchanged
  behavior — regression guard.)
- **AC-2:** When invoked via a single-level symlink (`ln -s /real/path/cli /tmp/x/cli`
  and run `/tmp/x/cli`), `$_ANW_SCRIPT_DIR` resolves to `/real/path` (the real
  parent), not `/tmp/x`.
- **AC-3:** When invoked via a symlink chain (`a → b → real`), `$_ANW_SCRIPT_DIR`
  resolves to the directory of `real`, regardless of chain depth.
- **AC-4:** Resolution works on macOS (where stock `readlink` lacks `-f` and stock
  bash is 3.2) and on Linux (where both `realpath` and `readlink -f` are available).
  The macOS path is exercised by forcing the pure-bash fallback in the test fixture.
- **AC-5:** All 99 existing bats tests still pass — no regressions in
  `tests/install.bats`, `tests/sanity.bats`, `tests/confidence*.bats`, or
  `tests/cli-confidence.bats`.
- **AC-6:** A new bats file `tests/script-dir.bats` covers AC-1 through AC-3 against
  the real CLI script using a temp-dir symlink fixture.

---

## Technical Design

### Files affected

| File | Change |
|---|---|
| `ai-native-workflow` | Replace line 82 with the helper-function block above. |
| `tests/script-dir.bats` | **New.** Symlink-fixture tests for AC-1, AC-2, AC-3. |

No other files change. No new dependencies.

### Test strategy

The CLI is invoked with `AW_DRY_RUN=1` to avoid running the agent pipeline. We do
**not** want to run `install global` — that's already covered by `tests/install.bats`
and would be slow / require sandboxing. Instead we add a lightweight introspection
path: invoke the script in a mode that prints `$_ANW_SCRIPT_DIR` and exits.

Two options for the introspection probe:

1. **Source the script in the test** with a guard that skips main execution and
   inspect `$_ANW_SCRIPT_DIR` directly. Requires adding a guard like
   `[ "${_ANW_SOURCE_ONLY:-0}" = "1" ] && return 0` near the top.
2. **Add a hidden subcommand** `ai-native-workflow __print-script-dir` that echoes
   `$_ANW_SCRIPT_DIR` and exits.

**Chosen: option 2 (hidden subcommand).** Pros: doesn't pollute the script with a
sourcing-mode guard, doesn't risk leaking partially-loaded state into the test
process, naturally exercises the real invocation path (which is what we're
testing). Documented as internal/test-only — prefix with `__` per convention.
Cost: ~3 lines added near the dispatch table.

The fallback path (AC-4 macOS bash 3.2) is exercised by setting
`PATH=/usr/bin:/bin` in one test variant so neither `realpath` nor `greadlink` is
on PATH, forcing the bash loop.

### Test cases

- `script-dir: canonical invocation matches script directory` (AC-1)
- `script-dir: single-level symlink resolves to real parent dir` (AC-2)
- `script-dir: symlink chain (a -> b -> real) resolves to real parent dir` (AC-3)
- `script-dir: pure-bash fallback works without realpath/greadlink on PATH` (AC-4)

### Performance

The helper runs once per CLI invocation. Worst case: a chain of N symlinks runs N
`readlink` calls. This is identical to what `realpath` does internally. Negligible.

---

## Risks

- **Risk 1: bash 3.2 syntax slip.** The fallback loop must avoid bash 4 features.
  Specifically: no namerefs, no `${var,,}`, no `mapfile`. The proposed block uses
  only `local`, `case`, `while`, `[ -L ]`, `readlink`, `dirname`, `cd`, `pwd`,
  `echo`, all bash 3.2-safe.
  *Mitigation:* QA agent runs the bats suite under `bash --version` 3.2 if
  available; CI on macOS hits stock bash anyway when bats invokes `/usr/bin/env bash`.
- **Risk 2: `cd` in the fallback could fail silently** if a symlink points to a
  non-existent dir. The original code had the same property (`cd ... && pwd`
  short-circuits). Acceptable — same failure surface.
- **Risk 3: hidden subcommand leaks into help/usage output.** Mitigation: use a
  `__`-prefixed name and exclude from the help dispatch table.
- **Risk 4: the `unset -f` is a bash 4 feature on some old systems.** Actually
  `unset -f` is POSIX and works in bash 3.2 — verified. No risk.

---

## Out of Scope

- Brew formula authoring — that's the next ticket after BREW-1 ships.
- Replacing the `inreplace` step in `Formula/ai-native-workflow.rb`. The formula
  draft in the spike still calls `inreplace`; once BREW-1 lands, the formula can
  drop that step in a follow-up.
- Refactoring the 6 callers of `_ANW_SCRIPT_DIR` — they're already correct given
  a correct `_ANW_SCRIPT_DIR`.
- Changes to `tests/install.bats` — its existing assertions are valid as-is and
  will exercise the fixed code path through the normal bats invocation.

---

## Open Questions

None. The spike already verified the bug behavior live and the recommended fix
direction. Architect chose helper-function form over inlined form for readability;
that is a style call, not a behavioral one.
