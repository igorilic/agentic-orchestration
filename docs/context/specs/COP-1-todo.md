# COP-1 — Todo plan

**Spec:** `docs/context/specs/COP-1-spec.md`
**Total steps:** 10 (8 implementation + 1 docs + 1 integration smoke)
**Driver:** tdd-developer
**Hand-off line for each step:** `Use tdd-developer on Step <N> of COP-1-todo.md`

Each step is a single atomic TDD cycle (RED → GREEN → REFACTOR), under
30 minutes, results in one or two commits (test commit + impl commit),
and ends with a green `bats tests/` run.

The bats test file `tests/install-copilot.bats` (NEW) is grown
incrementally across the steps. Step 1 creates it; subsequent steps
append to it.

> The fake-`copilot` PATH stub and `COPILOT_HOME=$SANDBOX` setup are
> identical for steps 1–7. Add the shared `setup()` / `teardown()` to
> `tests/install-copilot.bats` in Step 1; later steps just append
> `@test` blocks.

---

### Step 1: Hoist `COPILOT_*` constants to top-level

- **Test (RED):** Add `tests/install-copilot.bats` with a single
  `@test` that asserts the new constants are defined and referenced:

  ```
  @test "installer: COPILOT_DIR / COPILOT_SKILLS_DIR / COPILOT_INSTRUCTIONS_FILE / COPILOT_SETTINGS_FILE are top-level constants" {
    grep -qE '^COPILOT_DIR="\$\{COPILOT_HOME:-\$HOME/\.copilot\}"' "$INSTALLER"
    grep -qE '^COPILOT_AGENTS_DIR=' "$INSTALLER"
    grep -qE '^COPILOT_SKILLS_DIR=' "$INSTALLER"
    grep -qE '^COPILOT_INSTRUCTIONS_FILE=' "$INSTALLER"
    grep -qE '^COPILOT_SETTINGS_FILE=' "$INSTALLER"
    # And: no function-local COPILOT_DIR redefinitions remain
    ! grep -q 'local COPILOT_DIR=' "$INSTALLER"
  }
  ```

- **Implement (GREEN):**
  - Add the 5 constants right after the existing `CLAUDE_DIR=` line at
    the top of `ai-native-workflow` (see spec §3.1).
  - Remove the three `local COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"`
    lines from `install_copilot_agents` (~L3165), `show_status`
    (~L4088), and `uninstall_global` (~L4233). Replace each downstream
    reference with the global `$COPILOT_DIR`. All those references are
    inside the same functions so this is a mechanical edit.
  - Replace `$COPILOT_DIR/agents` paths with `$COPILOT_AGENTS_DIR` in
    those three functions.

- **Files:**
  - `ai-native-workflow` (top-level constant block + 3 functions)
  - `tests/install-copilot.bats` (NEW)

- **Verify:** `bats tests/install-copilot.bats` (1/1 green).
  `bats tests/` — full suite still green (regression guard).

- **Commit:**
  - `test(installer): add constants probe for COPILOT_* top-level vars`
  - `refactor(installer): hoist COPILOT_* paths to top-level constants`

---

### Step 2: `install_global_copilot_skills` — copy every skill

- **Test (RED):** Append to `tests/install-copilot.bats`:

  1. Test that runs `install global` against sandbox and asserts
     **every** subdirectory of `skills/` in the repo source becomes
     a `<name>/SKILL.md` under `$COPILOT_HOME/skills/`. Implementation
     hint: iterate the source directory in the test, do not hardcode
     the 14 names — keeps tests robust against new skills.

     ```
     @test "install global: copies every skill from source to $COPILOT_HOME/skills/" {
       run_install_global  # helper that exports CLAUDE_HOME + COPILOT_HOME and runs installer
       for d in "$REPO_ROOT/skills"/*/; do
         name="$(basename "$d")"
         [ -f "$SANDBOX/skills/$name/SKILL.md" ] || { echo "missing: $name"; return 1; }
       done
     }
     ```

  2. Test that `override-confidence/skill.bash` is also copied (the
     skill is multi-file; assert the auxiliary file).

     ```
     @test "install global: copies override-confidence/skill.bash to $COPILOT_HOME/skills/" {
       run_install_global
       [ -f "$SANDBOX/skills/override-confidence/skill.bash" ]
     }
     ```

