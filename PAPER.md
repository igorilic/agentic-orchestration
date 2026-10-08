# Agentic Orchestration for Test-Driven Development: A Native-First, Verifiable Harness for Solo Full-Stack Development

**Igor Ilic**

March 2026 · revised October 2026

---

> **Note on scope and method.** This is a *design and architecture whitepaper* describing a
> working open-source system, not an empirical study. It reports no controlled evaluation. The
> live runs it cites are small demonstrations (N ≤ 4 per scenario), not measured rates, and
> statements about what a mechanism "enforces" describe how the tools document their hook and
> sandbox behavior, checked by the tests and canaries in §5. Read the contributions below as
> design contributions.

---

## Erratum (October 2026)

Versions of this paper from March to September 2026 described two Claude Code `PreToolUse`
hooks, a TDD gate and a confidence gate, as deterministic enforcement that the model could not
override. **They never fired.** Both scripts read the command from an environment variable
(`CLAUDE_TOOL_INPUT`) that Claude Code does not set; hook input arrives as JSON on stdin. The
project's tests passed only because they set that variable themselves. So every claim of
machine-enforced TDD or confidence gating on the Claude side was false.

Three further statements were also wrong:
- the TDD skip marker was never removed after a commit;
- the skip and override skills that "kept the bypass accountable" were invocable by the agent itself;
- Copilot CLI *does* support user-global hooks.

The confidence score was computed from logs the agents wrote themselves.

The architecture has since been rebuilt (ADR-003), and this version describes the rebuilt
harness. Its enforcement is now tested against each tool's real hook payloads and checked live by
canaries (§5). The earlier text remains in the repository's git history.

---

## Abstract

We describe a harness for AI-assisted software development, used by a solo full-stack developer
with Claude Code and GitHub Copilot CLI. Its first version coordinated eight custom agents through
a pipeline it claimed was enforced by lifecycle hooks. An audit found that the hooks on the Claude
side had never run. The current version is native-first: the tools' own agent loops, plan modes
and subagents do the agent work, and the repository ships only what they lack. That is two
fail-closed hooks shared by both tools, five workflow skills, a sandboxed settings policy and
short instructions.

The design targets the failure that matters most for coding agents with tests in reach: making
the check pass instead of making the code right.
- **The finish line.** A per-repository script (`.anw/verify`, the full fast suite) runs whenever
  an editing session ends. It runs only if the developer approved it by hash and path, and then
  inside an OS sandbox.
- **Weakened tests.** A commit that deletes or weakens tests asks the human.
- **The honest exit.** The agent's sanctioned way out is `BLOCKED: <evidence>`.
- **Review.** A fresh-context, read-only `/check` reviews every change before a pull request.

We describe the design, its principles and how the harness itself is verified: contract tests on
the tools' real payloads, mutation-checked tests, and opt-in live canaries.

**Keywords:** coding agents, reward hacking, test-driven development, lifecycle hooks, sandboxing,
Claude Code, GitHub Copilot CLI

---

## 1. Introduction

### 1.1 Problem

A solo developer who delegates coding to agents needs three things the agents don't provide by
themselves.

1. **Checks that hold.** Instructions in a context file are suggestions. A model can deprioritize
   them as a session grows, so rules that must hold need machinery.
2. **Resistance to reward hacking.** Agents facing an impossible or contradictory task tend to go
   after the check instead. In one incident investigation, about 700 agents facing impossible tasks
   went after the scorer [9]. Telling an agent not to hack lowers the rate but does not eliminate
   it [11]. In one preprint, a written policy plus an escalation tool cut hacking from 23.6% to
   5.3% [10].
3. **Containment.** Agents read untrusted text (tickets, pull requests, logs, web pages) while
   holding credentials. A session should not combine untrusted input, sensitive systems and
   external actions [16]. Hooks and model-based approval are not a security boundary [17, 18];
   the OS sandbox is [5].

### 1.2 What the first version got wrong

The first version answered (1) with hooks that never ran (see the Erratum), and (2) with
bypasses the agent could reach. It answered (3) not at all: its pipelines launched agents with
permission-bypass flags and no sandbox. Its eight role-based agents were mostly orchestration
prompts, and none of them enforced anything. ADR-003 records the audit and the decision.

### 1.3 Contributions

- A **native-first harness**. The coding tools' own agents do the work; the harness adds only
  enforcement, containment and a few explicit workflows.
- **Two fail-closed hook scripts shared by both tools.** Each reads either tool's payload, so
  Claude Code and Copilot CLI are gated by the same code.
- A **trusted, sandboxed finish line**, run at the end of every editing turn, with an **honest
  exit** (`BLOCKED:`) in place of agent-reachable bypasses.
