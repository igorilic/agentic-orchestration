# Confidence Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic confidence verdict (GREEN / YELLOW / RED + 0–100 score) to the `tdd-developer → qa → reviewer` pipeline, enforced as a hook on PR/MR creation.

**Architecture:** Each agent appends events to a per-spec append-only log at `.context/specs/<id>-confidence.jsonl`. A pure shell script (`scripts/confidence.sh`) computes the verdict from the log. A `PreToolUse` hook (`hooks/confidence-gate.sh`) blocks `gh pr create` / `glab mr create` on RED unless an override marker is present. `/skip-tdd` auto-bypasses structural gates (NO_AC, AC_NOT_TESTED) only.

**Tech Stack:** bash 4+, `jq`, `bats-core` (for tests). No new runtime dependencies beyond what the repo already requires.

**Spec:** [`docs/superpowers/specs/2026-05-02-confidence-gate-design.md`](../specs/2026-05-02-confidence-gate-design.md)

---

## File Structure

### New files
| File | Responsibility |
|---|---|
| `scripts/confidence.sh` | Pure scorer: read jsonl log, compute hard gates + scored penalties, emit JSON verdict. |
| `hooks/confidence-gate.sh` | PreToolUse hook on `Bash` matching `gh pr create*` / `glab mr create*`; runs scorer, exits 2 on RED unless override resolves. |
| `skills/override-confidence/SKILL.md` | `/override-confidence "<reason>"` skill — writes one-shot bypass marker to `.git/aw/`. |
| `tests/confidence.bats` | Unit tests for `scripts/confidence.sh`. |
| `tests/confidence-gate-hook.bats` | Integration tests for `hooks/confidence-gate.sh`. |
| `tests/fixtures/confidence/*.jsonl` | Hand-crafted event log fixtures. |
| `tests/lib/confidence-helpers.bash` | Bats helper functions (build temp logs, mock skip-tdd marker, etc.). |

### Modified files
| File | Change |
|---|---|
| `agents/claude-code/architect.md` | Add §6: emit `spec` event after writing spec. |
| `agents/copilot-cli/architect.agent.md` | Same. |
| `agents/claude-code/qa.md` | Add §5: emit `qa` event after running tests. |
| `agents/copilot-cli/qa.agent.md` | Same. |
| `agents/claude-code/reviewer.md` | Add §7: emit `review` event after final loop. |
| `agents/copilot-cli/reviewer.agent.md` | Same. |
| `ai-native-workflow` | (a) Write `.git/aw/active-spec` at run start. (b) Invoke scorer per step. (c) Inject `## Confidence` PR body section. |
| `config/settings.json` | Register `hooks/confidence-gate.sh` as PreToolUse on Bash. |
| `README.md` | New section "Confidence Gate". |
| `docs/ARCHITECTURE.md` | Update pipeline diagrams. |

### Existing references (not modified, but read by the implementation)
- `.tdd-skip` — file written by `skills/skip-tdd/SKILL.md`. The hook reads this to detect skip-tdd is active.
- `hooks/tdd-gate.sh` — model the hook structure on this file.

---

## Task 1: Bootstrap test infrastructure

**Files:**
- Create: `tests/lib/confidence-helpers.bash`
- Create: `tests/sanity.bats`
- Modify: `README.md` (Requirements section adds bats-core)

**Background for the engineer:** `bats-core` is bash's test runner — installs via `brew install bats-core` on macOS. We use it because the repo is shell-based and we need a real assertion framework, not raw `if` statements. Helper file pattern: a sourced bash file with functions, by convention under `tests/lib/`.

- [ ] **Step 1: Verify bats-core is available**

Run: `which bats || brew install bats-core`
Expected: `bats` resolves on PATH and `bats --version` prints `Bats 1.x.x`.

- [ ] **Step 2: Create `tests/lib/confidence-helpers.bash`**

```bash
#!/usr/bin/env bash
# Helpers for confidence-gate tests.

# make_log <path> <events...>
# Each event arg is a JSON string written as one line.
make_log() {
  local path="$1"; shift
  : > "$path"
  for evt in "$@"; do
    printf '%s\n' "$evt" >> "$path"
  done
}

# Standard event builders. ts is fixed for deterministic tests.
spec_event() {
  local ac_json="${1:-[]}"
  printf '{"ts":"2026-05-02T18:00:00Z","event":"spec","spec_path":"x","ac_items":%s}' "$ac_json"
}

qa_event() {
  local step="$1" passed="$2" failed="$3" build="${4:-ok}" tested="${5:-[]}"
  printf '{"ts":"2026-05-02T18:00:01Z","event":"qa","step":%s,"tests_passed":%s,"tests_failed":%s,"build_status":"%s","ac_items_tested":%s}' \
    "$step" "$passed" "$failed" "$build" "$tested"
}

review_event() {
  local step="$1" must="${2:-0}" should="${3:-0}" sugg="${4:-0}" loops="${5:-1}" td="${6:-0}" diff="${7:-100}"
  local must_arr should_arr sugg_arr td_arr
  must_arr=$(  [ "$must"   -eq 0 ] && echo '[]' || seq 1 "$must"   | jq -Rcn '[inputs | {file:"f.go",line:1,msg:"x"}]')
  should_arr=$([ "$should" -eq 0 ] && echo '[]' || seq 1 "$should" | jq -Rcn '[inputs | {file:"f.go",line:1,msg:"x"}]')
  sugg_arr=$(  [ "$sugg"   -eq 0 ] && echo '[]' || seq 1 "$sugg"   | jq -Rcn '[inputs | {file:"f.go",line:1,msg:"x"}]')
  td_arr=$(    [ "$td"     -eq 0 ] && echo '[]' || seq 1 "$td"     | jq -Rcn '[inputs | {item:"x"}]')
  printf '{"ts":"2026-05-02T18:00:02Z","event":"review","step":%s,"must_fix":%s,"should_fix":%s,"suggestion":%s,"loops_used":%s,"tech_debt_deferrals":%s,"diff_lines":%s}' \
    "$step" "$must_arr" "$should_arr" "$sugg_arr" "$loops" "$td_arr" "$diff"
}
```

- [ ] **Step 3: Create `tests/sanity.bats`**

```bash
#!/usr/bin/env bats

load 'lib/confidence-helpers'

@test "helpers: make_log writes one event per line" {
  tmp="$(mktemp)"
  make_log "$tmp" "$(spec_event '[]')"
  run wc -l < "$tmp"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "helpers: spec_event with one AC produces valid JSON" {
  evt="$(spec_event '[{"id":"AC-1","text":"x"}]')"
  echo "$evt" | jq -e '.ac_items[0].id == "AC-1"'
}
```

- [ ] **Step 4: Run sanity tests**

Run: `bats tests/sanity.bats`
Expected: 2 tests pass.

- [ ] **Step 5: Update README requirements**

In `README.md`, in the Requirements section, add:
```markdown
- `bats-core` (development only — `brew install bats-core` on macOS, `npm i -g bats` elsewhere)
```

- [ ] **Step 6: Commit**

