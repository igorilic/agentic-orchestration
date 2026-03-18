# Agentic Orchestration

A multi-agent pipeline for test-driven development with Claude Code and GitHub Copilot CLI.

Five specialized AI agents collaborate through a deterministic pipeline:
**architect** → **tdd-developer** → **qa** → **reviewer** (with **troubleshooter** for incidents).

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

## Agent Pipeline

```
/plan "add user authentication"
  │
  ├─ architect (Opus 4.6)         → spec.md + todo.md (atomic steps)
  │
  ├─ tdd-developer (Sonnet 4.6)   → RED: failing tests → commit
  │                                  GREEN: implement → commit
  │                                  REFACTOR: improve → commit
  │
  ├─ qa (Haiku 4.5)               → runs affected tests only
  │
  ├─ reviewer (Sonnet 4.6)        → 🔴 MUST FIX / 🟡 SHOULD FIX / 🟢 SUGGESTION
  │                                  → you triage: [F]ix / [T]ech debt / [I]gnore
  │
  └─ (max 3 fix loops, then next step)
```

For production incidents:
```
Use the troubleshooter to investigate PROJ-456
  → Jira ticket context
  → ArgoCD pod logs (EMEA/APAC/NAM)
  → Azure Application Insights queries
  → Root cause diagnosis + TDD fix plan
```

## Quick Start

```bash
# Install globally (hooks, skills, agents for Claude Code + Copilot CLI)
./tdd-workflow install global

# Install per project (auto-detects your stack)
cd ~/code/my-project
tdd-workflow install project .

# Check what's installed
tdd-workflow status
```

## What Gets Installed

### Global (`~/.claude/` + `~/.copilot/`)

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
| `skills/clusters/` | Multi-cluster reference (EMEA/APAC/NAM) |
| `agents/architect.md` | Opus 4.6 — design, spec, atomic plans |
| `agents/tdd-developer.md` | Sonnet 4.6 — strict TDD implementation |
| `agents/qa.md` | Haiku 4.5 — run affected tests |
| `agents/reviewer.md` | Sonnet 4.6 — code review + triage |
| `agents/troubleshooter.md` | Opus 4.6 — incident diagnosis |

### Per-Project (generated based on detected stack)

| Component | Purpose |
|-----------|---------|
| `AGENTS.md` | Cross-tool agent rules (Claude + Copilot) |
| `CLAUDE.md` | Project context |
| `.context/` | Architecture, conventions, specs, sprint |
| `.github/copilot-instructions.md` | Copilot repo-wide rules |
| `.github/instructions/*.instructions.md` | Stack-specific Copilot rules |
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

### Claude Code
```bash
# Start the pipeline
/plan Add JWT authentication

# Or invoke agents directly
Use the architect agent to plan the auth feature
Use tdd-developer to work on Step 1 of auth-todo.md
Use qa to verify the changes
Use reviewer to review the changes

# Incident response
Use the troubleshooter to investigate PROJ-456
```

### Copilot CLI
```bash
# Interactive
copilot
> /agent    # pick from list

# Direct
copilot --agent=architect --prompt "Plan JWT auth"
copilot --agent=tdd-developer --prompt "Step 1 of auth-todo.md"
copilot --agent=troubleshooter --prompt "Investigate PROJ-456"
```

### TDD Bypass
```bash
# In Claude Code
/skip-tdd "docs-only change"

# The gate allows the next commit, then re-enables
```

## Multi-Cluster Troubleshooting

The troubleshooter agent works across 3 regional Kubernetes clusters (EMEA, APAC, NAM):

- **ArgoCD**: Single MCP instance manages all clusters
- **kubectl**: `--context=aks-<region>-prod` per command
- **App Insights**: Region-specific `--app` and `--resource-group`

Edit `~/.claude/skills/clusters/SKILL.md` with your cluster details after install.

## Documentation

- [PAPER.md](PAPER.md) — Scientific paper describing the architecture
- [docs/WORKFLOW-ARCHITECTURE-V2.md](docs/WORKFLOW-ARCHITECTURE-V2.md) — Full technical specification

## Requirements

- [Claude Code](https://code.claude.com) (for Claude Code agents/hooks/skills)
- [GitHub Copilot CLI](https://github.com/features/copilot/cli) (optional, for Copilot agents)
- `gh` CLI (for `/pr` skill with GitHub repos)
- `glab` CLI (for `/pr` skill with GitLab repos)
- `kubectl` (for troubleshooter)
- `az` CLI (for Azure Application Insights queries)
- `jq` (optional, for merging existing settings.json)

## License

MIT
