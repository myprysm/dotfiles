#!/bin/bash
# Tests the codex config modify_ template (#84, #96): which live keys survive an
# apply, and that the secret-read hook is declared with a trust hash codex
# accepts. Renders the chezmoi source against fixtures under a scratch HOME;
# reads nothing real.
#
#   ./tests/test-codex-config.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home/.codex"
TPL="$(cat "$REPO_ROOT/home/dot_codex/modify_private_config.toml")"
CMD="bash $SB/home/.claude/hooks/block-secret-reads.sh --codex"
KEY="$SB/home/.codex/config.toml:pre_tool_use:0:0"
ORCA_KEY="$SB/home/.codex/hooks.json:pre_tool_use:0:0"

pass=0; fail=0
out=""
render() { # render <live toml>
  printf '%s' "$1" | HOME="$SB/home" chezmoi execute-template --source "$REPO_ROOT/home" \
    --with-stdin "$TPL"
}
q() { # q <python expression over the parsed config `c`>
  printf '%s' "$out" | python3 -c 'import sys,tomllib,json; c=tomllib.loads(sys.stdin.read()); print(json.dumps(eval(sys.argv[1]), sort_keys=True))' "$1" 2>&1
}
is() { # is <label> <python expression> <expected json>
  got=$(q "$2")
  if [ "$got" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$3" "$got"; fi
}

# The formula codex 0.160 uses (hooks/src/engine/discovery.rs hook_hash): the
# normalized handler, its matcher and its event, as sorted compact JSON.
want_hash=$(python3 -c 'import sys,json,hashlib
ident={"event_name":"pre_tool_use","matcher":"Bash","hooks":[{"async":False,"command":sys.argv[1],"timeout":600,"type":"command"}]}
print(json.dumps("sha256:"+hashlib.sha256(json.dumps(ident,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()))' "$CMD")

echo "== empty stdin (fresh machine)"
out=$(render "")
is "secret-read hook declared" 'c["hooks"]["PreToolUse"]' "[{\"hooks\": [{\"command\": \"$CMD\", \"type\": \"command\"}], \"matcher\": \"Bash\"}]"
is "trust hash pre-seeded" "c['hooks']['state']['$KEY']['trusted_hash']" "$want_hash"
is "owned key set" 'c["approval_policy"]' '"on-request"'

echo "== live runtime state"
live=$(cat <<EOF
model = "other-model"

[projects."/x"]
trust_level = "trusted"

[[hooks.PreToolUse]]
matcher = "Edit"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "stale"

[hooks.state."$ORCA_KEY"]
trusted_hash = "sha256:orca"

[hooks.state."$KEY"]
enabled = false
trusted_hash = "sha256:stale"
EOF
)
out=$(render "$live")
is "PreToolUse replaced whole" 'len(c["hooks"]["PreToolUse"])' '1'
is "repo hook is the only group" 'c["hooks"]["PreToolUse"][0]["hooks"][0]["command"]' "\"$CMD\""
is "orca trust kept" "c['hooks']['state']['$ORCA_KEY']['trusted_hash']" '"sha256:orca"'
is "stale trust hash replaced" "c['hooks']['state']['$KEY']['trusted_hash']" "$want_hash"
is "operator disable kept" "c['hooks']['state']['$KEY']['enabled']" 'false'
is "projects kept" 'c["projects"]["/x"]["trust_level"]' '"trusted"'
is "model passes through" 'c["model"]' '"other-model"'

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
