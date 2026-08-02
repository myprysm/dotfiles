# McFly's init returns before binding ^R if HISTFILE is not readable, so on a
# fresh machine it is inert, not merely noisy. Seed the file at 600, the mode
# zsh itself would use. Test existence, not readability: an unreadable file is
# a permissions fault, and truncating it is the wrong answer. Failure is silent
# because McFly's own warning already says it, and a second one on every shell
# is worse than the first. Never chezmoi-managed — see home/.chezmoiignore.
() {
  local histfile=${HISTFILE:-$HOME/.zsh_history}
  [[ -e $histfile ]] || (umask 077; : > "$histfile") 2>/dev/null
}
eval "$(mcfly init zsh)"
