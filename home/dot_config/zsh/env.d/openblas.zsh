# PROTOTYPE — darwin-only (shipped via .chezmoiignore); example of a per-OS
# concern as a plain file, no runtime $OSTYPE guard (#4 §3).
export LDFLAGS="-L$HOMEBREW_PREFIX/opt/openblas/lib"
export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/openblas/include"
