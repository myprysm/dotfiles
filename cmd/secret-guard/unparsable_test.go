package main

import (
	"strings"
	"testing"
)

// A parse failure filed under `bypass` reached the agent as a --no-verify
// refusal when the command held an apostrophe inside '...' and markdown bold
// (#157).
func TestUnparsableCommandGetsItsOwnCategory(t *testing.T) {
	for _, src := range []string{
		`printf 'a (b'c d) **x**'`,
		"gh pr create --title t --body \"$(printf 'Garde l'ancien chemin (sans) **Door:** ouvert')\"",
	} {
		cat, why := decide(src)
		if cat != catUnparsable {
			t.Errorf("%q: got %v, want unparsable", src, cat)
		}
		if !strings.Contains(strings.Join(why, "\n"), "parses as neither") {
			t.Errorf("%q: reason %q lacks \"parses as neither\"", src, why)
		}
	}

	if cat, _ := decide(`for f (*.php) cat ~/.env`); cat != catSecret {
		t.Errorf("a secret named in unparsable text: got %v, want secret", cat)
	}
}
