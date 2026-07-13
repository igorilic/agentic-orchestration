# SDK-1 — Sidekick model-routing + live pipeline visualization

> Brainstorm capture. Status: **converged → ready for `/plan`**.
> Date: 2026-06-30. Origin: `/brainstorm "visualization of the pipeline and agentic work"`,
> inspired by a "Model Routing Example" card (frontier models + cheaper sidekick, with
> per-step actions and `DELEGATED TO SIDEKICK` badges).

## One-line summary

Add a **real cheap-model delegation capability** to the agent pipeline (heavy agents hand
mechanical sub-work to a Haiku "sidekick" subagent), and **visualize the whole pipeline live
in the terminal** as a flat, streaming, agent-attributed action transcript — including the
delegations.

## What this is (and what it became)

The request started as *just a visualization* of the pipeline. During elicitation it grew a
second, larger half: the reference image's signature element — `DELEGATED TO SIDEKICK` — has
**no referent in the current pipeline** (it is sequential, one tier per agent; `tdd-developer`
and `qa` don't even have a Task/Agent tool). Rather than fake the badge, the decision was to
**build the real capability** it implies. So SDK-1 is two stacked builds:

1. **Sidekick delegation** — a genuine new pipeline capability (the bigger build).
2. **Live pipeline visualization** — renders the pipeline, including the new delegations.

This is the actual "model routing" thesis: expensive models for hard reasoning, cheap models
for grunt work.

---

## Converged decisions

Each row is a fork that was explicitly decided during the brainstorm.

| # | Decision point | Chosen | Why |
|---|----------------|--------|-----|
| 1 | **Medium** | **Live CLI render** | Renders in the terminal *as agents run* (real telemetry, streaming). Best fit for a CLI-driven orchestrator; shows agentic work happening live. |
| 2 | **Granularity** | **Full action stream** | Match the image's inner-bullet detail — every meaningful inner action per agent, not just coarse phase boundaries or verdicts. |
| 3 | **Action source** | **Agent-emitted milestones** | Agents print explicit, clean progress markers → output reads like the image's curated bullets, not a noisy raw tool-call dump. Cost: agent definitions must emit markers. |
| 4 | **Data flow** | **Hybrid (sentinel → orchestrator)** | Agents stay *dumb* (print a sentinel line to stdout). The orchestrator — which already wraps every subprocess with a spinner — is the **single** thing that parses, renders live, AND appends structured events to `.anw/specs/<id>-milestones.jsonl`. CLI-agnostic; replayable artifact for free. |
| 5 | **Visual style** | **Flat indented stream** | `▸ agent · tier` header lines, `⏺` milestone bullets, active line shows spinner + elapsed, `✓` on completion. No live box redraw (fragile in bash at width/resize). Matches existing `▸`/`⏺`/`✓` aesthetic. |
| 6 | **Delegation semantics** | **Build real sidekick delegation** | Don't fake the badge. Heavy agents actually dispatch mechanical sub-tasks to a cheaper Haiku sidekick; parent reviews the result (the image's "Reviewed the sidekick's changes"). |
| 7 | **Delegation policy** | **Fixed mechanical allowlist** | Sidekick may only: scaffold files from templates, apply lint/format/type-fix output, generate fixtures & mocks, mechanical find-replace. Parent (Opus/Sonnet) **always** owns reasoning/tests/review and **vets sidekick output before accepting**. Predictable, gate-safe. |
| 8 | **MVP scope** | **All Claude heavy agents** | Roll the sidekick out to `tdd-developer` + `qa` + `architect` (each with its own allowlist) on the GitHub/Claude pipeline, with orchestrator render + JSONL persist. |

---

## Architecture (as decided)

```
agent (claude --agent=… -p)
   │  prints dumb sentinel lines to stdout, e.g.
   │     ▸▸M | Wrote failing test | status=done
   │     ▸▸M | Implemented ClusterBatch path | delegated=haiku
   │     ▸▸D | sidekick · Haiku: scaffolded boilerplate
   ▼
orchestrator (lib/pipeline-core.sh — already wraps each subprocess)
   ├─ parses sentinels  ──►  renders LIVE (flat indented stream)
   │                              ▸ tdd-developer · Sonnet
   │                                ⏺ Wrote failing test
   │                                ⏺ Implemented ClusterBatch path  [DELEGATED]
   │                                    ↳ sidekick · Haiku: scaffolded boilerplate
   │                                ⠙ Running lint & type checks (0m12s)
   └─ appends structured events ──► .anw/specs/<id>-milestones.jsonl
                                       {ts, agent, tier, text, delegated, status, ...}
   (non-sentinel agent stdout is suppressed from the live view / kept in audit.log)
```

