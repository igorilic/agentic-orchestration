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
#
# A-2 fix loop (post qa, F1-F4): the body()-scoped assertions above were
# still file-wide within the body — a body-wide `grep -qiE '\bgit\b'` etc. is
# satisfied by ANY section, not necessarily the one it's meant to pin. qa
# proved this: gutting the entire `## Forbidden actions` bullet list (heading
# kept) left every "forbidden actions" test green, because the `## No Bash`
# section's prose ("cannot run git, CI, migrations, or deploys") happens to
# repeat the same keywords.
#   - F1: adds a `section()` awk slicer (mirrors frontmatter()/body(): same
#     `---`-delimiter counting technique, extended to slice on `## <heading>`
#     boundaries within the body) and a `gut_section()` mutant-builder that
#     reproduces qa's exact probe (blank a named section's content, keep its
#     heading, leave the rest of the real file untouched). Each body clause
#     assertion is now factored into an `assert_*_section()` helper called
#     against `section()` output, so the SAME assertion logic backs both the
#     real (must-pass) test and a durable mutation-guard test (must-reject-
#     the-gutted-mutant) for Forbidden actions, Refuse-if-judgment, and the
#     Mechanical-only allowlist — closing exactly the bypass qa found.
#   - F2: new `## Write-path scope` section + scoped test — the old body only
#     constrained task *categories*, never write *paths*, so a delegated
#     sidekick could technically `Write` `.git/hooks/pre-commit`,
#     `.github/workflows/*.yml`, or `.env`. Soft-gate clause (OQ-4 style; no
#     hard enforcement) requiring refuse-and-hand-back for those paths.
#   - F3: the allowlist's "config" bullet contradicted the forbidden CI/CD
#     rule (config files were in-scope, CI/CD files were both "config" and
#     forbidden). The bullet now explicitly carves out CI/CD, workflow, and
#     secret/credential files as excluded from the config scaffold bullet.
#   - F4: new `## No destructive overwrites` section + scoped test — nothing
#     previously stopped a sidekick from silently truncating/overwriting an
#     existing file's contents while "scaffolding". Clause requires the
#     parent to have named the exact file + replacement content first.
#   F5 (imprecise "apply lint/format/type-fix output" wording) and F6 (no
#   warning against reading/echoing secret contents) are deferred; not fixed
#   here.

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

# Extract one `## <heading>` section from the BODY: the heading line itself
# plus every line up to (not including) the next `## ` heading. Scopes an
# assertion to exactly its own section, so content that lives in ANOTHER
# section (or the intro prose before the first heading) can never satisfy
# it. Mirrors frontmatter()/body()'s `---`-delimiter counting, extended with
# a second state flag for the `## ` boundary.
section() {
  local file="$1" want="## $2"
  awk -v want="$want" '
    /^---$/ { c++; next }
    c<2 { next }
    /^## / {
      if ($0 == want) { infield=1 } else { infield=0 }
      if (infield) print
      next
    }
    infield { print }
  ' "$file"
}

# Build a mutant copy of $1 with the named section's content blanked (its
# `## <heading>` line kept, every line under it up to the next `## `
# heading removed) — reproducing qa's exact F1 probe against an otherwise
# untouched copy of the real file, so a mutation-guard test proves the
# hardened section()-scoped assertion rejects it even though the rest of the
# file (e.g. the No-Bash section's git/CI/migrations/deploys prose) is
# still intact and would have fooled the old, unscoped body-wide grep.
gut_section() {
  local src="$1" want="## $2"
  awk -v want="$want" '
    $0 == want { print; skip=1; next }
    /^## / { skip=0 }
    skip { next }
    { print }
  ' "$src"
}

# --- Section-scoped assertion helpers -------------------------------------
# Each takes section() output and asserts every required item is present
# WITHIN it. Shared by the real (must-pass) tests below and by the durable
# mutation-guard tests, so both exercise identical logic.

assert_allowlist_section() {
  local sec="$1"
  echo "$sec" | grep -qiE 'scaffold.*(file|template)' &&
  echo "$sec" | grep -qiE 'lint|format|type-fix' &&
  echo "$sec" | grep -qiE 'fixture' &&
  echo "$sec" | grep -qiE 'mock' &&
  echo "$sec" | grep -qiE 'find-replace|find/replace|find and replace'
}

assert_refuse_section() {
  local sec="$1"
  echo "$sec" | grep -qiE 'refuse' &&
  echo "$sec" | grep -qiE 'judg?e?ment' &&
  echo "$sec" | grep -qiE 'hand.*back'
}

assert_forbidden_section() {
  local sec="$1"
  echo "$sec" | grep -qiE '\bgit\b' &&
  echo "$sec" | grep -qiE '\bCI\b|CI/CD|continuous integration' &&
  echo "$sec" | grep -qiE 'migration' &&
  echo "$sec" | grep -qiE 'deploy' &&
  echo "$sec" | grep -qiE 'test assertion' &&
  echo "$sec" | grep -qiE 'design|architecture'
}

assert_write_path_section() {
  local sec="$1"
  echo "$sec" | grep -qiE '\.git/' &&
  echo "$sec" | grep -qiE '\.github/workflows|CI/CD|workflow' &&
  echo "$sec" | grep -qiE '\.env|secret|credential' &&
  echo "$sec" | grep -qiE 'refuse' &&
  echo "$sec" | grep -qiE 'explicitly named'
}

