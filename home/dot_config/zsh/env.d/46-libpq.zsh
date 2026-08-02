# work bundle only (shipped via .chezmoiignore). libpq is keg-only, exactly like
# mysql-client, so brew links none of its 34 binaries into the prefix bin and
# PATH must name the keg. This is where psql, pg_dump, pg_restore and pg_isready
# come from — the pre-migration .zshrc had this entry and dropping it would have
# taken the whole Postgres client set off PATH.
export PATH="$HOMEBREW_PREFIX/opt/libpq/bin:$PATH"
