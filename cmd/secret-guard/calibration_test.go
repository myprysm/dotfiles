package main

import "testing"

// Calibration against MEASURED traffic rather than against imagined attacks.
//
// Six adversarial review rounds tuned this guard for safety and left one thing
// unmeasured: how much ordinary work it refuses. Run against 10,091 unique
// commands taken from this estate's own sessions, it denied 19.6% of them, and
// almost all of that was the recursive-search class rather than anything the
// six rounds were about. A guard that refuses one command in five is a guard
// somebody switches off, and a guard that is off protects nothing.
//
// The three changes below came from that measurement. Each overturned a
// decision made earlier on reasoning alone; each records the number that
// overturned it, so the next person to revisit one argues with the evidence
// rather than with the argument.

// TestGitGrepIsAllowed: 407 refusals, 4% of every real command.
//
// `git grep` was put in the recursive class for consistency with `rg`: both
// read files they never name. The consistency is real and the risk is not.
// `git grep` searches only TRACKED files, and a tracked file carrying a secret
// is precisely what the gitleaks pre-commit hook - which this same guard
// protects - exists to prevent. The agent can also already read any tracked
// file one at a time.
func TestGitGrepIsAllowed(t *testing.T) {
	check(t, "allow", `git grep TODO`, "the commonest spelling")
	check(t, "allow", `git grep -n password`, "a search for a risky word is still a search")
	check(t, "allow", `git grep TODO -- src/`, "with a pathspec")
	check(t, "allow", `git grep -i "api_key" -- '*.php'`, "a case-insensitive search over php")
	// The operands are still judged, so naming a secret is still a read.
	check(t, "deny", `git grep x -- ~/.env`, "a pathspec naming a secret")
	// Everything else in the class is unchanged.
	check(t, "deny", `rg TODO`, "ripgrep still searches the whole tree")
	check(t, "deny", `grep -r TODO .`, "and so does grep -r")
}

// TestDirenvExecIsNarrowed: 38 refusals, none of them an environment printer.
//
// `direnv exec DIR CMD` loads .envrc and runs CMD. Refusing the verb assumed
// that whether CMD prints the environment is unknowable. It is not, for the
// short list of commands whose whole job is to print it.
func TestDirenvExecIsNarrowed(t *testing.T) {
	check(t, "allow", `direnv exec . make build`, "an ordinary build")
	check(t, "allow", `direnv exec . npm run dev`, "an ordinary dev server")
	check(t, "allow", `direnv exec /srv/app php artisan migrate`, "an ordinary migration")
	// The forms that print the loaded environment back out still deny.
	check(t, "deny", `direnv exec . env`, "env prints every variable")
	check(t, "deny", `direnv exec . printenv`, "so does printenv")
	check(t, "deny", `direnv exec . set`, "and so does set")
	// `direnv export` prints the environment whatever follows it.
	check(t, "deny", `direnv export bash`, "export is the printing verb")
}

// TestTemplateSuffixes: `.env.j2` appeared 9 times in real traffic.
//
// A template carries placeholders; the RENDERED file is the secret, and it does
// not carry the suffix. `.env.example` was already neutralised for exactly this
// reason - the list was simply short by the suffixes this estate's ansible
// work actually uses.
func TestTemplateSuffixes(t *testing.T) {
	check(t, "allow", `cat .env.j2`, "an ansible template")
	check(t, "allow", `cat roles/app/templates/.env.j2`, "the same, in its usual home")
	check(t, "allow", `cat .env.jinja2`, "the long spelling")
	check(t, "allow", `cat .env.tpl`, "a generic template suffix")
	check(t, "allow", `cat .env.tftpl`, "terraform's spelling")
	check(t, "allow", `diff .env.example .env.j2`, "comparing two templates")
	check(t, "allow", `cat .env.production.j2`, "a template with an environment segment")
	// The rendered file is still the secret.
	check(t, "deny", `cat .env`, "the rendered file")
	check(t, "deny", `cat .env.production`, "and its environment variants")
	// A suffix that is not a template suffix is not neutralised.
	check(t, "deny", `cat .env.bak`, "a backup of the real thing")
	check(t, "deny", `cat .env.local`, "a real dotenv file")
}
