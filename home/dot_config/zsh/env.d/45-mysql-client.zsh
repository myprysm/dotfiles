# work bundle only (shipped via .chezmoiignore). mysql-client is keg-only, so
# brew never links mysql/mysqldump into the prefix bin and PATH must name it.
export PATH="$HOMEBREW_PREFIX/opt/mysql-client/bin:$PATH"
