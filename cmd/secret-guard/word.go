package main

import (
	"regexp"
	"strconv"
	"strings"

	"mvdan.cc/sh/v3/pattern"
	"mvdan.cc/sh/v3/syntax"
)

// Markers used inside a flattened word. Neither can appear in shell source, so
// neither can be forged by the command being judged.
const (
	markExp   = '\x00' // stands for an expansion whose value is not known here
	markQuote = '\x01' // stands for a quote boundary
)

// flatWord is one literal spelling of a word.
//
//   - lit  carries markQuote at every quote boundary, so a pattern can still
//     tell `jq '.vault'` (a filter) from `cat ~/.vault-token` (a filename).
//   - glob is the same text as a shell pattern: metacharacters that came from
//     inside quotes are escaped, so only a real glob is treated as one.
type flatWord struct {
	lit      string
	glob     string
	hasSubst bool // $( ), ` `, <( ) - an unresolvable command payload
	hasExp   bool // any expansion at all
}

// maxVariants caps brace expansion. `{a,b}{c,d}{e,f}…` is exponential, and a
// command guard must not be the place that discovers it.
const maxVariants = 64

// maxBraceInput caps the WORD brace expansion will look at. No path this
// guards is anywhere near it - the longest secret path in the policy is under
// 100 bytes - and without it a long word of brace groups costs seconds.
const maxBraceInput = 4096

// maxBraceTotal caps the brace text ONE COMMAND may ask to be expanded, across
// every word in it and across the two passes hitsSecretFlat makes over each.
//
// The per-word cap alone was not a budget. Sixty words of just-under-4 KB brace
// text - 243 KB in one command line, which is under the input ceiling - each
// passed the per-word test and together took 14.2 s to judge. A guard that can
// be made to think for fourteen seconds is a guard that gets killed by its
// caller and answers "undecided", which is the same as being switched off.
//
// The budget is generous against real traffic: p90 is 634 bytes of COMMAND, so
// this is twenty-five times the whole of a typical one, and a word only counts
// against it when it actually contains a brace at all.
const maxBraceTotal = 16 << 10

// braceBudget is what is LEFT of maxBraceTotal for this command. It is package
// state for the same reason SecretsDir is: this binary judges exactly one
// command per process, and decide() resets it. Past the budget a word is judged
// exactly as written, which is what braceExpand does past the per-word cap too.
var braceBudget = maxBraceTotal

type wordBuilder struct {
	lit      strings.Builder
	glob     strings.Builder
	hasSubst bool
	hasExp   bool
}

func (b *wordBuilder) write(lit, glob string) {
	b.lit.WriteString(lit)
	b.glob.WriteString(glob)
}

// flatten renders a word as the text a matcher can judge. Brace expansion is
// NOT done here: it runs over the assembled string in braceExpand, because a
// brace group can straddle several parts and a per-part expander never sees it.
func flatten(w *syntax.Word) flatWord {
	if w == nil {
		return flatWord{}
	}
	b := &wordBuilder{}
	appendParts(b, w.Parts, false)
	return flatWord{lit: b.lit.String(), glob: b.glob.String(), hasSubst: b.hasSubst, hasExp: b.hasExp}
}

func appendParts(b *wordBuilder, parts []syntax.WordPart, quoted bool) {
	for _, p := range parts {
		appendPart(b, p, quoted)
	}
}

