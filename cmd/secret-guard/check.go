package main

import (
	"strings"

	"mvdan.cc/sh/v3/pattern"
	"mvdan.cc/sh/v3/syntax"
)

type category int

// Ordered by the precedence the shell floor applies: the recursive, bypass and
// transfer classes each carry their own explanation, and the first that fires
// is the one the operator is shown.
const (
	catRecursive category = iota
	catBypass
	catTransfer
	catSecret
	catNone
	// catUndecided is not a verdict. It means this binary could not read the
	// command at all, so the caller must decide - see decide() for the one
	// case that reaches it.
	catUndecided
)

func (c category) String() string {
	switch c {
	case catRecursive:
		return "recursive"
	case catBypass:
		return "bypass"
	case catTransfer:
		return "transfer"
	case catSecret:
		return "secret"
	}
	return "none"
}

type finding struct {
	cat category
	why string
}

// maxReparseDepth bounds `eval` inside `eval` inside `bash -c`. A guard must
// not be the thing that runs out of stack.
const maxReparseDepth = 8

type checker struct {
	src      string
	findings []finding
	depth    int

	// Set once a `cd` or `pushd` in this command has entered a directory whose
	// contents are secret. Every reader after it is reading inside that
	// directory, however innocent the bare filename looks.
	inSecretDir bool

	// Functions whose body reads a file. The path then arrives at the CALL
	// site, where no reader is named: `f(){ cat "$1"; }; f <secret>`.
	readerFuncs map[string]bool

	// Destinations a secret was copied or linked to earlier in this command
	// line. A copy crosses no boundary on its own, which is why it is allowed
	// - but `cp <secret> /tmp/x && cat /tmp/x` reads it in one line, and
	// neither half alone says so.
	tainted map[string]bool

	// Destinations a secret DIRECTORY was copied to. A directory taint has to
	// be a PREFIX rather than an exact string: `cp -r ~/.kube /tmp/k` puts
	// every file in the directory under /tmp/k, and the read that follows names
	// `/tmp/k/config`, which the exact map never held.
	taintedDirs map[string]bool

	// The environment the CURRENT call is run with, however it was spelled:
	// `HOME=/tmp git commit` puts the pair in CallExpr.Assigns and `env
	// HOME=/tmp git commit` puts it in argv. Reset per call.
	envNames map[string]bool
	envWiped bool // `env -i`, `env --ignore-environment`, `env -`
}

func (c *checker) deny(cat category, why string) {
	c.findings = append(c.findings, finding{cat: cat, why: why})
}

// verdict returns the highest-precedence category found, or catNone.
func (c *checker) verdict() (category, []string) {
	best := catNone
	for _, f := range c.findings {
		if f.cat < best {
			best = f.cat
		}
	}
	var why []string
	for _, f := range c.findings {
		why = append(why, f.cat.String()+": "+f.why)
	}
	return best, why
}

func (c *checker) check(f flatWord, why string) {
	if hitsSecretFlat(f) {
		c.deny(catSecret, why)
	}
}

// checkOperand is check for a word standing where a READER expects a filename.
// See hitsSecretOperand: there the contextual patterns apply whether or not the
// word carries a path separator, because a tool with a filter or program slot
// has already skipped it before its operands reach here.
func (c *checker) checkOperand(f flatWord, why string) {
	if hitsSecretOperand(f) {
		c.deny(catSecret, why)
	}
}

func (c *checker) checkText(s, why string) {
	if hitsSecretText(s) {
		c.deny(catSecret, why)
	}
}

// textGate handles a construct this cannot resolve - a substitution payload, an
// eval of one, a redirect from one. It fails closed only when the raw command
// text names a secret, which is the same gate the shell floor applies before it
// consults its own fallback. Denying every unresolvable construct outright
// would refuse ordinary work that merely happens to contain one.
func (c *checker) textGate(why string) {
	if hitsSecretText(c.src) {
		c.deny(catSecret, why+" (unresolvable, secret named in the command text)")
	}
}

// ---------- entry ----------

func (c *checker) run(node syntax.Node) {
	c.collectReaderFuncs(node)
	syntax.Walk(node, func(n syntax.Node) bool {
		switch x := n.(type) {
		case *syntax.Stmt:
			c.stmtRedirs(x)
		case *syntax.CallExpr:
			c.call(x)
		case *syntax.DeclClause:
			for _, a := range x.Args {
				c.assign(a)
			}
		case *syntax.WordIter:
			// A `for` list binds the path to a variable and the body reads
			// `$var`, so no fragment ever holds both the reader and the path.
			for _, w := range x.Items {
				c.check(flatten(w), "for-list carries a secret path (dataflow)")
			}
		case *syntax.ForClause:
			c.forLoop(x)
		case *syntax.BinaryCmd:
			c.pipedLoop(x)
		}
		return true
	})
}

// pipedLoop catches the pipeline spelling of a recursive read. `find . -type f
// | while read f; do cat "$f"; done` reads every file in the tree and names not
// one of them, and only the `for` spelling was checked - the loop reads a
// variable and the walker sits on the OTHER side of the pipe, so neither half
// is a read of anything on its own. It printed every canary in the tree.
//
// The right-hand side has to be a LOOP, not merely a reader. `find . -name x |
// head -5` pages the list of NAMES and reads no file at all, so a rule keyed on
// "a reader downstream of a walker" would refuse ordinary work.
func (c *checker) pipedLoop(x *syntax.BinaryCmd) {
	if x.Op != syntax.Pipe && x.Op != syntax.PipeAll {
		return
	}
	if x.Y == nil || !loopReads(x.Y.Cmd) {
		return
	}
	if !walkerInNode(x.X) {
		return
	}
	c.deny(catRecursive, "a loop over a tree walk reads files it never names")
}

// loopReads reports whether a command is a loop whose body reads a file.
func loopReads(cmd syntax.Command) bool {
	switch l := cmd.(type) {
	case *syntax.WhileClause:
		return bodyReads(l.Do)
	case *syntax.ForClause:
		return bodyReads(l.Do)
	}
	return false
}

// walkerInNode reports whether any call anywhere under a node walks a tree.
func walkerInNode(n syntax.Node) bool {
	found := false
	syntax.Walk(n, func(m syntax.Node) bool {
		if call, ok := m.(*syntax.CallExpr); ok && isWalkerCall(call) {
			found = true
		}
		return !found
	})
	return found
}

// bodyReads reports whether a loop body contains a call to a reader. The path
// it reads is a variable the loop bound, so the reader is all there is to see.
func bodyReads(stmts []*syntax.Stmt) bool {
	for _, st := range stmts {
		reads := false
		syntax.Walk(st, func(n syntax.Node) bool {
			call, ok := n.(*syntax.CallExpr)
			if !ok || len(call.Args) == 0 {
				return true
			}
			words := make([]flatWord, len(call.Args))
			for i, a := range call.Args {
				words[i] = flatten(a)
			}
			if idx := unwrapWrappers(nil, words); idx < len(words) && isReader(base(words[idx].lit)) {
				reads = true
			}
			return !reads
		})
		if reads {
			return true
		}
	}
	return false
}

// collectReaderFuncs records the functions whose body reads a file, so a call
// to one can be judged on its own operands. Without it the reader and the path
// never appear together: the body says `cat "$1"` and the call says
// `f <secret>`, and neither alone is a read.
func (c *checker) collectReaderFuncs(node syntax.Node) {
	c.readerFuncs = map[string]bool{}
	syntax.Walk(node, func(n syntax.Node) bool {
		fd, ok := n.(*syntax.FuncDecl)
		if !ok || fd.Name == nil {
			return true
		}
		syntax.Walk(fd.Body, func(m syntax.Node) bool {
			call, ok := m.(*syntax.CallExpr)
			if !ok || len(call.Args) == 0 {
				return true
			}
			words := make([]flatWord, len(call.Args))
			for i, w := range call.Args {
				words[i] = flatten(w)
			}
			if idx := unwrapWrappers(nil, words); idx < len(words) {
				if b := base(words[idx].lit); isReader(b) {
					c.readerFuncs[strings.ToLower(fd.Name.Value)] = true
				}
			}
			return true
		})
		return true
	})
}

// forLoop catches the loop spelling of a recursive read. `for f in $(find .
// -type f); do cat "$f"; done` reads every file in the tree and names not one
// of them: the list is an unresolved substitution and the body reads a
// variable, so neither half on its own is a read of anything.
//
// Both halves are required, which is what keeps this off ordinary work: a loop
// over a tree walk that does not read - `for f in $(find . -name '*.php'); do
// php -l "$f"; done` would read, but `… do echo "$f"; done` does not - and a
// loop over a list that no walker produced are both untouched.
func (c *checker) forLoop(x *syntax.ForClause) {
	wi, ok := x.Loop.(*syntax.WordIter)
	if !ok {
		return
	}
	walker := false
	for _, w := range wi.Items {
		if isWalkerSubst(w) {
			walker = true
			break
		}
	}
	if !walker {
		return
	}
	if bodyReads(x.Do) {
		c.deny(catRecursive, "a loop over a tree walk reads files it never names")
	}
}

