# rust bundle only (shipped via .chezmoiignore). rustup is installed with
# --no-modify-path because this repo owns PATH — which only works if the repo
# then actually adds it. Without this line the toolchain installs and the
# shell cannot see it.
export PATH="$HOME/.cargo/bin:$PATH"

# cargo's completion is shipped INSIDE the active toolchain, so it belongs on
# fpath rather than being sourced: the file is a completion function file, and
# sourcing it executes `_arguments` outside a completion context, which prints
# "can only be called from completion function" on every new shell (measured —
# `rustup completions zsh cargo` does exactly that, and this route is silent).
# It lives here, in env.d, because fpath must be complete before the compinit
# that runs inside oh-my-zsh. The path is toolchain-specific and resolved fresh
# each shell, so switching the default toolchain needs no change here.
if command -v rustc >/dev/null 2>&1; then
  fpath+=("$(rustc --print sysroot)/share/zsh/site-functions")
fi
