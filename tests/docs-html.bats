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

@test "both instruction files carry the HTML rule: the doc template and docs/.design/styles.css" {
  for f in CLAUDE.md copilot-instructions.md; do
    grep -qF 'docs/context/specs/templates/doc.html' "$ROOT/instructions/$f" || { echo "no template in $f"; false; }
    grep -qF 'docs/.design/styles.css' "$ROOT/instructions/$f" || { echo "no stylesheet in $f"; false; }
  done
}
