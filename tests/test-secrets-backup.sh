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
# jq is linked, not found on PATH: on Linux it may live only in brew's bin, and
# that directory also holds a real gpg and bw (#80).
ln -s "$(command -v jq)" "$SB/bin/jq"
gpg_ok='out=""; while [ $# -gt 0 ]; do case $1 in --output) shift; out=$1 ;; esac; shift; done; [ -n "$out" ] && printf "encrypted" > "$out"'
stub gpg "$gpg_ok"

run() { # run <home>  -> rc, out
  HOME="$1" PATH="$SB/bin:/usr/bin:/bin" BW_SESSION=preset BACKUP_GPG="$SB/bin/gpg" \
    bash "$REPO_ROOT/scripts/secrets-backup.sh" > "$SB/out" 2>&1
  rc=$?; out=$(cat "$SB/out")
}
archive_of() { ls "$1/.local/share/dotfiles-secrets"/*.gpg 2>/dev/null | head -1; }
# GNU first: GNU `stat -f` prints filesystem status to stdout before failing (#80).
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

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
echo "== a second run replaces the first, once the new archive decrypts"
sleep 1
run "$H"
check "exits zero" "0" "$rc"
check "still one archive" "1" "$(ls "$H/.local/share/dotfiles-secrets" | wc -l | tr -d ' ')"
check "and it is the new one" "no" "$([ "$(archive_of "$H")" = "$a" ] && echo yes || echo no)"
says "names the archive it shredded" 'Shredded the previous archive' "$out"

echo
echo "== an archive that does not decrypt is removed, and the previous one kept"
# The archive is symmetric: a mistyped passphrase writes a brick that looks like
# a success. Pruning before the check would destroy the last good archive.
a=$(archive_of "$H")
stub gpg 'case " $* " in *" --decrypt "*) exit 2 ;; esac; '"$gpg_ok"
sleep 1
run "$H"
check "exits non-zero" "1" "$rc"
says "says the archive does not decrypt" 'does not decrypt' "$out"
check "previous archive kept, alone" "$a" "$(ls "$H/.local/share/dotfiles-secrets"/*.gpg)"
stub gpg "$gpg_ok"

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
# bw, not gpg: Ubuntu ships /usr/bin/gpg, which the pinned PATH still reaches,
# and the real gpg then waits on a passphrase prompt (#80).
rm -f "$SB/bin/bw"
H="$SB/h5"; mkdir -p "$H"; run "$H"
check "exits non-zero" "1" "$rc"
says "and names the missing binary" 'bw is required' "$out"

echo
echo "== the archive never goes through a bare gpg"
# On WSL a bare `gpg` and git's gpg.program are both the Windows exe behind a
# /usr/local/bin shim, which cannot open Linux paths. The LINUX_GPG guard against
# this was deleted as dead by #50. A real /usr/bin/gpg cannot be stubbed, so this
# probe reads the script.
if grep -qE '^require .*[[:space:]]gpg([[:space:]]|$)' "$REPO_ROOT/scripts/secrets-backup.sh"; then
  fail=$((fail+1)); echo "  FAIL requires a bare gpg again"
else
  pass=$((pass+1)); echo "  ok   no bare gpg requirement"
fi
says "prefers /usr/bin/gpg" 'gpg_bin=/usr/bin/gpg' "$(cat "$REPO_ROOT/scripts/secrets-backup.sh")"

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
