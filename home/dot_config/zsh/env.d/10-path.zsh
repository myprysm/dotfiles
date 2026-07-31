# User paths. $HOMEBREW_PREFIX is already set — .zprofile runs `brew shellenv`
# before .zshrc on both OSes (#4), which is what fixed the WSL ordering bug.
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
