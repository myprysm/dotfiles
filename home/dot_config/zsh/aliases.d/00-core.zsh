# Adding an alias = drop a file here, `chezmoi apply`, synced everywhere.
# Machine-specific aliases (hardcoded contexts, hosts, project paths) belong in
# untracked ~/.zshrc.local instead — the repo is public.
alias cls='clear'
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias jqd64='jq -r ".data|map_values(@base64d)"'
alias genpass="dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d -- '\n' | tr -- '+/' '-_'; echo"
alias ll="eza -l"
alias la="eza -la"
# The pnpm shim exists only after `corepack enable`, which no install step runs.
alias ccusage="corepack pnpm dlx ccusage@latest"
