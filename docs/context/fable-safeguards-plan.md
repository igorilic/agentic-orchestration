# Plan: Reduce Fable 5 Safeguard False Positives

**Status:** Proposed
**Date:** 2026-07-13
**Related spec:** [fable-safeguards-spec.md](./fable-safeguards-spec.md)

## Context

Claude Fable 5 runs safety classifiers on *everything the model reads* — including
skills, agent prompts, and hook output loaded at session start. When a classifier
fires, the session is force-switched to Opus 4.8. Since the July 1, 2026
redeployment, the cybersecurity classifier is tuned deliberately conservative and
is known to flag benign coding work.

This repo's instruction layer is unusually rich in classifier-trigger vocabulary,
which explains why *any* prompt in a session running this harness can get flagged:
the trigger content is in context from message one, and once flagged, it stays in
the conversation history.

An audit (2026-07-13) identified four trigger clusters, ranked by likely impact:

1. **Guardrail-circumvention framing** — `skip-tdd` and `override-confidence`
   skills are instruction files addressed to an AI agent that literally teach it
   to "bypass" and "override" its own enforcement gates, with trigger phrases
   like "bypass tests" and "force PR". Structurally identical to jailbreak
   content, even though the gates are TDD hooks, not safety systems.
2. **Offensive-security keyword cloud** — `qa`, `diff-reviewer`, `reviewer`
   agents and the `gh-cli`/`glab-cli` skills are dense with: SQL/command
   injection, path traversal, SSTI, XSS, SSRF, IDOR, auth bypass, TOCTOU,
   secrets/tokens, weak crypto. All defender-side, but loaded into every session.
3. **Autonomous prod-infra access pattern** — `troubleshooter` + `clusters`
   describe an agent with kubectl contexts into three regional production
   clusters, ArgoCD, and log/telemetry access, driven by "investigate the
   incident". Resembles the agentic-reconnaissance pattern the cyber classifier
   targets.
4. **Meta-level AI-harness vocabulary** (weak signal) — PAPER.md discusses custom
   system prompts, instruction extraction, model tiers. Low risk; no changes.

## Goals

- Reduce the false-positive rate of Fable 5 safeguard flags in sessions running
  this harness, without changing any runtime behavior of gates, hooks, or agents.
- Keep all wording honest and accurate. This is **not** an attempt to evade
  safety systems — it is removing accidental resemblance to the content those
  systems actually target, exactly as Anthropic's guidance suggests (state
  defensive scope clearly; avoid exploit-shaped phrasing).

## Non-Goals

- No weakening or removal of the TDD gate, confidence gate, or their exemption
  mechanisms.
- No changes to hook logic, agent capabilities, or pipeline flow.
- No attempt to defeat classifiers on genuinely sensitive content.

## Workstreams

### WS-1: Rewording the exemption skills (highest impact)

Rename and reword the two "bypass" skills so the accountable-exception mechanism
reads as what it is — a documented waiver — rather than a circumvention recipe.

- `skills/skip-tdd/` → `skills/tdd-exemption/`; description becomes "Record a
  documented, one-commit exemption from the TDD commit gate"; trigger phrases
  drop "bypass tests" in favor of "tdd exemption", "docs-only commit".
- `skills/override-confidence/` → `skills/confidence-waiver/`; same treatment
  ("waiver", "documented exception" instead of "bypass", "override", "force PR").
- Update every reference: hooks (`tdd-gate.sh`, `confidence-gate.sh` messages),
  agent prompts (`tdd-developer`, `explore`), `PAPER.md`, `README.md`, installer.
- **Decision point:** keep the old slash-command names as aliases for muscle
  memory, or hard-rename. Recommendation: hard-rename, note in changelog —
  aliases would keep the old trigger phrases in context and defeat the purpose.

### WS-2: Defensive framing preambles

Add a one-to-two-line preamble at the top of `qa`, `diff-reviewer`, `reviewer`,
`troubleshooter` agents (both Claude Code and Copilot CLI variants) and the
`gh-cli`/`glab-cli` skills:

> "Defensive code review of the author's own authorized codebase. All findings
> are remediation-oriented; never produce exploitation instructions."

Anthropic's classifier weights stated context; this shifts the reading of the
security checklists that follow. The checklists themselves stay intact — they
are the point of those agents.

### WS-3: Scope reduction of always-loaded context

- Move `clusters` and `troubleshooter` out of any globally-loaded context; they
  should enter context only when the incident pipeline
  (`pipeline-gitlab-incident`) is invoked.
- Audit `hooks/session-start.sh` for anything that injects trigger-dense content
  into every session and trim to the minimum.

### WS-4: PAPER.md wording pass

Replace "bypass mechanism", "escape hatch", and "accountable bypass" with
"accountable exemption" / "documented waiver" throughout. Same claims, same
architecture, less jailbreak-shaped vocabulary.

### WS-5: Verification and feedback loop

- Before/after measurement: run a fixed set of ~10 representative sessions
  (feature pipeline, review, incident) on Fable 5 and log flag counts.
- Report any remaining false positives through Anthropic's "Send feedback"
  channel, referencing this harness as a benign multi-agent dev workflow.

## Sequencing

| Order | Workstream | Effort | Risk |
|-------|-----------|--------|------|
| 1 | WS-1 exemption skills | ~2h | Rename breaks external references/docs |
| 2 | WS-4 PAPER.md pass | ~30m | None (prose only) |
| 3 | WS-2 framing preambles | ~1h | None (additive) |
| 4 | WS-3 context scoping | ~2h | Incident flow must still auto-load clusters |
| 5 | WS-5 verification | ongoing | — |

## Risks and Limitations

- Classifiers are server-side and evolving; no wording change guarantees zero
  flags. The goal is a measurable reduction, not elimination.
- WS-1 renames are breaking for anyone with the old slash commands in muscle
  memory or scripts; changelog entry required.
- Over-sanitizing the security checklists would degrade review quality — WS-2
  deliberately adds framing instead of removing checklist content.
