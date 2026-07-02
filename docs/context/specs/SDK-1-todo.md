# SDK-1 — Todo plan (atomic TDD steps)

> Spec: `docs/context/specs/SDK-1-spec.md`
> ADR: `docs/decisions/ADR-002-sentinel-stream-and-sidekick-delegation.md`
> Driver: tdd-developer. Total: 5 (Track A) + 9 (Track B, incl. integration) = 14 steps.

Two tracks. The **sentinel grammar is frozen in the spec (OQ-1)** and is the shared contract:
Track A teaches agents to *emit* it; Track B *renders + persists* it.

**A → B dependency (explicit):** Track B steps B1–B8 are built against committed fixtures that
match the frozen grammar and can proceed in parallel with Track A. The **integration step B9**
and all real-world value require Track A merged (agents actually emitting sentinels/delegations).
**A-1 is a hard GO/NO-GO gate** for the delegation half — do not build A-2..A-5 until it passes.

Each step: one RED test runnable today (`bats tests/<file>.bats`), one TDD cycle (~30 min), one
commit (or test+impl as two commits per local TDD style). The renderer mechanics are already
de-risked in `spikes/sdk-1-renderer/` — Track B **ports and reuses** them, it does not redesign them.

---

## Track A — Sidekick delegation capability

### Step A-1: Sidekick agent skeleton + `Task`→sidekick dispatch smoke test (GATE)
- **Test**:
  - `tests/sidekick-agent.bats`: after `install global` into a sandbox `CLAUDE_HOME`,
    `agents/sidekick.md` is present (installer glob picks it up with zero installer changes);
    frontmatter asserts `model: haiku` and `tools:` is exactly `Read, Write, Edit, Glob, Grep`
    (no `Bash`, no `Task`).
  - **Manual GO/NO-GO gate (documented in the step, not a bats unit):** add `Task` to a single
    heavy agent temporarily and run a real `claude --agent=tdd-developer -p "delegate a trivial
    file-scaffold to the sidekick"` against the installed CLI; confirm the parent dispatches to
    `sidekick` by name and gets a result. If dispatch fails → **STOP Track A**, fall back to
    narrated-only badge (Risk R1), revisit mechanism before A-2.
- **Implement**: `agents/claude-code/sidekick.md` skeleton (frontmatter only + one-line role).
- **Files**: `agents/claude-code/sidekick.md` (new), `tests/sidekick-agent.bats` (new).
- **Commit**: `test(sidekick): assert sidekick agent contract + install wiring` then
  `feat(sidekick): add haiku sidekick agent skeleton`.

### Step A-2: Sidekick prompt body — mechanical allowlist + refuse-if-judgment
- **Test**: `tests/sidekick-agent.bats` (extend): the body contains a mechanical-only allowlist
  section, an explicit "refuse and hand back if the task requires judgment" clause, and a
  forbidden-actions list (no git/CI/migrations/deploys/test-assertions/design).
- **Implement**: fill in `sidekick.md` body per spec OQ-6.
- **Files**: `agents/claude-code/sidekick.md` (modified), `tests/sidekick-agent.bats` (modified).
- **Commit**: `test(sidekick): assert mechanical-only prompt constraints` then
  `docs(sidekick): constrain sidekick to mechanical allowlist`.

### Step A-3: Add `Task` tool to the three heavy agents
- **Test**: `tests/agent-delegation.bats` (new): `tdd-developer.md`, `qa.md`, `architect.md` each
  have `Task` present in their `tools:` frontmatter line; `reviewer.md` and
  `requirements-engineer.md` do **not** (delegation scoped to the 3 MVP agents).
- **Implement**: one-line `tools:` edit adding `Task` to the 3 agents.
- **Files**: `agents/claude-code/{tdd-developer,qa,architect}.md` (modified),
  `tests/agent-delegation.bats` (new).
- **Commit**: `test(agents): assert Task tool scoped to the 3 heavy agents` then
  `feat(agents): grant Task tool to tdd-developer, qa, architect`.

