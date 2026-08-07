package main

import (
	"regexp"
	"strings"
	"sync"

	"mvdan.cc/sh/v3/pattern"
)

// A glob names a file the command text never spells out: `~/.en?`, `.e*` and
// `kubeconfi?` all open the real secret while every pattern in policy.go looks
// straight past them. Resolving the glob against the filesystem is not an
// option - a guard must not stat the paths it is asked about, and the file may
// live on another machine - so the glob is matched against the names a secret
// can have instead.
//
// Candidates are grouped by path-segment count, and the glob is tested one
// tail at a time: `~/.kube/conf?g` is tested as `conf?g` and as `.kube/conf?g`.
// A candidate carries which PART of it is distinctive, because that decides
// what a pattern has to pin down before it counts as naming the file.
//
// For nearly every secret here the distinctive part is the whole name or its
// suffix: `.env`, `kubeconfig`, `.tfstate`. Any pattern that matches one of
// those is naming it.
//
// `vault.yml` is the exception, and getting it wrong cost a defect in each
// direction. Its extension is the commonest one in this estate, so a candidate
// that ignores the stem turns every `cat *.yaml` into a refusal; but demanding
// that a pattern begin with a literal let `cat *ault.yml`, `cat *env` and
// `cat *ubeconfig` through, each confirmed printing a real file. The stem is
// what makes a vault file a vault file, so the stem is what a pattern must pin.
type globCandidate struct {
	name    string
	stemKey bool // the pattern must pin part of the name BEFORE its last dot
}

var globCandidates = map[int][]globCandidate{
	1: {
		{name: ".env"}, {name: ".env.local"}, {name: ".env.production"},
		{name: "prod.env"}, {name: "local.env"}, {name: ".envrc"},
		{name: "kubeconfig"}, {name: "talosconfig"},
		{name: "terraform.tfstate"}, {name: "prod.tfstate"}, {name: "dev.tfstate"},
		{name: "vault.yml", stemKey: true}, {name: "vault.yaml", stemKey: true},
		{name: ".vault-token"}, {name: "secrets.vault"}, {name: ".secrets"},
	},
	2: {
		{name: ".kube/config"}, {name: ".talos/config"},
		{name: ".hindsight/claude-code.json"}, {name: ".secrets/token"},
	},
}

// minGlobLiterals rejects a pattern too vague to name anything in particular.
// `cat *` and `grep x *` would otherwise match `kubeconfig` and be refused,
// which is a false positive on ordinary work; `.e*` carries two literal
// characters and is a confirmed leak, so the bar sits just below it.
//
// A DOT-LEADING pattern is exempt, and that exemption is the whole point:
// `cat .*` and `cat .??*` pin one literal each yet expand to every dotfile
// there is, which makes them the broadest reads in the language rather than the
// most innocent. Both were confirmed to print a real .env.
const minGlobLiterals = 2

var (
	globCacheMu sync.Mutex
	globCache   = map[string]*regexp.Regexp{}

	// globQualifierRe matches a zsh glob qualifier at the very END of a word.
	// The body is restricted to the characters qualifiers are actually made of,
	// so an ordinary filename carrying parentheses - `report (final)` - is left
	// alone. A qualifier only ever appears once, and only last.
	globQualifierRe = regexp.MustCompile(`\(([-.@=%^+,:/a-zA-Z0-9\[\]]{0,24})\)$`)
)

func globRegexp(pat string) *regexp.Regexp {
	globCacheMu.Lock()
	defer globCacheMu.Unlock()
	if re, ok := globCache[pat]; ok {
		return re
	}
	var re *regexp.Regexp
	if expr, err := pattern.Regexp(pat, 0); err == nil {
		re, _ = regexp.Compile(`(?i)^` + expr + `$`)
	}
	globCache[pat] = re
	return re
}

// literalCount counts the characters a pattern pins down, ignoring its
// metacharacters and their escapes.
func literalCount(pat string) int {
	n := 0
	inClass := false
	for i := 0; i < len(pat); i++ {
		c := pat[i]
		switch {
		case c == '\\' && i+1 < len(pat):
			i++
			n++
		case inClass:
			if c == ']' {
				inClass = false
			}
		case c == '[':
			inClass = true
		case c == '*' || c == '?':
		default:
			n++
		}
	}
	return n
}

