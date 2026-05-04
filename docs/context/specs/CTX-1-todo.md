# CTX-1 — Atomic todo plan

**Branch:** `feat/context-split` (cut from `main` before Step 1)

Each step is independently testable, results in one commit (or two — test+impl per TDD), and completes in one ~30 minute TDD cycle. Step 7 is doc-only and uses `/skip-tdd` per the request's constraint.

Order matters: tests first that codify the new convention, then the source-of-truth updates (agents → CLI → installer → templates), then the actual file migration, then docs and a smoke pass.

---

### Step 1: Add bats tests for new install layout (RED)

- **Test:**
  - In `tests/install.bats`, add 4 new `@test`s:
    - `install project: creates docs/context/CURRENT_SPRINT.md` — runs `ai-native-workflow install project "$SANDBOX_PROJECT"` into a fresh tempdir, asserts file exists.
    - `install project: creates docs/context/specs/templates/feature-spec.md` — same setup, asserts the templated spec file exists at the new path.
    - `install project: project .gitignore contains runtime ignore entries` — asserts `grep -F '.context/.pipeline-state' "$SANDBOX_PROJECT/.gitignore"` and the same for `.context/.pipeline-audit.log` and `.context/specs/*.jsonl`.
    - `install project: project .gitignore does NOT contain bare .context/` — asserts `! grep -E '^\.context/$' "$SANDBOX_PROJECT/.gitignore"`.
  - These tests will FAIL initially because the installer still writes `.context/CURRENT_SPRINT.md` etc.
- **Implement:** Nothing yet — RED phase. Just the test file additions.
- **Files:** `tests/install.bats`
- **Commit:** `test(install): assert new docs/context layout and runtime-only .gitignore`

---

### Step 2: Update installer to write new layout (GREEN for Step 1)

- **Test:** Step 1's 4 new bats tests pass. All previous bats tests still pass (`bats tests/`).
- **Implement:**
  - In `ai-native-workflow`:
    - Top-level constants (around line 30):
      ```
      SPEC_DIR="docs/context/specs"
      SPRINT_FILE="docs/context/CURRENT_SPRINT.md"
      RUNTIME_DIR=".context"
      STATE_FILE="${RUNTIME_DIR}/.pipeline-state"
      ```
      Remove the old `CONTEXT_DIR=".context/specs"` line.
    - Around line 246: rewrite `AUDIT_LOG=".context/.pipeline-audit.log"` to use `${RUNTIME_DIR}/.pipeline-audit.log` (or keep literal if simpler — flag is purely cosmetic; what matters is no agent-prompt or sprint path leaks here).
    - In `install_project_context` (line 3770): change the four `[ ! -f "$context_dir/CURRENT_SPRINT.md" ]` and `[ ! -f "$context_dir/specs/templates/feature-spec.md" ]` blocks to write to `$project_dir/docs/context/CURRENT_SPRINT.md` and `$project_dir/docs/context/specs/templates/feature-spec.md` respectively. Also `mkdir -p "$project_dir/docs/context/specs/templates"`. ARCHITECTURE/CONVENTIONS/GLOSSARY blocks STAY in `.context/`.
    - In `install_project_gitignore` (line 4012): change `entries=(".tdd-skip" ".claude/settings.local.json" ".context/.pipeline-state")` to `entries=(".tdd-skip" ".claude/settings.local.json" ".context/.pipeline-state" ".context/.pipeline-audit.log" ".context/specs/*.jsonl")`.
- **Files:** `ai-native-workflow`
- **Commit:** `feat(install): write specs and sprint to docs/context/, runtime stays in .context/`

---

### Step 3: Add a bats guard for repo-level .gitignore (RED)

- **Test:** In `tests/install.bats` (or a new short `tests/gitignore-shape.bats`), add 2 `@test`s checked against the repo's own `.gitignore`:
  - `repo .gitignore: does NOT contain bare .context/` — `! grep -E '^\.context/$' "$BATS_TEST_DIRNAME/../.gitignore"`.
  - `repo .gitignore: contains the three runtime entries` — `grep -F '.context/.pipeline-state'` etc.
  - These tests FAIL today (the bare line `.context/` is in `.gitignore`).
