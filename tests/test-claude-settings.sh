#!/bin/bash
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home/.claude" "$SB/src/.chezmoitemplates"
TPL="$(cat "$REPO_ROOT/home/dot_claude/modify_private_settings.json")"
REPO_HOOK="bash $SB/home/.claude/hooks/block-secret-reads.sh"
MOD_CHECK="bash $SB/home/.claude/hooks/mod-check.sh"

BASE="$REPO_ROOT/home/.chezmoitemplates/claude-settings.json"
base() { jq -c "$1" "$BASE"; }
cp "$BASE" "$SB/src/.chezmoitemplates/"
mkdir -p "$SB/retired/.chezmoitemplates"
jq 'del(.tui)' "$BASE" > "$SB/retired/.chezmoitemplates/claude-settings.json"

pass=0; fail=0
out=""
render() {
  printf '%s' "$2" | HOME="$SB/home" chezmoi execute-template --source "$1" \
    --override-data '{"secretsDir":"/nonexistent"}' --with-stdin "$TPL"
}
is() {
  got=$(printf '%s' "$out" | jq -c "$2" 2>&1)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$3" "$got"; fi
}

echo "== empty stdin (fresh machine)"
out=$(render "$SB/src" "")
is "renders valid JSON" 'type' '"object"'
is "repo hook installed" "[.hooks.PreToolUse[].hooks[].command]" "[\"$REPO_HOOK\"]"
is "mod check installed" "[.hooks.SessionStart[].hooks[].command]" "[\"$MOD_CHECK\"]"
is "model set from base" '.model' "$(base .model)"

echo "== foreign keys and runtime keys"
out=$(render "$SB/src" '{"autoMode":{"x":1},"someTool":true,"model":"sonnet","tui":"old"}')
is "foreign key kept" '.autoMode' '{"x":1}'
is "unknown key kept" '.someTool' 'true'
is "model passes through" '.model' '"sonnet"'
is "effortLevel set when missing" '.effortLevel' "$(base .effortLevel)"
is "owned key replaced" '.tui' "$(base .tui)"

echo "== retired owned key"
out=$(render "$SB/retired" '{"tui":"fullscreen","other":1}')
is "retired key deleted" 'has("tui")' 'false'
is "other key kept" '.other' '1'

echo "== hooks"
live=$(jq -n --arg old "bash $SB/home/.claude/hooks/retired.sh" --arg repo "$REPO_HOOK" --arg mod "$MOD_CHECK" '{hooks:{
  PreToolUse:[
    {matcher:"*",hooks:[{type:"command",command:"orca-hook"}]},
    {matcher:"Bash",hooks:[{type:"command",command:$old}]},
    {matcher:"Bash",hooks:[{type:"command",command:$repo}]},
    {matcher:"Edit",hooks:[{type:"command",command:"bash ~/.claude/hooks/tilde.sh"}]},
    {matcher:"Edit",hooks:[{type:"command",command:"bash $HOME/.claude/hooks/home.sh"}]},
    {matcher:"Write",hooks:[{type:"command",command:"orca-shared"},{type:"command",command:$old}]}],
  SessionStart:[{hooks:[{type:"command",command:"orca-hook"}]},{hooks:[{type:"command",command:$mod}]}],
  Notification:[{hooks:[{type:"command",command:"orca-hook"}]}],
  Stop:[{hooks:[{type:"command",command:$old}]}]}}')
out=$(render "$SB/src" "$live")
is "foreign hook kept" '[.hooks.PreToolUse[].hooks[].command | select(. == "orca-hook")] | length' '1'
is "foreign-only event kept" '.hooks.Notification[0].hooks[0].command' '"orca-hook"'
is "foreign hook kept next to the mod check" '[.hooks.SessionStart[].hooks[].command]' "[\"orca-hook\",\"$MOD_CHECK\"]"
is "retired repo hook removed" "[.. | strings | select(test(\"retired.sh\"))] | length" '0'
is "repo hook not duplicated" "[.hooks.PreToolUse[].hooks[].command | select(. == \"$REPO_HOOK\")] | length" '1'
is "repo hook takes the base matcher" "[.hooks.PreToolUse[] | select(.hooks[0].command == \"$REPO_HOOK\") | .matcher]" "[$(base '.hooks.PreToolUse[0].matcher')]"
is "~/ and \$HOME/ forms removed" '[.. | strings | select(test("tilde.sh|home.sh"))] | length' '0'
is "shared entry keeps its foreign command" '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[].command]' '["orca-shared"]'
is "event left empty is dropped" '.hooks | has("Stop")' 'false'

echo "== settings.local.json overlay"
cat > "$SB/home/.claude/settings.local.json" <<'EOF'
{"env":{"LOCAL_VAR":"1","CLAUDE_CODE_ENABLE_TELEMETRY":"1"},
 "permissions":{"allow":["Skill(playwright-cli)","Bash(local:*)"]},
 "tui":"default","theme":"dark","autoMode":{"local":1},"skillOverrides":{"x":"off"}}
EOF
out=$(render "$SB/src" '{"env":{"STALE":"1"},"autoMode":{"live":1}}')
is "overlay-only key not written" 'has("theme")' 'false'
is "overlay reaches an owned key the base lacks" '.skillOverrides' '{"x":"off"}'
is "overlay cannot replace a foreign key" '.autoMode' '{"live":1}'
is "objects merge deeply" ".env | has(\"LOCAL_VAR\") and has($(base '.env | keys[0]'))" 'true'
is "overlay wins for scalars" '.env.CLAUDE_CODE_ENABLE_TELEMETRY' '"1"'
is "overlay wins for top-level scalar" '.tui' '"default"'
is "lists concatenated" '.permissions.allow | index("Bash(local:*)") != null' 'true'
is "lists deduplicated" '[.permissions.allow[] | select(. == "Skill(playwright-cli)")] | length' '1'
is "owned key replaced whole" '.env | has("STALE")' 'false'
rm "$SB/home/.claude/settings.local.json"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
