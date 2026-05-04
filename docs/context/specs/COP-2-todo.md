# COP-2 — Todo plan (atomic TDD steps)

> Spec: `docs/context/specs/COP-2-spec.md`
> ADR: `docs/decisions/ADR-001-copilot-cli-dispatcher-fail-closed.md`
> Driver: tdd-developer
> Total steps: 11 + integration smoke (Step 12)

Each step:
- Has a RED test you can run today (`bats tests/<file>.bats -f "<name>"`).
- Yields ONE failing test → minimal impl → test passes → 1 commit (or
  test+impl as two commits if your local TDD style does that).
- Stays under one TDD cycle (~30 min).

---

## Step 1: Test fixture — Copilot payload helpers

- **Test**:
  - Create `tests/copilot-payload-helpers.bats` with:
    - A test that loads `tests/lib/copilot-payload-helpers.bash` and asserts
      `mk_payload "bash" "git status" "/tmp/x"` returns valid JSON parseable
      by `jq -e .`, with `.toolName == "bash"` and `(.toolArgs | fromjson | .command) == "git status"`.
    - A test that `mk_payload` produces the double-encoded `toolArgs`
      shape (i.e. `.toolArgs` is a string, not an object).
- **Implement**:
  - `tests/lib/copilot-payload-helpers.bash` with `mk_payload` only
    (no scorer mock yet — that arrives in Step 8).
- **Files**:
  - `tests/lib/copilot-payload-helpers.bash` (new)
  - `tests/copilot-payload-helpers.bats` (new)
- **Commit**:
  - `test(copilot-hooks): add mk_payload fixture helper`
  - `feat(copilot-hooks): add mk_payload helper for COP-2 hook tests`

---

## Step 2: Installer creates `.github/hooks/` skeleton

- **Test** in `tests/install-project-copilot-hooks.bats`:
  - `install project` into a sandbox directory creates `.github/hooks/`
    and `.github/hooks/scripts/` directories.
  - Assertions: both directories exist after install.
- **Implement**:
  - In `ai-native-workflow`: add `install_project_copilot_hooks()`
    function. For now it only does `mkdir -p` for the two directories.
  - Wire it into `install_project()` between `install_project_copilot`
    and `install_project_gitignore` (lines 3497–3500).
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (new)
  - `ai-native-workflow` (modified)
- **Commit**:
  - `test(installer): cop-2 step 2 — copilot hooks dirs created`
  - `feat(installer): add install_project_copilot_hooks skeleton`

---

## Step 3: Vendor `confidence.sh` into `.github/hooks/scripts/`

- **Test**:
  - After `install project` in sandbox, assert
    `.github/hooks/scripts/confidence.sh` exists, has executable bit
    set (`-x`), and is byte-identical to `<repo>/scripts/confidence.sh`
    (`cmp -s` returns 0).
- **Implement**:
  - Inside `install_project_copilot_hooks()` add the `cp` from
    `$_ANW_SCRIPT_DIR/scripts/confidence.sh` to
    `$project_dir/.github/hooks/scripts/confidence.sh`, then `chmod 0755`.
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (modified)
  - `ai-native-workflow` (modified)
- **Commit**:
  - `test(installer): cop-2 step 3 — confidence.sh vendored per project`
  - `feat(installer): vendor confidence.sh into project .github/hooks/scripts/`

---

## Step 4: Dispatcher skeleton — trap + filter (allow-only, no gates yet)

- **Test** in `tests/copilot-cli-dispatcher.bats`:
  - `tests/install-project-copilot-hooks.bats`:
    - `.github/hooks/copilot-cli-dispatcher.sh` exists, mode `0755`.
    - File contains the literal substrings `trap 'emit_deny`,
      `permissionDecisionReason`, and `toolName != "bash"`.
  - `tests/copilot-cli-dispatcher.bats`:
    - Helper `run_dispatcher` that pipes a payload to the script.
    - Test 1: payload with `toolName: "read_file"` → stdout JSON has
      `permissionDecision == "allow"`, exit 0.
    - Test 2: payload with `toolName: "bash"` and any command (still no
      gate logic yet) → stdout JSON has `permissionDecision == "allow"`,
      exit 0.
    - Test 3 (fail-closed): pipe an empty stdin (no JSON) → stdout JSON
      has `permissionDecision == "deny"` with reason containing `crashed`.
