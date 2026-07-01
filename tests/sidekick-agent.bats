#!/usr/bin/env bats

# SDK-1 Step A-1: sidekick agent contract + install wiring (GATE).
#
# Verifies:
#   - the source agents/claude-code/sidekick.md frontmatter is exactly the
#     OQ-6 decision: model: haiku, tools: Read, Write, Edit, Glob, Grep
#     (no Bash, no Task);
#   - `install global` into a sandbox CLAUDE_HOME picks up sidekick.md via
#     the existing agents/claude-code/*.md glob with ZERO installer changes
#     (lib/install-global.sh:593-607, install_global_agents()).
#
# Note: CLAUDE_HOME is the target .claude directory itself (not its parent),
# same convention as tests/install.bats.
#
# Test-hardening (A-1 fix loop, post qa/reviewer):
#   - F1: setup() sandboxes HOME/CLAUDE_HOME/COPILOT_HOME and stubs `copilot`
#     onto PATH, mirroring tests/diff-reviewer.bats's claude_install() /
#     tests/install-copilot.bats, so `install global` can never write to the
#     real ~/.claude or ~/.copilot.
#   - F2: frontmatter assertions are scoped to the frontmatter block (between
#     the first two `---` lines) and require exactly ONE occurrence of each
#     of name/model/tools there; `tools` is checked by set-equality against
#     the exact five-tool whitelist rather than a Bash/Task blacklist. This
#     closes two live bypasses where a decoy line in the BODY satisfied the
#     old file-wide, non-anchored-to-frontmatter `grep -q`:
#       Bypass A: frontmatter grants extra tools (WebFetch, SlashCommand)
#                 + a body line repeating the exact compliant tools string.
#       Bypass B: frontmatter pins model: sonnet + a body line "model: haiku".
#     Two regression tests below construct exactly these mutants and assert
#     the hardened checks reject them.
#   - F3: install-wiring tests now `run` the installer and assert exit 0
#     (previously discarded via `>/dev/null 2>&1`), so a partially-broken
#     install under `set -euo pipefail` can't show a false green.
#
# SDK-1 Step A-2: sidekick prompt BODY contract (frontmatter untouched).
#   Adds body()-scoped assertions (mirroring frontmatter()'s scoping) for:
#   a mechanical-only allowlist section, an explicit refuse-if-judgment
#   clause, a forbidden-actions list (git/CI/migrations/deploys/test
#   assertions/design), a no-Bash reminder ("parent runs, sidekick applies"),
#   a hand-back-for-review note, and the OQ-1 no-literal-sentinel-prefix rule.

INSTALLER="$BATS_TEST_DIRNAME/../ai-native-workflow"
SIDEKICK_SRC="$BATS_TEST_DIRNAME/../agents/claude-code/sidekick.md"

setup() {
  SANDBOX="$(mktemp -d /tmp/aw-sidekick-install-XXXXXX)"
  STUB_BIN="$(mktemp -d /tmp/aw-sidekick-stub-XXXXXX)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/copilot"
  chmod +x "$STUB_BIN/copilot"

  # Hermetic sandbox (F1): every path the installer can write to is pinned
  # inside $SANDBOX, and a stubbed `copilot` shadows any real one on PATH.
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  export CLAUDE_HOME="$SANDBOX/claude"
  export COPILOT_HOME="$SANDBOX/copilot"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  rm -rf "$SANDBOX" "$STUB_BIN"
}

# Extract just the YAML frontmatter block (the lines strictly between the
# first two `---` delimiters), so BODY content can never satisfy a
# frontmatter-only assertion.
frontmatter() {
  awk '
    /^---$/ { c++; next }
    c==1
  ' "$1"
}

# Extract the prompt BODY (everything strictly after the second `---`
# delimiter), so frontmatter content can never satisfy a body-only
# assertion (and vice versa).
body() {
  awk '
    /^---$/ { c++; next }
    c>=2
  ' "$1"
}

