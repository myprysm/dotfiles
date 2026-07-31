# ops bundle only (shipped via .chezmoiignore). helm@3 stays the
# active binary until v4 chart/plugin compatibility is confirmed.
# Retiring the pin = delete this file + drop helm@3 from packages.yaml.
export PATH="$HOMEBREW_PREFIX/opt/helm@3/bin:$PATH"
