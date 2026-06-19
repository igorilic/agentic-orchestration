#!/usr/bin/env bash
# lib/install-project.sh — part of ai-native-workflow. Sourced by the main
# dispatcher (not executed directly). Relies on the constants and colors
# defined in the main script before this file is sourced.
# shellcheck shell=bash

install_project() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  header "Installing project files in: $project_dir"
  echo ""

  # Detect stacks
  local stacks
  stacks=$(detect_stacks "$project_dir")
  local platform
  platform=$(detect_platform "$project_dir")

  if [ -z "$stacks" ]; then
    warn "No stack detected. Installing generic config."
    stacks="generic"
  fi

  info "Detected stacks: $(echo "$stacks" | tr '\n' ', ' | sed 's/,$//')"
  info "Platform: $platform"
  echo ""

  # --- AGENTS.md ---
  install_project_agents_md "$project_dir" "$stacks"

  # --- CLAUDE.md ---
  install_project_claude_md "$project_dir"

  # --- project context (docs/context/) + runtime dir (.anw/) ---
  install_project_context "$project_dir"

  # --- .github/ (copilot instructions) ---
  install_project_copilot "$project_dir" "$stacks"

  # --- .github/hooks/ (Copilot CLI dispatcher + vendored scorer) ---
  install_project_copilot_hooks "$project_dir"

  # --- .gitignore additions ---
  install_project_gitignore "$project_dir"

  # --- docs/decisions/ for ADRs ---
  mkdir -p "$project_dir/docs/decisions"
  success "docs/decisions/ (ADR directory)"

  echo ""
  header "Project installation complete"
  echo ""
  info "Installed in: $project_dir"
  info "Detected: $(echo "$stacks" | tr '\n' ', ' | sed 's/,$//')"
  info "Platform: $platform"
  echo ""
  info "Next steps:"
  dim "1. Edit AGENTS.md to customize for this project"
  dim "2. Edit docs/context/ARCHITECTURE.md with your system design"
  dim "3. Add domain terms to docs/context/GLOSSARY.md"
  dim "4. Start your first feature with /ticket or /tdd"
}

