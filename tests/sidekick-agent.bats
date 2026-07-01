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
