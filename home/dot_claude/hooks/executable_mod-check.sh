#!/usr/bin/env bash
# Mod check (#98): reports each installed plugin that ships a mod. A SessionStart
# hook, also run by hand. Prints only JSON: SessionStart adds plain stdout to the
# model's context, while systemMessage reaches the operator only. Claude Code
# still honours valid JSON on exit 1, so a finding exits 1 and is still shown.
set -u

file="$HOME/.claude/plugins/installed_plugins.json"
lines=()

not_run() { lines+=("mod check could not run: $1"); }

# The hooks: and calls: line format was never seen on a real mod (#98, item 11).
admission() { # admission <plugin dir>
  local out line w seen= items=()
  command -v claude >/dev/null 2>&1 || { printf ' — admission could not run: claude not found'; return; }
  out=$(claude plugin validate "$1" 2>&1) || { printf ' — admission could not run: claude plugin validate failed'; return; }
  while IFS= read -r line; do
    case "$line" in
      *hooks:*) seen=1; for w in tool.call classic.PreToolUse tool.check; do
                  [[ $line == *"$w"* ]] && items+=("$w"); done ;;
      *calls:*) seen=1; for w in fs.read process.run; do
                  [[ $line == *"$w"* ]] && items+=("$w"); done ;;
    esac
  done <<< "$out"
  [ -n "$seen" ] || { printf ' — admission could not run: no hooks: or calls: line from claude plugin validate'; return; }
  [ ${#items[@]} -gt 0 ] && printf ' — refused: %s' "${items[*]}"
}

check() { # check <id> <version> <plugin dir>
  local h="$3/hooks/hooks.json" has
  [ -d "$3" ] || { not_run "$3 not found"; return; }
  [ -f "$h" ] || return 0
  has=$(jq -r 'if type == "object" then has("modules") else error end' "$h" 2>/dev/null)
  case "$has" in
    true) ;;
    false) return 0 ;;
    *) not_run "$h is not a JSON object"; return ;;
  esac
  lines+=("$1 $2: ships a mod — run mod admission (#91)$(admission "$3")")
}

scan_installed() {
  local version entries id ver dir
  [ -f "$file" ] || { not_run "$file not found"; return; }
  [ -r "$file" ] || { not_run "$file not readable"; return; }
  version=$(jq -r '.version' "$file" 2>/dev/null) || { not_run "$file is not valid JSON"; return; }
  [ "$version" = 2 ] || { not_run "$file has unknown format (version $version)"; return; }
  entries=$(jq -r '.plugins | if type != "object" then error else to_entries[] end |
    .key as $id | .value[] |
    if (.installPath | type) == "string" then [$id, (.version // "unknown"), .installPath] | @tsv
    else error end' "$file" 2>/dev/null) || { not_run "$file has unknown format"; return; }
  while IFS=$'\t' read -r id ver dir; do
    [ -n "$id" ] && check "$id" "$ver" "$dir"
  done <<< "$entries"
}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"mod check could not run: jq not found"}\n'
  exit 1
fi
scan_installed

for d in "$HOME"/.claude/mods/plugins/*/; do
  [ -d "$d" ] || continue
  d=${d%/}
  ver=$(jq -r '.version // "unknown"' "$d/.claude-plugin/plugin.json" 2>/dev/null) || ver=unknown
  check "${d##*/}@dotfiles" "$ver" "$d"
done

[ ${#lines[@]} -eq 0 ] && exit 0
jq -cn --arg m "$(printf '%s\n' "${lines[@]}")" '{systemMessage:$m}'
exit 1
