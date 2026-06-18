# Agentic Orchestration

An AI-native development CLI with multi-agent pipelines for test-driven development using Claude Code and GitHub Copilot CLI.

Eight specialized AI agents across two tracks:
- **Production**: **requirements-engineer** → **architect** → **tdd-developer** → **qa** → **reviewer** (with **troubleshooter** for incidents), plus **diff-reviewer** for whole-PR/MR review.
- **Exploration**: **explorer** for spikes, prototypes, and API learning under `spikes/` (gitignored, TDD gate skipped).

The **diff-reviewer** agent reviews a finished GitHub PR or GitLab MR
(quality, correctness, logic, conventions, security, landmines, best
practices), ranks findings by severity, and — after a preview/confirm gate —
posts severity-ranked **inline comments** on the diff (or **conceptual
threads** for non-line issues) with a verdict. It drives `gh`/`glab` via the
`gh-cli`/`glab-cli` skills and reads acceptance criteria from the linked
GitHub issue or Jira ticket.

## The Problem

AI coding assistants forget your rules mid-session. You tell them "tests first" and 30 minutes later they're writing implementation code. TDD instructions in `CLAUDE.md` are suggestions — the model can deprioritize them.

## The Solution

Separate concerns by guarantee level:

| Layer | Mechanism | Guarantee |
|-------|-----------|-----------|
| **Hooks** | Shell scripts at lifecycle points | 100% — blocks actions via exit code 2 |
| **Skills** | Reusable workflow instructions | ~80% — model loads when contextually relevant |
| **Agents** | Specialized AI with scoped tools | Purpose-built — each agent does one thing |

The TDD gate is a `PreToolUse` hook that **blocks `git commit`** if no test files are staged. It's not a suggestion — it's a shell script that returns exit code 2. The AI cannot override it.

## Pipelines

### Pipeline 1: GitLab Feature (Copilot CLI + Jira)
```
ai-native-workflow run gitlab-feature PROJ-123
  │
  ├─ requirements-engineer  → structured requirements from Jira
  ├─ qa                     → test plan
  ├─ architect              → spec.md + todo.md
  ├─ tdd-developer          → RED → GREEN → REFACTOR (per step)
  ├─ qa                     → run affected tests
  ├─ reviewer               → code review + triage
  └─ glab mr create         → merge request

  then (manual follow-up, after the MR exists):
  └─ diff-reviewer          → review MR diff; preview → confirm → post
                              inline comments + threads + verdict (glab)
```

### Pipeline 2: GitLab Incident (Copilot CLI + Jira + Troubleshooter)
```
ai-native-workflow run gitlab-incident PROJ-456
  │
  ├─ troubleshooter         → Jira + ArgoCD + App Insights + kubectl
  ├─ USER DECIDES           → document findings OR fix the issue
  ├─ tdd-developer          → reproduce bug + fix via TDD
  ├─ qa                     → verify fix
  ├─ reviewer               → review MR
  └─ glab mr create         → merge request + update Jira
```

### Pipeline 3: GitHub Feature (Claude Code)
```
ai-native-workflow run github-feature specs.md
  │
  ├─ requirements-engineer  → structured requirements from specs.md
  ├─ gh issue create        → GitHub issue (feature request)
  ├─ architect              → spec.md + todo.md
  ├─ tdd-developer          → RED → GREEN → REFACTOR (per step)
  ├─ qa                     → run affected tests
  ├─ reviewer               → code review + triage
  └─ gh pr create           → pull request (Closes #issue)

  then (manual follow-up, after the PR exists):
  └─ diff-reviewer          → review PR diff; preview → confirm → post
                              inline comments + threads + verdict (gh)
```

### Exploration Track (both Claude Code and Copilot CLI)
For spikes, prototypes, and API learning. Throwaway code under `spikes/`,
gitignored, TDD gate skipped automatically.
```
/explore <topic>            (or copilot --agent=explorer)
  │
  ├─ explorer               → 2-3 approaches with tradeoffs
  ├─ spikes/<topic>/        → prototype iteratively (gitignored)
  └─ FINDINGS.md            → recommendation; re-enter /plan to ship
```
Use `/brainstorm` first if the idea is too vague to spike yet.

## Quick Start

