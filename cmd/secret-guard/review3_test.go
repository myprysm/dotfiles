package main

import "testing"

// Round 3. Defects the fresh adversarial review found, each confirmed by
// executing it against a canary file before being fixed.

func TestReviewWrapperPositionalOperands(t *testing.T) {
	// The scan stopped at the first bare word after a wrapper, so a wrapper's
	// OWN operand became the "command" and the reader behind it was invisible.
	// The floor got these right, which made this a regression against the
	// layer the binary fronts.
	check(t, "deny", `script -q /dev/null cat ~/.env`, "script's typescript operand")
	check(t, "deny", `env - cat ~/.env`, "env's bare dash")
	check(t, "deny", `sudo - cat ~/.env`, "a bare dash after sudo")
	check(t, "deny", `nice - cat ~/.env`, "a bare dash after nice")
	check(t, "deny", `su user -c 'cat ~/.env'`, "su's username before its -c payload")
	check(t, "deny", `parallel -j2 'cat {}' ::: ~/.env`, "parallel's operand syntax")
	// The look-ahead must not swallow operands of a non-reading command.
	check(t, "allow", `sudo cp ./config /tmp/x`, "a copy behind sudo")
	check(t, "allow", `env FOO=1 npm run build`, "an environment assignment")
	check(t, "allow", `timeout 30 make build`, "an ordinary wrapped command")
	check(t, "allow", `script -q /dev/null make test`, "script running a build")
}

func TestReviewCopyThenRead(t *testing.T) {
	// A copy crosses no boundary on its own, which is why it is allowed - but
	// copying and then reading in ONE command line is a read, and neither half
	// alone says so.
	check(t, "deny", `cp ~/.env /tmp/pub && cat /tmp/pub`, "copy then read")
	check(t, "deny", `ln -s ~/.env /tmp/pub; cat /tmp/pub`, "symlink then read")
	check(t, "deny", `mv ~/.env /tmp/pub && head /tmp/pub`, "move then read")
	check(t, "deny", `install ~/.envrc /tmp/x && cat /tmp/x`, "install then read")
	check(t, "deny", `cp ~/.kube/config /tmp/k && jq . /tmp/k`, "copy a kubeconfig then read it")
	// A copy alone stays allowed, and so does reading an unrelated file.
	check(t, "allow", `cp ./.env /tmp/backup.env`, "a copy by itself")
	check(t, "allow", `cp ./a /tmp/b && cat /tmp/b`, "copy and read of something ordinary")
	check(t, "allow", `cp ./.env /tmp/x && echo done`, "a copy followed by no read")
}

func TestReviewStreamingExec(t *testing.T) {
	// A command that is not a reader becomes one when it is pointed at a
	// standard stream, and xargs and find -exec hand it every path they find.
	check(t, "deny", `find . -name '*env*' | xargs -I{} cp {} /dev/stdout`, "xargs feeding cp to stdout")
	check(t, "deny", `find . -type f -exec cp {} /dev/stdout \;`, "find -exec doing the same")
	check(t, "allow", `find . -type f -exec chmod 644 {} \;`, "an ordinary -exec")
	check(t, "allow", `xargs -n1 echo < /tmp/list.txt`, "an ordinary xargs")
}

func TestReviewExpansionInsideTheName(t *testing.T) {
	// The expansion marker was substituted for a wildcard only AFTER the
	// has-metacharacter test, so a word whose only wildcard is the expansion
	// returned early and was never looked at.
	check(t, "deny", `cat /Users/x/.e${nope}nv`, "an expansion inside the filename")
	check(t, "deny", `cat ~/.k${x}ube/config`, "an expansion inside a directory name")
	check(t, "deny", `cat ~/.e$xnv`, "a bare parameter inside the name")
	check(t, "deny", "cat ~/.e`echo`nv", "a substitution inside the name")
	check(t, "allow", `cat ${HOME}/projects/README.md`, "an ordinary expansion")
	check(t, "allow", `cat ${dir}/main.go`, "an expansion naming nothing secret")
}

