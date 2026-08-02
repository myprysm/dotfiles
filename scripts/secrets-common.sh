#!/bin/bash
# Shared helpers for the secrets-* scripts.
# Sourced, never executed. Contains no item names and no destination paths:
# every identifying string lives in the vault, per the redaction rule.

# Generic containers only. bw uses nested folders, op mirrors them as tags.
BW_ROOT="dotfiles"
BW_SSH="dotfiles/ssh"
BW_RESTORE="dotfiles/restore"

# WSL's git signs through the Windows GnuPG store; bootstrap.sh creates this
# symlink and .gitconfig hardcodes the same path.
# Overridable so the import branch can be exercised without touching the real
# Windows keyring; the default is the only path .gitconfig knows about.
WSL_GPG="${WSL_GPG:-/usr/local/bin/gpg}"

# Machine-local, outside the repo and outside chezmoi's source dir.
BACKUP_DIR="$HOME/.local/share/dotfiles-secrets"
BACKUP_MAX_AGE_DAYS=30

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_MAP="$REPO_ROOT/home/.chezmoidata/secrets.yaml"

warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

is_wsl() {
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

# On WSL the shim above SHADOWS the native binary: the default PATH puts
# /usr/local/bin ahead of /usr/bin, so on a machine without a brew-installed
# gnupg a bare `gpg` IS the Windows exe. Resolve the native one explicitly, or
# the "Linux keyring" import silently lands in the Windows store instead.
# Overridable for testing, like WSL_GPG.
if [ -z "${LINUX_GPG:-}" ]; then
  if is_wsl; then LINUX_GPG="/usr/bin/gpg"; else LINUX_GPG="gpg"; fi
fi

require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required but not on PATH"
  done
}

# Exports BW_SESSION, unlocking interactively if needed. The scripts are
# explicitly invoked, so an interactive prompt is the right gate.
#
# The password is read here and handed to bw through the environment rather than
# letting bw prompt. `BW_SESSION="$(bw unlock --raw)"` cannot work: command
# substitution gives bw a pipe for stdout, its prompt library requires a TTY
# there, and it dies with ERR_USE_AFTER_CLOSE. Worse, it still exits 0 having
# printed nothing, so the empty session went undetected and every later bw call
# re-prompted — and those run inside `while read` loops whose stdin is a file, so
# they could not have read a password either. Unlocking once, here, is what makes
# the rest of the script's loops safe.
bw_open() {
  if [ -n "${BW_SESSION:-}" ] && [ "$(bw status | jq -r .status)" = "unlocked" ]; then
    return
  fi
  # Tested by opening it, not with `-r`: in a session with no controlling
  # terminal /dev/tty passes a readability test and then fails to open, which
  # printed the prompt and a raw "Device not configured" before the real error.
  # Where to read the password from, in order of what actually works. stdin comes
  # first: a process can have an interactive stdin and still have no controlling
  # terminal, which is exactly the case when these scripts are launched from an
  # agent session — /dev/tty then fails to open even though the operator can type.
  # /dev/tty is the fallback for the opposite case, a script whose stdin has been
  # redirected. Redirection order in the probe matters: bash applies them left to
  # right, so `: < /dev/tty 2>/dev/null` lets the failed open report to the real
  # stderr before 2>/dev/null is in effect. stderr first.
  local pw src=""
  if [ -t 0 ] || [ -p /dev/stdin ]; then
    # A pipe counts: bw_open runs before any of the callers' `while read` loops,
    # so nothing else is competing for stdin, and rejecting a piped password made
    # the scripts unusable from anything but a terminal.
    src="stdin"
  elif : 2>/dev/null < /dev/tty; then
    src="tty"
  else
    die "no way to prompt for the master password here. Either run this from a
       terminal, or unlock the vault yourself and pass the session in:
         BW_SESSION=\"\$(bw unlock --raw)\" $(basename "$0")"
  fi

  printf 'Master password (personal vault): ' >&2
  if [ "$src" = "stdin" ]; then
    IFS= read -rs pw || die "could not read the master password"
  else
    IFS= read -rs pw < /dev/tty || die "could not read the master password"
  fi
  printf '\n' >&2

  export BW_PASSWORD="$pw"
  pw=""
  BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)" || true
  unset BW_PASSWORD

  # Checked for emptiness, not by exit status: see above.
  [ -n "${BW_SESSION:-}" ] || die "could not unlock the personal vault — wrong password, or bw is not logged in"
  export BW_SESSION
}

bw_folder_id() {
  bw list folders --search "$1" \
    | jq -r --arg n "$1" '.[] | select(.name == $n) | .id'
}

bw_items() {
  local id
  # A locked vault lists nothing, which used to surface as "has this machine been
  # seeded?" — blaming the vault's contents for a failed unlock. Distinguish them.
  [ "$(bw status | jq -r .status)" = "unlocked" ] \
    || die "the personal vault is locked — the unlock did not take effect"
  id="$(bw_folder_id "$1")"
  [ -n "$id" ] || die "vault folder '$1' not found — has this machine been seeded?"
  bw list items --folderid "$id"
}

# Work domain is on only when the bundle is enabled AND op is installed.
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
