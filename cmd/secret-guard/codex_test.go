package main

import "testing"

func checkCodex(t *testing.T, want, cmd, why string) {
	t.Helper()
	Agent = "codex"
	defer func() { Agent = "" }()
	check(t, want, cmd, why)
}

// Codex has no Grep tool filtered by deny rules, so a blanket `rg` denial
// leaves it no way to search (#96). Under -agent=codex, rg is allowed while it
// keeps its own hidden-file and ignore-file filters, which is what skips
// `.env*`, `.ssh`, `.aws` and `.secrets` in a tree walk.
func TestCodexRgRespectingFiltersIsAllowed(t *testing.T) {
	checkCodex(t, "allow", `rg foo`, "a plain search of the working directory")
	checkCodex(t, "allow", `rg -n TODO src`, "a search of one directory")
	checkCodex(t, "allow", `rg '\.env' Makefile`, "the pattern names a secret, rg never opens it")
	checkCodex(t, "allow", `rg -A 3 .env src`, "a value-taking option before the pattern")
	checkCodex(t, "allow", `rg -C 3 foo src`, "context lines")
	checkCodex(t, "allow", `rg -g '!vendor' foo`, "an exclude glob only narrows")
	checkCodex(t, "allow", `rg --glob='!*.min.js' foo`, "an exclude glob, attached")
	checkCodex(t, "allow", `rg -ng '!vendor' foo`, "an exclude glob in a bundle")
	checkCodex(t, "allow", `rg -T go foo`, "an exclude type only narrows")
	checkCodex(t, "allow", `rg --type-not go foo`, "an exclude type, long")
	checkCodex(t, "allow", `rg -e foo -e bar src`, "patterns on the flag")
	checkCodex(t, "allow", `rg --no-require-git foo`, "narrows the search")
	checkCodex(t, "allow", `rg --no-ignore-messages foo`, "only silences messages")
	checkCodex(t, "allow", `rg --version`, "searches nothing")
}

func TestCodexRgDisablingFiltersIsDenied(t *testing.T) {
	checkCodex(t, "deny", `rg -u foo`, "unrestricted")
	checkCodex(t, "deny", `rg -uu foo`, "unrestricted twice")
	checkCodex(t, "deny", `rg -iu foo`, "unrestricted in a bundle")
	checkCodex(t, "deny", `rg --unrestricted foo`, "long unrestricted")
	checkCodex(t, "deny", `rg --hidden foo`, "hidden files")
	checkCodex(t, "deny", `rg -. foo`, "hidden files, short")
	checkCodex(t, "deny", `rg -n. foo`, "hidden files in a bundle")
	checkCodex(t, "deny", `rg --no-ignore foo`, "ignore files off")
	checkCodex(t, "deny", `rg --no-ignore-vcs foo`, "gitignore off")
	checkCodex(t, "deny", `rg --no-ignore-dot foo`, "dot ignore files off")
	checkCodex(t, "deny", `rg --pre cat foo`, "runs a command per file")
	checkCodex(t, "deny", `rg --pre=cat foo`, "runs a command per file, attached")
	checkCodex(t, "deny", `rg --pre-glob '*' foo`, "pre-glob")
	checkCodex(t, "deny", `rg --hostname-bin ./x foo`, "runs a command")
	checkCodex(t, "deny", `rg -L foo`, "follows symlinks out of the tree")
	checkCodex(t, "deny", `rg -nL foo`, "follow in a bundle")
	checkCodex(t, "deny", `rg --follow foo`, "follow, long")
	checkCodex(t, "deny", `rg --ignore-file=wl foo`, "a whitelist in an ignore file overrides the hidden filter")
	checkCodex(t, "deny", `rg --ignore-file wl foo`, "ignore file, separate value")
	checkCodex(t, "deny", `RIPGREP_CONFIG_PATH=/tmp/rc rg foo`, "a config file can turn on --hidden")
	checkCodex(t, "deny", `env RIPGREP_CONFIG_PATH=/tmp/rc rg foo`, "the env spelling")
}

// An include filter whitelists matching files past the hidden filter, and a
// glob past .gitignore too: `-g '*'` printed hidden and ignored canaries.
func TestCodexRgIncludeFiltersAreDenied(t *testing.T) {
	checkCodex(t, "deny", `rg -g '*.go' foo`, "include glob")
	checkCodex(t, "deny", `rg -g'*.go' foo`, "include glob, attached")
	checkCodex(t, "deny", `rg --glob='*' foo`, "include glob, long")
	checkCodex(t, "deny", `rg --glob '*' foo`, "include glob, long, separate")
	checkCodex(t, "deny", `rg -ng '*.go' foo`, "include glob in a bundle")
	checkCodex(t, "deny", `rg --iglob .ENV foo`, "case-insensitive include glob")
	checkCodex(t, "deny", `rg -t go foo`, "include type")
	checkCodex(t, "deny", `rg -tgo foo`, "include type, attached")
	checkCodex(t, "deny", `rg --type=go foo`, "include type, long")
	checkCodex(t, "deny", `rg --type-add 'x:*' foo`, "a type defined to match anything")
}

func TestCodexRgSecretOperandIsDenied(t *testing.T) {
	// rg searches a path it is NAMED even when that path is hidden.
	checkCodex(t, "deny", `rg foo ~/.kube`, "a named secret directory")
	checkCodex(t, "deny", `rg foo ~/.secrets/`, "the secrets directory")
	checkCodex(t, "deny", `rg foo .env`, "a named dotenv file")
	checkCodex(t, "deny", `rg -e foo ~/.kube/config`, "the pattern on the flag, the secret is the path")
	checkCodex(t, "deny", `rg -f ~/.env src`, "patterns read from a secret")
	checkCodex(t, "deny", `rg --file=.env src`, "patterns read from a secret, attached")
	checkCodex(t, "deny", `rg -nf ~/.env src`, "pattern file in a bundle")
	checkCodex(t, "deny", `cd ~/.secrets && rg foo`, "search inside a secret directory")
}

func TestCodexKeepsEveryOtherRule(t *testing.T) {
	checkCodex(t, "deny", `ag foo`, "only rg is relaxed")
	checkCodex(t, "deny", `ack foo`, "only rg is relaxed")
	checkCodex(t, "deny", `grep -r foo .`, "grep recursion stays denied")
	checkCodex(t, "deny", `cat ~/.env`, "a direct read")
	checkCodex(t, "deny", `git commit --no-verify -m x`, "the bypass class")
}

func TestClaudeStillDeniesRg(t *testing.T) {
	check(t, "deny", `rg foo`, "Claude searches with its Grep tool")
	check(t, "deny", `rg -n TODO src`, "Claude searches with its Grep tool")
}