- **Implement:** Nothing yet — RED.
- **Files:** `tests/install.bats` (or new `tests/gitignore-shape.bats`)
- **Commit:** `test(gitignore): assert repo .gitignore splits tracked specs from runtime`

---

### Step 4: Update repo .gitignore (GREEN for Step 3)

- **Test:** Step 3's 2 tests pass. All previous bats tests still pass.
- **Implement:**
  - Replace the line `.context/` in `.gitignore` with:
    ```
    .context/.pipeline-state
    .context/.pipeline-audit.log
    .context/specs/*.jsonl
    ```
- **Files:** `.gitignore`
- **Commit:** `chore(gitignore): split tracked vs runtime artifacts under .context/`

Note: at this point the local `.context/CURRENT_SPRINT.md` and `.context/specs/BREW-1-*.md` will start showing in `git status` as untracked. That's correct — Step 7 migrates them to the tracked `docs/context/` location.

---

### Step 5: Update Claude Code agent prompts

- **Test:** No new bats tests; the agents themselves don't have automated tests. Add a manual `rg` smoke check, codified as a bats test:
  - `agents/claude-code: no spec/todo/requirements paths under .context/specs/` — `! rg -q '\.context/specs/<id>-(spec|todo|requirements|bugfix|brainstorm|testplan)' agents/claude-code/`.
  - `agents/claude-code: confidence jsonl path under .context/specs/ remains` — `rg -q '\.context/specs/.*-confidence\.jsonl' agents/claude-code/qa.md agents/claude-code/reviewer.md agents/claude-code/architect.md`.
  - `agents/claude-code: ARCHITECTURE/CONVENTIONS reads stay under .context/` — `rg -q '\.context/ARCHITECTURE\.md' agents/claude-code/architect.md`.
  - These RED first.
- **Implement:** Edit each file:
  - `agents/claude-code/architect.md`: `.context/specs/<id>-<n>.md` → `docs/context/specs/<id>-<n>.md`; `.context/specs/<id>-todo.md` → `docs/context/specs/<id>-todo.md`; `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`. KEEP `.context/specs/<id>-confidence.jsonl`, `.context/specs/<id>-spec.md` reference inside the confidence-event jq snippet → CHANGE to `docs/context/specs/<id>-spec.md`. KEEP `.context/ARCHITECTURE.md` and `.context/CONVENTIONS.md`.
  - `agents/claude-code/qa.md`: `.context/specs/<id>-spec.md` (the AC list source) → `docs/context/specs/<id>-spec.md`. KEEP `.context/specs/${SPEC_ID}-confidence.jsonl`.
  - `agents/claude-code/reviewer.md`: `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`. KEEP `.context/specs/${SPEC_ID}-confidence.jsonl`.
  - `agents/claude-code/requirements-engineer.md`: `.context/specs/<id>-requirements.md` → `docs/context/specs/<id>-requirements.md`. KEEP `.context/ARCHITECTURE.md` / `.context/CONVENTIONS.md`.
  - `agents/claude-code/troubleshooter.md`: `.context/specs/<ticket>-bugfix.md` → `docs/context/specs/<ticket>-bugfix.md`; same for `<ticket>-todo.md`.
- **Files:** `agents/claude-code/{architect,qa,reviewer,requirements-engineer,troubleshooter}.md`, `tests/install.bats` (the new bats checks).
- **Commit:** Two commits per TDD: `test(agents): assert claude-code agent prompts use docs/context/specs/`, then `docs(agents): point claude-code agents to docs/context/`.

---

### Step 6: Update Copilot CLI agent prompts

- **Test:** Mirror Step 5's bats checks for `agents/copilot-cli/`:
  - `agents/copilot-cli: no spec/todo/requirements paths under .context/specs/`
  - `agents/copilot-cli: confidence jsonl path under .context/specs/ remains`
  - These RED first.
