# `=word` expands to the path of command `word`, so `echo =====` fails with
# "==== not found". Agents print `=====` banners; their Bash tool inherits these
# options through its shell snapshot.
setopt NO_EQUALS
