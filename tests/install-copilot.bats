#!/usr/bin/env bats

# The docs name what `install global` really puts in ~/.copilot (tested in
# tests/install-native.bats), and that both tools' hooks are user-global.

ROOT="$BATS_TEST_DIRNAME/.."

@test "docs: README lists what install global puts in ~/.copilot" {
  for p in '~/.copilot/hooks/anw.json' '~/.copilot/skills/' '~/.copilot/copilot-instructions.md' '~/.copilot/settings.json'; do
    grep -qF "$p" "$ROOT/README.md" || { echo "README.md does not mention $p"; false; }
  done
}

@test "docs: ARCHITECTURE says the hooks are user-global in both tools" {
  grep -qi 'user-global' "$ROOT/docs/ARCHITECTURE.md" || false
  grep -qF '~/.copilot/hooks/anw.json' "$ROOT/docs/ARCHITECTURE.md" || false
  ! grep -qiE 'repo[- ]scope' "$ROOT/docs/ARCHITECTURE.md" || false
}