```bash
# Install globally (hooks, skills, agents for Claude Code + Copilot CLI)
./ai-native-workflow install global

# Install per project (auto-detects your stack)
cd ~/code/my-project
ai-native-workflow install project .

# Run a pipeline
ai-native-workflow run gitlab-feature PROJ-123
ai-native-workflow run gitlab-incident PROJ-456
ai-native-workflow run github-feature specs.md

# Check what's installed
ai-native-workflow status
```

### Sandboxed installs

`install global` writes to `~/.claude/` and `~/.copilot/` by default, and
auto-backs up `CLAUDE.md` and `settings.json` as `<file>.bak.<timestamp>`
before overwriting. To install into a sandbox instead — useful for
testing changes without touching your real config — set `CLAUDE_HOME`
and/or `COPILOT_HOME`:

```bash
CLAUDE_HOME=/tmp/aw-sandbox \
COPILOT_HOME=/tmp/aw-sandbox-copilot \
  ai-native-workflow install global
```

## What Gets Installed

### Global (`~/.claude/` + `~/.copilot/`)

#### Claude Code (`~/.claude/`)

| Component | Purpose |
|-----------|---------|
| `hooks/session-start.sh` | Auto-loads context + detects stack on session start |
| `hooks/tdd-gate.sh` | Blocks commits without test files |
| `skills/plan/` | Pipeline orchestration entry point |
| `skills/tdd/` | RED → GREEN → REFACTOR workflow |
| `skills/ticket/` | Jira issue → spec + test stubs |
| `skills/skip-tdd/` | Bypass TDD with logged reason |
| `skills/session-report/` | Obsidian session notes |
| `skills/adr/` | Architecture Decision Records |
| `skills/pr/` | Create PR/MR (auto-detects gh/glab) |
| `skills/gh-cli/` | Drive `gh` to review a GitHub PR — inline comments + threads |
| `skills/glab-cli/` | Drive `glab` to review a GitLab MR — inline discussions + threads |
| `skills/clusters/` | Multi-cluster reference (EMEA/APAC/NAM) |
| `skills/pipeline-*/` | Pipeline reference skills |
| `agents/requirements-engineer.md` | Opus 4.6 — elicit & formalize requirements |
| `agents/architect.md` | Opus 4.6 — design, spec, atomic plans |
| `agents/tdd-developer.md` | Sonnet 4.6 — strict TDD implementation |
| `agents/qa.md` | Haiku 4.5 — run affected tests |
| `agents/reviewer.md` | Sonnet 4.6 — per-step code review + triage |
| `agents/diff-reviewer.md` | Opus 4.6 — whole-PR/MR diff review; posts inline comments + threads |
| `agents/troubleshooter.md` | Opus 4.6 — incident diagnosis |
| `agents/explorer.md` | Sonnet 4.6 — spikes/prototypes under `spikes/` |
| `skills/explore/` | Exploratory mode entry point |
| `skills/brainstorm/` | One-question-at-a-time spec elicitation |

#### Copilot CLI (`~/.copilot/`)

`install global` writes a symmetric harness for GitHub Copilot CLI alongside
the Claude Code installation. Copilot CLI must be on `PATH` for the Copilot
artifacts to be created. If `copilot` is not on PATH, the installer prints a
brief notice and skips Copilot-side artifacts. The Claude side installs
normally.

| Component | Purpose |
|-----------|---------|
| `~/.copilot/skills/` | All skills from `skills/`, with `claude --agent=` rewritten to `copilot --agent=` in pipeline skills |
| `~/.copilot/copilot-instructions.md` | Global AI instructions (equivalent of `CLAUDE.md`) |
| `~/.copilot/settings.json` | Copilot CLI settings (merged additively on re-install to preserve user keys) |
| `~/.copilot/agents/` | Agent definition files (`.agent.md`) mirroring `~/.claude/agents/` |

> **Hooks asymmetry**: Claude Code hooks (`tdd-gate.sh`, `confidence-gate.sh`,
> `session-start.sh`) are installed globally and fire on every Claude Code
> session. GitHub Copilot CLI scopes hooks per-repository. Run
> `ai-native-workflow install project` in each trusted repository to enable
> Copilot repo-level hooks (COP-2; not yet shipped).

### Per-Project (generated based on detected stack)

