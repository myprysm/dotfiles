# `workon` stays one command away; the auto-activation of a `main` env in every
# shell is gone. Retired entirely once the uv migration lands —
# deleting this file plus the formula is the whole retirement.
export VIRTUAL_ENV_DISABLE_PROMPT=1
command -v virtualenvwrapper.sh >/dev/null && source "$(command -v virtualenvwrapper.sh)"
