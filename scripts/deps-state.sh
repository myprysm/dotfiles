#!/bin/bash
# Prints the Renovate state of this repo for /deps: open PRs, pins pending
# approval, advisories. All or nothing (#173): stdout is written only after every
# read succeeded; any error prints to stderr and exits 2.
#
#   scripts/deps-state.sh
set -u

die() { echo "deps-state: $*" >&2; exit 2; }

for bin in gh jq; do
  command -v "$bin" > /dev/null || die "$bin is required"
done

prs=$(gh pr list --state open --limit 100 \
  --json number,createdAt,headRefOid,headRefName,isCrossRepository,labels,title) \
  || die "gh pr list failed"
issues=$(gh issue list --state open --limit 100 --search 'in:title "Dependency Dashboard"' \
  --json number,title,body) \
  || die "gh issue list failed"

out=$(jq -rn --argjson prs "$prs" --argjson issues "$issues" '
  def clean: gsub("[\\p{Cc}\\p{Cf}\\s]+"; " ") | sub("^ "; "") | sub(" $"; "");

  if ($prs | length) >= 100 then error("100 open PRs: the list may be cut") else . end
  | ($issues | map(select(.title == "Dependency Dashboard"))) as $dash
  | if ($dash | length) != 1 then error("\($dash | length) open Dependency Dashboard issues, want 1") else . end
  | ($dash[0].body | gsub("\r"; "") | split("\n")) as $lines
  | def section($t):
      reduce $lines[] as $l ({in: false, found: false, out: []};
        if ($l | startswith("## ")) then .in = ($l == "## " + $t) | .found = (.found or .in)
        elif .in then .out += [$l]
        else . end)
      | if .found then .out else null end;

  (section("Pending Approval") // []
    | map(
        if test("^ - \\[[ x]\\] <!-- approve-branch=\\S+ -->") then
          capture("^ - \\[[ x]\\] <!-- approve-branch=(?<b>\\S+) -->(?<t>.*)$") | "PENDING \(.b | clean) \(.t | clean)"
        elif test("^ - \\[[ x]\\] <!-- approve-all-pending-prs -->") then empty
        elif test("^\\s*$") or startswith("### ") or startswith("The following branches are pending approval") then empty
        else error("a Pending Approval line has an unknown shape") end)
  ) as $pending
  | (section("Vulnerabilities") // error("the Dashboard has no Vulnerabilities section")
    | reduce .[] as $l ({stack: [], found: [], skipped: 0};
        if ($l | test("^<details><summary>.*</summary>$")) then
          .stack += [$l | capture("^<details><summary>(?<s>.*)</summary>$").s | clean]
        elif $l == "</details>" then .stack |= .[:-1]
        elif $l == "<blockquote>" or $l == "</blockquote>" or ($l | test("^\\s*$")) or ($l | startswith(">"))
          or ($l | startswith("Renovate has not found any CVEs")) then .
        elif ($l | startswith("Renovate was unable to fetch CVE information")) then
          error("Renovate could not fetch the advisories on its last run")
        else
          ($l | capture("^- \\[(?<id>[^\\]]+)\\]\\(https://osv\\.dev/vulnerability/(?<id2>[^)]+)\\)( \\(fixed in [^)]*\\))?$") // null) as $m
          | if $m != null and $m.id == $m.id2 and (.stack | length) == 3
               and ($m.id | test("^(GHSA(-[23456789cfghjmpqrvwx]{4}){3}|CVE-[0-9]{4}-[0-9]{4,})$"))
            then .found += ["\($m.id) \(.stack[2]) \(.stack[1])"]
            else .skipped += 1 end
        end)
  ) as $adv
  | ($prs
    | map(select(.isCrossRepository == false and (.headRefName | startswith("renovate/"))))
    | sort_by(.number)
    | map("PR #\(.number) \((now - (.createdAt | fromdate)) / 86400 | floor)d \(.headRefOid) labels:\(.labels | map(.name | clean) | join(",")) \(.title | clean)")
  ) as $pr_lines
  | (if $pr_lines == [] then "PRs: none" else $pr_lines[] end),
    (if $pending == [] then "pending: none" else $pending[] end),
    (if $adv.found == [] then "advisories: none" else $adv.found[] end),
    (if $adv.skipped > 0 then "advisories skipped: \($adv.skipped) (unparsed)" else empty end)
') || die "cannot read the gh output"

printf '%s\n' "$out"