install_project_agents_md() {
  local project_dir="$1"
  local stacks="$2"
  local target="$project_dir/AGENTS.md"

  if [ -f "$target" ]; then
    warn "AGENTS.md already exists — skipping (use --force to overwrite)"
    return
  fi

  # Build stack-specific sections
  local stack_sections=""

  if echo "$stacks" | grep -q "dotnet"; then
    stack_sections="${stack_sections}
### .NET
- **Testing**: xUnit + FluentAssertions + NSubstitute
- **Pattern**: CQRS with MediatR, Result pattern for expected failures
- **Structure**: Api / Application / Domain / Infrastructure
- **DTOs**: Use C# records for immutability
"
  fi

  if echo "$stacks" | grep -q "go"; then
    stack_sections="${stack_sections}
### Go
- **Testing**: \`testing\` + testify, table-driven tests by default
- **Pattern**: Accept interfaces, return structs. Context as first param.
- **Structure**: cmd/ internal/ pkg/
- **Errors**: \`fmt.Errorf(\"context: %w\", err)\`
"
  fi

  if echo "$stacks" | grep -q "rust"; then
    stack_sections="${stack_sections}
### Rust
- **Testing**: Built-in + tokio-test
- **Pattern**: thiserror for libs, anyhow for apps. axum for web.
- **Structure**: src/ with handlers/ services/ models/ db/
"
  fi

  if echo "$stacks" | grep -q "python"; then
    stack_sections="${stack_sections}
### Python
- **Testing**: pytest with fixtures
- **Pattern**: Type hints everywhere, Pydantic for validation
- **Formatting**: Black (line length 88) + Ruff
"
  fi

  if echo "$stacks" | grep -q "react-native"; then
    stack_sections="${stack_sections}
### React Native / TypeScript
- **Testing**: Jest + React Native Testing Library. E2E: Detox
- **Platform-specific**: \`.ios.tsx\` / \`.android.tsx\` suffixes
"
  elif echo "$stacks" | grep -q "react-ts"; then
    local e2e_runner
    e2e_runner=$(detect_e2e_runner "$project_dir")
    local e2e_text=""
    [ -n "$e2e_runner" ] && e2e_text=". E2E: ${e2e_runner^}"

    local test_runner
    test_runner=$(detect_test_runner "$project_dir")
    [ -z "$test_runner" ] && test_runner="vitest"

    stack_sections="${stack_sections}
### React / TypeScript
- **Testing**: ${test_runner^} + React Testing Library${e2e_text}
- **Pattern**: Functional components only, custom hooks, Zod validation
- **Structure**: components/ features/ hooks/ lib/ types/
"
  elif echo "$stacks" | grep -q "typescript"; then
    stack_sections="${stack_sections}
### TypeScript
- **Testing**: Vitest or Jest
- **Pattern**: Type-safe, explicit error handling
"
  fi

  if echo "$stacks" | grep -q "swift"; then
    stack_sections="${stack_sections}
### Swift
- **Testing**: XCTest with protocol-based mocks
- **Pattern**: MVVM, protocol-oriented, async/await
"
  fi

  cat > "$target" << AGENTS_EOF
# AGENTS.md

> Cross-tool agent instructions. Read by Claude Code, GitHub Copilot, and other AI agents.

## Two Tracks: Production and Exploration

### Production (\`/plan\`)
For tickets, features, bug fixes, anything that ships. Pipeline:
**requirements-engineer → architect → tdd-developer → qa → reviewer**
(troubleshooter replaces requirements-engineer + architect for incidents).

### Exploration (\`/explore\`, \`/brainstorm\`)
For spikes, prototypes, API learning, vague ideas. Throwaway code under
\`spikes/<topic>/\` (gitignored). The TDD gate skips spike-only commits.
End with \`FINDINGS.md\`. To promote findings to production, re-enter
via \`/plan\`.

### When to skip both
Trivial only: typo, single-line config, comment-only, local rename.
Anything touching logic, types, public APIs, or 2+ files is non-trivial.
When in doubt, ask.

## Shorthand

- \`go\` — proceed with the proposed plan as-is
- \`fix\` — triage and address the issues just identified
- \`f\` / \`t\` / \`i\` — per-item triage on a numbered list:
  - \`f\` = fix now
  - \`t\` = log to tech debt (append to \`docs/context/CURRENT_SPRINT.md\`)
  - \`i\` = ignore, not a real issue
- Positional mapping: \`f t i f\` against a 4-item list maps 1→f, 2→t, 3→i, 4→f.

## Tool Preferences (decision order; negative rules are hard)

- Search content: \`rg\`. Never \`grep\` or \`find | xargs grep\`.
- Find files: \`fd\`. Never \`find\`.
- JSON: \`jq\`. Never sed/awk on JSON.
- CSV/TSV: \`python\` (csv module) or \`mlr\`. Never awk on CSV.
- Multi-step text processing: Python script, not chained sed/awk.
- Source-code edits: editor tool, never \`sed -i\`.
- Python one-offs: \`uv run --with <pkg> python ...\`. Never \`pip install\` to system.
- Git: never \`git add -A\` / \`git add .\`; list files. Never \`--force\`,
  use \`--force-with-lease\`. Never amend or rebase commits not yours.

## Core Rules

### 1. TDD is Mandatory
Every code change follows RED → GREEN → REFACTOR:
1. **RED**: Write failing test(s) FIRST. Run them. Confirm failure.
2. **GREEN**: Write MINIMUM code to pass. One test at a time.
3. **REFACTOR**: Improve code while keeping tests green.

Your first output for any feature request MUST be test code.
To bypass: use \`/skip-tdd\` with a reason (logged for accountability).

### 2. Stop and Ask When Uncertain
Do NOT guess. Stop and present options when:
- Requirements are ambiguous
- Multiple valid approaches exist
- Spec contradicts existing code
- Business logic is unclear

### 3. Document As You Go
- Update \`docs/context/CURRENT_SPRINT.md\` when task status changes
- Note architecture decisions in commit messages
- Flag documentation that needs updating

## Before Starting Any Work
1. Read the spec in \`docs/context/specs/\` if one exists
2. Scan \`docs/context/ARCHITECTURE.md\` for system context
3. Check \`docs/context/CONVENTIONS.md\` for stack patterns
4. Identify ALL affected components before writing code

## Commit Messages
Conventional Commits: \`<type>(<scope>): <description>\`
Types: \`feat\`, \`fix\`, \`test\`, \`refactor\`, \`docs\`, \`chore\`, \`ci\`, \`perf\`

## Test Organization
\`\`\`
tests/
├── unit/           # Fast, isolated, mocked dependencies
├── integration/    # Real DB via TestContainers
└── fixtures/       # Shared test data
\`\`\`

## Stack Conventions
${stack_sections}
### Database (PostgreSQL)
- **Tables**: snake_case, plural (\`users\`, \`order_items\`)
- **Primary keys**: \`id\` (UUID or serial)
- **Foreign keys**: \`{table_singular}_id\`
- **Migrations**: Always reversible, one concern per migration

## Error Reporting
\`\`\`
❌ ERROR: [What happened]
Context: [What was being attempted]
Location: [File/function]
Possible causes:
1. [Cause and fix]
Suggested action: [What to do next]
\`\`\`

## Session End Protocol
1. Ensure all tests pass
2. Commit pending changes
3. Update \`docs/context/CURRENT_SPRINT.md\`
4. Use \`/session-report\` to generate Obsidian report
AGENTS_EOF
  success "AGENTS.md (tailored for: $(echo "$stacks" | tr '\n' ', ' | sed 's/,$//'))"
}

install_project_claude_md() {
  local project_dir="$1"
  local target="$project_dir/CLAUDE.md"

  if [ -f "$target" ]; then
    warn "CLAUDE.md already exists — skipping"
    return
  fi

  local project_name
  project_name=$(basename "$project_dir")

  cat > "$target" << CLAUDE_EOF
# CLAUDE.md

> Project context for Claude Code. Behavioral rules are in AGENTS.md.

## Project
${project_name}

## Architecture
Read \`docs/context/ARCHITECTURE.md\` for system design.

## Current Work
Read \`docs/context/CURRENT_SPRINT.md\` for active tasks.

## Specs
Feature specifications are in \`docs/context/specs/\`.

## Commands
\`\`\`bash
make test              # Unit tests
make test-integration  # Integration tests
make test-e2e          # End-to-end tests
make lint              # Lint
make fmt               # Format
make build             # Build
make dev               # Local dev server
\`\`\`

## Key Paths
| Path | Purpose |
|---|---|
| \`docs/context/\` | Sprint board, tracked specs/todos, architecture, conventions, glossary |
| \`.anw/\` | Runtime pipeline state + confidence logs (gitignored) |
| \`docs/\` | Arc42 documentation + ADRs |
| \`tests/unit/\` | Unit tests |
| \`tests/integration/\` | Integration tests |
CLAUDE_EOF
  success "CLAUDE.md"
}

install_project_context() {
  local project_dir="$1"
  local docs_context_dir="$project_dir/docs/context"

  # Tracked project context lives under docs/context/ — the sprint board, spec
  # templates, and the installer-seeded ARCHITECTURE/CONVENTIONS/GLOSSARY that
  # the consuming project commits. Runtime artifacts (.pipeline-state,
  # .pipeline-audit.log, confidence *.jsonl) live under .anw/ and are gitignored.
  mkdir -p "$docs_context_dir/specs/templates"
  mkdir -p "$project_dir/.anw/specs"

  # Only create files that don't exist
  if [ ! -f "$docs_context_dir/ARCHITECTURE.md" ]; then
    cat > "$docs_context_dir/ARCHITECTURE.md" << 'EOF'
# Architecture

> Document your system architecture here.

## Overview
<!-- High-level system description -->

## Components
<!-- List major components and their responsibilities -->

## Data Flow
<!-- How data moves through the system -->

## Key Decisions
<!-- Link to ADRs: docs/decisions/ADR-*.md -->
EOF
    success "docs/context/ARCHITECTURE.md"
  fi

  if [ ! -f "$docs_context_dir/CONVENTIONS.md" ]; then
    cat > "$docs_context_dir/CONVENTIONS.md" << 'EOF'
# Conventions

> Stack-specific conventions for this project.
> See AGENTS.md for cross-tool agent rules.

## Project-Specific Patterns
<!-- Add project-specific conventions here -->
EOF
    success "docs/context/CONVENTIONS.md"
  fi

  if [ ! -f "$docs_context_dir/GLOSSARY.md" ]; then
    cat > "$docs_context_dir/GLOSSARY.md" << 'EOF'
# Glossary

> Domain terminology for this project.

| Term | Definition |
|---|---|
<!-- Add domain terms here -->
EOF
    success "docs/context/GLOSSARY.md"
  fi

  if [ ! -f "$docs_context_dir/CURRENT_SPRINT.md" ]; then
    cat > "$docs_context_dir/CURRENT_SPRINT.md" << 'EOF'
# Current Sprint

## In Progress
<!-- - [TICKET-ID] Description -->

## Up Next
<!-- - [TICKET-ID] Description -->

## Done (this sprint)
<!-- - [TICKET-ID] Description -->

## Blockers
<!-- - Description -->
EOF
    success "$SPRINT_FILE"
  fi

  if [ ! -f "$docs_context_dir/specs/templates/feature-spec.md" ]; then
    cat > "$docs_context_dir/specs/templates/feature-spec.md" << 'EOF'
# [TICKET-ID]: Feature Name

## Context
<!-- What problem does this solve? -->

## Acceptance Criteria
- [ ] <!-- Criterion 1 -->

## Technical Approach
<!-- How will this be implemented? -->

## Test Plan
### Unit Tests
- [ ] <!-- Test case -->

### Integration Tests
- [ ] <!-- Test case -->

## Open Questions
- <!-- Any ambiguity -->
EOF
    success "$SPEC_DIR/templates/feature-spec.md"
  fi
}

install_project_copilot() {
  local project_dir="$1"
  local stacks="$2"

  mkdir -p "$project_dir/.github/instructions"

  # --- copilot-instructions.md ---
  if [ ! -f "$project_dir/.github/copilot-instructions.md" ]; then
    cat > "$project_dir/.github/copilot-instructions.md" << 'COPILOT_EOF'
# Copilot Instructions

> Repository-wide instructions for GitHub Copilot agent mode.
> For detailed rules, see AGENTS.md at the project root.

## TDD Workflow (Non-Negotiable)
1. Write failing tests FIRST — your first output must be test code
2. Implement minimum code to pass tests
3. Refactor while keeping tests green

## Before Coding
- Check `docs/context/specs/` for feature specifications
- Read `docs/context/CONVENTIONS.md` for stack patterns
- Read `docs/context/ARCHITECTURE.md` for system context

## When Uncertain
Stop and ask. Present options with tradeoffs.

## Commit Messages
Conventional Commits: `<type>(<scope>): <description>`
Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `ci`, `perf`

## Code Standards
- Explicit over implicit
- Small functions (< 20 lines)
- Meaningful names (purpose, not implementation)
- Fail fast (validate early, return early)
- No magic numbers
- Type annotations on all signatures
COPILOT_EOF
    success ".github/copilot-instructions.md"
  fi

  # --- Path-specific instructions based on detected stacks ---

  if echo "$stacks" | grep -q "dotnet"; then
    if [ ! -f "$project_dir/.github/instructions/dotnet.instructions.md" ]; then
      cat > "$project_dir/.github/instructions/dotnet.instructions.md" << 'EOF'
---
applyTo: "**/*.cs"
---
Use xUnit for tests with FluentAssertions for assertions and NSubstitute for mocking.
Follow CQRS pattern with MediatR for command/query separation.
Use Result<T> pattern for expected failures — do not throw exceptions for business logic.
DTOs as C# records: `public record UserDto(int Id, string Name, string Email);`
Structure: Api → Application → Domain → Infrastructure.
Arrange-Act-Assert in all tests.
EOF
      success ".github/instructions/dotnet.instructions.md"
    fi
  fi

  if echo "$stacks" | grep -q "go"; then
    if [ ! -f "$project_dir/.github/instructions/go.instructions.md" ]; then
      cat > "$project_dir/.github/instructions/go.instructions.md" << 'EOF'
---
applyTo: "**/*.go"
---
Use table-driven tests with testify assertions as the default pattern.
Accept interfaces, return structs. Always pass context.Context as first parameter.
Wrap errors with context: `fmt.Errorf("operation: %w", err)`.
Package names: lowercase, short, no underscores (`user`, `auth`).
Exported: PascalCase. Unexported: camelCase.
EOF
      success ".github/instructions/go.instructions.md"
    fi
  fi

  if echo "$stacks" | grep -q "rust"; then
    if [ ! -f "$project_dir/.github/instructions/rust.instructions.md" ]; then
      cat > "$project_dir/.github/instructions/rust.instructions.md" << 'EOF'
---
applyTo: "**/*.rs"
---
Use thiserror for library error types, anyhow for application error handling.
Prefer axum for web services with tokio async runtime.
Derive liberally: `#[derive(Debug, Clone, Serialize, Deserialize)]`.
Tests in `#[cfg(test)] mod tests` within the same file.
Use `#[tokio::test]` for async tests.
EOF
      success ".github/instructions/rust.instructions.md"
    fi
  fi

  if echo "$stacks" | grep -q "python"; then
    if [ ! -f "$project_dir/.github/instructions/python.instructions.md" ]; then
      cat > "$project_dir/.github/instructions/python.instructions.md" << 'EOF'
---
applyTo: "**/*.py"
---
Type hints on ALL function signatures.
Pydantic models for data validation and DTOs.
Format: Black (line length 88). Lint: Ruff. Imports: isort.
pytest with fixtures (conftest.py). Async preferred for I/O.
Private: leading underscore. Constants: UPPER_SNAKE_CASE.
EOF
      success ".github/instructions/python.instructions.md"
    fi
  fi

  if echo "$stacks" | grep -qE "react-ts|react-native|typescript"; then
    if [ ! -f "$project_dir/.github/instructions/typescript.instructions.md" ]; then
      cat > "$project_dir/.github/instructions/typescript.instructions.md" << 'EOF'
---
applyTo: "**/*.ts,**/*.tsx"
---
Functional components only — no class components.
Extract complex state logic into custom hooks (`use` prefix).
Zod for runtime validation of external data.
Props interfaces: PascalCase with Props suffix (`UserCardProps`).
Constants: UPPER_SNAKE_CASE. Test behavior, not implementation.
EOF
      success ".github/instructions/typescript.instructions.md"
    fi
  fi

  if echo "$stacks" | grep -q "swift"; then
    if [ ! -f "$project_dir/.github/instructions/swift.instructions.md" ]; then
      cat > "$project_dir/.github/instructions/swift.instructions.md" << 'EOF'
---
applyTo: "**/*.swift"
---
MVVM architecture with protocol-oriented design.
Use async/await for all asynchronous code.
Protocol-based mocks for testing with XCTest.
Prefer protocols over inheritance. Use Combine or async sequences for reactive streams.
@Published properties in ViewModels for SwiftUI bindings.
EOF
      success ".github/instructions/swift.instructions.md"
    fi
  fi
}

