#!/bin/bash
# Tests the redaction arm of the estate pre-commit hook (#41) and runs it over
# every tracked file. The staged-diff arm never sees a value already committed,
# so case 1 stages the whole working tree into a scratch repo as new files and
# runs the same rendered hook. Never touches the real HOME or any real repo.
#
#   ./tests/test-redaction.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/home"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

pass=0; fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1 (exit $3)"
  else fail=$((fail+1)); echo "  FAIL $1 (expected $2, got $3)"; fi
}
yes_no() { # yes_no <label> <0 if condition held>
  if [ "$2" = "0" ]; then pass=$((pass+1)); echo "  ok   $1"
  else fail=$((fail+1)); echo "  FAIL $1"; fi
}

mkdir -p "$SB/hooks"
chezmoi execute-template --source "$SRC" \
  < "$SRC/dot_config/git/hooks/executable_pre-commit.tmpl" > "$SB/hooks/pre-commit"
cp "$SRC/dot_config/git/hooks/executable__chain" "$SB/hooks/_chain"
chmod +x "$SB/hooks/pre-commit" "$SB/hooks/_chain"

newrepo() { # newrepo [nomarker]
  rm -rf "$SB/repo"; mkdir -p "$SB/repo"; cd "$SB/repo" || exit 1
  git init -q .
  git config user.email t@example.invalid; git config user.name Test
  git config commit.gpgsign false
  git config core.hooksPath "$SB/hooks"
  if [ "${1:-}" != nomarker ]; then
    echo marker > .redaction-check; git add .redaction-check
  fi
}

# Built at runtime so this file does not trip the scan it tests.
H=/home; U=/Users; AT=@; T='~'

echo "== 1. every tracked file passes the scan"
newrepo nomarker
git -C "$REPO_ROOT" ls-files -z | (cd "$REPO_ROOT" && tar --null -T - -cf -) | tar -xf -
[ -f .redaction-check ]; yes_no "the repo tracks the marker" $?
git add -A
out=$(git commit -q -m tree 2>&1); rc=$?
check "whole tree commits" 0 $rc
[ "$rc" = 0 ] || echo "$out" | grep -E '^[^ ]+:[0-9]+: ' | sed 's/^/       /'
git update-ref -d HEAD && printf 'path = %s/someone\n' "$H" >> README.md && git add -A
git commit -q -m planted >/dev/null 2>&1; check "the same tree with a planted value is refused" 1 $?

for probe in \
  "absolute linux home|path = $H/someone/.env" \
  "absolute mac home|path = $U/someone/.env" \
  "email at a real domain|email = someone${AT}gmail.com" \
  "ssh key file|IdentityFile $T/.ssh/id_work_rsa" ; do
  label=${probe%%|*}; line=${probe#*|}
  echo "== 2. refused: $label"
  newrepo; printf '%s\n' "$line" > f.txt; git add f.txt
  out=$(git commit -m leak 2>&1); check "commit refused" 1 $?
  echo "$out" | grep -q '^f.txt:1: '; yes_no "names file and line" $?
  echo "$out" | grep -qF "$line"; [ $? -ne 0 ]; yes_no "value not printed" $?
done

echo "== 3. the hit is found on the right line of a later file"
newrepo; printf 'a\n' > a.txt; printf 'one\ntwo\nhome = %s/someone\n' "$H" > b.txt
git add a.txt b.txt
out=$(git commit -m leak 2>&1); check "commit refused" 1 $?
echo "$out" | grep -q '^b.txt:3: '; yes_no "reports b.txt:3" $?

for probe in \
  "placeholder|$U/OPERATOR/.env and $H/OPERATOR" \
  "linuxbrew|$H/linuxbrew/.linuxbrew/bin" \
  "reserved domain|user${AT}example.com t${AT}example.invalid" \
  "repo-relative home dir|\$REPO_ROOT$H/dot_claude" \
  "ssh config|$T/.ssh/config" ; do
  label=${probe%%|*}; line=${probe#*|}
  echo "== 4. allowed: $label"
  newrepo; printf '%s\n' "$line" > f.txt; git add f.txt
  git commit -q -m ok >/dev/null 2>&1; check "commit succeeds" 0 $?
done

echo "== 5. a removed line is not scanned"
newrepo; printf 'path = %s/someone\n' "$H" > f.txt; git add f.txt
git commit -q --no-verify -m base >/dev/null 2>&1
: > f.txt; git add f.txt
git commit -q -m remove >/dev/null 2>&1; check "deletion commits" 0 $?

echo "== 6. a repo without the marker is untouched"
newrepo nomarker; printf 'path = %s/someone/.env\n' "$H" > f.txt; git add f.txt
git commit -q -m x >/dev/null 2>&1; check "commit succeeds" 0 $?

echo "== 7. a scan that cannot run fails closed"
newrepo; echo hi > f.txt; git add f.txt
mkdir -p "$SB/noawk"
for t in git mktemp rm dirname gitleaks; do
  p=$(command -v "$t") && ln -sf "$p" "$SB/noawk/$t"
done
PATH="$SB/noawk" git commit -q -m x >/dev/null 2>&1; check "missing awk blocks" 1 $?

echo "== 8. --no-verify remains the operator's escape hatch"
newrepo; printf 'path = %s/someone\n' "$H" > f.txt; git add f.txt
git commit -q --no-verify -m x >/dev/null 2>&1; check "bypass commits" 0 $?

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