- **Implement:** Same edits for the Copilot variants:
  - `agents/copilot-cli/architect.agent.md` (lines 6, 21, 22, 24, 37): `.context/specs/<id>-<n>.md`, `<id>-todo.md`, `<id>-spec.md` → `docs/context/specs/...`; `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`. KEEP `.context/specs/<id>-confidence.jsonl` (line 29). KEEP `.context/ARCHITECTURE.md` and `.context/CONVENTIONS.md` (line 18).
  - `agents/copilot-cli/qa.agent.md`: `.context/specs/<id>-spec.md` → `docs/context/specs/<id>-spec.md` (line 24). KEEP confidence path (line 35).
  - `agents/copilot-cli/reviewer.agent.md`: `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md` (lines 54, 68). KEEP confidence path (line 80).
  - `agents/copilot-cli/requirements-engineer.agent.md`: `.context/specs/<id>-requirements.md` → `docs/context/specs/<id>-requirements.md` (line 31). KEEP `.context/ARCHITECTURE.md` / `.context/CONVENTIONS.md` (line 29).
- **Files:** `agents/copilot-cli/{architect,qa,reviewer,requirements-engineer}.agent.md`, `tests/install.bats`.
- **Commit:** `test(agents): assert copilot-cli agent prompts use docs/context/specs/`, then `docs(agents): point copilot-cli agents to docs/context/`.

(Note: there is no `agents/copilot-cli/troubleshooter.agent.md` with `.context/specs/` references — verified via the earlier `rg` scan. If one is added later, the same pattern applies.)

---

### Step 7: Migrate in-flight BREW-1 files (doc-only, /skip-tdd)

- **Test:** None — this is a `git mv` of existing files. Existing tests must still pass.
- **Implement:**
  - Run `/skip-tdd "doc-only migration of BREW-1 spec/todo and CURRENT_SPRINT.md to docs/context/"` to permit a commit without test changes.
  - Execute:
    ```
    mkdir -p docs/context/specs
    git mv .context/CURRENT_SPRINT.md docs/context/CURRENT_SPRINT.md
    git mv .context/specs/BREW-1-anw-script-dir-symlink.md docs/context/specs/BREW-1-anw-script-dir-symlink.md
    git mv .context/specs/BREW-1-todo.md docs/context/specs/BREW-1-todo.md
    ```
  - Verify with `git status` that the moves are recorded, and the `.context/` directory now contains only ARCHITECTURE/CONVENTIONS/GLOSSARY.md (and `specs/` empty).
  - Inside the moved `docs/context/specs/BREW-1-anw-script-dir-symlink.md` and `docs/context/specs/BREW-1-todo.md`, find/replace any internal references:
    - `Spec: .context/specs/BREW-1-...` → `Spec: docs/context/specs/BREW-1-...`
    - `Todo: .context/specs/BREW-1-todo.md` → `Todo: docs/context/specs/BREW-1-todo.md`
  - Same in the moved `docs/context/CURRENT_SPRINT.md` (the In Progress block lists those paths — confirmed in CURRENT_SPRINT.md lines 6-7 today).
- **Files:** `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`; `.context/specs/BREW-1-anw-script-dir-symlink.md` → `docs/context/specs/BREW-1-anw-script-dir-symlink.md`; `.context/specs/BREW-1-todo.md` → `docs/context/specs/BREW-1-todo.md`.
- **Commit:** `docs(context): migrate sprint board and BREW-1 spec to docs/context/` (with `/skip-tdd` marker file in the commit).

---

### Step 8: Update embedded heredocs in ai-native-workflow

