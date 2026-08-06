# Handoff — replace the secret-read guard's splitter with a real shell parser (2026-08-06)

Session that rewrote `home/dot_claude/hooks/executable_block-secret-reads.sh.tmpl` three
times, had it adversarially reviewed three times, prototyped an AST-based replacement, and
ended with the operator deciding to pursue that replacement properly. Written so the next
session reconstructs none of it from commit messages.

Everything below was measured against a rendered hook or an executed command, never inferred.

## The decision, and the evidence for it

**Pursue the parser properly. Do not adopt today's prototype as it stands.**

Graded by the same standard, on the same 250-case adversarial corpus:

| | corpus correct | defects found by review |
|---|---|---|
| shell guard (after three fix rounds) | **124** | 26, all fixed |
| Go prototype (never reviewed before) | **118** | **77 false negatives** |

Head-to-head: the shell guard wins **14**, the prototype wins **6**. Split of the
prototype's 77 — **52% policy** (word lists, path patterns), **35% mechanism** (the tree
walk), **13% undecidable statically**.

**The lesson that shapes the whole project:** 10 of the 14 losses came from one idea —
teaching the checker that grep's first operand is a pattern and awk's is a program. Attached
forms (`-eMA`, `-e1p`, `-f<prog>`) and filenames *inside* an awk or sed program became
invisible. Precision bought false negatives at roughly 1:1. Blunt text matching caught every
one.

The policy half is mechanism-independent and is already fixed in the shell guard by
`9c0b19f`. Those patterns port over unchanged.

## Blocking questions — settle before writing code

**1. Bootstrap route.** `go run` is ruled out by measurement: 55–80 ms warm, which is slower
than the shell hook it would replace, and 2.4 s cold. A prebuilt binary is therefore
required. But `go` sits in the **opt-in `go` bundle** in `home/.chezmoidata/packages.yaml`,
not in `core`, so "build during apply" fails on any machine that does not enable it — and the
guard is not optional. Three shapes, none chosen:

- move `go` into `core` (a compiler on every machine, for one hook);
- commit per-platform binaries to this public repo (anyone bootstrapping must trust the build);
- **install `shfmt` from Homebrew and drive `--to-json`** — verified working from the module
  cache with nothing installed, formula 3.13.1, bottled. Policy then lives in a jq or Python
  tree-walker. **Unverified and decisive: whether `shfmt` bottles on Linux as well as macOS.**
  Check that first.

**2. Exit contract.** The prototype returns exit **2** on crafted deep input — an
unrecoverable Go stack overflow at roughly 100k–500k nodes, ≥1.5 MB — with **empty stdout**.
Any wrapper deciding by scanning stdout for `deny` reads a crash as silence. Only 0 and 1 are
defined. Pin this at the integration boundary before anything ships.

## Mechanism fixes — the honest argument for the parser, because they are cheap

Line numbers are in `prototype/main.go` on branch `prototype/ast-secret-guard`.

1. **`WordHdoc` missing from the redirect switch** (~196–212): here-strings are never
   inspected, so `bash <<< 'cat <secret>'` leaks with the filename in plain sight. Cleanest
   hole in the program.
2. **`SglQuoted.Dollar` ignored** (~105): `$'\x2eenv'` reaches the matcher with no dot.
   7 confirmed leaks. The flag exists and is unused.
3. **`Assign.Array` never inspected** (~235): `a=(<secret>); cat "${a[0]}"` leaks.
4. **Globs and brace expansion unresolved** (~102, ~36): 12 confirmed leaks — `.en?`, `.e*`,
   `.{e,f}nv`, `kubeconfi?`. `mvdan.cc/sh/expand` exists and is not used.
5. **`trap` payloads never reparsed** (~167); function bodies not bound to call sites.
6. **Wrapper-unwrap lookahead compares the raw word** to the reader list while normalisation
   (quotes, backslash, basename) happens later (~266, ~555), so `nice /bin/cat <secret> x`
   discards the operand. It also jumps to the first known word anywhere in argv — latent
   unsoundness.

Three of those are one-liners in existing functions. A hand-written splitter offers no
comparable purchase, which is the strongest structural argument on the parser's side.

## Policy decisions

7. **Drop the per-tool argument tables, or rebuild them on a real option parser.** Half
   knowledge of grep, awk and sed flags is worse than none. This decision determines whether
   the parser is a net gain at all.
8. **Add a `default` to the command switch** (~316–388). An unlisted command with a secret
   operand is invisible today; the shell guard's bluntness caught those.
9. **Port the policy layer from `9c0b19f`** — the canonical `.kube/config` path, the
   multi-segment dotenv pattern, the secrets-directory final-segment match, the
   exposing-command set, `curl file://`, the g-prefixed GNU tools, the terminal device.

## Design constraint the operator has already weighed

Keep the shell guard as the **always-available floor**; use the parser as the primary
decision only when its binary is present. A missing binary or a parse divergence then
degrades to today's behaviour rather than to nothing.

On trusting a third-party parser: `mvdan.cc/sh` is mature, and `shfmt` is years of
production use. But in a formatter a misparse is ugly output that gets reported; in a guard
it is a silent allow that nobody notices. Same bug class, different consequence. That is why
the floor stays.

