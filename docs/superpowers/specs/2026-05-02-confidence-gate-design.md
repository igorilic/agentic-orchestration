# Confidence Gate — Design Spec

**Date:** 2026-05-02
**Status:** Approved (brainstorming) — pending implementation plan
**Author:** Brainstorming session with Igor

## Summary

Add a deterministic confidence verdict to the `tdd-developer → qa → reviewer` pipeline. Each step emits structured receipts as events in a per-spec append-only log; a shell script computes a score and band (GREEN / YELLOW / RED) from those events; a `PreToolUse` hook on `gh pr create` / `glab mr create` enforces the gate. The verdict surfaces as both a number (0–100) and a band, so users can read it descriptively or numerically.

This spec covers v1: hardcoded rubric, single-spec scope, shell-only implementation.

## Goals

- Provide a defensible, reproducible signal of "did the pipeline actually deliver against the spec?"
- Block PR/MR creation when the pipeline produces unsafe output (broken tests, must-fix bugs, missing acceptance criteria).
- Surface the verdict numerically (e.g. `87/100`) and descriptively (`GREEN`).
- Stay consistent with existing repo conventions: shell-only, hook-enforced, file-based audit trail.
- Co-locate confidence artifacts with the rest of a spec's working state under `.context/specs/`.

## Non-goals (v1)

