# Handoff — bootstrap verification on a fresh machine (2026-07-31)

Session that resolved [#9](https://github.com/myprysm/dotfiles/issues/9) and everything it dragged out
behind it. Written so the next session does not have to reconstruct any of this from commit messages.

## Where things stand

The one-liner takes a bare Ubuntu 26.04 WSL image to `EXIT=0` with **all eight bundles enabled**, and
every bundle's binaries are reachable from a real interactive login shell. `chezmoi status` afterwards
shows exactly one drift line, `.agents/.skill-lock.json`, which is known and ticketed.

`main` is at `cbc924b`. Fifteen commits landed, all signed.

## Verified, by observation on the target machine

Not inferred from exit codes or from fetching `main` locally — both of those misled during this session.

- Naked Ubuntu 26.04 (glibc 2.43, `/bin/sh` = dash) → complete machine, first attempt, cold brew cache.
- Both `bootstrap.sh` abort paths fired for real, forced by genuine conditions rather than edited code:
  automount disabled so `/mnt/c` vanished (no Windows GnuPG), and binfmt interop unregistered (shim
  present but unrunnable).
- `secrets-restore.sh` on a machine holding nothing: 28 restored, 0 skipped. **The mode-600 write path
  ran live for the first time** — only the 644 arm had ever executed before.
- `git commit -S` produced a good signature on the rebuilt machine (`sig=G`, ultimate trust).
- Idempotency: two consecutive re-runs, both `EXIT=0`.
- Bundle binaries resolve in an interactive login shell: ffmpeg, exiftool, vips, qpdf, llama-cli, mvn,
  kubectl, helm, terraform, rclone, starship, rustc, cargo. Both JDKs installed; four krew plugins;
  27 skills restored; rclone.conf written 600 with personal remotes only.

## NOT verified — do not assume these

- **macOS. Nothing here was run on a Mac.** That is [#13](https://github.com/myprysm/dotfiles/issues/13).
- **The checkbox starts empty on a fresh machine.** The empty-defaults argument is explicit in the
  template and renders correctly, but nobody has watched the first prompt on a naked machine.
- **The work bundle.** Deliberately unsupported on Linux; it now degrades instead of failing.
- **`git commit -S` on a *different* Windows host.** The test distro shares its host's Windows GnuPG
  store, so the Windows-side import was close to a no-op.
- **`HOMEBREW_BUNDLE_NO_JOBS=1` under sustained load.** One cold-cache run passed. Three earlier runs
  failed without it. Suggestive, not conclusive.

## Defects found and fixed (nine)

Six were invisible to both existing machines because both were configured by hand before the repo
existed — they had krew, zip, and the skills already.

| # | Defect | Commit |
|---|---|---|
| 1 | `bw config server` is refused while logged in, so **every re-run died** and no run had ever reached `chezmoi apply`. The README's idempotency claim was false. | `36a80eb` |
| 2 | Double master-password prompt made a successful login look rejected | `36a80eb` |
| 3 | Homebrew re-installed on every run (`command -v brew` is false in a fresh shell) | `36a80eb` |
| 4 | Dangling `/usr/local/bin/gpg` failed with a bare `ln: Already exists` | `36a80eb` |
| 5 | krew was **never installed** — listed only in its own plugin list, four failures hidden by `\|\| true` | `79dc71f` |
| 6 | Skills restore prompted per skill, installed to 15 agent dirs, and one withdrawn skill aborted the whole apply | `79dc71f` |
| 7 | SDKMAN's `zip`/`unzip` undeclared; `unzip` was present only as a terraform dependency | `86d0f66` |
| 8 | SDKMAN dies under `set -u` | `b674d58` |
| 9 | `brew bundle` installs in parallel and races on its own download cache | `e458a99` |
| 10 | Work bundle took the whole apply down when `op` is absent | `447d0d4` |
| 11 | **`chezmoi init` never pulls an existing source** — pushed fixes silently never arrived | `a6cb6bb` |
| 12 | rust bundle installed a toolchain no shell could see (`~/.cargo/bin` was on no PATH) | `cbc924b` |

Also landed: java split into its own bundle, eight y/n prompts replaced by one multi-select, and
closed-ticket references stripped from comments repo-wide.

## Process lessons — these cost real time

1. **`EXIT=0` is not evidence.** The rust bundle reported success while installing 150MB of unusable
   toolchain. Check that the *binary resolves*, not that the file exists.
2. **Fetching `main` yourself proves nothing about what a machine runs.**
   `raw.githubusercontent.com` caches for 5 minutes (`cache-control: max-age=300`) and different edge
   nodes disagree. A push followed immediately by a run will execute the *previous* script. Use a
   commit-pinned URL (`.../<sha>/bootstrap.sh`) when testing, or check the source SHA on the machine.
3. **Check the source revision on the target machine.** Combined with defect 11, three consecutive
   fixes were diagnosed against code that was never running, producing one confidently wrong root cause.
4. **`zsh -lc` is a login shell but not an interactive one**, so `.zshrc` — and therefore every `env.d`
   drop-in — is skipped. Use `zsh -lic` to test anything the drop-ins provide, or you will get a false
   negative. This is also a real design question, now [#25](https://github.com/myprysm/dotfiles/issues/25).
5. **`|| true` does not catch a `set -u` failure.** An unbound variable exits the shell outright;
   `f || true` never returns. `21-krew-plugins` uses the same idiom and has not been audited for it.

## Tickets opened this session

- [#21](https://github.com/myprysm/dotfiles/issues/21) — skills lockfile can never converge and **blocks
  apply with an interactive prompt**; skills install copied rather than symlinked; the CLI hits GitHub's
  API rate limit mid-restore because `gh auth login` happens *after* apply.
- [#22](https://github.com/myprysm/dotfiles/issues/22) — McFly warns on every shell until a history file exists.
- [#23](https://github.com/myprysm/dotfiles/issues/23) — nothing installs `authorized_keys`; owner leans
  toward doing it unconditionally.
- [#24](https://github.com/myprysm/dotfiles/issues/24) — remaining bundle verification. Carries evidence
  from this run; the `t64` apt names did resolve on 26.04.
- [#25](https://github.com/myprysm/dotfiles/issues/25) — `env.d` only reaches interactive shells.

## Suggested next step

[#13](https://github.com/myprysm/dotfiles/issues/13), the Mac migration — the largest remaining gap
toward the destination, and it now inherits a bootstrap genuinely proven on Linux rather than one that
merely looked like it worked. [#21](https://github.com/myprysm/dotfiles/issues/21) is the cheaper win
if unattended `chezmoi apply` matters sooner.

## Open, not written

A README note about the 5-minute CDN window on the one-liner. Proposed, agreed in principle, never
committed.