install_project_copilot_hooks() {
  local project_dir="$1"
  local hooks_dir="$project_dir/.github/hooks"
  local scripts_dir="$hooks_dir/scripts"

  mkdir -p "$scripts_dir"
  success ".github/hooks/scripts/ (Copilot CLI hook directories)"

  # Vendor confidence scorer so the hook is self-contained (OQ-4).
  cp "$_ANW_SCRIPT_DIR/scripts/confidence.sh" "$scripts_dir/confidence.sh"
  chmod 0755 "$scripts_dir/confidence.sh"
  success ".github/hooks/scripts/confidence.sh (vendored scorer)"

  # Write the Copilot CLI dispatcher (Steps 4+5).
  # Step 11: Write to a temp file first so we can cmp with any existing copy.
  # If content is identical → skip (idempotent). If differs → backup, then overwrite.
  # Using a quoted heredoc (<<'DISPATCHER_EOF') so all '$' are literal in the
  # output script — they must be runtime variables, not install-time expansions.
  local dispatcher="$hooks_dir/copilot-cli-dispatcher.sh"
  local dispatcher_tmp
  dispatcher_tmp="$(mktemp /tmp/copilot-dispatcher-XXXXXX.sh)"
  cat > "$dispatcher_tmp" <<'DISPATCHER_EOF'
#!/usr/bin/env bash
# copilot-cli-dispatcher.sh — ai-native-workflow Copilot CLI pre-tool hook
# Enforces TDD and confidence gates for GitHub Copilot CLI.
# Contract: read JSON payload from stdin; write permissionDecision JSON to stdout.
# CRITICAL: Must be fail-closed — crash → deny (via trap ERR below).
set -euo pipefail

# ---------------------------------------------------------------------------
# emit_deny: write deny JSON to stdout, then exit 0.
# Exit 0 because Copilot reads the decision from stdout JSON, not exit code.
# No stderr output — bats merges stdout+stderr into $output by default.
# jq-free fallback: if jq is missing, printf with manual escaping preserves
# the fail-closed guarantee (ADR-001 invariant).
# ---------------------------------------------------------------------------
emit_deny() {
  local reason="${1:-hook crashed; failing closed}"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" '{permissionDecision: "deny", permissionDecisionReason: $r}'
  else
    # jq-free fallback: minimal JSON via printf with manual escaping
    local escaped="${reason//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\n'/\\n}"
    escaped="${escaped//$'\r'/}"
    escaped="${escaped//$'\t'/\\t}"
    printf '{"permissionDecision":"deny","permissionDecisionReason":"%s"}\n' "$escaped"
  fi
  exit 0
}

# Fail-closed trap: any unhandled error → deny.
trap 'emit_deny "Copilot hook crashed unexpectedly"' ERR

# Early jq presence check: deny cleanly if jq is not available.
command -v jq >/dev/null 2>&1 || emit_deny "jq not found on PATH; cannot enforce gates"

# ---------------------------------------------------------------------------
# Read the payload exactly once from stdin.
# jq -e fails (exit 1) on invalid JSON or null — triggers ERR trap → deny.
# ---------------------------------------------------------------------------
PAYLOAD="$(cat)"
# Validate JSON and parse toolName; invalid/empty payload fails here (fail-closed).
TOOL_NAME="$(echo "$PAYLOAD" | jq -re '.toolName')"

# Filter: if toolName != "bash" allow immediately — no gate applies.
if [ "$TOOL_NAME" != "bash" ]; then
  jq -nc '{permissionDecision: "allow"}'
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 5: Resolve the project directory.
# Priority: payload .cwd → git rev-parse --show-toplevel.
# ---------------------------------------------------------------------------
PROJECT_DIR="$(echo "$PAYLOAD" | jq -r '.cwd // empty')"

# Walk up via git from the given cwd (or pwd if not provided).
_candidate="${PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(git -C "$_candidate" rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$PROJECT_DIR" ]; then
  emit_deny "cannot resolve project dir"