// redirectedLoop catches the third spelling of the same read: `while read f; do
// cat "$f"; done < <(find . -type f)` feeds the walk in through a REDIRECTION
// rather than through a pipe or a for-list. It printed every canary in the tree.
func (c *checker) redirectedLoop(s *syntax.Stmt) {
	if len(s.Redirs) == 0 || !loopReads(s.Cmd) {
		return
	}
	for _, r := range s.Redirs {
		if r.Word != nil && isWalkerSubst(r.Word) {
			c.deny(catRecursive, "a loop over a tree walk reads files it never names")
			return
		}
	}
}

// isWalkerSubst reports whether a word is built from a command substitution
// over a tool that ENUMERATES a tree. Such a tool prints names rather than
// contents, so it is harmless on its own - but a reader handed its output reads
// every file it found, and the command text spells out none of them.
// `cat $(find . -type f)` printed a real canary.
func isWalkerSubst(w *syntax.Word) bool {
	if w == nil {
		return false
	}
	found := false
	syntax.Walk(w, func(n syntax.Node) bool {
		if call, ok := n.(*syntax.CallExpr); ok && isWalkerCall(call) {
			found = true
		}
		return !found
	})
	return found
}

// isWalkerCall reports whether one call enumerates files. `git` is asked for
// the subcommand that makes it one, because every other git subcommand
// enumerates nothing.
func isWalkerCall(call *syntax.CallExpr) bool {
	if len(call.Args) == 0 {
		return false
	}
	words := make([]flatWord, len(call.Args))
	for i, a := range call.Args {
		words[i] = flatten(a)
	}
	idx := unwrapWrappers(nil, words)
	if idx >= len(words) {
		return false
	}
	b := base(words[idx].lit)
	if treeWalkers[b] {
		return true
	}
	rest := words[idx+1:]
	switch b {
	case "git":
		for _, a := range rest {
			w := strings.ToLower(stripAll(a.lit))
			if isFlag(w) {
				continue
			}
			return w == "ls-files" || w == "ls-tree"
		}
	}
	return false
}

// ---------- redirections ----------

func (c *checker) stmtRedirs(s *syntax.Stmt) {
	c.redirectedLoop(s)
	cmdBase, isInterpCmd := "", false
	if cc, ok := s.Cmd.(*syntax.CallExpr); ok && len(cc.Args) > 0 {
		words := make([]flatWord, len(cc.Args))
		for i, w := range cc.Args {
			words[i] = flatten(w)
		}
		idx := unwrapWrappers(nil, words)
		if idx < len(words) {
			cmdBase = base(words[idx].lit)
			isInterpCmd = isInterp(cmdBase)
		}
	}
	for _, r := range s.Redirs {
		switch r.Op {
		case syntax.RdrOut, syntax.RdrClob, syntax.RdrAll:
			// `printf '' > .git/hooks/pre-commit` empties the hook without
			// naming rm, chmod or core.hooksPath, and an empty hook runs no
			// gitleaks scan. Appending is deliberately absent: it leaves the
			// existing script in front of whatever is added, so it disables
			// nothing.
			if r.Word != nil && hookFileRe.MatchString(stripAll(flatten(r.Word).lit)) {
				c.deny(catBypass, "redirecting output over the pre-commit hook skips the gitleaks scan")
			}

		case syntax.RdrIn, syntax.RdrInOut:
			f := flatten(r.Word)
			if f.hasSubst {
				c.textGate("input redirection from a substitution")
			}
			c.checkOperand(f, "input redirection from a secret path")
			// A copy made earlier in this command line, now being read through
			// a redirection rather than as an operand. The taint was consulted
			// only for operands, so `cp <secret> /tmp/x && cat < /tmp/x`
			// printed a real canary while `cp <secret> /tmp/x && head /tmp/x`
			// was refused - the same read, one character apart.
			if c.readsTainted(f) {
				c.deny(catSecret, "input redirection reads a copy of a secret made earlier in this command")
			}

		case syntax.Hdoc, syntax.DashHdoc:
			// An interpreter EXECUTES its heredoc whatever the quoting, so the
			// body is script text and every filename in it is opened. For any
			// other command the body is data; a substitution inside an
			// unquoted body stays a CmdSubst node, which the walk visits on
			// its own.
			if isInterpCmd && r.Hdoc != nil {
				c.checkText(rawText(c.src, r.Hdoc), "heredoc script fed to an interpreter names a secret path")
			}

		case syntax.WordHdoc:
			// A here-string fed to an interpreter is executed, not data:
			// `bash <<< 'cat <secret>'` runs the read with the filename in
			// plain sight.
			if isInterpCmd && r.Word != nil {
				c.checkText(rawText(c.src, r.Word), "here-string executed by an interpreter names a secret path")
			}
			if f := flatten(r.Word); f.hasSubst {
				c.textGate("here-string built from a substitution")
			}
		}
	}
}

func rawText(src string, w *syntax.Word) string {
	s, e := w.Pos().Offset(), w.End().Offset()
	if int(e) <= len(src) && s <= e {
		return src[s:e]
	}
	return flatten(w).lit
}

// ---------- assignments ----------

func (c *checker) assign(a *syntax.Assign) {
	if a == nil {
		return
	}
	if a.Value != nil {
		c.check(flatten(a.Value), "secret path assigned to a variable (dataflow)")
	}
	// `a=(<secret>); cat "${a[0]}"` reaches the reader through the array, which
	// no split can follow.
	if a.Array != nil {
		for _, el := range a.Array.Elems {
			if el.Value != nil {
				c.check(flatten(el.Value), "secret path assigned to an array (dataflow)")
			}
		}
	}
}

// gitConfigEnv catches the environment spelling of the hooksPath bypass.
// `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
// git commit` skips the estate-wide gitleaks scan without naming --no-verify or
// touching `git -c` at all - verified against a scratch repository, where the
// plain commit ran the hook and this one produced no hook output whatsoever.
func (c *checker) gitConfigEnv(a *syntax.Assign) {
	if a == nil || a.Name == nil || a.Value == nil {
		return
	}
	c.gitConfigAssign(a.Name.Value, stripAll(flatten(a.Value).lit))
}

// noteEnvName records one variable this call sets, however it was spelled.
func (c *checker) noteEnvName(name string) {
	if c.envNames == nil {
		c.envNames = map[string]bool{}
	}
	c.envNames[strings.ToUpper(name)] = true
}

// gitEnvBypass denies the environment spellings that relocate the GLOBAL git
// configuration, which is where this estate's `core.hooksPath` lives. Git looks
// for that file at `$XDG_CONFIG_HOME/git/config`, falling back to
// `$HOME/.gitconfig`, so moving either variable - or clearing the environment
// outright with `env -i` - points git at a configuration that carries no
// hooksPath and runs no gitleaks scan. All three were verified against a
// scratch repository where the plain commit printed the hook's marker and these
// printed nothing.
//
// Keyed on the git subcommand rather than on the variable alone, and that is
// what keeps it off ordinary work: `HOME=/tmp npm test` and `env -i make` are
// how a clean environment is asked for, and neither runs a hook.
func (c *checker) gitEnvBypass(sub string) {
	if sub != "commit" {
		return
	}
	switch {
	case c.envWiped:
		c.deny(catBypass, "env -i in front of git commit drops the global configuration carrying core.hooksPath, skipping the gitleaks pre-commit scan")
	case c.envNames["HOME"]:
		c.deny(catBypass, "HOME relocates the global git configuration carrying core.hooksPath, skipping the gitleaks pre-commit scan")
	case c.envNames["XDG_CONFIG_HOME"]:
		c.deny(catBypass, "XDG_CONFIG_HOME relocates the global git configuration carrying core.hooksPath, skipping the gitleaks pre-commit scan")
	}
}

// gitConfigAssign is the same test applied to a NAME=VALUE pair however it was
// spelled. `env NAME=VALUE git commit` puts the pair in argv rather than in
// CallExpr.Assigns, and unwrapWrappers steps over those words to find the real
// command, so this has to be called from there too.
func (c *checker) gitConfigAssign(name, value string) {
	// `GIT_CONFIG_GLOBAL=/dev/null git commit -m x` names neither --no-verify
	// nor core.hooksPath, and the commit ran no hook at all. The estate's
	// gitleaks scan is carried by a GLOBAL core.hooksPath - this machine
	// answers `~/.config/git/hooks` - so replacing that file, or suppressing
	// the system one, drops the hook with it. Verified in a scratch repository:
	// the hook printed its marker with the global config in place and printed
	// nothing under GIT_CONFIG_GLOBAL=/dev/null.
	//
	// Denied on the NAME rather than on the value, because every value drops
	// the hook: a config file that is not the estate's does not carry the
	// estate's hooksPath, whether it is /dev/null or a scratch file.
	if gitConfigFileEnvRe.MatchString(name) {
		c.deny(catBypass, name+" replaces the git configuration carrying core.hooksPath, skipping the gitleaks pre-commit scan")
		return
	}
	if !gitConfigKeyRe.MatchString(name) {
		return
	}
	if strings.EqualFold(value, "core.hooksPath") {
		c.deny(catBypass, "GIT_CONFIG_KEY core.hooksPath skips the gitleaks pre-commit scan")
	}
}

// ---------- simple commands ----------

