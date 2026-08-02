#!/bin/bash
# Vault-first drift audit.
#
# The vault is canonical and the machine is a checkout, so drift is worth
# knowing about in both directions:
#   local-only   a secret exists here and nowhere else — one disk failure from gone
#   vault-only   a secret is backed up but not on this machine — often deliberate
#
# Secret values are never printed. Only public halves (.pub attachments) are
# downloaded, for fingerprint comparison; private key material is never read.
set -euo pipefail
. "$(dirname "$0")/secrets-common.sh"

require bw jq yq ssh-keygen
bw_open
bw sync >/dev/null

findings=0
flag() { warn "$*"; findings=$((findings + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
chmod 700 "$tmp"

note "== SSH key estate =="
bw_items "$BW_SSH" | jq -r '.[] | .id as $i | (.attachments // [])[] | "\($i) \(.id) \(.fileName)"' > "$tmp/vault-ssh"
cut -d' ' -f3- "$tmp/vault-ssh" | sort > "$tmp/vault-names"

# ~/.ssh holds more than key material. config is vaulted as a restore item and
# is checked in the next section; the rest is machine-local by nature.
find "$HOME/.ssh" -maxdepth 1 -type f -exec basename {} \; 2>/dev/null \
  | grep -Ev '^(config|known_hosts|known_hosts\.old|authorized_keys|environment|rc)$' \
  | sort > "$tmp/local-names" || true

while read -r name; do
  [ -n "$name" ] && flag "local-only (unbacked): ~/.ssh/$name"
done < <(comm -23 "$tmp/local-names" "$tmp/vault-names")

while read -r name; do
  [ -n "$name" ] && note "  vault-only (not restored here): $name"
done < <(comm -13 "$tmp/local-names" "$tmp/vault-names")

# Same name on both sides is not the same key, and the same key can sit under
# two names. Fingerprint every public half on both sides, then compare twice:
# by name (a mismatch) and by fingerprint (a duplicate under another name).
# Keypairs whose .pub is absent stay outside both comparisons by design —
# private key material is never read, so only the name checks above cover them.
: > "$tmp/vault-fp"
while read -r item att name; do
  case "$name" in *.pub) ;; *) continue ;; esac
  bw get attachment "$att" --itemid "$item" --raw > "$tmp/cmp.pub"
  vault_fp="$(ssh-keygen -lf "$tmp/cmp.pub" | awk '{print $2}')"
  printf '%s %s vault\n' "$vault_fp" "$name" >> "$tmp/vault-fp"
done < "$tmp/vault-ssh"
rm -f "$tmp/cmp.pub"

: > "$tmp/local-fp"
while read -r name; do
  case "$name" in *.pub) ;; *) continue ;; esac
  local_fp="$(ssh-keygen -lf "$HOME/.ssh/$name" | awk '{print $2}')"
  printf '%s %s local\n' "$local_fp" "$name" >> "$tmp/local-fp"
done < "$tmp/local-names"

compared=0
while read -r fp name _; do
  here="$(awk -v n="$name" '$2 == n { print $1 }' "$tmp/local-fp")"
  [ -n "$here" ] || continue
  if [ "$fp" = "$here" ]; then
    compared=$((compared + 1))
  else
    flag "fingerprint mismatch: ~/.ssh/$name differs from the vault copy"
  fi
done < "$tmp/vault-fp"

# The vault's filename is canonical; the machine is a checkout of it.
while read -r dupe; do
  [ -n "$dupe" ] && flag "same key under different filenames: $dupe — the vault name is canonical, so rename the local file to it and repoint ~/.ssh/config"
done < <(cat "$tmp/vault-fp" "$tmp/local-fp" | awk '
  !seen[$1 SUBSEP $2]++ {
    names[$1] = names[$1] (names[$1] == "" ? "" : ", ") $2 " (" $3 ")"
    n[$1]++
  }
  END { for (f in names) if (n[f] > 1) print names[f] }' | sort)

note "  $(wc -l < "$tmp/vault-names" | tr -d ' ') in the vault, $(wc -l < "$tmp/local-names" | tr -d ' ') on this machine, $compared fingerprints matched"

note "== Self-describing restore items =="
while read -r path; do
  [ -n "$path" ] || continue
  if [ -e "$HOME/$path" ]; then
    note "  present"
  else
    note "  vault-only (not restored here)"
  fi
done < <(bw_items "$BW_RESTORE" | jq -r '.[] | [(.fields // [])[] | select(.name == "path") | .value][0] // ""')

note "== Template refs (.chezmoidata/secrets.yaml) =="
# The map is the expected-set: every ref a template resolves must exist.
bw list items | jq -r '.[].name' | sort -u > "$tmp/bw-names"
while read -r key domain ref; do
  case "$domain" in
    personal)
      if grep -qxF "$ref" "$tmp/bw-names"; then
        note "  ok        $key"
      else
        flag "missing from the personal vault: $key"
      fi
      ;;
    work)
      note "  deferred  $key (work domain — issue #13)"
      ;;
  esac
done < <(yq -r '.secrets | to_entries[] | .key + " " + .value.domain + " " + .value.ref' "$SECRETS_MAP")

note "== Local backup freshness =="
# -mtime rather than stat: BSD and GNU stat disagree on flags, find does not.
any="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'secrets-*.zip.gpg' 2>/dev/null | head -1 || true)"
fresh="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'secrets-*.zip.gpg' -mtime -"$BACKUP_MAX_AGE_DAYS" 2>/dev/null | head -1 || true)"
if [ -z "$any" ]; then
  flag "no local backup archive — run scripts/secrets-backup.sh"
elif [ -z "$fresh" ]; then
  flag "the last local backup is older than $BACKUP_MAX_AGE_DAYS days — run scripts/secrets-backup.sh"
else
  note "  ok        backed up within $BACKUP_MAX_AGE_DAYS days"
fi

report_work_domain || true

note ""
if [ "$findings" -eq 0 ]; then
  note "No drift. The machine matches the vault."
else
  note "$findings finding(s) above."
  exit 1
fi