### Step A-4: Per-agent delegation allowlist + parent-review-gate contract
- **Test**: `tests/agent-delegation.bats` (extend): each of the 3 agent bodies contains its
  spec OQ-3 allowlist AND a parent-review-gate clause ("vet sidekick output before accepting;
  emit an accept milestone or a `deleg_reject`").
- **Implement**: add the delegation + review-gate section to each of the 3 agent bodies.
- **Files**: `agents/claude-code/{tdd-developer,qa,architect}.md` (modified),
  `tests/agent-delegation.bats` (modified).
- **Commit**: `test(agents): assert per-agent allowlist + review gate` then
  `docs(agents): add delegation allowlist + parent-review gate`.

### Step A-5: Sentinel-emission contract in the heavy agents (grammar, redacted prefix)
- **Test**: `tests/agent-delegation.bats` (extend): each of the 3 agent bodies documents the
  frozen sentinel grammar and instructs emitting `phase`/`step`/`deleg`/`deleg_reject`/`done`
  milestones; asserts the collision rule is honored — **no literal `@@ANW|` line appears in the
  agent files** (grammar is documented with the redacted prefix per OQ-1).
- **Implement**: add the sentinel-emission section (redacted-prefix grammar) to each agent body.
- **Files**: `agents/claude-code/{tdd-developer,qa,architect}.md` (modified),
  `tests/agent-delegation.bats` (modified).
- **Commit**: `test(agents): assert sentinel-emission contract + no literal prefix` then
  `docs(agents): teach heavy agents to emit milestone sentinels`.

---

## Track B — Live milestone visualization

### Step B-1: Port the spike renderer to `lib/render-stream.sh` + golden regression
- **Test**: `tests/render-stream.bats` (new): pipe a committed fixture sentinel stream into
  `bash lib/render-stream.sh --plain` and assert output is **byte-identical** to a committed golden
  file; include the spike's crux cases — embedded `|` in a two-field `step|ok` free-text, and an
  embedded `|` in a single-field `done` (must render intact, per the spike bug fix).
- **Implement**: port `spikes/sdk-1-renderer/render.sh` to `lib/render-stream.sh`, `source`-ing
  `lib/common.sh` for colors/frames instead of duplicating. No mechanic changes.
- **Files**: `lib/render-stream.sh` (new), `tests/render-stream.bats` (new),
  `tests/fixtures/sdk-1/basic.sentinels` (new), `tests/fixtures/sdk-1/basic.golden` (new).
- **Commit**: `test(render): golden regression for ported renderer` then
  `feat(render): port de-risked spike renderer to lib/render-stream.sh`.

### Step B-2: Renderer arity validation (drop malformed sentinels)
- **Test**: `tests/render-stream.bats` (extend): `@@ANW·|step|run` with no text is **not** rendered
  as `⏺ run`; an unknown event type `@@ANW·|bogus|x` is dropped; neither crashes the renderer.
  (Use the redacted prefix in prose; real fixtures use the literal prefix.)
- **Implement**: add per-event arity guards to `lib/render-stream.sh` (OQ-1 hardening).
- **Files**: `lib/render-stream.sh` (modified), `tests/render-stream.bats` (modified),
  `tests/fixtures/sdk-1/malformed.sentinels` (new).
- **Commit**: `test(render): malformed sentinels are dropped, not mis-rendered` then
  `feat(render): validate sentinel arity, drop malformed lines`.

### Step B-3: Milestones JSONL writer `lib/milestones.sh::append_milestone`
- **Test**: `tests/milestones.bats` (new): `append_milestone` with the OQ-2 fields writes one
  `jq -e .`-valid single-line object to `.anw/specs/<id>-milestones.jsonl`; asserts each field value;
  two calls → two lines (append-only); text with an embedded `|` and quotes is preserved.
- **Implement**: `lib/milestones.sh` with `append_milestone()` (new orchestrator-side writer;
  reuse only confidence.jsonl's field/format conventions).
- **Files**: `lib/milestones.sh` (new), `tests/milestones.bats` (new).
- **Commit**: `test(milestones): append_milestone writes valid JSONL` then
  `feat(milestones): add orchestrator-side milestones JSONL writer`.

### Step B-4: Renderer persists milestones (orchestrator-injected fields)
- **Test**: `tests/render-stream.bats` (extend): run the renderer with
  `AW_SPEC_ID=SDK-1 AW_PIPELINE_STEP=4.2 AW_AGENT=tdd-developer AW_TIER=sonnet` over a fixture that
  includes a `deleg`; assert milestones.jsonl gains lines with those injected fields correct, the
  delegation line has `event=delegation` + `delegated_to=haiku` + `parent_text` set to the active
  milestone.
- **Implement**: wire `lib/render-stream.sh` to call `append_milestone` for each finalized event,
  reading injected context from env; `source lib/milestones.sh`.
- **Files**: `lib/render-stream.sh` (modified), `tests/render-stream.bats` (modified),
  `tests/fixtures/sdk-1/delegation.sentinels` (new).
- **Commit**: `test(render): renderer persists injected milestone fields` then
  `feat(render): append milestones as sentinels are finalized`.

### Step B-5: `agent_tier()` lookup
- **Test**: `tests/pipeline-core-stream.bats` (new): `agent_tier architect`→`opus`,
  `agent_tier qa`→`opus`, `agent_tier tdd-developer`→`sonnet`, `agent_tier sidekick`→`haiku`,
  unknown→default.
- **Implement**: `agent_tier()` in `lib/pipeline-core.sh`.
- **Files**: `lib/pipeline-core.sh` (modified), `tests/pipeline-core-stream.bats` (new).
- **Commit**: `test(pipeline): agent_tier maps agents to tiers` then
  `feat(pipeline): add agent_tier lookup`.

### Step B-6: Extract `run_agent_streamed` — errexit/PIPESTATUS-safe pipe (behavior-preserving)
- **Test**: `tests/pipeline-core-stream.bats` (extend) using a fake `claude` shim on `PATH`
  (passthrough = `cat`, spinner still on): (a) agent stdout is shown; (b) a non-zero shim exit is
  propagated via `${PIPESTATUS[0]}`, logs `AGENT_ERROR`, returns non-zero; (c) a zero exit returns 0
  and logs `AGENT_OK`. Behavior must match today's semantics under `set -euo pipefail`.
- **Implement**: extract `run_agent_streamed` helper; convert `run_claude_agent` to
  `claude … 2>&1 | cat` capturing `${PIPESTATUS[0]}`; keep the existing spinner + audit paths for now.
- **Files**: `lib/pipeline-core.sh` (modified), `tests/pipeline-core-stream.bats` (modified),
  `tests/fixtures/sdk-1/fake-claude.sh` (new).
- **Commit**: `test(pipeline): pipe preserves exit semantics via PIPESTATUS` then
  `refactor(pipeline): stream run_claude_agent through an errexit-safe pipe`.

### Step B-7: Attach renderer + milestones; remove generic spinner; capture debug log
- **Test**: `tests/pipeline-core-stream.bats` (extend) with a fake `claude` emitting sentinels:
  rendered milestones appear live; `.anw/specs/<id>-milestones.jsonl` is populated with injected
  `spec_id`/`pipeline_step`/`agent`/`tier`; non-sentinel lines are suppressed from the live view but
  present in the debug log (AC-8); assert **no** `spinner_start`/`spinner_stop` on the streamed path
  and no leftover feeder/ticker/spinner processes after the run (incl. a shim that dies mid-stream).
- **Implement**: swap the `cat` passthrough for `bash "$RENDER"` with injected env; remove
  `spinner_start`/`spinner_stop` from the streamed path (replace-not-coexist); `tee` the raw stream
  to a debug log (closes the audit gap).
- **Files**: `lib/pipeline-core.sh` (modified), `tests/pipeline-core-stream.bats` (modified).
- **Commit**: `test(pipeline): live render + milestones + suppressed non-sentinel output` then
  `feat(pipeline): live sentinel render replaces generic spinner`.

### Step B-8: Cost/quality summary `scripts/milestones-summary.sh`
- **Test**: `tests/milestones-summary.bats` (new): given a fixture milestones.jsonl with N
  delegations (some rejected), the script reports total delegations, accept vs reject counts, and
  per-agent delegation counts.
- **Implement**: `scripts/milestones-summary.sh` (jq over the JSONL).
- **Files**: `scripts/milestones-summary.sh` (new), `tests/milestones-summary.bats` (new),
  `tests/fixtures/sdk-1/summary.jsonl` (new).
- **Commit**: `test(summary): milestones-summary reports delegation metrics` then
  `feat(summary): add milestones cost/quality summary script`.

### Step B-9 (Integration): end-to-end streamed step on `pipeline_github_feature`
- **Test**: `tests/sdk-1-integration.bats` (new): with a fake `claude` on `PATH` emitting a
  realistic one-step stream (`phase → step run/ok → deleg haiku → step ok "reviewed & accepted" →
  done`), drive the streamed `run_claude_agent` path for one pipeline step and assert:
  (1) live render output present; (2) a complete `.anw/specs/<id>-milestones.jsonl` including the
  delegation **and** its accept milestone; (3) agent exit semantics preserved (success + a forced
  failure case); (4) `scripts/milestones-summary.sh` reports 1 delegation, 1 accept, 0 reject.
- **Implement**: only glue/wiring needed to make the end-to-end path run (no new behavior).
- **Files**: `tests/sdk-1-integration.bats` (new), `tests/fixtures/sdk-1/e2e.sentinels` (new).
- **Commit**: `test(sdk-1): end-to-end streamed step with delegation` then
  `feat(sdk-1): wire live streaming + delegation into github-feature`.

---

## Status checklist

- [x] A-1  Sidekick skeleton + Task dispatch smoke GATE — **GO** (smoke test passed: smoke-parent→Task→sidekick created hello.txt; verified 2026-07-01)
- [x] A-2  Sidekick mechanical-only prompt body
- [x] A-3  Task tool on the 3 heavy agents
- [ ] A-4  Per-agent allowlist + parent-review gate
- [ ] A-5  Sentinel-emission contract (redacted prefix)
- [ ] B-1  Port renderer → lib/render-stream.sh + golden
- [ ] B-2  Renderer arity validation
- [ ] B-3  append_milestone JSONL writer
- [ ] B-4  Renderer persists injected milestone fields
- [ ] B-5  agent_tier lookup
- [ ] B-6  run_agent_streamed errexit/PIPESTATUS pipe (behavior-preserving)
- [ ] B-7  Attach renderer + milestones, remove spinner, debug log
- [ ] B-8  milestones-summary cost/quality script
- [ ] B-9  Integration: end-to-end streamed step with delegation
</content>
