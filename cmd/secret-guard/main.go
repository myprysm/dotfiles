// Command secret-guard decides whether one shell command would read the
// contents of a secret file, search recursively through files it never names,
// skip the estate-wide gitleaks pre-commit scan, or move a secret path off this
// machine.
//
// It reads the command on stdin and answers on stdout:
//
//	allow                 exit 0
//	deny <category>\n…    exit 1
//
// Any other exit code, or a first line that is neither, means this binary could
// not decide. The calling hook then falls back to its own shell splitter, which
// is always present. That contract is why a crash here degrades to yesterday's
// behaviour instead of to no guard at all.
//
// A command that does not PARSE fails closed where it looks dangerous and
// degrades to the caller otherwise: it is denied when its raw text names a
// secret or matches a bypass, recursive or transfer pattern, and answers
// "undecided" when it names nothing. See decide() for why a flat denial was
// wrong - mvdan's zsh mode refuses syntax that real zsh accepts.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// maxInput bounds the work a crafted command can ask for. The parser is linear
// at roughly 12 ms/MB, so this is not a latency guard: it is a ceiling on the
// tree depth that has been measured to overflow the Go stack (~1.5 MB, 100k to
// 500k nodes). Real traffic is nowhere near it - p90 is 634 bytes, and only
// 0.07% of commands exceed 8 KB.
const maxInput = 256 << 10

// exitUndecided tells the caller to fall back. Distinct from 0 and 1 so that
// the fallback is chosen deliberately rather than by reading empty stdout.
const exitUndecided = 3

// parse reads the command as ZSH first, because zsh 5.9 is what the agent's
// Bash tool actually executes on this estate. Parsing as bash was a real hole:
// any zsh-only token - an anonymous function, `${(f)x}`, `=(…)` - failed to
// parse, and handing the whole command to the shell floor turned the guard off
// for it, since the floor's reader list is a strict subset of this one's.
//
// The two dialects are not supersets of each other, so a construct zsh mode
// does not implement is retried as bash. `exec {fd}<file` is the measured case:
// real zsh accepts it and mvdan's zsh mode does not. Three other bash-only
// constructs that fail here - `${x^^}`, `${!prefix*}`, `coproc name { … }` -
// were checked against `zsh -n`, which rejects all three, so failing on them
// costs nothing.
func parse(src string) (*syntax.File, error) {
	f, err := parseAs(syntax.LangZsh, src)
	if err == nil {
		return f, nil
	}
	var lang syntax.LangError
	if errors.As(err, &lang) {
		if bashFile, bashErr := parseAs(syntax.LangBash, src); bashErr == nil {
			return bashFile, nil
		}
	}
	return nil, err
}

func parseAs(lang syntax.LangVariant, src string) (*syntax.File, error) {
	p := syntax.NewParser(syntax.Variant(lang), syntax.KeepComments(false))
	return p.Parse(strings.NewReader(src), "cmd")
}

func main() {
	dir := flag.String("secretsdir", "", "absolute path of the machine-local secrets directory")
	flag.Parse()
	SecretsDir = strings.TrimRight(*dir, "/")

	in, err := io.ReadAll(io.LimitReader(os.Stdin, maxInput+1))
	if err != nil {
		fmt.Fprintln(os.Stderr, "secret-guard: cannot read stdin:", err)
		os.Exit(exitUndecided)
	}
	if len(in) > maxInput {
		// Past the ceiling nothing can be judged, so the caller decides.
		fmt.Fprintln(os.Stderr, "secret-guard: command exceeds the size ceiling")
		os.Exit(exitUndecided)
	}

	// A panic here is a bug, not a verdict. Turning it into the undecided exit
	// hands the command to the shell floor instead of letting an unhandled
	// node type read as silence. syntax.Walk panics on a node type it does not
	// know, which is exactly the kind of surprise this catches.
	defer func() {
		if r := recover(); r != nil {
			fmt.Fprintln(os.Stderr, "secret-guard: internal error:", r)
			os.Exit(exitUndecided)
		}
	}()

	cat, reasons := decide(string(in))
	if cat == catUndecided {
		fmt.Fprintln(os.Stderr, "secret-guard: undecided:", strings.Join(reasons, "; "))
		os.Exit(exitUndecided)
	}
	if cat == catNone {
		fmt.Println("allow")
		os.Exit(0)
	}
	fmt.Println("deny", cat)
	for _, r := range reasons {
		fmt.Println(r)
	}
	os.Exit(1)
}

// decide is the whole policy, exposed for the corpus tests.
func decide(src string) (category, []string) {
	braceBudget = maxBraceTotal
	c := &checker{src: src}
	f, err := parse(src)
	if err != nil {
		// Neither dialect could read it. The old answer here was a flat denial,
		// on the reasoning that malformed shell is shell the interpreter would
		// refuse too, so refusing it cost nothing.
		//
		// That reasoning does not hold. `for f (*.php) php -l $f` is VALID zsh -
		// `zsh -n` accepts it - and mvdan's zsh mode cannot parse it, so a
		// command the shell runs happily was refused as unreadable. The shell
		// floor allows it, which made this binary a REGRESSION against the layer
		// it fronts.
		//
		// So an unreadable command now fails closed only where it looks
		// dangerous - its raw text names a secret, or matches one of the coarse
		// bypass, recursive and transfer patterns - and otherwise returns the
		// undecided exit, which hands it to the floor. The floor is always
		// present, so degrading to it is the same guarantee that covers a crash
		// here or an over-long input.
		if hitsSecretText(src) {
			c.deny(catSecret, "the command parses as neither zsh nor bash and its text names a secret path: "+err.Error())
			return c.verdict()
		}
		if matchAny(parseFailDangerRes, src) {
			c.deny(catBypass, "the command parses as neither zsh nor bash and its text matches a bypass, recursive or transfer pattern: "+err.Error())
			return c.verdict()
		}
		return catUndecided, []string{"the command parses as neither zsh nor bash: " + err.Error()}
	}
	c.run(f)
	return c.verdict()
}