- **Implement (GREEN):**
  - New function `install_global_copilot_skills` placed immediately
    after `install_copilot_agents` in `ai-native-workflow`. Body:
    print a header, `mkdir -p "$COPILOT_SKILLS_DIR"`, iterate
    `"$_ANW_SCRIPT_DIR"/skills/*/`, for each: backup existing
    `SKILL.md` if present, `cp -R` source dir contents, print success.
  - Wire one new line into `install_global` after the
    `install_copilot_agents` call: `install_global_copilot_skills`.
  - Guard at top of fn: `command -v copilot &>/dev/null || return 0`
    (graceful skip when Copilot CLI absent).

- **Files:**
  - `ai-native-workflow` (new fn + 1-line wire-in)
  - `tests/install-copilot.bats` (2 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (3/3). `bats tests/` green.

- **Commit:**
  - `test(install-copilot): assert all skills copied to COPILOT_HOME`
  - `feat(install-copilot): install all skills to ~/.copilot/skills/`

---

### Step 3: Pipeline-skill rewrite — `claude --agent=` → `copilot --agent=`

- **Test (RED):** Append three tests to `tests/install-copilot.bats`:

  ```
  @test "install global: pipeline-gitlab-feature SKILL.md uses copilot --agent= (not claude)" {
    run_install_global
    grep -q 'copilot --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
    ! grep -q 'claude --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
  }

  @test "install global: pipeline-gitlab-incident SKILL.md uses copilot --agent=" {
    run_install_global
    grep -q 'copilot --agent=' "$SANDBOX/skills/pipeline-gitlab-incident/SKILL.md"
    ! grep -q 'claude --agent=' "$SANDBOX/skills/pipeline-gitlab-incident/SKILL.md"
  }

  @test "install global: explore SKILL.md uses copilot --agent= in copilot install path" {
    run_install_global
    grep -q 'copilot --agent=' "$SANDBOX/skills/explore/SKILL.md"
    ! grep -q 'claude --agent=' "$SANDBOX/skills/explore/SKILL.md"
  }
  ```

  Also add a regression guard: the **Claude** side still gets
  `claude --agent=` (the rewrite must only affect the Copilot copy):

  ```
  @test "install global: Claude side keeps claude --agent= (rewrite is Copilot-only)" {
    run_install_global
    grep -q 'claude --agent=' "$CLAUDE_HOME/skills/pipeline-gitlab-feature/SKILL.md"
  }
  ```

- **Implement (GREEN):** Inside `install_global_copilot_skills`, after
  the `cp -R` loop, add the dynamic rewrite block from spec §5.3.
  Use `sed -i.tmp 's/claude --agent=/copilot --agent=/g'` followed by
  `rm -f "${skill_md}.tmp"` for cross-platform sed portability.

- **Files:**
  - `ai-native-workflow` (rewrite block inside `install_global_copilot_skills`)
  - `tests/install-copilot.bats` (4 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (7/7). `bats tests/` green.

- **Commit:**
  - `test(install-copilot): assert claude→copilot rewrite in pipeline skills`
  - `feat(install-copilot): rewrite agent invocations in copied skills`

---

### Step 4: `install_global_copilot_instructions` — global instructions file

- **Test (RED):** Append:

  ```
  @test "install global: writes copilot-instructions.md with required marker substrings" {
    run_install_global
    [ -f "$SANDBOX/copilot-instructions.md" ]
    grep -q 'Stack Detection'  "$SANDBOX/copilot-instructions.md"
    grep -q 'Agent Pipeline'   "$SANDBOX/copilot-instructions.md"
    grep -q '/plan'            "$SANDBOX/copilot-instructions.md"
    # Negative: no Claude-specific phrasing
    ! grep -q '~/.claude/'        "$SANDBOX/copilot-instructions.md"
    ! grep -q 'Claude Code session' "$SANDBOX/copilot-instructions.md"
  }

  @test "install global: copilot-instructions.md is backed up on re-install" {
    run_install_global
    run_install_global
    # Exactly one backup file should exist after the second run
    backups=( "$SANDBOX"/copilot-instructions.md.bak.* )
    [ "${#backups[@]}" -eq 1 ]
  }
  ```

- **Implement (GREEN):**
  - New function `install_global_copilot_instructions`:
    `mkdir -p "$COPILOT_DIR"`, `backup_if_exists "$COPILOT_INSTRUCTIONS_FILE"`,
    write a heredoc with content semantically equivalent to the
    Claude `CLAUDE.md` heredoc (~L1698) but with neutral phrasing
    (no `~/.claude/`, no "Claude Code session"). Keep `Stack Detection`,
    `Agent Pipeline`, and `/plan` substrings so the marker test
    passes.
  - Wire one new line into `install_global` after
    `install_global_copilot_skills`: `install_global_copilot_instructions`.
  - Guard at top of fn: `command -v copilot &>/dev/null || return 0`.

- **Files:**
  - `ai-native-workflow` (new fn + 1-line wire-in)
  - `tests/install-copilot.bats` (2 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (9/9). `bats tests/` green.

- **Commit:**
  - `test(install-copilot): assert copilot-instructions.md content + backup`
  - `feat(install-copilot): install ~/.copilot/copilot-instructions.md`

---

### Step 5: `install_global_copilot_settings` — fresh install path

- **Test (RED):** Append:

  ```
  @test "install global: settings.json fresh install seeds renderMarkdown/theme/beep" {
    run_install_global
    [ -f "$SANDBOX/settings.json" ]
    [ "$(jq -r '.renderMarkdown' "$SANDBOX/settings.json")" = "true" ]
    [ "$(jq -r '.theme'          "$SANDBOX/settings.json")" = "auto" ]
    [ "$(jq -r '.beep'           "$SANDBOX/settings.json")" = "true" ]
  }

  @test "install global: settings.json fresh install has no hooks key" {
    run_install_global
    ! jq -e '.hooks' "$SANDBOX/settings.json" >/dev/null 2>&1
  }
  ```

- **Implement (GREEN):**
  - New function `install_global_copilot_settings`. Body for the
    fresh path only (target absent): write the literal JSON
    `{"renderMarkdown": true, "theme": "auto", "beep": true}` via a
    heredoc → `jq '.'` if jq present, else heredoc literal as fallback
    (per Risk R-3).
  - Wire into `install_global` after `install_global_copilot_instructions`.
  - Guard: `command -v copilot &>/dev/null || return 0`.

- **Files:**
  - `ai-native-workflow` (new fn + 1-line wire-in)
  - `tests/install-copilot.bats` (2 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (11/11). `bats tests/` green.

- **Commit:**
  - `test(install-copilot): assert settings.json fresh install shape`
  - `feat(install-copilot): seed ~/.copilot/settings.json on fresh install`

---

### Step 6: `install_global_copilot_settings` — merge path preserves user keys

- **Test (RED):** Append (this is the meaty one):

  ```
  @test "install global: settings.json merge preserves user-set model/effortLevel/allowedUrls" {
    mkdir -p "$SANDBOX"
    cat > "$SANDBOX/settings.json" <<'JSON'
  {"model": "gpt-5", "effortLevel": "high", "allowedUrls": ["https://example.com"]}
  JSON
    run_install_global
    [ "$(jq -r '.model'           "$SANDBOX/settings.json")" = "gpt-5" ]
    [ "$(jq -r '.effortLevel'     "$SANDBOX/settings.json")" = "high" ]
    [ "$(jq -r '.allowedUrls[0]'  "$SANDBOX/settings.json")" = "https://example.com" ]
    # Defaults filled in for missing keys:
    [ "$(jq -r '.renderMarkdown'  "$SANDBOX/settings.json")" = "true" ]
    [ "$(jq -r '.theme'           "$SANDBOX/settings.json")" = "auto" ]
    # And exactly one backup of the pre-merge file:
    backups=( "$SANDBOX"/settings.json.bak.* )
    [ "${#backups[@]}" -eq 1 ]
  }

  @test "install global: settings.json merge does NOT overwrite existing user value" {
    mkdir -p "$SANDBOX"
    echo '{"theme":"dark","beep":false}' > "$SANDBOX/settings.json"
    run_install_global
    [ "$(jq -r '.theme' "$SANDBOX/settings.json")" = "dark" ]
    [ "$(jq -r '.beep'  "$SANDBOX/settings.json")" = "false" ]
  }
  ```

- **Implement (GREEN):** Extend `install_global_copilot_settings` with
  the merge branch from spec §5.4. Use
  `jq --slurpfile existing "$f" '. * $existing[0]'` so existing keys
  win over defaults. `command -v jq` guard with warn-and-return on
  absent.

- **Files:**
  - `ai-native-workflow` (extend the new fn)
  - `tests/install-copilot.bats` (2 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (13/13). `bats tests/` green.

- **Commit:**
  - `test(install-copilot): assert settings.json merge preserves user keys`
  - `feat(install-copilot): merge user settings.json with defaults additively`

---

### Step 7: Graceful handling — Copilot CLI absent + closing-banner caveat

- **Test (RED):** Append:

  ```
  @test "install global: skips Copilot section when copilot is not on PATH" {
    EMPTY_BIN="$(mktemp -d /tmp/aw-empty-XXXXXX)"
    PATH="$EMPTY_BIN:/usr/bin:/bin" \
      CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" install global >/dev/null 2>&1
    rm -rf "$EMPTY_BIN"
    [ ! -d "$SANDBOX/skills" ]
    [ ! -f "$SANDBOX/copilot-instructions.md" ]
    [ ! -f "$SANDBOX/settings.json" ]
  }

  @test "install global: closing banner mentions hooks-not-globally-installed caveat" {
    output="$(run_install_global 2>&1)"
    [[ "$output" == *"Copilot hooks are NOT installed globally"* ]]
  }

  @test "install global: closing banner caveat prints even when copilot is absent" {
    EMPTY_BIN="$(mktemp -d /tmp/aw-empty-XXXXXX)"
    output="$(PATH="$EMPTY_BIN:/usr/bin:/bin" \
      CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" install global 2>&1)"
    rm -rf "$EMPTY_BIN"
    [[ "$output" == *"Copilot hooks are NOT installed globally"* ]]
  }
  ```

- **Implement (GREEN):**
  - Confirm the `command -v copilot` guards added in Steps 2/4/5 are
    sufficient. If not, fix here.
  - Update the closing banner of `install_global` (~L1685) to print
    the caveat unconditionally (outside any `command -v copilot`
    guard) per spec §3.3. Format:

    ```bash
    echo ""
    dim "▸ Copilot hooks are NOT installed globally — Copilot CLI scopes"
    dim "  hooks per-repo. Run \`ai-native-workflow install project\` in"
    dim "  trusted folders for repo-level hooks (COP-2; not yet shipped)."
    ```

- **Files:**
  - `ai-native-workflow` (banner edit; possibly fn-guard tightening)
  - `tests/install-copilot.bats` (3 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (16/16). `bats tests/` green.

- **Commit:**
  - `test(install-copilot): assert graceful skip + hooks caveat banner`
  - `feat(install-copilot): print hooks-not-global caveat unconditionally`

---

### Step 8: Status command surfaces Copilot artifacts

- **Test (RED):** Append:

  ```
  @test "status: lists every installed Copilot skill with ✓" {
    run_install_global
    output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" status 2>&1)"
    for d in "$REPO_ROOT/skills"/*/; do
      name="$(basename "$d")"
      [[ "$output" == *"skills/$name"* ]]
    done
  }

  @test "status: lists copilot-instructions.md and settings.json" {
    run_install_global
    output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" status 2>&1)"
    [[ "$output" == *"copilot-instructions.md"* ]]
    [[ "$output" == *"settings.json"* ]]
  }
  ```

- **Implement (GREEN):** Edit `show_status` (~L4088) per spec §3.4:
  - Add `check_file "$COPILOT_INSTRUCTIONS_FILE" "copilot-instructions.md"`
  - Add `check_file "$COPILOT_SETTINGS_FILE" "settings.json"`
  - Add the dynamic skills loop: `for d in "$COPILOT_SKILLS_DIR"/*/; do ...`

- **Files:**
  - `ai-native-workflow` (`show_status` edit)
  - `tests/install-copilot.bats` (2 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (18/18). `bats tests/` green.

- **Commit:**
  - `test(status): assert Copilot skills/instructions/settings shown`
  - `feat(status): list new Copilot artifacts in status output`

---

### Step 9: Uninstall removes Copilot skills, preserves user files

- **Test (RED):** Append:

  ```
  @test "uninstall global: removes ~/.copilot/skills/ tree" {
    run_install_global
    [ -d "$SANDBOX/skills" ]
    CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" uninstall global >/dev/null 2>&1
    [ ! -d "$SANDBOX/skills" ]
  }

  @test "uninstall global: preserves copilot-instructions.md (warns instead)" {
    run_install_global
    output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" uninstall global 2>&1)"
    [ -f "$SANDBOX/copilot-instructions.md" ]
    [[ "$output" == *"copilot-instructions.md preserved"* ]] || \
      [[ "$output" == *"copilot-instructions.md"*preserved* ]]
  }

  @test "uninstall global: preserves settings.json (warns instead)" {
    run_install_global
    CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" uninstall global >/dev/null 2>&1
    [ -f "$SANDBOX/settings.json" ]
  }
  ```

- **Implement (GREEN):** Edit `uninstall_global` (~L4232) per spec §3.5:
  - Add `rm -rf "$COPILOT_SKILLS_DIR"` to the explicit removal list
    (or do it inline; mirror however the Claude side handles its
    skills directory removal).
  - Add a `warn "~/.copilot/copilot-instructions.md and ~/.copilot/settings.json preserved"`
    line, mirroring the existing warn for `CLAUDE.md`/`settings.json`
    on the Claude side (~L4229).

- **Files:**
  - `ai-native-workflow` (`uninstall_global` edit)
  - `tests/install-copilot.bats` (3 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (21/21). `bats tests/` green.

- **Commit:**
  - `test(uninstall): assert Copilot skills removed, user files preserved`
  - `feat(uninstall): remove ~/.copilot/skills/, preserve user files`

---

### Step 10: Documentation — README + ARCHITECTURE updates

- **Test (RED):** Append:

  ```
  @test "docs: README mentions ~/.copilot/skills/" {
    rg -q '~/\.copilot/skills/' "$BATS_TEST_DIRNAME/../README.md"
  }

  @test "docs: README mentions ~/.copilot/copilot-instructions.md" {
    rg -q '~/\.copilot/copilot-instructions\.md' "$BATS_TEST_DIRNAME/../README.md"
  }

  @test "docs: README mentions ~/.copilot/settings.json" {
    rg -q '~/\.copilot/settings\.json' "$BATS_TEST_DIRNAME/../README.md"
  }

  @test "docs: ARCHITECTURE notes hooks asymmetry (Claude global, Copilot repo-scope)" {
    rg -qi 'copilot.*(repo|repository)[- ]scope|repo[- ]scope.*copilot' \
      "$BATS_TEST_DIRNAME/../docs/ARCHITECTURE.md"
  }
  ```

- **Implement (GREEN):**
  - Edit `README.md`: add a short "What `install global` writes" block
    near the existing "Quick Start". List the new Copilot artifacts.
    Add one sentence on the hooks asymmetry.
  - Edit `docs/ARCHITECTURE.md`: add a "Symmetric harness" subsection
    (≤ 1 paragraph) under the three-layer diagram noting that
    skills + agents + global instructions are symmetric across Claude
    Code and Copilot CLI; hooks are Claude-global today, Copilot
    repo-scope (COP-2 deferred).

- **Files:**
  - `README.md`
  - `docs/ARCHITECTURE.md`
  - `tests/install-copilot.bats` (4 tests appended)

- **Verify:** `bats tests/install-copilot.bats` (25/25). `bats tests/` green.

- **Commit:**
  - `test(docs): assert README + ARCHITECTURE mention Copilot harness`
  - `docs(cop-1): document symmetric Copilot CLI harness`

---

### Step 11: Integration smoke — fresh install end-to-end + idempotency

- **Test:** Append one large `@test` to `tests/install-copilot.bats`
  that exercises every AC in one run:

  ```
  @test "integration smoke: install global twice produces full Copilot harness, one backup per file per re-run" {
    run_install_global
    # Snapshot first-run state
    first_skills_count=$(find "$SANDBOX/skills" -name 'SKILL.md' | wc -l | tr -d ' ')
    [ "$first_skills_count" -ge 14 ]
    [ -f "$SANDBOX/copilot-instructions.md" ]
    [ -f "$SANDBOX/settings.json" ]
    # Re-run
    run_install_global
    # Backups exist for each rewritten file
    [ "$(find "$SANDBOX" -maxdepth 2 -name 'copilot-instructions.md.bak.*' | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(find "$SANDBOX" -maxdepth 2 -name 'settings.json.bak.*' | wc -l | tr -d ' ')" -eq 1 ]
    # Pipeline rewrite still in place after re-run
    grep -q 'copilot --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
    ! grep -q 'claude --agent=' "$SANDBOX/skills/pipeline-gitlab-feature/SKILL.md"
    # Status reflects the install
    output="$(CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
      "$INSTALLER" status 2>&1)"
    [[ "$output" == *"copilot-instructions.md"* ]]
    [[ "$output" == *"settings.json"* ]]
  }

  @test "integration smoke: COPILOT_HOME=/tmp/cop-test redirects all writes" {
    ALT="$(mktemp -d /tmp/aw-cop-alt-XXXXXX)"
    PATH="$STUB_BIN:$PATH" CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$ALT" \
      "$INSTALLER" install global >/dev/null 2>&1
    [ -d "$ALT/skills" ]
    [ -f "$ALT/copilot-instructions.md" ]
    [ -f "$ALT/settings.json" ]
    rm -rf "$ALT"
  }
  ```

- **Implement:** No production code change expected. If a test fails
  here it surfaces an integration defect — fix forward.

- **Files:**
  - `tests/install-copilot.bats` (2 tests appended)

- **Verify:** `bats tests/` — full suite green (target: ~133 tests
  total: 131 pre-existing + 25 new from steps 1–10 + 2 here =
  approximately, depending on prior counts).

- **Commit:**
  - `test(integration): smoke COP-1 install global end-to-end`

  (Single commit; this is a verification step, no production code.)

---

## Status checklist

- [x] **Step 1** — Hoist `COPILOT_*` constants
  - [x] Test added (constants probe)
  - [x] Implementation: top-level constants + 3 functions de-localized
  - [x] AC: covers spec §3.1 prereq for all later steps
- [x] **Step 2** — Skills install
  - [x] Tests added (every-skill loop, multi-file skill)
  - [x] Implementation: `install_global_copilot_skills` + wire-in
  - [x] AC-1 covered
- [x] **Step 3** — Pipeline-skill rewrite
  - [x] Tests added (3 affected skills + Claude-side regression guard)
  - [x] Implementation: dynamic sed rewrite block
  - [x] AC-2 covered
- [x] **Step 4** — Global instructions file
  - [x] Tests added (markers + backup)
  - [x] Implementation: `install_global_copilot_instructions` + wire-in
  - [x] AC-3, AC-6 covered
- [ ] **Step 5** — Settings.json fresh install
  - [ ] Tests added (renderMarkdown/theme/beep, no hooks)
  - [ ] Implementation: fresh-path heredoc/jq write
  - [ ] AC-4 covered
- [ ] **Step 6** — Settings.json merge
  - [ ] Tests added (preserve user keys, defaults fill gaps)
  - [ ] Implementation: jq additive merge
  - [ ] AC-5 covered
- [ ] **Step 7** — Graceful skip + hooks caveat banner
  - [ ] Tests added (3 cases)
  - [ ] Implementation: banner edit, guard verification
  - [ ] AC-8, AC-12 covered
- [ ] **Step 8** — Status command
  - [ ] Tests added (skills loop + 2 files)
  - [ ] Implementation: `show_status` edits
  - [ ] AC-10 covered
- [ ] **Step 9** — Uninstall
  - [ ] Tests added (skills removed, user files preserved)
  - [ ] Implementation: `uninstall_global` edits
  - [ ] AC-11 covered
- [ ] **Step 10** — Documentation
  - [ ] Tests added (README + ARCHITECTURE asserts)
  - [ ] Implementation: README + ARCHITECTURE edits
  - [ ] AC-13 covered
- [ ] **Step 11** — Integration smoke
  - [ ] Tests added (idempotency + COPILOT_HOME override)
  - [ ] AC-7, AC-9 covered
- [ ] Spec marked **Done** in `docs/context/CURRENT_SPRINT.md`

## Bats helper to add in Step 1's `tests/install-copilot.bats` setup

For reference (kept here so the tdd-developer doesn't have to invent
it from scratch):

```bash
INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-cop-XXXXXX)"
  CLAUDE_HOME_DIR="$(mktemp -d /tmp/aw-claude-XXXXXX)"
  STUB_BIN="$(mktemp -d /tmp/aw-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/copilot"
  chmod +x "$STUB_BIN/copilot"
  export PATH="$STUB_BIN:$PATH"
  export COPILOT_HOME="$SANDBOX"
  export CLAUDE_HOME="$CLAUDE_HOME_DIR"
}

teardown() {
  rm -rf "$SANDBOX" "$CLAUDE_HOME_DIR" "$STUB_BIN"
}

run_install_global() {
  CLAUDE_HOME="$CLAUDE_HOME" COPILOT_HOME="$SANDBOX" \
    PATH="$STUB_BIN:$PATH" \
    "$INSTALLER" install global "$@"
}
```
