# Agentic Orchestration

An AI-native development CLI with multi-agent pipelines for test-driven development using Claude Code and GitHub Copilot CLI.

Six specialized AI agents collaborate through platform-specific pipelines:
**requirements-engineer** → **architect** → **tdd-developer** → **qa** → **reviewer** (with **troubleshooter** for incidents).

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
```

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
| `skills/pipeline-*/` | Pipeline reference skills |
| `agents/requirements-engineer.md` | Opus 4.6 — elicit & formalize requirements |
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
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Architecture v3.0 with all pipelines

## Requirements

- [Claude Code](https://code.claude.com) (for Claude Code agents/hooks/skills)
- [GitHub Copilot CLI](https://github.com/features/copilot/cli) (optional, for Copilot agents)
- `gh` CLI (for GitHub pipelines and `/pr` skill)
- `glab` CLI (for GitLab pipelines and `/pr` skill)
- `kubectl` (for troubleshooter)
- `az` CLI (for Azure Application Insights queries)
- `jq` (optional, for merging existing settings.json)

## License

MIT