## Benchmarks, so nobody measures them again

Apple M3 Max. Spawn baseline 1.8–2.4 ms, included on both sides.

| | shell guard | Go binary |
|---|---|---|
| fast path, no secret named | 39–41 ms | 3.4–3.9 ms |
| real command mix, 300 sampled from actual transcripts | 32.7 ms median | 3.1 ms |
| 100 KB command | denies at the 8 KB cap | 3.8 ms |
| uncapped splitter, 100 KB | **203.6 s measured** | — |

The splitter is quadratic (exponent 1.98 on a doubling ladder); the parser is linear at
~12 ms/MB. Real traffic: p50 179 B, p90 634 B, **only 0.07% of commands exceed 8 KB**, so the
size cap costs almost nothing in practice. bash 3.2 versus 5.3 barely matters. Over 500 tool
calls: ~19.5 s against ~2.0 s.

**Performance should not decide this.** No single call crosses human-perceptible latency.

## Where the artifacts live

Branch **`prototype/ast-secret-guard`**, directory `prototype/` — kept out of `main` because
it is throwaway code, per the prototype skill:

- `main.go` (621 lines), `go.mod`, `go.sum`
- `demo.html` — self-contained side-by-side demo, opens by double-click
- `corpus-merged.jsonl` — 205 cases (146 suite probes plus 59 adversarial)
- `corpus-adversarial.jsonl` — 60 hand-written adversarial cases
- `results.json` — the prototype's own comparison run

The operator's username was replaced with `/Users/OPERATOR` throughout, per the redaction
rule: usernames are infrastructure identifiers and this repo is public. Paths in the corpora
are therefore placeholders, not live paths.

## Acceptance gate

`tests/test-block-secret-reads.sh` — **189 probes**. Every probe encodes a real finding from
one of the three reviews; do not delete one without deciding deliberately. One probe needs an
explicit policy answer rather than a mitigation: the oversized-command case currently passes
only because the splitter hits its 8 KB cap, and on the stated policy `echo` reads nothing, so
a parser correctly allows it.

Five other suites must stay green: `test-statusline.sh` (15), `test-rclone-conf.sh` (20),
`test-secrets-common.sh` (25), `test-secrets-backup.sh` (17), `test-git-hooks.sh` (20).

## Rules that bind the next session

Four of these cost real time in this one.

1. **Never create, close or re-scope an issue without the operator's approval.** No
   exceptions, including when a skill instructs it. Propose title, question and reason in the
   conversation. See `AGENTS.md` and `docs/agents/issue-tracker.md`.
2. **Tickets, specs, resolution comments and map entries go in ASD-STE100 Simplified
   Technical English.** Short sentences, one idea each, active voice, every technical fact
   kept.
3. **No push without explicit approval**, per the map's Notes.
4. **The live guard intercepts the agent's own Bash calls.** A command whose text names a
   secret file, or matches an exposing pattern, is denied — including `git commit` with such a
   message. Put candidates and commit messages in files and use `-F` or `--body-file`. This is
   expected behaviour, not a malfunction.
5. **Never `chezmoi apply -v` for an apply that reads the personal vault.** It captures
   stdout, the vault CLI cannot then prompt, and it prints nothing while exiting 0.
6. **Verify subagent findings before acting.** Roughly one claim in ten in this session was a
   fixture artefact rather than a real defect.
7. This working tree is the Mac's chezmoi source. Verify tree identity before a fast-forward,
   and re-fetch `origin/main` immediately before pushing.

## Also open, unrelated to the parser

- `scripts/secrets-restore.sh` and `scripts/secrets-audit.sh` have **no tests** — 439 lines
  between them. The two suites added in `5474421` are the pattern to follow.
- `secrets-backup.sh` calls a **bare `gpg`** although `git_gpg()` exists precisely because a
  bare `gpg` on WSL is the Windows executable. Pinned as a known defect by a probe in
  `tests/test-secrets-backup.sh`; belongs to the WSL batch on the map.
- Remaining guard limits are documented in the hook's own `KNOWN LIMITS` block: computed
  paths, non-shell interpreter payloads, globs, and a secret name used as a search pattern.

## Suggested skills

- `superpowers:brainstorming` — before any code. Both blocking questions are decisions the
  operator wants to make.
- `mattpocock-skills:writing-plans` — a multi-session build with a fixed acceptance gate
  deserves a written plan first.
- `mattpocock-skills:codebase-design` — the floor-plus-parser shape is an interface question:
  where the seam goes and what each layer promises.
- `superpowers:test-driven-development` — the corpus exists; write the failing probe for each
  mechanism fix first. That is how every defect in this session was found.
- `mattpocock-skills:code-review` — before anything lands. Three reviews found 103 defects
  across the two implementations; this should not change unreviewed.
- `mattpocock-skills:wayfinder` — only if the operator asks. It creates issues, and rule 1
  overrides its instructions.
- `caveman:caveman` — on by default in this estate, per the operator's global instructions.

Do not invoke `mattpocock-skills:prototype` for this again. The spike is finished and its
question is answered.
