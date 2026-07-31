#!/bin/bash
# Restore vaulted secrets onto THIS machine (issues #11 §5, #15 §5, #19).
# Explicit invocation only; never wired into chezmoi apply — a throwaway VM
# running the bootstrap one-liner must not implicitly receive the key estate.
#
# Placement is driven entirely by vault metadata, so this repo holds no item
# names and no destination paths:
#   dotfiles/ssh      attachments land in ~/.ssh under their own filenames
#   dotfiles/restore  items carry `path` ($HOME-relative) and `mode` fields
#   dotfiles          gpg-keys is imported into the keyring, not placed
set -euo pipefail
. "$(dirname "$0")/secrets-common.sh"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

require bw jq gpg
bw_open
bw sync >/dev/null

restored=0
skipped=0

# Guard, called BEFORE the vault read. Two reasons it is not folded into place():
# a secret we are going to skip should never be fetched at all, and a reader left
# undrained dies of EPIPE mid-stream.
wanted() {
  local dest="$1"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
    note "  skip (exists)  ${dest/#$HOME/\~}"
    skipped=$((skipped + 1))
    return 1
  fi
  return 0
}

# Reads stdin, writes it to $1 with mode $2.
# Call with input redirection, never a pipe: a pipe would subshell the counters.
place() {
  local dest="$1" mode="$2"
  mkdir -p "$(dirname "$dest")"
  (umask 077; cat > "$dest")
  chmod "$mode" "$dest"
  if [ ! -s "$dest" ]; then
    warn "wrote an EMPTY file to ${dest/#$HOME/\~} — the vault read likely failed"
  fi
  note "  restored       ${dest/#$HOME/\~} ($mode)"
  restored=$((restored + 1))
}

note "SSH keys -> ~/.ssh"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
# Two of the seeded keypairs have no public half (#8), so iterate attachments
# rather than assuming a .pub exists alongside every private key.
while read -r item att name; do
  case "$name" in
    *.pub) mode=644 ;;
    *) mode=600 ;;
  esac
  wanted "$HOME/.ssh/$name" || continue
  place "$HOME/.ssh/$name" "$mode" < <(bw get attachment "$att" --itemid "$item" --raw)
done < <(bw_items "$BW_SSH" | jq -r '.[] | .id as $i | (.attachments // [])[] | "\($i) \(.id) \(.fileName)"')

note "Self-describing restore items"
while read -r item; do
  id="$(jq -r .id <<<"$item")"
  path="$(jq -r '[(.fields // [])[] | select(.name == "path") | .value][0] // ""' <<<"$item")"
  mode="$(jq -r '[(.fields // [])[] | select(.name == "mode") | .value][0] // "600"' <<<"$item")"
  if [ -z "$path" ]; then
    warn "a restore item carries no path field — skipped"
    continue
  fi
  wanted "$HOME/$path" || continue
  att="$(jq -r '[(.attachments // [])[].id][0] // ""' <<<"$item")"
  if [ -n "$att" ]; then
    place "$HOME/$path" "$mode" < <(bw get attachment "$att" --itemid "$id" --raw)
  else
    place "$HOME/$path" "$mode" <<<"$(jq -r '.notes // ""' <<<"$item")"
  fi
done < <(bw_items "$BW_RESTORE" | jq -c '.[]')

note "GPG"
# The one special case: import into the keyring rather than placing files (#11 §2).
gpg_item="$(bw_items "$BW_ROOT" | jq -r '.[] | select(.name == "gpg-keys") | .id')"
if [ -z "$gpg_item" ]; then
  warn "no gpg-keys item in the vault — skipped"
else
  bw get attachment secret-keys.asc --itemid "$gpg_item" --raw | gpg --batch --import
  bw get attachment ownertrust.txt --itemid "$gpg_item" --raw | gpg --batch --import-ownertrust
  note "  imported       secret keys + ownertrust"
fi

report_work_domain || true

note ""
note "Done. $restored restored, $skipped left alone."
if [ "$skipped" -gt 0 ]; then
  note "Re-run with --force to overwrite what already exists."
fi
note "Ephemeral credentials are re-authed separately: gh, docker, npm, cloud CLIs (#11 §3)."