func (c *checker) call(x *syntax.CallExpr) {
	// The environment belongs to THIS call, so it is rebuilt for each one.
	c.envNames, c.envWiped = nil, false
	for _, a := range x.Assigns {
		c.assign(a)
		c.gitConfigEnv(a)
		if a.Name != nil {
			c.noteEnvName(a.Name.Value)
		}
	}
	if len(x.Args) == 0 {
		return
	}
	words := make([]flatWord, len(x.Args))
	for i, w := range x.Args {
		words[i] = flatten(w)
	}
	c.simple(x.Args, words)
}

// unwrapWrappers returns the index of the real command word, skipping prefix
// wrappers together with their own options and operands. Every comparison is
// made on the NORMALISED word - quotes and backslashes off, leading path gone -
// because the raw spelling defeated the list: `nice /bin/cat <secret> x` read
// as harmless. It never jumps to the first recognised word anywhere in argv;
// that shortcut skipped operands it had no right to skip.
func unwrapWrappers(c *checker, words []flatWord) int {
	idx := 0
	for idx < len(words) {
		w := base(words[idx].lit)
		if !wrappers[w] {
			break
		}
		idx++
		optArgs := wrapperOptArg[w]
		// The scan runs twice for a wrapper that takes an operand of its own
		// before the command: `flock /tmp/lock -c '<script>'` carries the
		// lockfile first, and stopping at it left the `-c` payload unread.
		positionalTaken := false
	flags:
		for idx < len(words) {
			a := stripAll(words[idx].lit)
			if a == "--" {
				idx++
				break
			}
			// A bare `-` is a flag every one of these wrappers understands -
			// `su -` asks for a login shell and `env -` for an empty
			// environment - but isFlag() calls it a positional, so
			// `su - user -c '<script>'` spent su's one positional slot on the
			// dash, stopped at the username and never read the -c payload.
			if a == "-" {
				if c != nil && w == "env" {
					c.envWiped = true
				}
				idx++
				continue
			}
			// `env -i` and `env -` start the command with NO environment at
			// all, which takes HOME with it - see gitEnvBypass.
			if c != nil && w == "env" && (a == "-i" || a == "--ignore-environment") {
				c.envWiped = true
			}
			if !isFlag(a) {
				if !positionalTaken && wrapperPositional[w] {
					positionalTaken = true
					idx++
					continue
				}
				break flags
			}
			// An option's value reaches it in three spellings, and only the
			// separate one was handled: `env -S'cat <secret>'` and
			// `env --split-string=cat …` both carry the payload ON the flag,
			// so the whole word was skipped and the read went unseen.
			name, attached := a, ""
			if e := strings.IndexByte(a, '='); e > 0 {
				name, attached = a[:e], a[e+1:]
			} else if len(a) > 2 && a[1] != '-' && optArgs[a[:2]] {
				name, attached = a[:2], a[2:]
			}
			idx++
			switch {
			case attached != "":
				if c != nil && shellPayloadOpt[name] {
					c.reparse(attached, w+" "+name+" payload")
				}
			case optArgs[name] && idx < len(words):
				// `su -c '<script>'` and `flock -c '<script>'` carry shell
				// code, not an operand to skip past.
				if c != nil && shellPayloadOpt[name] {
					c.reparse(stripAll(words[idx].lit), w+" "+name+" payload")
				}
				idx++
			}
		}
		switch w {
		case "env", "command":
			for idx < len(words) {
				a := stripAll(words[idx].lit)
				if isFlag(a) || !strings.Contains(a, "=") {
					break
				}
				// These NAME=VALUE words are assignments the parser never put in
				// CallExpr.Assigns, because `env` stands in front of them. Only
				// gitConfigEnv looked at that field, so
				// `env GIT_CONFIG_KEY_0=core.hooksPath … git commit` skipped the
				// gitleaks scan - confirmed against a scratch repository, where
				// the hook produced no output at all.
				if c != nil {
					name, value, _ := strings.Cut(a, "=")
					c.gitConfigAssign(name, value)
					c.noteEnvName(name)
					// The VALUE of such an assignment is dataflow exactly as
					// `NAME=<secret> cmd` is, and only the parser's Assigns
					// field was ever looked at. `env BASH_ENV=~/.env bash -c :`
					// was allowed, and bash sourced the file - while the same
					// line without `env` in front of it was refused. Only the
					// value is judged, so that `env KUBECONFIG=/path kubectl
					// get pods` stays the ordinary work it is: the NAME of a
					// variable is not a file anyone opens.
					c.checkText(value, "environment assignment in front of a command names a secret path (dataflow)")
				}
				idx++
			}
		case "timeout", "gtimeout":
			if idx < len(words) && durationRe.MatchString(stripAll(words[idx].lit)) {
				idx++
			}
		case "repeat":
			// zsh's `repeat N cmd` puts a count where the command was expected.
			if idx < len(words) && durationRe.MatchString(stripAll(words[idx].lit)) {
				idx++
			}
		}
	}
	return idx
}