- **Implement**:
  - In `install_project_copilot_hooks()` add a heredoc that writes the
    dispatcher with: shebang, `set -euo pipefail`, `emit_deny()`, `trap
    ... ERR`, stdin read, `jq` parse of `toolName`, the `!= "bash"`
    early-return printing `{"permissionDecision":"allow"}`, and a final
    fall-through that prints `allow`. **No gate logic yet.**
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (modified)
  - `tests/copilot-cli-dispatcher.bats` (new)
  - `ai-native-workflow` (modified)
- **Commit**:
  - `test(copilot-hooks): cop-2 step 4 — dispatcher trap+filter skeleton`
  - `feat(copilot-hooks): write dispatcher skeleton with fail-closed trap`

---

## Step 5: cwd resolution — payload first, fallback to `git rev-parse --show-toplevel`

- **Test** in `tests/copilot-cli-dispatcher.bats`:
  - Test: payload `cwd` is a sub-directory of a sandbox git repo →
    dispatcher must internally resolve to the repo root. Assert by
    checking that a debug trace line (e.g. `>&2 echo "PROJECT_DIR=..."`
    only when `ANW_DEBUG=1`) prints the toplevel path.
  - Test: payload missing `cwd` → dispatcher uses `pwd` then
    `git rev-parse --show-toplevel`. If outside a repo, dispatcher
    emits `deny` with reason mentioning `cannot resolve project dir`.
- **Implement**:
  - Extend the dispatcher heredoc with a `resolve_project_dir` function
    that:
    1. Reads `$PAYLOAD | jq -r '.cwd // empty'`.
    2. Falls back to `pwd`.
    3. Runs `git -C "$candidate" rev-parse --show-toplevel`.
    4. On failure, calls `emit_deny "cannot resolve project dir"`.
  - Add the `ANW_DEBUG`-gated trace line.
- **Files**:
  - `tests/copilot-cli-dispatcher.bats` (modified)
  - `ai-native-workflow` (modified — heredoc body)
- **Commit**:
  - `test(copilot-hooks): cop-2 step 5 — cwd resolution + fallback`
  - `feat(copilot-hooks): resolve project dir via payload then git toplevel`

---

## Step 6: Policy JSON writer (fresh-install path)

- **Test** in `tests/install-project-copilot-hooks.bats`:
  - After `install project` into a sandbox with no pre-existing
    `copilot-cli-policy.json`:
    - File exists.
    - `jq -e . < .github/hooks/copilot-cli-policy.json` returns 0.
    - `.version == 1`.
    - `.hooks.preToolUse | length == 1`.
    - `.hooks.preToolUse[0].bash == "./copilot-cli-dispatcher.sh"`.
    - `.hooks.preToolUse[0].cwd == ".github/hooks"`.
    - `.hooks.preToolUse[0].timeoutSec == 15`.
- **Implement**:
  - Add `write_copilot_policy_fresh` helper inside
    `install_project_copilot_hooks` that emits the JSON via `jq -n`,
    pipes through `jq -e .`, then `mv` atomically. Only writes if the
    file does NOT exist (the merge path comes in Step 7).
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (modified)
  - `ai-native-workflow` (modified)
- **Commit**:
  - `test(installer): cop-2 step 6 — fresh policy json shape`
  - `feat(installer): write copilot-cli-policy.json on fresh install`

---

## Step 7: Policy JSON writer — merge path

- **Test** in `tests/install-project-copilot-hooks.bats`:
  - Pre-populate the sandbox with a `copilot-cli-policy.json` containing
    a custom `preToolUse` entry with `bash: "./scripts/audit-log.sh"`.
  - Run `install project`.
  - Assert: `.hooks.preToolUse | length == 2`; both `audit-log.sh` and
    `copilot-cli-dispatcher.sh` present; entries deduped by `.bash`
    (re-running once more keeps `length == 2`).
