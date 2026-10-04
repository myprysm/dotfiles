#!/bin/bash
# Tests the mod check (#98): which installed plugins it reports as shipping a
# mod, and that it never passes silently when it cannot run. Runs the script
# against fixture plugin trees under a scratch HOME; reads nothing real.
#
# PATH holds only jq, so the `claude plugin validate` path never runs: no real
# mod exists to verify a fixture for it against (#98, item 9).
#
#   ./tests/test-mod-check.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/home/dot_claude/hooks/executable_mod-check.sh"
BASH_BIN="$(command -v bash)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/nojq"
ln -s "$(command -v jq)" "$SB/bin/jq"

pass=0; fail=0
out=""; code=0
run() { # run <bin dir>
  out=$(HOME="$SB/home" PATH="$1" "$BASH_BIN" "$SCRIPT" 2>&1); code=$?
}
is() { # is <label> <got> <expected>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$3" "$2"; fi
}
msg() { printf '%s' "$out" | jq -r '.systemMessage' 2>&1; }

reset_home() {
  rm -rf "$SB/home"
  mkdir -p "$SB/home/.claude/plugins/cache"
}
plugin() { # plugin <name> <version> <hooks.json or empty>
  local dir="$SB/home/.claude/plugins/cache/mkt/$1/$2"
  mkdir -p "$dir"
  [ -n "$3" ] && { mkdir -p "$dir/hooks"; printf '%s' "$3" > "$dir/hooks/hooks.json"; }
  printf '%s' "$dir"
}
installed() { # installed <json>
  printf '%s' "$1" > "$SB/home/.claude/plugins/installed_plugins.json"
}

CLASSIC='{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"x"}]}]}}'
MOD='{"modules":["./mod.js"],"hooks":{}}'

echo "== plugins with no mod"
reset_home
a=$(plugin plain 1.0.0 "")
b=$(plugin classic 2.0.0 "$CLASSIC")
installed "$(jq -n --arg a "$a" --arg b "$b" '{version:2,plugins:{
  "plain@mkt":[{scope:"user",installPath:$a,version:"1.0.0"}],
  "classic@mkt":[{scope:"user",installPath:$b,version:"2.0.0"}]}}')"
run "$SB/bin"
is "clean result shows nothing" "$out" ""
is "clean result exits 0" "$code" "0"

echo "== a plugin with a modules key"
reset_home
a=$(plugin plain 1.0.0 "$CLASSIC")
b=$(plugin modded 3.1.0 "$MOD")
installed "$(jq -n --arg a "$a" --arg b "$b" '{version:2,plugins:{
  "plain@mkt":[{scope:"user",installPath:$a,version:"1.0.0"}],
  "modded@mkt":[{scope:"user",installPath:$b,version:"3.1.0"}]}}')"
run "$SB/bin"
is "one line for the mod" "$(msg)" "modded@mkt 3.1.0: ships a mod — run mod admission (#91)"
is "finding exits non-zero" "$([ "$code" -ne 0 ] && echo yes)" "yes"

echo "== a mod under ~/.claude/mods/plugins"
reset_home
installed '{"version":2,"plugins":{}}'
mkdir -p "$SB/home/.claude/mods/plugins/bar/hooks" "$SB/home/.claude/mods/plugins/bar/.claude-plugin"
printf '%s' "$MOD" > "$SB/home/.claude/mods/plugins/bar/hooks/hooks.json"
printf '%s' '{"name":"bar","version":"0.1.0"}' > "$SB/home/.claude/mods/plugins/bar/.claude-plugin/plugin.json"
run "$SB/bin"
is "repo mod reported" "$(msg)" "bar@dotfiles 0.1.0: ships a mod — run mod admission (#91)"
is "finding exits non-zero" "$([ "$code" -ne 0 ] && echo yes)" "yes"

echo "== installed_plugins.json the script cannot read"
reset_home
installed 'not json'
run "$SB/bin"
is "unreadable file reported" "$(msg)" "mod check could not run: $SB/home/.claude/plugins/installed_plugins.json is not valid JSON"
is "exits non-zero" "$([ "$code" -ne 0 ] && echo yes)" "yes"

reset_home
installed '{"version":3,"plugins":{}}'
run "$SB/bin"
is "unknown format reported" "$(msg)" "mod check could not run: $SB/home/.claude/plugins/installed_plugins.json has unknown format (version 3)"

reset_home
run "$SB/bin"
is "missing file reported" "$(msg)" "mod check could not run: $SB/home/.claude/plugins/installed_plugins.json not found"
is "exits non-zero" "$([ "$code" -ne 0 ] && echo yes)" "yes"

echo "== jq missing"
reset_home
installed '{"version":2,"plugins":{}}'
run "$SB/nojq"
is "jq missing reported" "$(msg)" "mod check could not run: jq not found"
is "exits non-zero" "$([ "$code" -ne 0 ] && echo yes)" "yes"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
