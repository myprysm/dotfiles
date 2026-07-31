#!/bin/bash
# Shared helpers for the secrets-* scripts (issues #11, #15, #19).
# Sourced, never executed. Contains no item names and no destination paths:
# every identifying string lives in the vault, per the redaction rule.

# Generic containers only. bw uses nested folders, op mirrors them as tags (#15 §1).
BW_ROOT="dotfiles"
BW_SSH="dotfiles/ssh"
BW_RESTORE="dotfiles/restore"

# Machine-local, outside the repo and outside chezmoi's source dir (#11 §4).
BACKUP_DIR="$HOME/.local/share/dotfiles-secrets"
BACKUP_MAX_AGE_DAYS=30

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_MAP="$REPO_ROOT/home/.chezmoidata/secrets.yaml"

warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required but not on PATH"
  done
}

# Exports BW_SESSION, unlocking interactively if needed. The scripts are
# explicitly invoked (#11 §5), so an interactive prompt is the right gate.
bw_open() {
  if [ -n "${BW_SESSION:-}" ] && [ "$(bw status | jq -r .status)" = "unlocked" ]; then
    return
  fi
  BW_SESSION="$(bw unlock --raw)" || die "could not unlock the personal vault"
  export BW_SESSION
}

bw_folder_id() {
  bw list folders --search "$1" \
    | jq -r --arg n "$1" '.[] | select(.name == $n) | .id'
}

bw_items() {
  local id
  id="$(bw_folder_id "$1")"
  [ -n "$id" ] || die "vault folder '$1' not found — has this machine been seeded?"
  bw list items --folderid "$id"
}

# Work domain is on only when the bundle is enabled AND op is installed (#5, #19).
# op enumeration itself is deferred to #13, which seeds and verifies the work vault.
work_bundle_enabled() {
  command -v chezmoi >/dev/null 2>&1 || return 1
  [ "$(chezmoi data --format json 2>/dev/null | jq -r '.bundles.work // false')" = "true" ]
}

report_work_domain() {
  if ! work_bundle_enabled; then
    note "work domain: bundle off — personal vault only"
    return 1
  fi
  if ! command -v op >/dev/null 2>&1; then
    warn "work bundle is on but op is not installed — skipping the work domain"
    return 1
  fi
  warn "work domain not implemented yet (see issue #13) — skipping"
  return 1
}
