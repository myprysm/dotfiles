package main

import "testing"

// Round 2. Each case below is a defect the second pair of adversarial reviews
// found in the round-1 FIXES, confirmed by executing it. Three of the four were
// regressions introduced by those fixes, which is why each one keeps a probe.

func TestReviewLeadingWildcardGlobs(t *testing.T) {
	// Requiring a pattern to begin with a literal removed the `cat *.yaml`
	// false positive and opened a whole family of reads in exchange: one
	// leading wildcard disabled the candidate check entirely. Each of these
	// was confirmed printing a real file.
	check(t, "deny", `cat *env`, "a wildcard before the secret suffix")
	check(t, "deny", `cat *ubeconfig`, "a wildcard eating the first character")
	check(t, "deny", `cat *ault.yml`, "a wildcard reaching into the vault stem")
	check(t, "deny", `cat *.en?`, "a wildcard at each end")
	check(t, "deny", `cat *.tfstat?`, "the same for a state file")
	check(t, "deny", `cat [k]ubeconfig`, "a character class standing for the first letter")
	check(t, "deny", `head *env`, "a reader other than cat")
	check(t, "deny", `cat ~/.local/share/*f2a1c94-8d3e-4b7a-9f10-2c5e8a7b3d61/token`,
		"a wildcard inside the secrets-directory UUID")
	// The false positive that prompted the bad fix must stay fixed. What makes
	// these safe is that their literals fall entirely inside a generic
	// EXTENSION, pinning nothing of the vault stem.
	check(t, "allow", `cat *.yaml`, "the estate's commonest extension")
	check(t, "allow", `cat k8s/*.yaml`, "an ordinary manifest directory")
	check(t, "allow", `cat *.yml`, "the other spelling")
	check(t, "allow", `diff a/*.yaml b/*.yaml`, "two manifest globs")
	check(t, "allow", `cat ~/.config/*`, "an ordinary config directory")
	check(t, "allow", `cat *.tf`, "terraform sources")
	check(t, "allow", `cat *.json`, "json files")
}

func TestReviewArchiveSpellings(t *testing.T) {
	// The destination rides on the flag bundle in `-cf-`, hides behind a
	// device name in `/dev/stdout`, and `pax`/`cpio` spell "create" with
	// letters the first fix did not know.
	check(t, "deny", `tar -cf- . | base64`, "the destination attached to the bundle")
	check(t, "deny", `tar --create -f /dev/fd/1 . | base64`, "stdout by file descriptor")
	check(t, "deny", `tar cf /dev/stdout . | base64`, "stdout by device name")
	check(t, "deny", `pax -w . | base64`, "pax spells create -w")
	check(t, "deny", `ls | cpio -o`, "cpio spells create -o")
	check(t, "allow", `tar -czf /tmp/b.tar.gz src/`, "an archive written to a file")
	check(t, "allow", `tar -xzf release.tgz`, "extracting is not archiving")
}

func TestReviewWrappedCommandOperands(t *testing.T) {
	// Reparsing the quoted command string and then returning threw away the
	// operands that belong to it. `watch 'cmd -flag' file` and
	// `parallel 'cat {}' ::: files` are the idiomatic spellings of both tools.
	check(t, "deny", `watch 'cat -v' ~/.env`, "operand after a two-word command string")
	check(t, "deny", `watch -n1 'head -5' ~/.envrc`, "the same behind an option")
	check(t, "deny", `sudo 'cat -n' ~/.env`, "the same behind sudo")
	check(t, "deny", `timeout 5 'cat -v' ~/.env`, "the same behind timeout")
	check(t, "deny", `parallel 'cat {}' ::: ~/.env`, "parallel's operand syntax")
	check(t, "allow", `watch -n 5 'kubectl get pods'`, "an ordinary watched command")
	check(t, "allow", `parallel 'gzip {}' ::: logs/*.log`, "an ordinary parallel run")
}