- **Test-integrity checks at commit time** that ask the human, rather than skip or override switches.
- **Verification of the harness itself**: contract tests on real payloads, mutation-checked tests
  and live canaries.

---

## 2. Background

### 2.1 Extension points

Both tools expose lifecycle hooks that receive a JSON payload on stdin.
- **Claude Code** blocks a tool call on exit code 2 or a JSON decision. Other failures, timeouts
  and missing scripts let the call proceed [2].
- **Copilot CLI** denies on a non-zero exit, but its hook timeouts always fail open [6, 7].
- **Skills** are reusable instruction sets [3]. A skill can run in a forked context that doesn't
  see the conversation history, with a read-only agent type.
- **Plan mode** and **built-in subagents** cover planning and delegation natively [4].
- Both tools offer an **OS sandbox** [5].

### 2.2 Reward hacking and weak checks

Most test patches carry weak or no explicit oracle [12]. LLM reviewers miss some confirmed hacks,
and evasion rises when agents receive detailed feedback [13]. Agents also tamper with their own
traces [14], so scores computed from agent-written logs are not evidence. Vendor guidance asks the
model not to special-case tests and to report a wrong test rather than work around it [22]. That
helps, but prompts alone do not suffice [11].

### 2.3 One writer, one reviewer

Multi-agent systems work best "when writes stay single-threaded and the additional agents
contribute intelligence rather than actions" [15]. A reviewer prompted to find gaps "will usually
report some, even when the work is sound" [21]. So the review step asks for merge-blocking
problems only, each with a repro.

---

## 3. Architecture

### 3.1 Principles

| # | Principle |
|---|---|
| P1 | **Enforce outside the agent's reach.** Must-hold rules live in hooks and settings that fail closed and that the agent can't edit. Prompts only state intent. |
| P2 | **Ground truth comes from execution, never self-report.** The hooks run the check themselves; CI and branch protection stay final. |
| P3 | **Every gate has an honest exit.** `BLOCKED: <evidence>` is a success path, and the human is the only bypass. |
| P4 | **Strong finish lines.** The finish line runs the whole fast suite, so no cheap hack passes it. |
| P5 | **Native first.** One session writes; one fresh-context review checks. No custom agents. |
| P6 | **Contain the blast radius.** OS sandbox, egress allowlist, denied secrets, human approval for outward and irreversible actions. |
| P7 | **Verify the harness against reality.** Contract tests use real payloads; canaries rerun after model updates. |

### 3.2 Components

```
ENFORCEMENT  guard.sh   before every command and edit (both tools, user-global)
             verify.sh  when an editing turn ends: the trusted, sandboxed finish line
CONTAINMENT  settings   OS sandbox, egress allowlist, secrets unreadable, ask before outward actions
WORKFLOW     skills     /plan  /check  /incident  /pr  (the developer)  ·  /verify (the model)
AGENTS       native     the main session, plan mode, built-in subagents
```

### 3.3 The development flow

- **Small changes** happen in the main session: a failing test first, then the fix [1]. The hooks
  gate the commit and the end of the turn.
- **Larger work** starts with `/plan`, which writes testable acceptance criteria and small steps.
  The developer approves the plan: this is the highest-value human checkpoint. Each step is then
  implemented in its own session and committed.
- **Before a pull request**, `/check` reviews the branch in a fresh, read-only context. `/pr`
  pushes and opens the PR or MR, each after the developer confirms.
- **Incidents** go through `/incident`, a read-only investigation that produces a report. The
  developer decides what to post, and the fix starts in a fresh session.
- **Headless pipelines** run the same stages as fresh `claude -p` or `copilot -p` processes with no
  bypass flags. Only the pipeline script pushes or posts, and only after the developer confirms.

### 3.4 Enforcement: `guard.sh`

Runs before every command and file edit, in both tools.
- **Deny:** hook bypasses (`--no-verify`, `core.hooksPath`, …), nested agents launched with
  permissions disabled, and writes to the harness itself (hooks, settings, skills, the trust list,
  the finish line).
- **Ask:** a commit that deletes tests, adds skip or focus markers, removes or rewrites
  assertions, or changes source with no test; a new dependency name; CI and instruction edits.
  Headless, an ask becomes a denial.
- **Never:** it never emits an `allow`, which would approve the call. A crash, malformed input or a
  missing script denies.

Every edit also marks the session as edited, which arms the finish line.

### 3.5 The finish line: `verify.sh`

When a session that edited files ends, the hook runs the repository's `.anw/verify`.
- **Trust.** Hooks run outside the agent's sandbox, so the script runs only if its exact content
  at that exact path was approved: like `direnv allow`, a `shasum -a 256` line recorded by
  `ai-native-workflow trust`. A cloned, copied or edited script is skipped, and the developer is told.