```bash
git add tests/ README.md
git commit -m "test: bootstrap bats-core test infrastructure for confidence gate"
```

---

## Task 2: confidence.sh — skeleton, happy path, JSON output

**Files:**
- Create: `scripts/confidence.sh`
- Create: `tests/fixtures/confidence/all-green.jsonl`
- Modify: `tests/confidence.bats` (new file)

**Background:** The script reads a jsonl log path as `$1` and emits a single line of JSON to stdout. Keep functions small. `set -euo pipefail` at top. Use `jq -s` (slurp) to read the log as an array of events.

- [ ] **Step 1: Write the failing test**

Create `tests/confidence.bats`:
```bash
#!/usr/bin/env bats

load 'lib/confidence-helpers'

setup() {
  TMPLOG="$(mktemp)"
}

teardown() {
  rm -f "$TMPLOG"
}

@test "all-green log: score 100, band GREEN, no gates" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.score == 100'
  echo "$output" | jq -e '.band == "GREEN"'
  echo "$output" | jq -e '.gates == []'
}

@test "output JSON has all required fields" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e 'has("score") and has("band") and has("gates") and has("penalties") and has("verdict_text")'
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/confidence.bats`
Expected: FAIL — `scripts/confidence.sh: No such file or directory`.

- [ ] **Step 3: Implement minimal `scripts/confidence.sh`**

```bash
#!/usr/bin/env bash
# Computes a deterministic confidence verdict from an event log.
# Usage: scripts/confidence.sh <log-path> [--scope=aggregate|step] [--step=N]
set -euo pipefail

LOG="${1:?usage: confidence.sh <log-path> [--scope=...] [--step=N]}"
SCOPE="aggregate"
STEP=""
shift || true
for arg in "$@"; do
  case "$arg" in
    --scope=*) SCOPE="${arg#--scope=}" ;;
    --step=*)  STEP="${arg#--step=}" ;;
  esac
done

[ -f "$LOG" ] || { echo "log not found: $LOG" >&2; exit 1; }

# Slurp into an array. Strip irrelevant events for scope=step.
events="$(jq -s '.' "$LOG")"
if [ "$SCOPE" = "step" ] && [ -n "$STEP" ]; then
  events="$(jq --argjson s "$STEP" '[.[] | select((.step // 0) == $s or .event == "spec")]' <<<"$events")"
fi

score=100
gates=()
penalties_should_fix=0
penalties_loops=0
penalties_tech_debt=0
penalties_ac_coverage=0
penalties_diff=0
penalties_suggestion=0

# (Hard gates and scored penalties added in subsequent tasks.)

# Determine band.
if [ "${#gates[@]}" -gt 0 ]; then
  band="RED"
elif [ "$score" -ge 80 ]; then
  band="GREEN"
elif [ "$score" -ge 60 ]; then
  band="YELLOW"
else
  band="RED"
fi

verdict_text="$band: ${score}/100"

jq -n \
  --arg band "$band" \
  --argjson score "$score" \
  --argjson gates "$(printf '%s\n' "${gates[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson penalties "$(jq -n \
      --argjson should_fix "$penalties_should_fix" \
      --argjson suggestion "$penalties_suggestion" \
      --argjson loops "$penalties_loops" \
      --argjson tech_debt "$penalties_tech_debt" \
      --argjson ac_coverage "$penalties_ac_coverage" \
      --argjson diff "$penalties_diff" \
      '{should_fix:$should_fix, suggestion:$suggestion, loops:$loops, tech_debt:$tech_debt, ac_coverage:$ac_coverage, diff:$diff}')" \
  --arg verdict_text "$verdict_text" \
  '{band:$band, score:$score, gates:$gates, penalties:$penalties, verdict_text:$verdict_text}'
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x scripts/confidence.sh
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/confidence.bats`
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/confidence.sh tests/confidence.bats
git commit -m "feat(confidence): scaffold scorer with all-green happy path"
```

---

## Task 3: confidence.sh — hard gates

**Files:**
- Modify: `scripts/confidence.sh`
- Modify: `tests/confidence.bats`

**Background:** Six gates. Each one, when triggered, appends a string to the `gates` array. Order they appear in the array doesn't matter for behavior but use a deterministic order for test stability: `NO_AC`, `TEST_FAILED`, `BUILD_BROKEN`, `MUST_FIX`, `AC_NOT_TESTED`, `TDD_BYPASSED_NO_REASON`. Implement them in that order.

### 3a — NO_AC

- [ ] **Step 1: Write failing test**

Append to `tests/confidence.bats`:
```bash
@test "NO_AC: missing spec event triggers RED" {
  make_log "$TMPLOG" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.band == "RED"'
  echo "$output" | jq -e '.gates | index("NO_AC") != null'
}

