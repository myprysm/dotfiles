# dotfiles

> **PROTOTYPE** — throwaway skeleton built for [wayfinder ticket #7](https://github.com/myprysm/dotfiles/issues/7).
> Nothing here is applied anywhere yet. React to the shape; the real tree lands after review.

chezmoi-managed dotfiles for all my machines (WSL2 Ubuntu, macOS). Public repo:
**no secrets, in any form** — see [docs/secrets.md](docs/secrets.md).

## Bootstrap a fresh machine

One command on a naked machine:

```sh
sh -c "$(curl -fsLS https://raw.githubusercontent.com/myprysm/dotfiles/main/bootstrap.sh)"
```

What it assumes:

- **Ubuntu (incl. WSL2)**: `sh` + `curl` present (minimal images: `apt-get install -y curl` first). One sudo moment for apt prerequisites; Homebrew installs to `/home/linuxbrew/.linuxbrew` (needs glibc ≥ 2.39 for Tier 1).
- **WSL2 additionally**: **GnuPG must already be installed on the Windows side** (Gpg4win). Git here signs every commit through the Windows GnuPG store, so `bootstrap.sh` links `/usr/local/bin/gpg` to `gpg.exe` and **aborts loudly if it is not there** — install it before running the one-liner. `secrets-restore.sh` then imports the signing key into *both* keyrings.
- **macOS**: `curl` + `sh` ship with the OS. The Homebrew installer pulls Xcode CLT itself.

`bootstrap.sh` is idempotent and the single owner of OS prerequisites — a
hand-cloned repo is set up by running `./bootstrap.sh`, never by a raw
`chezmoi apply` (brew and the secret CLIs would be missing).

The script: apt/CLT prerequisites → Homebrew → chezmoi → `chezmoi init`
(prompts once: email, Bitwarden server URL, bundle toggles) → secret CLIs
(`bw` always, `op` if work bundle) → auth → `chezmoi apply` → prints the
post-bootstrap checklist (tool-native auth: `gh auth login`, `docker login`, …
and — deliberately manual — `scripts/secrets-restore.sh`).

## Daily workflow

| I want to… | Do |
| --- | --- |
| Add an alias | drop a file: `chezmoi edit --create ~/.config/zsh/aliases.d/foo.zsh`, then `chezmoi apply` |
| Add an env var / PATH entry | same, in `~/.config/zsh/env.d/` |
| Add a tool hook (runs last) | same, in `~/.config/zsh/rc.d/` |
| Edit a tracked config | `chezmoi edit ~/.zshrc` (never edit the target directly) |
| Add a package | edit `home/.chezmoidata/packages.yaml`, `chezmoi apply` re-runs the install scripts |
| Machine-only tweak (never synced) | `~/.zshrc.local` — untracked, sourced last |
| Sync this machine with the repo | `chezmoi update` (pull + apply) |
| Push my changes | `chezmoi cd && git add -p && git commit && git push` — **line-by-line review before every add** |

## Layout

```text
.chezmoiroot            → source state lives under home/
bootstrap.sh            → the one-liner target
docs/secrets.md         → secrets policy (what never enters this repo, vault/restore rules)
scripts/                → secrets-restore.sh, secrets-audit.sh, secrets-backup.sh (explicit invocation only)
                          secrets-common.sh is sourced by all three, never run
home/
  .chezmoi.toml.tmpl    → init prompts (email, bw server, bundle toggles) → machine-local config
  .chezmoidata/         → packages.yaml (core + bundles), zsh.yaml (plugin lists)
  .chezmoitemplates/    → secret (per-domain router: personal→bw, work→op)
  .chezmoiexternal.toml → oh-my-zsh + amix/vimrc, pinned archives
  .chezmoiignore        → per-OS / per-bundle exclusions (templated)
  .chezmoiscripts/      → run_once_/run_onchange_ package + restore scripts
  dot_zshrc.tmpl        → ~20-line skeleton; all content lives in drop-in dirs
  dot_config/zsh/       → env.d/ completions.d/ aliases.d/ rc.d/
```
