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

	check(t, "deny", `aws sts get-session-token`, "root mints and prints a session")
	check(t, "deny", `aws --profile myprysm sts get-session-token`, "a global option before the service")
	check(t, "deny", `aws --endpoint-url https://sts.amazonaws.com sts get-session-token`, "an endpoint before the service")
	check(t, "deny", `aws --query Credentials sts get-session-token`, "a query before the service")
	check(t, "deny", `aws --color off configure export-credentials`, "a color option before the service")
	check(t, "deny", `aws --cli-read-timeout 5 --ca-bundle b.pem sts get-session-token`, "two global options")
	check(t, "deny", `aws sts get-federation-token --name x`, "a federation token")
	check(t, "deny", `aws sts assume-role --role-arn r --role-session-name s`, "an assumed role")
	check(t, "deny", `aws sts assume-role-with-web-identity --role-arn r`, "an assumed role, web identity")
	check(t, "deny", `aws sso get-role-credentials --role-name r`, "SSO role credentials")
	check(t, "deny", `aws ecr get-login-password`, "a registry password")
	check(t, "deny", `aws ecr-public get-login-password`, "a public registry password")

	check(t, "allow", `aws sts get-caller-identity`, "an AWS call that names no file")
	check(t, "allow", `aws configure list-profiles`, "listing profiles names no file")
	check(t, "allow", `cat aws/main.tf`, "a Terraform root named aws")
	check(t, "allow", `cat ~/.aws-notes`, "a different name that starts the same")
}
