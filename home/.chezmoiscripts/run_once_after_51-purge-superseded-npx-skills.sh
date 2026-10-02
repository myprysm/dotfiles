#!/bin/bash
# Purge the CLI-installed skills that marketplace plugins now supersede, on
# every machine that still carries them. Dropping a name from the tracked
# lockfile stops 50-claude-skills from restoring it, but removes nothing
# already on disk, and chezmoi leaves a target standing when its source entry
# goes away — so without this a migrated machine keeps a second, unmanaged copy
# of every skill the plugin ships, and the standalone hooks keep firing
# alongside the plugin's.
#
# Keyed on the lockfile's `source` field rather than a name list: the CLI
# records who each skill came from, so a repo that renames or adds a skill is
# still matched, and this cannot delete a skill installed from anywhere else.
#
# DRY=1 prints the plan and touches nothing.
set -eu

DRY="${DRY:-0}"
LOCK="$HOME/.agents/.skill-lock.json"
SUPERSEDED='mattpocock/skills JuliusBrussee/caveman'

command -v python3 >/dev/null 2>&1 || { echo "python3 not found — skipping skill purge" >&2; exit 0; }
[ -f "$LOCK" ] || exit 0

names=$(python3 -c "
import json, sys
srcs = set(sys.argv[1].split())
with open(sys.argv[2]) as f:
    lock = json.load(f)
print(' '.join(k for k, v in lock.get('skills', {}).items() if v.get('source') in srcs))
" "$SUPERSEDED" "$LOCK")

# Agent directories are dotdirs in \$HOME, so they are globbed rather than
# found: a walk of \$HOME on macOS is both slow and enough to raise the TCC
# prompts for Desktop and Documents. The .[!.]* form is what keeps . and ..
# out of the glob.
purge_links() {
  skill="$1"
  for dir in "$HOME"/.[!.]*/skills "$HOME"/.config/*/skills; do
    link="$dir/$skill"
    [ -L "$link" ] || continue
    # A same-named symlink pointing somewhere else belongs to another
    # installer; only the ones aimed at the CLI's own store are ours to remove.
    case "$(readlink "$link")" in
      *agents/skills/"$skill")
        echo "  unlink $link"
        [ "$DRY" = 1 ] || rm -f "$link"
        ;;
    esac
  done
}

for skill in $names; do
  purge_links "$skill"
  payload="$HOME/.agents/skills/$skill"
  if [ -d "$payload" ]; then
    echo "  remove $payload"
    [ "$DRY" = 1 ] || rm -rf "$payload"
  fi
done

# Lockfile last: a run interrupted before this point still finds the same names
# on the next apply.
if [ -n "$names" ]; then
  echo "  prune lockfile: $names"
  [ "$DRY" = 1 ] || python3 -c "
import json, sys
srcs = set(sys.argv[1].split())
path = sys.argv[2]
with open(path) as f:
    lock = json.load(f)
lock['skills'] = {k: v for k, v in lock.get('skills', {}).items() if v.get('source') not in srcs}
with open(path, 'w') as f:
    f.write(json.dumps(lock, indent=2) + '\n')
" "$SUPERSEDED" "$LOCK"
fi

# The standalone caveman hook install, which the plugin's own manifest makes
# redundant: identical files, registered twice, so activation fired twice a
# session. block-secret-reads.sh is this repo's and is not listed here.
for hook in caveman-activate.js caveman-mode-tracker.js caveman-config.js \
            cavecrew-model-overrides.js caveman-stats.js caveman-statusline.sh \
            caveman-statusline.ps1 package.json; do
  path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/$hook"
  [ -e "$path" ] || continue
  echo "  remove $path"
  [ "$DRY" = 1 ] || rm -f "$path"
done

# enabledPlugins declares the plugins, but whether that alone installs one on a
# machine that has never seen it is unverified — these calls are idempotent and
# make the outcome not depend on the answer.
if command -v claude >/dev/null 2>&1; then
  for plugin in mattpocock-skills@claude-plugins-official caveman@caveman; do
    [ "$DRY" = 1 ] && { echo "  claude plugin install $plugin"; continue; }
    claude plugin install "$plugin" >/dev/null 2>&1 \
      || echo "  ! 'claude plugin install $plugin' failed — install it by hand" >&2
  done
fi