func (c *checker) simple(argWords []*syntax.Word, words []flatWord) {
	// A command word that itself names a secret is either reading it or
	// running it. `cat${IFS}<path>` arrives as a single word for that reason.
	c.check(words[0], "command word names a secret path")

	idx := unwrapWrappers(c, words)
	if idx >= len(words) {
		return
	}
	cmd := words[idx]
	cmdBase := base(cmd.lit)
	args := words[idx+1:]
	rest := argWords[idx+1:]

	// A wrapper's own positional operand is not the command: `script -q
	// /dev/null cat <secret>` and `env - cat <secret>` both stop the scan at
	// `/dev/null` and `-`, and the reader behind them was never seen. The
	// floor gets these right, so leaving them would make this binary WEAKER
	// than the layer it fronts.
	//
	// Rather than enumerate every wrapper's positional grammar, an unresolved
	// command word is followed by a look-ahead for a reader. The words stepped
	// over are still judged for secret paths, so nothing is discarded silently
	// - that discarding is what made the same shortcut unsound in the
	// prototype.
	if idx > 0 && !isKnownCommand(cmdBase) {
		for j := idx + 1; j < len(words); j++ {
			if !isKnownCommand(base(words[j].lit)) {
				continue
			}
			for k := idx; k < j; k++ {
				c.check(words[k], "operand of a wrapper names a secret path")
			}
			cmd = words[j]
			cmdBase = base(cmd.lit)
			args = words[j+1:]
			rest = argWords[j+1:]
			break
		}
	}

	// The word a wrapper resolves to is a command word in its own right, and
	// only words[0] was ever checked: `sudo <secret>` and `nice <secret>` both
	// EXECUTE the file, and both were allowed while the floor denied them.
	if idx > 0 {
		c.check(cmd, "command word names a secret path")
		// `watch 'cat <secret>'` hands its whole command over as one quoted
		// word, so the resolved "command word" is a script. The operands that
		// follow it belong to that script - `watch 'cat -v' <secret>` and
		// `parallel 'cat {}' ::: <secret>` are the idiomatic spellings of both
		// tools - so they are joined on rather than dropped.
		if inner := stripAll(cmd.lit); strings.ContainsAny(inner, " \t\n") {
			var sb strings.Builder
			sb.WriteString(inner)
			for _, a := range args {
				sb.WriteByte(' ')
				sb.WriteString(stripAll(a.lit))
			}
			c.reparse(sb.String(), "wrapped command string")
			return
		}
	}

	// A command word built by an expansion cannot be identified, so any secret
	// among its operands is treated as read.
	if cmd.hasExp {
		for _, a := range args {
			c.check(a, "unresolvable command word with a secret path operand")
		}
		c.check(cmd, "unresolvable command word embedding a secret path")
		return
	}

	c.exposing(cmdBase, args)
	if cmdBase == "direnv" {
		c.direnv(args)
	}

	c.transfer(cmdBase, args)

	// Removing or disabling the hook file has the same effect as --no-verify,
	// and names neither the flag nor core.hooksPath. Truncating it, replacing
	// it with a symlink to /dev/null, or editing an early `exit 0` into it all
	// leave the file exactly where git looks for it and still run no scan, so
	// they belong in the same arm as `rm`.
	switch cmdBase {
	// `cp /dev/null <hook>`, `dd if=/dev/null of=<hook>` and
	// `echo 'exit 0' | tee <hook>` each leave the file exactly where git looks
	// for it, empty or rewritten, and an empty hook runs no gitleaks scan. All
	// three were allowed while `truncate -s 0 <hook>`, which has the same
	// effect, was refused.
	case "rm", "mv", "chflags", "ln", "install", "truncate", "cp", "dd", "tee":
		// The hook DIRECTORY counts for the verbs that take it away whole:
		// `rm -rf ~/.config/git/hooks` and `mv ~/.config/git/hooks /tmp/h` each
		// remove the estate-wide scan from every repository at once. It is not
		// applied to `cp`, `dd`, `tee`, `truncate` or `install`, which write a
		// file INTO a directory rather than removing one.
		dirCounts := cmdBase == "rm" || cmdBase == "mv" || cmdBase == "chflags" || cmdBase == "ln"
		for _, a := range args {
			if c.hitsHookPath(a, dirCounts) {
				c.deny(catBypass, cmdBase+" on the pre-commit hook skips the gitleaks scan")
				break
			}
		}
	case "chmod":
		// Only the modes that take the execute bit AWAY. `chmod +x
		// .git/hooks/pre-commit` is how a hook is RE-ARMED after a fresh clone,
		// and refusing it made the guard stand between the operator and the
		// scan it exists to protect.
		if !chmodDropsExec(args) {
			break
		}
		for _, a := range args {
			if c.hitsHookPath(a, false) {
				c.deny(catBypass, "chmod removes the execute bit from the pre-commit hook, skipping the gitleaks scan")
				break
			}
		}
	case "sed", "gsed", "perl", "ruby":
		// Only the IN-PLACE forms rewrite the file. `sed -n /x/p <hook>` reads
		// it and changes nothing, and refusing that would be a false positive
		// on inspecting one's own hook.
		inPlace := false
		for _, a := range args {
			if sedInPlaceRe.MatchString(stripAll(a.lit)) {
				inPlace = true
			}
		}
		if inPlace {
			for _, a := range args {
				if c.hitsHookPath(a, false) {
					c.deny(catBypass, cmdBase+" -i rewrites the pre-commit hook, skipping the gitleaks scan")
					break
				}
			}
		}
	}

	// A `cd` into a directory whose contents are secret defeats every path
	// rule at once, because what follows names a bare `config`. The reader
	// that follows it in the same command is what makes it a read.
	if cmdBase == "cd" || cmdBase == "pushd" {
		for _, a := range args {
			if hitsSecretDir(stripAll(a.lit)) {
				c.inSecretDir = true
			}
		}
	}
	if c.inSecretDir && (readers[cmdBase] || grepFamily[cmdBase] || isInterp(cmdBase)) {
		c.deny(catSecret, cmdBase+" reads inside a directory the command changed into")
	}

	// A copy made earlier in this command line, now being read. Applied to
	// every reading command rather than inside one arm, because jq, grep, sed
	// and the interpreters each have arms of their own.
	if isReader(cmdBase) {
		for _, a := range args {
			if c.readsTainted(a) {
				c.deny(catSecret, cmdBase+" reads a copy of a secret made earlier in this command")
			}
			// A recursive glob names none of the files it expands to, which is
			// the same class as `rg` and `grep -r`. `cat **/*` printed a canary
			// from a subdirectory while every path pattern looked past it.
			if hasTreeGlob(a.glob) {
				c.deny(catRecursive, cmdBase+" reads a recursive glob, naming none of the files it expands to")
			}
		}
		// An operand built from a tree walk names none of the files it reads.
		for _, aw := range rest {
			if isWalkerSubst(aw) {
				c.deny(catRecursive, cmdBase+" reads the files a tree walk enumerated, naming none of them")
				break
			}
		}
	}

	// A function whose body reads carries the path from its call site, where
	// no reader is named at all: `f(){ cat "$1"; }; f <secret>`.
	if c.readerFuncs[cmdBase] {
		for _, a := range args {
			c.check(a, "secret path passed to a function that reads its arguments")
		}
	}

	switch {
	case cmdBase == "eval":
		c.eval(args)
	case cmdBase == "trap":
		// A trap payload is shell code that runs later, so it is reparsed.
		if len(args) > 0 {
			if args[0].hasSubst {
				c.textGate("trap payload built from a substitution")
			} else {
				c.reparse(stripAll(args[0].lit), "trap payload")
			}
		}
	case cmdBase == "xargs":
		c.xargs(args)
	case execFinders[cmdBase]:
		c.find(cmdBase, args)
	case cmdBase == "git":
		c.git(args)
	case cmdBase == "ansible-vault":
		if len(args) > 0 {
			switch base(args[0].lit) {
			case "view", "decrypt", "edit", "cat", "rekey":
				c.deny(catSecret, "ansible-vault exposes vault content")
			}
		}
	case alwaysRecursive[cmdBase]:
		// `rg --version` and `ag --help` search nothing.
		if !onlyInfoFlags(args) {
			c.deny(catRecursive, cmdBase+" searches recursively and reads files it never names")
		}
	case grepFamily[cmdBase]:
		c.grep(cmdBase, args)
	case transferCmds[cmdBase]:
		for _, a := range args {
			c.checkTransfer(a, cmdBase+" moves a secret path off this machine")
		}
	case uploadCmds[cmdBase]:
		c.curl(cmdBase, args)
	case archiveCmds[cmdBase]:
		c.archive(cmdBase, args)
	case cmdBase == "docker" || cmdBase == "podman" || cmdBase == "nerdctl":
		c.container(cmdBase, args)
	case cmdBase == "jq" || cmdBase == "yq":
		c.jq(cmdBase, args)
	case cmdBase == "sed" || cmdBase == "awk" || cmdBase == "gawk" || cmdBase == "mawk":
		c.program(cmdBase, args)
	case cmdBase == "tee":
		// Every operand of tee is a file it WRITES; it reads only stdin, and
		// whatever fills that stdin is a command of its own that this walk
		// judges separately. `tee <secret> < input` overwrites the secret and
		// prints nothing of it, so it is not a read.
	case cmdBase == "cp" || cmdBase == "install" || cmdBase == "mv" || cmdBase == "ln":
		// A copy crosses no boundary and is allowed by design - but a copy
		// whose destination is a standard stream is a read with extra steps.
		stream := false
		for _, a := range args {
			if devStreamRe.MatchString(stripAll(a.lit)) {
				stream = true
			}
		}
		if stream {
			for _, a := range args {
				c.check(a, "copy of a secret path into a standard stream is a read")
			}
		}
		c.taintDestination(args)
	case assignCmds[cmdBase]:
		for _, a := range args {
			c.check(a, "secret path assigned to a variable (dataflow)")
		}
	case isInterp(cmdBase):
		c.interp(cmdBase, args, rest)
	case readers[cmdBase]:
		for _, a := range args {
			c.checkOperand(a, cmdBase+" reads a secret path")
		}
		for _, aw := range rest {
			if f := flatten(aw); f.hasSubst && hitsSecretText(rawText(c.src, aw)) {
				c.deny(catSecret, cmdBase+" operand built from a substitution naming a secret path")
			}
		}
	}

	if cmdBase == "source" || cmdBase == "." {
		for i, a := range args {
			c.check(a, "source executes and reads a secret path")
			if flatten(rest[i]).hasSubst {
				c.textGate("source of a substitution")
			}
		}
	}
}

// exposing covers commands that print secret material with NO filename anywhere
// in them: a path-pattern guard is blind to `kubectl config view --raw` by
// construction. Keyed on the command word and its first operands, never on the
// argument text - prose in a commit message lives in that command's own
// arguments, and matching the text refused the message that introduced this
// very rule.
func (c *checker) exposing(cmdBase string, args []flatWord) {
	key := subcommandKey(cmdBase, args, 3)
	for _, p := range exposingPrefixes {
		if strings.HasPrefix(key, p) {
			c.deny(catSecret, p+" prints secret material")
			return
		}
	}
}

// transfer covers the cloud CLIs that move a file off the machine exactly as
// scp does. Keyed on the subcommand, then on the operands: `aws configure list`
// names nothing and `aws eks update-kubeconfig` writes one rather than sending
// one.
func (c *checker) transfer(cmdBase string, args []flatWord) {
	key := subcommandKey(cmdBase, args, 4)
	for _, p := range transferPrefixes {
		if strings.HasPrefix(key, p) {
			for _, a := range args {
				c.checkTransfer(a, p+" moves a secret path off this machine")
			}
			return
		}
	}
}

// subcommandKey joins the command word to its first n NON-FLAG operands. The
// flags have to be skipped: keyed on the first two operands whatever they were,
// `kubectl -n foo config view --raw` and `terraform -chdir=infra output` walked
// straight past the set, and one flag is all it took.
func subcommandKey(cmdBase string, args []flatWord, n int) string {
	key := cmdBase
	for i := 0; i < len(args) && n > 0; i++ {
		w := stripAll(args[i].lit)
		if w == "--" {
			continue
		}
		if isFlag(w) {
			// A global option with a separate value would otherwise contribute
			// its value as a subcommand.
			if !strings.Contains(w, "=") && i+1 < len(args) && globalOptArg[w] {
				i++
			}
			continue
		}
		key += " " + strings.ToLower(w)
		n--
	}
	return key
}

// checkMount is checkTransfer's twin for containers: mounting a secret
// DIRECTORY hands over every file in it, and `docker run -v ~/.kube:/root/.kube`
// matched nothing because the directory itself is not a filename in the
// pattern set.
func (c *checker) checkMount(f flatWord, why string) {
	if hitsSecretFlat(f) || hitsSecretDir(stripAll(f.lit)) {
		c.deny(catSecret, why)
		return
	}
	// A mount is written `src:dst[:opts]`, and the directory patterns need the
	// path to END there: in `-v ~/.kube:/k` the source is followed by a colon,
	// not by a separator, so the whole operand matched nothing while the same
	// mount written `-v ~/.kube:/root/.kube` matched on its destination.
	//
	// `--mount` uses a different grammar for the same thing - comma-separated
	// `key=value` pairs - so the path there is followed by a COMMA and pinned in
	// front by an `=`. Splitting on `:` alone left `docker run --mount
	// type=bind,source=$L/.kube,target=/k alpine cat /k/config` allowed, and it
	// printed a real canary.
	for _, part := range strings.FieldsFunc(stripAll(f.lit), func(r rune) bool {
		return r == ':' || r == ',' || r == '='
	}) {
		if part == "" {
			continue
		}
		if hitsSecretDir(part) || hitsSecretText(part) {
			c.deny(catSecret, why)
			return
		}
	}
}

