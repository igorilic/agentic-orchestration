# BREW-1 — Todo plan

**Spec:** `docs/context/specs/BREW-1-anw-script-dir-symlink.md`
**Total steps:** 2 (resolution fix + integration smoke)

Each step is a single atomic TDD cycle. The fix itself is genuinely small;
splitting further would be ceremonial.

---

### Step 1: Resolve `_ANW_SCRIPT_DIR` through symlinks

- **Test (RED):** Add `tests/script-dir.bats` with four bats cases. The script
  doesn't expose `_ANW_SCRIPT_DIR` yet, so first add a small introspection probe
  in the same step (it is part of the same atomic change — without it, the new
  behavior cannot be observed).

  Cases (against the real `ai-native-workflow` script via the `__print-script-dir`
  internal subcommand):

  1. `script-dir: canonical invocation matches script directory` — invoke
     `<repo>/ai-native-workflow __print-script-dir`, assert output equals
     `<repo>` resolved via `pwd -P`. (AC-1)
  2. `script-dir: single-level symlink resolves to real parent dir` — `ln -s` the
     CLI into a fresh `mktemp -d`, invoke the symlink, assert output equals the
     real script directory, **not** the temp dir. (AC-2)
  3. `script-dir: symlink chain (a -> b -> real) resolves to real parent dir` —
     two-hop chain in two temp dirs, invoke through the head of the chain,
     assert real parent. (AC-3)
  4. `script-dir: pure-bash fallback works without realpath/greadlink on PATH` —
     run case 2 again with `PATH=/usr/bin:/bin` (and `unset` of `realpath` /
     `greadlink` aliases if any), confirm same output. (AC-4)

  All four cases should fail before the fix lands (cases 2/3/4 because of the
  bug; case 1 because `__print-script-dir` doesn't exist yet).

- **Implement (GREEN):** Apply two small edits to `ai-native-workflow`:

  1. **Replace line 82** with the helper-function block from the spec:

     ```bash
     _anw_resolve_source() {
       local src="${BASH_SOURCE[0]}"
       if command -v realpath >/dev/null 2>&1; then
         realpath "$src"; return
       fi
       if command -v greadlink >/dev/null 2>&1; then
         greadlink -f "$src"; return
       fi
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

  2. **Add the `__print-script-dir` internal subcommand** in the dispatch table.
     Place it next to the existing top-level command dispatch (search for the
     `case "$1" in` block that handles `install|run|detect|status|...`). Add:

     ```bash
     __print-script-dir)
       echo "$_ANW_SCRIPT_DIR"
       exit 0
       ;;
     ```

     The `__` prefix marks it internal. Do **not** add it to the help text or
     usage banner — keep it test-only.

- **Files:**
  - `ai-native-workflow` (edit line 82 region; add internal subcommand in dispatch)
  - `tests/script-dir.bats` (new file)

- **Verify:** `bats tests/script-dir.bats` — all 4 pass. Then
  `bats tests/` — all 99 pre-existing tests still pass (AC-5).

- **Commit:**
  - `test(cli): add symlink-resolution tests for _ANW_SCRIPT_DIR`
  - `fix(cli): resolve _ANW_SCRIPT_DIR through symlink chains`

  (Two commits per the RED/GREEN convention. Test commit first; it will fail CI
  in isolation, but the GREEN commit immediately follows in the same PR.)

---

### Step 2: Integration smoke — installer survives symlink invocation

This step guards against the original failure mode end-to-end. `tests/install.bats`
already exercises `install global` against the canonical script path; we need one
test that exercises it through a symlink, replicating the brew layout.

- **Test (RED):** Add to `tests/install.bats` (or new `tests/install-symlink.bats`
  if the existing file's setup pattern doesn't fit cleanly):

  ```
  @test "install: install global succeeds when invoked via a symlink (brew layout)"
  ```

  - Create temp dir `LINKDIR=$(mktemp -d)`.
  - `ln -s "$INSTALLER" "$LINKDIR/ai-native-workflow"`.
  - Set `CLAUDE_HOME="$SANDBOX"` and run `"$LINKDIR/ai-native-workflow" install global`.
  - Assert exit code is 0.
  - Assert at least one canary file is present, e.g.
    `[ -f "$SANDBOX/hooks/confidence-gate.sh" ]` and
    `[ -f "$SANDBOX/scripts/confidence-cli.sh" ]`.
  - Cleanup: `rm -rf "$LINKDIR"` in teardown.

  Before Step 1's fix, this test would fail with `cp: ... No such file or directory`
  errors out of `install_global`. After Step 1, it should pass — but we add it
  explicitly to lock the regression.

- **Implement (GREEN):** No production code change expected. Step 1's fix is what
  makes this test pass. If the test fails here, that's a real defect surfaced —
  fix forward.

- **Files:**
  - `tests/install.bats` (one test added) **or** `tests/install-symlink.bats` (new)
  - No production code change expected.

- **Verify:** `bats tests/install.bats` (or full `bats tests/`) — green.

- **Commit:**
  - `test(install): exercise install global via symlinked CLI invocation`

---

## Status checklist

- [x] Step 1 — `_ANW_SCRIPT_DIR` symlink resolution + internal probe
  - [x] Test added (`tests/script-dir.bats`, 4 cases)
  - [x] Implementation applied (helper function + internal subcommand)
  - [x] All 99 pre-existing tests still pass
  - [x] AC-1, AC-2, AC-3, AC-4 covered
- [x] Step 2 — Integration smoke through symlink
  - [x] Test added (`install: install global succeeds when invoked via a symlink`)
  - [x] Test passes against fixed CLI
  - [x] AC-5 confirmed (full bats suite green)
- [x] AC-6 satisfied: `tests/script-dir.bats` exists and covers AC-1..AC-3
- [ ] Spec marked **Done** in `docs/context/CURRENT_SPRINT.md`