fi

[ "${ANW_DEBUG:-0}" = "1" ] && printf 'PROJECT_DIR=%s\n' "$PROJECT_DIR" >&2

# ---------------------------------------------------------------------------
# Step 8: TDD gate — port of hooks/tdd-gate.sh (exit-code → emit_deny/allow).
# Only fires on bash commands that match "git commit".
# ---------------------------------------------------------------------------
BASH_CMD="$(echo "$PAYLOAD" | jq -re '.toolArgs | fromjson | .command' 2>/dev/null)" || \
  emit_deny "could not extract bash command from payload (malformed toolArgs)"

if echo "$BASH_CMD" | grep -qE 'git\s+commit'; then
  # Allow amend
  if echo "$BASH_CMD" | grep -qE -- '--amend'; then
    jq -nc '{permissionDecision: "allow"}'
    exit 0
  fi

  # Check bypass file
  if [ -f "$PROJECT_DIR/.tdd-skip" ]; then
    jq -nc '{permissionDecision: "allow"}'
    exit 0
  fi

  # Spike-only commits skip the TDD gate
  STAGED_FILES="$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null || true)"
  NON_SPIKE_FILES="$(echo "$STAGED_FILES" | grep -v '^spikes/' | grep -v '^$' || true)"
  if [ -n "$STAGED_FILES" ] && [ -z "$NON_SPIKE_FILES" ]; then
    jq -nc '{permissionDecision: "allow"}'
    exit 0
  fi

  # Check for test files in staged changes
  TEST_PATTERNS='(test|spec|_test\.|\.test\.|\.spec\.|tests/|__tests__/|Tests/|Test\.)'
  TEST_FILES="$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | grep -iE "$TEST_PATTERNS" || true)"

  if [ -z "$TEST_FILES" ]; then
    MSG="$(printf 'TDD gate: No test files in staged changes. Options: 1. Write tests first, stage them, commit together. 2. /skip-tdd '"'"'reason'"'"' to bypass (logged).')"
    emit_deny "$MSG"
  fi
