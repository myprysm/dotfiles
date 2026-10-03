# darwin + work bundle (shipped via .chezmoiignore); example of a per-OS
# concern as a plain file, no runtime $OSTYPE guard.
# All four variables, not two: the Mac exported PKG_CONFIG_PATH and
# CMAKE_PREFIX_PATH as well, and without them a build finds the headers but not
# the pkg-config or cmake metadata.
export LDFLAGS="-L$HOMEBREW_PREFIX/opt/openblas/lib"
export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/openblas/include"
export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/opt/openblas/lib/pkgconfig"
export CMAKE_PREFIX_PATH="$HOMEBREW_PREFIX/opt/openblas"
