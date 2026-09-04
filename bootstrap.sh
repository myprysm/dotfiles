#!/bin/sh
# Bootstrap a fresh machine onto myprysm/dotfiles: OS prerequisites, Homebrew,
# chezmoi, the secret-manager CLIs, authentication, apply.
set -eu

REPO="myprysm/dotfiles"

echo "==> [1/7] OS prerequisites"
case "$(uname -s)" in
  Linux)
    # WSL only: .gitconfig hardcodes gpg.program=/usr/local/bin/gpg because the
    # signing key lives in the Windows GnuPG store, and
    # nothing else in this repo creates that symlink. Without it a fresh WSL
    # machine gets commit.gpgsign=true pointing at nothing and cannot commit.
    # No key material is involved here — this only makes gpg.program resolvable.
    # Runs BEFORE apt: the check needs nothing apt provides, and a machine
    # that cannot sign should hear so before paying for a full package run.
    if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
      echo "    WSL detected — checking the Windows GnuPG shim"
      WIN_GPG=""
      for candidate in \
        "/mnt/c/Program Files/GnuPG/bin/gpg.exe" \
        "/mnt/c/Program Files (x86)/GnuPG/bin/gpg.exe"
      do
        if [ -e "$candidate" ]; then WIN_GPG="$candidate"; break; fi
      done

      if [ -z "$WIN_GPG" ]; then
        echo "FATAL: WSL detected, but GnuPG is not installed on the Windows side." >&2
        echo "       git is configured to sign every commit through it." >&2
        echo "       Install Gpg4win on Windows, then re-run this script." >&2
        exit 1
      fi

      # -f, because [ -e ] is FALSE on a dangling symlink: a link left over
      # from a Gpg4win that has since moved would take the create branch and
      # collide, failing with a bare "ln: Already exists". -sfn is idempotent
      # and replaces a stale link with the one .gitconfig expects.
      echo "    linking /usr/local/bin/gpg -> Windows GnuPG"
      sudo ln -sfn "$WIN_GPG" /usr/local/bin/gpg

      if ! /usr/local/bin/gpg --version >/dev/null 2>&1; then
        echo "FATAL: /usr/local/bin/gpg exists but will not run." >&2
        echo "       Windows-interop is most likely unregistered — check that" >&2
        echo "       /proc/sys/fs/binfmt_misc/WSLInterop exists. 'wsl --shutdown'" >&2
        echo "       from Windows and reopen the terminal, then re-run." >&2
        exit 1
      fi
    fi

    # The single owner of apt prerequisites: a superset of Homebrew's needs plus
    # the manifest's build deps. Hand-cloned repos run this script too — no
    # run_once_before_ duplicate in .chezmoiscripts.
    sudo apt-get update
    # gnupg and openssh-client are declared rather than inherited: Ubuntu
    # 24.04 and 26.04 both ship them, but secrets-restore.sh hard-depends on
    # both, and a minimal or container-derived image need not carry either.
    sudo apt-get install -y build-essential procps curl file git zsh libffi-dev python3-dev \
      gnupg openssh-client
    ;;
  Darwin)
    : # Homebrew installer handles Xcode CLT itself.
    ;;
esac

echo "==> [2/7] Homebrew"
# Test the install prefixes, not PATH: nothing here writes `brew shellenv`
# into the login shell, so `command -v brew` is false in every fresh shell and a
# re-run would download and run the whole Homebrew installer again.
# All three prefixes, before and after the install. /usr/local is the Intel Mac
# one and was missing from the post-install branch, which fell through to
# /opt/homebrew — a path that does not exist there, so `brew shellenv` failed and
# took the whole bootstrap with it on the very machine the installer had just
# succeeded on.
find_brew() {
  for candidate in \
    /home/linuxbrew/.linuxbrew/bin/brew \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew
  do
    if [ -x "$candidate" ]; then echo "$candidate"; return 0; fi
  done
  command -v brew 2>/dev/null || return 1
}

if ! BREW="$(find_brew)"; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if ! BREW="$(find_brew)"; then
    echo "FATAL: Homebrew installed but no brew binary found in any known prefix." >&2
    exit 1
  fi
fi
eval "$("$BREW" shellenv)"

echo "==> [3/7] chezmoi"
brew install chezmoi

echo "==> [4/7] chezmoi init (prompts: email, Bitwarden server URL, bundles)"
chezmoi init "$REPO"   # no --apply: secret CLIs must be installed + authed first

# `chezmoi init` clones ONLY when the source directory is absent; on a machine
# that already has one it leaves the checkout exactly as it found it. Without
# this pull, re-running the one-liner silently applies stale source — a fix
# pushed to the repo appears to have failed when it was simply never fetched.
# Not fatal: a development machine whose source carries local or unpushed
# commits cannot fast-forward, and must still be able to bootstrap.
if chezmoi git -- pull --ff-only >/dev/null 2>&1; then
  echo "    source updated to $(chezmoi git -- rev-parse --short HEAD 2>/dev/null)"
