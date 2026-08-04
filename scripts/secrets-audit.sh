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

require bw jq yq ssh-keygen git
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

note "== Commit signing =="
# The hole this section closes: the audit used to ask only whether a vault ref
# RESOLVED, and printed `ok` for the signing key on a machine where
# `git commit -S` failed with "No secret key". A ref that resolves to a key the
# local keyring cannot use is drift, and drift is what this script exists to
# find. Each machine now signs with its own key (#48/#50), so there is no ref to
# resolve and the only real question is whether git can sign here.
#
# Metadata only: --list-secret-keys reads the keyring's public records and the
# presence of a secret stub. No passphrase is requested and no key material is
# read, so the property stated at the top of this file still holds. A real
# signing test would prove more and is deliberately not done — it raises a
# pinentry prompt, and an audit that blocks is an audit nobody runs unattended.
sign_key="$(git config --get user.signingkey 2>/dev/null || true)"
sign_on="$(git config --get commit.gpgsign 2>/dev/null || true)"
gpg_bin="$(git_gpg)"
if [ "$sign_on" != "true" ]; then
  note "  n/a       commit.gpgsign is off on this machine"
elif [ -z "${sign_key}" ]; then
  flag "commit.gpgsign is on but no user.signingkey is set — git falls back to whatever gpg calls its default key, which is not a choice this estate makes. Set it in ~/.gitconfig.local"
elif ! "$gpg_bin" --version >/dev/null 2>&1; then
  flag "git signs through '$gpg_bin' (gpg.program) and it will not run — nothing can be signed here"
else
  note "  key       $sign_key"
  note "  store     $gpg_bin (git's gpg.program)"
  sec="$("$gpg_bin" --with-colons --list-secret-keys "$sign_key" 2>/dev/null \
    | awk -F: '$1 == "sec" { print; exit }')"
  if [ -z "$sec" ]; then
    flag "user.signingkey $sign_key is configured but that store holds no matching secret key — git commit -S fails with \"No secret key\". Either this is another machine's key, or this machine has yet to generate one (see bootstrap.sh)"
  else
    # Field 2 is validity, field 7 the expiry timestamp (empty = never), field 12
    # the capabilities — where an UPPERCASE letter means the key as a whole,
    # subkeys included, can do it. So `S` and not `s` is the question.
    validity="$(cut -d: -f2 <<<"$sec")"
    expires="$(cut -d: -f7 <<<"$sec")"
    caps="$(cut -d: -f12 <<<"$sec")"
    case "$validity" in
      r) flag "user.signingkey $sign_key is REVOKED — git commit -S will refuse it" ;;
      e) flag "user.signingkey $sign_key has EXPIRED — git commit -S will refuse it" ;;
      d) flag "user.signingkey $sign_key is disabled — git commit -S will refuse it" ;;
      i) flag "user.signingkey $sign_key is invalid — git commit -S will refuse it" ;;
      *)
        if [[ "$caps" != *S* ]]; then
          flag "user.signingkey $sign_key carries no signing capability (caps: $caps) — it is the wrong key for commit.gpgsign"
        elif [ -n "$expires" ] && [ "$expires" -le "$(date +%s)" ]; then
          flag "user.signingkey $sign_key expired on $(date -r "$expires" +%Y-%m-%d 2>/dev/null || echo "$expires")"
        else
          note "  ok        secret key present, sign-capable, not expired"
        fi
        ;;
    esac
  fi
fi

note "== Config fragments =="
# rclone.conf is assembled from vault fragments by run_once_40, which never
# overwrites an existing config: on divergence it writes a .from-vault copy
# beside it and asks for a hand reconcile. That warning scrolls past once and is
# then invisible, which is how the vault came to hold fewer remotes than the
# machine with the audit reporting `ok`. The leftover copy is the standing
# signal. Deliberately no content comparison: the fragment is credentials end to
# end, and reading it would cost this script its never-read-private-material
# property for a check the sidecar already gives away for free.
sidecar="$HOME/.config/rclone/rclone.conf.from-vault"
if [ -e "$sidecar" ]; then
  flag "${sidecar/#$HOME/\~} exists — the vault fragment diverged from this machine and was never reconciled. Reconcile, re-seed the vault, then delete the copy"
else
  note "  ok        no unreconciled fragment copy"
fi

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
