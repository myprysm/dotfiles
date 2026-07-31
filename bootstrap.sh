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

cat <<'EOF'

Done. Post-bootstrap checklist (tool-native auth, never in the repo):
  - gh auth login
  - docker login <registries>
  - npm / composer registry auth (work bundle)
  - chsh -s "$(command -v zsh)"   # if zsh is not the login shell yet
  - scripts/secrets-restore.sh    # ONLY on a machine that should hold your keys
EOF
