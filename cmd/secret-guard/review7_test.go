package main

import "testing"

// TestEnvironmentNameStems settles the one trade round 5 left to the operator
// and round 6 answered.
//
// `.env.<source-extension>` is neutralised because `old.env.js` and
// `config.env.ts` are ordinary modules, not dotenv files. That neutraliser then
// swallowed `prod.env.php`, which is credentials - and `.env.php` was Laravel
// 4's own format for them, so this estate is exactly where the spelling turns
// up.
//
// The two look identical in shape: a word, a dot, `env`, a dot, a source
// extension. What separates them is the STEM. `prod`, `dev`, `staging` and
// their siblings name an environment; `config`, `old` and `vite` name a module.
// Special-casing that short list keeps every module readable and closes every
// environment spelling, which is why it was taken over the alternative of
// dropping `php` from the extension list and refusing `config.env.php`.
func TestEnvironmentNameStems(t *testing.T) {
	// An environment name in front of it makes it a dotenv file.
	check(t, "deny", `cat prod.env.php`, "Laravel 4's credential format")
	check(t, "deny", `cat production.env.php`, "the long spelling")
	check(t, "deny", `cat staging.env.js`, "another environment, another extension")
	check(t, "deny", `cat local.env.ts`, "the local environment")
	check(t, "deny", `head -1 config/prod.env.php`, "one directory down")
	check(t, "deny", `cat .env.php`, "no stem at all is still a dotenv file")
	check(t, "deny", `cat .env.vue`, "and any source extension after it")

	// A module name in front of it leaves it an ordinary source file.
	check(t, "allow", `cat config.env.php`, "an ordinary Laravel module")
	check(t, "allow", `cat old.env.js`, "an ordinary javascript module")
	check(t, "allow", `cat vite.env.ts`, "vite's own typing module")
	check(t, "allow", `diff old.env.js new.env.js`, "two of them")
	check(t, "allow", `cat src/env.d.ts`, "the ambient declaration file")
}