func appendPart(b *wordBuilder, p syntax.WordPart, quoted bool) {
	switch x := p.(type) {
	case *syntax.Lit:
		// A backslash escapes the next character for the shell, so it is not
		// part of the filename: `\cat` runs cat and `~/.en\v` opens ~/.env.
		// The glob spelling keeps it, because there it is a pattern escape -
		// unless the literal sits inside quotes, where a metacharacter is just
		// a character and `cat ".en?"` opens a file with that exact name.
		lit := strings.ReplaceAll(x.Value, `\`, ``)
		if quoted {
			b.write(lit, pattern.QuoteMeta(lit, 0))
			return
		}
		b.write(lit, x.Value)

	case *syntax.SglQuoted:
		v := x.Value
		if x.Dollar {
			// ANSI-C quoting is evaluated by the shell, so `$'\x2eenv'`
			// reaches the reader as the real filename while the command
			// text carries no dot at all.
			v = decodeANSIC(v)
		}
		q := string(markQuote)
		b.write(q+v+q, q+pattern.QuoteMeta(v, 0)+q)

	case *syntax.DblQuoted:
		b.write(string(markQuote), string(markQuote))
		appendParts(b, x.Parts, true)
		b.write(string(markQuote), string(markQuote))

	case *syntax.CmdSubst, *syntax.ProcSubst:
		b.hasExp, b.hasSubst = true, true
		b.write(string(markExp), string(markExp))

	default:
		b.hasExp = true
		b.write(string(markExp), string(markExp))
	}
}

// braceExpand returns every spelling a word takes through brace expansion:
// `.{e,f}nv` becomes `.env` and `.fnv`, `~/.env{,.local}` becomes both paths,
// and `.e{n..n}v` becomes `.env`.
//
// It runs over the ASSEMBLED word rather than through syntax.SplitBraces,
// which rewrites the word into BraceExp nodes that syntax.Walk then panics on.
// Running over the assembled word is also what makes `.{"e",f}nv` work: bash
// expands braces BEFORE it removes quotes, so a quoted element still takes
// part while a quoted BRACE does not. The quote markers already in the string
// are what tells the two apart.
//
// A group with no top-level comma and no range is not an expansion, so `{}` in
// `find -exec … {} \;` is left exactly as it is.
// The second return value reports that the BUDGET ran out on this word while a
// brace was still standing in it. Judging such a word as written is what the
// per-word cap does, and at the budget it is a hole rather than a compromise:
// six just-under-4 KB brace words exhaust the shared budget, and the `cat
// .{e,x}nv` behind them was then judged literally and allowed - confirmed
// printing a real canary. So past the budget an unexpanded brace is a denial,
// because the guard can no longer say what the word spells.
func braceExpand(s string) ([]string, bool) {
	// Almost every word has no brace at all, and this runs twice per check.
	//
	// The length cap is what bounds the work. `.{e,f}` repeated 50 000 times
	// is a 250 KB word whose expansion copies the whole tail once per group
	// per level, which measured 8.7 s. A FILENAME is short: padding inside the
	// word cannot help an attacker either, because the padding lands next to
	// the name and the patterns need a boundary there. So a word too long to
	// be a path is judged as written.
	if len(s) > maxBraceInput || !strings.ContainsRune(s, '{') {
		return []string{s}, false
	}
	// The whole command shares one budget, so a long word cannot be repeated
	// until the total is what costs the seconds.
	if len(s) > braceBudget {
		braceBudget = 0
		return []string{s}, true
	}
	braceBudget -= len(s)
	out := braceExpandDepth(s, 0)
	if len(out) > maxVariants {
		// Too many spellings to enumerate. Concatenating them all over-matches
		// rather than under-matches, which is the safe direction here.
		return []string{strings.Join(out[:maxVariants], " ")}, false
	}
	return out, false
}

func braceExpandDepth(s string, depth int) []string {
	if depth > 8 {
		return []string{s}
	}
	inQuote := false
	for i := 0; i < len(s); i++ {
		if s[i] == markQuote {
			inQuote = !inQuote
			continue
		}
		if s[i] != '{' || inQuote {
			continue
		}
		nest, end, commas, q := 0, -1, []int(nil), false
		for j := i; j < len(s) && end < 0; j++ {
			switch s[j] {
			case markQuote:
				q = !q
			case '{':
				if !q {
					nest++
				}
			case ',':
				if !q && nest == 1 {
					commas = append(commas, j)
				}
			case '}':
				if !q {
					if nest--; nest == 0 {
						end = j
					}
				}
			}
		}
		if end < 0 {
			break // unbalanced: nothing to expand
		}
		pre, post := s[:i], s[end+1:]
		var elems []string
		if len(commas) > 0 {
			start := i + 1
			for _, c := range commas {
				elems = append(elems, s[start:c])
				start = c + 1
			}
			elems = append(elems, s[start:end])
		} else if seq := sequenceElems(s[i+1 : end]); seq != nil {
			elems = seq
		} else {
			i = end // a group, not an expansion; look past it
			continue
		}

		tails := braceExpandDepth(post, depth+1)
		var out []string
		for _, e := range elems {
			for _, ee := range braceExpandDepth(e, depth+1) {
				for _, t := range tails {
					out = append(out, pre+ee+t)
					if len(out) > maxVariants {
						return out
					}
				}
			}
		}
		return out
	}
	return []string{s}
}

// sequenceElems expands the `{x..y}` form bash also treats as a brace
// expansion. `.e{n..n}v` spells `.env` with no comma in sight, so a
// comma-only expander walked straight past it. Returns nil when the body is
// not a sequence.
func sequenceElems(body string) []string {
	parts := strings.Split(body, "..")
	if len(parts) < 2 || len(parts) > 3 {
		return nil
	}
	from, to := parts[0], parts[1]
	if len(from) == 1 && len(to) == 1 && isRangeChar(from[0]) && isRangeChar(to[0]) {
		lo, hi := from[0], to[0]
		if lo > hi {
			lo, hi = hi, lo
		}
		if int(hi-lo) >= maxVariants {
			return nil
		}
		var out []string
		for c := lo; c <= hi; c++ {
			out = append(out, string(c))
		}
		return out
	}
	lo, err1 := strconv.Atoi(from)
	hi, err2 := strconv.Atoi(to)
	if err1 != nil || err2 != nil {
		return nil
	}
	if lo > hi {
		lo, hi = hi, lo
	}
	if hi-lo >= maxVariants {
		return nil
	}
	var out []string
	for n := lo; n <= hi; n++ {
		out = append(out, strconv.Itoa(n))
	}
	return out
}

func isRangeChar(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// decodeANSIC evaluates the escapes bash resolves inside $'…'.
func decodeANSIC(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' || i+1 >= len(s) {
			b.WriteByte(s[i])
			continue
		}
		i++
		switch c := s[i]; c {
		case 'a':
			b.WriteByte(7)
		case 'b':
			b.WriteByte(8)
		case 'e', 'E':
			b.WriteByte(27)
		case 'f':
			b.WriteByte(12)
		case 'n':
			b.WriteByte('\n')
		case 'r':
			b.WriteByte('\r')
		case 't':
			b.WriteByte('\t')
		case 'v':
			b.WriteByte(11)
		case '\\', '\'', '"', '?':
			b.WriteByte(c)
		case 'x':
			i += readHex(s, i+1, 2, &b)
		case 'u':
			i += readRune(s, i+1, 4, &b)
		case 'U':
			i += readRune(s, i+1, 8, &b)
		case 'c':
			if i+1 < len(s) {
				i++
				b.WriteByte(s[i] & 0x1f)
			}
		default:
			if c >= '0' && c <= '7' {
				n := 0
				v := 0
				for n < 3 && i+n < len(s) && s[i+n] >= '0' && s[i+n] <= '7' {
					v = v*8 + int(s[i+n]-'0')
					n++
				}
				b.WriteByte(byte(v))
				i += n - 1
			} else {
				b.WriteByte('\\')
				b.WriteByte(c)
			}
		}
	}
	return b.String()
}

func isHex(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

func readHex(s string, start, maxLen int, b *strings.Builder) int {
	n := 0
	for n < maxLen && start+n < len(s) && isHex(s[start+n]) {
		n++
	}
	if n == 0 {
		b.WriteString(`\x`)
		return 0
	}
	v, _ := strconv.ParseUint(s[start:start+n], 16, 32)
	b.WriteByte(byte(v))
	return n
}

func readRune(s string, start, maxLen int, b *strings.Builder) int {
	n := 0
	for n < maxLen && start+n < len(s) && isHex(s[start+n]) {
		n++
	}
	if n == 0 {
		b.WriteString(`\u`)
		return 0
	}
	v, _ := strconv.ParseUint(s[start:start+n], 16, 32)
	b.WriteRune(rune(v))
	return n
}

// ---------- the single secret test ----------

func stripAll(s string) string {
	return strings.ReplaceAll(s, string(markQuote), "")
}

// stripInner removes a quote boundary only where it sits BETWEEN two characters
// a filename is made of. That is what quote splitting actually looks like -
// `.secre"ts"` - and it leaves a quote that opens a word alone, so a leading
// quote still marks a filter expression.
func stripInner(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == markQuote && i > 0 && i+1 < len(s) &&
			isNameByte(s[i-1]) && isNameByte(s[i+1]) {
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func isNameByte(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return true
	}
	switch c {
	case '_', '.', '/', '~', '-':
		return true
	}
	return false
}

// hitsSecretFlat is the single test every decision uses, so the split between
// context-free and contextual arms can never be applied unevenly.
func hitsSecretFlat(f flatWord) bool {
	lits, exhausted := braceExpand(f.lit)
	if exhausted {
		return true
	}
	for _, lit := range lits {
		if hitsSecretSpelling(lit) {
			return true
		}
	}
	globs, exhausted := braceExpand(f.glob)
	if exhausted {
		return true
	}
	for _, glob := range globs {
		if globHitsSecret(stripAll(glob)) {
			return true
		}
	}
	return false
}

// hitsSecretOperand is hitsSecretFlat for a word standing where a READER
// expects a FILENAME. There it also applies the contextual patterns that
// hitsSecretSpelling reserves for words carrying a path separator.
//
// The separator condition exists to protect `jq '.vault.name'`, where a quoted
// word is a FILTER rather than a path. That is an argument about the ARGUMENT,
// not about the quoting: the tools with a filter or program slot skip it before
// they get here, so every word that reaches this one is an operand a reader will
// open. `cat '.vault-token'` and `cat '.secrets'` each printed a real canary
// while `cat .vault-token` was refused, which is the same file spelled two ways.
func hitsSecretOperand(f flatWord) bool {
	if hitsSecretFlat(f) {
		return true
	}
	lits, exhausted := braceExpand(f.lit)
	if exhausted {
		return true
	}
	for _, lit := range lits {
		if matchAny(contextualPathRes, neutralise(collapseSlashes(lit))) {
			return true
		}
	}
	return false
}

func hitsSecretSpelling(lit string) bool {
	// A doubled separator and a `/./` detour name the same file as the plain
	// spelling and matched none of the patterns.
	lit = collapseSlashes(lit)
	v1 := neutralise(lit)
	// The quote markers come off AFTER a first pass of the neutralisers,
	// because one of them depends on the character standing in FRONT of the
	// identifier, and for `node -p "process.env.NODE_ENV"` that character is
	// the marker itself. Stripping first threw the context away and refused an
	// ordinary property access; running the pass twice keeps both that context
	// and the split-name case v2 exists for, `.sec"ret"s`.
	v2 := neutralise(stripAll(neutralise(lit)))
	v3 := neutralise(stripInner(lit))

	if matchAny(contextFreeRes, v1) || matchAny(contextFreeRes, v2) || matchAny(contextFreeRes, v3) {
		return true
	}
	if matchAny(contextualRes, v1) || matchAny(contextualRes, v3) {
		return true
	}
	// A quoted operand carrying a path separator is a filename however it is
	// quoted, which the arms above deliberately refuse to assume.
	if strings.ContainsRune(lit, '/') && matchAny(contextualPathRes, v1) {
		return true
	}
	return hitsSecretsDir(v2)
}

// isFilterExpression reports whether a word is a jq or yq program rather than a
// filename. Only the shape matters: a program begins at the root of the
// document and is written as one quoted word.
//
// This exists because `.env` is matched with no boundary in front of it - which
// is what catches `prod.env` and `local.env` - so every jq filter that reaches
// an `env` key matched it too, and `jq '.env' package.json`,
// `docker inspect x | jq '.[0].Config.Env'` and
// `kubectl get pod x -o json | jq '.spec.containers[0].env'` were all refused.
func isFilterExpression(f flatWord) bool {
	lit := f.lit
	if len(lit) < 2 || lit[0] != markQuote {
		return false // an unquoted word is a filename, not a program
	}
	inner := stripAll(lit)
	if inner == "" || strings.ContainsRune(inner, '/') {
		return false // a path separator makes it a filename again
	}
	switch inner[0] {
	case '.', '$':
		return true
	}
	return false
}

// sedAddressRe recognises a sed line address followed by a command letter:
// `1p`, `$d`, `1,40p`, `2i\…`. The command letter is what keeps a filename out:
// `2024-report.txt` carries digits and no letter behind them.
var sedAddressRe = regexp.MustCompile(`^([0-9]+|\$)(,([0-9]+|\$))?!?[a-zA-Z]`)

// isProgramText reports whether a word is a sed or awk SCRIPT rather than a
// filename. sed and awk take the script as their first bare operand, so without
// this every search pattern naming a secret was read as a file to open.
//
// The bar is a recognisable script SHAPE, never "any quoted word": a quoted
// word is a filename at least as often as it is a program, and `sed -n p
// '/home/u/.env'` must still be a read. The three shapes accepted are the ones
// sed and awk actually have:
//
//   - an awk rule, which is written inside braces;
//   - a substitution or transliteration - `s/a/b/`, `s|a|b|`, `y/abc/xyz/` -
//     recognised by its repeated delimiter rather than by a fixed `/`;
//   - a `/regex/` address, where what follows the closing delimiter is a sed
//     command rather than a filename, which is what keeps `/home/u/.env` out.
func isProgramText(f flatWord) bool {
	lit := f.lit
	if len(lit) < 2 || lit[0] != markQuote {
		return false // an unquoted word is a filename, not a program
	}
	// A word the SHELL will brace-expand is not one program word, whatever it
	// looks like afterwards. `sed '' ''{.env,}` expands to `sed '' .env ''`, so
	// the secret is in a FILE operand - but the `{ }` in the unexpanded spelling
	// made it read as an awk rule, and the slot it was skipped in was the
	// script's. The empty first word had already been stepped over for BSD
	// sed's `-i ''`, which is what left the script slot open for it.
	if vars, exhausted := braceExpand(lit); exhausted || len(vars) > 1 {
		return false
	}
	inner := stripAll(lit)
	if inner == "" {
		return false
	}
	if strings.ContainsRune(inner, '{') && strings.ContainsRune(inner, '}') {
		return true
	}
	if (inner[0] == 's' || inner[0] == 'y') && len(inner) > 3 && isSedDelim(inner[1]) {
		if strings.Count(inner, string(inner[1])) >= 3 {
			return true
		}
	}
	if inner[0] == '/' {
		if i := strings.LastIndexByte(inner, '/'); i > 0 {
			return isSedCommandTail(inner[i+1:])
		}
	}
	return sedAddressRe.MatchString(inner)
}

// isSedDelim reports whether a byte can stand as an s/// delimiter. Letters,
// digits, whitespace and backslash cannot, which is what stops `set`, `soft`
// and `system` from reading as substitutions.
func isSedDelim(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return false
	}
	switch c {
	case ' ', '\t', '\n', '\\':
		return false
	}
	return true
}

// isSedCommandTail reports whether what follows a closing `/` is sed's own
// vocabulary rather than the last segment of a path. `/\.env/p` ends in a
// command; `/home/u/.env` ends in a filename.
func isSedCommandTail(s string) bool {
	for i := 0; i < len(s); i++ {
		if !strings.ContainsRune("pdDgGhHnNpPqQxz=!,;{}bt lwr", rune(s[i])) {
			return false
		}
	}
	return true
}

// ---------- sed and awk scripts that open files ----------

// scriptOpensFile reports whether a sed or awk SCRIPT carries a construct that
// opens a file. It is the discriminator that lets the script slot stay skipped:
// a script that only matches and substitutes names no file, so judging its text
// would refuse the search patterns this guard is most often asked about, while
// a script that reads or writes one has the filename written inside it.
func scriptOpensFile(name, script string) bool {
	switch name {
	case "sed", "gsed":
		return sedOpensFile(script)
	}
	return awkOpensFileRe.MatchString(script)
}

// awkOpensFileRe lists awk's own file primitives. `getline < f` reads a file,
// `system()` runs a shell command, `print > f` and `close()` write and flush
// one, and `ENVIRON` reaches the whole environment. Each was confirmed printing
// a real canary from inside a script the guard skipped.
//
// The redirection test demands the `>` on the SAME statement as the print,
// which is what keeps `awk '$3 > 100 {print $1}'` and `awk '{print $1}'` out:
// in both, what follows `print` reaches a statement boundary first.
// `ARGV` and `ARGC` are awk's own argument vector, and awk opens every element
// of it as an input file. `awk 'BEGIN{ARGV[1]=".env";ARGC=2}{print}'` and the
// push form `awk 'BEGIN{ARGV[ARGC++]=".env"}{print}'` each printed a real canary
// with no `getline` and no `system(` anywhere in the script: the filename is
// injected into the vector and awk's ordinary main loop does the reading.
//
// `print | "cmd"` pipes the output into a SHELL COMMAND, which is the same
// primitive as `system()` written the other way round, and only `>` was tested.
// The pipe is matched on the same statement as the print, exactly as the
// redirection is.
var awkOpensFileRe = regexp.MustCompile(
	`(?i)\b(getline|system[[:space:]]*\(|close[[:space:]]*\(|ENVIRON\b|ARGV\b|ARGC\b)|\b(print|printf)\b[^;}\n]*[>|]`)

// awkSystemRe pulls the shell command out of `system("…")` so it can be judged
// as the shell code it is.
var awkSystemRe = regexp.MustCompile(`(?i)\bsystem[[:space:]]*\([[:space:]]*"([^"]*)"`)

// awkPipeRe pulls the shell command out of `print … | "cmd"` and out of
// `"cmd" | getline`. Both hand a whole command line to the shell, so both are
// judged as the shell code they are: `awk 'BEGIN{print "x" | "cat .env"}'`
// printed a real canary. `|&` is gawk's co-process spelling of the same thing.
var awkPipeRe = regexp.MustCompile(`\|&?[[:space:]]*"([^"]*)"|"([^"]*)"[[:space:]]*\|&?[[:space:]]*getline`)

func awkSystemArgs(name, script string) []string {
	switch name {
	case "sed", "gsed":
		return nil
	}
	var out []string
	for _, m := range awkSystemRe.FindAllStringSubmatch(script, -1) {
		out = append(out, m[1])
	}
	for _, m := range awkPipeRe.FindAllStringSubmatch(script, -1) {
		if m[1] != "" {
			out = append(out, m[1])
		}
		if m[2] != "" {
			out = append(out, m[2])
		}
	}
	return out
}

// foldQuotes rewrites every quote spelling to the quote marker, so one pattern
// can read a payload that arrives with its inner quotes as markers and one that
// arrives with them as ordinary characters. Which of the two a payload is
// depends only on how the OUTER word was quoted, which says nothing about what
// the payload does.
func foldQuotes(s string) string {
	return strings.NewReplacer(`"`, string(markQuote), `'`, string(markQuote)).Replace(s)
}

// hasLiteralConcat reports whether a payload joins two string LITERALS. See
// litConcatRe: paired with a read primitive, that is a filename built out of
// characters, which no path pattern can see.
func hasLiteralConcat(script string) bool {
	return litConcatRe.MatchString(foldQuotes(script))
}

// sedOpensFile reports whether a sed script carries `r`, `R`, `w` or `W` in a
// COMMAND position, or an `s///w` flag. All four name a file: `sed '$r .env'
// package.json` appends the secret to what it prints, and `sed '/x/w out'`
// copies matching lines into a file of its own.
//
// The position is what makes this precise rather than a text search. A bare
// search for `w` would fire on every `s/foo/war/`, and a bare search for `r`
// on every regex carrying one. So the script is scanned the way sed reads it:
// separators, then an optional address, then the command letter.
func sedOpensFile(s string) bool {
	i := 0
	for i < len(s) {
		for i < len(s) && strings.ContainsRune(" \t\n;{}", rune(s[i])) {
			i++
		}
		if i >= len(s) {
			return false
		}
		if s[i] == '#' {
			for i < len(s) && s[i] != '\n' {
				i++
			}
			continue
		}
		i = skipSedAddress(s, i)
		for i < len(s) && (s[i] == ' ' || s[i] == '\t' || s[i] == '!') {
			i++
		}
		if i >= len(s) {
			return false
		}
		switch c := s[i]; c {
		// `e` is GNU sed's EXECUTE command: `sed '1e cat .env' package.json`
		// runs the rest of the line as a shell command and prints its output.
		// It reaches a file exactly as `r` does, one indirection further on.
		case 'r', 'R', 'w', 'W', 'e':
			return true
		case 's', 'y':
			end, flags := skipSedSubst(s, i)
			// `s/a/b/gw out.txt` writes the changed lines to a file, and the
			// `w` rides on the flag list rather than standing as a command.
			//
			// `e` rides there too, and that was the spelling that slipped:
			// `sed 's/^/cat .env/e' package.json` substitutes the command INTO
			// the pattern space and then executes it, printing a real canary,
			// while the `e` command form above was the only one tested.
			if strings.ContainsAny(flags, "wWe") {
				return true
			}
			if end <= i {
				return false
			}
			i = end
		case 'a', 'i', 'c':
			// Appended, inserted or changed TEXT runs to the end of the line
			// and is not sed vocabulary at all.
			for i < len(s) && s[i] != '\n' {
				i++
			}
		default:
			for i < len(s) && s[i] != '\n' && s[i] != ';' && s[i] != '}' {
				i++
			}
		}
	}
	return false
}

// skipSedAddress steps over `1`, `$`, `1,40`, `0~3`, `/re/` and `\%re%`, in
// either half of a range.
func skipSedAddress(s string, i int) int {
	i = skipOneSedAddress(s, i)
	if i < len(s) && (s[i] == ',' || s[i] == '~') {
		i = skipOneSedAddress(s, i+1)
	}
	return i
}

func skipOneSedAddress(s string, i int) int {
	if i >= len(s) {
		return i
	}
	switch {
	case s[i] == '$':
		return i + 1
	case s[i] >= '0' && s[i] <= '9':
		for i < len(s) && s[i] >= '0' && s[i] <= '9' {
			i++
		}
		return i
	case s[i] == '/':
		return skipSedAddressFlags(s, skipDelimited(s, i, '/'))
	case s[i] == '\\' && i+1 < len(s):
		return skipSedAddressFlags(s, skipDelimited(s, i+1, s[i+1]))
	}
	return i
}

// skipSedAddressFlags steps over the `I` and `M` an address may carry.
func skipSedAddressFlags(s string, i int) int {
	for i < len(s) && (s[i] == 'I' || s[i] == 'M') {
		i++
	}
	return i
}

// skipDelimited steps over `<delim>…<delim>`, honouring backslash escapes, and
// returns the index just past the closing delimiter.
func skipDelimited(s string, i int, delim byte) int {
	for i++; i < len(s); i++ {
		if s[i] == '\\' {
			i++
			continue
		}
		if s[i] == delim {
			return i + 1
		}
	}
	return len(s)
}

// skipSedSubst steps over an `s` or `y` command and returns the index past it
// together with its flag text, which is where an `s///w` file lands.
func skipSedSubst(s string, i int) (int, string) {
	if i+1 >= len(s) || !isSedDelim(s[i+1]) {
		return i + 1, ""
	}
	d := s[i+1]
	k, parts := i+2, 0
	for k < len(s) && parts < 2 {
		if s[k] == '\\' {
			k += 2
			continue
		}
		if s[k] == d {
			parts++
		}
		k++
	}
	start := k
	for k < len(s) && s[k] != ';' && s[k] != '\n' && s[k] != '}' {
		k++
	}
	return k, s[start:k]
}

// hitsSecretText judges raw command text, where quote characters stand in for
// the markers. Used for the fail-closed gate and for interpreter payloads.
//
// The text is judged TWICE where escapes are present, once as written and once
// with them resolved. A substitution can spell the filename in escapes that the
// tool inside it - not the shell - is the one to decode: `cat "$(printf
// '\56env')"` and `cat "$(printf '\x2eenv')"` both printed a real canary, and
// the command text they were judged on contains no dot at all. Judging the
// resolved spelling as WELL as the written one is what keeps `sed 's/\.env/x/'`
// readable: `\.` resolves to `\.`, so nothing changes for it either way.
func hitsSecretText(s string) bool {
	if hitsSecretFlat(flatWord{lit: foldQuotes(s), glob: s}) {
		return true
	}
	if d := decodeANSIC(s); d != s {
		return hitsSecretFlat(flatWord{lit: foldQuotes(d), glob: d})
	}
	return false
}
