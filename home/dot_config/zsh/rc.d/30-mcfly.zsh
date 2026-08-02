() {
  local histfile=${HISTFILE:-$HOME/.zsh_history}
  [[ -r $histfile ]] || (umask 077; : > $histfile)
}
eval "$(mcfly init zsh)"