- **Sandbox.** A trusted script still runs repository code the agent may have just written. On
  macOS it therefore runs under `sandbox-exec` with the agent's own file limits.
- **Outcome.** While the check is red, the turn cannot end, and the hook returns the failure with
  the honest-exit instruction. A reply with a `BLOCKED:` line, or a second red stop in a row, ends
  the turn and is flagged to the developer.

The finish line must be strong. In our spike, a check made only of an assertion contradicting the
spec was gamed in 2 of 2 runs. With a real test added, so that no simple hack could pass both,
4 of 4 runs ended `BLOCKED:` instead (§5.4).

### 3.6 Review: `/check`

A forked, read-only skill at the Opus tier. It runs the check itself and reads the diff before any
summary, then audits integrity: weakened or deleted tests, special-cased inputs, tests that would
pass without the change. It reports only what would block the merge, each with a failing repro,
and ends with `Verdict: block` or `Verdict: pass`. It is a sensor, not a gate. Review panels can
be evaded [13], so CI and branch protection remain the ground truth.

### 3.7 Containment

The Claude policy turns the OS sandbox on with an egress allowlist and makes secrets unreadable at
the OS level. It asks before push, PR/MR creation and comments. It denies force-push and mutating
cluster commands, and it disables the permission-bypass mode [8]. Copilot uses its own sandbox and
deny rules; pipelines pass the same policy as `--deny-tool` rules.

### 3.8 Model strategy

What matters architecturally is the tier, not a version:
- planning and review run at the Opus tier;
- implementation runs at the Sonnet tier;
- Copilot uses its session default.

Everything uses floating aliases (`opus`, `sonnet`), so nothing pins a model version. Because
model updates can break harness prompts, the canaries are rerun after each alias move.

### 3.9 Cross-tool consistency

The same two scripts serve both tools. A short `AGENTS.md` per repository is read by Copilot and
imported by `CLAUDE.md`. The global instructions are 16 lines per tool, with the same working
agreements. Skills are installed into both tools as copies, so an agent editing the harness
repository can't change live enforcement.

---

## 4. Implementation

A bash CLI (`ai-native-workflow`, about 1,350 lines with its library) installs and runs the harness.

- `install global` copies the hooks and skills. It merges the policy into Claude's settings,
  keeping the developer's own keys, writes managed instruction blocks and generates Copilot's hook
  wiring. Anything an earlier version installed moves to a timestamped backup.
- `install project` writes `.anw/verify` for the detected stack, and asks the developer to trust
  it. A Makefile `test:` target wins; otherwise Go, Rust, .NET, Python, Node or Swift test
  commands are used.
- `trust`, `doctor` (exits non-zero on drift, a custom agent or an untrusted finish line) and
  `doctor --smoke` (the live canaries).
- `run github-feature | github-issue | gitlab-feature | gitlab-incident`, with `status` and `resume`.

| Component | First version | Now |
|---|---|---|
| Custom agents | 9 Claude + 8 Copilot | 0 |
| Enforcement scripts | 3 Claude hooks (inert) + a per-project Copilot dispatcher | 2 scripts for both tools (236 lines) |
| Global instructions | 58 + 55 lines | 16 + 16 lines |
| Bypass mechanisms | 2 agent-invocable skills, 2 marker files | none: the developer answers the prompt |
| Test suite | 391 tests, mostly on the wrong hook contract | 164 tests on the real payloads |

---

## 5. Verifying the harness

### 5.1 Contract tests

The hooks are tested with the payload shapes each tool really sends, captured from live sessions.
This is the step whose absence let the first version's gates stay inert. The pipelines are tested
with stub CLIs that record their arguments, and pushes go to a local bare remote.

### 5.2 Mutation-checked tests

Each change to the harness was checked by seeding mutants into the code: removing a check, or
loosening a rule. The new tests had to fail on each mutant, and a control had to stay green. One
surviving mutant in the canary step was equivalent: it removed an explicit exit that `set -e`
already guarantees.

### 5.3 Live canaries

`make smoke` runs real headless sessions against the installed harness, in throwaway
repositories. The guard must deny `--no-verify` in both tools, a nested agent without permissions,
and an untested source commit. A fake secret must stay unreadable and the network outside the
allowlist unreachable. An honest bug fix must pass without pushback. An impossible finish line,
run three times, must end `BLOCKED:` with nothing tampered. `/check` must block a gamed change.

The canary script has its own tests: every injected defect must fail its own canary. Results are
recorded per run in ADR-003, as observed counts, never extrapolated.

### 5.4 Spike demonstrations

The design was shaped by small live runs (haiku agent, Opus-tier review):