// checkTransfer is deliberately blunter than checkText: sending a secret
// DIRECTORY moves every file in it, and `rsync -a ~/.kube host:/tmp` matched
// nothing because the directory itself is not a filename in the pattern set.
// direnv loads .envrc into the environment and then runs a command. `direnv
// export` prints the environment itself and is handled by the exposing set;
// `direnv exec <dir> <cmd>` leaks only when <cmd> is one of the few commands
// that print the environment back out.
func (c *checker) direnv(args []flatWord) {
	sub := ""
	var rest []flatWord
	for i, a := range args {
		if w := stripAll(a.lit); !isFlag(w) {
			sub = strings.ToLower(w)
			rest = args[i+1:]
			break
		}
	}
	if sub != "exec" {
		return
	}
	// The first operand of `exec` is the directory; the command follows it.
	for i, a := range rest {
		w := stripAll(a.lit)
		if isFlag(w) || i == 0 {
			continue
		}
		if envPrinters[base(a.lit)] {
			c.deny(catSecret, "direnv exec running "+base(a.lit)+" prints the loaded environment")
		}
		break
	}
}

func (c *checker) checkTransfer(f flatWord, why string) {
	if hitsSecretFlat(f) || hitsSecretDir(stripAll(f.lit)) {
		c.deny(catTransfer, why)
	}
}

// taintDestination records where a secret was just copied. The destination is
// the last operand, which is what cp, mv, ln and install all agree on.
func (c *checker) taintDestination(args []flatWord) {
	var operands []flatWord
	for _, a := range args {
		if !isFlag(stripAll(a.lit)) {
			operands = append(operands, a)
		}
	}
	if len(operands) < 2 {
		return
	}
	dest := operands[len(operands)-1]
	for _, src := range operands[:len(operands)-1] {
		// Keyed on the COLLAPSED spelling, because the read half is free to
		// respell the same file: `cp <secret> /tmp/x && cat /tmp/./x` named
		// one path on the left of the map and another on the right, and the
		// two never met.
		key := collapseSlashes(stripAll(dest.lit))
		switch {
		// A secret DIRECTORY copied wholesale puts every file in it under the
		// destination, and the read that follows names a file the map never
		// held: `cp -r ~/.kube /tmp/k && cat /tmp/k/config` was allowed because
		// the taint was the exact string `/tmp/k`. A directory taints its
		// destination as a PREFIX for that reason.
		case hitsSecretDir(stripAll(src.lit)):
			if c.taintedDirs == nil {
				c.taintedDirs = map[string]bool{}
			}
			c.taintedDirs[strings.TrimSuffix(key, "/")] = true
			return
		case hitsSecretFlat(src):
			if c.tainted == nil {
				c.tainted = map[string]bool{}
			}
			c.tainted[key] = true
			return
		}
	}
}

// readsTainted reports whether an operand reaches a copy made earlier in this
// command line. The operand is matched three ways, because naming the copy
// exactly is only the easiest of them:
//
//   - by its collapsed spelling, so `/tmp/./x` finds `/tmp/x`;
//   - as a GLOB, so `cat /tmp/x*` finds it without spelling it out;
//   - with every expansion standing for anything, so `D=/tmp; cat $D/x` finds
//     it through a variable no static split can follow.
//
// The last two only ever look at paths this command line itself copied a secret
// to, so a command that copies nothing secret is untouched by them.
func (c *checker) readsTainted(a flatWord) bool {
	if len(c.tainted) == 0 && len(c.taintedDirs) == 0 {
		return false
	}
	lit := collapseSlashes(stripAll(a.lit))
	if c.tainted[lit] {
		return true
	}
	// A copied DIRECTORY taints everything under it, which is what the exact
	// map cannot express.
	for dir := range c.taintedDirs {
		if lit == dir || strings.HasPrefix(lit, dir+"/") {
			return true
		}
	}
	pat := collapseSlashes(strings.ReplaceAll(stripAll(a.glob), string(markExp), "*"))
	if !pattern.HasMeta(pat, 0) {
		return false
	}
	re := globRegexp(pat)
	if re == nil {
		return false
	}
	for dest := range c.tainted {
		if re.MatchString(dest) {
			return true
		}
	}
	for dir := range c.taintedDirs {
		if re.MatchString(dir) {
			return true
		}
	}
	return false
}

// chmodDropsExec reports whether a chmod mode takes the execute bit AWAY. Git
// will not run a hook it cannot execute, so removing the bit is a bypass -
// while adding it back is the repair every fresh clone needs.
//
// Both spellings are read. A symbolic mode is a comma-separated list, and only
// the clause carrying the `-` matters, so `chmod u+x,g-x` is caught where
// anchoring on the whole word missed it. A numeric mode is judged on its OWNER
// digit, the one git's own executable test looks at.
func chmodDropsExec(args []flatWord) bool {
	for _, a := range args {
		w := stripAll(a.lit)
		if chmodNumericRe.MatchString(w) {
			if (w[len(w)-3]-'0')&1 == 0 {
				return true
			}
			continue
		}
		for _, part := range strings.Split(w, ",") {
			if chmodSymbolicDropRe.MatchString(part) {
				return true
			}
			// An ASSIGNMENT sets the bits exactly, so a clause with no `x` in
			// it takes the execute bit away. Only a clause touching the OWNER
			// counts - see chmodAssignDropRe.
			if m := chmodAssignDropRe.FindStringSubmatch(part); m != nil &&
				(m[1] == "" || strings.ContainsAny(m[1], "ua")) {
				return true
			}
		}
	}
	return false
}

// streamsToStdout reports whether a command that is not a reader has been
// pointed at a standard stream, which makes it one: `xargs -I{} cp {}
// /dev/stdout` prints every file it is handed.
func streamsToStdout(b string, args []flatWord) bool {
	switch b {
	case "cp", "mv", "ln", "install", "dd", "tee":
	default:
		return false
	}
	for _, a := range args {
		if devStreamRe.MatchString(stripAll(a.lit)) {
			return true
		}
	}
	return false
}

// grep: recursion is denied as a class, because a recursive search never names
// the file whose contents it prints, so no path rule can catch it.
//
// The first bare operand of `grep PATTERN FILE…` is the pattern, and grep never
// opens it, so skipping it is what makes `grep -n '\.env' Makefile` readable.
// The prototype lost 10 cases to this idea by treating "first bare operand" as
// the pattern unconditionally: with `-eMA` or `-f<prog>` the pattern rides on
// the flag, so the first bare operand is a FILE and skipping it hid the read.
//
// The options are parsed instead. Every option that takes a value is listed,
// in its separate, attached and `=` spellings. An option MISSING from that list
// costs a false positive - its value is judged as a filename - and never a
// false negative, which is the direction to fail in.
func (c *checker) grep(name string, args []flatWord) {
	patternSeen := false
	stopFlags := false
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)

		if !stopFlags && w == "--" {
			stopFlags = true
			continue
		}
		if !stopFlags && isFlag(w) {
			opt, val, attached := splitOpt(w, grepOptArg)
			if isRecursiveGrepFlag(opt, val, attached) {
				c.deny(catRecursive, name+" searches recursively and reads files it never names")
				return
			}
			if !grepOptArg[opt] {
				continue
			}
			if !attached {
				if i+1 >= len(args) {
					continue
				}
				i++
				val = stripAll(args[i].lit)
				// `-d recurse` walks the tree exactly as `-r` does, and it is
				// the one spelling both layers walked past.
				if isRecursiveGrepFlag(opt, val, true) {
					c.deny(catRecursive, name+" searches recursively and reads files it never names")
					return
				}
				if grepFileOptArg[opt] {
					c.check(args[i], name+" "+opt+" reads a secret path")
				}
			} else if grepFileOptArg[opt] {
				c.checkText(val, name+" "+opt+" reads a secret path")
			}
			if opt == "-e" || opt == "--regexp" || opt == "-f" || opt == "--file" {
				patternSeen = true // the pattern rode on the flag
			}
			continue
		}
		if !patternSeen {
			patternSeen = true // the search pattern, which grep does not open
			continue
		}
		c.checkOperand(args[i], name+" reads a secret path")
	}
}

// hitsHookPath reports whether a word names the pre-commit hook: the file
// itself, a GLOB that could expand to it, or - when the verb takes a directory
// away whole - the hooks directory that carries it.
func (c *checker) hitsHookPath(a flatWord, dirCounts bool) bool {
	lit := collapseSlashes(stripAll(a.lit))
	if hookFileRe.MatchString(lit) {
		return true
	}
	if dirCounts && hooksDirRe.MatchString(lit) {
		return true
	}
	return hookGlobHits(collapseSlashes(stripAll(a.glob)))
}

// isStdoutDest reports whether an archive destination is the agent's own
// output. `-` is the spelling everyone writes; `/dev/stdout` and `/dev/fd/1`
// are the same thing under another name.
func isStdoutDest(dest string) bool {
	return dest == "-" || devStreamRe.MatchString(dest)
}

