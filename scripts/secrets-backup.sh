#!/bin/bash
# Monthly local vault backup.
#
# Vaultwarden is backed up infra-side; this is the second copy that survives
# losing the server. One passphrase-encrypted archive in a machine-local
# directory, never in this repo.
#
# `bw export --format zip` bundles data.json AND the attachment tree, so the
# per-item download loop the vault policy originally specified is no longer
# was lifted upstream (verified against bw 2026.6.0). Caveat inherited from the
# implementation: organisation-owned and trashed ciphers get no attachments.
#
# The work domain is deliberately not covered. `op` has no export command at all
# (its whole command surface was checked, not assumed), so any work-domain
# archive would have to be hand-rolled item by item — which means writing the
# employer's secrets to a personal machine's disk to guard against a loss the
# employer already guards against. Decided rather than deferred, and said out
# loud at the end of a run so the gap is not mistaken for an oversight.
set -euo pipefail
. "$(dirname "$0")/secrets-common.sh"

require bw jq gpg
bw_open
bw sync >/dev/null

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
chmod 700 "$tmp"

stamp="$(date +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/secrets-$stamp.zip.gpg"

note "Exporting the personal vault (plaintext, into a 700 temp dir)…"
bw export --format zip --output "$tmp/vault.zip"
[ -s "$tmp/vault.zip" ] || die "the export produced nothing"

note "Encrypting — you will be prompted for an archive passphrase."
(umask 077; gpg --symmetric --cipher-algo AES256 --output "$out" "$tmp/vault.zip")
chmod 600 "$out"

note ""
note "Wrote ${out/#$HOME/\~} ($(du -h "$out" | cut -f1))"
note "Decrypt with: gpg --decrypt <archive> > vault.zip"
note "Store the passphrase where it does not depend on this vault."
if work_bundle_enabled; then
  note ""
  note "Work domain: not backed up, by design — op has no export command, and the"
  note "work vault is the employer's to back up. See docs/secrets.md."
fi
