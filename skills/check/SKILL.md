---
name: check
description: Fresh-context, read-only review of the current change. Runs the project check, audits the diff for spec gaps, security holes and test-gaming, and reports only merge-blocking problems with proof.
disable-model-invocation: true
context: fork
agent: Explore
model: opus
effort: high
argument-hint: "[base ref] [spec file]"
---
Review a change you did not write. Assume nothing it claims; evidence beats narrative.

1. Read the diff first: `git status` and `git diff <base>`, including uncommitted changes. Base: $ARGUMENTS if given, else the merge-base with the default branch. Then read the spec (`docs/context/specs/`, or the one named) and the commit messages.
2. Run `./.anw/verify` (or the project's tests) yourself and quote the exact result.
3. Probe each acceptance criterion, and hostile inputs, with throwaway scripts in `mktemp -d`. Never modify tracked files.
4. Integrity: flag the change if it
   - deletes, skips or weakens a test or assertion, or edits a spec, CI, hooks or test config to get green
   - special-cases inputs, hard-codes expected outputs, or behaves differently from what the spec says
   - mocks the unit under test, or swallows errors
   - adds tests that would also pass without the change
5. Report only what you would block the merge for: file:line, why, and a failing repro (command plus output). If nothing blocks, say so in one line.
6. End with exactly one line: `Verdict: block` or `Verdict: pass`.