# Assert a `tools:` line (e.g. "tools: Read, Write, Edit, Glob, Grep") is a
# set-equals match against the exact five-tool whitelist, order-independent.
# This is a positive whitelist check (not a Bash/Task blacklist): anything
# added or missing is rejected, whatever its name.
assert_tools_whitelist() {
  local line="$1" got want
  got="$(printf '%s' "${line#tools: }" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort | tr '\n' ',')"
  want="$(printf 'Read\nWrite\nEdit\nGlob\nGrep\n' | sort | tr '\n' ',')"
  [ "$got" = "$want" ]
}

# ---------------------------------------------------------------------------
# Source frontmatter contract (OQ-6)
# ---------------------------------------------------------------------------

@test "sidekick source: agents/claude-code/sidekick.md exists" {
  [ -f "$SIDEKICK_SRC" ]
}

@test "sidekick source: frontmatter name is sidekick (scoped + unique)" {
  fm="$(frontmatter "$SIDEKICK_SRC")"
  count="$(grep -cE '^name: sidekick$' <<<"$fm" || true)"
  [ "$count" -eq 1 ]
}

@test "sidekick source: frontmatter model is haiku (scoped + unique, no pinned version)" {
  fm="$(frontmatter "$SIDEKICK_SRC")"
  count="$(grep -cE '^model: haiku$' <<<"$fm" || true)"
  [ "$count" -eq 1 ]
}

@test "sidekick source: frontmatter tools set-equals the exact whitelist (scoped + unique)" {
  fm="$(frontmatter "$SIDEKICK_SRC")"
  count="$(grep -cE '^tools:' <<<"$fm" || true)"
  [ "$count" -eq 1 ]
  tools_line="$(grep -E '^tools:' <<<"$fm")"
  assert_tools_whitelist "$tools_line"
}

# ---------------------------------------------------------------------------
# Prompt BODY contract (OQ-6 / Step A-2): mechanical-only, refuse-if-judgment,
# forbidden actions. Scoped to the body (via body()) so a frontmatter-only
# file (e.g. the A-1 skeleton) fails these for the right reason.
# ---------------------------------------------------------------------------

@test "sidekick body: contains a mechanical-only allowlist section" {
  bd="$(body "$SIDEKICK_SRC")"
  echo "$bd" | grep -qiE 'allow[- ]?list'
  echo "$bd" | grep -qiE 'scaffold.*(file|template)'
  echo "$bd" | grep -qiE 'lint|format|type-fix'
  echo "$bd" | grep -qiE 'fixture'
  echo "$bd" | grep -qiE 'mock'
  echo "$bd" | grep -qiE 'find-replace|find/replace|find and replace'
}

@test "sidekick body: contains an explicit refuse-if-judgment clause" {
  bd="$(body "$SIDEKICK_SRC")"
  echo "$bd" | grep -qiE 'refuse'
  echo "$bd" | grep -qiE 'judg?e?ment'
  echo "$bd" | grep -qiE 'hand.?back'
}

@test "sidekick body: contains a forbidden-actions list (git/CI/migrations/deploys/test-assertions/design)" {
  bd="$(body "$SIDEKICK_SRC")"
  echo "$bd" | grep -qiE 'forbidden'
  echo "$bd" | grep -qiE '\bgit\b'
  echo "$bd" | grep -qiE '\bCI\b|CI/CD|continuous integration'
  echo "$bd" | grep -qiE 'migration'
  echo "$bd" | grep -qiE 'deploy'
  echo "$bd" | grep -qiE 'test assertion'
  echo "$bd" | grep -qiE 'design|architecture'
}

@test "sidekick body: no-Bash reminder — the parent runs tools, sidekick applies edits" {
  bd="$(body "$SIDEKICK_SRC")"
  echo "$bd" | grep -qiE '\bBash\b'
  echo "$bd" | grep -qiE 'parent (runs|run)'
}

@test "sidekick body: hand-back-for-review note (parent vets/accepts output)" {
  bd="$(body "$SIDEKICK_SRC")"
  echo "$bd" | grep -qiE 'review'
  echo "$bd" | grep -qiE 'vet|accept'
}

@test "sidekick body: contains no literal sentinel prefix (OQ-1 redaction rule)" {
  bd="$(body "$SIDEKICK_SRC")"
  ! echo "$bd" | grep -qF '@@ANW|'
}

# ---------------------------------------------------------------------------
# Regression guards: the hardened checks must reject the exact bypasses
# qa demonstrated against the old, unscoped file-wide grep -q assertions.
# ---------------------------------------------------------------------------

@test "sidekick source: hardened tools check rejects Bypass A (frontmatter superset + decoy body line)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  cat > "$mutant" <<'EOF'
---
name: sidekick
model: haiku
tools: Read, Write, Edit, Glob, Grep, WebFetch, SlashCommand
---

You are the sidekick.

tools: Read, Write, Edit, Glob, Grep
EOF
  fm="$(frontmatter "$mutant")"
  tools_line="$(grep -E '^tools:' <<<"$fm")"
  run assert_tools_whitelist "$tools_line"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "sidekick source: hardened model check rejects Bypass B (frontmatter sonnet + decoy body line)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  cat > "$mutant" <<'EOF'
---
name: sidekick
model: sonnet
tools: Read, Write, Edit, Glob, Grep
---

You are the sidekick.

model: haiku
EOF
  fm="$(frontmatter "$mutant")"
  count="$(grep -cE '^model: haiku$' <<<"$fm" || true)"
  rm -rf "$mutant_dir"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Install wiring: zero installer changes, picked up by the existing glob
# ---------------------------------------------------------------------------

@test "install global: sidekick.md lands in the installed agents dir" {
  run "$INSTALLER" install global
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_HOME/agents/sidekick.md" ]
}

@test "install global: installed sidekick.md byte-matches source (no drift)" {
  run "$INSTALLER" install global
  [ "$status" -eq 0 ]
  cmp -s "$SIDEKICK_SRC" "$CLAUDE_HOME/agents/sidekick.md"
}

@test "install global: installed sidekick.md frontmatter preserves model: haiku and exact tools" {
  run "$INSTALLER" install global
  [ "$status" -eq 0 ]
  fm="$(frontmatter "$CLAUDE_HOME/agents/sidekick.md")"
  [ "$(grep -cE '^model: haiku$' <<<"$fm" || true)" -eq 1 ]
  tools_line="$(grep -E '^tools:' <<<"$fm")"
  assert_tools_whitelist "$tools_line"
}