### Delegation mechanism
- Heavy agents (`tdd-developer`, `qa`, `architect`) gain a **Task/Agent tool** in their
  frontmatter (they currently lack it) and a **`sidekick` agent definition** (Haiku tier)
  scoped to the mechanical allowlist.
- When a parent delegates, it emits a `[DELEGATED]` parent milestone + a nested
  `↳ sidekick · Haiku: …` line via the same sentinel channel — so the orchestrator's existing
  parser handles nesting; no new transport.
- **Guardrail:** delegation must not bypass TDD/quality gates. Parent reviews & accepts/rejects
  sidekick output before continuing. (Maps to a real "Reviewed the sidekick's changes" step.)

### Why this fits the existing system (from the runtime scan)
- Orchestrator is **pure bash** (`ai-native-workflow` + `lib/*.sh`); agents run as opaque
  subprocesses; zero npm/pip deps. The hybrid sentinel approach needs **no new runtime** — just
  stdout parsing + line rendering, consistent with the current spinner/ANSI helpers.
- A structured telemetry pattern already exists (`.anw/specs/<id>-confidence.jsonl`); the new
  `…-milestones.jsonl` mirrors it.
- Model tiers already live in each agent's YAML frontmatter.

---

## MVP scope

**In:**
- `sidekick` agent (Haiku) + the mechanical allowlist contract.
- `tdd-developer`, `qa`, `architect` each: gain Task tool, per-agent allowlist, emit
  milestone + delegation sentinels, parent-review gate.
- Orchestrator: sentinel parser + flat-indented live renderer + spinner on active line.
- Persist `.anw/specs/<id>-milestones.jsonl`.
- Target the **GitHub / Claude Code** pipeline (`pipeline_github_feature`).

**Deferred (fast-follows):**
- GitLab / **Copilot** pipeline (needs verifying copilot passes agent stdout sentinels through).
- **Replay / status** command that re-renders a past run from the JSONL + embeds it in the
  Obsidian session report.
- A **whitepaper figure** generated from a real run's JSONL (the original viz ask; now a
  byproduct of persistence — note the PAPER is a design whitepaper, keep it illustrative).
- Sidekick for `reviewer` / `requirements-engineer` (mostly reasoning, little mechanical work).
- Live "collapse-to-card" visual treatment (was considered, rejected for MVP in favor of flat).

---

## Open questions for `/plan` (architect to nail)

1. **Sentinel grammar** — exact prefix/format for milestone vs delegation lines, how `status`
   (running/done/ok/fail) and `delegated=<tier>` are encoded, and how to avoid collisions with
   normal agent output.
2. **JSONL schema** — final field set for `…-milestones.jsonl` (ts, agent, tier, parent/child,
   text, delegated, status, step). Reuse confidence.jsonl conventions.
3. **Per-agent allowlists** — concrete delegatable task list for `tdd-developer` vs `qa` vs
   `architect` (they differ: architect scaffolds plan/spec files; qa generates fixtures/probes;
   tdd scaffolds impl boilerplate + applies fixes).
4. **Parent-review gate** — how acceptance/rejection of sidekick output is enforced and recorded
   (and how a rejected delegation renders).
5. **Renderer details** — spinner-on-active-line behavior, tier badge styling/colors
   (Opus/Sonnet/Haiku), nesting indentation, behavior under non-TTY / piped output.
6. **Sidekick agent definition** — tools, model (`haiku`), and prompt constraints to keep it
   strictly mechanical.
7. **Cost/quality validation** — how to confirm delegation actually saves cost without
   regressing quality (the parent-review gate is the safety net; consider a metric in the JSONL).

---

## Recommended next track

**`/plan SDK-1`** — this is production-ready, real-capability work with TDD implications
(new tools, new agent, orchestrator changes, quality gates). It should go through
`architect → tdd-developer → qa → reviewer`. Given the two-part scope, the architect may split
it into two spec/todo tracks: **(A) sidekick delegation capability** and **(B) live milestone
visualization**, with B depending on A's sentinel/delegation events existing.