- **Test:** Add a bats check `cli: ai-native-workflow heredocs use docs/context/ for spec/sprint paths`:
  - `! rg -q '\.context/specs/(<id>|\\$\\{?SPEC_ID\\}?)-(spec|todo|requirements|bugfix|brainstorm|testplan)\.md' ai-native-workflow`
  - `! rg -q '\.context/CURRENT_SPRINT\.md' ai-native-workflow` — *but* allow it inside the embedded `session-start.sh` heredoc only if the source `hooks/session-start.sh` was already updated. To keep things simple: assert ZERO occurrences of `.context/CURRENT_SPRINT` after this step.
  - These RED first because lines 1979, 2191, 2204, 2293, 2463, 2473, 2707, 2713, 2769, 2774, 2779, 2798, 3075-3076, 3197, 3199, 3226, 3238, 3241-3244, 3635, 3670, 3675-3677, 3713, 3740, 3743, 3746, 3762, 3890-3892 still reference old paths.
- **Implement:** Update every embedded heredoc in `ai-native-workflow` that mirrors an agent prompt, skill, or installed file. Concretely:
  - The session-start hook heredoc (~line 1979) — change to `docs/context/CURRENT_SPRINT.md`.
  - The `architect`, `qa`, `reviewer`, `requirements-engineer`, `troubleshooter`, `brainstorm` heredoc bodies (lines ~2191-2204, 2293, 2463-2473, 2707-2713, 2769-2798, 3075-3076, 3197-3244) — same find/replace as Steps 5/6.
  - The `install_project_agents_md` AGENTS.md heredoc (lines ~3635, 3670, 3675-3677, 3713) — change `.context/CURRENT_SPRINT.md` and `.context/specs/` (when followed by spec/todo/requirements text) to `docs/context/...`. KEEP `.context/ARCHITECTURE.md` and `.context/CONVENTIONS.md` reads on lines 3676-3677.
  - The `install_project_claude_md` CLAUDE.md heredoc (lines ~3740-3762): "Read `.context/CURRENT_SPRINT.md` for active tasks" → `docs/context/CURRENT_SPRINT.md`; "Feature specifications are in `.context/specs/`" → `docs/context/specs/`; the `.context/` row in the Key Paths table updates to clarify "Architecture, conventions, glossary, runtime state" while a new `docs/context/` row says "Sprint board + tracked specs". KEEP the `.context/ARCHITECTURE.md` line.
  - The `install_project_copilot` copilot-instructions.md heredoc (lines ~3890-3892): "Check `.context/specs/` for feature specifications" → "Check `docs/context/specs/` for feature specifications". KEEP `.context/ARCHITECTURE.md` and `.context/CONVENTIONS.md` lines.
  - The help text and "what gets installed" tables (around lines 4280, 4370): the per-project section gets a new `docs/context/` entry.
- **Files:** `ai-native-workflow`, `tests/install.bats`.
- **Commit:** Two: `test(cli): assert ai-native-workflow heredocs use docs/context/`, then `docs(cli): align embedded heredocs with docs/context/ split`.

---

### Step 9: Update hooks/session-start.sh

