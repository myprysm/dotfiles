#!/bin/bash
# Tests scripts/deps-audit.sh through its stdout lines and exit code. The repo is
# a fixture tree with the known pin shapes, and gh is a stub that serves the
# Dashboard, the open PRs and the branches; no GitHub API is contacted.
#
#   ./tests/test-deps-audit.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin"
JQ="$(command -v jq)"
GIT="$(command -v git)"

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-46s %s\n' "$1" "${3%%$'\n'*}"
          else fail=$((fail+1)); printf '  FAIL %-46s\n         want [%s]\n         got  [%s]\n' "$1" "$2" "$3"; fi }

# PATH is the stub dir alone: gh, jq and git all sit beside other tools in a real
# bin dir, so a wider PATH could not prove a missing binary is refused.
cat > "$SB/bin/jq" <<EOF
#!$BASH
if [ -e "$SB/jq-fail-args" ] && [ "\$*" = "\$(<"$SB/jq-fail-args")" ]; then
  [ -e "$SB/jq-fail-out" ] && printf "%s" "\$(<"$SB/jq-fail-out")"; echo "jq: error" >&2; exit 5
fi
exec "$JQ" "\$@"
EOF
chmod +x "$SB/bin/jq"
ln -s "$GIT" "$SB/bin/git"
cat > "$SB/bin/gh" <<EOF
#!$BASH
for a in "\$@"; do case "\$a" in repos/*) ep=\${a%%\?*}; ep=\${ep##*/} ;; esac; done
[ -e "$SB/fail-\$ep" ] && { echo "gh: HTTP 502" >&2; exit 1; }
case "\$*" in
  "api repos/{owner}/{repo}/issues?state=open&per_page=100") printf "%s" "\$(<"$SB/issues.json")" ;;
  "api --paginate --slurp repos/{owner}/{repo}/pulls?state=open&per_page=100") printf "%s" "\$(<"$SB/pulls.json")" ;;
  "api --paginate --slurp repos/{owner}/{repo}/branches?per_page=100") printf "%s" "\$(<"$SB/branches.json")" ;;
  *) echo "gh stub: unexpected \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$SB/bin/gh"

FX="$SB/repo"
fixture() { # fixture <path> <content>
  mkdir -p "$(dirname "$FX/$1")"; printf '%s\n' "$2" > "$FX/$1"
  "$GIT" -C "$FX" add -- "$1"
}
"$GIT" init -q "$FX"

run() {
  (cd "$FX/home" && PATH="$SB/bin" "$BASH" "$REPO_ROOT/scripts/deps-audit.sh") > "$SB/out" 2> "$SB/err"
  rc=$?; out=$(cat "$SB/out")
}

dashboard() { "$JQ" -n --arg body "$1" '[{number: 150, title: "Dependency Dashboard", author_association: "MEMBER", body: $body}]' > "$SB/issues.json"; }
pulls() { printf '%s\n' "${1:-[[]]}" > "$SB/pulls.json"; }
branches() { printf '%s\n' "${1:-[[]]}" > "$SB/branches.json"; }

# Shape of PackageFiles.getDashboardMarkdown in Renovate's
# lib/workers/repository/package-files.ts (tag 44.257.9): <details> per manager
# with a <blockquote>, then per package file without one, each dep as
# " - `<depName> <version>`".
DETECTED='## Detected Dependencies
'
detected() { # detected <manager> <file> <deps...>
  local m=$1 f=$2; shift 2
  printf '<details><summary>%s (1)</summary>\n<blockquote>\n\n<details><summary>%s (%s)</summary>\n\n' "$m" "$f" "$#"
  for d in "$@"; do printf ' - `%s`\n' "$d"; done
  printf '\n</details>\n\n</blockquote>\n</details>\n\n'
}

fixture docs/agents/dependencies.md '# Dependency catalogue

## Accept-list

Line format: `accept <file> <pin> <reason>`.

```text
```

## Command shapes
'

echo "== every pin is tracked"
fixture home/.chezmoidata/packages.yaml '      uvTools:
        - package: "ansible==13.8.0"     # #17 pin'
dashboard "$DETECTED
$(detected regex home/.chezmoidata/packages.yaml 'ansible 13.8.0')"
pulls; branches
run
check "exits zero" "0" "$rc"
check "prints nothing" "" "$out"