assert_no_overwrite_section() {
  local sec="$1"
  echo "$sec" | grep -qiE 'overwrite' &&
  echo "$sec" | grep -qiE 'truncate|delete' &&
  echo "$sec" | grep -qiE 'explicitly named' &&
  echo "$sec" | grep -qiE 'scaffold'
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

@test "sidekick body: mechanical-only allowlist section asserts its own bullets (scoped)" {
  sec="$(section "$SIDEKICK_SRC" "Mechanical-only allowlist")"
  [ -n "$sec" ]
  assert_allowlist_section "$sec"
}

@test "sidekick body: allowlist config bullet carves out CI/CD, workflow, and secret files (F3)" {
  sec="$(section "$SIDEKICK_SRC" "Mechanical-only allowlist")"
  [ -n "$sec" ]
  echo "$sec" | grep -qiE '\bconfig\b'
  echo "$sec" | grep -qiE 'exclud'
  echo "$sec" | grep -qiE 'CI/CD|workflow'
  echo "$sec" | grep -qiE 'secret|credential'
}

@test "sidekick body: refuse-if-judgment clause is pinned by its own section content (scoped)" {
  sec="$(section "$SIDEKICK_SRC" "Refuse if judgment is required")"
  [ -n "$sec" ]
  assert_refuse_section "$sec"
}

@test "sidekick body: forbidden-actions section requires git/CI/migrations/deploys/test-assertions/design WITHIN it (scoped)" {
  sec="$(section "$SIDEKICK_SRC" "Forbidden actions")"
  [ -n "$sec" ]
  assert_forbidden_section "$sec"
}

@test "sidekick body: write-path scope refuses .git internals, CI/CD/workflow files, and secret files (F2)" {
  sec="$(section "$SIDEKICK_SRC" "Write-path scope")"
  [ -n "$sec" ]
  assert_write_path_section "$sec"
}

@test "sidekick body: no-destructive-overwrite guard on existing file contents (F4)" {
  sec="$(section "$SIDEKICK_SRC" "No destructive overwrites")"
  [ -n "$sec" ]
  assert_no_overwrite_section "$sec"
}

@test "sidekick body: no-Bash reminder — the parent runs tools, sidekick applies edits (scoped)" {
  sec="$(section "$SIDEKICK_SRC" "No Bash — apply, don't run")"
  [ -n "$sec" ]
  echo "$sec" | grep -qiE '\bBash\b'
  echo "$sec" | grep -qiE 'parent (runs|run)'
}

@test "sidekick body: hand-back-for-review note (parent vets/accepts output) (scoped)" {
  sec="$(section "$SIDEKICK_SRC" "Hand back for review")"
  [ -n "$sec" ]
  echo "$sec" | grep -qiE 'review'
  echo "$sec" | grep -qiE 'vet|accept'
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
# A-2 fix-loop mutation guards (F1): reproduce qa's exact probe — gut a
# named section's bullets (heading kept) in a full copy of the REAL file,
# leaving every other section (including the No-Bash section's git/CI/
# migrations/deploys prose) intact. The old unscoped, body-wide grep -q
# checks stayed green against this mutant (the bug); the section()-scoped
# assert_*_section() helpers — the SAME helpers the real tests above use —
# must reject it.
# ---------------------------------------------------------------------------

@test "sidekick body: hardened forbidden-actions check rejects a gutted Forbidden section (heading kept, bullets removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  gut_section "$SIDEKICK_SRC" "Forbidden actions" > "$mutant"
  sec="$(section "$mutant" "Forbidden actions")"
  run assert_forbidden_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "sidekick body: hardened refuse-if-judgment check rejects an emptied Refuse section (heading kept, prose removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  gut_section "$SIDEKICK_SRC" "Refuse if judgment is required" > "$mutant"
  sec="$(section "$mutant" "Refuse if judgment is required")"
  run assert_refuse_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "sidekick body: hardened allowlist check rejects an emptied Allowlist section (heading kept, bullets removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  gut_section "$SIDEKICK_SRC" "Mechanical-only allowlist" > "$mutant"
  sec="$(section "$mutant" "Mechanical-only allowlist")"
  run assert_allowlist_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "sidekick body: hardened write-path-scope check rejects a gutted Write-path scope section (heading kept, prose removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  gut_section "$SIDEKICK_SRC" "Write-path scope" > "$mutant"
  sec="$(section "$mutant" "Write-path scope")"
  run assert_write_path_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
}

@test "sidekick body: hardened no-destructive-overwrite check rejects a gutted No destructive overwrites section (heading kept, prose removed)" {
  mutant_dir="$(mktemp -d /tmp/aw-sidekick-mutant-XXXXXX)"
  mutant="$mutant_dir/sidekick.md"
  gut_section "$SIDEKICK_SRC" "No destructive overwrites" > "$mutant"
  sec="$(section "$mutant" "No destructive overwrites")"
  run assert_no_overwrite_section "$sec"
  rm -rf "$mutant_dir"
  [ "$status" -ne 0 ]
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
