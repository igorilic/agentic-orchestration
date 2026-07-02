# SDK-1 — Sidekick model-routing + live pipeline visualization (Spec)

> Source: `docs/context/specs/SDK-1-brainstorm.md` (converged) + `spikes/sdk-1-renderer/FINDINGS.md` (completed spike).
> ADR: `docs/decisions/ADR-002-sentinel-stream-and-sidekick-delegation.md`
> Driver: architect → tdd-developer.
> Two tracks: **A) sidekick delegation capability**, **B) live milestone visualization** (B renders/persists the events A emits).

---

## Problem Statement

The pipeline is sequential and opaque: `run_claude_agent` buffers an agent's entire
stdout to a temp file, blocks on a generic spinner, then `cat`s the whole file after the
process exits (`lib/pipeline-core.sh:225-264`). There is **no live view** of what an agent
is doing, and there is **no cheap-model delegation** — every agent runs one tier end to end,
so the reference-image element `DELEGATED TO SIDEKICK` has no referent in the system today
(all 8 Claude agents lack the `Task` tool). SDK-1 builds the real capability the badge implies
and renders it live.

## Context

- Orchestrator is pure bash (`ai-native-workflow` + `lib/*.sh`); agents run as opaque
  subprocesses; zero npm/pip deps. `set -euo pipefail` is set globally (`ai-native-workflow:25`).
- A structured-telemetry precedent exists: `.anw/specs/<id>-confidence.jsonl`. **Correction from
  the spike:** that file is written by the *agent itself* (a `jq` step in `architect.md:64-82`),
  not the orchestrator. Only its **field/format conventions** transfer to milestones; the
  orchestrator-side writer is new code with no in-repo precedent.
- The renderer mechanics are **already de-risked** by the spike (`spikes/sdk-1-renderer/render.sh`,
  verified byte-identical to `SAMPLE-OUTPUT.txt`, clean teardown on abrupt producer death,
  bash-3.2-safe FIFO/ticker spinner, non-TTY fallback). SDK-1 **reuses** those mechanics; it does
  not re-litigate them.
- Colors/spinner frames in the spike are byte-identical to `lib/common.sh:8-16` and
  `lib/pipeline-core.sh:150`; production code `source`s `lib/common.sh` rather than duplicating.
- MVP targets the **GitHub / Claude** pipeline only: `pipeline_github_feature`
  (`lib/pipelines.sh:358-544`).

### What the spike already settled (do NOT redo)

| OQ | Question | Spike status (cite `FINDINGS.md`) |
|----|----------|------------------------------------|
| 1 | Sentinel grammar | **Partially settled.** `\|`-split is safe for genuinely-2-field events with embedded pipes in the free-text field (verified). It is **not** safe for single-field events — a `done`-event embedded-`\|` truncation bug was found + fixed; use the raw post-evtype remainder (`rest`), never `f1`/`f2`, for single-field events. Prefix-collision is real but low-probability. |
| 5 | Renderer details | **Substantially settled.** Spinner/cursor/teardown verified clean under normal completion and abrupt producer death; tier coloring implemented & aesthetically matched; single-level nesting + stacked consecutive delegations verified; non-TTY output deterministic. Coexist-vs-replace question answered: **replace** the generic spinner, do not coexist. |

The remaining OQs (2, 3, 4, 6, 7) are resolved below by design decision.

---

## Proposed Solution

Agents print **dumb sentinel lines** to stdout. The orchestrator restructures `run_claude_agent`
into a **live pipe** (`claude … 2>&1 | render-stream`) where the renderer (ported from the spike)
(a) renders the flat indented stream live and (b) appends orchestrator-authored structured events
to `.anw/specs/<id>-milestones.jsonl`. Heavy agents (`tdd-developer`, `qa`, `architect`) gain the
`Task` tool and delegate mechanical sub-work to a new Haiku `sidekick` agent, narrating each
delegation via the same sentinel channel; the parent always reviews sidekick output before
accepting.

