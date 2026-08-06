#!/bin/bash
# Tests scripts/secrets-backup.sh: what it refuses to do, and the permissions it
# leaves behind. bw and gpg are stubbed, HOME is a scratch directory, and no real
# vault is contacted — the export is a fixture zip, not an export.
#
#   ./tests/test-secrets-backup.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin"

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-46s %s\n' "$1" "$3"
          else fail=$((fail+1)); printf '  FAIL %-46s want [%s] got [%s]\n' "$1" "$2" "$3"; fi }
says() { if printf '%s' "$3" | grep -q -- "$2"; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
         else fail=$((fail+1)); printf '  FAIL %s (no %s)\n         in: %s\n' "$1" "$2" "$3"; fi }
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$SB/bin/$1"; chmod +x "$SB/bin/$1"; }

# A vault that unlocks from a piped password, syncs, and exports a fixture. The
# `export` arm honours --output so the script's own path handling is exercised.
bw_ok='case "$1" in
  status) echo "{\"status\":\"unlocked\"}" ;;
  unlock) echo "session-token" ;;
  sync) : ;;
  export) shift; while [ $# -gt 0 ]; do case $1 in --output) shift; printf "PK\003\004fixture" > "$1" ;; esac; shift; done ;;
  *) exit 1 ;;
esac'
stub jq 'exec /usr/bin/jq "$@"'
stub gpg 'out=""; while [ $# -gt 0 ]; do case $1 in --output) shift; out=$1 ;; esac; shift; done; [ -n "$out" ] && printf "encrypted" > "$out"'

run() { # run <home>  -> rc, out
  HOME="$1" PATH="$SB/bin:/usr/bin:/bin" BW_SESSION=preset \
    bash "$REPO_ROOT/scripts/secrets-backup.sh" > "$SB/out" 2>&1
  rc=$?; out=$(cat "$SB/out")
}
archive_of() { ls "$1/.local/share/dotfiles-secrets"/*.gpg 2>/dev/null | head -1; }
mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

echo "== an export that produces nothing must not be encrypted and shipped"
# The failure that matters here is a SILENT one: an empty export encrypted into a
# plausible-looking archive is worse than no archive, because the staleness check
# in the audit would then report the machine as backed up.
stub bw 'case "$1" in
  status) echo "{\"status\":\"unlocked\"}" ;; unlock) echo t ;; sync) : ;;
  export) shift; while [ $# -gt 0 ]; do case $1 in --output) shift; : > "$1" ;; esac; shift; done ;;
esac'
H="$SB/h1"; mkdir -p "$H"; run "$H"
check "exits non-zero" "1" "$rc"
says "and says the export produced nothing" 'produced nothing' "$out"
check "no archive left behind" "" "$(archive_of "$H")"

echo
echo "== a good run writes one archive, 600, in a 700 machine-local directory"
stub bw "$bw_ok"
H="$SB/h2"; mkdir -p "$H"; run "$H"
check "exits zero" "0" "$rc"
a=$(archive_of "$H")
check "one archive written" "1" "$(ls "$H/.local/share/dotfiles-secrets" | wc -l | tr -d ' ')"
check "archive mode" "600" "$(mode_of "$a")"
check "directory mode" "700" "$(mode_of "$H/.local/share/dotfiles-secrets")"
outside_repo() { case "$1" in "$REPO_ROOT"/*) printf no ;; *) printf yes ;; esac; }
check "archive is outside the repo" "yes" "$(outside_repo "$a")"
says "tells the operator how to decrypt" 'gpg --decrypt' "$out"
says "warns that the passphrase must not live in the vault" 'does not depend on this vault' "$out"

echo
echo "== a second run does not overwrite the first"
sleep 1
run "$H"
check "two archives now" "2" "$(ls "$H/.local/share/dotfiles-secrets" | wc -l | tr -d ' ')"

echo
echo "== the work domain gap is stated out loud when the bundle is on"
# op has no export command, so this is a decision rather than an omission, and it
# is announced so a reader does not mistake it for one.
stub chezmoi 'echo "{\"bundles\":{\"work\":true}}"'
H="$SB/h3"; mkdir -p "$H"; run "$H"
says "the run names the work gap" 'not backed up, by design' "$out"
stub chezmoi 'echo "{\"bundles\":{\"work\":false}}"'
H="$SB/h4"; mkdir -p "$H"; run "$H"
if printf '%s' "$out" | grep -q 'not backed up'; then
  fail=$((fail+1)); echo "  FAIL the work notice appears with the bundle off"
else
  pass=$((pass+1)); echo "  ok   no work notice when the bundle is off"
fi

echo
echo "== a missing prerequisite is refused by name"
rm -f "$SB/bin/gpg"
H="$SB/h5"; mkdir -p "$H"; run "$H"
check "exits non-zero" "1" "$rc"
says "and names the missing binary" 'gpg is required' "$out"
stub gpg 'out=""; while [ $# -gt 0 ]; do case $1 in --output) shift; out=$1 ;; esac; shift; done; [ -n "$out" ] && printf "encrypted" > "$out"'

echo
echo "== KNOWN DEFECT, pinned so it is not lost: the archive uses a bare gpg"
# secrets-common.sh has git_gpg() precisely because a bare `gpg` on WSL resolves
# to the WINDOWS executable through a /usr/local/bin shim. This script calls a
# bare gpg anyway, so on WSL the archive is encrypted by Windows gnupg against a
# Linux temp path. The LINUX_GPG helper that guarded the restore against exactly
# this was deleted as dead by #50, so the knowledge lives only in that resolution.
# This probe asserts the CURRENT behaviour and will flip when the defect is fixed
# — at which point the expectation below is what needs changing, deliberately.
if grep -qE '^require .*[[:space:]]gpg([[:space:]]|$)' "$REPO_ROOT/scripts/secrets-backup.sh"; then
  pass=$((pass+1)); echo "  ok   still requires a bare gpg (defect present, tracked for the WSL batch)"
else
  fail=$((fail+1)); echo "  FAIL the bare-gpg requirement changed — update this probe deliberately"
fi
if grep -q 'git_gpg' "$REPO_ROOT/scripts/secrets-backup.sh"; then
  fail=$((fail+1)); echo "  FAIL git_gpg is now used — flip the expectation above, the defect is fixed"
else
  pass=$((pass+1)); echo "  ok   git_gpg not yet used here (defect present)"
fi

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
