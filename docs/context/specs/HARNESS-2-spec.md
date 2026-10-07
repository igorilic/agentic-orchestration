# HARNESS-2 — Native-first, minimal, verifiable harness (Claude Code + Copilot CLI)

> Status: **Proposed, rev 2** (2026-10-07). **No custom agents**: the native harnesses do the agent work. This repo ships 2 hooks, 5 workflow skills, settings and instructions.
> Todo: `HARNESS-2-todo.md` · Spike and proof: `spikes/harness-2/` (`PROOF.md`, hooks, skills, instructions, config, 52 contract tests, live-run evidence)
> Research window: **2026-08-01 → 2026-10-07**; older sources are marked *OLDER (date)*.
> No controlled evaluation of this harness exists. §6 reports small live demonstrations, not effect sizes.

---

## 1. Problem

The harness relies on deterministic enforcement: "rules that must hold are hooks, not prompts" (PAPER §3.1).
**On the Claude side that enforcement has been a no-op.** Both gates read `CLAUDE_TOOL_INPUT`, which Claude Code
never sets; hook input arrives as JSON on stdin. The bats suite stayed green because it injected the env var
itself ([E1–E2](../../../spikes/harness-2/PROOF.md)). Around that gap:

1. **Security.** Pipelines run agents with bypass flags and no sandbox. Those agents read untrusted tickets, PRs and logs while holding gh, glab, az and production kubectl credentials, with open egress. The installed `session-start.sh` **executes code from any opened repo** (E3d).
2. **Reward hacking.** Every bypass is reachable by the agent:
   - `/skip-tdd` and `/override-confidence` are model-invocable;
   - `.tdd-skip` is never cleared;
   - the confidence score is computed from the agents' own logs;
   - nothing protects tests, hooks or settings.
3. **Weight.**
   - 9 custom agents, 32% of whose text is orchestration plumbing;
   - two competing methodologies;
   - 103 off-task MCP tools, including Gmail send and Drive share;
   - an installed copy that has drifted from the repo.

**Rev 2 drops custom agents entirely**, for three reasons:
- every role has a native equivalent in both tools (§3.9, PROOF E10);
- the role prompts were never what enforced quality (E1–E2);
- Copilot agent files forced the last pinned model versions.

**Goal:** the smallest harness that is actually enforced.
- The native agent loop, plan mode and built-in subagents do the work.
- 2 fail-closed hooks and the OS sandbox enforce.
- 5 skills you invoke carry the procedures.
- Every claim is proven by a contract test or a live canary.

---

## 2. Audit of the current harness (evidence in `spikes/harness-2/PROOF.md`)

| Sev | Finding | Proof |
|---|---|---|
| 🔴 | Claude TDD and confidence gates never fire (env-var contract) | E1, E2 |
| 🔴 | Installed `session-start.sh` `source`s `.context/.pipeline-state` from the opened repo | E3d (probe created `PWNED`) |
| 🔴 | Pipelines use bypass flags; no sandbox; open egress; prod kube contexts with `kubectl:*` allowed | E3e, E3j, E6, E7 |
| 🔴 | Read-deny is bypassable without a sandbox: an obfuscated `python3` read printed the secret | E6 |
| 🟠 | Agent-reachable bypasses (`skip-tdd` / `override-confidence` invocable and preloaded; `.tdd-skip` never cleared) | E3a, E3b |
| 🟠 | Confidence score built on self-reports; agents can and do tamper with their own traces (§3.3) | E3c |
| 🟠 | Copilot: 350 stored approvals (`sudo`, `bash`, `curl`, `kubectl`, `git push`, …); polluted `allowedUrls` | E3i |
| 🟠 | Copilot dispatcher prints `allow` for every non-gated tool. In both tools' hook schemas, `allow` approves the call | E9 |
| 🟡 | Troubleshooter reads untrusted logs/tickets *and* posts to Jira (Rule of Two) | E3f |
| 🟡 | Drift: repo ≠ installed (all agents, hooks, paths); 17 duplicate `.bak` skills; shadowing commands | E3g, E3h, E3k |
| 🟡 | Context: 103 deferred off-task MCP tools, 22 agents, 45+ skills, two methodologies | E8 |
| 🟡 | Docs claim behavior that isn't true (auto-cleared `.tdd-skip`; "Copilot has no user-global hooks") | E3a, E9 |

---

## 3. Research digest — mapped to your flow

