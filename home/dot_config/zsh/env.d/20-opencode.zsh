# opencode's installer appends this export to ~/.zshrc, which chezmoi apply
# then erases. A reinstall appends it again; delete that line rather than adopt it.
export PATH="$HOME/.opencode/bin:$PATH"
