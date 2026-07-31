# rust bundle only (shipped via .chezmoiignore). rustup is installed with
# --no-modify-path because this repo owns PATH — which only works if the repo
# then actually adds it. Without this line the toolchain installs and the
# shell cannot see it.
export PATH="$HOME/.cargo/bin:$PATH"
