#!/bin/bash
# Tests the rclone.conf assembly script (#53): which vault answers it accepts,
# and what it refuses to write. Renders the chezmoi source into a scratch file
# and stubs both managers; reads no real vault and touches no real config.
#
#   ./tests/test-rclone-conf.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin"

printf '[p1]\ntype = s3\nkey = 1\n\n[p2]\ntype = s3\nkey = 2\n' > "$SB/personal"
printf '[w1]\ntype = s3\nkey = 3\n' > "$SB/work"

# The personal manager's answer is what each case varies.
mk_bw() { printf '#!/bin/sh\n%s\n' "$1" > "$SB/bin/bw"; chmod +x "$SB/bin/bw"; }
printf '#!/bin/sh\n[ "$1" = "read" ] && cat %s && exit 0\nexit 1\n' "$SB/work" > "$SB/bin/op"
chmod +x "$SB/bin/op"

chezmoi execute-template --source "$REPO_ROOT/home" \
  < "$REPO_ROOT/home/.chezmoiscripts/run_once_40-rclone-conf.sh.tmpl" > "$SB/script.sh" || exit 1

pass=0; fail=0
rc=0; got=""
run() {
  HOME="$1" PATH="$SB/bin:$PATH" bash "$SB/script.sh" > "$SB/out" 2>&1; rc=$?
  f="$1/.config/rclone/rclone.conf"
  if [ -f "$f" ]; then got="$(grep -c '^\[' "$f") remotes"; else got="no config"; fi
}
check() { # check <label> <want-rc> <want-state>
  if [ "$2" = "$rc" ] && [ "$3" = "$got" ]; then
    pass=$((pass+1)); printf '  ok   %-42s rc=%s %s\n' "$1" "$rc" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-42s want rc=%s %s, got rc=%s %s\n' "$1" "$2" "$3" "$rc" "$got"
  fi
}
says() { # says <label> <pattern>
  if grep -q "$2" "$SB/out"; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s (no match for %s)\n' "$1" "$2"; fi
}

# bw prints nothing and exits 0 whenever its prompt library cannot use the
# terminal (#19 measured it; `chezmoi apply -v` reproduces it by capturing this
# script's stdout). Trusting the exit status wrote a work-only config and called
# it "restored" (#53). Both machine states are covered: the fresh-machine one is
# where the loss was silent.
echo "== a personal fragment with no remote in it is fatal"
mk_bw 'exit 0'
H="$SB/a"; mkdir -p "$H"; run "$H"; check "fresh machine writes nothing" 1 "no config"
H="$SB/b"; mkdir -p "$H/.config/rclone"; cat "$SB/personal" "$SB/work" > "$H/.config/rclone/rclone.conf"
run "$H"; check "existing config left untouched" 1 "3 remotes"
if [ -f "$H/.config/rclone/rclone.conf.from-vault" ]; then
  fail=$((fail+1)); echo "  FAIL a sidecar was written from a failed read"
else
  pass=$((pass+1)); echo "  ok   no sidecar written from a failed read"
fi
says "the message names the cause, not the symptom" 'no remote in it'

echo
echo "== other unusable answers are fatal too"
mk_bw 'exit 1'
H="$SB/c"; mkdir -p "$H"; run "$H"; check "a non-zero exit" 1 "no config"
mk_bw 'printf "You are not logged in.\n"; exit 0'
H="$SB/d"; mkdir -p "$H"; run "$H"; check "text with no section header" 1 "no config"

echo
echo "== the good path"
mk_bw "cat \"$SB/personal\"; exit 0"
H="$SB/e"; mkdir -p "$H"; run "$H"; check "fresh machine gets both fragments" 0 "3 remotes"
if [ "$(stat -f %Lp "$H/.config/rclone/rclone.conf" 2>/dev/null || stat -c %a "$H/.config/rclone/rclone.conf")" = "600" ]; then
  pass=$((pass+1)); echo "  ok   written at mode 600"
else
  fail=$((fail+1)); echo "  FAIL not written at mode 600"
fi
# The fragments carry no trailing newline of their own, so the boundary between
# them is what the guard supplies. Without it the first work section is glued to
# the last personal line and one remote disappears (#53).
if [ "$(grep -c '^\[' "$H/.config/rclone/rclone.conf")" = "3" ]; then
  pass=$((pass+1)); echo "  ok   no section glued to the fragment above it"
else
  fail=$((fail+1)); echo "  FAIL a section was glued to the fragment above it"
fi

H="$SB/f"; mkdir -p "$H/.config/rclone"
{ cat "$SB/personal"; cat "$SB/work"; } > "$H/.config/rclone/rclone.conf"
run "$H"; check "an identical config is a match" 0 "3 remotes"
says "reports the match instead of a divergence" 'already matches'

# Section counts alone printed the same number on both sides when the difference
# was line endings or order, which read as a contradiction (#53).
echo
echo "== a divergence says whether it is format or content"
H="$SB/g"; mkdir -p "$H/.config/rclone"
{ cat "$SB/work"; cat "$SB/personal"; } | sed 's/$/\r/' > "$H/.config/rclone/rclone.conf"
run "$H"; says "same lines, other order and CRLF: format" 'FORMAT only'
H="$SB/h"; mkdir -p "$H/.config/rclone"; cat "$SB/personal" > "$H/.config/rclone/rclone.conf"
run "$H"; says "a missing remote: content" 'CONTENT differs'

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
