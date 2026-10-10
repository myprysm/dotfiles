#!/bin/bash
# Tests the coding-agent.json modify_ template (#127, #128, #129): the restore
# credentials survive, optInOnly goes, and the repo-owned keys are set. Renders
# the chezmoi source against dummy fixtures under a scratch HOME; reads nothing
# real.
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
render() { # render <live json>
  printf '%s' "$1" | HOME="$SB/home" chezmoi execute-template --source "$REPO_ROOT/home" \
    --with-stdin "$TPL"
}
is() { # is <label> <jq filter> <expected compact json>
  got=$(printf '%s' "$out" | jq -c "$2" 2>&1)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$3" "$got"; fi
}

echo "== restore body on stdin"
out=$(render '{"serverMode":"self-hosted","apiUrl":"http://127.0.0.1:9","apiToken":"dummy-not-a-secret","optInOnly":true}')
is "serverMode kept" '.serverMode' '"self-hosted"'
is "apiUrl kept" '.apiUrl' '"http://127.0.0.1:9"'
is "apiToken kept" '.apiToken' '"dummy-not-a-secret"'
is "optInOnly removed" 'has("optInOnly")' 'false'

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
is "no harnesses section" 'has("harnesses")' 'false'

echo "== a repo-owned key the live file changed is set again"
out=$(render '{"apiToken":"dummy-not-a-secret","autoUpdate":true,"bankId":"other","customPages":{"x":{}}}')
is "autoUpdate reset" '.autoUpdate' 'false'
is "bankId reset" '.bankId' '"damien-main-memory"'
is "customPages removed" 'has("customPages")' 'false'

echo "== empty stdin"
out=$(render "")
is "renders valid JSON" 'type' '"object"'
is "no credential key" '[has("serverMode"), has("apiUrl"), has("apiToken")]' '[false,false,false]'
is "repo-owned key still set" '.bankId' '"damien-main-memory"'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
