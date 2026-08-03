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

# McFly's own store is a full command transcript in SQLite and it creates the
# file at the ambient umask — 644 on both machines, world-readable, while every
# text history file on the estate is 600 because its tool sets it. Tighten the
# DIRECTORY as well as the file: SQLite writes sidecar files during a
# transaction and those would land at 644 again. Self-healing rather than a
# one-off chmod, so a rebuilt machine and a recreated database both get it.
() {
  local dir
  if [[ $OSTYPE == darwin* ]]; then
    dir=$HOME/Library/Application\ Support/McFly
  else
    dir=${XDG_DATA_HOME:-$HOME/.local/share}/mcfly
  fi
  [[ -d $dir ]] || return
  chmod 700 "$dir" 2>/dev/null
  [[ -e $dir/history.db ]] && chmod 600 "$dir"/history.db* 2>/dev/null
}
eval "$(mcfly init zsh)"
