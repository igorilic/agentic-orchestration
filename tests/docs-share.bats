#!/usr/bin/env bats
# docs-share: shareable copies of the HTML docs with the Spotlight stylesheet inlined.

ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  W="$BATS_TEST_TMPDIR"
  mkdir -p "$W/d/.design/tokens" "$W/d/sub"
  printf '@import url("tokens/a.css");\n@import url("b.css");\n' > "$W/d/.design/styles.css"
  echo 'body{color:red}' > "$W/d/.design/tokens/a.css"
  echo 'p{margin:0}' > "$W/d/.design/b.css"
  printf '<head>\n<link rel="stylesheet" href="../.design/styles.css">\n</head>\n' > "$W/d/sub/x.html"
}

@test "inlines the imported css and drops the link, keeping the relative path" {
  run env DESIGN_DIR="$W/d/.design" "$ROOT/lib/docs-share.sh" "$W/out" "$W/d/sub/x.html"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  f=$(find "$W/out" -name x.html)
  grep -qF 'body{color:red}' "$f" || { cat "$f"; false; }
  grep -qF 'p{margin:0}' "$f" || false
  ! grep -q '<link rel="stylesheet"' "$f" || { cat "$f"; false; }
}

@test "fails when the design system is not installed" {
  run env DESIGN_DIR="$W/nope" "$ROOT/lib/docs-share.sh" "$W/out" "$W/d/sub/x.html"
  [ "$status" -ne 0 ]
}