| Component | Purpose |
|-----------|---------|
| `AGENTS.md` | Cross-tool agent rules (Claude + Copilot) |
| `CLAUDE.md` | Project context |
| `docs/context/` | Sprint board, tracked specs, todos, requirements (git-tracked; reviewable in PRs) |
| `.context/` | Architecture, conventions, glossary (installer-seeded) + runtime pipeline state (gitignored) |
| `.github/copilot-instructions.md` | Copilot repo-wide rules |
| `.github/instructions/*.instructions.md` | Stack-specific Copilot rules |
| `.github/hooks/copilot-cli-dispatcher.sh` | **Copilot CLI per-project hook** — enforces TDD + confidence gates (mirrors Claude's global hooks; per-project because Copilot CLI has no user-global hook support) |
| `.github/hooks/scripts/confidence.sh` | Vendored confidence scorer (self-contained copy; no dependency on `~/.claude/`) |
| `.github/hooks/copilot-cli-policy.json` | Registers the dispatcher as a `preToolUse` hook; merged idempotently on re-install |
| `.github/hooks/README.md` | Explains bypass paths (`/skip-tdd`, `/override-confidence`) and audit trail to contributors |
| `docs/decisions/` | ADR directory |

## Stack Detection

The installer auto-detects your stack and generates tailored configuration:

| Files Found | Stack | Test Runner | Copilot Instructions |
|-------------|-------|-------------|---------------------|
| `*.csproj` / `*.sln` | .NET | xUnit + FluentAssertions | `dotnet.instructions.md` |
| `go.mod` | Go | testing + testify | `go.instructions.md` |
| `Cargo.toml` | Rust | built-in + tokio-test | `rust.instructions.md` |
| `pyproject.toml` | Python | pytest | `python.instructions.md` |
| `package.json` + react | React/TS | Vitest + Testing Library | `typescript.instructions.md` |
| `package.json` + react-native | React Native | Jest + RNTL | `typescript.instructions.md` |
| `Package.swift` | Swift | XCTest | `swift.instructions.md` |

Scans 3 levels deep for monorepo support.

## Usage

### CLI Pipelines
```bash
# Full automated pipelines
ai-native-workflow run gitlab-feature PROJ-123
ai-native-workflow run gitlab-incident PROJ-456
ai-native-workflow run github-feature specs.md
ai-native-workflow run github-feature            # interactive input

# Pipeline management
ai-native-workflow run status                    # check progress
ai-native-workflow run resume                    # resume from checkpoint
```

### Claude Code (Interactive)
```bash
# Start the pipeline
/plan Add JWT authentication

# Or invoke agents directly
Use the requirements-engineer to analyze the specs
Use the architect agent to plan the auth feature
Use tdd-developer to work on Step 1 of auth-todo.md
Use qa to verify the changes
Use reviewer to review the changes

# Review a finished PR/MR (posts inline comments after you confirm)
Use diff-reviewer to review PR #42

# Incident response
Use the troubleshooter to investigate PROJ-456
```

### Copilot CLI
```bash
# Interactive
copilot
> /agent    # pick from list

# Direct
copilot --agent=requirements-engineer --prompt "Analyze PROJ-123"
copilot --agent=architect --prompt "Plan JWT auth"
copilot --agent=tdd-developer --prompt "Step 1 of auth-todo.md"
copilot --agent=diff-reviewer --prompt "Review MR !42 for PROJ-123"
copilot --agent=troubleshooter --prompt "Investigate PROJ-456"
```

### TDD Bypass
```bash
# In Claude Code
/skip-tdd "docs-only change"

# The gate allows the next commit, then re-enables
```

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

## Multi-Cluster Troubleshooting

The troubleshooter agent works across 3 regional Kubernetes clusters (EMEA, APAC, NAM):

- **ArgoCD**: Single MCP instance manages all clusters
- **kubectl**: `--context=aks-<region>-prod` per command
- **App Insights**: Region-specific `--app` and `--resource-group`

Edit `~/.claude/skills/clusters/SKILL.md` with your cluster details after install.

## Documentation

- [PAPER.md](PAPER.md) — Scientific paper describing the architecture
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Architecture v3.0 with all pipelines

## Requirements

- [Claude Code](https://code.claude.com) (for Claude Code agents/hooks/skills)
- [GitHub Copilot CLI](https://github.com/features/copilot/cli) (optional, for Copilot agents)
- `gh` CLI (for GitHub pipelines and `/pr` skill)
- `glab` CLI (for GitLab pipelines and `/pr` skill)
- `kubectl` (for troubleshooter)
- `az` CLI (for Azure Application Insights queries)
- `jq` (required for tests; also used to merge existing settings.json)
- `bats-core` (development only — `brew install bats-core` on macOS, `npm i -g bats` elsewhere)

## License

MIT
