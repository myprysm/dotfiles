#!/bin/bash
# Tests the shared helpers in scripts/secrets-common.sh, which the three
# secrets-* scripts all depend on and which had no coverage at all. Both vault
# CLIs are stubbed and every path is a scratch directory: this suite reads no
# vault, needs no unlock, and never touches a real secret.
#
#   ./tests/test-secrets-common.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin"

pass=0; fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-52s %s\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %-52s want [%s] got [%s]\n' "$1" "$2" "$3"; fi
}
says() { # says <label> <pattern> <text>
  if printf '%s' "$3" | grep -q -- "$2"; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s (no match for %s)\n         in: %s\n' "$1" "$2" "$3"; fi
}
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$SB/bin/$1"; chmod +x "$SB/bin/$1"; }

# Sourced in a subshell each time, with a pinned PATH so this machine's real bw,
# op and chezmoi can never leak into a fixture. That leak is not hypothetical: it
# silently voided a probe in the rclone suite.
helper() { # helper <shell code using the helpers>
  HOME="$SB/home" PATH="$SB/bin:/usr/bin:/bin" bash -c "
    set -u
    . '$REPO_ROOT/scripts/secrets-common.sh' 2>/dev/null
    $1
  " 2>&1
}

echo "== the work bundle gate reads chezmoi data, and copes without chezmoi"
stub chezmoi 'echo "{\"bundles\":{\"work\":true}}"'
check "bundle on"  "on"  "$(helper 'work_bundle_enabled && echo on || echo off')"
stub chezmoi 'echo "{\"bundles\":{\"work\":false}}"'
check "bundle off" "off" "$(helper 'work_bundle_enabled && echo on || echo off')"
stub chezmoi 'echo "{}"'
check "key absent is off, not an error" "off" "$(helper 'work_bundle_enabled && echo on || echo off')"
rm -f "$SB/bin/chezmoi"
check "chezmoi absent is off, not a crash" "off" "$(helper 'work_bundle_enabled && echo on || echo off')"

echo
echo "== op_ready distinguishes a timeout from a refusal, and never trusts op whoami"
stub chezmoi 'echo "{\"bundles\":{\"work\":true}}"'
stub timeout 'shift; exec "$@"'
# 124 is what `timeout` returns when op blocks on an unapproved GUI prompt. It
# must not read as "the vault is unreachable": the operator's fix is different.
stub op 'exit 124'
out=$(helper 'op_ready && echo ready || echo notready')
check "a timeout is not ready" "notready" "$(printf '%s' "$out" | tail -1)"
says "the timeout message tells the operator to approve the prompt" 'unapproved' "$out"
stub op 'exit 1'
out=$(helper 'op_ready && echo ready || echo notready')
check "a refusal is not ready" "notready" "$(printf '%s' "$out" | tail -1)"
says "the refusal message names the exit code" 'op exit 1' "$out"
stub op 'exit 0'
check "a successful read is ready" "ready" "$(helper 'op_ready && echo ready || echo notready' | tail -1)"

echo
echo "== work_domain_ready gates on the bundle, then the binary, then a real read"
stub chezmoi 'echo "{\"bundles\":{\"work\":false}}"'
out=$(helper 'work_domain_ready && echo ready || echo notready')
check "bundle off short-circuits" "notready" "$(printf '%s' "$out" | tail -1)"
says "and says so without warning about op" 'bundle off' "$out"
stub chezmoi 'echo "{\"bundles\":{\"work\":true}}"'
rm -f "$SB/bin/op"
out=$(helper 'work_domain_ready && echo ready || echo notready')
check "bundle on but no op is not ready" "notready" "$(printf '%s' "$out" | tail -1)"
says "and names op as the missing piece" 'op is not installed' "$out"

echo
echo "== op tag selection is sub-nested, so the filter must be exact"
# `op item list --tags dotfiles` also returns dotfiles/ssh and dotfiles/restore.
# The root tag is where the GPG special case lives, so a loose filter would sweep
# every SSH key into it.
stub op 'cat <<JSON
[ {"id":"a","tags":["dotfiles"]},
  {"id":"b","tags":["dotfiles/ssh"]},
  {"id":"c","tags":["dotfiles/restore"]},
  {"id":"d","tags":["dotfiles","dotfiles/ssh"]} ]
JSON'
check "exact root tag" "a d" "$(helper 'op_items_tagged dotfiles | jq -r "[.[].id]|join(\" \")"')"
check "exact ssh tag"  "b d" "$(helper 'op_items_tagged dotfiles/ssh | jq -r "[.[].id]|join(\" \")"')"
check "exact restore tag" "c" "$(helper 'op_items_tagged dotfiles/restore | jq -r "[.[].id]|join(\" \")"')"

echo
echo "== op_field reads a labelled field, and an absent one is empty not null"
stub op 'cat <<JSON
{"fields":[{"label":"path","value":".ssh/id_ed25519"},{"label":"mode","value":"600"}]}
JSON'
check "a present field"  "600" "$(helper 'op_item_json x | op_field mode')"
check "an absent field is empty" "" "$(helper 'op_item_json x | op_field nosuch')"

echo
echo "== a locked vault is reported as locked, not as an unseeded machine"
# These two failures have the same symptom - nothing listed - and completely
# different fixes, so the message must not blame the vault's contents.
stub bw 'case "$1" in status) echo "{\"status\":\"locked\"}" ;; *) echo "[]" ;; esac'
out=$(helper 'bw_items dotfiles || true')
says "locked is named as locked" 'locked' "$out"
stub bw 'case "$1" in status) echo "{\"status\":\"unlocked\"}" ;; list) echo "[]" ;; esac'
out=$(helper 'bw_items nosuchfolder || true')
says "a missing folder asks whether the machine was seeded" 'seeded' "$out"

echo
echo "== git_gpg resolves the binary git signs through, never a bare gpg"
# A bare `gpg` on WSL is the WINDOWS executable, reached through a /usr/local/bin
# shim, so asking git is the only portable answer. This is the trap the archive
# path still falls into - see the note in test-secrets-backup.sh.
stub git 'case "$*" in *"gpg.program"*) echo /opt/homebrew/bin/gpg ;; esac'
check "git's configured program wins" "/opt/homebrew/bin/gpg" "$(helper 'git_gpg')"
stub git 'exit 1'
check "no configuration falls back to gpg" "gpg" "$(helper 'git_gpg')"

echo
echo "== the backup directory and staleness window are machine-local constants"
check "archive directory is under the home directory" "yes" \
  "$(helper 'case "$BACKUP_DIR" in "$HOME"/*) echo yes ;; *) echo no ;; esac')"
check "archive directory is outside the repo" "yes" \
  "$(helper 'case "$BACKUP_DIR" in *dotfiles/*) echo no ;; *) echo yes ;; esac')"
check "staleness window is 30 days" "30" "$(helper 'printf %s "$BACKUP_MAX_AGE_DAYS"')"

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