```
agent (claude --agent=… -p)  ──prints sentinels to stdout──►  orchestrator pipe
   @@ANW|phase|tdd-developer|sonnet                              │
   @@ANW|step|run|Wrote failing test                             ├─ render-stream:
   @@ANW|step|ok|Wrote failing test                              │    live flat stream  (TTY)
   @@ANW|deleg|haiku|scaffolded ClusterBatch boilerplate         │    + append_milestone → JSONL
   @@ANW|step|ok|Reviewed & accepted sidekick output             │
   @@ANW|done|Step 3 complete                                    ▼
                                              .anw/specs/<id>-milestones.jsonl
```

---

## Decisions on the 7 open questions

### OQ-1 — Sentinel grammar (spike-anchored)

- **Reserved prefix** `@@ANW|`, field separator `|`. Non-sentinel lines are discarded from the
  live view.
- **Event types** (agent-emitted): `phase`, `step`, `deleg`, `deleg_reject`, `verdict`, `done`.
  Reserved internal-only tokens (renderer machinery, never emitted by agents): `__TICK__`, `__EOF__`.
- **Two-field events** — `phase|<agent>|<tier>`, `step|<status>|<text>`, `deleg|<tier>|<text>`,
  `deleg_reject|<tier>|<text>`, `verdict|<band>|<score>`: short field first, free-text field is
  `"${payload#*|}"` (everything after the first remaining `|`). Embedded `|` in the free-text field
  is **safe** (spike-verified).
- **Single-field events** — `done|<text>`: text is the **raw remainder after the event type**
  (`rest`), **never** `f1`/`f2` (spike bug fix). New single-field event types MUST use `rest`.
- **`status`** ∈ `run | ok | fail`. **`delegated`** is expressed as a `deleg` event carrying the
  sidekick `<tier>` (haiku); the parent's own milestone is finalized `[DELEGATED]` by the renderer.
- **Collision avoidance (decision: keep `@@ANW|`, option (a) from FINDINGS):** accept the residual
  low-probability collision risk and add a hard rule to every agent prompt: *never print a literal
  `@@ANW|…` example line in agent-visible output; when documenting the grammar, redact the prefix
  (write it as `@@ANW·|` or fenced as "(reserved prefix)").* No lower-collision re-encoding for MVP.