echo
echo "== each known pin shape, tracked and untracked"
fixture home/.chezmoidata/packages.yaml '  bundles:
    ops:
      # helm@3 and "x==1.0" in a comment are prose, not pins.
      brews: [python@3.13, kubernetes-cli, helm, helm@3, talosctl]
      uvTools:
        - package: "ansible==13.8.0"     # #17 pin
          python: "3.13"
          with: [kubernetes, "boto3==1.28.53", "pydo==0.3.0"]
        - package: "mkdocs==1.6.1"
          python: "3.13"
    java:
      sdkman: [25-tem, 25-graal]    # SDKMAN owns JDKs
    go:
      tools:
        - golang.org/x/tools/gopls@latest'
fixture home/.chezmoidata/secret-guard.yaml '# set `version` to `vX.Y.Z`
secretGuard:
  version: "v0.7.2"
  sha256:
    linux-amd64: "4f8164b2e728fb56ccc4494efcc8991725db5554c1a778e269f83c754363bb72"'
fixture home/dot_agents/dot_skill-lock.json '{
  "version": 3,
  "skills": {
    "find-skills": {"source": "vercel-labs/skills", "skillFolderHash": "3013fdeb8a11b10b1eb795ec3ae8bfca38f7c26d"},
    "orca-cli": {
      "source": "stablyai/orca",
      "skillFolderHash": "572f7952ac451a30a9c2451b472a639b125ee584"
    }
  }
}'
fixture home/dot_zprofile '# expands it (nvm, helm@3, openblas).
export PATH'
PKG=home/.chezmoidata/packages.yaml
SGY=home/.chezmoidata/secret-guard.yaml
LCK=home/dot_agents/dot_skill-lock.json
dashboard "$DETECTED
$(detected regex $PKG 'ansible 13.8.0' 'mkdocs 1.6.1' 'python@3.13 3.13' 'helm@3 3' 'python 3.13' \
  'boto3 1.28.53' 'pydo 0.3.0' '25-tem 25' '25-graal 25')
$(detected regex $SGY 'secretGuard.version v0.7.2')
$(detected regex $LCK 'skills.find-skills.skillFolderHash 3013fde' 'skills.orca-cli.skillFolderHash 572f795')"
run
check "all tracked: exits zero" "0" "$rc"
check "all tracked: prints nothing" "" "$out"

dashboard "$DETECTED
$(detected regex $PKG 'ansible 13.8.0' 'mkdocs 1.6.1')"
run
check "untracked: exits 1" "1" "$rc"
check "untracked: one GAP per pin, by file and pin" "GAP untracked $PKG 25-graal
GAP untracked $PKG 25-tem
GAP untracked $PKG boto3
GAP untracked $PKG helm@3
GAP untracked $PKG pydo
GAP untracked $PKG python
GAP untracked $PKG python@3.13
GAP untracked $SGY secretGuard.version
GAP untracked $LCK skills.find-skills.skillFolderHash
GAP untracked $LCK skills.orca-cli.skillFolderHash" "$out"

echo
echo "== an accepted pin prints as INFO, in the catalogue's line format"
fixture docs/agents/dependencies.md '# Dependency catalogue