fi

# ---------------------------------------------------------------------------
# Step 9+10: Confidence gate — port of hooks/confidence-gate.sh.
# Only fires on PR/MR creation commands.
# ---------------------------------------------------------------------------
SCORER="$PROJECT_DIR/.github/hooks/scripts/confidence.sh"

if echo "$BASH_CMD" | grep -qE '(gh\s+pr\s+create(\s|$)|glab\s+mr\s+create(\s|$))'; then
  ACTIVE_SPEC_FILE="$PROJECT_DIR/.git/aw/active-spec"
  if [ ! -f "$ACTIVE_SPEC_FILE" ]; then
    emit_deny "Confidence gate: no .git/aw/active-spec pointer. The pipeline driver writes this file. If you ran agents manually, set it explicitly: echo PROJ-123 > .git/aw/active-spec"
  fi

  SPEC_ID="$(cat "$ACTIVE_SPEC_FILE" | tr -d '[:space:]')"
  if ! echo "$SPEC_ID" | grep -qE '^[A-Za-z0-9._-]+$'; then
    emit_deny "Confidence gate: invalid spec id '$SPEC_ID' — must match [A-Za-z0-9._-]+"
  fi

  CONF_LOG="$PROJECT_DIR/.anw/specs/${SPEC_ID}-confidence.jsonl"
  if [ ! -f "$CONF_LOG" ]; then
    emit_deny "Confidence gate: log not found at $CONF_LOG"
  fi

  # Run vendored scorer
  VERDICT_JSON="$("$SCORER" "$CONF_LOG" 2>&1)" || {
    emit_deny "Confidence gate: scorer failed — blocking as safety default."
  }
  BAND="$(echo "$VERDICT_JSON" | jq -r '.band' 2>/dev/null)" || BAND=""
  SCORE="$(echo "$VERDICT_JSON" | jq -r '.score' 2>/dev/null)" || SCORE=""
  GATES="$(echo "$VERDICT_JSON" | jq -c '.gates' 2>/dev/null)" || GATES="[]"

  if [ -z "$BAND" ] || [ -z "$SCORE" ]; then
    emit_deny "Confidence gate: scorer output is malformed — blocking as safety default."
  fi

  # Append aggregate verdict to log
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg ts "$TS" \
    --arg band "$BAND" \
    --argjson score "$SCORE" \
    --argjson gates "$GATES" \
    '{ts:$ts, event:"verdict", scope:"aggregate", band:$band, score:$score, gates:$gates}' \
    >> "$CONF_LOG"

  case "$BAND" in
    GREEN)
      jq -nc '{permissionDecision: "allow"}'
      exit 0
      ;;
    YELLOW)
      # Include "YELLOW" in permissionDecisionReason so callers can detect the band.
      jq -nc --arg r "Confidence: YELLOW ($SCORE/100) — proceeding with caution." \
        '{permissionDecision: "allow", permissionDecisionReason: $r}'
      exit 0
      ;;
    RED)
      SKIP_TDD_FILE="$PROJECT_DIR/.tdd-skip"
      if [ -f "$SKIP_TDD_FILE" ]; then
        STRUCTURAL_GATES='["NO_AC","AC_NOT_TESTED"]'
        ALL_STRUCTURAL="$(jq -n --argjson g "$GATES" --argjson s "$STRUCTURAL_GATES" \
          '($g | length) > 0 and ($g - $s | length) == 0')"

        if [ "$ALL_STRUCTURAL" = "true" ]; then
          SKIP_REASON="$(grep -m 1 '^Reason:' "$SKIP_TDD_FILE" | sed 's/^Reason: *//' || true)"
          jq -n \
            --arg ts "$TS" \
            --arg reason "${SKIP_REASON:-skip-tdd active}" \
            --argjson gates "$GATES" \
            '{ts:$ts, event:"override", trigger:"skip-tdd-auto", reason:$reason, gates_bypassed:$gates}' \
            >> "$CONF_LOG"
          jq -nc '{permissionDecision: "allow"}'
          exit 0
        else
          MSG="$(printf 'Confidence: RED (%s/100) — gates: %s\n\n/skip-tdd does not bypass behavioral gates. Use /override-confidence "<reason>".' "$SCORE" "$GATES")"
          emit_deny "$MSG"
        fi
      fi

      OVERRIDE_FILE="$PROJECT_DIR/.git/aw/override-${SPEC_ID}"
      if [ -f "$OVERRIDE_FILE" ]; then
        if ! OVERRIDE_REASON="$(jq -re '.reason // empty' "$OVERRIDE_FILE" 2>/dev/null)"; then
          rm -f "$OVERRIDE_FILE"
          emit_deny "override marker is malformed; deleted"
        fi
        if [ -z "$OVERRIDE_REASON" ] || [ "$OVERRIDE_REASON" = "null" ]; then
          rm -f "$OVERRIDE_FILE"
          emit_deny "override marker has empty/null reason; deleted"
        fi
        jq -n \
          --arg ts "$TS" \
          --arg reason "$OVERRIDE_REASON" \
          --argjson gates "$GATES" \
          '{ts:$ts, event:"override", trigger:"manual", reason:$reason, gates_bypassed:$gates}' \
          >> "$CONF_LOG"
        rm -f "$OVERRIDE_FILE"
        jq -nc '{permissionDecision: "allow"}'
        exit 0
      fi

      emit_deny "$(printf 'Confidence gate: RED (%s/100) — gates: %s. Options: 1. Address the failing gates and retry. 2. /override-confidence "<reason>" to bypass (logged).' "$SCORE" "$GATES")"
      ;;
    *)
      emit_deny "Confidence gate: unexpected band value '$BAND' — blocking as safety default."
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Fall-through: no gate applies.
# ---------------------------------------------------------------------------
jq -nc '{permissionDecision: "allow"}'
exit 0
DISPATCHER_EOF

  # Step 11: idempotency + backup-on-mismatch.
  if [ -f "$dispatcher" ] && cmp -s "$dispatcher_tmp" "$dispatcher"; then
    # Content identical — skip overwrite to avoid spurious churn.
    rm -f "$dispatcher_tmp"
    dim ".github/hooks/copilot-cli-dispatcher.sh already up to date"
  else
    if [ -f "$dispatcher" ]; then
      cp "$dispatcher" "${dispatcher}${BACKUP_SUFFIX}"
      dim "Backed up existing copilot-cli-dispatcher.sh"
    fi
    mv "$dispatcher_tmp" "$dispatcher"
    chmod 0755 "$dispatcher"
    success ".github/hooks/copilot-cli-dispatcher.sh (Copilot CLI dispatcher)"
  fi

  # Step 11: Write .github/hooks/README.md explaining the hook layer.
  local readme="$hooks_dir/README.md"
  if [ ! -f "$readme" ]; then
    cat > "$readme" <<'README_EOF'
