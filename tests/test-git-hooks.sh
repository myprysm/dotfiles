#!/bin/bash
# Tests the estate-wide git hooks (#18): the gitleaks pre-commit scan, the
# _chain dispatch, and the shims. Renders the chezmoi source into a scratch
# directory - never touches the real HOME, ~/.gitconfig, or any real repo.
#
#   ./tests/test-git-hooks.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/home"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

pass=0; fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1 (exit $3)"
  else fail=$((fail+1)); echo "  FAIL $1 (expected $2, got $3)"; fi
}
yes_no() { # yes_no <label> <0 if condition held>
  if [ "$2" = "0" ]; then pass=$((pass+1)); echo "  ok   $1"
  else fail=$((fail+1)); echo "  FAIL $1"; fi
}

mkdir -p "$SB/hooks"
chezmoi execute-template --source "$SRC" \
  < "$SRC/dot_config/git/hooks/executable_pre-commit.tmpl" > "$SB/hooks/pre-commit"
cp "$SRC/dot_config/git/hooks/executable__chain" "$SB/hooks/_chain"
chmod +x "$SB/hooks/pre-commit" "$SB/hooks/_chain"
for h in commit-msg prepare-commit-msg pre-push post-checkout post-commit post-merge; do
  ln -sf _chain "$SB/hooks/$h"
done

newrepo() {
  rm -rf "$SB/repo"; mkdir -p "$SB/repo"; cd "$SB/repo" || exit 1
  git init -q .
  git config user.email t@example.invalid; git config user.name Test
  git config commit.gpgsign false
  git config core.hooksPath "$SB/hooks"
}

# A canary must be a REAL-shaped secret. The AWS documentation example key
# (AKIAIOSFODNN7EXAMPLE) is in gitleaks' default allowlist and passes - case 4
# pins that, so a future reader does not mistake it for a broken hook.
#
# Both fixtures are fake, and both are flagged by the very hook under test -
# the commit adding this file was refused by it. `gitleaks:allow` is the
# documented marker for exactly this case. It is the ONLY place in this repo
# where it is acceptable: these two strings are the test's subject matter.
PAT='ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8' # gitleaks:allow
KEYBLOCK='-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gt\n-----END OPENSSH PRIVATE KEY-----\n' # gitleaks:allow

echo "== 1. clean staged diff commits"
newrepo; echo hello > a.txt; git add a.txt
git commit -q -m clean >/dev/null 2>&1; check "clean commit" 0 $?

echo "== 2. planted token is refused on the FIRST commit (no HEAD yet)"
newrepo; printf 'token = "%s"\n' "$PAT" > t.txt; git add t.txt
out=$(git commit -m leak 2>&1); check "token commit refused" 1 $?
echo "$out" | grep -q "commit refused"; yes_no "refusal message present" $?
echo "$out" | grep -qv "$PAT"; yes_no "secret value redacted in output" $?

echo "== 3. private key block is refused (with HEAD)"
newrepo; echo base > a.txt; git add a.txt; git commit -q --no-verify -m base >/dev/null 2>&1
printf -- "$KEYBLOCK" > id_fake; git add id_fake
git commit -q -m key >/dev/null 2>&1; check "private key refused" 1 $?

echo "== 4. the AWS documentation example key is allowlisted by gitleaks"
newrepo
printf 'aws_key = "AKIAIOSFODNN7EXAMPLE"\naws_secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"\n' > creds.txt
git add creds.txt; git commit -q -m aws >/dev/null 2>&1
check "AWS example passes (scanner config, NOT a hook defect)" 0 $?

echo "== 5. absent gitleaks fails closed"
newrepo; echo hi > a.txt; git add a.txt
mkdir -p "$SB/hooks-absent"
sed 's#^GITLEAKS=.*#GITLEAKS="/nonexistent/gitleaks"#' "$SB/hooks/pre-commit" > "$SB/hooks-absent/pre-commit"
cp "$SB/hooks/_chain" "$SB/hooks-absent/_chain"
chmod +x "$SB/hooks-absent/pre-commit" "$SB/hooks-absent/_chain"
git config core.hooksPath "$SB/hooks-absent"
out=$(PATH=/usr/bin:/bin git commit -m x 2>&1); check "absent gitleaks blocks" 1 $?
echo "$out" | grep -q "brew install gitleaks"; yes_no "names the install command" $?

echo "== 6. chains to the repo's own pre-commit after a clean scan"
newrepo; mkdir -p .git/hooks
printf '#!/bin/sh\necho LOCAL-PRECOMMIT-RAN\nexit 0\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo hi > a.txt; git add a.txt
out=$(git commit -m chain 2>&1); check "commit succeeds" 0 $?
echo "$out" | grep -q LOCAL-PRECOMMIT-RAN; yes_no "local pre-commit ran" $?

echo "== 7. the local hook's non-zero exit propagates"
newrepo; mkdir -p .git/hooks
printf '#!/bin/sh\nexit 3\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
echo hi > a.txt; git add a.txt
git commit -q -m x >/dev/null 2>&1; check "local rejection blocks commit" 1 $?

echo "== 8. no recursion (git rev-parse --git-path honours core.hooksPath)"
newrepo; echo hi > a.txt; git add a.txt
timeout 20 git commit -q -m x >/dev/null 2>&1; check "commit terminates, not a timeout" 0 $?

echo "== 9. every shim chains, and propagates a rejection"
for h in commit-msg prepare-commit-msg post-commit; do
  newrepo; mkdir -p .git/hooks
  printf '#!/bin/sh\necho LOCAL-%s-RAN\nexit 0\n' "$h" > ".git/hooks/$h"
  chmod +x ".git/hooks/$h"
  echo hi > a.txt; git add a.txt
  out=$(git commit -m shim 2>&1)
  echo "$out" | grep -q "LOCAL-$h-RAN"; yes_no "$h shim chained" $?
done
newrepo; mkdir -p .git/hooks
printf '#!/bin/sh\nexit 7\n' > .git/hooks/commit-msg; chmod +x .git/hooks/commit-msg
echo hi > a.txt; git add a.txt
git commit -q -m x >/dev/null 2>&1; check "commit-msg rejection blocks commit" 1 $?

echo "== 10. a shim with no local hook is a no-op"
newrepo; echo hi > a.txt; git add a.txt
git commit -q -m x >/dev/null 2>&1; check "commit succeeds with empty .git/hooks" 0 $?

echo "== 11. linked worktree resolves the common dir"
newrepo; echo hi > a.txt; git add a.txt; git commit -q -m base >/dev/null 2>&1
mkdir -p .git/hooks
printf '#!/bin/sh\necho LOCAL-PRECOMMIT-RAN\nexit 0\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git worktree add -q "$SB/wt" -b wtbranch >/dev/null 2>&1
cd "$SB/wt" || exit 1
echo hi2 > b.txt; git add b.txt
out=$(git commit -m x 2>&1); check "worktree commit succeeds" 0 $?
echo "$out" | grep -q LOCAL-PRECOMMIT-RAN; yes_no "worktree chained to the common dir" $?

echo "== 12. --no-verify remains the operator's escape hatch"
newrepo; printf 'token = "%s"\n' "$PAT" > t.txt; git add t.txt
git commit -q --no-verify -m x >/dev/null 2>&1; check "bypass commits" 0 $?

echo
echo "===== $pass passed, $fail failed ====="
[ "$fail" -eq 0 ]
