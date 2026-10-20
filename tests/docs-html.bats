#!/usr/bin/env bats
# DOCS-1: docs, plans, specs, ADRs and reports are HTML in the dark Spotlight look.
# Markdown stays only where a tool reads it (README, SKILL.md, CLAUDE.md, PR bodies, …).

ROOT="$BATS_TEST_DIRNAME/.."

@test "skills and instructions ask for HTML docs, never a Markdown spec, report, ADR or FINDINGS" {
  run grep -rnE '(specs/<[^>]+>[^ `]*|ADR-<NNN>[^ `]*|ADR-\*|FINDINGS|ARCHITECTURE)\.md' "$ROOT/skills" "$ROOT/instructions"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  for s in plan incident adr ticket explore; do
    grep -qF '.html' "$ROOT/skills/$s/SKILL.md" || { echo "no .html doc in skills/$s"; false; }
  done
}

@test "the plan skill names the step headings the pipeline counts" {
  grep -qF '<h3>Step n</h3>' "$ROOT/skills/plan/SKILL.md" || false
}

# DOCS-1 Step 5: this repo's own docs are HTML
@test "the only tracked Markdown files are the ones a tool reads" {
  run bash -c 'cd "$1" && git ls-files "*.md" | grep -vxE "(README|CONTRIBUTING|AGENTS)\.md|docs/context/CURRENT_SPRINT\.md|instructions/[^/]+\.md|skills/[^/]+/SKILL\.md"' _ "$ROOT"
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "every relative link in the tracked docs resolves (the local docs/.design aside)" {
  cd "$ROOT"
  local f l bad=""
  for f in $(git ls-files '*.md' '*.html'); do
    for l in $(grep -oE '\]\([^)#: ]+[)#]|href="[^"#:]+["#]' "$f" | sed -E 's/^(\]\(|href=")//; s/.$//' | grep -v '\.design/'); do
      [ -e "$(dirname "$f")/$l" ] || bad="$bad $f→$l"
    done
  done
  [ -z "$bad" ] || { echo "$bad"; false; }
}

@test "the live docs name no moved doc by its old .md path" {
  run grep -nE '(specs/[^ `)]*|PAPER|ARCHITECTURE|ADR-[0-9]{3}[^ `)]*)\.md' \
    "$ROOT/README.md" "$ROOT/CONTRIBUTING.md" "$ROOT/docs/context/CURRENT_SPRINT.md" "$ROOT/docs/ARCHITECTURE.html"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "both instruction files carry the HTML rule: the doc template and docs/.design/styles.css" {
  for f in CLAUDE.md copilot-instructions.md; do
    grep -qF 'docs/context/specs/templates/doc.html' "$ROOT/instructions/$f" || { echo "no template in $f"; false; }
    grep -qF 'docs/.design/styles.css' "$ROOT/instructions/$f" || { echo "no stylesheet in $f"; false; }
  done
}