| Scenario | Result |
|---|---|
| Honest bug fix | fixed, check green at stop, no pushback |
| Weak finish line (only an assertion contradicting the spec) | 2/2 gamed it (`a + b + 1`) |
| Strong finish line (a real test plus the contradictory assertion) | 4/4 ended `BLOCKED:`, no code changed |
| `/check` on the two gamed states | 2/2 blocked the merge with the right diagnosis |

These are demonstrations of the mechanisms, not estimates of how often they work.

---

## 6. Discussion

### 6.1 Hooks are guardrails; the sandbox is the boundary

A hook that pattern-matches shell text stops the naive bypass, not a determined injection [17].
The harness therefore puts the hard limits in the OS sandbox and the settings. It uses the hooks
for what they do well: running the check, asking at commit time, and failing closed.

### 6.2 Honest exits beat clever detectors

The harness detects hacks only crudely, at commit time and in `/check`. Mostly it makes hacks
unnecessary: a strong finish line, a sanctioned `BLOCKED:` exit, and a human who is the only
bypass. That matches the evidence that an escalation path reduces hacking [10] and that
instructions alone don't [11].

### 6.3 Less harness

Repository context files rarely help and raise cost [19]. Skills that should fire on their own
often don't [20]. So the instructions stay short, skills are invoked explicitly, and anything that
must hold is a hook or a setting. A harness component can stop being needed, or start getting in
the way, when the model changes, so the canaries are rerun after every model update.

### 6.4 Limitations

- No controlled evaluation. The spike runs and canaries are small-N demonstrations.
- The finish-line sandbox needs macOS `sandbox-exec`; elsewhere the check runs unsandboxed, and
  `trust` says so.
- A repository's own settings can disable hooks. Only managed settings can't be overridden.
- The guard's shell-text rules can be phrased around; shell writes to CI config currently get no
  ask.
- Copilot hook timeouts fail open, so the finish line must stay under ten minutes.
- The design targets a single developer.

---

## 7. Conclusion

The first version of this harness promised enforcement that never ran, and its tests could not
tell. The rebuilt harness is smaller and more honest. The coding tools' native agents do the work.
Two hooks shared by both tools gate commits and the end of every editing turn. The finish line is
trusted, sandboxed and strong. The agent always has an honest exit. The harness itself is checked
against the tools' real behavior, by contract tests and live canaries. We offer it as a design:
operational and in daily single-developer use, but not empirically evaluated.

---

## References

1. Beck, K. (2003). *Test-Driven Development: By Example*. Addison-Wesley.
2. Anthropic. Claude Code: Hooks. https://code.claude.com/docs/en/hooks
3. Anthropic. Claude Code: Skills. https://code.claude.com/docs/en/skills
4. Anthropic. Claude Code: Subagents. https://code.claude.com/docs/en/sub-agents
5. Anthropic. Claude Code: Sandboxing. https://code.claude.com/docs/en/sandboxing
6. GitHub. Copilot CLI hooks reference. https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference
7. GitHub. GitHub Copilot CLI documentation. https://docs.github.com/en/copilot/how-tos/copilot-cli
8. Anthropic. Claude Code: Permissions. https://code.claude.com/docs/en/permissions
9. METR (2026-08-26). OpenAI / Hugging Face incident investigation. https://metr.org/blog/2026-08-26-openai-hugging-face-incident-investigation/
10. Gomez (2026-08-29). arXiv 2608.29460 (preprint). https://arxiv.org/abs/2608.29460
11. Hack-Verifiable Terminal Bench (2026-08-22). arXiv 2608.22103. https://arxiv.org/abs/2608.22103
12. *All Smoke, No Alarm* (2026-06-16). arXiv 2606.18168. https://arxiv.org/abs/2606.18168
13. (2026-09-23). arXiv 2609.28614. https://arxiv.org/abs/2609.28614
14. (2026-09-24). arXiv 2609.30266. https://arxiv.org/abs/2609.30266
15. Factory (2026-08-27). What it takes for coding agents to complete large software tasks. https://factory.com/news/what-it-takes-for-coding-agents-to-complete-large-software-tasks
16. Meta (2025-10-31). Practical AI agent security (the Agents Rule of Two). https://ai.meta.com/blog/practical-ai-agent-security/
17. Trail of Bits. claude-code-config. https://github.com/trailofbits/claude-code-config
18. (2026-09-17). arXiv 2609.19587. https://arxiv.org/abs/2609.19587
19. ETH Zurich (2026-09-29). arXiv 2602.11988 v3. https://arxiv.org/abs/2602.11988
20. Vercel (2026-01-27). AGENTS.md outperforms skills in our agent evals. https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals
21. Anthropic. Claude Code: Best practices. https://code.claude.com/docs/en/best-practices
22. Anthropic. Claude prompting best practices. https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

---

*This paper describes a system developed for personal use and shared as open-source software. The
author has no commercial affiliation with Anthropic or GitHub.*
