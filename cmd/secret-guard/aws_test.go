package main

import "testing"

func TestAwsDirectory(t *testing.T) {
	check(t, "deny", `cat ~/.aws/credentials`, "the static credentials file")
	check(t, "deny", `cat ~/.aws/login/cache/abc.json`, "the aws login session cache")
	check(t, "deny", `cat ~/.aws/sso/cache/abc.json`, "the SSO token cache")
	check(t, "deny", `cat ~/.aws/config`, "the config, denied with the directory")
	check(t, "deny", `cat "$HOME/.aws/login/cache/abc.json"`, "the cache under a quoted HOME")
	check(t, "deny", `jq . ~/.aws/login/cache/abc.json`, "a filter over a cache file")
	check(t, "deny", `cat ~/.aws/login/cache/*`, "a glob inside the cache")
	check(t, "deny", `cat ~/.a*s/credentials`, "a glob on the directory name")
	check(t, "deny", `tar czf - ~/.aws`, "an archive of the bare directory")
	check(t, "deny", `cat ~/.aws`, "the bare directory name")

	check(t, "allow", `aws sts get-caller-identity`, "an AWS call that names no file")
	check(t, "allow", `aws configure list-profiles`, "listing profiles names no file")
	check(t, "allow", `cat aws/main.tf`, "a Terraform root named aws")
	check(t, "allow", `cat ~/.aws-notes`, "a different name that starts the same")
}