An accept line in prose: accept home/.chezmoidata/packages.yaml helm@3 not at the line start (#1)

accept home/.chezmoidata/packages.yaml python before the section (#1)

## Accept-list

Line format, one entry on each line, at the start of the line: `accept <file> <pin> <reason>`.

```text
accept home/.chezmoidata/packages.yaml boto3 mirrors the work playbook, pairing P2 (#172)
accept home/.chezmoidata/packages.yaml pydo mirrors the work playbook, pairing P2 (#172)
accept home/.chezmoidata/secret-guard.yaml secretGuard.version our own release, its release steps move it (#172)
accept home/.chezmoidata/packages.yaml mkdocs tracked anyway, so no INFO (#1)
accept home/dot_zprofile 25-tem the right pin in the wrong file (#1)
```

## Command shapes

accept home/.chezmoidata/packages.yaml 25-graal after the section (#1)
'
run
check "accepted: still exits 1 for the other gaps" "1" "$rc"
check "accepted: INFO for each accepted pin, GAP for the rest" "GAP untracked $PKG 25-graal
GAP untracked $PKG 25-tem
GAP untracked $PKG helm@3
GAP untracked $PKG python
GAP untracked $PKG python@3.13
GAP untracked $LCK skills.find-skills.skillFolderHash
GAP untracked $LCK skills.orca-cli.skillFolderHash
INFO accepted $PKG boto3 mirrors the work playbook, pairing P2 (#172)
INFO accepted $PKG pydo mirrors the work playbook, pairing P2 (#172)
INFO accepted $SGY secretGuard.version our own release, its release steps move it (#172)" "$out"

TRACKED="$DETECTED
$(detected regex $PKG 'ansible 13.8.0' 'mkdocs 1.6.1' 'python@3.13 3.13' 'helm@3 3' 'python 3.13' '25-tem 25' '25-graal 25')
$(detected regex $LCK 'skills.find-skills.skillFolderHash 3013fde' 'skills.orca-cli.skillFolderHash 572f795')"
INFOS="INFO accepted $PKG boto3 mirrors the work playbook, pairing P2 (#172)
INFO accepted $PKG pydo mirrors the work playbook, pairing P2 (#172)
INFO accepted $SGY secretGuard.version our own release, its release steps move it (#172)"
dashboard "$TRACKED"
run
check "only accepted gaps: exits zero" "0" "$rc"
check "only accepted gaps: the INFO lines" "$INFOS" "$out"

echo
echo "== the Dashboard sections of a broken Renovate run"
# Shapes of ensureDependencyDashboard, getBranchesListMd and getListItem in
# Renovate's lib/workers/repository/dependency-dashboard.ts, and of
# getDepWarningsDashboard in errors-warnings.ts (tag 44.257.9).
section_case() { # section_case <name> <dashboard text> <want lines>
  dashboard "This issue lists Renovate updates and detected dependencies.

$2
## Vulnerabilities

Renovate has not found any CVEs on [osv.dev](https://osv.dev).

$TRACKED"
  run
  check "$1: exits 1" "1" "$rc"
  check "$1: the GAP lines" "$3
$INFOS" "$out"
}
section_case "config migration with a PR" '## Config Migration Needed

<!-- config-migration-pr-info --> See Config Migration PR: #161.
' "GAP config-migration See Config Migration PR: #161."
section_case "config migration blocked" '## Config Migration Needed (Blocked)

<!-- config-migration-pr-info --> The Config Migration branch exists but has been modified by another user. Renovate will not push to this branch unless it is first deleted.

 See Config Migration PR: #161.
' "GAP config-migration The Config Migration branch exists but has been modified by another user. Renovate will not push to this branch unless it is first deleted. See Config Migration PR: #161."
section_case "config migration without a PR" '## Config Migration Needed

 - [ ] <!-- create-config-migration-pr --> Select this checkbox to let Renovate create an automated Config Migration PR.
' "GAP config-migration Select this checkbox to let Renovate create an automated Config Migration PR."
section_case "repository problems" "## Repository Problems

Renovate tried to run on this repository, but found these problems.

 - WARN: Package lookup failures
 - WARN: Error updating branch:$(printf '\a') update failure
" "GAP problem WARN: Package lookup failures
GAP problem WARN: Error updating branch: update failure"
section_case "awaiting schedule" "## Awaiting Schedule

The following updates are awaiting their schedule. To get an update now, click on a checkbox below.

 - [ ] <!-- unschedule-branch=renovate/a -->chore(packages): update a
 - [ ] <!-- unschedule-branch=renovate/b -->chore(packages): update b (\`b1\`, \`b2\`)
 - [ ] <!-- create-all-awaiting-schedule-prs -->🔐 **Create all awaiting schedule PRs at once** 🔐
" "GAP awaiting-schedule renovate/a chore(packages): update a
GAP awaiting-schedule renovate/b chore(packages): update b (\`b1\`, \`b2\`)"
section_case "rate-limited" "## Rate-Limited

The following updates are currently rate-limited. To force their creation now, click on a checkbox below.

### Skills

 - [ ] <!-- unlimit-branch=renovate/c -->chore(skills): update c
" "GAP rate-limited renovate/c chore(skills): update c"
section_case "errored" "## Errored

The following updates encountered an error and will be retried. To force a retry now, click on a checkbox below.

 - [ ] <!-- retry-branch=renovate/d -->[chore(externals): update d](../pull/12)
" "GAP errored renovate/d [chore(externals): update d](../pull/12)"
section_case "lookup failures" "## Open

 - [ ] <!-- rebase-branch=renovate/e -->[chore: e](../pull/13)


---

> ⚠️ **Warning**
>
> Renovate failed to look up the following dependencies: \`kubermatic/kubeone\`, \`@vectorize-io/hindsight-coding-agents\`.
>
> Files affected: \`home/.chezmoiscripts/run_once_after_23-kubeone.sh.tmpl\`, \`home/.chezmoidata/hindsight.yaml\`

---
" "GAP lookup-failure kubermatic/kubeone
GAP lookup-failure @vectorize-io/hindsight-coding-agents"

echo
echo "== a renovate/ branch with no PR and no Dashboard marker is stale"
pr_of() { # pr_of <branch> <head repo>
  printf '{"number":1,"head":{"ref":"%s","repo":{"full_name":"%s"}},"base":{"ref":"main","repo":{"full_name":"me/dotfiles"}}}' "$1" "$2"; }
branches '[[{"name":"main"},{"name":"feat/x"},{"name":"renovate/a"},{"name":"renovate/f"}],[{"name":"renovate/g"},{"name":"renovate/h"}]]'
pulls "[[$(pr_of renovate/f me/dotfiles),$(pr_of renovate/g fork/dotfiles)]]"
section_case "stale branch" "## Open

The following updates have all been created. To force a retry/rebase of any, click on a checkbox below.

 - [ ] <!-- rebase-branch=renovate/a -->[chore: a](../pull/9)
" "GAP stale-branch renovate/g
GAP stale-branch renovate/h"
pulls; branches

echo
echo "== every error prints nothing on stdout and exits 2"
refused() {
  check "$1: exits 2" "2" "$rc"
  check "$1: no stdout" "" "$out"
}
dashboard "## Vulnerabilities

Renovate has not found any CVEs on [osv.dev](https://osv.dev).
"
run; refused "no Detected Dependencies section"
dashboard "$DETECTED
None detected
"
run; refused "Detected Dependencies holds no dependency"
dashboard "$DETECTED
> ℹ️ **Note**
>
> Detected dependencies section has been truncated

$(detected regex $PKG 'ansible 13.8.0')"
run; refused "a truncated Detected Dependencies section"
"$JQ" -n --arg body "$TRACKED" '[{number: 150, title: "Dependency Dashboard", author_association: "NONE", body: $body},
  {number: 151, title: "Dependency Dashboard", author_association: "MEMBER", body: $body, pull_request: {}},
  {number: 152, title: "Dependency Dashboard (old)", author_association: "MEMBER", body: $body}]' > "$SB/issues.json"
run; refused "zero trusted Dashboards (stranger, PR, near title)"
"$JQ" -n --arg body "$TRACKED" '[{number: 150, title: "Dependency Dashboard", author_association: "OWNER", body: $body},
  {number: 151, title: "Dependency Dashboard", author_association: "COLLABORATOR", body: $body}]' > "$SB/issues.json"
run; refused "two trusted Dashboards"
"$JQ" -n --arg body "$TRACKED" '[range(100) | {number: ., title: "x", author_association: "MEMBER", body: ""}]
  + [{number: 150, title: "Dependency Dashboard", author_association: "MEMBER", body: $body}]' > "$SB/issues.json"
run; refused "100 open issues (the list may be cut)"
dashboard "$TRACKED"
for ep in issues pulls branches; do
  : > "$SB/fail-$ep"
  run; refused "a failed $ep read"
  rm "$SB/fail-$ep"
done
printf '%s' "-cs add" > "$SB/jq-fail-args"; printf '[]' > "$SB/jq-fail-out"
run; refused "a failed jq merge of the lock-file pins"
printf '%s' "-r .json[]" > "$SB/jq-fail-args"; rm "$SB/jq-fail-out"
run; refused "a failed jq list of the lock files"
rm "$SB/jq-fail-args"
printf 'not json' > "$SB/branches.json"
run; refused "a branch read that is not JSON"
branches
cp "$FX/docs/agents/dependencies.md" "$SB/catalogue"
fixture docs/agents/dependencies.md '## Accept-list

accept home/.chezmoidata/packages.yaml boto3
'
run; refused "an accept line with no reason"
rm "$FX/docs/agents/dependencies.md"
run; refused "no catalogue"
cp "$SB/catalogue" "$FX/docs/agents/dependencies.md"
for bin in gh jq git; do
  mv "$SB/bin/$bin" "$SB/$bin.off"
  run; refused "$bin missing"
  mv "$SB/$bin.off" "$SB/bin/$bin"
done
run
check "the good state reads again" "0" "$rc"
check "and prints the INFO lines" "$INFOS" "$out"

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
