#!/bin/sh
# PROTOTYPE (wayfinder #7) — bootstrap a fresh machine onto myprysm/dotfiles.
# Sequence decided in issue #6. Draft: not yet exercised on a naked machine (#9 does that).
set -eu

REPO="myprysm/dotfiles"

echo "==> [1/7] OS prerequisites"
case "$(uname -s)" in
  Linux)
    # WSL only: .gitconfig hardcodes gpg.program=/usr/local/bin/gpg because the
    # signing key lives in the Windows GnuPG store (#6, #8 deviation 11), and
    # nothing else in this repo creates that symlink. Without it a fresh WSL
    # machine gets commit.gpgsign=true pointing at nothing and cannot commit.
    # No key material is involved here — this only makes gpg.program resolvable.
    # Runs BEFORE apt (#9): the check needs nothing apt provides, and a machine
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

      # -f, because [ -e ] is FALSE on a dangling symlink (#9): a link left over
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

    # The single owner of apt prerequisites (superset of Homebrew's needs +
    # #5 §4 build deps). Hand-cloned repos run this script too — no
    # run_once_before_ duplicate in .chezmoiscripts.
    sudo apt-get update
    sudo apt-get install -y build-essential procps curl file git zsh libffi-dev python3-dev
    ;;
  Darwin)
    : # Homebrew installer handles Xcode CLT itself.
    ;;
esac

echo "==> [2/7] Homebrew"
# Test the install prefixes, not PATH (#9): nothing here writes `brew shellenv`
# into the login shell, so `command -v brew` is false in every fresh shell and a
# re-run would download and run the whole Homebrew installer again.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  BREW=/home/linuxbrew/.linuxbrew/bin/brew
elif [ -x /opt/homebrew/bin/brew ]; then
  BREW=/opt/homebrew/bin/brew
elif command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    BREW=/home/linuxbrew/.linuxbrew/bin/brew
  else
    BREW=/opt/homebrew/bin/brew
  fi
fi
eval "$("$BREW" shellenv)"

echo "==> [3/7] chezmoi"
brew install chezmoi

echo "==> [4/7] chezmoi init (prompts: email, Bitwarden server URL, bundles)"
chezmoi init "$REPO"   # no --apply: secret CLIs must be installed + authed first

echo "==> [5/7] Secret manager CLIs"
brew install bitwarden-cli
WORK_BUNDLE="$(chezmoi execute-template '{{ .bundles.work }}')"
if [ "$WORK_BUNDLE" = "true" ]; then
  case "$(uname -s)" in
    Darwin) brew install --cask 1password-cli ;;
    Linux)  echo "TODO: op via 1Password apt repo" ;;
  esac
fi

echo "==> [6/7] Authenticate"
# bw refuses `config server` while logged in ("Logout required before server
# config update"), which under set -e killed every re-run (#9). Setting the
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
  eval "$(op signin)"
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
