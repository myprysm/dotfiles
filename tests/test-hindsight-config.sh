#!/bin/bash
# Tests the coding-agent.json modify_ template (#127, #128, #129, #141): the
# restore credentials survive, hindsightPaths sets optInOnly and optInPaths, and
# the repo-owned keys are set. Renders the chezmoi source against dummy fixtures
# under a scratch HOME; reads nothing real.
#
#   ./tests/test-hindsight-config.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home"
TPL="$(cat "$REPO_ROOT/home/private_dot_hindsight/modify_private_coding-agent.json")"

pass=0; fail=0
out=""
render() { # render <live json> [hindsightPaths]; no second argument leaves the key out
  local data='{}'
  [ $# -ge 2 ] && data=$(jq -cn --arg p "$2" '{hindsightPaths: $p}')
  printf '%s' "$1" | HOME="$SB/home" chezmoi execute-template --source "$REPO_ROOT/home" \
    --override-data "$data" --with-stdin "$TPL"
}
is() { # is <label> <jq filter> <expected compact json>
  got=$(printf '%s' "$out" | jq -c "$2" 2>&1)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$3" "$got"; fi
}

echo "== restore body on stdin"
RESTORE='{"serverMode":"self-hosted","apiUrl":"http://127.0.0.1:9","apiToken":"dummy-not-a-secret","optInOnly":true}'
out=$(render "$RESTORE" '*')
is "serverMode kept" '.serverMode' '"self-hosted"'
is "apiUrl kept" '.apiUrl' '"http://127.0.0.1:9"'
is "apiToken kept" '.apiToken' '"dummy-not-a-secret"'
is "*: optInOnly removed" 'has("optInOnly")' 'false'
is "*: no optInPaths" 'has("optInPaths")' 'false'

echo "== repo-owned keys"
is "bankId" '.bankId' '"damien-main-memory"'
is "manageBankConfig" '.manageBankConfig' 'false'
is "pages: all five off" '.pages' '{"Component map":false,"Conventions and patterns":false,"Core concepts":false,"Initiatives and enhancements":false,"Key decisions and rationale":false}'
is "no customPages" 'has("customPages")' 'false'
is "retainTags" '.retainTags' '["project:{gitProject}"]'
is "retainMetadata" '.retainMetadata' '{"repo":"{gitProject}"}'
is "autoSeed" '.autoSeed' 'false'
is "gitIngest" '.gitIngest' '"none"'
is "codebaseSurvey" '.codebaseSurvey' 'false'
is "autoUpdate" '.autoUpdate' 'false'
is "autoInject: recall" '.autoInject' '"recall"'
is "no harnesses section" 'has("harnesses")' 'false'

echo "== hindsightPaths"
out=$(render "$RESTORE" '~/projects/a,/srv/b')
is "list: optInOnly true" '.optInOnly' 'true'
is "list: optInPaths, ~ kept as typed" '.optInPaths' '["~/projects/a","/srv/b"]'
out=$(render "$RESTORE" '  ~/projects/a , ,, /srv/b  ,')
is "spaces and blanks: trimmed, blanks dropped" '.optInPaths' '["~/projects/a","/srv/b"]'
out=$(render "$RESTORE" ' * ')
is "* with spaces: optInOnly removed" 'has("optInOnly")' 'false'
out=$(render '{"apiToken":"dummy-not-a-secret","optInPaths":["/old"]}' '*')
is "*: a stale optInPaths removed" 'has("optInPaths")' 'false'
for v in '' '  ' ' , ,'; do
  out=$(render "$RESTORE" "$v")
  is "empty [$v]: optInOnly true" '.optInOnly' 'true'
  is "empty [$v]: no optInPaths" 'has("optInPaths")' 'false'
done
out=$(render '{"apiToken":"dummy-not-a-secret","optInPaths":["/old"]}' '')
is "empty: a stale optInPaths removed" 'has("optInPaths")' 'false'
out=$(render "$RESTORE")
is "key absent: optInOnly true" '.optInOnly' 'true'
is "key absent: no optInPaths" 'has("optInPaths")' 'false'

echo "== a repo-owned key the live file changed is set again"
out=$(render '{"apiToken":"dummy-not-a-secret","autoUpdate":true,"bankId":"other","customPages":{"x":{}},"autoInject":"reflect"}')
is "autoUpdate reset" '.autoUpdate' 'false'
is "bankId reset" '.bankId' '"damien-main-memory"'
is "autoInject reset" '.autoInject' '"recall"'
is "customPages removed" 'has("customPages")' 'false'

echo "== empty stdin"
out=$(render "")
is "renders valid JSON" 'type' '"object"'
is "no credential key" '[has("serverMode"), has("apiUrl"), has("apiToken")]' '[false,false,false]'
is "repo-owned key still set" '.bankId' '"damien-main-memory"'

echo "== hindsightPaths prompt in chezmoi init"
init() { # init <config file>; the answers come on stdin, one per line
  HOME="$SB/home" chezmoi init --no-tty --source "$REPO_ROOT" --config "$1" --config-path "$1" >/dev/null 2>&1
}
check() { # check <label> <command...>
  if "${@:2}"; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n' "$1"; fi
}
CFG="$SB/hindsight.toml"
# The blank line after "hindsight" ends the bundle multichoice; the next one is the empty answer.
printf 'n\ne@x\nhttps://b\n/s\nhindsight\n\n\n' | init "$CFG"
check "empty answer stored" grep -qx '    hindsightPaths = ""' "$CFG"
# No answers on stdin: any prompt hits EOF and init fails.
check "second init does not ask again" init "$CFG" </dev/null
check "empty answer still stored" grep -qx '    hindsightPaths = ""' "$CFG"
CFG="$SB/no-hindsight.toml"
printf 'n\ne@x\nhttps://b\n/s\ngo\n\n' | init "$CFG"
check "no hindsight bundle: not asked" grep -qx '    bundleList = \["go"\]' "$CFG"
check "no hindsight bundle: no key" test -z "$(grep hindsightPaths "$CFG")"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