// globHitsSecret reports whether a pattern could name one of the secrets.
func globHitsSecret(glob string) bool {
	// The expansion marker is substituted FIRST. Testing for a metacharacter
	// before it meant a word whose only wildcard IS the expansion returned
	// early, so `cat ~/.e${nope}nv` and `cat ~/.k${x}ube/config` were never
	// looked at - the value is unknown, so it stands for anything.
	glob = strings.ReplaceAll(glob, string(markExp), "*")
	// A trailing zsh glob QUALIFIER is not part of the name. `cat ~/.en?(.)`
	// asks for the regular files matching `~/.en?` and printed a real canary,
	// while `(.)` turned the tail into a pattern that matches nothing this
	// file knows. It is stripped before anything else looks at the word.
	glob = globQualifierRe.ReplaceAllString(glob, "")
	if glob == "" || !pattern.HasMeta(glob, 0) {
		return false
	}

	segs := strings.Split(glob, "/")

	// zsh's `**/` matches ZERO directories as readily as many, so the path with
	// those segments removed is one spelling of the same file - and it is a
	// spelling with no metacharacter left in it, which is why the tail loop
	// below could never see it. `cat ~/.kube/**/config` printed a real canary
	// while every pattern in the policy looked straight past it.
	if kept := dropTreeSegs(segs); len(kept) != len(segs) {
		if hitsSecretSpelling(strings.Join(kept, "/")) {
			return true
		}
		segs = kept
	}

	// The machine-local secrets directory is matched per SEGMENT, not only at
	// the end of the path: `~/.local/share/6f2a1c94-…-*/token` names a file
	// inside it while the last segment is an innocent `token`.
	if b := secretsDirBase(); b != "" {
		for i, seg := range segs {
			if !pattern.HasMeta(seg, 0) {
				continue
			}
			re := globRegexp(seg)
			if re == nil || !re.MatchString(b) {
				continue
			}
			if literalCount(seg) >= minGlobLiterals {
				return true
			}
			// A segment too vague to name anything on its own - a bare `*` -
			// still names this directory when the path in FRONT of it is the
			// directory's own parent. `cat <secretsdir-parent>/*/token` was
			// confirmed reading a real file. Without the prefix test the same
			// segment would match every `cat /tmp/*/x` in ordinary work, which
			// is why the literal bar cannot simply be lowered.
			if i > 0 && strings.HasPrefix(strings.ToLower(SecretsDir),
				strings.ToLower(strings.Join(segs[:i], "/"))+"/") {
				return true
			}
		}
	}

	for k := 1; k <= 2 && k <= len(segs); k++ {
		tail := strings.Join(segs[len(segs)-k:], "/")
		dotLed := strings.HasPrefix(tail, ".")
		if !pattern.HasMeta(tail, 0) {
			continue
		}
		if literalCount(tail) < minGlobLiterals && !dotLed {
			continue
		}
		re := globRegexp(tail)
		if re == nil {
			continue
		}
		for _, cand := range globCandidates[k] {
			// A shell glob does not match a leading dot unless the pattern
			// spells the dot out, so `*` never expands to `.env`.
			if strings.HasPrefix(cand.name, ".") && !dotLed {
				continue
			}
			if cand.stemKey && literalCount(stemOf(tail)) < minGlobLiterals {
				continue
			}
			if re.MatchString(cand.name) {
				return true
			}
		}
	}
	return false
}

// hasTreeGlob reports whether a word is a recursive glob that names nothing in
// particular. `cat **/*` reads every file under the working directory and spells
// out not one of them, which is the same class as `rg` and `grep -r`; it printed
// a canary from a subdirectory.
//
// Only the UNQUOTED spelling counts, which is why the glob rendering is what is
// read: inside quotes a `*` is a character, and `grep '\*\*' notes.md` searches
// for two asterisks.
//
// The LAST segment has to be vague as well, and that is where this stops short
// of the whole construct. Round 4 decided that `cat src/**/*.go`,
// `cat **/*.yaml` and `cat docs/**/*.md` are ordinary work on this estate, and
// they are: a typed tail names a class of file the operator asked for by
// extension. A tail that pins nothing - `**/*`, `**`, `**/*.*` - asks for
// everything there is, which is the read no path rule can see.
func hasTreeGlob(glob string) bool {
	segs := strings.Split(strings.ReplaceAll(glob, string(markQuote), ""), "/")
	tree := false
	for _, seg := range segs {
		if seg == "**" || seg == "***" {
			tree = true
		}
	}
	if !tree {
		return false
	}
	last := segs[len(segs)-1]
	return pattern.HasMeta(last, 0) && literalCount(last) < minGlobLiterals
}

// hookGlobHits reports whether a PATTERN could name the pre-commit hook.
// `rm ~/.config/git/hooks/pre-comm*` and `rm .git/hooks/*` each remove the
// estate-wide gitleaks scan while spelling `pre-commit` nowhere, so the literal
// match hookFileRe makes is not enough on its own.
//
// The last two segments are what decide, exactly as they do for the file: the
// one before must name a hooks directory and the last must be able to expand to
// `pre-commit`. That pairing is what keeps `rm build/*` and `rm dist/pre-*` out.
func hookGlobHits(glob string) bool {
	segs := strings.Split(glob, "/")
	if len(segs) < 2 {
		return false
	}
	prev, last := segs[len(segs)-2], segs[len(segs)-1]
	if !pattern.HasMeta(prev, 0) && !pattern.HasMeta(last, 0) {
		return false // no pattern at all; hookFileRe already answered
	}
	return globSegMatches(prev, "hooks") && globSegMatches(last, "pre-commit")
}

// globSegMatches compares one path segment to a name, as a glob when it carries
// a metacharacter and case-insensitively when it does not.
func globSegMatches(seg, name string) bool {
	if !pattern.HasMeta(seg, 0) {
		return strings.EqualFold(seg, name)
	}
	re := globRegexp(seg)
	return re != nil && re.MatchString(name)
}

// dropTreeSegs removes the segments that stand for "any number of directories,
// including none": zsh's `**` and `***`.
func dropTreeSegs(segs []string) []string {
	kept := make([]string, 0, len(segs))
	for _, s := range segs {
		if s == "**" || s == "***" {
			continue
		}
		kept = append(kept, s)
	}
	return kept
}

func secretsDirBase() string {
	b := SecretsDir
	if i := strings.LastIndexByte(b, '/'); i >= 0 {
		b = b[i+1:]
	}
	return b
}

// stemOf returns the part of a pattern before its final dot. `*.yaml` pins
// nothing of a stem; `*ault.yml` pins four characters of one.
func stemOf(pat string) string {
	if i := strings.LastIndexByte(pat, '.'); i > 0 {
		return pat[:i]
	}
	return pat
}
