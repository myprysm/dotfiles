#!/bin/bash
# Shared helpers for the secrets-* scripts.
# Sourced, never executed. Contains no item names and no destination paths:
# every identifying string lives in the vault, per the redaction rule.

# Generic containers only. bw uses nested folders, op mirrors them as tags.
BW_SSH="dotfiles/ssh"
BW_RESTORE="dotfiles/restore"

# Machine-local, outside the repo and outside chezmoi's source dir.
BACKUP_DIR="$HOME/.local/share/dotfiles-secrets"
BACKUP_MAX_AGE_DAYS=30

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_MAP="$REPO_ROOT/home/.chezmoidata/secrets.yaml"

warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

# The GnuPG binary git itself signs through, which is the only one whose keyring
# can answer "can this machine sign?". Never a bare `gpg`: on WSL that resolves
# to the Windows exe via /usr/local/bin, and .gitconfig points gpg.program there
# deliberately — so asking git is both simpler and correct on every machine.
# Overridable for testing.
git_gpg() {
  if [ -z "${GIT_GPG:-}" ]; then
    GIT_GPG="$(git config --get gpg.program 2>/dev/null || true)"
    [ -n "$GIT_GPG" ] || GIT_GPG="gpg"
  fi
  printf '%s\n' "$GIT_GPG"
}

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

work_bundle_enabled() {
  command -v chezmoi >/dev/null 2>&1 || return 1
  [ "$(chezmoi data --format json 2>/dev/null | jq -r '.bundles.work // false')" = "true" ]
}

# --- work domain (1Password) -------------------------------------------------
#
# op has no folders, so the containers mirror bw's folder paths as tags. The two
# are NOT the symmetric pair the naming conventions assumed: a bw folder is
# exact, while `op item list --tags dotfiles` ALSO returns everything tagged
# dotfiles/ssh and dotfiles/restore — tag selection is sub-nested, stated in
# `op item list --help` and confirmed against the live vault. Every enumeration
# below therefore filters the tag exactly, client-side.
OP_VAULT="${OP_VAULT:-Employee}"
OP_TAG_SSH="dotfiles/ssh"
OP_TAG_RESTORE="dotfiles/restore"

# Every op call is bounded, because op can BLOCK rather than fail. With the
# desktop app integration it raises a GUI approval prompt and waits — about two
# minutes before giving up with "authorization timeout". Unbounded, a restore
# loop over N work items stalls for N x 2 minutes having printed nothing.
#
# `op whoami` is no use as a gate: it never raises the prompt, and it reports
# "account is not signed in" even when the very next read would have succeeded.
# The only honest test is whether a real read works, which is what op_ready does.
OP_TIMEOUT="${OP_TIMEOUT:-45}"
if [ -z "${TIMEOUT_BIN:-}" ]; then
  # coreutils on both OSes (declared in core.darwin.brews, base on Linux), but
  # the scripts must not die on a machine that somehow lacks it: an unbounded
  # call is worse than no call only when it is also unannounced.
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
fi

op_run() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$OP_TIMEOUT" op "$@"
  else
    op "$@"
  fi
}

# Reachability, tested by reading. The migration recorded why this cannot be
# "is op installed": on a machine that has op but whose work vault is unseeded
# or unauthorized, the binary exists and every read fails.
op_ready() {
  local rc=0
  op_run vault get "$OP_VAULT" --format json >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 0 ;;
    124)
      warn "the work vault did not answer within ${OP_TIMEOUT}s — op's authorization"
      warn "  prompt went unapproved. Unlock 1Password, run 'op vault list' once, retry."
      return 1
      ;;
    *)
      warn "the work vault is not reachable (op exit $rc) — check that this account"
      warn "  can see the '$OP_VAULT' vault."
      return 1
      ;;
  esac
}

# The gate every work arm calls. Returns 0 only when the work domain is usable.
work_domain_ready() {
  if ! work_bundle_enabled; then
    note "work domain: bundle off — personal vault only"
    return 1
  fi
  if ! command -v op >/dev/null 2>&1; then
    warn "work bundle is on but op is not installed — skipping the work domain"
    return 1
  fi
  op_ready
}

# Item summaries carrying exactly this tag. See the sub-nesting note above.
op_items_tagged() {
  op_run item list --vault "$OP_VAULT" --tags "$1" --format json 2>/dev/null \
    | jq -c --arg t "$1" '[.[] | select((.tags // []) | any(. == $t))]'
}

op_item_json() {
  op_run item get "$1" --vault "$OP_VAULT" --format json 2>/dev/null
}

# Field value by label, reading item JSON on stdin. Custom fields (path, mode)
# and built-ins (notesPlain, fingerprint, public key) are the same shape here.
op_field() {
  jq -r --arg l "$1" '[((.fields // [])[] | select(.label == $l) | .value)][0] // ""'
}
