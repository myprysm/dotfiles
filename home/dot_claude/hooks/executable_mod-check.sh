#!/usr/bin/env bash
# Mod check (#98): reports each installed plugin that ships a mod. A SessionStart
# hook, also run by hand. Prints only JSON: SessionStart adds plain stdout to the
# model's context, while systemMessage reaches the operator only. Claude Code
# still honours valid JSON on exit 1, so a finding exits 1 and is still shown.
set -u

file="$HOME/.claude/plugins/installed_plugins.json"
lines=()

cannot_run() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "mod check could not run: $1" '{systemMessage:$m}'
  else
    printf '{"systemMessage":"mod check could not run: %s"}\n' "$1"
  fi
  exit 1
}

# The hooks: and calls: line format was never seen on a real mod (#98, item 11).
refused() { # refused <plugin dir>
  command -v claude >/dev/null 2>&1 || return 0
  local out line w items=()
  out=$(claude plugin validate "$1" 2>&1)
  while IFS= read -r line; do
    case "$line" in
      *hooks:*) for w in tool.call classic.PreToolUse tool.check; do
                  [[ $line == *"$w"* ]] && items+=("$w"); done ;;
      *calls:*) for w in fs.read process.run; do
                  [[ $line == *"$w"* ]] && items+=("$w"); done ;;
    esac
  done <<< "$out"
  [ ${#items[@]} -gt 0 ] && printf ' — refused: %s' "${items[*]}"
}

check() { # check <id> <version> <plugin dir>
  local h="$3/hooks/hooks.json" has
  [ -d "$3" ] || cannot_run "$3 not found"
  [ -f "$h" ] || return 0
  has=$(jq -r 'has("modules")' "$h" 2>/dev/null) || cannot_run "$h is not valid JSON"
  [ "$has" = true ] || return 0
  lines+=("$1 $2: ships a mod — run mod admission (#91)$(refused "$3")")
}

command -v jq >/dev/null 2>&1 || cannot_run "jq not found"
[ -f "$file" ] || cannot_run "$file not found"
[ -r "$file" ] || cannot_run "$file not readable"
version=$(jq -r '.version' "$file" 2>/dev/null) || cannot_run "$file is not valid JSON"
[ "$version" = 2 ] || cannot_run "$file has unknown format (version $version)"
entries=$(jq -r '.plugins | to_entries[] | .key as $id | .value[] |
  if (.installPath | type) == "string" then [$id, (.version // "unknown"), .installPath] | @tsv
  else error end' "$file" 2>/dev/null) || cannot_run "$file has unknown format"

while IFS=$'\t' read -r id ver dir; do
  [ -n "$id" ] && check "$id" "$ver" "$dir"
done <<< "$entries"

for d in "$HOME"/.claude/mods/plugins/*/; do
  [ -d "$d" ] || continue
  d=${d%/}
  ver=$(jq -r '.version // "unknown"' "$d/.claude-plugin/plugin.json" 2>/dev/null) || ver=unknown
  check "${d##*/}@dotfiles" "$ver" "$d"
done

[ ${#lines[@]} -eq 0 ] && exit 0
jq -cn --arg m "$(printf '%s\n' "${lines[@]}")" '{systemMessage:$m}'
exit 1