func TestReviewMountedDirectories(t *testing.T) {
	// A mount is written `src:dst[:opts]`, so the source is followed by a
	// colon rather than by a separator and the directory patterns missed it.
	check(t, "deny", `docker run -v ~/.kube:/k alpine cat /k/config`, "source is a secret directory")
	check(t, "deny", `podman run -v ~/.talos:/t alpine cat /t/config`, "the podman spelling")
	check(t, "deny", `docker run -v ~/.kube:/root/.kube alpine sh`, "secret on both sides")
	check(t, "deny", `docker run -v ~/.env:/e:ro alpine cat /e`, "a mount with options")
	check(t, "allow", `docker run -v $(pwd):/app node npm test`, "mounting the working directory")
	check(t, "allow", `docker run -v /tmp/cache:/cache alpine true`, "an ordinary cache mount")
}

func TestReviewRecursiveByDefault(t *testing.T) {
	// rgrep carries no -r because it IS grep -r, so routing it through the
	// grep arm meant nothing ever fired.
	check(t, "deny", `rgrep SECRET ~`, "rgrep is recursive by definition")
	check(t, "deny", `rgrep -n SECRET ~`, "with an option in front")
}

func TestReviewReadOnlyGitConfig(t *testing.T) {
	// Reading the value back changes nothing; only the writing forms bypass.
	check(t, "allow", `git config --get core.hooksPath`, "reading the value")
	check(t, "allow", `git config --get-all core.hooksPath`, "reading every value")
	check(t, "allow", `git config --list`, "listing the whole config")
	check(t, "deny", `git config core.hooksPath /dev/null`, "writing a value")
	check(t, "deny", `git config --global core.hooksPath /tmp/empty`, "the global form")
	check(t, "deny", `git config --unset core.hooksPath`, "unsetting it")
	check(t, "deny", `git config core.hooksPath=/tmp/x`, "the joined spelling")
}

func TestReviewFindNamesWithoutReading(t *testing.T) {
	// find NAMES files; it only reads through -exec. Checking every operand
	// refused a search that opens nothing.
	check(t, "allow", `find . -name '.env*' -print`, "searching for a name")
	check(t, "allow", `find ~ -name kubeconfig`, "the same for a kubeconfig")
	check(t, "allow", `find . -name '*.go' -newer go.mod`, "an ordinary search")
	check(t, "deny", `find . -name '*.env' -exec cat {} \;`, "-exec with a reader still reads")
}

func TestReviewParentSegment(t *testing.T) {
	// A `..` detour names the same file as the plain spelling.
	check(t, "deny", `cat ~/.kube/x/../config`, "a parent-directory detour")
	check(t, "deny", `cat ~/.talos/a/b/../../config`, "two of them")
	check(t, "allow", `cat ../README.md`, "an ordinary relative path")
	check(t, "allow", `cat ../../src/main.go`, "two ordinary levels")
}

// TestReviewDeliberateOverDenials records the refusals that are policy rather
// than defect, so nobody "fixes" one without deciding to.
func TestReviewDeliberateOverDenials(t *testing.T) {
	// Reading anything inside a directory whose contents are secret. Which
	// file it is cannot be known once the command has changed into it.
	check(t, "deny", `cd ~/.hindsight && cat README.md`, "a harmless file in a secret directory")
	// `git grep` was recorded here as deliberate: it reads every tracked file
	// and names none, which is the whole reason the recursive class exists.
	//
	// MEASUREMENT OVERTURNED IT. Run against 10,091 real commands from this
	// estate's own sessions, `git grep` accounted for 407 refusals - 4% of
	// every command issued - for the weakest security value in the class. It
	// searches only TRACKED files, which carry no secret by construction,
	// since the gitleaks hook this same guard protects is what keeps them out;
	// and the agent can already read any tracked file one at a time. A guard
	// that refuses one command in twenty-five gets switched off, and a guard
	// that is off protects nothing. See TestGitGrepIsAllowed.
	check(t, "allow", `git grep TODO -- src/`, "tracked files carry no secret by construction")
	// A secret name used as a search pattern for sed or awk was recorded here
	// as policy, on the grounds that neither tool had an option grammar in this
	// file. Round 4 reversed it: sed and awk DO have a script grammar, it is
	// simply not jq's, and refusing every `sed 's/\.env/x/' Makefile` is the
	// single commonest false positive a guard of this kind produces. The
	// script is now recognised by its own shape - see isProgramText - so the
	// case below reads as a program rather than as a filename.
	check(t, "allow", `sed -i 's/.env/.environment/' README.md`, "a secret name inside a sed script")
	// A glob that really can expand to a secret name.
	check(t, "deny", `cat *config*`, "a substring glob reaching kubeconfig")
}
