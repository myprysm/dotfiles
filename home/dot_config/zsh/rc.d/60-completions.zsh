# compinit already ran inside oh-my-zsh; bashcompinit is what `complete -C`
# and bash-style completion files need. Each source is guarded so a machine
# without the tool loads a clean shell.
autoload -U +X bashcompinit && bashcompinit

# nvm ships a bash completion; needs bashcompinit, hence here and not 40-nvm
[ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \
  source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"

# Only tools that NOTHING else supplies belong here. Three layers already cover
# most of the estate, all of them versioned with the tool and self-refreshing:
#   1. brew's share/zsh/site-functions, on fpath via `brew shellenv` in
#      .zprofile — 33 files, incl. _argocd _cyphernetes _hcloud _doctl _helm
#      _kubectl _velero _talosctl _k9s _uv _uvx _gh _bw _op _rclone _yq.
#   2. omz plugins shipping a static function: terraform (_terraform), golang,
#      docker-compose, gradle, laravel (_artisan), 1password.
#   3. omz plugins generating at load: vault (`complete -C`, and it calls
#      bashcompinit itself, so ordering here does not matter), kubectl, npm,
#      docker (caches its own _docker under $ZSH_CACHE_DIR), composer, dotnet,
#      doctl, git.
# Verified absent from all three, hence the two blocks below: kubeone (a
# hand-installed binary with no formula) and rustup/cargo (rustup is not a brew
# formula). The uv/uvx `generate-shell-completion` evals that used to live here
# were removed: the formula ships _uv and _uvx, so they bought nothing and cost
# two subprocesses per shell start.
command -v kubeone >/dev/null && source <(kubeone completion zsh)

# compinit has already run inside oh-my-zsh, so a sourced completion needs an
# explicit compdef to bind the function it defines.
if command -v rustup >/dev/null; then
  source <(rustup completions zsh)
  compdef _rustup rustup
  source <(rustup completions zsh cargo)
  compdef _cargo cargo
fi
