#!/bin/bash
# Tests the statusline renderer: field alignment against payloads that omit
# fields, and the bar arithmetic. Renders the chezmoi source into a scratch file
# and feeds it JSON on stdin; reads nothing real.
#
#   ./tests/test-statusline.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
SL="$SB/statusline.sh"
chezmoi execute-template --source "$REPO_ROOT/home" \
  < "$REPO_ROOT/home/dot_claude/executable_statusline.sh" > "$SL" || exit 1

# A fixed point an hour out, so the countdown is stable within a run.
SOON=$(( $(date +%s) + 3600 ))

pass=0; fail=0
out=""
render() { printf '%s' "$1" | bash "$SL" | perl -pe 's/\e\[[0-9;]*m//g'; }
has() { # has <label> <pattern>
  if printf '%s' "$out" | grep -q -- "$2"; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         in: %s\n' "$1" "$out"; fi
}
hasnt() { # hasnt <label> <pattern>
  if printf '%s' "$out" | grep -q -- "$2"; then fail=$((fail+1)); printf '  FAIL %s\n         in: %s\n' "$1" "$out"
  else pass=$((pass+1)); printf '  ok   %s\n' "$1"; fi
}

ctx='"context_window":{"used_percentage":10,"total_input_tokens":1000,"context_window_size":200000}'

echo "== every field present"
out=$(render "{\"model\":{\"display_name\":\"M\"},$ctx,\"rate_limits\":{\"five_hour\":{\"used_percentage\":47,\"resets_at\":$SOON},\"seven_day\":{\"used_percentage\":83,\"resets_at\":$SOON}}}")
has "both windows render" '5h .* │ 7d '
has "5h is 4 of 10 cells" '5h ████░░░░░░ 47%'
has "7d is 8 of 10 cells" '7d ████████░░ 83%'

# TAB is an IFS whitespace character, so a tab-separated read collapsed a run of
# tabs and shifted every later field left. One window's epoch then printed as
# the next window's percentage.
echo
echo "== a field the payload omits must not shift the ones after it"
out=$(render "{\"model\":{\"display_name\":\"M\"},$ctx,\"rate_limits\":{\"five_hour\":{\"used_percentage\":47},\"seven_day\":{\"used_percentage\":83,\"resets_at\":$SOON}}}")
has "the later window keeps its own percentage" '7d ████████░░ 83%'
has "the later window keeps its own timer" '7d .*↻'
hasnt "no epoch printed as a percentage" '[0-9]\{8,\}%'
hasnt "no timer invented for the window that has none" '5h ████░░░░░░ 47% ↻'

echo
echo "== a payload with no rate limits at all"
out=$(render "{\"model\":{\"display_name\":\"M\"},$ctx}")
has "the context section still renders" 'ctx 1k/200k (10%)'
hasnt "no 5h window" '5h '
hasnt "no 7d window" '7d '

echo
echo "== a malformed payload must not spew shell errors"
out=$(render 'not json at all')
hasnt "no bash error text" 'line [0-9]'
has "falls back to a question mark model" '?'

echo
echo "== the bar clamps above 100"
out=$(render "{\"model\":{\"display_name\":\"M\"},$ctx,\"rate_limits\":{\"five_hour\":{\"used_percentage\":140}}}")
has "ten cells, not fourteen" '5h ██████████ 140%'

# The hook is invoked as plain `bash`, so the interpreter is whatever PATH gives.
# Stock macOS /bin/bash is 3.2, and a bash-4 builtin (`mapfile`) once made the
# whole line degrade to `? | ctx 0/0 (0%)` with status 0 on any machine where
# brew's bash was not first. Same payload, both interpreters, same output.
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]; then
  echo
  echo "== identical output under stock /bin/bash $(/bin/bash -c 'echo $BASH_VERSION')"
  payload="{\"model\":{\"display_name\":\"M\"},$ctx,\"rate_limits\":{\"five_hour\":{\"used_percentage\":47},\"seven_day\":{\"used_percentage\":83,\"resets_at\":$SOON}}}"
  five=$(printf '%s' "$payload" | bash "$SL" | perl -pe 's/\e\[[0-9;]*m//g')
  three=$(printf '%s' "$payload" | /bin/bash "$SL" 2>&1 | perl -pe 's/\e\[[0-9;]*m//g')
  if [ "$five" = "$three" ]; then
    pass=$((pass+1)); printf '  ok   bash 3.2 output matches bash 5\n'
  else
    fail=$((fail+1)); printf '  FAIL bash 3.2 differs\n         5.x: %s\n         3.2: %s\n' "$five" "$three"
  fi
  case $three in
    *'command not found'*|*'ctx 0/0'*)
      fail=$((fail+1)); printf '  FAIL bash 3.2 degraded: %s\n' "$three" ;;
    *) pass=$((pass+1)); printf '  ok   no bash-4 builtin in the path\n' ;;
  esac
else
  echo
  echo "  -- skipped: no bash 3.x at /bin/bash on this machine"
fi

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
