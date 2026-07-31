# brew-installed nvm needs explicit sourcing; default alias lts/* (#5 §5)
export NVM_DIR="$HOME/.nvm"
[ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
