#!/bin/bash
# Coverage audit for /deps (#172): prints each pin of a known shape under home/
# that the Dependency Dashboard does not list in Detected Dependencies, and each
# Dashboard section that shows a broken Renovate run. Read-only.
# Exit 0: no gap. Exit 1: a gap. Exit 2: an error, with nothing on stdout.
#
#   scripts/deps-audit.sh
set -u

die() { echo "deps-audit: $*" >&2; exit 2; }

for bin in gh jq git; do
  command -v "$bin" > /dev/null || die "$bin is required"
done

root=$(git rev-parse --show-toplevel 2> /dev/null) || die "not inside the repo"
cd "$root" || die "cannot enter $root"
catalogue=docs/agents/dependencies.md
[ -r "$catalogue" ] || die "cannot read $catalogue"
accept=$(jq -cnR '
  reduce inputs as $l ({in: false, out: []};
    if ($l | startswith("## ")) then .in = ($l == "## Accept-list")
    elif .in and ($l | startswith("accept ")) then
      .out += [$l | capture("^accept (?<f>[^ ]+) (?<p>[^ ]+) (?<r>.*[^ ].*)$")
        // error("an accept-list line has no file, pin and reason")]
    else . end)
  | .out
' "$catalogue") || die "cannot read the accept-list of $catalogue"

# git ls-files, not rg: rg skips hidden dirs, and the pins live in .chezmoidata.
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(git ls-files -z -- home)

# A pin is named without its version, as the accept-list names it. A version
# inside a formula name (python@3.13) or a sdkman id (25-tem) names a different
# package when it moves, so it stays in the name. A `#` comment is cut first:
# comments name pins in prose (helm@3 in helm3-pin.zsh, .zprofile).
scan=$(jq -cnR '
  reduce (inputs | {f: input_filename, raw: ., l: sub("(^|\\s)#.*$"; "")}) as $x
    ({f: null, top: null, hits: [], json: []};
      (if $x.f != .f then .f = $x.f | .top = null else . end)
      | (if ($x.raw | test("^[A-Za-z_][\\w.-]*:")) then .top = ($x.raw | capture("^(?<k>[^:]+):").k) else . end)
      | .hits += [$x.l
          | ([scan("(?<![\\w/@.+-])([A-Za-z][\\w.+-]*@[0-9][\\w.]*)")[0] | sub("\\.+$"; "")][]),
            ([scan("([A-Za-z][\\w.-]*)==[0-9][\\w.]*")[0]][]),
            (if test("^\\s*(-\\s+)?python:\\s*\"?[0-9]") then "python" else empty end),
            ((capture("(^|\\s)sdkman:\\s*\\[(?<l>[^\\]]*)\\]").l // empty)
              | split(",")[] | gsub("^\\s+|\\s+$"; "") | select(. != ""))
          | {f: $x.f, p: .}]
      | (if .top == "secretGuard" and ($x.l | test("^\\s+version:\\s*\"?[^\"\\s]")) then
           .hits += [{f: $x.f, p: "secretGuard.version"}] else . end)
      | (if ($x.l | test("\"skillFolderHash\"")) then .json += [$x.f] else . end))
  | {hits, json: (.json | unique)}
' "${files[@]}" < /dev/null) || die "cannot search the pins"

hits=$(jq -c '.hits' <<< "$scan")
while IFS= read -r f; do
  [ -n "$f" ] || continue
  more=$(jq -c --arg f "$f" '[paths(type == "object" and has("skillFolderHash"))
    | map(tostring) | join(".") + ".skillFolderHash" | {f: $f, p: .}]' "$f") \
    || die "cannot read $f as JSON"
  hits=$(printf '%s\n%s\n' "$hits" "$more" | jq -cs add)
done <<< "$(jq -r '.json[]' <<< "$scan")"

issues=$(gh api 'repos/{owner}/{repo}/issues?state=open&per_page=100') \
  || die "gh api issues failed"
pulls=$(gh api --paginate --slurp 'repos/{owner}/{repo}/pulls?state=open&per_page=100') \
  || die "gh api pulls failed"
branches=$(gh api --paginate --slurp 'repos/{owner}/{repo}/branches?per_page=100') \
  || die "gh api branches failed"

# The Dashboard body is untrusted data: anyone can open an issue with its title,
# so only a member's issue counts, and its text never reaches stdout uncleaned.
# The reads go to jq on stdin: the issue bodies overflow ARG_MAX as --argjson.
out=$(printf '%s\n%s\n%s\n%s\n%s\n' "$issues" "$pulls" "$branches" "$hits" "$accept" | jq -rs '
  def clean: gsub("[\\p{Cc}\\p{Cf}\\s]+"; " ") | sub("^ "; "") | sub(" $"; "");

  if length != 5 then error("cannot read the gh output") else . end
  | .[0] as $issues | (.[1] | add // []) as $pulls | (.[2] | add // []) as $branches
  | .[3] as $hits | .[4] as $accept
  | if ($issues | length) >= 100 then error("100 open issues: the list may be cut") else . end
  | ($issues | map(select(has("pull_request") | not)
      | select(.title == "Dependency Dashboard"
          and (.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))))) as $dash
  | if ($dash | length) != 1 then error("\($dash | length) trusted open Dependency Dashboard issues, want 1") else . end
  | ($dash[0].body // "" | gsub("\r"; "") | split("\n")) as $lines
  | def section($t):
      reduce $lines[] as $l ({in: false, found: false, out: []};
        if ($l | startswith("## ")) then .in = ($l == "## " + $t) | .found = (.found or .in)
        elif .in then .out += [$l]
        else . end)
      | if .found then .out else null end;
  def migration($t):
    section($t) // empty
    | map(gsub("<!--.*?-->"; "") | sub("^ - \\[[ x]\\] "; "")) | join(" ") | clean
    | "GAP config-migration \(if . == "" then "needed" else . end)";
  def items($t; $kind):
    section($t) // [] | .[]
    | select(startswith(" - ") and (test("^ - \\[[ x]\\] <!-- create-all-") | not))
    | if test("^ - \\[[ x]\\] <!-- [a-z]+-branch=\\S+ -->") then
        capture("^ - \\[[ x]\\] <!-- [a-z]+-branch=(?<b>\\S+) -->(?<t>.*)$") | "GAP \($kind) \(.b | clean) \(.t | clean)"
      else "GAP \($kind) \(sub("^ - "; "") | clean)" end;

  [migration("Config Migration Needed"), migration("Config Migration Needed (Blocked)"),
   items("Repository Problems"; "problem"), items("Awaiting Schedule"; "awaiting-schedule"),
   items("Rate-Limited"; "rate-limited"), items("Errored"; "errored"),
   ($lines[] | select(startswith("> Renovate failed to look up the following dependencies: "))
     | scan("`([^`]+)`")[0] | "GAP lookup-failure \(clean)")
  ] as $dashgaps
  | ([$lines[] | scan("<!-- [a-z]+-branch=(\\S+) -->")[0]]
     + [$pulls[] | select(.head.repo.full_name == .base.repo.full_name) | .head.ref]) as $known
  | [$branches[].name | select(startswith("renovate/")) | select(. as $b | $known | index([$b]) | not)
     | "GAP stale-branch \(clean)"] as $stale

  | (section("Detected Dependencies") // error("the Dashboard has no Detected Dependencies section")
    | if any(.[]; test("^> .*Detected dependencies section has been truncated")) then
        error("the Detected Dependencies section is truncated: a listed pin may look untracked") else . end
    | reduce .[] as $l ({file: null, deps: []};
        if ($l | test("^<details><summary>.*</summary>$")) then
          .file = ($l | capture("^<details><summary>(?<s>.*?)( \\([0-9]+\\))?</summary>$").s)
        elif ($l | test("^ - `[^ `]+ ")) then
          .deps += [{f: .file, p: ($l | capture("^ - `(?<p>[^ `]+) ").p)}]
        else . end)
    | if .deps == [] then error("the Detected Dependencies section lists no dependency") else .deps end
  ) as $detected
  | ($hits | unique | map(select(. as $h | $detected | index([$h]) | not))) as $untracked
  | $dashgaps[], $stale[],
    ($untracked | map(. as $h | select(any($accept[]; .f == $h.f and .p == $h.p) | not))[]
      | "GAP untracked \(.f) \(.p)"),
    ($untracked | map(. as $h | first($accept[] | select(.f == $h.f and .p == $h.p)) // empty)[]
      | "INFO accepted \(.f) \(.p) \(.r | clean)")
') || die "cannot read the gh output"

[ -n "$out" ] && printf '%s\n' "$out"
case "$out" in *GAP*) exit 1 ;; esac
exit 0