// oldStyleTarFlags reports whether a bare word is tar's dashless flag bundle.
func oldStyleTarFlags(w string) bool {
	if w == "" || len(w) > 8 {
		return false
	}
	for i := 0; i < len(w); i++ {
		if !strings.ContainsRune("cxtruvfzjJZphmokPWORSA", rune(w[i])) {
			return false
		}
	}
	return strings.ContainsAny(w, "cxtru")
}

// onlyInfoFlags reports whether a command was asked for its version or its
// help and nothing else.
func onlyInfoFlags(args []flatWord) bool {
	if len(args) == 0 {
		return false
	}
	for _, a := range args {
		switch stripAll(a.lit) {
		case "--version", "-V", "--help", "-h":
		default:
			return false
		}
	}
	return true
}

func isRecursiveGrepFlag(opt, val string, attached bool) bool {
	switch opt {
	case "--recursive", "--dereference-recursive", "-R":
		return true
	case "-d", "--directories":
		return attached && strings.EqualFold(val, "recurse")
	}
	return isFlag(opt) && !strings.HasPrefix(opt, "--") && recShortFlag.MatchString(opt)
}

// splitOpt separates an option from a value carried on the option itself, in
// both the `--name=value` and the `-nvalue` spellings.
func splitOpt(w string, known map[string]bool) (opt, val string, attached bool) {
	if strings.HasPrefix(w, "--") {
		if name, v, ok := strings.Cut(w, "="); ok {
			return name, v, true
		}
		return w, "", false
	}
	if len(w) > 2 && known[w[:2]] {
		return w[:2], w[2:], true
	}
	return w, "", false
}

// jq and yq take a PROGRAM as their first bare operand, not a filename. Without
// that, every filter reaching an `env` key matched the `.env` pattern - which
// carries no boundary in front of it so that `prod.env` is caught - and
// `jq '.env' package.json` and `kubectl get pod x -o json | jq '…env'` were
// both refused. `-f`/`--from-file` moves the program into a FILE, so the first
// bare operand is data again and nothing is skipped.
func (c *checker) jq(name string, args []flatWord) {
	programSeen := false
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)
		if isFlag(w) {
			opt, _, attached := splitOpt(w, nil)
			if opt == "-f" || opt == "--from-file" || opt == "--fromfile" {
				programSeen = true
				if !attached && i+1 < len(args) {
					i++
					c.check(args[i], name+" reads its program from a secret path")
				}
			}
			continue
		}
		if !programSeen && isFilterExpression(args[i]) {
			programSeen = true
			continue
		}
		programSeen = true
		c.check(args[i], name+" reads a secret path")
	}
}

// program covers sed and awk, whose first bare operand is a SCRIPT rather than
// a filename: `sed -i ” 's/import.meta.env.VITE_API/API/' src/main.ts` and
// `awk '/import.meta.env.VITE_X/{print}' src/app.ts` name no file at all.
//
// It once reused jq's isFilterExpression, which demands a leading `.` or `$`
// and refuses any word carrying a `/`. No sed or awk script has ever looked
// like that, so the discriminator could not fire once: `sed -n '/\.env/p'
// Makefile` and `sed 's/\.env/x/' Makefile` were both refused, and a search
// pattern naming a secret is the single commonest thing a guard is asked about.
// isProgramText is its own shape test for that reason - see word.go.
//
// `-e`/`-f` move the script onto the flag, so the first bare operand is data
// again and nothing is skipped - the lesson the grep arm was built on.
//
// Skipping the script slot is where round 4 stopped, and that is a hole on its
// own: a sed or awk SCRIPT can itself open a file. `sed '$r .env' package.json`
// and `awk 'BEGIN{while((getline l < ".env")>0) print l}'` each printed a real
// canary while the word carrying the filename was the one word not looked at.
//
// Text-gating the whole script is not the answer either - that is exactly the
// false positive the skip was added to remove, and `sed 's/\.env/x/' Makefile`
// is the commonest thing a guard is asked about. So the slot is still skipped,
// and the script's TEXT is judged only when the script contains a construct
// that opens a file. See scriptOpensFile.
func (c *checker) program(name string, args []flatWord) {
	scriptOnFlag := false
	for _, a := range args {
		w := stripAll(a.lit)
		opt, _, _ := splitOpt(w, programOptArg)
		if programOptArg[opt] {
			scriptOnFlag = true
		}
	}
	seen := scriptOnFlag
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)
		if isFlag(w) {
			opt, val, attached := splitOpt(w, programOptArg)
			switch {
			case programFileOptArg[opt]:
				if !attached && i+1 < len(args) {
					i++
					c.check(args[i], name+" reads its script from a secret path")
				}
			case programOptArg[opt]:
				// `-e`, `--expression` and `--source` carry SCRIPT text, in
				// both the attached and the separate spelling. The value was
				// judged as a filename, which refused
				// `sed -e 's/\.env/x/' Makefile`.
				if attached {
					c.programScript(name, flatWord{lit: string(markQuote) + val, glob: val})
				} else if i+1 < len(args) {
					i++
					c.programScript(name, args[i])
				}
			}
			continue
		}
		// BSD sed spells `-i` with a separate, usually EMPTY, backup suffix, so
		// `sed -i '' 's/…/…/' f` puts an empty word where the script was
		// expected. An empty word names no file either way; what matters is
		// that it must not spend the one slot the script is looked for in.
		if w == "" {
			continue
		}
		if !seen && isProgramText(args[i]) {
			seen = true
			c.programScript(name, args[i])
			continue
		}
		seen = true
		c.check(args[i], name+" reads a secret path")
	}
}

// programScript judges a word that was accepted as a sed or awk SCRIPT.
//
// A script that only matches, substitutes or prints opens nothing, so its text
// is left alone: that is what keeps `sed 's/\.env/x/' Makefile`,
// `sed -n '/\.env/p' Makefile` and `awk '{print $1}' data.txt` readable. A
// script carrying a file-opening construct is judged on its text instead, which
// is where the filename it opens is written.
func (c *checker) programScript(name string, f flatWord) {
	script := stripAll(f.lit)
	if !scriptOpensFile(name, script) {
		return
	}
	// Marked as script text, exactly as an interpreter payload is: the
	// code-identifier neutraliser reads the character standing in front of the
	// name, and a script does not begin like a filename word.
	c.checkText(string(markQuote)+f.lit, name+" script opens a file and names a secret path")
	// awk joins strings by writing them next to each other, so
	// `awk 'BEGIN{f=".en" "v";while((getline l<f)>0)print l}'` builds the
	// filename out of two literals and the script text spells none of it. The
	// script is already known to open a file, which is the second half this
	// gate demands - see litConcatRe.
	if hasLiteralConcat(script) {
		c.deny(catSecret, name+" script joins a filename out of string literals and opens it, naming no path")
	}
	// `awk 'BEGIN{system("cat .env")}'` hands a whole shell command to the
	// shell. It is shell code, so it is judged as shell code.
	for _, arg := range awkSystemArgs(name, script) {
		c.reparse(arg, name+" system() payload")
	}
}

// archive: tar and friends read a whole tree without naming one file in it.
// Only the forms that send the archive to STDOUT matter - `tar czf out.tgz src/`
// writes to a file and leaks nothing into the agent's context, while
// `tar czf - . | base64` is a recursive read with extra steps.
func (c *checker) archive(name string, args []flatWord) {
	if name == "zip" {
		c.zip(args)
		return
	}
	creating, toStdout, sawFileFlag := false, false, false
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)
		// tar's original spelling carries its flags with no dash at all, and
		// `tar czf - .` is the shape that matters most here.
		if i == 0 && !isFlag(w) && oldStyleTarFlags(w) {
			w = "-" + w
		}
		switch {
		// `-w` is pax's create flag and `-o` is cpio's; without them
		// `pax -w . | base64` and `ls | cpio -o` never counted as archiving.
		case w == "--create" || w == "--append" || w == "--update":
			creating = true
		case strings.HasPrefix(w, "--file="):
			sawFileFlag = true
			toStdout = isStdoutDest(strings.TrimPrefix(w, "--file="))
		case w == "--file" || w == "-f":
			sawFileFlag = true
			if i+1 < len(args) {
				i++
				toStdout = isStdoutDest(stripAll(args[i].lit))
			}
		case isFlag(w) && !strings.HasPrefix(w, "--"):
			if strings.ContainsAny(w, "crwo") {
				creating = true
			}
			if j := strings.IndexByte(w, 'f'); j >= 0 {
				sawFileFlag = true
				// The destination rides on the bundle in `tar -cf- .` and
				// follows it in `tar czf - .`. Reading only the second
				// spelling made the first swallow the operand instead.
				if j+1 < len(w) {
					toStdout = isStdoutDest(w[j+1:])
				} else if i+1 < len(args) {
					i++
					toStdout = isStdoutDest(stripAll(args[i].lit))
				}
			}
		}
	}
	if !sawFileFlag {
		toStdout = true // no destination named: cpio and pax write to stdout
	}
	if creating && toStdout {
		c.deny(catRecursive, name+" archives to standard output, reading files it never names")
		return
	}
	for _, a := range args {
		c.check(a, name+" reads a secret path")
	}
}