- **Test:** Add a bats `@test` `hooks: session-start reads sprint from docs/context/CURRENT_SPRINT.md`:
  - Create a tempdir `PROJECT_DIR` with `docs/context/CURRENT_SPRINT.md` containing a known string. Run `bash hooks/session-start.sh` with `CLAUDE_PROJECT_DIR="$PROJECT_DIR"`. Assert the known string appears in stdout.
  - And the negative: with only `.context/CURRENT_SPRINT.md` present, the known string should NOT appear (we've intentionally hard-cut).
  - RED first.
- **Implement:** In `hooks/session-start.sh` (lines 40-41), change `$PROJECT_DIR/.context/CURRENT_SPRINT.md` to `$PROJECT_DIR/docs/context/CURRENT_SPRINT.md`.
  - Note: the embedded copy in `ai-native-workflow` (~line 1979) is updated in Step 8; this step only touches the source file. Confirm both already match after Step 8 — if not, fix here.
- **Files:** `hooks/session-start.sh`, `tests/install.bats` (or a new `tests/session-start-hook.bats`).
- **Commit:** `test(hooks): assert session-start.sh reads sprint from docs/context/`, then `feat(hooks): point session-start.sh sprint read to docs/context/CURRENT_SPRINT.md`.

---

### Step 10: Update templates/AGENTS.md and skills

- **Test:** Add a bats `@test` `docs: templates/AGENTS.md and skills/ reference docs/context/ for sprint and specs`:
  - `! rg -q '\.context/CURRENT_SPRINT\.md|\.context/specs/[^c]' templates/AGENTS.md skills/` — except the line `Read .context/ARCHITECTURE.md` and `.context/CONVENTIONS.md` are allowed (those don't move). Use a pattern that excludes those (`rg -v` or two narrower patterns).
  - Practical assertion: `! rg -q '\.context/CURRENT_SPRINT\.md' templates/AGENTS.md skills/` AND `! rg -q '\.context/specs/<.*>(-spec|-todo|-requirements|-bugfix|-brainstorm|-testplan)?\.md' templates/AGENTS.md skills/`.
  - RED first.
- **Implement:**
  - `templates/AGENTS.md`: lines 29, 64, 69, 71 (KEEP), 72 (KEEP), 108 — replace `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md` and `.context/specs/` (when about specs) → `docs/context/specs/`. Lines 70-71 (`.context/ARCHITECTURE.md`, `.context/CONVENTIONS.md`) STAY.
  - `skills/ticket/SKILL.md`: line 37 `.context/specs/<ticket-id>-...md` → `docs/context/specs/...`; line 50 `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`.
  - `skills/session-report/SKILL.md`: line 33 `.context/CURRENT_SPRINT.md` → `docs/context/CURRENT_SPRINT.md`.
  - `skills/brainstorm/SKILL.md`: lines 24, 34 `.context/specs/<id>-brainstorm.md` → `docs/context/specs/<id>-brainstorm.md`.
  - `skills/pipeline-gitlab-feature/SKILL.md`, `skills/pipeline-github-feature/SKILL.md`, `skills/pipeline-gitlab-incident/SKILL.md`: every `.context/specs/<id>-...md` referenced as spec/todo/requirements/testplan/bugfix → `docs/context/specs/...`.
  - `skills/adr/SKILL.md`: line 27 `.context/ARCHITECTURE.md` STAYS unchanged (per-project doc).
- **Files:** `templates/AGENTS.md`, `skills/ticket/SKILL.md`, `skills/session-report/SKILL.md`, `skills/brainstorm/SKILL.md`, `skills/pipeline-gitlab-feature/SKILL.md`, `skills/pipeline-github-feature/SKILL.md`, `skills/pipeline-gitlab-incident/SKILL.md`, `tests/install.bats`.
- **Commit:** `test(docs): assert AGENTS template and skills reference docs/context/`, then `docs(skills): align AGENTS template and skills with docs/context/ split`.

---

### Step 11: Update README.md and docs/ARCHITECTURE.md

- **Test:** Add a bats `@test` `docs: README and ARCHITECTURE list docs/context/ for tracked specs`:
  - `rg -q 'docs/context/' README.md docs/ARCHITECTURE.md` (positive — must mention).
  - `! rg -q '\.context/specs/<id>-(requirements|spec|todo|bugfix|testplan|brainstorm)\.md' README.md docs/ARCHITECTURE.md` (negative — old paths gone).
  - The `.context/specs/<id>-confidence.jsonl` references in README.md (lines 220, 255) STAY — they're describing a runtime path.
  - RED first.
- **Implement:**
  - `docs/ARCHITECTURE.md`: lines 45, 114 — `.context/specs/<id>-requirements.md` → `docs/context/specs/<id>-requirements.md`. Add a one-paragraph "Path conventions" section near "Key Design Decisions" (line 185) explaining the split: tracked specs in `docs/context/`, runtime in `.context/`.
  - `README.md`: line 143 — split the `.context/` row in the per-project install table into two: `docs/context/` (Sprint, specs, todos, requirements) and `.context/` (Architecture/conventions/glossary + runtime state). Lines 220 and 255 stay (confidence jsonl path).
- **Files:** `README.md`, `docs/ARCHITECTURE.md`, `tests/install.bats`.
- **Commit:** `test(docs): assert README and ARCHITECTURE describe docs/context/ split`, then `docs: document context split in README and ARCHITECTURE`.

---

### Step 12: Integration smoke test

- **Test:** Add an integration-style bats test (or a single shell script invoked from a bats `@test`) that:
  - Spins a tempdir as a fake project (no git init needed for this — just file presence checks).
  - Runs `CLAUDE_HOME="$SANDBOX_CLAUDE" "$AW" install global` AND `"$AW" install project "$SANDBOX_PROJECT"`.
  - Asserts:
    - `[ -f "$SANDBOX_PROJECT/docs/context/CURRENT_SPRINT.md" ]`
    - `[ -f "$SANDBOX_PROJECT/docs/context/specs/templates/feature-spec.md" ]`
    - `[ -f "$SANDBOX_PROJECT/.context/ARCHITECTURE.md" ]` (still installed there)
    - `grep -F '.context/.pipeline-state' "$SANDBOX_PROJECT/.gitignore"`
    - `! grep -E '^\.context/$' "$SANDBOX_PROJECT/.gitignore"`
    - `[ -f "$SANDBOX_CLAUDE/agents/architect.md" ]` AND `! grep -E '\.context/specs/<id>-(spec|todo|requirements)' "$SANDBOX_CLAUDE/agents/architect.md"`.
  - This is the AC-15 promise — one fresh install proves the new layout is wired end-to-end.
- **Implement:** No new code — just the test. By this step, all previous changes should make this test green.
- **Files:** `tests/install.bats` (new section at the bottom).
- **Commit:** `test(install): integration smoke — install project lands tracked specs at docs/context/`.

---

### Step 13: Final smoke pass + run all tests

- **Test:** Run the full bats suite: `bats tests/`. All tests pass (105 existing + ~12 new from Steps 1, 3, 5, 6, 8, 9, 10, 11, 12).
- **Implement:** Audit `rg` pass to catch any stragglers:
  ```
  rg -n '\.context/specs/[^/]*-(spec|todo|requirements|bugfix|testplan|brainstorm)\.md' \
    --glob '!spikes/**' --glob '!.git/**' --glob '!.context/**' --glob '!docs/context/**'
  rg -n '\.context/CURRENT_SPRINT\.md' \
    --glob '!spikes/**' --glob '!.git/**' --glob '!.context/**' --glob '!docs/context/**'
  ```
  Both should return zero matches. Fix any stragglers in this same step.
  - Update `.context/CURRENT_SPRINT.md` (now at `docs/context/CURRENT_SPRINT.md`) to mark CTX-1 as Done.
- **Files:** Whatever the final audit catches (likely nothing if Steps 1–12 were thorough); `docs/context/CURRENT_SPRINT.md`.
- **Commit:** `chore(context): mark CTX-1 done` (or fold into an earlier commit if no source files changed).

---

## Status checklist

- [x] Step 1 — RED: bats tests for new install layout
- [x] Step 2 — GREEN: installer writes new layout
- [x] Step 3 — RED: bats guard for repo .gitignore
- [x] Step 4 — GREEN: repo .gitignore updated
- [x] Step 5 — Claude Code agent prompts updated (test + impl)
- [x] Step 6 — Copilot CLI agent prompts updated (test + impl)
- [x] Step 7 — In-flight BREW-1 files migrated (`/skip-tdd`)
- [x] Step 8 — `ai-native-workflow` heredocs updated (test + impl)
- [ ] Step 9 — `hooks/session-start.sh` updated (test + impl)
- [ ] Step 10 — `templates/AGENTS.md` + skills updated (test + impl)
- [x] Step 11 — README + ARCHITECTURE updated (test + impl)
- [x] Step 12 — Integration smoke test
- [x] Step 13 — Final audit pass + sprint board mark Done

## Done definition

All 17 ACs from `CTX-1-spec.md` verified, all bats tests pass, the BREW-1 spec is now reviewable in `docs/context/specs/`, and a fresh `ai-native-workflow install project` into a sandbox produces the new layout. Branch `feat/context-split` ready to PR.