@test "NO_AC: empty ac_items array triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("NO_AC") != null'
}
```

- [ ] **Step 2: Run, verify failure**

Run: `bats tests/confidence.bats`
Expected: 2 new tests fail (band is GREEN with no gates).

- [ ] **Step 3: Implement gate**

In `scripts/confidence.sh`, after the `events="$(jq -s ...)"` block and before the band check, add:
```bash
ac_count="$(jq '[.[] | select(.event=="spec")] | (.[0].ac_items // []) | length' <<<"$events")"
[ "$ac_count" -gt 0 ] || gates+=("NO_AC")
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bats tests/confidence.bats`
Expected: all tests pass.

### 3b — TEST_FAILED

- [ ] **Step 5: Failing test**

```bash
@test "TEST_FAILED: any qa event with tests_failed > 0 triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 3 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("TEST_FAILED") != null'
}
```

- [ ] **Step 6: Run, verify failure**

Run: `bats tests/confidence.bats`

- [ ] **Step 7: Implement**

After the NO_AC check:
```bash
failed_total="$(jq '[.[] | select(.event=="qa") | .tests_failed] | add // 0' <<<"$events")"
[ "$failed_total" -eq 0 ] || gates+=("TEST_FAILED")
```

- [ ] **Step 8: Run, verify pass**

### 3c — BUILD_BROKEN

- [ ] **Step 9: Failing test**

```bash
@test "BUILD_BROKEN: qa event with build_status != ok triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 broken '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("BUILD_BROKEN") != null'
}
```

- [ ] **Step 10: Run, verify failure**

- [ ] **Step 11: Implement**

```bash
broken="$(jq '[.[] | select(.event=="qa" and .build_status != "ok")] | length' <<<"$events")"
[ "$broken" -eq 0 ] || gates+=("BUILD_BROKEN")
```

- [ ] **Step 12: Run, verify pass**

### 3d — MUST_FIX

- [ ] **Step 13: Failing test**

```bash
@test "MUST_FIX: any review with non-empty must_fix triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("MUST_FIX") != null'
}
```

- [ ] **Step 14: Run, verify failure**

- [ ] **Step 15: Implement**

```bash
must_fix_total="$(jq '[.[] | select(.event=="review") | .must_fix | length] | add // 0' <<<"$events")"
[ "$must_fix_total" -eq 0 ] || gates+=("MUST_FIX")
```

- [ ] **Step 16: Run, verify pass**

### 3e — AC_NOT_TESTED

- [ ] **Step 17: Failing test**

```bash
@test "AC_NOT_TESTED: AC-2 in spec but not in any ac_items_tested triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("AC_NOT_TESTED") != null'
}
```

- [ ] **Step 18: Run, verify failure**

- [ ] **Step 19: Implement**

```bash
spec_acs="$(jq '[.[] | select(.event=="spec")][0].ac_items // [] | map(.id)' <<<"$events")"
tested_acs="$(jq '[.[] | select(.event=="qa") | .ac_items_tested[]] | unique' <<<"$events")"
missing_acs="$(jq -n --argjson s "$spec_acs" --argjson t "$tested_acs" '$s - $t')"
missing_count="$(jq 'length' <<<"$missing_acs")"
[ "$missing_count" -eq 0 ] || gates+=("AC_NOT_TESTED")
```

- [ ] **Step 20: Run, verify pass**

### 3f — TDD_BYPASSED_NO_REASON

- [ ] **Step 21: Failing test**

```bash
@test "TDD_BYPASSED_NO_REASON: explicit event in log triggers RED" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)" \
    '{"ts":"2026-05-02T18:00:03Z","event":"tdd_bypassed","reason":""}'

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.gates | index("TDD_BYPASSED_NO_REASON") != null'
}
```

**Note for engineer:** The `tdd_bypassed` event is emitted by the CLI driver (Task 12) when a commit lands without test files AND no `.tdd-skip` was active. The reason is empty in that case.

- [ ] **Step 22: Run, verify failure**

- [ ] **Step 23: Implement**

```bash
bypass_no_reason="$(jq '[.[] | select(.event=="tdd_bypassed" and ((.reason // "") == ""))] | length' <<<"$events")"
[ "$bypass_no_reason" -eq 0 ] || gates+=("TDD_BYPASSED_NO_REASON")
```

- [ ] **Step 24: Run, verify pass**

- [ ] **Step 25: Commit**

```bash
git add scripts/confidence.sh tests/confidence.bats
git commit -m "feat(confidence): implement six hard gates with full test coverage"
```

---

## Task 4: confidence.sh — scored penalties

**Files:**
- Modify: `scripts/confidence.sh`
- Modify: `tests/confidence.bats`

**Penalty rubric (recap from spec):**
- `should_fix`: −5 each
- `suggestion`: −1 each
- `loops_used >= 2`: −5 (per step that used 2+ loops)
- `loops_used >= 3`: −10 additional (so a step with 3 loops = −15 cumulative)
- `tech_debt_deferrals`: −3 each
- AC coverage missing: −2 each, capped at −20
- `diff_lines` > 1000: −15; else if > 400: −5

Penalties are accumulated in `penalties_*` variables and subtracted from `score`. Update the JSON output to surface them.

- [ ] **Step 1: Failing tests for all penalties**

```bash
@test "penalty: should_fix is -5 each" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 2 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 90'
  echo "$output" | jq -e '.penalties.should_fix == -10'
}

@test "penalty: suggestion is -1 each" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 3 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 97'
}

@test "penalty: loops_used 2 is -5, loops_used 3 is -15 cumulative" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 5 0 ok '["AC-2"]')" \
    "$(review_event 1 0 0 0 2 0 100)" \
    "$(review_event 2 0 0 0 3 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 80'
  echo "$output" | jq -e '.penalties.loops == -20'
}

@test "penalty: tech_debt_deferrals is -3 each" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 2 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 94'
}

@test "penalty: diff > 400 lines is -5" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 500)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 95'
  echo "$output" | jq -e '.penalties.diff == -5'
}

@test "penalty: diff > 1000 lines is -15 (replaces -5)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 1500)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 85'
  echo "$output" | jq -e '.penalties.diff == -15'
}

@test "score floor is 0, never negative" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 30 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 0'
}
```

- [ ] **Step 2: Run, verify failures**

Run: `bats tests/confidence.bats`
Expected: 7 new failures, all with `.score == 100` (penalties not yet applied).

- [ ] **Step 3: Implement penalties**

In `scripts/confidence.sh`, replace the placeholder comment `# (Hard gates and scored penalties added in subsequent tasks.)` with the gate implementations from Task 3, followed by:
```bash
# --- Scored penalties ---
should_fix_count="$(jq '[.[] | select(.event=="review") | .should_fix | length] | add // 0' <<<"$events")"
penalties_should_fix=$(( -5 * should_fix_count ))

suggestion_count="$(jq '[.[] | select(.event=="review") | .suggestion | length] | add // 0' <<<"$events")"
penalties_suggestion=$(( -1 * suggestion_count ))

loops2="$(jq '[.[] | select(.event=="review" and .loops_used >= 2)] | length' <<<"$events")"
loops3="$(jq '[.[] | select(.event=="review" and .loops_used >= 3)] | length' <<<"$events")"
penalties_loops=$(( -5 * loops2 + -10 * loops3 ))

td_count="$(jq '[.[] | select(.event=="review") | .tech_debt_deferrals | length] | add // 0' <<<"$events")"
penalties_tech_debt=$(( -3 * td_count ))

# AC coverage penalty (the gate already handles 100% missing; this scores partial misses).
penalties_ac_coverage=$(( -2 * missing_count ))
[ "$penalties_ac_coverage" -lt -20 ] && penalties_ac_coverage=-20

total_diff="$(jq '[.[] | select(.event=="review") | .diff_lines] | add // 0' <<<"$events")"
if [ "$total_diff" -gt 1000 ]; then
  penalties_diff=-15
elif [ "$total_diff" -gt 400 ]; then
  penalties_diff=-5
fi

score=$(( score + penalties_should_fix + penalties_suggestion + penalties_loops + penalties_tech_debt + penalties_ac_coverage + penalties_diff ))
[ "$score" -lt 0 ] && score=0
```

**Note on AC_NOT_TESTED + ac_coverage interaction:** the gate fires whenever ANY AC is untested. The penalty also reduces score, but since the gate forces RED, the penalty is moot in those cases. Keep both for cases where the user overrides the gate — at least the score reflects the actual coverage.

- [ ] **Step 4: Run tests, verify all pass**

Run: `bats tests/confidence.bats`
Expected: all tests pass (existing + 7 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/confidence.sh tests/confidence.bats
git commit -m "feat(confidence): implement scored penalties and score floor"
```

---

## Task 5: confidence.sh — band thresholds

**Files:**
- Modify: `tests/confidence.bats`

**Background:** The band logic is already implemented (Task 2's skeleton). This task adds explicit boundary tests so future regressions surface immediately.

- [ ] **Step 1: Failing tests for boundaries**

```bash
@test "band: score 80 is GREEN (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 4 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 80'
  echo "$output" | jq -e '.band == "GREEN"'
}

@test "band: score 79 is YELLOW (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 4 1 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 79'
  echo "$output" | jq -e '.band == "YELLOW"'
}

@test "band: score 60 is YELLOW (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 60'
  echo "$output" | jq -e '.band == "YELLOW"'
}

