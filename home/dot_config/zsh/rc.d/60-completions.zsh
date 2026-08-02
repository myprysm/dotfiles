# compinit already ran inside oh-my-zsh; bashcompinit is what `complete -C`
# and bash-style completion files need. Each source is guarded so a machine
# without the tool loads a clean shell.
autoload -U +X bashcompinit && bashcompinit

# nvm ships a bash completion; needs bashcompinit, hence here and not 40-nvm
[ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \
  source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"

# Only tools that NOTHING else supplies belong here. Three layers already cover
# the estate, each versioned with its tool and refreshing itself:
#   1. brew's share/zsh/site-functions, on fpath via `brew shellenv` in
#      .zprofile. Every brew formula's completion arrives this way — no list
#      here, because any list goes stale on the next `brew install`.
#   2. omz plugins, either shipping a static function (terraform, golang,
#      docker-compose, laravel) or generating one at load (vault via
#      `complete -C`, which calls bashcompinit itself so ordering here is
#      irrelevant; kubectl; npm; composer; git; docker, which caches its own
#      _docker under $ZSH_CACHE_DIR). Bundle-gated plugins supply theirs only
#      when that bundle is on — see .chezmoidata/zsh.yaml.
#   3. a tool's own versioned tree placed on fpath from env.d — cargo, in
#      20-cargo.zsh.
# What is left over is the two blocks below: kubeone (a hand-installed binary
# with no formula) and rustup (not a brew formula). The uv/uvx
# `generate-shell-completion` evals that used to live here were removed — the
# formula ships _uv and _uvx, so they bought nothing and cost two subprocesses
# per shell start.
# cobra-generated completions self-register: their second line is already
# `compdef _<tool> <tool>`, so sourcing is the whole job and no compdef belongs
# here. Verified against chezmoi's output as the shape all cobra CLIs emit.
for c in kubeone sqlc; do
  command -v "$c" >/dev/null && source <("$c" completion zsh)
done
unset c

# rustup is clap, not cobra, but it also self-registers (its tail runs
# `compdef _rustup rustup`), so sourcing is all it needs.
# cargo is deliberately NOT here: its completion ships inside the toolchain and
# goes on fpath in env.d/20-cargo.zsh instead — `rustup completions zsh cargo`
# sources a completion function file, which prints an _arguments error at every
# shell start.
command -v rustup >/dev/null && source <(rustup completions zsh)