else
  echo "    source NOT fast-forwarded — continuing with the checkout as-is" >&2
  echo "    (local commits, a detached HEAD, or no network)" >&2
fi

echo "==> [5/7] Secret manager CLIs"
brew install bitwarden-cli
WORK_BUNDLE="$(chezmoi execute-template '{{ .bundles.work }}')"
if [ "$WORK_BUNDLE" = "true" ]; then
  case "$(uname -s)" in
    Darwin) brew install --cask 1password-cli ;;
    # macOS-only by declaration, not by omission (issue #54): the apt repo is
    # the small half — op on Linux still needs a way to sign in, the desktop app
    # integration needs a desktop app, and WSL has none.
    Linux)  echo "    op is macOS-only — this machine gets no work domain (issue #54)." >&2
            echo "    Turn the work bundle off here; see docs/secrets.md." >&2 ;;
  esac
fi

echo "==> [6/7] Authenticate"
# bw refuses `config server` while logged in ("Logout required before server
# config update"), which under set -e killed every re-run. Setting the
# server is a logged-out-only act, so it belongs inside this branch — and
# `login --raw` hands back the session directly, sparing the second master
# password prompt that made a fresh login look like a rejection.
if ! bw login --check >/dev/null 2>&1; then
  BW_SERVER="$(chezmoi execute-template '{{ .bwServer }}')"
  bw config server "$BW_SERVER"
  BW_SESSION="$(bw login --raw)"
else
  BW_SESSION="$(bw unlock --raw)"
fi
export BW_SESSION
if [ "$WORK_BUNDLE" = "true" ]; then
  # Deliberately no sign-in. `eval "$(op signin)"` used to live here and claimed
  # an authentication it never performed: under the desktop app integration
  # `op signin` prints nothing, the session lives in the daemon, and the eval ran
  # an empty string and succeeded. The honest test is a real read (op_ready, in
  # scripts/secrets-common.sh), which every work caller already does for itself.
  # Where that test belongs is issue #35's call, not this step's.
  echo "    work domain NOT authenticated here — bootstrap does not sign in to op." >&2
  echo "    The first work read raises 1Password's approval prompt; see docs/secrets.md." >&2
fi

echo "==> [7/7] chezmoi apply"
chezmoi apply

# chezmoi init clones to ~/.local/share/chezmoi, and .chezmoiroot puts the source
# state one level down, so the repo root is the parent of the source path. The
# checklist prints an absolute path — a relative one resolves to nothing from $HOME.
REPO_DIR="$(dirname "$(chezmoi source-path)")"

cat <<EOF

Done. Post-bootstrap checklist (tool-native auth, never in the repo):
  - gh auth login
  - docker login <registries>
  - npm / composer registry auth (work bundle)
  - chsh -s "\$(command -v zsh)"   # if zsh is not the login shell yet
  - $REPO_DIR/scripts/secrets-restore.sh
      ONLY on a machine that should hold your keys
EOF

# Each machine signs with its own key, generated here and never exported, so
# nothing restores one onto a fresh machine any more. Detected, never done for
# you: ~/.gnupg is a private keyring this repo is hard-denied, which is the same
# reason the pinentry step below is manual — and on WSL the key has to be
# generated through the WINDOWS store, the one .gitconfig points gpg.program at,
# which no test here can reach.
GIT_GPG="$(git config --get gpg.program 2>/dev/null || true)"
[ -n "$GIT_GPG" ] || GIT_GPG="gpg"
if ! "$GIT_GPG" --list-secret-keys >/dev/null 2>&1 \
   || [ -z "$("$GIT_GPG" --with-colons --list-secret-keys 2>/dev/null | grep '^sec' || true)" ]
then
  cat <<EOF
  - THIS MACHINE HAS NO SIGNING KEY, and commit.gpgsign is on, so git cannot
    commit until all three are done:
      1. $GIT_GPG --quick-generate-key "\$(git config user.name) <\$(git config user.email)>" ed25519 sign 0
      2. printf '[user]\\n\\tsigningkey = <id>\\n' >> ~/.gitconfig.local
      3. $GIT_GPG --armor --export <id>    then paste it at github.com/settings/keys
    Verify with scripts/secrets-audit.sh, whose Commit signing section fails
    until all three are in place.
EOF
fi

# macOS-only. ~/.gnupg is hard-denied to this repo (it is a private keyring), so
# nothing here can write gpg-agent.conf and it has to be a manual step. Without
# it gpg-agent falls back to pinentry-curses: signing still works in a terminal,
# but a GUI git client gets no passphrase prompt at all.
if [ "$(uname -s)" = "Darwin" ]; then
  cat <<EOF
  - point gpg-agent at pinentry-mac (needed for GUI git clients only):
      echo "pinentry-program \$(command -v pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
      gpgconf --kill gpg-agent
EOF
fi