@test "band: score 59 is RED (boundary)" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 1 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  echo "$output" | jq -e '.score == 59'
  echo "$output" | jq -e '.band == "RED"'
}

@test "band: any hard gate forces RED regardless of score" {
  make_log "$TMPLOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  # score before gate would be 100, but NO_AC fires
  echo "$output" | jq -e '.band == "RED"'
}
```

- [ ] **Step 2: Run tests**

Run: `bats tests/confidence.bats`
Expected: all pass (band logic was already correct — this is regression coverage).

- [ ] **Step 3: Commit**

```bash
git add tests/confidence.bats
git commit -m "test(confidence): add boundary tests for band thresholds"
```

---

## Task 6: confidence.sh — per-step scoping

**Files:**
- Modify: `tests/confidence.bats`

**Background:** Task 2's skeleton already includes the `--scope=step --step=N` filter logic. This task validates it.

- [ ] **Step 1: Failing tests**

```bash
@test "scope=step: only events for that step are considered" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 5 0 ok '["AC-2"]')" \
    "$(review_event 1 0 0 0 1 0 100)" \
    "$(review_event 2 0 4 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=1
  echo "$output" | jq -e '.score == 100'

  run scripts/confidence.sh "$TMPLOG" --scope=step --step=2
  echo "$output" | jq -e '.score == 80'
}

@test "scope=aggregate (default): all events considered" {
  make_log "$TMPLOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"},{"id":"AC-2","text":"y"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(qa_event 2 5 0 ok '["AC-2"]')" \
    "$(review_event 1 0 2 0 1 0 100)" \
    "$(review_event 2 0 2 0 1 0 100)"

  run scripts/confidence.sh "$TMPLOG"
  # 4 should-fix total = -20 = score 80
  echo "$output" | jq -e '.score == 80'
}
```

- [ ] **Step 2: Run, verify pass**

Run: `bats tests/confidence.bats`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add tests/confidence.bats
git commit -m "test(confidence): verify per-step scope filtering"
```

---

## Task 7: hooks/confidence-gate.sh — basic enforcement

**Files:**
- Create: `hooks/confidence-gate.sh`
- Create: `tests/confidence-gate-hook.bats`

**Background:** This hook is invoked by Claude Code's PreToolUse mechanism. It receives `CLAUDE_TOOL_INPUT` containing the proposed bash command. Pattern lifted from `hooks/tdd-gate.sh`. The hook needs:
1. Filter: only fire on `gh pr create` or `glab mr create` commands.
2. Resolve spec id from `.git/aw/active-spec`.
3. Run `scripts/confidence.sh` to get verdict.
4. Append `verdict` event with scope=aggregate to log.
5. Apply gate logic (GREEN/YELLOW: exit 0; RED: check overrides → exit 0 or 2).

We tackle (1)–(4) here; overrides come in Tasks 9–10.

- [ ] **Step 1: Failing test**

Create `tests/confidence-gate-hook.bats`:
```bash
#!/usr/bin/env bats

load 'lib/confidence-helpers'

setup() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR"
  git init -q
  mkdir -p .git/aw .context/specs
  echo "PROJ-1" > .git/aw/active-spec
  LOG=".context/specs/PROJ-1-confidence.jsonl"
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

# Helper: run hook with a given proposed command.
run_hook() {
  CLAUDE_PROJECT_DIR="$TESTDIR" \
  CLAUDE_TOOL_INPUT="$1" \
    bash "$BATS_TEST_DIRNAME/../hooks/confidence-gate.sh"
}

@test "non-PR commands pass through (exit 0)" {
  make_log "$LOG" "$(spec_event '[]')"
  run run_hook "git status"
  [ "$status" -eq 0 ]
}

@test "GREEN aggregate: gh pr create proceeds (exit 0)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "gh pr create --title x --body y"
  [ "$status" -eq 0 ]
}

@test "RED aggregate: gh pr create blocked (exit 2)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "gh pr create --title x --body y"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RED"* ]]
  [[ "$output" == *"TEST_FAILED"* ]]
}

@test "RED aggregate: glab mr create blocked (exit 2)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "glab mr create --title x"
  [ "$status" -eq 2 ]
}

@test "YELLOW aggregate: pr create proceeds with warning (exit 0)" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 8 0 1 0 100)"
  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YELLOW"* ]]
}

@test "missing active-spec pointer: exit 2 with clear error" {
  rm .git/aw/active-spec
  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [[ "$output" == *"active-spec"* ]]
}

@test "verdict event appended to log on every gate fire" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  run jq -s '[.[] | select(.event=="verdict" and .scope=="aggregate")] | length' "$LOG"
  [ "$output" = "1" ]
}
```

- [ ] **Step 2: Run, verify failures**

