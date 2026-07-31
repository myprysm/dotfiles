# compinit already ran inside oh-my-zsh; bashcompinit is what `complete -C`
# and bash-style completion files need. Each source is guarded so a machine
# without the tool loads a clean shell (#4 §2).
autoload -U +X bashcompinit && bashcompinit

# nvm ships a bash completion; needs bashcompinit, hence here and not 40-nvm
[ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \
  source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"

# vault/terraform completion comes from their omz plugins — no `complete -C`
# duplicate here (#4 §5).
command -v kubeone >/dev/null && source <(kubeone completion zsh)

if command -v uv >/dev/null; then
  eval "$(uv generate-shell-completion zsh)"
  eval "$(uvx --generate-shell-completion zsh)"
fi
