package main

import "testing"

func TestPerVaultTokenFiles(t *testing.T) {
	check(t, "deny", `cat ~/.vault-token-home`, "the home Vault token")
	check(t, "deny", `cat ~/.vault-token-kloud`, "the kloud Vault token")
	check(t, "deny", `cat "$HOME/.vault-token-kloud"`, "the token under a quoted HOME")
	check(t, "deny", `cat '.vault-token-home'`, "the quoted spelling")
	check(t, "deny", `cat ~/.vault-token-*`, "a glob over both tokens")
	check(t, "deny", `cat ~/.v*-kloud`, "a glob that drops the vault stem")
	check(t, "deny", `cat ~/.*token-home`, "a dot-led glob on the suffix")
	check(t, "deny", `cat ~/.[v]ault-token-home`, "a bracket class on the first letter")

	check(t, "allow", `cat *-home`, "a glob that cannot expand to a dotfile")
	check(t, "allow", `jq '.vault-token' x.json`, "a jq filter, not a filename")
}