- Per-org configurable weights or thresholds.
- Test-coverage-delta as a signal (dropped — too noisy across stacks).
- Cross-spec trend analysis or dashboards.
- Auto-loop-on-RED retry (conflicts with reviewer's 3-loop cap).
- Confidence verdicts for the `explorer` / `spikes/` track (no merge there).

## Architecture

### New files

| File | Purpose |
|---|---|
| `scripts/confidence.sh` | Pure deterministic scorer. Reads a per-spec jsonl event log, computes hard gates + scored penalties, prints `{band, score, gates, penalties, verdict_text}` as JSON. Bash + `jq`, ~80 lines. |
| `hooks/confidence-gate.sh` | `PreToolUse` hook on `Bash` calls matching `gh pr create*` and `glab mr create*`. Resolves spec id from current branch/state, runs `confidence.sh`, exits 2 on RED unless an override is present. |
| `skills/override-confidence/SKILL.md` | `/override-confidence "<reason>"` skill. Mirrors `/skip-tdd`. Writes a one-shot bypass marker; refuses empty/boilerplate reasons. |

### Modified files

| File | Change |
|---|---|
| `agents/claude-code/architect.md` + `agents/copilot-cli/architect.agent.md` | After producing the spec, append a `spec` event to `.context/specs/<id>-confidence.jsonl` listing the canonical AC items. |
| `agents/claude-code/qa.md` + `agents/copilot-cli/qa.agent.md` | After running tests for a step, append a `qa` event with test counts, build status, and which AC ids the step's tests cover. |
| `agents/claude-code/reviewer.md` + `agents/copilot-cli/reviewer.agent.md` | After a review pass, append a `review` event with finding counts, loops used, tech-debt deferrals, and diff line count. |
| `ai-native-workflow` (CLI driver) | After each step: invoke `confidence.sh`, append a `verdict` event with `scope=step`, surface to user. Before PR/MR step: invoke `confidence.sh` against full log, append `verdict` event with `scope=aggregate`, render PR body block. Also writes `.git/aw/active-spec` pointing at the active spec id so the hook can resolve it. |

### Storage layout

All per-spec artifacts continue to live under `.context/specs/`, following the existing flat naming convention:

```
.context/specs/
  PROJ-123-requirements.md      # existing
  PROJ-123-spec.md              # existing
  PROJ-123-todo.md              # existing
  PROJ-123-confidence.jsonl     # new — append-only event log
```

The confidence file is committed to the repo as a permanent change artifact. Reviewers can see exactly which AC items the developer claimed coverage for, which findings were triaged, and which review loops fired. The git history of these files becomes the long-term audit trail.

The override marker is the only transient artifact and lives outside the work tree:

```
.git/aw/override-<spec-id>     # one-shot, consumed by next hook fire
```

No `.gitignore` entries are introduced.

## Event log format

Each line of `<id>-confidence.jsonl` is one JSON object. All events have `ts` (ISO-8601 UTC) and `event`. Field schemas per event type:

### `spec` (emitted once by architect)
```json
{
  "ts": "2026-05-02T18:01:00Z",
  "event": "spec",
  "spec_path": ".context/specs/PROJ-123-spec.md",
  "ac_items": [
    {"id": "AC-1", "text": "User can log in with valid credentials"},
    {"id": "AC-2", "text": "Invalid password returns 401"}
  ]
}
```

Empty `ac_items` triggers the `NO_AC` hard gate.

### `qa` (emitted once per step by qa agent)
```json
{
  "ts": "2026-05-02T18:14:22Z",
  "event": "qa",
  "step": 1,
  "tests_passed": 12,
  "tests_failed": 0,
  "tests_added": 3,
  "build_status": "ok",
  "ac_items_tested": ["AC-1"]
}
```

`tests_failed > 0` triggers `TEST_FAILED`. `build_status != "ok"` triggers `BUILD_BROKEN`.

### `review` (emitted once per step by reviewer agent — after final loop)
```json
{
  "ts": "2026-05-02T18:18:10Z",
  "event": "review",
  "step": 1,
  "must_fix":   [{"file": "auth.go", "line": 42, "msg": "..."}],
  "should_fix": [{"file": "auth.go", "line": 58, "msg": "..."}],
  "suggestion": [],
  "loops_used": 1,
  "tech_debt_deferrals": [],
  "diff_lines": 187
}
```

Non-empty `must_fix` triggers `MUST_FIX`.

### `verdict` (emitted by `confidence.sh`, written by CLI driver)
```json
{
  "ts": "2026-05-02T18:18:11Z",
  "event": "verdict",
  "scope": "step",
  "step": 1,
  "score": 95,
  "band": "GREEN",
  "gates": [],
  "penalties": {"should_fix": 0, "loops": 0, "tech_debt": 0, "ac_coverage": 0, "diff": 0}
}
```

`scope` is `"step"` for per-step verdicts and `"aggregate"` for the final verdict computed at PR/MR time.

### `override` (emitted by `/override-confidence` and by `/skip-tdd` auto-bypass)
```json
{
  "ts": "2026-05-02T19:50:01Z",
  "event": "override",
  "trigger": "manual",
  "reason": "Reviewer flagged perf regression tracked in PERF-42; not blocking this delivery",
  "gates_bypassed": ["MUST_FIX"]
}
```

`trigger` is `"manual"` (from `/override-confidence`) or `"skip-tdd-auto"` (auto-applied because `/skip-tdd` was active and only structural gates fired).

### `pr_created`
```json
{
  "ts": "2026-05-02T19:50:02Z",
  "event": "pr_created",
  "url": "https://github.com/.../pull/42"
}
```

## Algorithm

```
score = 100

# Per-step penalties summed across all step events:
score -= 5  * sum(len(should_fix) for each review event)
score -= 1  * sum(len(suggestion) for each review event)
score -= 5  * count(review events with loops_used >= 2)
score -= 10 * count(review events with loops_used >= 3)
score -= 3  * sum(len(tech_debt_deferrals) for each review event)

# AC coverage (single check across all qa events vs spec event):
ac_in_spec   = set of AC ids from the `spec` event
ac_tested    = union of `ac_items_tested` across all qa events
missing      = ac_in_spec - ac_tested
score -= min(2 * len(missing), 20)

# Diff size (single check on aggregate diff):
total_diff = sum(diff_lines for each review event)
if total_diff > 1000:    score -= 15
elif total_diff > 400:   score -= 5

score = max(0, score)

# Hard gates (any one fires => RED):
gates = []
if no spec event present, or ac_items empty, or all ac_items lack a testable verb:
    gates.append("NO_AC")
if any qa event has tests_failed > 0:
    gates.append("TEST_FAILED")
if any qa event has build_status != "ok":
    gates.append("BUILD_BROKEN")
if any review event has non-empty must_fix:
    gates.append("MUST_FIX")
if any AC id appears in spec but never in any ac_items_tested:
    gates.append("AC_NOT_TESTED")
if a commit was made bypassing tdd-gate without a logged /skip-tdd reason:
    gates.append("TDD_BYPASSED_NO_REASON")

# Band:
if gates is non-empty:    band = RED
elif score >= 80:         band = GREEN
elif score >= 60:         band = YELLOW
else:                     band = RED
```

### Per-step vs aggregate

The same algorithm runs in two scopes:

- **Per-step:** filtered to events for a single `step`. Informational only. Surfaces between pipeline steps so the developer sees a real-time signal. Does not block.
- **Aggregate:** the entire log. Enforced by the hook at PR/MR time. The aggregate verdict is what gates the merge.

## Hook enforcement

`hooks/confidence-gate.sh` registers as a `PreToolUse` hook matching `Bash` invocations of `gh pr create*` or `glab mr create*`.

```
PR/MR creation attempted
  ├─ resolve <spec-id> from active branch / pipeline state
  ├─ run scripts/confidence.sh <spec-id>  → JSON verdict on stdout
  ├─ append `verdict` event with scope=aggregate to log
  ├─ band == GREEN  → exit 0; PR proceeds
  ├─ band == YELLOW → exit 0; print warning; PR proceeds
  └─ band == RED    → resolve overrides:
        ├─ .git/aw/override-<spec-id> present?
        │     YES → consume marker, append override event (trigger=manual), exit 0
        ├─ /skip-tdd marker active for this commit/branch?
        │     YES → check firing gates:
        │         ├─ All gates structural (NO_AC, AC_NOT_TESTED)?
        │         │     → append override event (trigger=skip-tdd-auto, reason=skip-tdd's reason), exit 0
        │         └─ Any other gate firing (TEST_FAILED, BUILD_BROKEN, MUST_FIX, TDD_BYPASSED_NO_REASON)?
        │              → exit 2 with: "skip-tdd does not bypass this gate.
        │                Use /override-confidence with explicit reason."
        └─ no override applicable → exit 2 with verdict + failing gates
```

YELLOW does not block at the hook layer because the YELLOW pause already happens in the CLI driver during the pipeline run (the user types `go` to continue past it). By PR creation time, YELLOW is informational.

## Override mechanism

### Manual: `/override-confidence "<reason>"`

A skill mirroring `/skip-tdd`. Behavior:

- Refuses empty reasons or boilerplate (`"."`, `"fix"`, `"override"`, single word, etc.).
- Writes `.git/aw/override-<spec-id>` containing `{reason, timestamp, user}`.
- Auto-clears (file deleted) on the next hook fire, success or failure. One-shot.
- Logs creation to the spec's confidence.jsonl as an `override` event with `trigger=manual`.

### Auto-applied via `/skip-tdd` (structural gates only)

When the confidence hook fires RED and a `/skip-tdd` marker is active for the current commit/branch:

- **Structural gates** (`NO_AC`, `AC_NOT_TESTED`) are auto-bypassed, reusing the `/skip-tdd` reason as the override reason. Logged as `trigger=skip-tdd-auto`.
- **Behavioral gates** (`TEST_FAILED`, `BUILD_BROKEN`, `MUST_FIX`) are *not* bypassed. Skip-tdd does not grant a free pass for broken code or real bugs found in review. The user must address the issue or use `/override-confidence` with an explicit deliberate reason.

`TDD_BYPASSED_NO_REASON` cannot fire while `/skip-tdd` is active (the gate's condition is "TDD bypassed *and* no reason logged"; `/skip-tdd` is the reason-logging mechanism). If it does fire, it indicates a TDD bypass via some other path and requires explicit `/override-confidence`.

### Why split

`/skip-tdd` says "this isn't a normal feature change" — that's a fine excuse for missing AC or skipped tests (the docs/config/hotfix cases). It is not a fine excuse for shipping broken code. Splitting the gate classes preserves the safety value of the confidence gate while removing redundant override friction for legitimate skip-tdd cases.

## Surfacing the verdict

### During pipeline run

The CLI driver prints per-step verdicts inline:

```
[step 2/5] tdd-developer ...    OK
[step 2/5] qa ...               12 passed, 0 failed
[step 2/5] reviewer ...         1 must-fix → fix loop
[step 2/5] reviewer ...         clean, 2 should-fix
[step 2/5] confidence           YELLOW: 71/100 (-10 should-fix, -5 loop2, -3 tech-debt)
                                Continue to step 3? [go / fix / abort]
```

A YELLOW step does not auto-block, but it does pause for user input. RED at a step prompts the same way but with stronger framing.

### At PR/MR creation (hook)

```
$ glab mr create
⚠ confidence: RED — gates: [MUST_FIX]
  step 4 has 1 unresolved must-fix in auth.go:42

  To proceed: address the finding, or run /override-confidence "<reason>"

[exit 2]
```

### In the PR/MR body

The CLI driver injects a `## Confidence` section into the PR body when creating it:

```markdown
## Confidence
**GREEN: 87/100**

Penalties: −5 should-fix (1 item), −5 review loop 2, −3 tech-debt deferred
AC coverage: 4/4 (100%)
Audit: `.context/specs/PROJ-123-confidence.jsonl`
```

## Testing

Three test layers, modelled on the existing `tdd-gate.sh` test pattern in this repo:

1. **Unit tests for `scripts/confidence.sh`** — `bats-core` with fixture jsonl files in `tests/fixtures/`. Cover: all-green, mixed-yellow, hard-gate-red for each gate, override active, skip-tdd structural-only bypass, skip-tdd attempting behavioral bypass (must still fail), missing log file, malformed events.
2. **Hook integration test** — fixture repo with a fake `glab`/`gh` shim on PATH that records its arguments; assert the hook exits 0/2 correctly given various log states and override conditions.
3. **End-to-end via `ai-native-workflow run`** against a fixture spec — runs the pipeline, asserts the right `verdict` and `pr_created` events land in the jsonl. One happy-path case and one RED-blocks-PR case for v1.

## Open questions for the implementation plan

(These are decisions to surface during plan-writing, not blockers on this design.)

- Exact bats-core layout: per-script test file vs single suite? (Probably matches existing `tests/` layout; needs a look.)
- Whether `<id>` resolution from the active branch should use a CLI flag (`--spec PROJ-123`) or an environment variable (`AW_SPEC_ID`) when the branch name doesn't carry it. Likely the CLI driver writes a `.git/aw/active-spec` pointer; the hook reads it.
- Whether the `verdict_text` field in the script's stdout should be machine-formatted or human-formatted. Probably both: structured fields for machines, `verdict_text` for humans.

## Acceptance criteria for the implementation

- `AC-1` Running `scripts/confidence.sh <spec-id>` against a hand-crafted all-green log prints a JSON verdict with `band: "GREEN"` and `score: 100`.
- `AC-2` Each defined hard gate, when triggered by the corresponding event in the log, produces `band: "RED"` with the correct gate name in the `gates` array.
- `AC-3` Penalty math matches the rubric exactly: a log with one `should_fix` item produces `score: 95`, two produce `90`, etc.; combined penalties stack additively up to `score: 0` minimum.
- `AC-4` `hooks/confidence-gate.sh` exits 2 when the aggregate band is RED and no override applies; exits 0 on GREEN, YELLOW, or RED with valid override.
- `AC-5` `/override-confidence "<reason>"` creates the marker file; the next hook fire consumes it and writes an `override` event with `trigger: "manual"` to the log.
- `AC-6` With `/skip-tdd` active and only `NO_AC` firing, the hook exits 0 and logs `trigger: "skip-tdd-auto"`.
- `AC-7` With `/skip-tdd` active and `MUST_FIX` firing, the hook exits 2 with the correct error message.
- `AC-8` `architect`, `qa`, and `reviewer` agents (both Claude and Copilot variants) emit the documented event shapes.
- `AC-9` The CLI driver injects the `## Confidence` section into the PR/MR body when creating the PR.
- `AC-10` `.gitignore` is unchanged.