// zip names its archive as the FIRST bare operand, so `zip -r - .` streams the
// whole tree to standard output while `zip -r out.zip .` writes a file.
func (c *checker) zip(args []flatWord) {
	for _, a := range args {
		w := stripAll(a.lit)
		if isFlag(w) {
			continue
		}
		if w == "-" {
			c.deny(catRecursive, "zip archives to standard output, reading files it never names")
			return
		}
		break // the archive is a real file
	}
	for _, a := range args {
		c.check(a, "zip reads a secret path")
	}
}

// container: a bind mount hands the file to a process that prints it, and
// `docker cp` copies it straight out.
//
// `--env-file` was left out on the argument that it passes the secret INTO a
// container without printing it, the same shape as `kubectl --kubeconfig`. That
// argument is wrong: the container's own first command can print the
// environment, and `docker run --rm --env-file <secret> alpine env` was
// confirmed printing a real canary. It goes to checkMount exactly as `-v` does.
func (c *checker) container(name string, args []flatWord) {
	sub := ""
	for _, a := range args {
		if w := stripAll(a.lit); !isFlag(w) {
			sub = strings.ToLower(w)
			break
		}
	}
	if sub == "cp" {
		for _, a := range args {
			c.checkMount(a, name+" cp copies a secret path out")
		}
		return
	}
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)
		opt, val, attached := splitOpt(w, map[string]bool{"-v": true})
		why := name + " bind-mounts a secret path into a container"
		switch opt {
		case "--env-file":
			why = name + " hands a secret path to a container as its environment"
			fallthrough
		case "-v", "--volume", "--mount":
			if !attached && i+1 < len(args) {
				i++
				c.checkMount(args[i], why)
			} else if val != "" {
				c.checkMount(flatWord{lit: val, glob: val}, why)
			}
		}
	}
}

func (c *checker) curl(name string, args []flatWord) {
	upload := false
	for _, a := range args {
		w := stripAll(a.lit)
		if uploadFlags[w] || uploadFlags[strings.SplitN(w, "=", 2)[0]] {
			upload = true
		}
	}
	for _, a := range args {
		if upload {
			c.checkTransfer(a, name+" uploads a secret path")
		}
		// `curl file://<path>` prints a local file. It is not a reader, and
		// the transfer arm only looks at an upload flag, so this walked
		// through as a one-token exfiltration primitive.
		if fileURLRe.MatchString(stripAll(a.lit)) {
			c.check(a, name+" file:// prints a local secret path")
		}
	}
}

func (c *checker) eval(args []flatWord) {
	var lit []string
	for _, a := range args {
		if a.hasSubst {
			c.textGate("eval of a substitution")
			return
		}
		lit = append(lit, stripAll(a.lit))
	}
	c.reparse(strings.Join(lit, " "), "eval payload")
}

// xargs and find -exec build a command line from paths they were handed, so the
// reader at the end of them prints files that appear nowhere in the text.
func (c *checker) xargs(args []flatWord) {
	for _, a := range args {
		b := base(a.lit)
		// A SYNTAX CHECK prints diagnostics, not contents. `git diff
		// --name-only HEAD~1 | xargs php -l` lints the files a commit touched,
		// which is daily work on this estate, and `php -l` puts no line of any
		// file into the agent's context - it answers "No syntax errors
		// detected" or points at a line number. Refusing it taught the operator
		// that the recursive class fires on work that reads nothing.
		if isSyntaxCheckOnly(b, args) {
			continue
		}
		if isReader(b) || streamsToStdout(b, args) {
			c.deny(catRecursive, "xargs feeding "+b+" reads files it never names")
			return
		}
	}
	for _, a := range args {
		c.check(a, "xargs reads a secret path")
	}
}

func (c *checker) find(name string, args []flatWord) {
	c.findDeletesHook(args)
	for i, a := range args {
		switch stripAll(a.lit) {
		// `fd -x`/`-X` is the same primitive under another name.
		case "-exec", "-execdir", "-ok", "-okdir", "-x", "-X", "--exec", "--exec-batch":
			if i+1 < len(args) {
				b := base(args[i+1].lit)
				// An IN-PLACE edit prints nothing. `find . -name "*.php" -exec
				// sed -i '' 's/foo/bar/' {} +` is the ordinary way to make one
				// change across a Laravel tree, and it puts no file content in
				// the agent's context at all - the tool rewrites each file and
				// says nothing. Only the editors that HAVE an in-place mode are
				// exempted, and only when the flag is actually there.
				if isInPlaceEdit(b, args[i+2:]) {
					continue
				}
				// A syntax check reads nothing into the agent's context - see
				// the same exemption in xargs.
				if isSyntaxCheckOnly(b, args[i+2:]) {
					continue
				}
				if isReader(b) || streamsToStdout(b, args) {
					c.deny(catRecursive, name+" running "+b+" reads files it never names")
					return
				}
			}
		}
	}
}

// findDeletesHook catches the finder spelling of removing the pre-commit hook.
// `find ~/.config/git -name pre-commit -delete` takes the estate-wide gitleaks
// scan away and no single word in it is a hook PATH: the directory and the
// filename stand in separate operands, so hookFileRe sees neither.
//
// Both halves are required - a destructive action AND a word that names the
// hook - which is what keeps `find . -name '*.tmp' -delete` untouched.
func (c *checker) findDeletesHook(args []flatWord) {
	destroys := false
	for i, a := range args {
		switch stripAll(a.lit) {
		case "-delete":
			destroys = true
		case "-exec", "-execdir", "-ok", "-okdir":
			if i+1 < len(args) {
				switch base(args[i+1].lit) {
				case "rm", "mv", "chmod", "truncate", "unlink", "chflags":
					destroys = true
				}
			}
		}
	}
	if !destroys {
		return
	}
	for _, a := range args {
		w := collapseSlashes(stripAll(a.lit))
		if hookFileRe.MatchString(w) || hooksDirRe.MatchString(w) ||
			globSegMatches(collapseSlashes(stripAll(a.glob)), "pre-commit") {
			c.deny(catBypass, "find deletes the pre-commit hook, skipping the gitleaks scan")
			return
		}
	}
}

// isSyntaxCheckOnly reports whether an interpreter was asked to CHECK a file
// rather than to run or print it. `php -l`, `ruby -c` and `node --check` parse
// the file and report diagnostics; none of them puts a line of the file into
// the agent's context, so none of them is a read.
//
// The exemption is withdrawn the moment a payload option is present as well:
// `php -l -r '<code>'` runs the code, whatever else is on the line.
func isSyntaxCheckOnly(b string, rest []flatWord) bool {
	var flags map[string]bool
	switch {
	case strings.HasPrefix(b, "php"):
		flags = set(`-l --syntax-check`)
	case b == "ruby":
		flags = set(`-c`)
	case b == "node" || b == "bun":
		flags = set(`--check`)
	default:
		return false
	}
	seen := false
	for _, a := range rest {
		w := stripAll(a.lit)
		if flags[w] {
			seen = true
			continue
		}
		switch w {
		case "-r", "-e", "-p", "--eval", "--print", "-c", "--command":
			if !flags[w] {
				return false
			}
		}
	}
	return seen
}

// isInPlaceEdit reports whether the command a finder runs REWRITES each file it
// is handed rather than printing it. Restricted to the tools that have an
// in-place mode, because `-i` means something else everywhere else - it is
// grep's case-insensitive flag and ssh's identity file.
func isInPlaceEdit(b string, rest []flatWord) bool {
	switch b {
	case "sed", "gsed", "perl", "ruby":
	default:
		return false
	}
	for _, a := range rest {
		if sedInPlaceRe.MatchString(stripAll(a.lit)) {
			return true
		}
	}
	return false
}