# .github/hooks — AI-Native Workflow: Copilot CLI Hook Layer

This directory contains the **per-project Copilot CLI hook** for
[ai-native-workflow](https://github.com/igorIlic/agentic-orchestration).

## Purpose

Two quality gates are enforced at the Copilot CLI `preToolUse` hook:

1. **TDD gate** — blocks `git commit` unless test files are staged.
2. **Confidence gate** — blocks `gh pr create` / `glab mr create` when the
   active spec's aggregate confidence score is RED.

These mirror the Claude Code global hooks (`~/.claude/hooks/tdd-gate.sh` and
`~/.claude/hooks/confidence-gate.sh`) but are **per-project** because Copilot
CLI does not support user-global hooks — only repository-scoped ones.

## Files

| File | Purpose |
|------|---------|
| `copilot-cli-dispatcher.sh` | Single entry point; routes to TDD + confidence gates |
| `scripts/confidence.sh` | Vendored confidence scorer (self-contained copy) |
| `copilot-cli-policy.json` | Registers this dispatcher as a `preToolUse` hook |

## Bypassing

- **TDD gate**: run `/skip-tdd "reason"` — creates `.tdd-skip`; logged.
- **Confidence gate (structural-only gates)**: `.tdd-skip` auto-bypasses
  `NO_AC` and `AC_NOT_TESTED` gates.
- **Confidence gate (behavioral gates)**: run `/override-confidence "reason"`
  — creates `.git/aw/override-<spec-id>`; consumed once then deleted.

## Audit Trail

Every confidence gate verdict and bypass is appended to:

```
.anw/specs/<spec-id>-confidence.jsonl
```

This file is gitignored (runtime state) but retained for local audit.

## Asymmetry vs Claude Code

| | Claude Code | Copilot CLI |
|---|---|---|
| Hook scope | Global (`~/.claude/hooks/`) | Per-project (`.github/hooks/`) |
| TDD gate | `tdd-gate.sh` | `copilot-cli-dispatcher.sh` |
| Confidence gate | `confidence-gate.sh` | `copilot-cli-dispatcher.sh` |
| Scorer | `~/.claude/scripts/confidence.sh` | `.github/hooks/scripts/confidence.sh` (vendored) |
README_EOF
    success ".github/hooks/README.md (Copilot CLI hook documentation)"
  else
    dim ".github/hooks/README.md already exists — skipping"
  fi

  # Write / merge copilot-cli-policy.json (Steps 6 + 7).
  local policy="$hooks_dir/copilot-cli-policy.json"
  local tmp_policy
  tmp_policy="$(mktemp /tmp/copilot-policy-XXXXXX.json)"

  if ! command -v jq &> /dev/null; then
    # jq not available — write a static minimal policy without merging.
    # Any existing user entries will NOT be merged; warn accordingly.
    warn "jq not found — writing static copilot-cli-policy.json (existing entries not merged). Install jq and re-run to merge."
    cat > "$tmp_policy" <<'STATIC_POLICY_EOF'
{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"./copilot-cli-dispatcher.sh","cwd":".github/hooks","timeoutSec":15,"comment":"ai-native-workflow TDD + confidence gate dispatcher"}]}}
STATIC_POLICY_EOF
  else
    local dispatcher_entry
    dispatcher_entry="$(jq -nc '{"type":"command","bash":"./copilot-cli-dispatcher.sh","cwd":".github/hooks","timeoutSec":15,"comment":"ai-native-workflow TDD + confidence gate dispatcher"}')"

    if [ ! -f "$policy" ]; then
      # Fresh install: write a minimal policy with only our dispatcher entry.
      jq -n --argjson entry "$dispatcher_entry" \
        '{version:1,hooks:{preToolUse:[$entry]}}' \
        | jq -e . > "$tmp_policy"
    else
      # Merge: append our entry and dedupe by .bash (preserves user entries).
      jq --argjson entry "$dispatcher_entry" \
        '.hooks.preToolUse = ((.hooks.preToolUse // []) + [$entry] | unique_by(.bash))' \
        "$policy" \
        | jq -e . > "$tmp_policy"
    fi
  fi

  mv "$tmp_policy" "$policy"
  success ".github/hooks/copilot-cli-policy.json (Copilot CLI hook policy)"
}

install_project_gitignore() {
  local project_dir="$1"
  local gitignore="$project_dir/.gitignore"

  # .anw/ is purely runtime now (pipeline state, audit log, confidence logs), so
  # ignore the whole directory rather than listing individual files.
  local entries=(".tdd-skip" ".claude/settings.local.json" ".anw/")
  local added=0

  for entry in "${entries[@]}"; do
    if [ -f "$gitignore" ]; then
      if ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
        echo "$entry" >> "$gitignore"
        added=$((added + 1))
      fi
    else
      echo "$entry" >> "$gitignore"
      added=$((added + 1))
    fi
  done

  if [ "$added" -gt 0 ]; then
    success ".gitignore (added $added entries)"
  else
    dim ".gitignore already up to date"
  fi
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                     STATUS / DETECT / UNINSTALL                 ║
# ╚══════════════════════════════════════════════════════════════════╝

