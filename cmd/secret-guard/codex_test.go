package main

import "testing"

func checkEveryAgent(t *testing.T, want, cmd, why string) {
	t.Helper()
	defer func() { Agent = "" }()
	for _, a := range []string{"", "codex"} {
		Agent = a
		check(t, want, cmd, why+" (agent "+a+")")
	}
}

// Neither agent has a Grep tool filtered by deny rules, so a blanket `rg`
// denial leaves it no way to search (#96). rg is allowed while it keeps its own hidden-file and ignore-file filters, which is what skips
// `.env*`, `.ssh`, `.aws` and `.secrets` in a tree walk.
func TestCodexRgRespectingFiltersIsAllowed(t *testing.T) {
	checkEveryAgent(t, "allow", `rg foo`, "a plain search of the working directory")
	checkEveryAgent(t, "allow", `rg -n TODO src`, "a search of one directory")
	checkEveryAgent(t, "allow", `rg '\.env' Makefile`, "the pattern names a secret, rg never opens it")
	checkEveryAgent(t, "allow", `rg -A 3 .env src`, "a value-taking option before the pattern")
	checkEveryAgent(t, "allow", `rg -C 3 foo src`, "context lines")
	checkEveryAgent(t, "allow", `rg -g '!vendor' foo`, "an exclude glob only narrows")
	checkEveryAgent(t, "allow", `rg --glob='!*.min.js' foo`, "an exclude glob, attached")
	checkEveryAgent(t, "allow", `rg -ng '!vendor' foo`, "an exclude glob in a bundle")
	checkEveryAgent(t, "allow", `rg -T go foo`, "an exclude type only narrows")
	checkEveryAgent(t, "allow", `rg --type-not go foo`, "an exclude type, long")
	checkEveryAgent(t, "allow", `rg -e foo -e bar src`, "patterns on the flag")
	checkEveryAgent(t, "allow", `rg --no-require-git foo`, "narrows the search")
	checkEveryAgent(t, "allow", `rg --no-ignore-messages foo`, "only silences messages")
	checkEveryAgent(t, "allow", `rg --version`, "searches nothing")
}

func TestCodexRgDisablingFiltersIsDenied(t *testing.T) {
	checkEveryAgent(t, "deny", `rg -u foo`, "unrestricted")
	checkEveryAgent(t, "deny", `rg -uu foo`, "unrestricted twice")
	checkEveryAgent(t, "deny", `rg -iu foo`, "unrestricted in a bundle")
	checkEveryAgent(t, "deny", `rg --unrestricted foo`, "long unrestricted")
	checkEveryAgent(t, "deny", `rg --hidden foo`, "hidden files")
	checkEveryAgent(t, "deny", `rg -. foo`, "hidden files, short")
	checkEveryAgent(t, "deny", `rg -n. foo`, "hidden files in a bundle")
	checkEveryAgent(t, "deny", `rg --no-ignore foo`, "ignore files off")
	checkEveryAgent(t, "deny", `rg --no-ignore-vcs foo`, "gitignore off")
	checkEveryAgent(t, "deny", `rg --no-ignore-dot foo`, "dot ignore files off")
	checkEveryAgent(t, "deny", `rg --pre cat foo`, "runs a command per file")
	checkEveryAgent(t, "deny", `rg --pre=cat foo`, "runs a command per file, attached")
	checkEveryAgent(t, "deny", `rg --pre-glob '*' foo`, "pre-glob")
	checkEveryAgent(t, "deny", `rg --hostname-bin ./x foo`, "runs a command")
	checkEveryAgent(t, "deny", `rg -L foo`, "follows symlinks out of the tree")
	checkEveryAgent(t, "deny", `rg -nL foo`, "follow in a bundle")
	checkEveryAgent(t, "deny", `rg --follow foo`, "follow, long")
	checkEveryAgent(t, "deny", `rg --ignore-file=wl foo`, "a whitelist in an ignore file overrides the hidden filter")
	checkEveryAgent(t, "deny", `rg --ignore-file wl foo`, "ignore file, separate value")
	checkEveryAgent(t, "deny", `RIPGREP_CONFIG_PATH=/tmp/rc rg foo`, "a config file can turn on --hidden")
	checkEveryAgent(t, "deny", `env RIPGREP_CONFIG_PATH=/tmp/rc rg foo`, "the env spelling")
}

// An include filter whitelists matching files past the hidden filter, and a
// glob past .gitignore too: `-g '*'` printed hidden and ignored canaries.
func TestCodexRgIncludeFiltersAreDenied(t *testing.T) {
	checkEveryAgent(t, "deny", `rg -g '*.go' foo`, "include glob")
	checkEveryAgent(t, "deny", `rg -g'*.go' foo`, "include glob, attached")
	checkEveryAgent(t, "deny", `rg --glob='*' foo`, "include glob, long")
	checkEveryAgent(t, "deny", `rg --glob '*' foo`, "include glob, long, separate")
	checkEveryAgent(t, "deny", `rg -ng '*.go' foo`, "include glob in a bundle")
	checkEveryAgent(t, "deny", `rg --iglob .ENV foo`, "case-insensitive include glob")
	checkEveryAgent(t, "deny", `rg -t go foo`, "include type")
	checkEveryAgent(t, "deny", `rg -tgo foo`, "include type, attached")
	checkEveryAgent(t, "deny", `rg --type=go foo`, "include type, long")
	checkEveryAgent(t, "deny", `rg --type-add 'x:*' foo`, "a type defined to match anything")
}

func TestCodexRgSecretOperandIsDenied(t *testing.T) {
	// rg searches a path it is NAMED even when that path is hidden.
	checkEveryAgent(t, "deny", `rg foo ~/.kube`, "a named secret directory")
	checkEveryAgent(t, "deny", `rg foo ~/.secrets/`, "the secrets directory")
	checkEveryAgent(t, "deny", `rg foo .env`, "a named dotenv file")
	checkEveryAgent(t, "deny", `rg -e foo ~/.kube/config`, "the pattern on the flag, the secret is the path")
	checkEveryAgent(t, "deny", `rg -f ~/.env src`, "patterns read from a secret")
	checkEveryAgent(t, "deny", `rg --file=.env src`, "patterns read from a secret, attached")
	checkEveryAgent(t, "deny", `rg -nf ~/.env src`, "pattern file in a bundle")
	checkEveryAgent(t, "deny", `cd ~/.secrets && rg foo`, "search inside a secret directory")
}

func TestCodexKeepsEveryOtherRule(t *testing.T) {
	checkEveryAgent(t, "deny", `ag foo`, "only rg is relaxed")
	checkEveryAgent(t, "deny", `ack foo`, "only rg is relaxed")
	checkEveryAgent(t, "deny", `grep -r foo .`, "grep recursion stays denied")
	checkEveryAgent(t, "deny", `cat ~/.env`, "a direct read")
	checkEveryAgent(t, "deny", `git commit --no-verify -m x`, "the bypass class")
}