func TestReviewGitConfigEnvironment(t *testing.T) {
	// The environment spelling of the hooksPath bypass names neither
	// --no-verify nor `git -c`.
	check(t, "deny",
		`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x`,
		"the environment override")
	check(t, "deny", `chmod -x .git/hooks/pre-commit && git commit -m x`, "disabling the hook file")
	check(t, "deny", `rm .git/hooks/pre-commit; git commit -m x`, "removing the hook file")
	check(t, "deny", `mv .git/hooks/pre-commit /tmp/ && git commit -m x`, "moving the hook aside")
	check(t, "allow", `GIT_AUTHOR_NAME=x git commit -m y`, "an ordinary git environment variable")
	check(t, "allow", `chmod +x scripts/build.sh`, "an ordinary chmod")
}

func TestReviewMissingReaders(t *testing.T) {
	check(t, "deny", `m4 ~/.env`, "m4 prints its input")
	// interpRe spelled Rscript with a capital while base() lowercases first,
	// so that alternative could never fire.
	check(t, "deny", `Rscript -e 'cat(readLines("/Users/x/.env"))'`, "case in the interpreter pattern")
	check(t, "deny", `zmodload zsh/mapfile; print -r -- $mapfile[~/.env]`, "zsh's mapfile module")
}

// ---------------------------------------------------------------------------
// False positives measured on realistic traffic for this estate's stack.

func TestReviewCodeIdentifiersAreNotPaths(t *testing.T) {
	// `.env` is matched with no boundary in front of it, which is what catches
	// `prod.env` - so it matched every source line reaching an `env` property.
	// This estate is Vue, Vite and Laravel, so those lines are everywhere.
	check(t, "allow", `node -p "process.env.NODE_ENV"`, "a node property access")
	check(t, "allow", `node -e "console.log(process.env.API_URL)"`, "the same in a script")
	check(t, "allow", `node -e "console.log(import.meta.env)"`, "vite's import.meta.env")
	check(t, "allow", `sed -i '' 's/import.meta.env.VITE_API/API/' src/main.ts`, "a sed program")
	check(t, "allow", `awk '/import.meta.env.VITE_X/{print}' src/app.ts`, "an awk program")
	check(t, "allow", `sed -n '/process.env.NODE_ENV/p' webpack.config.js`, "a sed search")
	check(t, "allow", `diff old.env.js new.env.js`, "source files that carry env in the name")
	check(t, "allow", `cat config.env.ts`, "a typescript module")
	// A real dotenv file is still a real dotenv file.
	check(t, "deny", `sed -n 1p ~/.env`, "sed reading the real file")
	check(t, "deny", `awk '{print}' ~/.env`, "awk reading the real file")
	check(t, "deny", `sed -f ~/.env data.txt`, "the script read from a secret")
	check(t, "deny", `awk -f ~/.envrc data.txt`, "the same for awk")
	check(t, "deny", `node ~/.env`, "node handed the real file")
	check(t, "deny", `cat prod.env`, "a dotenv file with a prefix")
}

func TestReviewGitProseOperands(t *testing.T) {
	// A message or a search expression is prose, not a filename. This is the
	// same association split that stopped `git commit -m` being refused; it
	// was never carried into the other subcommands.
	check(t, "allow", `git stash push -m "wip on .env parser"`, "a stash message")
	check(t, "allow", `git log --oneline --grep=kubeconfig`, "a log search")
	check(t, "allow", `git log --grep '.env loading' -n 5`, "the separate spelling")
	check(t, "allow", `git log --author "someone" --format="%H .env"`, "an author and a format")
	check(t, "allow", `git log -S '.env' --oneline`, "a pickaxe search")
	// A real path operand is still judged.
	check(t, "deny", `git show HEAD:.env`, "a path in a show operand")
	check(t, "deny", `git diff HEAD -- ~/.env`, "a path in a diff operand")
}

func TestReviewInfoFlags(t *testing.T) {
	check(t, "allow", `rg --version`, "a version query is not a search")
	check(t, "allow", `ag --help`, "a help query")
	check(t, "allow", `rg -V`, "the short spelling")
	check(t, "deny", `rg pattern`, "an actual search")
	check(t, "deny", `rg --version pattern .`, "a search wearing a version flag")
}
