# ADR-002 — Sentinel-stream live rendering + real sidekick delegation

- **Status**: Proposed
- **Date**: 2026-07-01
- **Related**: `docs/context/specs/SDK-1-spec.md`, `docs/context/specs/SDK-1-brainstorm.md`,
  `spikes/sdk-1-renderer/FINDINGS.md`

## Context

SDK-1 adds (A) cheap-model "sidekick" delegation and (B) a live, agent-attributed pipeline
transcript. Two structural forks needed a recorded decision because they change orchestrator
behavior and introduce a new pipeline capability with no in-repo precedent:

1. **How agents communicate live progress to the orchestrator**, given that `run_claude_agent`
   (`lib/pipeline-core.sh:225-264`) buffers all stdout to a temp file and only `cat`s it after the
   process exits — there is no live streaming today, and the generic `spinner_start` writes its own
   `\r`-driven frames independently.
2. **How to render `DELEGATED TO SIDEKICK` for real** when all 8 Claude agents lack the `Task` tool
   and there is no working in-repo precedent for parent→subagent dispatch.

## Decision

**Transport — dumb sentinels, orchestrator renders + persists.** Agents print reserved
`@@ANW|`-prefixed sentinel lines to stdout. `run_claude_agent` is restructured into a live pipe
(`claude … 2>&1 | tee debug.log | render-stream`). The renderer (ported from the de-risked spike into
`lib/render-stream.sh`) renders the flat indented stream live **and** appends orchestrator-authored
events to `.anw/specs/<id>-milestones.jsonl`. The orchestrator is the **sole** JSONL writer (it injects
`spec_id`/`pipeline_step`/`agent`/`tier` that the dumb agent does not know); only confidence.jsonl's
field/format conventions are reused, not its agent-side writer.

- Single-field sentinel events (`done`) use the raw post-event-type remainder, never the `f1`/`f2`
  split (spike-found bug). Two-field events keep embedded pipes in the free-text field (spike-verified).
- The generic `spinner_start`/`spinner_stop` is **removed from the streamed path**, not run alongside
  the renderer's active-line spinner — two independent `\r` timers corrupt the same line
  (`FINDINGS.md`).
- The pipe captures `${PIPESTATUS[0]}` as the agent's real exit code and preserves today's
  `AGENT_ERROR`/`AGENT_OK` audit + return-code semantics under `set -euo pipefail`.

**Delegation — real Haiku sidekick, soft-enforced review gate.** A new `agents/claude-code/sidekick.md`
(`model: haiku`; tools `Read, Write, Edit, Glob, Grep` — no `Bash`, no `Task`) does strictly mechanical
sub-work. `tdd-developer`, `qa`, `architect` gain `Task` + a per-agent allowlist. The parent always
vets sidekick output before accepting; this gate stays a **soft, auditable** prompt contract for MVP
(every delegation is followed by an accept milestone or a `deleg_reject`, both recorded in JSONL).

## Consequences

**Positive**
- Live, curated, agent-attributed transcript with a replayable JSONL artifact for free.
- Real model-routing: mechanical work shifts to Haiku; frontier tiers keep reasoning.
- Renderer risk is already retired by the spike; the remaining work is integration.
- Shared `run_agent_streamed` helper positions `run_copilot_agent` for the same fix later.

**Negative / Risks**
- `Task`→sidekick dispatch is unverified in-repo → gated behind an early smoke test (todo A-1); fall
  back to a narrated-only badge if it fails.
- errexit/pipefail exit-code handling is easy to get silently wrong → built as an isolated
  behavior-preserving step (todo B-6) before the renderer is attached.
- The review gate is unenforced by tooling → mitigated by auditability + the existing confidence gate;
  hard enforcement deferred.
- Reserved-prefix collision if an agent prints literal `@@ANW|` text → mitigated by a redaction rule.

## Alternatives Considered

- **Parse raw tool-call telemetry instead of agent-emitted sentinels** — rejected: noisy, not the
  curated bullet style the brainstorm chose; couples the renderer to CLI-internal formats.
- **Keep the generic spinner and add a second renderer spinner** — rejected: two `\r` timers on one
  line corrupt the terminal (spike-proven).
- **Agent writes milestones.jsonl directly (like confidence.jsonl)** — rejected: the agent cannot
  know `spec_id`/`pipeline_step`; the orchestrator must inject run context.
- **Fake the `DELEGATED` badge with no real delegation** — rejected by the brainstorm; build the real
  capability the badge implies.
- **Hard-enforce the review gate in the confidence-gate hook now** — deferred: no precedent, larger
  surface; soft+auditable is sufficient for MVP.
</content>