- **Arity validation (decision beyond the spike):** the production renderer drops malformed
  sentinels (unknown event type; `step`/`phase`/`deleg`/`deleg_reject`/`verdict` missing their
  free-text/second field) instead of mis-rendering the status keyword as text (spike gap #1). Dropped
  sentinels go to the debug log, not the live view. Orphan `deleg`/`deleg_reject` (spike gaps #3/#4)
  render gracefully as-is (accepted; the parent contract always emits `step|run` before `deleg`).

### OQ-2 — Milestones JSONL schema

- Path `.anw/specs/<id>-milestones.jsonl` (gitignored, alongside confidence.jsonl). **Orchestrator
  is the sole writer** via a new `append_milestone()` helper in `lib/milestones.sh` — this is new
  code; only confidence.jsonl's *conventions* (ISO-8601 UTC `ts`, one JSON object per line,
  append-only, `jq -n`-built) are reused.
- One object per finalized sentinel event. Fields:

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `ts` | string | orchestrator | ISO-8601 UTC |
| `event` | string | sentinel | `phase｜milestone｜delegation｜delegation_reject｜verdict｜done` |
| `spec_id` | string | orchestrator | pipeline id (agents don't know it — the key reason the orchestrator writes) |
| `pipeline_step` | string | orchestrator | e.g. `4.2` from `save_state` |
| `agent` | string | orchestrator | current agent name |
| `tier` | string | orchestrator | parent tier for milestones; sidekick tier for delegations |
| `status` | string｜null | sentinel | `run｜ok｜fail` for milestone events; null otherwise |
| `text` | string | sentinel | free-text field |
| `delegated_to` | string｜null | sentinel | sidekick tier on delegation events; null otherwise |
| `parent_text` | string｜null | orchestrator | active milestone text a delegation hangs under; null otherwise |

`spec_id`, `pipeline_step`, `agent`, `tier`, `parent_text` are injected by the orchestrator (it
knows run context the dumb agent does not); `event`, `status`, `text`, `delegated_to` come from the
parsed sentinel.

### OQ-3 — Per-agent delegation allowlists

Parent (Opus/Sonnet tier) **always** owns reasoning, test design/assertions, review, and the
accept/reject decision, and **vets sidekick output before accepting**. Sidekick may only do:

| Agent | Delegatable to sidekick (mechanical) | Parent keeps (reasoning) |
|-------|--------------------------------------|--------------------------|
| `tdd-developer` | scaffold impl/test file boilerplate from templates; apply formatter/linter/type-fix edits; generate fixtures, mocks & stub data; mechanical find-replace / rename | RED test **assertions**, logic, GREEN decisions, refactor choices |
| `qa` | scaffold throwaway probe skeletons; generate boundary-value input tables/fixtures; mechanical test-data generation | what to probe, pass/fail judgment, security reasoning, the adversarial hunt |
| `architect` | scaffold spec/todo/ADR file skeletons from the standard section templates; generate boilerplate headers & the status-checklist table | the design, step decomposition, AC authoring, risk analysis |

`reviewer` and `requirements-engineer` get **no** sidekick (mostly reasoning) — deferred.

### OQ-4 — Parent-review gate enforcement (decision: soft contract, auditable)

- **MVP keeps the gate a soft, prompt-level behavioral contract** — consistent with sibling
  unenforced rules already in the codebase (e.g. `architect.md:87-89` "Bash is READ-ONLY" has no
  tooling gate). No new hard tooling gate in MVP.
- **But it is observable/auditable via the sentinel channel:** every `deleg` MUST be followed by
  the parent either (a) emitting a milestone narrating its review and accepting (`step|ok|Reviewed
  & accepted sidekick output`) or (b) emitting `deleg_reject|<tier>|<reason>`. Both land in
  milestones.jsonl, so a human — or a future hard gate — can audit that every delegation was vetted.
- **Rendering already settled by the spike:** accept → parent bullet finalized `[DELEGATED]` + `↳`
  nested line; reject → `❌ sidekick · <tier>: <reason>`.
- **Flagged for the user:** hard enforcement (teaching the gate into the confidence-gate hook) is
  **deferred** and listed under Risks/Out of Scope; approve the soft-contract choice before build.

### OQ-5 — Renderer details (spike-anchored)

- **Replace, do not coexist:** remove `spinner_start`/`spinner_stop` from the streamed
  `run_claude_agent` path; the renderer owns the single active-line spinner
  (`FINDINGS.md` "Spinner conflict — must replace, not coexist").
- **Ship the renderer as a standalone script** `lib/render-stream.sh`, invoked as the downstream of
  the pipe (`claude … 2>&1 | bash "$_ANW_SCRIPT_DIR/lib/render-stream.sh" …`). Standalone keeps the
  renderer's own FIFO/ticker/EXIT-trap machinery isolated from the orchestrator's
  `enable_pipeline_error_trap` traps — a sourced function's EXIT trap would collide.
- **`source lib/common.sh`** for colors/frames (byte-identical per spike); do not duplicate.
- **Tier colors:** Opus = MAGENTA, Sonnet = CYAN, Haiku = GREEN, other = BOLD (from the spike's
  `tier_color`).
- **Nesting:** single level only (no delegation-of-a-delegation). Documented constraint; sidekick
  has no `Task` tool, which structurally enforces it.
- **Non-TTY / piped:** plain deterministic output, no ANSI, `run` steps buffered until finalized
  (spike-verified).

### OQ-6 — Sidekick agent definition

- New `agents/claude-code/sidekick.md`: `name: sidekick`, `model: haiku`. Installer needs **zero**
  changes (`install_global_agents` globs `agents/claude-code/*.md`, `lib/install-global.sh:601`).
- **Tools:** `Read, Write, Edit, Glob, Grep` — **no `Bash`, no `Task`.** No Bash keeps it gate-safe
  (it can never run git/CI/migrations/deploys); no Task structurally prevents recursive delegation.
  Running formatters/linters (needs Bash) stays with the parent, which hands the sidekick the
  resulting edits to apply.
- **Prompt constraints:** strictly mechanical; must not author test assertions, make design/logic
  decisions, or judge correctness; must return the artifact for parent review; must **refuse and
  hand back** if a task requires judgment.
- **Sentinels are emitted by the PARENT, not the sidekick.** The sidekick runs *inside* the parent's
  Claude turn — its stdout is not separately piped to the orchestrator. The parent narrates the
  delegation by emitting the `deleg` / `deleg_reject` sentinel to its own stdout (which is the stream
  the orchestrator pipes).

### OQ-7 — Cost/quality validation (decision: derive from JSONL)

- **Quality safety net** = the parent-review gate (OQ-4) + the existing confidence gate (unchanged).
  Acceptance: on a delegated run the affected test suite stays green and the confidence verdict does
  not regress versus a non-delegated baseline of the same step.
- **Cost proxy** = count of mechanical tasks shifted to Haiku, derived from milestones.jsonl by a new
  `scripts/milestones-summary.sh` reporting: total delegations, accept vs reject count, per-agent
  delegation counts. No dollar-cost measurement in MVP (deferred). This is a validation *approach*,
  not a hard metric.

---

## Acceptance Criteria (testable)

- **AC-1** — Sentinel grammar frozen: a documented parser renders `phase｜step｜deleg｜deleg_reject｜
  verdict｜done`; embedded `|` in a two-field event's free-text renders intact; a single-field `done`
  with an embedded `|` renders intact (spike regression preserved).
- **AC-2** — Malformed sentinels (unknown event type, or a field-short `step`/`phase`/`deleg`/
  `verdict`) are dropped from the live view rather than mis-rendered as `⏺ run`.
- **AC-3** — `lib/render-stream.sh --plain` on a fixture stream is byte-identical to a committed
  golden file (non-TTY determinism).
- **AC-4** — `append_milestone()` writes exactly one valid single-line JSON object per call to
  `.anw/specs/<id>-milestones.jsonl` with the OQ-2 field set; N calls → N lines (append-only).
- **AC-5** — The renderer, given orchestrator-injected `spec_id`/`pipeline_step`/`agent`/`tier`,
  persists each finalized event to milestones.jsonl with those injected fields correct.
- **AC-6** — `run_claude_agent` streams live through the pipe; the agent's real exit code is
  propagated via `${PIPESTATUS[0]}` (not the renderer's); a non-zero agent exit still logs
  `AGENT_ERROR` and returns non-zero (today's error semantics preserved under `errexit`/`pipefail`).
- **AC-7** — On the streamed path the generic `spinner_start`/`spinner_stop` no longer runs; no
  leftover spinner/feeder/ticker processes remain after a run (incl. abrupt agent death).
- **AC-8** — Non-sentinel agent stdout is suppressed from the live view but captured to a debug log
  (closes the audit-gap the spike flagged).
- **AC-9** — `sidekick.md` exists with `model: haiku` and tools exactly `Read, Write, Edit, Glob,
  Grep` (no `Bash`, no `Task`); the installer glob copies it with zero installer changes.
- **AC-10** — `tdd-developer`, `qa`, `architect` each carry `Task` in `tools:` and a documented
  delegation allowlist + parent-review-gate + sentinel-emission contract in their bodies.
- **AC-11** — A live `Task`→`sidekick` dispatch smoke test against the installed Claude CLI succeeds
  before any downstream step depends on delegation (GO/NO-GO gate).
- **AC-12** — `scripts/milestones-summary.sh` on a fixture JSONL reports total delegations,
  accept/reject counts, and per-agent delegation counts.
- **AC-13** — `sidekick.md`'s prompt BODY (OQ-6) contract enumerates five required,
  independently-testable clauses — mechanical-only allowlist (a closed set), refuse-if-judgment,
  forbidden-actions list, write-path scope (never `.git/` internals, CI/CD or workflow files, or
  secret/credential files outside what the parent explicitly named), and no-destructive-overwrite
  (never truncate/overwrite an existing file's contents unless the parent named that exact file and
  supplied the replacement content) — and each clause MUST be asserted by its own **section-scoped**
  test (extracting only the lines under that clause's `## ` heading, per `tests/sidekick-agent.bats`'s
  `section()` helper) rather than a body-wide grep, so content in one section can never satisfy
  another section's assertion. Each such test is additionally proven **mutation-resistant**: a
  mutant with that section's content gutted (heading kept, body removed) from an otherwise-real copy
  of the file must fail the assertion.

## Technical Design

- **New files:** `agents/claude-code/sidekick.md`, `lib/render-stream.sh`, `lib/milestones.sh`,
  `scripts/milestones-summary.sh`, plus test fixtures/golden under `tests/fixtures/sdk-1/`.
- **Modified files:** `lib/pipeline-core.sh` (`run_claude_agent` → streamed pipe; extract shared
  `run_agent_streamed`), `agents/claude-code/{tdd-developer,qa,architect}.md` (Task tool + contracts).
- **Streaming pipe (the crux, `run_claude_agent`):**
  `claude … 2>&1 | tee "$debug_log" | bash "$RENDER" …` under `errexit`/`pipefail` — capture
  `${PIPESTATUS[0]}` as the agent exit code, preserve the `AGENT_ERROR` audit path and return code.
  Extract a shared `run_agent_streamed` helper so the deferred `run_copilot_agent`
  (`lib/pipeline-core.sh:183-223`, a near-duplicate) reuses it later.
- **Tier resolution:** `agent_tier()` maps agent→tier (architect/qa=opus, tdd-developer/reviewer=
  sonnet, sidekick=haiku; unknown→default) so the orchestrator injects the correct `tier`.

## Risks

- **R1 (highest) — `Task`→sidekick dispatch is UNVERIFIED in-repo.** No agent uses `Task` today. Gate
  the whole delegation half behind the A-1 smoke test; if it fails, fall back to a narrated-only badge
  and defer real delegation. (`FINDINGS.md` sidekick notes.)
- **R2 — errexit/pipefail exit-code landmine.** Converting to a pipe makes `$?` the renderer's code;
  a failing `claude` may already trip the global `ERR` trap before the old error block runs. Handle
  with `${PIPESTATUS[0]}` + explicit guarding; B-track builds this as an isolated behavior-preserving
  step first.
- **R3 — Parent-review gate is soft (unenforced).** A misbehaving parent could accept bad sidekick
  output. Mitigated by auditability (OQ-4) + existing confidence gate; hard enforcement deferred.
- **R4 — Prefix collision** if an agent prints literal `@@ANW|` example text. Mitigated by the
  redaction rule (OQ-1); residual risk accepted for MVP.

## Out of Scope (deferred fast-follows)

- GitLab / **Copilot** pipeline + `run_copilot_agent` streaming (factor the shared helper now; wire
  later).
- Replay / status re-render from JSONL; Obsidian session-report embedding.
- Whitepaper figure from a real run (illustrative only — PAPER is a design whitepaper).
- Sidekick for `reviewer` / `requirements-engineer`.
- **Hard** enforcement of the parent-review gate (confidence-gate hook integration).
- Dollar-cost measurement; multi-level delegation nesting.
</content>
</invoke>