- **Implement**:
  - Replace the "only writes if missing" check with a `jq` merge that
    appends our dispatcher entry to existing `preToolUse`, then
    `unique_by(.bash)`. Same atomic write.
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (modified)
  - `ai-native-workflow` (modified)
- **Commit**:
  - `test(installer): cop-2 step 7 — policy merge preserves user hooks`
  - `feat(installer): merge copilot-cli-policy.json preserving user entries`

---

## Step 8: Mock scorer fixture + TDD gate port

- **Test** in `tests/copilot-cli-dispatcher.bats`:
  - Add `mock_confidence_scorer` helper to
    `tests/lib/copilot-payload-helpers.bash` (just for symmetry; the
    TDD gate doesn't need it yet).
  - TDD-gate tests (mirror Claude tests in `tests/install.bats` lines
    related to TDD logic):
    - `git commit -m x`, no test files staged → deny with reason
      containing `TDD GATE` and `Options:`.
    - `git commit -m x`, `.tdd-skip` exists → allow.
    - `git commit --amend` → allow.
    - `git commit -m x`, staged file `foo_test.go` → allow.
    - `git commit -m x`, all staged paths under `spikes/` → allow.
    - `git status` (not a commit) → allow.
- **Implement**:
  - Extend dispatcher heredoc with the TDD gate block. Port logic from
    `hooks/tdd-gate.sh` lines 9–46. Replace `exit 2` with `emit_deny`
    using the same human message text. Keep stderr echoes too (OQ-5).
- **Files**:
  - `tests/lib/copilot-payload-helpers.bash` (modified — add mock scorer
    stub for later)
  - `tests/copilot-cli-dispatcher.bats` (modified)
  - `ai-native-workflow` (modified — heredoc body)
- **Commit**:
  - `test(copilot-hooks): cop-2 step 8 — tdd gate parity tests`
  - `feat(copilot-hooks): port tdd gate logic into dispatcher`

---

## Step 9: Confidence gate port — happy paths (GREEN/YELLOW/RED-no-bypass)

- **Test** in `tests/copilot-cli-dispatcher.bats`:
  - Use `make_log` from `tests/lib/confidence-helpers.bash` — load both
    helpers files in this bats file.
  - Tests (mirror `tests/confidence-gate-hook.bats` cases):
    - GREEN aggregate, payload `gh pr create` → allow; verdict event
      appended to log.
    - RED aggregate (`TEST_FAILED`), no override, no `.tdd-skip`,
      payload `gh pr create` → deny with reason containing `RED` and
      `TEST_FAILED`; verdict event appended.
    - YELLOW aggregate → allow with stderr warning.
    - Missing active-spec pointer → deny.
    - `glab mr create` with RED → deny (parity).
    - `git push` (not a PR command) → allow without scorer invocation.
- **Implement**:
  - Extend dispatcher heredoc with the confidence-gate block. Port
    logic from `hooks/confidence-gate.sh` lines 9–80, but resolve the
    scorer at `$PROJECT_DIR/.github/hooks/scripts/confidence.sh`
    (vendored copy), not `$SCRIPT_DIR/../scripts/confidence.sh`.
- **Files**:
  - `tests/copilot-cli-dispatcher.bats` (modified)
  - `ai-native-workflow` (modified — heredoc body)
- **Commit**:
  - `test(copilot-hooks): cop-2 step 9 — confidence gate happy paths`
  - `feat(copilot-hooks): port confidence gate (GREEN/YELLOW/RED) logic`

---

## Step 10: Confidence gate — bypass paths (skip-tdd auto + override marker)

- **Test** in `tests/copilot-cli-dispatcher.bats`:
  - RED + `.tdd-skip` + structural-only gates (`["NO_AC","AC_NOT_TESTED"]`)
    → allow; auto-bypass override event appended to log.
  - RED + `.tdd-skip` + behavioral gate (`["TEST_FAILED"]`) → deny;
    reason mentions `use /override-confidence`.
  - RED + valid override marker (`.git/aw/override-<spec>` containing
    `{"reason":"x"}`) → allow; marker file removed; override event
    appended.
  - RED + malformed override (no `reason` field) → marker file removed;
    deny.
- **Implement**:
  - Extend dispatcher heredoc with the bypass-classification block from
    `hooks/confidence-gate.sh` lines 71–113.
- **Files**:
  - `tests/copilot-cli-dispatcher.bats` (modified)
  - `ai-native-workflow` (modified — heredoc body)
- **Commit**:
  - `test(copilot-hooks): cop-2 step 10 — confidence bypass classifications`
  - `feat(copilot-hooks): port confidence-gate skip-tdd + override logic`

---

## Step 11: README stub + idempotency / backup-on-mismatch

- **Test** in `tests/install-project-copilot-hooks.bats`:
  - After `install project`: `.github/hooks/README.md` exists; content
    mentions both `tdd-gate` and `confidence-gate` (or "TDD" and
    "confidence").
  - Run `install project` twice with no edits between runs:
    `git status --porcelain .github/hooks` is empty after the second
    run (after committing the first).
  - Hand-edit dispatcher: add a marker line to
    `.github/hooks/copilot-cli-dispatcher.sh`. Run `install project`
    again. Assert: a backup file matching
    `copilot-cli-dispatcher.sh.bak.*` exists; the live dispatcher no
    longer contains the marker line.
- **Implement**:
  - Add `write_copilot_hooks_readme` helper.
  - Wrap dispatcher write with the existing `backup_if_exists` helper
    (line 64 of `ai-native-workflow`) when the existing content differs
    from what we'd write. Compute "content matches" by writing to a
    temp file and `cmp -s`.
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (modified)
  - `ai-native-workflow` (modified)
- **Commit**:
  - `test(installer): cop-2 step 11 — readme stub + backup-on-mismatch`
  - `feat(installer): add readme stub and backup hand-edits before overwrite`

---

## Step 12: Integration smoke + ARCHITECTURE/README docs

- **Test** in `tests/install-project-copilot-hooks.bats`
  (end-to-end smoke):
  - Sandbox project, run `install project`, then:
    1. Pipe a `git commit` payload (no test files staged) directly into
       `.github/hooks/copilot-cli-dispatcher.sh` and assert deny output.
    2. Pipe a non-bash payload and assert allow.
    3. Pipe a `gh pr create` payload with a freshly-created
       `.context/specs/SMOKE-1-confidence.jsonl` set up for GREEN and
       assert allow.
  - Assertion: existing 160 bats still pass (re-run `bats tests/`).
- **Implement**:
  - Add a section to `docs/ARCHITECTURE.md` under "Hook surfaces"
    describing the per-project Copilot dispatcher.
  - Add a paragraph to `README.md` under "Per-project install" pointing
    at `.github/hooks/`.
  - Optional: extend `install_project_gitignore` to add
    `.github/hooks/logs/` (FR-7), but only if the user later asks for
    audit logging. Skip otherwise.
- **Files**:
  - `tests/install-project-copilot-hooks.bats` (modified)
  - `docs/ARCHITECTURE.md` (modified)
  - `README.md` (modified)
- **Commit**:
  - `test(copilot-hooks): cop-2 step 12 — end-to-end smoke`
  - `docs: cop-2 — document copilot dispatcher in architecture + readme`

---

## Status checklist

- [x] Step 1 — payload helper fixture
- [x] Step 2 — installer skeleton + dirs
- [x] Step 3 — vendor confidence.sh
- [x] Step 4 — dispatcher skeleton (trap + filter)
- [x] Step 5 — cwd resolution
- [ ] Step 6 — policy JSON fresh write
- [ ] Step 7 — policy JSON merge
- [ ] Step 8 — TDD gate port
- [ ] Step 9 — confidence gate happy paths
- [ ] Step 10 — confidence gate bypass paths
- [ ] Step 11 — README + backup-on-mismatch
- [ ] Step 12 — integration smoke + docs

## Hand-off

> Use tdd-developer on Step 1 of `docs/context/specs/COP-2-todo.md`.