Run: `bats tests/confidence-gate-hook.bats`
Expected: all fail (hook file doesn't exist).

- [ ] **Step 3: Implement hook**

```bash
#!/usr/bin/env bash
# Confidence gate: blocks PR/MR creation on RED aggregate verdict.
# Modeled on hooks/tdd-gate.sh — exit 2 to block.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"

# Filter: only fire on PR/MR creation commands.
if ! echo "$TOOL_INPUT" | grep -qE '(gh\s+pr\s+create|glab\s+mr\s+create)'; then
  exit 0
fi

ACTIVE_SPEC_FILE="$PROJECT_DIR/.git/aw/active-spec"
if [ ! -f "$ACTIVE_SPEC_FILE" ]; then
  echo "🚫 Confidence gate: no .git/aw/active-spec pointer." >&2
  echo "  The pipeline driver writes this file. If you ran agents manually," >&2
  echo "  set it explicitly: echo PROJ-123 > .git/aw/active-spec" >&2
  exit 2
fi

SPEC_ID="$(cat "$ACTIVE_SPEC_FILE")"
LOG="$PROJECT_DIR/.context/specs/${SPEC_ID}-confidence.jsonl"

if [ ! -f "$LOG" ]; then
  echo "🚫 Confidence gate: log not found at $LOG" >&2
  exit 2
fi

# Compute verdict.
VERDICT_JSON="$("$PROJECT_DIR/scripts/confidence.sh" "$LOG")"
BAND="$(echo "$VERDICT_JSON" | jq -r '.band')"
SCORE="$(echo "$VERDICT_JSON" | jq -r '.score')"
GATES="$(echo "$VERDICT_JSON" | jq -c '.gates')"

# Append aggregate verdict to log.
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg ts "$TS" \
  --arg band "$BAND" \
  --argjson score "$SCORE" \
  --argjson gates "$GATES" \
  '{ts:$ts, event:"verdict", scope:"aggregate", band:$band, score:$score, gates:$gates}' \
  >> "$LOG"

case "$BAND" in
  GREEN)
    echo "✅ Confidence: GREEN ($SCORE/100) — proceeding." >&2
    exit 0
    ;;
  YELLOW)
    echo "⚠ Confidence: YELLOW ($SCORE/100) — proceeding with caution." >&2
    exit 0
    ;;
  RED)
    echo "🚫 Confidence: RED ($SCORE/100) — gates: $GATES" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Address the failing gates and retry" >&2
    echo "  2. /override-confidence \"<reason>\" to bypass (logged)" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Make executable**

```bash
chmod +x hooks/confidence-gate.sh
```

- [ ] **Step 5: Run tests, verify pass**

Run: `bats tests/confidence-gate-hook.bats`
Expected: all 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/confidence-gate.sh tests/confidence-gate-hook.bats
git commit -m "feat(confidence): add PreToolUse hook for PR/MR creation gating"
```

---

## Task 8: skills/override-confidence

**Files:**
- Create: `skills/override-confidence/SKILL.md`
- Create: `tests/override-confidence.bats`

**Background:** Mirrors `/skip-tdd`. Writes `.git/aw/override-<spec-id>` with `{reason, ts, branch}`. The hook (Task 9) consumes the marker. Refuses empty/boilerplate reasons.

- [ ] **Step 1: Failing test**

Create `tests/override-confidence.bats`:
```bash
#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR"
  git init -q
  mkdir -p .git/aw
  echo "PROJ-1" > .git/aw/active-spec
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

# Simulate the skill body. The skill itself is markdown that Claude executes,
# so we factor the bash logic into a sourceable function for testing.
source_skill() {
  source "$BATS_TEST_DIRNAME/../skills/override-confidence/skill.bash"
}

@test "override-confidence: writes marker with reason" {
  source_skill
  override_confidence "Reviewer flagged perf issue tracked in PERF-42; not blocking"
  [ -f ".git/aw/override-PROJ-1" ]
  run jq -r '.reason' ".git/aw/override-PROJ-1"
  [[ "$output" == *"PERF-42"* ]]
}

@test "override-confidence: rejects empty reason" {
  source_skill
  run override_confidence ""
  [ "$status" -ne 0 ]
  [ ! -f ".git/aw/override-PROJ-1" ]
}

@test "override-confidence: rejects boilerplate reason" {
  source_skill
  run override_confidence "fix"
  [ "$status" -ne 0 ]
  run override_confidence "."
  [ "$status" -ne 0 ]
  run override_confidence "override"
  [ "$status" -ne 0 ]
}

@test "override-confidence: refuses if no active-spec" {
  source_skill
  rm .git/aw/active-spec
  run override_confidence "valid reason text here"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run, verify failures**

Run: `bats tests/override-confidence.bats`
Expected: fail — `skill.bash` doesn't exist.

- [ ] **Step 3: Create the skill bash function**

The skill is markdown that Claude executes. To make it testable, factor the actual bash into a separate file the skill sources.

Create `skills/override-confidence/skill.bash`:
```bash
#!/usr/bin/env bash
# Sourceable function — used by SKILL.md and tests.

override_confidence() {
  local reason="$1"
  local boilerplate_re='^(\.|fix|override|x|y|skip|bypass|no|none)$'

  # Trim whitespace.
  reason="${reason#"${reason%%[![:space:]]*}"}"
  reason="${reason%"${reason##*[![:space:]]}"}"

  if [ -z "$reason" ]; then
    echo "🚫 /override-confidence requires a non-empty reason." >&2
    return 1
  fi

  # Reject boilerplate single tokens.
  if echo "$reason" | grep -qiE "$boilerplate_re"; then
    echo "🚫 /override-confidence reason looks like boilerplate. Be specific." >&2
    return 1
  fi

  # Require minimum length to discourage low-effort reasons.
  if [ "${#reason}" -lt 12 ]; then
    echo "🚫 /override-confidence reason must be at least 12 characters." >&2
    return 1
  fi

  if [ ! -f ".git/aw/active-spec" ]; then
    echo "🚫 /override-confidence: no .git/aw/active-spec pointer." >&2
    return 1
  fi

  local spec_id branch ts
  spec_id="$(cat .git/aw/active-spec)"
  branch="$(git branch --show-current 2>/dev/null || echo unknown)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -n \
    --arg reason "$reason" \
    --arg branch "$branch" \
    --arg ts "$ts" \
    '{reason:$reason, branch:$branch, ts:$ts}' \
    > ".git/aw/override-${spec_id}"

  echo "✅ /override-confidence active for spec $spec_id. Auto-clears after next PR/MR creation." >&2
}
```

- [ ] **Step 4: Create SKILL.md**

```markdown
---
name: override-confidence
description: >
  Bypass the confidence gate for the next PR/MR creation. Logs the reason
  for accountability. Auto-clears after the next gate fire.
  Triggers on: override confidence, bypass confidence, force PR.
---

## Override Confidence Gate

Creates a one-shot bypass marker so the confidence-gate hook allows the
next `gh pr create` or `glab mr create` even on RED.

### Usage
`/override-confidence "<reason>"`

Reason must be at least 12 characters and not boilerplate. Example:
> /override-confidence "Reviewer flagged perf regression tracked in PERF-42; not blocking this delivery"

### Execute
Run:
```bash
source skills/override-confidence/skill.bash
override_confidence "$ARGUMENTS"
```

The marker file `.git/aw/override-<spec-id>` is consumed by the next hook
fire (success or failure). Reason is logged to the spec's confidence.jsonl
as an `override` event with `trigger: "manual"`.
```

- [ ] **Step 5: Run tests, verify pass**

Run: `bats tests/override-confidence.bats`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add skills/override-confidence/ tests/override-confidence.bats
git commit -m "feat(confidence): add /override-confidence skill for one-shot bypass"
```

---

## Task 9: hooks/confidence-gate.sh — manual override consumption

**Files:**
- Modify: `hooks/confidence-gate.sh`
- Modify: `tests/confidence-gate-hook.bats`

**Background:** When the hook fires RED and `.git/aw/override-<spec-id>` exists, consume it (read, log, delete) and exit 0.

- [ ] **Step 1: Failing test**

Append to `tests/confidence-gate-hook.bats`:
```bash
@test "RED with override marker: proceeds, marker deleted, override event logged" {
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 1 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"
  echo '{"reason":"valid reason text here that is long enough","branch":"x","ts":"2026-05-02T00:00:00Z"}' \
    > .git/aw/override-PROJ-1

  run run_hook "gh pr create"
  [ "$status" -eq 0 ]
  [ ! -f ".git/aw/override-PROJ-1" ]

  # override event was appended
  run jq -s '[.[] | select(.event=="override" and .trigger=="manual")] | length' "$LOG"
  [ "$output" = "1" ]
}
```

- [ ] **Step 2: Run, verify failure**

Run: `bats tests/confidence-gate-hook.bats`
Expected: new test fails (still exits 2 because override logic not implemented).

- [ ] **Step 3: Implement override consumption**

In `hooks/confidence-gate.sh`, replace the `RED)` case with:
```bash
  RED)
    OVERRIDE_FILE="$PROJECT_DIR/.git/aw/override-${SPEC_ID}"
    if [ -f "$OVERRIDE_FILE" ]; then
      OVERRIDE_REASON="$(jq -r '.reason' "$OVERRIDE_FILE")"
      jq -n \
        --arg ts "$TS" \
        --arg reason "$OVERRIDE_REASON" \
        --argjson gates "$GATES" \
        '{ts:$ts, event:"override", trigger:"manual", reason:$reason, gates_bypassed:$gates}' \
        >> "$LOG"
      rm -f "$OVERRIDE_FILE"
      echo "⚠ Confidence: RED ($SCORE/100) — override consumed: \"$OVERRIDE_REASON\"" >&2
      exit 0
    fi

    echo "🚫 Confidence: RED ($SCORE/100) — gates: $GATES" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Address the failing gates and retry" >&2
    echo "  2. /override-confidence \"<reason>\" to bypass (logged)" >&2
    exit 2
    ;;
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bats tests/confidence-gate-hook.bats`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/confidence-gate.sh tests/confidence-gate-hook.bats
git commit -m "feat(confidence): consume /override-confidence marker in hook"
```

---

## Task 10: hooks/confidence-gate.sh — skip-tdd auto-bypass

**Files:**
- Modify: `hooks/confidence-gate.sh`
- Modify: `tests/confidence-gate-hook.bats`

**Background:** When `.tdd-skip` exists AND verdict is RED AND only structural gates (NO_AC, AC_NOT_TESTED) fired, auto-bypass using the skip-tdd reason. Behavioral gates (TEST_FAILED, BUILD_BROKEN, MUST_FIX, TDD_BYPASSED_NO_REASON) still block.

The `.tdd-skip` file lives in repo root (per `skills/skip-tdd/SKILL.md`). Format is plain text with `Reason: <text>` line.

- [ ] **Step 1: Failing tests**

```bash
@test "skip-tdd active + only NO_AC: auto-bypass, exit 0, trigger=skip-tdd-auto" {
  printf 'TDD bypass active\nReason: docs-only change\nBranch: x\nTime: x\n' > .tdd-skip
  make_log "$LOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 0 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 0 ]

  run jq -s '[.[] | select(.event=="override" and .trigger=="skip-tdd-auto")] | length' "$LOG"
  [ "$output" = "1" ]
}

@test "skip-tdd active + MUST_FIX: still blocks (exit 2)" {
  printf 'TDD bypass active\nReason: docs-only change\nBranch: x\nTime: x\n' > .tdd-skip
  make_log "$LOG" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 1 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
  [[ "$output" == *"behavioral"* ]] || [[ "$output" == *"MUST_FIX"* ]]
}

@test "skip-tdd active + mixed (NO_AC + TEST_FAILED): blocks (exit 2)" {
  printf 'TDD bypass active\nReason: docs-only change\nBranch: x\nTime: x\n' > .tdd-skip
  make_log "$LOG" \
    "$(spec_event '[]')" \
    "$(qa_event 1 5 1 ok '[]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  run run_hook "gh pr create"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Run, verify failures**

- [ ] **Step 3: Implement structural-only auto-bypass**

In `hooks/confidence-gate.sh`, in the `RED)` case, BEFORE the existing manual-override check:
```bash
  RED)
    SKIP_TDD_FILE="$PROJECT_DIR/.tdd-skip"
    if [ -f "$SKIP_TDD_FILE" ]; then
      # Classify gates.
      STRUCTURAL_GATES='["NO_AC","AC_NOT_TESTED"]'
      ALL_STRUCTURAL="$(jq -n --argjson g "$GATES" --argjson s "$STRUCTURAL_GATES" \
        '($g | length) > 0 and ($g - $s | length) == 0')"

      if [ "$ALL_STRUCTURAL" = "true" ]; then
        SKIP_REASON="$(grep '^Reason:' "$SKIP_TDD_FILE" | sed 's/^Reason: *//')"
        jq -n \
          --arg ts "$TS" \
          --arg reason "${SKIP_REASON:-skip-tdd active}" \
          --argjson gates "$GATES" \
          '{ts:$ts, event:"override", trigger:"skip-tdd-auto", reason:$reason, gates_bypassed:$gates}' \
          >> "$LOG"
        echo "⚠ Confidence: RED ($SCORE/100) — auto-bypassed by /skip-tdd (structural gates only)" >&2
        exit 0
      else
        echo "🚫 Confidence: RED ($SCORE/100) — gates: $GATES" >&2
        echo "" >&2
        echo "/skip-tdd does not bypass behavioral gates. Use /override-confidence \"<reason>\"." >&2
        exit 2
      fi
    fi

    # ... existing OVERRIDE_FILE check follows
```

- [ ] **Step 4: Run tests, verify all pass**

- [ ] **Step 5: Commit**

```bash
git add hooks/confidence-gate.sh tests/confidence-gate-hook.bats
git commit -m "feat(confidence): auto-bypass structural gates when /skip-tdd is active"
```

---

## Task 11: Modify agent files to emit events

**Files:**
- Modify: `agents/claude-code/architect.md`
- Modify: `agents/copilot-cli/architect.agent.md`
- Modify: `agents/claude-code/qa.md`
- Modify: `agents/copilot-cli/qa.agent.md`
- Modify: `agents/claude-code/reviewer.md`
- Modify: `agents/copilot-cli/reviewer.agent.md`

**Background:** Agents are markdown instructions. Each one needs a section telling the model to append an event to the per-spec log after completing its primary work. The event is created via `jq -n` and `>>`-appended to `.context/specs/<id>-confidence.jsonl`.

This task has no automated tests — agent instructions are validated end-to-end in Task 13. Reviewer should manually verify each `.md` change reads naturally and matches the event schema in the spec.

- [ ] **Step 1: Modify `agents/claude-code/architect.md`**

Append a new section before the `## Rules` section:
```markdown
### 6. Emit Confidence Event
After writing the spec, append a `spec` event to the confidence log:

```bash
LOG=".context/specs/<id>-confidence.jsonl"
mkdir -p "$(dirname "$LOG")"

# Build ac_items JSON from spec's AC section.
AC_JSON='[{"id":"AC-1","text":"..."},{"id":"AC-2","text":"..."}]'  # extracted from spec

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg path ".context/specs/<id>-spec.md" \
  --argjson ac "$AC_JSON" \
  '{ts:$ts, event:"spec", spec_path:$path, ac_items:$ac}' \
  >> "$LOG"
```
Each AC item must have `id` (e.g. AC-1) and `text` (the criterion).
```

- [ ] **Step 2: Modify `agents/copilot-cli/architect.agent.md`**

Same content, adapted to that file's format. Read the existing file first to match its tone/structure.

- [ ] **Step 3: Modify `agents/claude-code/qa.md`**

Append a new section before `## Rules`:
```markdown
### 5. Emit Confidence Event
After running tests, append a `qa` event to the confidence log:

```bash
LOG=".context/specs/<id>-confidence.jsonl"
TESTED='["AC-1","AC-3"]'  # AC ids covered by tests run for this step

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson step "$STEP" \
  --argjson passed "$PASSED" \
  --argjson failed "$FAILED" \
  --argjson added "$ADDED" \
  --arg build "$BUILD_STATUS" \
  --argjson tested "$TESTED" \
  '{ts:$ts, event:"qa", step:$step, tests_passed:$passed, tests_failed:$failed, tests_added:$added, build_status:$build, ac_items_tested:$tested}' \
  >> "$LOG"
```
Determine which AC ids the tests cover by mapping test names → spec AC numbers.
```

- [ ] **Step 4: Modify `agents/copilot-cli/qa.agent.md`**

Same content, adapted.

- [ ] **Step 5: Modify `agents/claude-code/reviewer.md`**

Append a new section before `## Rules`:
```markdown
### 7. Emit Confidence Event
After your final review pass (whether clean or after fix loops), append a `review` event:

```bash
LOG=".context/specs/<id>-confidence.jsonl"

# Build findings arrays from your categorized review.
MUST_FIX_JSON='[{"file":"x.go","line":42,"msg":"..."}]'   # or []
SHOULD_FIX_JSON='[]'
SUGGESTION_JSON='[]'
TECH_DEBT_JSON='[]'
DIFF_LINES=$(git diff --stat HEAD~1..HEAD | tail -1 | awk '{print $4 + $6}')

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson step "$STEP" \
  --argjson must "$MUST_FIX_JSON" \
  --argjson should "$SHOULD_FIX_JSON" \
  --argjson sugg "$SUGGESTION_JSON" \
  --argjson loops "$LOOPS_USED" \
  --argjson td "$TECH_DEBT_JSON" \
  --argjson diff "$DIFF_LINES" \
  '{ts:$ts, event:"review", step:$step, must_fix:$must, should_fix:$should, suggestion:$sugg, loops_used:$loops, tech_debt_deferrals:$td, diff_lines:$diff}' \
  >> "$LOG"
```
`loops_used` is the number of fix-loops that ran for this step (1, 2, or 3).
```

- [ ] **Step 6: Modify `agents/copilot-cli/reviewer.agent.md`**

Same content, adapted.

- [ ] **Step 7: Visual review of all six files**

Read each modified file in full. Verify:
- Section number is sequential (doesn't conflict with existing section)
- `.md` formatting renders correctly
- Code blocks fence properly

- [ ] **Step 8: Commit**

```bash
git add agents/
git commit -m "feat(confidence): instruct architect/qa/reviewer agents to emit events"
```

---

## Task 12: ai-native-workflow CLI integration

**Files:**
- Modify: `ai-native-workflow`
- Create: `tests/cli-confidence.bats`

**Background:** Three integration points in the CLI:
1. **At pipeline start** — write `.git/aw/active-spec` with the resolved spec id.
2. **After each step** — invoke `scripts/confidence.sh --scope=step --step=N`, append `verdict` event with `scope=step`, surface to user; if YELLOW/RED, prompt `[go / fix / abort]`.
3. **Before PR/MR creation** — invoke aggregate scorer, inject `## Confidence` section into the PR body string passed to `gh pr create` / `glab mr create`.

The CLI is a single bash script. Search for the pipeline runner functions (`run_github_feature`, `run_gitlab_feature`, etc.). Add the integration there.

- [ ] **Step 1: Read existing pipeline runner**

Read `ai-native-workflow` and locate functions:
- The function that handles `run github-feature` / `run gitlab-feature`
- The loop that iterates todo.md steps

Document where each integration point goes inline before writing tests. (No code change in this step — orientation only.)

- [ ] **Step 2: Write integration test for active-spec write**

Create `tests/cli-confidence.bats`:
```bash
#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR"
  git init -q
  CLI="$BATS_TEST_DIRNAME/../ai-native-workflow"
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

@test "CLI: pipeline start writes .git/aw/active-spec" {
  # Stub Jira/gh fetches; just exercise the active-spec write path.
  AW_DRY_RUN=1 AW_SPEC_ID=PROJ-42 "$CLI" run github-feature --spec-id PROJ-42 || true
  [ -f ".git/aw/active-spec" ]
  [ "$(cat .git/aw/active-spec)" = "PROJ-42" ]
}
```

The `AW_DRY_RUN=1` environment is a new flag we'll add — when set, the CLI sets up state but doesn't actually call agents. Search for any existing dry-run handling first; reuse if present.

- [ ] **Step 3: Run, verify failure**

- [ ] **Step 4: Implement active-spec write**

In `ai-native-workflow`, locate the pipeline-start path. Add at the top:
```bash
write_active_spec() {
  local spec_id="$1"
  mkdir -p .git/aw
  printf '%s\n' "$spec_id" > .git/aw/active-spec
}

# In each pipeline runner, after spec id is resolved:
write_active_spec "$SPEC_ID"
```

If `AW_DRY_RUN=1`, return after writing active-spec (skip agent invocations).

- [ ] **Step 5: Run, verify pass**

- [ ] **Step 6: Add per-step verdict invocation**

After each step's `qa` and `reviewer` invocations finish, add:
```bash
emit_step_verdict() {
  local spec_id="$1" step="$2"
  local log=".context/specs/${spec_id}-confidence.jsonl"
  local verdict
  verdict="$(scripts/confidence.sh "$log" --scope=step --step="$step")"

  # Append verdict event.
  local ts band score
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  band="$(jq -r '.band' <<<"$verdict")"
  score="$(jq -r '.score' <<<"$verdict")"
  jq -n --arg ts "$ts" --argjson step "$step" --arg band "$band" --argjson score "$score" \
    '{ts:$ts, event:"verdict", scope:"step", step:$step, band:$band, score:$score}' \
    >> "$log"

  # Surface.
  echo "[step $step] confidence: $band ($score/100)"

  # Prompt if not GREEN.
  if [ "$band" != "GREEN" ]; then
    read -rp "Continue? [go/fix/abort]: " choice
    case "$choice" in
      go)    return 0 ;;
      fix)   return 10 ;;  # caller loops back to reviewer
      abort) exit 130 ;;
      *)     echo "unrecognized; aborting" >&2; exit 1 ;;
    esac
  fi
}
```

Call `emit_step_verdict "$SPEC_ID" "$STEP_NUMBER"` after each step.

- [ ] **Step 7: Add PR body confidence section injection**

In the PR/MR creation function:
```bash
build_pr_body() {
  local spec_id="$1" base_body="$2"
  local log=".context/specs/${spec_id}-confidence.jsonl"
  local verdict band score penalties_summary

  verdict="$(scripts/confidence.sh "$log")"
  band="$(jq -r '.band' <<<"$verdict")"
  score="$(jq -r '.score' <<<"$verdict")"
  penalties_summary="$(jq -r '.penalties | to_entries | map(select(.value != 0)) | map("\(.value) \(.key)") | join(", ")' <<<"$verdict")"
  [ -z "$penalties_summary" ] && penalties_summary="(none)"

  cat <<EOF
$base_body

## Confidence
**$band: $score/100**

Penalties: $penalties_summary
Audit: \`.context/specs/${spec_id}-confidence.jsonl\`
EOF
}
```

Pipe through this when invoking `gh pr create --body` / `glab mr create --description`.

- [ ] **Step 8: Test end-to-end**

Add to `tests/cli-confidence.bats`:
```bash
@test "CLI: build_pr_body injects ## Confidence section" {
  source "$CLI" >/dev/null 2>&1 || true  # source for function access; may need a refactor
  mkdir -p .context/specs .git/aw
  echo "PROJ-1" > .git/aw/active-spec
  source "$BATS_TEST_DIRNAME/lib/confidence-helpers"
  make_log ".context/specs/PROJ-1-confidence.jsonl" \
    "$(spec_event '[{"id":"AC-1","text":"x"}]')" \
    "$(qa_event 1 5 0 ok '["AC-1"]')" \
    "$(review_event 1 0 0 0 1 0 100)"

  result="$(build_pr_body PROJ-1 "Initial body")"
  [[ "$result" == *"## Confidence"* ]]
  [[ "$result" == *"GREEN"* ]]
}
```

If sourcing the CLI is impractical (because of side effects on source), refactor `build_pr_body` and `emit_step_verdict` into a helper file `scripts/confidence-cli.sh` that the CLI sources. Tests source the same helper.

- [ ] **Step 9: Commit**

```bash
git add ai-native-workflow scripts/confidence-cli.sh tests/cli-confidence.bats
git commit -m "feat(confidence): integrate scorer into ai-native-workflow pipeline"
```

---

## Task 13: Hook registration

**Files:**
- Modify: `config/settings.json`
- Modify: `ai-native-workflow` (the installer that copies these to `~/.claude/`)

**Background:** Add a second PreToolUse hook entry. The existing tdd-gate hook already matches `Bash`; both can coexist as separate entries in the same hook list.

- [ ] **Step 1: Read current settings.json**

Run: `cat config/settings.json`
Confirm the structure: `hooks.PreToolUse[0].matcher == "Bash"`, `hooks.PreToolUse[0].hooks` is an array.

- [ ] **Step 2: Add confidence-gate hook entry**

Modify `config/settings.json`:
```json
{
  "hooks": {
    "SessionStart": [...],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tdd-gate.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/confidence-gate.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Notification": [...]
  }
}
```

- [ ] **Step 3: Update installer to copy confidence-gate.sh**

Search `ai-native-workflow` for where `tdd-gate.sh` is copied to `~/.claude/hooks/`. Add `confidence-gate.sh` to the same copy step. Likewise copy `scripts/confidence.sh` to `~/.claude/scripts/`.

The installer should also copy `skills/override-confidence/` to `~/.claude/skills/`.

- [ ] **Step 4: Verify install on a sandbox**

Run:
```bash
CLAUDE_HOME=/tmp/aw-confidence-test ./ai-native-workflow install global
ls /tmp/aw-confidence-test/.claude/hooks/confidence-gate.sh
ls /tmp/aw-confidence-test/.claude/scripts/confidence.sh
ls /tmp/aw-confidence-test/.claude/skills/override-confidence/
jq '.hooks.PreToolUse[0].hooks | length' /tmp/aw-confidence-test/.claude/settings.json
```
Expected: all paths exist; hook count is 2.

- [ ] **Step 5: Commit**

```bash
git add config/settings.json ai-native-workflow
git commit -m "feat(confidence): register hook and copy scorer in installer"
```

---

## Task 14: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Add Confidence Gate section to README**

Insert after the "TDD Bypass" section, before "Multi-Cluster Troubleshooting":
```markdown
## Confidence Gate

After every pipeline run, a deterministic confidence verdict is computed
from the events that `architect`, `qa`, and `reviewer` write to
`.context/specs/<id>-confidence.jsonl`. The verdict surfaces both as a
0–100 score and as a band (GREEN / YELLOW / RED).

**The hook (`hooks/confidence-gate.sh`) blocks `gh pr create` /
`glab mr create` on RED.** It also surfaces YELLOW as a non-blocking
warning, and writes a `## Confidence` section into the PR/MR body.

### Hard gates (any one → RED)
- `NO_AC` — no acceptance criteria in spec
- `TEST_FAILED` — any test failed
- `BUILD_BROKEN` — build/typecheck broken
- `MUST_FIX` — reviewer flagged an unresolved must-fix item
- `AC_NOT_TESTED` — an AC item has no corresponding test
- `TDD_BYPASSED_NO_REASON` — TDD gate bypassed without `/skip-tdd`

### Scored penalties
Score starts at 100; subtractions: −5 per should-fix, −1 per suggestion,
−5 per step that needed a 2nd review loop, −10 more for a 3rd, −3 per
tech-debt deferral, −2 per missing AC (cap −20), −5 if diff > 400 lines
(−15 if > 1000).

### Bands
- `GREEN` ≥ 80 — proceed
- `YELLOW` 60–79 — pause and prompt during pipeline; informational at PR
- `RED` < 60 or any hard gate — block PR

### Bypass
- `/override-confidence "<reason>"` — explicit one-shot bypass; reason
  must be ≥12 chars and not boilerplate.
- `/skip-tdd "<reason>"` — auto-bypasses **structural** gates only
  (`NO_AC`, `AC_NOT_TESTED`). Behavioral gates (test/build/must-fix)
  still block.

### Audit trail
The full event history per spec lives in
`.context/specs/<id>-confidence.jsonl` and is committed to the repo.
Every verdict, every override, every gate fire is auditable in git
history.
```

- [ ] **Step 2: Update ARCHITECTURE.md pipeline diagrams**

Find each pipeline diagram (search for `tdd-developer`). Add a `confidence` step after `reviewer`, before the PR/MR creation step. Example:
```
ai-native-workflow run github-feature specs.md
  │
  ├─ requirements-engineer
  ├─ architect              → writes .context/specs/<id>-spec.md
  │                           emits spec event to <id>-confidence.jsonl
  ├─ tdd-developer (per step)
  │   ├─ qa                 → emits qa event
  │   ├─ reviewer           → emits review event
  │   └─ confidence (per-step verdict, prompts on YELLOW/RED)
  ├─ confidence (aggregate verdict — hook enforces RED at PR step)
  └─ gh pr create           → PR body includes ## Confidence section
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/ARCHITECTURE.md
git commit -m "docs: document confidence gate in README and ARCHITECTURE"
```

---

## Verification checklist (after all tasks complete)

- [ ] All bats tests pass: `bats tests/`
- [ ] Manual end-to-end: run `ai-native-workflow run github-feature` against a fixture spec, observe per-step verdicts, observe aggregate verdict in PR body
- [ ] Manual override path: induce RED, run `/override-confidence "valid reason of sufficient length"`, verify PR creation succeeds and `override` event is in the log
- [ ] Manual skip-tdd structural path: produce a NO_AC RED, set `.tdd-skip`, verify PR proceeds with `trigger: "skip-tdd-auto"` event
- [ ] Manual skip-tdd behavioral path: produce a MUST_FIX RED, set `.tdd-skip`, verify PR is still blocked
- [ ] No new `.gitignore` entries
- [ ] `bash -n` clean: `find scripts hooks -name '*.sh' -exec bash -n {} \;`
- [ ] All AC items from the spec (AC-1 through AC-10) have a passing test or a documented manual verification step
