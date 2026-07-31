#!/bin/sh
# PROTOTYPE (wayfinder #7) — bootstrap a fresh machine onto myprysm/dotfiles.
# Sequence decided in issue #6. Draft: not yet exercised on a naked machine (#9 does that).
set -eu

REPO="myprysm/dotfiles"

echo "==> [1/7] OS prerequisites"
case "$(uname -s)" in
  Linux)
    # The ONE sudo moment, and the single owner of apt prerequisites
    # (superset of Homebrew's needs + #5 §4 build deps). Hand-cloned repos
    # run this script too — no run_once_before_ duplicate in .chezmoiscripts.
    sudo apt-get update
    sudo apt-get install -y build-essential procps curl file git zsh libffi-dev python3-dev

    # WSL only: .gitconfig hardcodes gpg.program=/usr/local/bin/gpg because the
    # signing key lives in the Windows GnuPG store (#6, #8 deviation 11), and
    # nothing else in this repo creates that symlink. Without it a fresh WSL
    # machine gets commit.gpgsign=true pointing at nothing and cannot commit.
    # No key material is involved here — this only makes gpg.program resolvable.
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

      if [ ! -e /usr/local/bin/gpg ]; then
        echo "    linking /usr/local/bin/gpg -> Windows GnuPG"
        sudo ln -s "$WIN_GPG" /usr/local/bin/gpg
      fi

      if ! /usr/local/bin/gpg --version >/dev/null 2>&1; then
        echo "FATAL: /usr/local/bin/gpg exists but will not run." >&2
        echo "       Windows-interop is most likely unregistered — check that" >&2
        echo "       /proc/sys/fs/binfmt_misc/WSLInterop exists. 'wsl --shutdown'" >&2
        echo "       from Windows and reopen the terminal, then re-run." >&2
        exit 1
      fi
    fi
    ;;
  Darwin)
    : # Homebrew installer handles Xcode CLT itself.
    ;;
esac

echo "==> [2/7] Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [ -d /home/linuxbrew/.linuxbrew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -d /opt/homebrew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

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
BW_SERVER="$(chezmoi execute-template '{{ .bwServer }}')"
bw config server "$BW_SERVER"
bw login --check >/dev/null 2>&1 || bw login
BW_SESSION="$(bw unlock --raw)"
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