func (c *checker) git(args []flatWord) {
	i := 0
	for i < len(args) {
		w := stripAll(args[i].lit)
		name, val, hasEq := strings.Cut(w, "=")
		if gitGlobalArg[name] {
			if !hasEq && i+1 < len(args) {
				val = stripAll(args[i+1].lit)
				i += 2
			} else {
				i++
			}
			// Pointing hooksPath elsewhere skips the estate-wide gitleaks scan
			// without naming --no-verify at all.
			if strings.HasPrefix(strings.ToLower(val), "core.hookspath=") {
				c.deny(catBypass, "git -c core.hooksPath skips the gitleaks pre-commit scan")
			}
			continue
		}
		if isFlag(w) {
			i++
			continue
		}
		break
	}
	if i >= len(args) {
		return
	}
	sub := strings.ToLower(stripAll(args[i].lit))
	rest := args[i+1:]
	c.gitEnvBypass(sub)

	// `git grep` was refused as part of the recursive class, on the argument
	// that it reads files it never names. Measurement overturned it: 407
	// refusals in this estate's real traffic, 4% of every command, for the
	// weakest security value in that class. It searches only TRACKED files,
	// which carry no secret by construction - the whole point of the gitleaks
	// hook this guard also protects - and which the agent can already read one
	// at a time. It falls through to the read-subcommand arm below, so
	// `git grep x -- <secret>` is still judged on its operands.
	if gitReadSubs[sub] {
		// A message or a search expression is prose, not a filename. Skipping
		// them is the same association split that stopped `git commit -m`
		// being refused; it was simply never carried into `git stash -m` or
		// `git log --grep`.
		for i := 0; i < len(rest); i++ {
			w := stripAll(rest[i].lit)
			opt, _, attached := splitOpt(w, gitProseOptArg)
			if gitProseOptArg[opt] {
				if !attached && i+1 < len(rest) {
					i++
				}
				continue
			}
			// An EXCLUDING pathspec names the file it will not show. `git diff
			// -- ':!.env'` is how a diff is asked to leave the secret out, and
			// refusing it stood between the operator and the safer command.
			if isExcludePathspec(w) {
				continue
			}
			c.check(rest[i], "git "+sub+" prints file contents")
		}
	}
	if sub == "commit" {
		for _, a := range rest {
			w := stripAll(a.lit)
			if isNoVerifyFlag(w) ||
				(isFlag(w) && !strings.HasPrefix(w, "--") && shortNFlag.MatchString(w)) {
				c.deny(catBypass, "git commit --no-verify skips the gitleaks pre-commit scan")
				return
			}
		}
	}
	// `git config core.hooksPath …` re-points the hook directory permanently,
	// which skips the scan exactly as the `-c` form does for one command.
	// Only the WRITING forms: `git config --get core.hooksPath` reads the value
	// back and changes nothing, and refusing it was a false positive.
	if sub == "config" {
		named, writes, reads := false, false, false
		for i, a := range rest {
			w := strings.ToLower(stripAll(a.lit))
			switch {
			case strings.HasPrefix(w, "core.hookspath"):
				named = true
				// A value after the key, or joined to it, is a write.
				if strings.Contains(w, "=") || (i+1 < len(rest) && !isFlag(stripAll(rest[i+1].lit))) {
					writes = true
				}
			case w == "--get" || w == "--get-all" || w == "--get-regexp" ||
				w == "--get-urlmatch" || w == "-l" || w == "--list":
				reads = true
			case w == "--unset" || w == "--unset-all" || w == "--replace-all" || w == "--add":
				writes = true
			}
		}
		if named && writes && !reads {
			c.deny(catBypass, "git config core.hooksPath skips the gitleaks pre-commit scan")
			return
		}
	}
}

// isExcludePathspec reports whether a pathspec EXCLUDES what it names. git
// spells it `:!<path>`, `:^<path>` or with the long magic `:(exclude)<path>`.
// A path named that way is one the command is being told not to print.
func isExcludePathspec(w string) bool {
	return strings.HasPrefix(w, ":!") || strings.HasPrefix(w, ":^") ||
		(strings.HasPrefix(w, ":(") && strings.Contains(w, "exclude"))
}

// isNoVerifyFlag accepts every abbreviation git itself accepts. git resolves
// any UNAMBIGUOUS prefix of a long option, so `git commit --no-veri` skips the
// pre-commit hook exactly as `--no-verify` does - confirmed against git 2.50.1,
// where `--no-ver` is the first prefix git rejects as ambiguous. Matching the
// full spelling alone left the whole arm one character from useless.
func isNoVerifyFlag(w string) bool {
	const full = "--no-verify"
	return len(w) >= len("--no-v") && len(w) <= len(full) && strings.HasPrefix(full, w)
}

func (c *checker) interp(name string, args []flatWord, argWords []*syntax.Word) {
	if c.artisan(name, args) {
		return
	}
	sawScript := false
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)
		// `-r` is php's spelling of `-e` and `-p` is node's "print this
		// expression". Both are accepted only for a NON-shell interpreter,
		// where neither can mean anything else; `sh -r` is a restricted shell
		// and `sh -p` is privileged mode, and neither takes a payload.
		isPayloadOpt := w == "-c" || w == "-e" || w == "--eval" || w == "--command" ||
			((w == "-r" || w == "-p" || w == "--print") && !isShell(name))
		if isPayloadOpt && i+1 < len(args) {
			sawScript = true
			payload := args[i+1]
			switch {
			case payload.hasSubst:
				c.textGate("interpreter payload built from a substitution")
			case isShell(name):
				c.reparse(stripAll(payload.lit), name+" -c payload")
			default:
				// A payload is SCRIPT TEXT, never a filename word, and it is
				// marked as such: the code-identifier neutraliser refuses to
				// fire at the start of a filename word, so without the marker
				// `node -p process.env.NODE_ENV` read as a path. The payload's
				// own quote markers are kept for the same reason.
				c.checkText(string(markQuote)+payload.lit, name+" script text names a secret path")
				c.decodedRead(name, stripAll(payload.lit))
				// The payload keeps its quote markers here: whether the inner
				// quotes arrive as markers or as characters depends only on how
				// the OUTER word was quoted, and the concatenation test reads
				// both spellings.
				c.concatRead(name, payload.lit)
			}
			i++
			continue
		}
		if !isFlag(w) {
			sawScript = true
		}
		c.check(args[i], name+" reads a secret path")
	}

	// An interpreter with no payload option and no script operand takes its
	// script from STDIN, and whatever fills that stdin is a separate command
	// this walk cannot connect to the reader: `echo 'cat <secret>' | sh` ran
	// the read and printed the canary. The whole-command text gate is the
	// established answer to a construct that cannot be resolved, and it is what
	// the shell floor applies here too. It sees through `echo … | sh` and
	// deliberately not through `… | base64 -d | sh`, where the payload names
	// nothing in plain text.
	if !sawScript {
		c.textGate(name + " takes its script from standard input")
	}
	for _, aw := range argWords {
		if aw == nil {
			continue
		}
		for _, p := range aw.Parts {
			if _, ok := p.(*syntax.ProcSubst); ok {
				c.textGate("interpreter fed a process substitution")
			}
		}
	}
}

// artisan judges `php artisan …`, Laravel's own command line, and reports
// whether it took the command over.
//
// Every operand artisan is handed is a COMMAND NAME, a configuration key or an
// option value, and php opens none of them: `php artisan config:show app.env`
// and `php artisan migrate --pretend` are daily work on this estate, and the
// first was refused because a Laravel configuration key is spelled exactly like
// a dotenv filename with a stem in front of it.
//
// The one operand that IS executed is tinker's `--execute`, which carries PHP.
// It is judged as script text, so `php artisan tinker --execute="readfile('.env')"`
// is still a read while `--execute="dd(config('app.env'))"` is a config lookup -
// see laravelConfigNeutral for the key that tells them apart.
func (c *checker) artisan(name string, args []flatWord) bool {
	if !strings.HasPrefix(name, "php") {
		return false
	}
	first := -1
	for i, a := range args {
		if !isFlag(stripAll(a.lit)) {
			first = i
			break
		}
	}
	if first < 0 {
		return false
	}
	if w := stripAll(args[first].lit); w != "artisan" && !strings.HasSuffix(w, "/artisan") {
		return false
	}
	for i := 0; i < len(args); i++ {
		w := stripAll(args[i].lit)
		opt, val, attached := splitOpt(w, set(`--execute`))
		if opt != "--execute" && opt != "--eval" {
			continue
		}
		if !attached && i+1 < len(args) {
			i++
			val = stripAll(args[i].lit)
		}
		c.checkText(string(markQuote)+val, "php artisan tinker --execute names a secret path")
		c.decodedRead(name, val)
		c.concatRead(name, val)
	}
	return true
}

// decodedRead denies an interpreter payload that BUILDS the filename it opens.
// `python3 -c "print(open(base64.b64decode('LmVudg==').decode()).read())"`,
// `php -r 'echo file_get_contents(base64_decode("LmVudg=="));'` and the
// String.fromCharCode spelling in node each printed a real canary while every
// path pattern looked at text that contains no filename at all.
//
// Both halves are required. A decoder on its own is ordinary work - encoding an
// image, hashing a string - and a read on its own is already judged by the name
// it opens, so demanding the pair is what keeps this from refusing either.
func (c *checker) decodedRead(name, script string) {
	if interpDecoderRe.MatchString(script) && interpReadRe.MatchString(script) {
		c.deny(catSecret, name+" payload decodes a filename and opens it, naming no path")
	}
}

// concatRead is decodedRead's twin for the payload that JOINS the filename out
// of literals rather than decoding it: `python3 -c "print(open('.en'+'v').read())"`
// and `php -r 'echo file_get_contents(".en"."v");'` each printed a real canary,
// and no decoder appears in either. See litConcatRe for the shapes accepted and
// for why both halves are demanded.
func (c *checker) concatRead(name, script string) {
	if hasLiteralConcat(script) && interpReadRe.MatchString(script) {
		c.deny(catSecret, name+" payload joins a filename out of string literals and opens it, naming no path")
	}
}

func isShell(name string) bool {
	switch name {
	case "sh", "bash", "zsh", "ksh", "dash", "ash", "busybox":
		return true
	}
	return false
}

func (c *checker) reparse(script, what string) {
	if strings.TrimSpace(script) == "" {
		return
	}
	if c.depth >= maxReparseDepth {
		c.deny(catSecret, what+": nested too deeply to judge")
		return
	}
	f, err := parse(script)
	if err != nil {
		c.textGate(what + " does not parse")
		return
	}
	sub := &checker{src: script, depth: c.depth + 1}
	sub.run(f)
	// The nested source is not the outer one, so a fail-closed gate inside it
	// must also see the outer text.
	c.findings = append(c.findings, sub.findings...)
}
