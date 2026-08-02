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

note "== Work domain =="
work_ready=0
if work_domain_ready; then
  work_ready=1
  note "  reachable — '$OP_VAULT' vault"
fi

note "== SSH key estate =="
bw_items "$BW_SSH" | jq -r '.[] | .id as $i | (.attachments // [])[] | "\($i) \(.id) \(.fileName)"' > "$tmp/vault-ssh"
cut -d' ' -f3- "$tmp/vault-ssh" | sort > "$tmp/vault-names"

# Work SSH items join the same tables rather than getting a section of their own:
# a key held in one domain and checked out under the other is exactly the drift
# worth catching, and it is invisible if the two are audited separately.
#
# op stores the key natively and carries no filename, so the canonical name is
# the basename of its `path` field — the same string the restore writes to disk,
# which is what makes it comparable with a bw attachment name. One item accounts
# for two local files, so both go into the name table.
: > "$tmp/op-ssh"
: > "$tmp/op-names"
if [ "$work_ready" -eq 1 ]; then
  while read -r id; do
    [ -n "$id" ] || continue
    p="$(op_item_json "$id" | op_field path)"
    if [ -z "$p" ]; then
      flag "a work SSH item carries no path field — it can be neither restored nor compared"
      continue
    fi
    printf '%s %s\n' "$id" "$(basename "$p")" >> "$tmp/op-ssh"
  done < <(op_items_tagged "$OP_TAG_SSH" | jq -r '.[].id')
  awk '{ print $2; print $2 ".pub" }' "$tmp/op-ssh" | sort -u > "$tmp/op-names"
  sort -u "$tmp/vault-names" "$tmp/op-names" > "$tmp/all-vault-names"
  mv "$tmp/all-vault-names" "$tmp/vault-names"
fi

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
  printf '%s %s bw\n' "$vault_fp" "$name" >> "$tmp/vault-fp"
done < "$tmp/vault-ssh"
rm -f "$tmp/cmp.pub"

# op publishes the fingerprint as item metadata, in the same SHA256 form
# ssh-keygen prints (checked equal against a generated keypair), so the work half
# is compared with no download at all — a stronger form of the never-read-private-
# material property the bw arm buys by fetching only .pub attachments.
if [ "$work_ready" -eq 1 ]; then
  while read -r id name; do
    fp="$(op_run read "op://$OP_VAULT/$id/fingerprint" 2>/dev/null || true)"
    if [ -z "$fp" ]; then
      flag "work key $name publishes no fingerprint — it cannot be compared"
      continue
    fi
    printf '%s %s.pub op\n' "$fp" "$name" >> "$tmp/vault-fp"
  done < "$tmp/op-ssh"
fi

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

# The assertion the work-key move depends on: for each work key, does the
# personal vault still hold the same fingerprint? Reported as a note and not a
# finding, because during the move both vaults legitimately hold it — the point
# is to be able to say the op copy is verified BEFORE anything is deleted from bw.
# The duplicate detector above cannot say this: it groups on (fingerprint, name),
# so one key under one name in both vaults collapses to a single entry.
if [ "$work_ready" -eq 1 ] && [ -s "$tmp/op-ssh" ]; then
  crossed=0
  while read -r fp name side; do
    [ "$side" = "op" ] || continue
    if awk -v f="$fp" '$1 == f && $3 == "bw" { found = 1 } END { exit !found }' "$tmp/vault-fp"; then
      note "  work key also in the personal vault: $name — op copy fingerprint-verified (#48)"
      crossed=$((crossed + 1))
    fi
  done < "$tmp/vault-fp"
  if [ "$crossed" -eq 0 ]; then
    note "  no work key is duplicated in the personal vault"
  fi
fi

note "  $(wc -l < "$tmp/vault-names" | tr -d ' ') vaulted ($(wc -l < "$tmp/op-names" | tr -d ' ') work), $(wc -l < "$tmp/local-names" | tr -d ' ') on this machine, $compared fingerprints matched"

note "== Self-describing restore items =="
while read -r path; do
  [ -n "$path" ] || continue
  if [ -e "$HOME/$path" ]; then
    note "  present"
  else
    note "  vault-only (not restored here)"
  fi
done < <(bw_items "$BW_RESTORE" | jq -r '.[] | [(.fields // [])[] | select(.name == "path") | .value][0] // ""')

if [ "$work_ready" -eq 1 ]; then
  while read -r id; do
    [ -n "$id" ] || continue
    p="$(op_item_json "$id" | op_field path)"
    if [ -z "$p" ]; then
      flag "a work restore item carries no path field"
    elif [ -e "$HOME/$p" ]; then
      note "  present (work)"
    else
      note "  vault-only (not restored here, work)"
    fi
  done < <(op_items_tagged "$OP_TAG_RESTORE" | jq -r '.[].id')
fi

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
      if [ "$work_ready" -eq 0 ]; then
        note "  skipped   $key (work domain unavailable)"
      elif op_run item get "$ref" --vault "$OP_VAULT" >/dev/null 2>&1; then
        note "  ok        $key"
      else
        flag "missing from the work vault: $key"
      fi
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
if work_bundle_enabled; then
  # Stated rather than silent: a whole domain missing from a freshness section
  # reads as an oversight, and the next reader re-opens the question.
  note "  n/a       work domain has no local backup by design (see docs/secrets.md)"
fi

note ""
if [ "$findings" -eq 0 ]; then
  note "No drift. The machine matches the vault."
else
  note "$findings finding(s) above."
  exit 1
fi
