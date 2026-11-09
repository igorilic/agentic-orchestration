#!/usr/bin/env bash
# Self-contained copies of the HTML docs for sharing: the Spotlight stylesheet
# (licensed, never committed) is inlined in place of the relative link.
# Usage: lib/docs-share.sh OUT_DIR [doc.html ...]   (default: every doc under docs/)
set -euo pipefail

out=${1:?usage: docs-share.sh OUT_DIR [doc.html ...]}; shift
design=${DESIGN_DIR:-docs/.design}
[ -f "$design/styles.css" ] || { echo "docs-share: no Spotlight design system at $design" >&2; exit 1; }

# styles.css is a list of @imports; flatten them in order
CSS=$(sed -n 's/^@import url("\(.*\)");$/\1/p' "$design/styles.css" | while read -r f; do cat "$design/$f"; done)
export CSS

if [ $# -eq 0 ]; then
  set --
  while IFS= read -r f; do set -- "$@" "$f"; done < <(find docs -name '*.html' -not -path '*/templates/*')
fi

for f in "$@"; do
  dest="$out/${f#docs/}"
  mkdir -p "$(dirname "$dest")"
  perl -0pe 's{<link rel="stylesheet" href="[^"]*styles\.css">}{<style>\n$ENV{CSS}\n</style>}' "$f" > "$dest"
done
echo "docs-share: $# file(s) -> $out"
