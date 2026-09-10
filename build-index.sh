#!/usr/bin/env bash
# build-index.sh -- turn `omarchy menu keybindings --print` into index.json,
# a map of canonical modifier mask -> [{k: key, d: description}, ...].
#
#   { "": [...], "SUPER": [...], "SUPER+SHIFT": [...], "SUPER+CTRL+SHIFT": [...] }
#
# Canonical mask order is always SUPER, CTRL, ALT, SHIFT regardless of how the
# binding is written in the Hyprland config. Runs in a few ms; safe to call on
# every HUD open.
#
# The output goes to the XDG cache dir, NOT the plugin dir -- the shell watches
# the plugin dir and would reload the plugin on every write.
set -euo pipefail

export PATH="$PATH:/usr/share/omarchy/bin"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-whichkey"
out="$cache/index.json"
mkdir -p "$cache"

omarchy menu keybindings --print 2>/dev/null | awk '
function canon(mods,   i, n, arr, has, pref, res) {
  n = split(mods, arr, " ")
  for (i = 1; i <= n; i++) has[arr[i]] = 1
  split("SUPER CTRL ALT SHIFT", pref, " ")
  res = ""
  for (i = 1; i <= 4; i++) if (has[pref[i]]) res = res (res ? "+" : "") pref[i]
  return res
}
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
BEGIN { FS = " *\xe2\x86\x92 *" }   # split on the  ->  arrow (U+2192)
NF < 2 { next }
# A keyboard cheat sheet: drop pointer/scroll bindings.
$1 ~ /MOUSE|[Mm]ouse|AXIS|mouse_(up|down|left|right)/ { next }
{
  lhs = $1; desc = $2
  gsub(/^[ \t]+|[ \t]+$/, "", lhs)
  gsub(/^[ \t]+|[ \t]+$/, "", desc)
  if (lhs ~ / \+ /) {
    key  = lhs; sub(/^.* \+ /, "", key)      # everything after the last " + "
    mods = lhs; sub(/ \+ [^+]*$/, "", mods)  # everything before it
  } else {
    key = lhs; mods = ""
  }
  mask = canon(mods)
  item = "{\"k\":\"" jesc(key) "\",\"d\":\"" jesc(desc) "\"}"
  data[mask] = data[mask] (count[mask]++ ? "," : "") item
}
END {
  printf "{"
  first = 1
  for (m in data) {
    printf "%s\"%s\":[%s]", (first ? "" : ","), m, data[m]
    first = 0
  }
  print "}"
}
' > "$out.tmp"

python3 "$dir/collapse.py" < "$out.tmp" > "$out.tmp2" && mv "$out.tmp2" "$out"
rm -f "$out.tmp"
