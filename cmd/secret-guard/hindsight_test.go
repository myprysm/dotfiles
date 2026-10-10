package main

import "testing"

// The whole of ~/.hindsight is secret (#128): the runtime config holds the
// token, and the logs are treated as holding it until shown otherwise.
func TestHindsightDirectory(t *testing.T) {
	check(t, "deny", `cat ~/.hindsight/coding-agent.json`, "the runtime config with the token")
	check(t, "deny", `cat ~/.hindsight/coding-agents/package.json`, "a file of the staged runtime")
	check(t, "deny", `cat ~/.hindsight/coding-agents-logs/hooks.log`, "a runtime log")
	check(t, "deny", `cat ~/.hindsight/claude-code.json`, "the legacy plugin config")
	check(t, "deny", `jq .version $HOME/.hindsight/coding-agents/package.json`, "a filter over a runtime file")
	check(t, "deny", `cat ~/.hind*/coding-agent.json`, "a glob on the directory name")
	check(t, "deny", `cat ~/.hindsight/coding-agents/*`, "a glob inside the runtime")

	check(t, "allow", `cat ~/.claude/settings.json.hindsight-backup`, "a name that only contains the word")
	check(t, "allow", `cat home/private_dot_hindsight/modify_private_coding-agent.json`, "the chezmoi source of the config")
}