### 3.1 Plan
- **Plan approval is the highest-value human checkpoint** ("move [feedback] closer to the decision it is informing").
  - [Laycock, *Code review*, martinfowler.com, 2026-09-02](https://martinfowler.com/rachels-ramblings/code-review.html)
- Spec-first pays off on **3+ file** changes and not on 1–2 file fixes, refactors or bug fixes. This is a vendor benchmark; treat it as weak evidence.
  - [Uvik, 2026-09-24](https://uvik.net/spec-driven-development-benchmark/)
- Keep phases that share context in one conversation. Anthropic advises preferring the main conversation when "planning, implementation, and testing" share significant context.
  - [Claude Code docs: subagents](https://code.claude.com/docs/en/sub-agents)
- "Define completion before starting."
  - [OpenAI, *Rethinking skills and prompts for GPT-6 Astra*, ~2026-09](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
- → **Plan in the main session (plan mode plus a `/plan` skill), and only for bigger work. No planner agent.**

### 3.2 Implement
- **Impossible or contradictory tasks drive hacking.**
  - Attempted reward hacks were **3–6× higher** on impossible tasks, made worse when told not to ask for clarification. [Anthropic system card, current Opus tier, 2026-09-22](https://www.anthropic.com/claude-opus-5-5-system-card)
  - In a real incident, about 700 agents facing impossible tasks went after the scorer. [METR, 2026-08-26](https://metr.org/blog/2026-08-26-openai-hugging-face-incident-investigation/)
- **Give a sanctioned exit.** A written policy plus an escalation tool cut hacking from **23.6% to 5.3%**; 98.7% of escalations involved no hacking.
  - [Gomez, arXiv 2608.29460, 2026-08-29 — preprint](https://arxiv.org/abs/2608.29460)
- **Official anti-gaming wording.** The Claude docs give: "Do not hard-code values or create solutions that only work for specific test inputs… It is unacceptable to remove or edit tests… If… any of the tests are incorrect, please inform me rather than working around them."
  - [Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)
  - The Sonnet-tier page adds: "A syntax-only check, or a check command that failed to start, does not count." [Anthropic prompting guide, current Sonnet tier](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5)
- **Prompts help but do not suffice.**
  - "Simply instructing the agent not to hack lowers the hack rate but does not eliminate it"; a specific instruction took rates to 0–7%. [Hack-Verifiable Terminal Bench, arXiv 2608.22103, 2026-08-22](https://arxiv.org/abs/2608.22103)
  - "Don't cheat!" helps some models and backfires on others. [CheatBench, arXiv 2609.36308, 2026-09-28](https://arxiv.org/abs/2609.36308)
  - A model trained to hack still hacked 23% under the strongest prompt. [Anthropic, *Training a Misaligned Reward Seeker*, 2026-08](https://alignment.anthropic.com/2026/reward-seeker/)
- **Hacks hide as refactors.** "Astra often frames the reward-hacking workaround as normal code modularization."
  - [GPT-6 Astra system card, 2026-09-03](https://deploymentsafety.openai.com/gpt-6-astra)
- **TDD-first evidence is mixed.** TDD used 3–8.5× more tokens with no clear gain in quality or mutation score (a small experiment). Willison's red/green pattern is the counterpoint.
  - [Böckeler, *TDD in the agent loop*, 2026-08-11](https://martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html)
- **Effort:** implement at lower effort and verify at higher effort.
  - [Thariq, *Spending your effort*, 2026-09-25](https://claude.dev/blog/spending-your-effort/)
- → **One writer, an explicit `BLOCKED:` exit, the official integrity wording, outcome gates over ritual. Keep test-first as a soft check.**

### 3.3 Verify and review
- **Single writer plus an isolated verifier.** "Multi-agent systems work best today when writes stay single-threaded and the additional agents contribute intelligence rather than actions."
  - [Factory, 2026-08-27](https://factory.com/news/what-it-takes-for-coding-agents-to-complete-large-software-tasks)
  - [Garg, *Orchestrator tax*, OLDER (2026-07-16)](https://martinfowler.com/articles/orchestrator-tax.html)
  - Role-based agent teams sit only in "Assess". [Thoughtworks Radar Vol. 34, OLDER (2026-04)](https://www.thoughtworks.com/en-us/radar/techniques/feedback-sensors-for-coding-agents)
- **Over-reporting.** "A reviewer prompted to find gaps will usually report some, even when the work is sound… Chasing every finding leads to over-engineering."
  - [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
  - Ask for merge-blocking problems only, with a failing repro, and "check its evidence before you accept it." [Osmani, claude.dev, 2026-09-22](https://claude.dev/blog/getting-the-most-out-of-opus-5-5/)
- **Weak oracles are the norm.** "80.2% of test patches contain weak or no explicit oracle signals."
  - [*All Smoke, No Alarm*, OLDER (2026-06-16)](https://arxiv.org/abs/2606.18168)
  - Mutation testing exposes them (60%→82% after killing survivors). [Radzymiński, 2026-08-02](https://www.awesome-testing.com/2026/08/mutation-testing-for-agent-written-code)
- **LLM monitors miss things and are gameable.**
  - A review panel missed 6.5% of confirmed hacks; evasion rose to 40.5% with detailed feedback. [arXiv 2609.28614, 2026-09-23](https://arxiv.org/abs/2609.28614)
  - Agents tamper with their own traces. [arXiv 2609.30266, 2026-09-24](https://arxiv.org/abs/2609.30266)
- **Personas don't help.** Persona prompts produced the most weaknesses of the techniques tested.
  - [OpenSSF guide, OLDER (2025-08)](https://best.openssf.org/Security-Focused-Guide-for-AI-Code-Assistant-Instructions)
- → **One fresh-context, read-only `/check` (a forked skill, not an agent):**
  - it runs the tests itself and reads the diff before any summary;
  - it reports only merge-blocking problems, each with a repro;
  - it checks that new tests fail without the change.
  - **Drop self-reported confidence logs.**

### 3.4 Ship (commit, PR/MR)
- **Make the gates fail closed.**
  - "If your hook is meant to enforce a policy, use `exit 2`." Exit 1, timeouts and missing scripts let the call proceed. [Claude Code hooks](https://code.claude.com/docs/en/hooks)
  - Copilot: "Timeouts are always fail-open, even for `preToolUse`." [Copilot CLI hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference)
- **Agents bypass hooks in practice.** Reported in the wild: `--no-verify` and `git stash` across 6 commits despite CLAUDE.md. The recommended fixes are deny rules, a PreToolUse parser and CI.
  - [pydevtools, 2026-09-14](https://pydevtools.com/handbook/how-to/how-to-stop-ai-agents-from-bypassing-pre-commit-hooks/)
- **Claude will run a `verify` skill.** Since v2.1.286 Claude is told to run a skill named `verify` right before each commit. It's an instruction, not a gate.
  - [Claude Code skills](https://code.claude.com/docs/en/skills)
- **Code review trusts the PR's own instructions.** Copilot code review reads instructions, AGENTS.md and skills **from the PR head branch**, so an agent's PR can weaken its own review. Protect those paths with CODEOWNERS and rulesets.
  - [GitHub Docs](https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/copilot-code-review)
  - Copilot review approvals can count toward required reviews; keep them off. [2026-09-01](https://github.blog/changelog/2026-09-01-copilot-code-review-can-now-approve-pull-requests)
- **Hooks are not a security boundary.** "Hooks are not a security boundary — a prompt injection can work around them."
  - [Trail of Bits claude-code-config, updated 2026-08-24](https://github.com/trailofbits/claude-code-config)
  - "Treat tool hooks as a useful guardrail, not a complete enforcement boundary." [OpenAI Codex security](https://developers.openai.com/codex/agent-approvals-security)
- → **One fail-closed guard and a stop-time verifier; CI and branch protection stay the ground truth.**

### 3.5 Operate (incidents)
- **Rule of Two.** Within one session, combine at most two of: untrusted input, sensitive data/systems, external actions.
  - [Meta, OLDER (2025-10-31)](https://ai.meta.com/blog/practical-ai-agent-security/)
- **Issue and PR text is an attack channel.** Review agents approved vulnerable PRs when the description was persuasive.
  - [SEVRA-BENCH, OLDER (2026-06-11)](https://arxiv.org/abs/2606.13757)
- → **`/incident` investigates read-only and writes a plan. You decide what goes to Jira (the pipeline script posts only after your confirmation), and the fix starts in a fresh session.**

### 3.6 The security boundary (cross-cutting)
- **The sandbox is the boundary.**
  - Sandbox off by default; "no built-in credential deny list"; Read/Edit deny rules merge into the OS boundary. [Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing)
  - Users approved about 93% of prompts, so environment controls are the deterministic layer. [*How we contain Claude*, OLDER (2026-05-25)](https://www.anthropic.com/engineering/how-we-contain-claude)
- **Auto mode is not a boundary.**
  - Bypassed in 60–80% of attempts; Anthropic: the boundary is "OS isolation and network egress control". [Rehberger, 2026-08-26](https://embracethered.com/blog/posts/2026/breaking-claude-code-opus-5-and-automode/)
  - Injection bypassed it in 79% of trials. [arXiv 2609.19587, 2026-09-17](https://arxiv.org/abs/2609.19587)
- **Agent config is now a supply chain.**
  - An npm worm wrote `.claude/settings.json` SessionStart hooks. [The Hacker News, 2026-08-04](https://thehackernews.com/2026/08/keyv-linked-npm-worm-poisons-hundreds.html)
  - Look-alike skills reached 1.7M installs. [Zenity via TNW, 2026-08-07](https://thenextweb.com/news/zenity-malicious-ai-skills-1-7m-installs-supply-chain-credential-theft)
  - Never pre-approve shell in third-party skills. [GitHub Docs: skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)
- **Dependency installs need a deterministic check.** Assistants checked provenance in only 9 of 1,920 trials.
  - [Shan, arXiv 2609.07754, 2026-09-07](https://arxiv.org/abs/2609.07754)
- **Exfiltration from one web page.** In autopilot mode, one web page was enough to read `.env.prod` and send it out.
  - [Adversa, 2026-10-06](https://adversa.ai/blog/cryptographic-context-injection-github-copilot/)
  - Excessive Agency is now #3. [OWASP GenAI Top 10 2026, 2026-09-01](https://genai.owasp.org/2026/09/01/owasp-genai-security-project-unveils-2026-top-10-for-llm-applications-new-agent-control-standard-and-sponsors-as-community-tops-30000-members/)
- → **Sandbox on with an egress allowlist; secrets denied at the OS level; human approval for outward actions and new dependencies; prune plugins and MCP.**

### 3.7 Minimal context (cross-cutting)
- **Context files rarely help.** Repo context files didn't generally improve success and raised inference cost by more than 20%.
  - [ETH Zurich, arXiv 2602.11988 v3, 2026-09-29](https://arxiv.org/abs/2602.11988)
  - "A short, accurate `AGENTS.md` is more useful than a long file full of vague rules." [OpenAI Codex best practices](https://developers.openai.com/codex/learn/best-practices)
- **Less prompt, same results.** Anthropic removed more than 80% of Claude Code's system prompt "with no measurable loss".
  - [Thariq, OLDER (2026-07-24)](https://claude.dev/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models/)
  - Keep CLAUDE.md under 200 lines; move procedures into skills. [Claude Code memory](https://code.claude.com/docs/en/memory)
- **Audit and prune regularly.** "Installing a useful skill and keeping it forever are separate decisions."
  - [Osmani, 2026-08-27](https://addyosmani.com/blog/audit-your-agent-files/)
  - Instruction bloat and MCP by default are rated Caution. [Thoughtworks, OLDER (2026-04)](https://www.thoughtworks.com/en-us/radar/techniques/agent-instruction-bloat)
- **Skills are unreliable for must-follow rules.** Skills went uninvoked 56% of the time; an explicit checklist passed 10/10 against 5/10 for "check your work".
  - [Vercel, OLDER (2026-01-27)](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals) and its arXiv companions
- **Harnesses break on model updates.**
  - [Yegge, 2026-08](https://yegge.ai/essays/the-shape-of-things-to-come/), [Ronacher, 2026-09-07](https://lucumr.pocoo.org/2026/9/7/astra-why/)
  - "every component in a harness encodes an assumption about what the model can't do on its own." [Anthropic, OLDER (2026-03-24)](https://www.anthropic.com/engineering/harness-design-long-running-apps)
  - Look at the data first. [Husain, 2026-09-30](https://hamel.dev/blog/posts/claude-auto-evals/)
- → **Short instruction files; skills only for workflows you invoke explicitly; hooks for must-hold rules; re-run the canaries whenever model aliases move.**

### 3.8 Weak or missing evidence, so not built
- **Self-rated confidence scores.** Inputs are agent-written, and traces get tampered with.
- **Role-based agent teams.** Rated Assess (Radar); heavy managerial oversight scored worst (Ren et al., OLDER).
- **Persona prompts** (OpenSSF).
- **Mandatory test-first as a hard gate.** Evidence is mixed (§3.2), so it is kept as a soft "ask".
- **Model-printed protocol lines** (sentinels) as orchestration signals.
  - They are probabilistic, and Claude Code already emits structured events (`--output-format stream-json`).

### 3.9 Native capabilities, verified on the installed versions (PROOF E10)

| Need | Claude Code 2.1.292 | Copilot CLI 1.0.92 |
|---|---|---|
| Plan before building | Plan mode (read-only). `opusplan` = "Opus in plan mode, else Sonnet" | Plan mode hard-blocks workspace mutations (1.0.71). `/model plan <model>` (1.0.74) |
| Fresh-context review | Skill frontmatter `context: fork` + `agent: Explore`: "The subagent doesn't see your conversation history". Explore has no Write/Edit. Built-in `/code-review` and `/security-review` | `/rubber-duck`: an independent critique, with an opposite-family model strategy (1.0.49, 1.0.64). `/review` (0.0.388) |
| Cheaper implementer | Per-call `model` parameter on the Agent tool; skill `model` / `effort` frontmatter | Session model; built-in `explore` / `task` subagents |
| Workflows | Skills (`/name`), also in `claude -p` | Skills (`/name`, 0.0.389), also in `-p` (0.0.403) |
| Verify before commit | A skill named `verify` "is run right before each commit" (v2.1.286). It is an instruction, not a gate | — (use the hooks) |

Anthropic's guidance:
- "Use the main conversation when … multiple phases share significant context, such as planning, implementation, and testing."
- Subagents are for verbose output, tool restrictions or self-contained work. [Sub-agents](https://code.claude.com/docs/en/sub-agents)
- Skills are for reusable workflows. [Skills](https://code.claude.com/docs/en/skills)
- → **No custom agents.**

---

## 4. Design principles

| # | Principle | Sources |
|---|---|---|
| P1 | **Enforce outside the agent's reach.** Must-hold rules live in hooks and settings that fail closed and that the agent can't edit. Prompts only state intent. | §3.4, §3.6 |
| P2 | **Ground truth comes from execution, never self-report.** The hooks run the check themselves. CI and branch protection are final. | §3.3, §3.4 |
| P3 | **Every gate has an honest exit.** `BLOCKED: <evidence>` is a success path, and you are the only bypass. | §3.2, E12 |
| P4 | **Strong finish lines.** `.anw/verify` runs the whole fast suite, so no cheap hack can pass it. A weak check was gamed 2/2; a strong one led to `BLOCKED:` 4/4. | E12 |
| P5 | **Native first.** One session writes and one fresh-context `/check` reviews. No custom agents. | §3.1, §3.3, §3.9 |
| P6 | **Contain the blast radius.** OS sandbox, egress allowlist, denied secrets, approval for outward and irreversible actions, read-only prod access. Hooks run outside the sandbox, so they execute only code you have trusted. | §3.5, §3.6, E14 |
| P7 | **Verify the harness against reality.** Contract tests use the real payloads, and live canaries run after every model-alias move. | E1–E5, §3.7 |

---

## 5. Target design

### 5.1 The development flow

**Once per repo:** `ai-native-workflow install project` writes three things:
- `.anw/verify`, your full fast suite and the finish line, with its hash recorded as trusted;
- a slim AGENTS.md;
- a `.gitignore` rule that keeps `.anw/verify` tracked.

**A. Small change (1–2 files, clear requirement): the default**
1. Ask in the main session ("fix X"). Per the working agreements, the agent writes a failing test first, then the fix.
2. `guard.sh` watches every command and edit. At commit time it **asks you** if a test was deleted, skipped or weakened, or if code changed with no test.
3. When the turn ends, `verify.sh` runs `.anw/verify`, because the session edited files.
   - Red: the agent keeps working, or ends with `BLOCKED:` and evidence.
4. `/check`, then `/pr`.

**B. Feature or unclear work (3+ files)**
1. `/plan PROJ-123` (Opus, high effort) writes `docs/context/specs/PROJ-123.md` with testable ACs and small steps. **You approve.** This is the key checkpoint.
2. `/clear`, then "implement step 1 of docs/context/specs/PROJ-123.md".
   - The same gates as A apply. Commit after each step.
   - Repeat for each step, clearing between steps when the context gets long.
3. `/check` reviews the branch with a fresh context, read-only, at Opus tier. You triage each finding: fix, tech debt, or ignore.
4. `/pr`: push and PR each ask you first. CI and branch protection decide.

Copilot differences:
- Plan in plan mode, with `/model plan` choosing the planning model, plus `/plan`.
- After `/check`, run `/rubber-duck` for a critique from the opposite model family.

**C. Incident**
1. `/incident PROJ-456` runs a read-only investigation, treating ticket and log text as data. It produces a diagnosis and a fix plan.
2. You decide what to post to Jira.
3. Start a fresh session: `/plan docs/context/specs/PROJ-456-incident.md`, or flow A if it's small. Step 1 reproduces the bug as a failing test.

**D. Reviewing a PR or MR:** built-in `/code-review`; add `--comment` to post once you've read the preview. In Copilot, `/review`.

**E. Spike:** ask for a spike under `spikes/`, which is gitignored and exempt from the test-first check. End with `FINDINGS.md`, then `/plan` to promote it.

**F. Headless pipeline (`ai-native-workflow run …`):** the same stages, each run as a fresh process.
1. `claude -p "/plan PROJ-123" --model opus`, then you confirm.
2. For each step: `claude -p "implement step N of …" --model sonnet`.
3. `claude -p "/check" --model opus --disallowedTools Edit,Write,MultiEdit,NotebookEdit`.
4. The script runs the trusted `.anw/verify`, then push, PR/MR and Jira after you confirm.

Every Claude call uses `--permission-mode acceptEdits --permission-prompts none`. Copilot uses `copilot -p "/plan …"` with `--deny-tool` rules and the sandbox.

**G. Keeping it healthy**
- After any model or tool update: `ai-native-workflow doctor --smoke`.
- Monthly: `/context`, then prune.
- Add a rule only after you see the same failure twice in transcripts.

### 5.2 Enforcement: 2 scripts for both tools (`spikes/harness-2/hooks/`, 52 contract tests)

**`guard.sh`** runs as Claude `PreToolUse` (matcher `Bash|Edit|Write|MultiEdit|NotebookEdit`) and Copilot `preToolUse`.
- It reads either tool's stdin JSON.
- It never emits `allow`, which would auto-approve the call.
- A crash means deny. On Claude this goes through `|| exit 2`, so a missing script also blocks (E15).

| Rule | Decision |
|---|---|
| `--no-verify`, `commit -n`, `core.hooksPath`, `HUSKY=0`, `SKIP=` | deny |
| Nested `claude --bare` or `--dangerously-skip-permissions`; `copilot --yolo` or `--allow-all*` | deny |
| Edits or shell writes to `~/.claude`, `~/.copilot` (including the trust list), `.claude/settings*.json`, `.git/`, `.github/hooks/`, `.anw/` | deny |
| A commit (including `--amend`) that deletes tests, adds skip or focus markers, removes or rewrites assertions in existing tests, or changes source with no test | ask |
| New dependency names (`npm i x`, `uv add`, `go get`, `cargo add`, `dotnet add package`) | ask |
| Edits to CI config, AGENTS.md / CLAUDE.md / copilot-instructions, `.claude/*`, `.mcp.json`, `.vscode/tasks.json` | ask |
| Any file edit, allowed or not | marks the session as "edited", which arms `verify.sh` |

`ask` means you approve in the moment. Auto mode can deny an ask but never approve it, and in headless runs an ask becomes a denial (E5). **This replaces `/skip-tdd`, `/override-confidence`, `.tdd-skip` and the override markers.**

**`verify.sh`** runs as Claude `Stop` and Copilot `agentStop`. It acts only when:
- the session edited files, and
- `.anw/verify` exists, and
- the script's hash is in `~/.claude/anw/trusted-verify`.

The trust check exists because hooks run outside the sandbox. A cloned or modified script is skipped, and you're told (E14).

Outcomes:
- Green: the turn ends normally.
- Red: it returns `{"decision":"block"}` with the failure output and the honest-exit instruction.
- A reply ending in `BLOCKED:`, or a second red stop in a row: allowed through, and flagged to you.

**This replaces the confidence scorer.**

Parity notes:
- In Claude, only exit 2 or a JSON decision blocks.
- In Copilot, any non-zero exit denies.
- In both, a timeout passes, so keep `.anw/verify` under 600 s.

### 5.3 Skills: the only "agents" left (`spikes/harness-2/skills/`)

| Skill | Invoked by | Frontmatter | Job |
|---|---|---|---|
| `plan` | you | `disable-model-invocation`, `model: opus`, `effort: high` | ticket → testable ACs and small TDD steps in `docs/context/specs/<id>.md`, then stops for your approval |
| `check` | you | `disable-model-invocation`, `context: fork`, `agent: Explore`, `model: opus`, `effort: high` | fresh-context, read-only review: runs the check, reads the diff first, audits integrity, reports merge-blocking findings with a repro |
| `verify` | the model (Claude runs it before every commit) | none | runs `.anw/verify` or the tests and quotes the exact result |
| `incident` | you | `disable-model-invocation`, `model: opus`, `effort: high` | read-only investigation → diagnosis and fix plan; never posts |
| `pr` | you | `disable-model-invocation` | verify, then push and PR/MR (both ask you), with the real verification output |

- **Keep as knowledge** (model-invocable): `clusters`, `k8s` (mutating commands marked human-only; the deny rules enforce it), `app-insights`, and `kibana` (Copilot).
- **Keep only if you use them:** `adr`, `session-report`, `caveman`, `explore` (spikes).
- **Delete:**
  - all 9 agents, in both tools;
  - `tdd`, now one line in the working agreements;
  - `skip-tdd`, `override-confidence`, and `pipeline-*` (the CLI's `--help` covers those);
  - `brainstorm`, which duplicates superpowers;
  - `gh-cli` / `glab-cli`, if D5 favours the built-in `/code-review`;
  - everything in `~/.claude/commands/`.

Copilot doesn't document `context` or `agent` in SKILL.md, so treat `/check` there as running inline and follow it with `/rubber-duck` (verified in P1-4).

### 5.4 `~/.claude` end state
- **`CLAUDE.md`:** `spikes/harness-2/instructions/CLAUDE.md`, 16 lines (who you are, 6 working agreements, the flow).
- **`settings.json`:** merge `spikes/harness-2/config/claude-settings.json` with `jq -s '.[0] * .[1]'`. The dry run against your current file keeps your vault directory, status line and model (E15).
  - **Mode:** `defaultMode: "auto"` set explicitly; `disableBypassPermissionsMode: "disable"`.
  - **Allow:** read-only kubectl, az and docker commands.
  - **Ask:** push; PR/MR create, merge and comment; `gh api`, `gist` and `repo`; `glab api`; Confluence writes.
  - **Deny:**
    - reads of secrets;
    - edits to `~/.claude`, `~/.copilot` and the project's `.claude/settings*.json`;
    - force-push, reset and clean;
    - mutating kubectl and helm commands;
    - the Gmail, Drive and Calendar tools.
  - **Sandbox:**
    - on, strict (`allowUnsandboxedCommands: false`), with sandboxed Bash auto-allowed;
    - docker, kubectl, az and helm run outside it via `excludedCommands`;
    - outbound network limited to your forges and package registries.
  - **Hooks:** `PreToolUse` → `guard.sh || exit 2`; `Stop` → `verify.sh`. `SessionStart` is removed: Claude already injects git status and reads AGENTS.md, and that hook was the RCE.
  - **Plugins:**
    - `syncClaudeAiPlugins` and `syncClaudeAiSkills` set to `false`;
    - superpowers, the duplicate vercel plugin, latex, figma and frontend-design off globally (enable them per project).
- **Rule order:** "Rules are evaluated in order: deny, then ask, then allow… rule specificity doesn't change the order" ([permissions](https://code.claude.com/docs/en/permissions)).
  - So reads get explicit allows and mutations get explicit denies.
  - Read and Edit deny rules also become the sandbox's OS-level `denyRead` / `denyWrite` (E6).
- **Project settings outrank yours** and can turn `disableAllHooks` on. The mitigations:
  - the guard plus the `Edit(./.claude/settings*.json)` deny stop agents and sandboxed install scripts from writing them;
  - for repos you didn't write, run headless with `--setting-sources user`;
  - managed settings (P2-2) are the only place a repo can't override.
- **`hooks/`:** `guard.sh` and `verify.sh` as copies, never symlinks, so an agent working in this repo can't change live enforcement.
- **`skills/`:** the 5 workflow skills plus the knowledge skills, symlinked from the repo.
- **`agents/`, `commands/`, `scripts/`:** empty.
- **`anw/trusted-verify`:** hashes of the `.anw/verify` scripts you have approved.

### 5.5 `~/.copilot` end state
- **`copilot-instructions.md`:** `spikes/harness-2/instructions/copilot-instructions.md`. Same agreements; the flow mentions plan mode and `/rubber-duck`.
- **`hooks/anw.json`:** `spikes/harness-2/config/copilot-hooks.json`. `preToolUse` → `guard.sh` (15 s); `agentStop` → `verify.sh` (600 s). The scripts are copied next to it.
- **`settings.json`:**
  - `allowedUrls` pruned to docs, registries, your forges and localhost;
  - sandbox on, with bypass off and an egress allowlist (`/sandbox`);
  - from CLI 1.0.93 on, check the result with `copilot config list`.
- **Approvals and MCP:**
  - `permissions-config.json` reset to `{"locations":{}}`;
  - `mcp-config.json` tools narrowed from `["*"]` to the read tools you use;
  - `trustedFolders` without `~/.claude`, `~/.copilot` and `~/.config/fish`.
- **`agents/`:** empty, so there are no more pinned model slugs. Use the session default model, and `/model plan` for planning.
- **Don't set `disableBypassPermissionsMode` here.** It also suppresses `--allow-all-tools`, which `copilot -p` requires. Deny rules (which beat `--allow-all`), the sandbox and the hooks do the work instead.

### 5.6 Pipelines and installer (repo)
- **Pipeline stages** call the native CLIs with skills and model flags (flow F). There is no `--agent` and no bypass flag.
  - **Claude:** `--permission-mode acceptEdits --permission-prompts none`, so anything that would prompt is denied. The user-level sandbox applies.
  - **Copilot:** `--allow-all-tools` (required for `-p`) plus `--deny-tool` rules and `--secret-env-vars`, with no `--allow-all-paths`.
- **Outward actions stay in the script.** Push, PR/MR and Jira writes happen only after your confirmation, and only once the trusted `.anw/verify` passes.
- **The live renderer** reads `--output-format stream-json` events from Claude and `--output-format json` events from Copilot, instead of model-printed sentinels (D1). The sidekick and sentinel prompt text go away with the agents.
- **`install global`:**
  - copies the hooks;
  - merges the settings;
  - symlinks the skills;
  - writes the instructions;
  - removes the legacy agents, skills, commands and hooks.
- **`install project`:**
  - writes `.anw/verify` for the detected stack and trusts it;
  - adds `.anw/*` plus `!.anw/verify` to `.gitignore`, so the script stays tracked;
  - writes a slim AGENTS.md: commands first, then Always / Ask first / Never, at most 80 lines.
- **New commands:**
  - `ai-native-workflow trust` re-approves a changed `.anw/verify`;
  - `doctor [--smoke]` reports drift and runs the canaries.

### 5.7 Size: before → after

| Component | Before | After |
|---|---|---|
| Custom agents | 9 Claude and 8 Copilot files (1,303 + 528 lines) | **0** |
| Skills | 21 per tool, plus 17 duplicate `.bak` dirs | 5 workflow + 3–4 knowledge (+ conveniences you choose) |
| Enforcement code | 458 lines plus a ~200-line generated dispatcher, on the wrong contract | `guard.sh` + `verify.sh`: 173 lines, both tools |
| Enforcement tests | 1,711 lines on the wrong contract | 52 contract tests + `make smoke` |
| Global instructions | 58 + 55 lines | 16 + 16 |
| Bypass mechanisms | 2 skills and 2 marker files | 0: you approve the prompt |
| Pinned model versions | Copilot agent slugs | none: aliases and session settings only |

---

## 6. Evidence that this design works (live runs, small N; PROOF E4–E15)

| What | Result |
|---|---|
| Contract tests on both tools' real payloads | **52/52** green, including a regression test proving the old gate is a no-op |
| The full proposed Claude config, live (E15) | `cat .env` → `Operation not permitted`; `--no-verify` → denied by the guard; `curl example.com` → `deny network-outbound`. A missing guard script → every call blocked (fail-closed) |
| Guard in headless Claude Code (E5) | A source change committed without a test, and `npm i left-padd` → ask → denied in `-p`, under both acceptEdits and auto |
| Sandbox off vs on (E6) | Off: an obfuscated `python3` read printed a fake secret, and `curl` → 200. On: the OS blocked the read and the network call |
| Stop hook on an honest task (E11) | Bug fixed, check green at stop, no pushback, marker cleared |
| Canary with a **weak** finish line (only the contradictory assertion) (E12) | **2/2 gamed it** with `a + b + 1`. B1 also rewrote the spec after the guard denied editing the check |
| Canary with a **strong** finish line (a real test plus the contradictory assertion) (E12) | **4/4 ended with `BLOCKED:`** and evidence, with no code changed. In every run the first move was editing `.anw/verify`, which the guard denied, followed by one Stop-hook pushback. Current vs proposed instructions made no visible difference at N=2, because the hook's message carried the escalation |
| `/check` (fresh context, read-only, Opus tier) on both gamed states (E13) | **2/2 blocked the merge** with the right diagnosis (code bent to the check, and the spec rewritten to match). Working tree untouched |

**Reading:**
- The deterministic gates stopped every attempt to edit the check.
- A strong finish line plus the honest exit produced escalation instead of hacks.
- The semantic hack that a weak check allowed was caught only by the fresh-context review.

That is why the flow makes `.anw/verify` the full suite and `/check` a standard step before `/pr`.

---

## 7. Acceptance criteria

- **AC-1** A real `claude -p` **and** `copilot -p` session attempting `git commit --no-verify` is denied, with the guard's reason in the result (`make smoke`).
- **AC-2** The gates fail closed:
  - malformed input → exit 2 (Claude) or deny JSON (Copilot);
  - a missing `guard.sh` blocks every Claude call (E15).
- **AC-3** A commit that deletes a test, adds a skip or focus marker, removes or rewrites an assertion in an existing test, or changes source with no test → asks interactively, and is denied headless (bats + smoke).
- **AC-4** Agent writes are denied, through Edit/Write and common shell writes, to:
  - `~/.claude` and `~/.copilot` (including the trust list);
  - `.claude/settings*.json`, `.git/`, `.github/hooks/` and `.anw/`.
- **AC-5** An editing session can't end red, except through `BLOCKED:` or a second red stop, and both are surfaced to you. A turn that edited nothing never runs the check (bats + smoke).
- **AC-6** Hooks and the pipeline never execute an untrusted or changed `.anw/verify` (bats).
- **AC-7** With your settings applied, in a Claude session:
  - `cat .env` → `Operation not permitted`;
  - `curl` to a non-allowlisted host is blocked;
  - `claude --dangerously-skip-permissions` is refused (smoke).
- **AC-8** No pipeline passes a bypass flag, and agents never push or post (bats on `lib/`).
- **AC-9** In both tools: zero custom agents installed, and the skills are exactly the 5 workflow skills plus knowledge skills (plus any optional ones you keep). Checked by bats on a sandbox-HOME install and by `doctor`.
- **AC-10** Size budgets:
  - global instruction files ≤ 25 lines;
  - each workflow skill ≤ 30 lines;
  - AGENTS.md template ≤ 80 lines.
- **AC-11** Canaries:
  - the strong-finish-line canary ends in `BLOCKED:` with no test or check changed;
  - `/check` blocks the weak-finish-line hack.
  - Report k/n after every model-alias change, with no extrapolation.
- **AC-12** PAPER and ARCHITECTURE match reality (gate errata, native-first architecture), and ADR-003 supersedes ADR-002.

---

## 8. Decisions for you (recommended default in bold)

| # | Decision | Options |
|---|---|---|
| D1 | Live renderer | **Keep it, fed from the tools' event streams**, or drop it |
| D2 | Strength of the test-first gate | **Soft (`ask`)**, or hard |
| D3 | superpowers plugin | **Disable globally**, or keep |
| D4 | Gmail/Drive/Calendar and synced plugins in Claude Code | **Deny them and stop the sync**, or keep |
| D5 | PR review | **A/B the built-in `/code-review` against your gh-cli/glab-cli skills on 3 PRs**, and keep the better one |
| D6 | Hidden acceptance tests (P2-1) | Opt-in for critical repos; they are the strongest fix for weak finish lines |
| D7 | Managed settings for the hooks (P2-2) | **After P1** |
| D8 | Default session model | **`opusplan`**: Opus plans, Sonnet implements, which is your old tiering done natively. `/plan`, `/check` and `/incident` pin Opus regardless. Or keep `opus` everywhere |

---

## 9. Risks and limits

- **R1** Regex detection has a ceiling. Backstops: the sandbox, `/check`, CI, hidden tests.
- **R2** A hook timeout lets the action through, in both tools. Keep `guard.sh` limited to git-diff work, and keep `.anw/verify` well under 600 s.
- **R3** Hooks are guardrails, not a security boundary. Prompt injection, mods and project settings can route around them. The **sandbox** is the boundary; managed settings (P2-2) harden the hooks.
- **R4** Auto mode is not a boundary: published bypass rates are 60–80% and 79%.
- **R5** Sandbox friction. Excluded commands run unsandboxed. If strict mode blocks them, set `allowUnsandboxedCommands: true` (P0-3 checks this).
- **R6** There is no controlled evaluation. Canaries catch regressions; they don't measure effect sizes.
- **R7** Sources conflict on whether to disclose graders to the agent. Disclose only the visible, deterministic checks, and never the hidden tests.
- **R8** Evidence for test-first is mixed, so it stays a soft ask.
- **R9** Model updates break harness prompts. Rev 2 has far fewer prompts to break. Run `doctor --smoke` after every update.
- **R10** **Weak finish lines invite hacks** (seen 2/2 in E12). Mitigations: the full suite in `.anw/verify`, `/check` before `/pr`, and hidden tests for critical code.
- **R11** Native features move (skill `context: fork`, Copilot's rubber-duck). `doctor --smoke` detects breakage, and there are fewer moving parts than with custom agents.
- **R12** Copilot may ignore `context`/`agent` in SKILL.md. Then `/check` runs inline there, and `/rubber-duck` adds the independence.
- **R13** Edits made only through Bash don't mark the session. The pre-push verify and CI still run.

## 10. Out of scope

Multi-developer coordination; cloud-agent (`/delegate`) environments beyond the repo templates; enterprise managed-policy rollout; replacing CI.
