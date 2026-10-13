#!/usr/bin/env bash
# Static checks for the plugin folder. Runs anywhere with bash, jq and python3,
# including CI, where Omarchy itself isn't installed.
#
# The manifest rules mirror Omarchy's `omarchy plugin validate`
# (bin/omarchy-plugin-validate). The rest are this repo's own consistency checks.
# Usage: bash tests/check-plugin.sh [plugin-folder]   → prints problems, exits 1 if any

set -uo pipefail
DIR=${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
M="$DIR/manifest.json"
problems=0
bad() { printf '  - %s\n' "$*"; problems=$((problems + 1)); }

# ---- manifest (mirrors omarchy plugin validate)
if ! jq -e . "$M" >/dev/null 2>&1; then
  bad "manifest.json is missing or not valid JSON"
else
  jq -e '.schemaVersion == 1' "$M" >/dev/null || bad "schemaVersion must be the number 1"
  for field in id name version kinds entryPoints; do
    jq -e --arg f "$field" 'has($f)' "$M" >/dev/null || bad "manifest missing '$field'"
  done
  id=$(jq -r '.id // ""' "$M")
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || bad "invalid plugin id '$id'"
  [[ $id != omarchy.* ]] || bad "id uses the reserved omarchy.* namespace"
  jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$M" >/dev/null || bad "'kinds' must be a non-empty array"
  jq -e '(.entryPoints | type) == "object"' "$M" >/dev/null || bad "'entryPoints' must be an object"
  jq -e '.barWidget.defaultSection? as $s
         | if $s == null then true else (["left", "center", "right"] | index($s)) != null end' \
    "$M" >/dev/null || bad "barWidget.defaultSection must be left, center, or right"
  while IFS= read -r ep; do
    [[ -n $ep && $ep != /* && $ep != *..* ]] || { bad "unsafe entry point '$ep'"; continue; }
    [[ -f $DIR/$ep ]] || bad "entry point not found: $ep"
  done < <(jq -r '.entryPoints[]' "$M")
  for pair in bar:bar bar-widget:barWidget menu:menu overlay:overlay panel:panel service:service; do
    kind=${pair%%:*}; key=${pair##*:}
    if jq -e --arg k "$kind" '.kinds | index($k) != null' "$M" >/dev/null; then
      jq -e --arg e "$key" '.entryPoints | has($e)' "$M" >/dev/null || bad "kind '$kind' needs entryPoints.$key"
    fi
  done
fi
link=$(find "$DIR" -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || bad "symlink inside the plugin folder: ${link#"$DIR"/}"

# ---- versions agree
mv=$(jq -r '.version // ""' "$M" 2>/dev/null)
pv=$(sed -nE 's/^PROBE_VERSION="([^"]*)"/\1/p' "$DIR/bin/user-menu-probe")
[[ $mv == "$pv" ]] || bad "manifest version ($mv) != probe version ($pv)"

# ---- icons: Marks.js, assets/ and the probe's providers agree
marks=$(sed -nE 's/^var MARKS = \[(.*)\]/\1/p' "$DIR/Marks.js" | tr -d '" ' | tr ',' '\n' | sort)
files=$(find "$DIR/assets" -maxdepth 1 -name '*.svg' -printf '%f\n' | sed 's/\.svg$//' | sort)
[[ $marks == "$files" ]] || bad "Marks.js and assets/*.svg disagree (run: python3 -I scripts/update-icons)"
glyphs=$(sed -n '/^var PROVIDER_GLYPHS = {/,/^}/p' "$DIR/Format.js" | sed -nE 's/^[[:space:]]+([a-z0-9]+):.*/\1/p')
providers=$(sed -n '/^PROVIDERS=(/,/)/p' "$DIR/bin/user-menu-probe" | tr -d '()' | sed 's/PROVIDERS=//' | tr -s ' \n' '\n' | sed '/^$/d')
for p in $providers; do
  grep -qx -- "$p" <<<"$marks"$'\n'"$glyphs" || bad "provider '$p' has no mark or glyph (it would show a puzzle piece)"
done

# ---- bundled SVGs carry geometry only
for f in "$DIR"/assets/*.svg; do
  if grep -qiE '<(script|style|image|use|foreignObject|a[[:space:]>])|href=|[[:space:]]on[a-z]+=|url\(' "$f"; then
    bad "${f#"$DIR"/} contains scripts, links, styles or references"
  fi
done

# ---- scripts parse
bash -n "$DIR/bin/user-menu-probe" || bad "bin/user-menu-probe has a bash syntax error"
python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$DIR/scripts/update-icons" \
  || bad "scripts/update-icons has a Python syntax error"

if (( problems )); then exit 1; fi
echo "  plugin checks passed"
