# darwin-only (shipped via .chezmoiignore). Apple clang needs libc++ named
# explicitly for C++ sources; the flag is wrong on Linux, where libstdc++ is the
# default, so this is a per-OS file rather than a guard.
export CXXFLAGS="-stdlib=libc++"
