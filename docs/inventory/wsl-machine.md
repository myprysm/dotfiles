# Inventory — WSL2 machine

Resolves [#3](https://github.com/myprysm/dotfiles/issues/3). Snapshot taken 2026-07-31.

Host: Ubuntu 24.04.4 LTS on WSL2 (kernel 6.6.114.1-microsoft-standard-WSL2), login shell `/usr/bin/zsh` (zsh 5.9).

> **This file is published in a public repo.** Two rules applied throughout:
>
> 1. No secret values. Secret-bearing files are named and flagged only.
> 2. No infrastructure identifiers. Internal hostnames, object-store remote names, kube contexts, key ids and SSH key filenames are reduced to counts — publishing "which hosts exist and which key opens them" is reconnaissance even when no secret leaks. The counts are what the downstream decisions need; the names are on the machine.

---

## 1. Packages

### 1.1 Homebrew (Linux)

Prefix `/home/linuxbrew/.linuxbrew` (system-wide install, **not** `~/.homebrew`). Homebrew 6.0.13. `~/.homebrew/` exists but holds only `trust.json` — cask/trust metadata, not a prefix; ignore.

Taps: `hashicorp/tap`, `ariga/tap`.

**Leaves (29) — the Brewfile candidates:**

| Formula | Purpose | Keep? |
|---|---|---|
| `bat` | cat with syntax highlighting | keep |
| `bind` | `dig`/`host` | keep |
| `btop` | resource monitor | keep |
| `direnv` | per-dir env, hooked in `.zshrc` | keep |
| `eza` | `ll`/`la` aliases depend on it | keep |
| `gcc` | linuxbrew build dep (bottles need it) | keep (Linux-only) |
| `gh` | GitHub CLI | keep |
| `hashicorp/tap/terraform` | terraform | keep |
| `hashicorp/tap/vault` | vault CLI, completion in `.zshrc` | keep |
| `hcloud` | Hetzner CLI | keep |
| `hello` | GNU hello — **install test artifact** | **purge** |
| `helm@3` | pinned helm 3 | keep — pin is deliberate, `.zshrc` puts `opt/helm@3/bin` on PATH |
| `htop` | process viewer | keep |
| `jq` | JSON | keep |
| `k9s` | k8s TUI | keep |
| `kubernetes-cli` | `kubectl` | keep |
| `mcfly` | history search, hooked in `.zshrc` | keep |
| `minio-mc` | `mc`, completion in `.zshrc` | keep |
| `mkdocs` | docs site builder | borderline — project-specific, not shell-critical |
| `nvm` | node version manager (brew-installed, not the curl installer) | keep |
| `rclone` | object-store sync | keep |
| `starship` | prompt | keep |
| `swaks` | SMTP test tool | borderline — rarely used |
| `talosctl` | Talos CLI | keep |
| `tmux` | multiplexer — **no `~/.tmux.conf` exists** | keep binary, no config to migrate |
| `uv` | python packaging, 2 completion evals in `.zshrc` | keep |
| `velero` | k8s backup CLI | keep |
| `virtualenvwrapper` | `workon`, sourced in `.zshrc` | keep — but see §3.4 |
| `yq` | YAML | keep |

Full formula list is 73 — the other 44 are transitive deps (`openssl@3`, `python@3.14`, `libgit2`, `ncurses`, …) plus `atlas` (from `ariga/tap`, pulled as a dep, not a leaf). A Brewfile of leaves reproduces all of it.

**Note for the package-manifest ticket:** `bind` provides `dig`; `hello` is pure noise; `mkdocs`/`swaks` are the only two whose "core vs optional" placement is genuinely open.

### 1.2 apt (manually installed)

Stripping the `ubuntu-minimal`/`ubuntu-wsl` base set and the ~30 Playwright/Chrome shared-library deps (`libnss3`, `libgbm1`, `libatk*`, `fonts-*`, `xvfb`, …), the deliberate installs are:

| Package | Why it's apt not brew | Keep? |
|---|---|---|
| `zsh` | login shell — must exist before brew | keep, bootstrap prerequisite |
| `git` | 2.43.0, `/usr/bin/git` — brew git not installed | keep, bootstrap prerequisite |
| `curl` | bootstrap prerequisite | keep |
| `build-essential`, `libffi-dev`, `python3-dev` | compile toolchain for python/native gems | keep |
| `ripgrep` | apt version, no brew duplicate | keep (or move to brew — decide in package ticket) |
| `ffmpeg` | media | borderline |
| `brave-browser`, `google-chrome-stable` | GUI browsers via WSLg | borderline — GUI, arguably out of scope |
| `xvfb` + font/lib set | Playwright headless deps | keep as a grouped "playwright" optional bundle |

`ubuntu-wsl` marks this host as WSL — a per-OS marker the templates can key on but not a package to install elsewhere.

### 1.3 Node (nvm)

nvm installed **via brew**, loaded from `$HOMEBREW_PREFIX/opt/nvm/nvm.sh`. `NVM_DIR=$HOME/.nvm`. Default alias: `lts/*`.

Installed versions: `v22.22.2`, `v24.14.1`, `v24.15.0`, `v24.18.0` (active).

**Global npm packages (on v24.18.0 only — globals are per-version, they do not follow a node upgrade):**

- `@bitwarden/cli@2026.6.0` — the `bw` CLI the secrets strategy depends on
- `@playwright/cli@0.1.17`
- `corepack@0.35.0`
- `npm@12.0.1`

`.zshrc` sets `PNPM_HOME=$HOME/.local/share/pnpm` (hardcoded absolute in the file) and prepends it to PATH, but **pnpm is not installed** and `pnpm ls -g` returns nothing — despite `alias ccusage="pnpx ccusage@latest"` depending on it. Dead alias + dead PATH entry, or a missing install; the package ticket must pick one.

### 1.4 Go

`/usr/local/go` (tarball install — `go1.26.1.linux-amd64.tar.gz` still sits in `$HOME`, 66 MB of leftover). `$HOME/go/bin` holds:

`ginkgo`, `golangci-lint`, `gopls`, `kind`, `setup-envtest`, `sqlc`, `tygo`

All `go install`-able — reproducible as a `run_onchange_` script with pinned versions. Go itself is neither apt nor brew: an unmanaged tarball. **Flag for the package ticket** — that is the one install path with no manifest today.

### 1.5 Other tool paths

- `~/.local/bin`: `claude` (Claude Code, self-updating), `python3.11` — both self-managed, not repo material.
- `kubectl krew` plugins: `cnpg`, `krew`, `oidc-login`. Reproducible as a `run_onchange_` script.
- `/usr/local/bin/kubeone` — manual binary install; `.zshrc` sources its completion.
- No `pipx`, no `uv tool` installs, no cargo/rust toolchain, no `dotnet`, no `composer`.

---

## 2. Shell stack

### 2.1 oh-my-zsh

`ZSH=$HOME/.oh-my-zsh`, theme `robbyrussell`.

**Theme is dead weight:** `starship init zsh` runs at the end of `.zshrc` (line 233) and overwrites the prompt entirely. `robbyrussell` costs startup time and produces nothing.

**26 declared plugins — status:**

| Plugin | Source | Underlying tool present? | Verdict |
|---|---|---|---|
| `autoupdate` | custom | n/a | keep if omz stays; conflicts with pinning omz as a chezmoi external |
| `brew` | builtin | yes | **load-bearing — see §2.2** |
| `bw` | custom | yes (`@bitwarden/cli`) | keep |
| `colorize` | builtin | yes — `/usr/bin/pygmentize` present (pulled in by an apt dep, not deliberately installed) | keep, but the dep is accidental |
| `command-not-found` | builtin | yes (Ubuntu handler) | keep |
| `direnv` | builtin | yes | redundant — `.zshrc:232` already runs `direnv hook zsh` |
| `dotnet` | builtin | **no `dotnet`** | dead |
| `doctl` | builtin | **no `doctl`** | dead |
| `docker` | builtin | yes (`/usr/bin/docker`) | keep |
| `docker-compose` | builtin | yes (as docker plugin) | keep |
| `encode64` | builtin | n/a (pure zsh) | keep |
| `git` | builtin | yes | keep |
| `golang` | builtin | yes | keep |
| `gradle` | builtin | no gradle binary (plugin only defines `gradle-or-gradlew`) | dead in practice |
| `kubectl` | builtin | yes | keep |
| `mvn` | builtin | no maven binary | dead in practice |
| `npm` | builtin | yes | keep |
| `nvm` | builtin | yes | keep |
| `composer` | builtin | **no `composer`** | dead |
| `helm` | builtin | yes | keep |
| `laravel` | builtin | **no `laravel`/PHP** | dead |
| `rust` | builtin | **no `cargo`** | dead |
| `terraform` | builtin | yes | keep |
| `vault` | builtin | yes | keep — but `.zshrc:224` also registers `complete -C vault`, duplicate |
| `zsh-claudecode-completion` | custom | yes | keep |
| `zsh-syntax-highlighting` | custom | n/a | keep — **must stay last** |
| `zsh-autosuggestions` | custom | n/a | keep |

**6 unambiguously dead** (`dotnet`, `doctl`, `composer`, `laravel`, `rust`, plus `direnv` as a duplicate); `gradle`/`mvn` dead until a JVM project appears — neither binary exists, the plugins only define the `*-or-*w` wrappers.

Custom plugin dirs present: `autoupdate`, `bw`, `example`, `zsh-autosuggestions`, `zsh-claudecode-completion`, `zsh-syntax-highlighting`. Custom themes: `example.zsh-theme` only. `$ZSH_CUSTOM/example.zsh` is the shipped stub.

`fpath+=…/plugins/zsh-completions/src` (line 128) points at **`zsh-completions`, which is not installed** — a stale fpath entry.

### 2.2 `.zshrc` — broken and dead entries

Ordering bug, worth its own line in the shell-architecture ticket:

`HOMEBREW_PREFIX` is **not exported before it is used**. It is set by the omz `brew` plugin (`brew.plugin.zsh:30`), which only runs at `source $ZSH/oh-my-zsh.sh` on line 132. Lines 4, 5 and 11 use `$HOMEBREW_PREFIX` *before* that, so they expand to the empty string:

```
export PATH="$HOMEBREW_PREFIX/opt/mysql-client/bin:$PATH"   # -> /opt/mysql-client/bin   (does not exist)
export PATH="$HOMEBREW_PREFIX/opt/libpq/bin:$PATH"          # -> /opt/libpq/bin          (does not exist)
export PATH="$HOMEBREW_PREFIX/opt/helm@3/bin:$PATH"         # -> /opt/helm@3/bin         (does not exist)
```

Confirmed in a clean login shell: `PATH` contains `/opt/helm@3/bin`, `/opt/libpq/bin`, `/opt/mysql-client/bin` — three nonexistent dirs. `helm@3` is on PATH only by luck, via the brew prefix `bin`. The nvm block at line 190 works because it runs after line 132.

Consequence: the omz `brew` plugin is currently the *only* thing that sets `HOMEBREW_PREFIX` for zsh. `.bashrc` runs `brew shellenv` properly (twice — lines 118 and 120, duplicated). Any move away from oh-my-zsh must add an explicit `brew shellenv` eval early.

**macOS leftovers to purge** (this file was carried over from a Mac — `.zshrc.bck` is the pre-migration copy and still says `/opt/homebrew`):

| Line | Content | Status |
|---|---|---|
| 10 | `PATH=$PATH:/Users/<mac-user>/.dotnet/tools` | dead path, no dotnet |
| 12 | `PATH="/Users/<mac-user>/.local/bin:$PATH"` | dead path — and line 15 already adds the real `$HOME/.local/bin` |
| 17-18 | `JAVA_HOME=/Library/Java/…/graalvm-jdk-21.0.3+7.1/Contents/Home` + PATH | dead path, no JVM installed; **pollutes PATH in every shell** |
| 22 | `CXXFLAGS="-stdlib=libc++"` | macOS/clang flag, wrong on Linux gcc |
| 24-25 | `DevToysGuiDebugEntryPoint` / `DevToysCliDebugEntryPoint` | macOS app paths, DevToys not installed |
| 36 | `ZSH_THEME="robbyrussell"` | overridden by starship |
| 129 | `fpath+=(~/.config/hcloud/completion/zsh)` | **`~/.config/hcloud` does not exist** |
| 175-187 | `MAX_MEMORY_UNITS` + `TIMEFMT` | works, but the Darwin branch is the only cross-OS bit worth templating |
| 217 | tabtab source guard | harmless no-op, file absent |

**Live content worth keeping:** aliases (`cls`, `sail`, `jqd64`, `genpass`, `garage`, `ll`, `la`, `ccusage`), `EDITOR=vim`, `GPG_TTY`, `DOTNET_CLI_TELEMETRY_OPTOUT`, krew PATH, go PATH, the nvm `load-nvmrc` chpwd hook, and the five init evals (`compinit`/`bashcompinit`, `mcfly`, `direnv`, `starship`, plus `mc`/`vault`/`uv`/`kubeone` completions).

The `garage` alias hardcodes a named kube context and a pod name (values withheld) — cluster-specific, belongs in a per-machine override, not the shared repo.

`.zshrc.bck` (6.7 KB, macOS-era) has no value once the purge lands — **delete, do not migrate**.

### 2.3 Startup noise in `$HOME`

Four `.zcompdump*` cache files (`.zcompdump`, plus `-<host>-5.9` and `-<host>-5.9.zwc` variants under **two different hostnames** — the machine was renamed at some point). Generated, never tracked; the `.chezmoiignore` should exclude them.

### 2.4 virtualenvwrapper

`.zshrc:135` sources `virtualenvwrapper.sh` and `.zshrc:138-140` auto-activates the `main` venv in every shell. `~/.virtualenvs` holds `main` and `myprysm-infrastructure` plus the standard hook scripts (`postactivate`, `premkvirtualenv`, …).

Envs are **not** repo material (contents are installed packages). The hook scripts are user-editable and currently unmodified stubs. **Open question for the shell ticket:** whether auto-`workon main` at every shell start survives, given `uv` is also installed and is the newer tool.

---

## 3. Config candidates

### 3.1 Keep — safe, no secrets

| Path | Content | Why |
|---|---|---|
| `~/.zshrc` | shell rc | the core artifact; migrate **after** the purge in §2.2 |
| `~/.config/starship.toml` | 29 bytes: `[kubernetes] disabled = false` | tiny but deliberate; keep |
| `~/.config/k9s/config.yaml` | refresh rate, thresholds, shellPod `busybox:1.37.0`, logger settings | machine-agnostic; **contains an absolute `screenDumpDir` under `$HOME`** — template the home path |
| `~/.config/k9s/aliases.yaml` | 8 resource aliases | keep verbatim |
| `~/.config/k9s/skins/` | **empty** | nothing to migrate |
| `~/.config/htop/htoprc` | field layout, colors | keep — but htop rewrites it on exit; expect chezmoi drift |
| `~/.config/git/ignore` | one line: `**/.claude/settings.local.json` | keep |
| `~/.config/gh/config.yml` | git_protocol https, alias `co: pr checkout` | keep — **this file has no token**, unlike `hosts.yml` |
| `~/.config/helm/repositories.yaml` | 14 public chart repos (external-dns, cilium, jetstack, dex, argocd, velero, traefik, twuni, verdaccio, emberstack, cnpg, vm, argo, jellyfin) | keep — all public URLs, no creds. Better expressed as a `run_onchange_` of `helm repo add` than as a synced file, since helm rewrites it |
| `~/.zfunc/_g` | one completion function | keep, trivial |
| `~/.nuxtrc` | `telemetry.enabled=false` | keep, trivial opt-out |

### 3.2 Keep, but templated — contains identity or host-specific values

| Path | Issue | Handling |
|---|---|---|
| `~/.gitconfig` | `user.email`, `user.name`, `user.signingkey` (a GPG key **id** — not key material, but identity; value withheld here). Also `gpg.program = /usr/local/bin/gpg`, which on this host is a symlink to `/mnt/c/Program Files/GnuPG/bin/gpg.exe` — **a Windows binary via WSL interop**. That path is meaningless on Linux and on Mac. | Split: aliases/`pull.rebase`/`push.autoSetupRemote`/`rebase.autoStash` are universal and go in the repo; identity, signing key and `gpg.program` become template values or a per-machine include |

`.gitconfig` also raises a work-vs-personal question the repo is public and the email is a work address — worth confirming that identity belongs in a public repo at all, even though it is already public in every commit.

### 3.3 SECURITY FLAG — never in the repo, in any form

Repo is public. Every path below either holds a credential or is one.

| Path | What it holds |
|---|---|
| `~/.config/gh/hosts.yml` | GitHub OAuth token |
| `~/.config/rclone/rclone.conf` | **6 object-store remotes**, each with a live `secret_access_key`. Names withheld — they identify providers, regions and one self-hosted endpoint |
| `~/.mc/config.json` | minio-client: **4 aliases** with S3 key pairs. Names withheld, same reason |
| `~/.docker/config.json` | **2 private registry auths** (+ `credsStore`). Hostnames withheld |
| `~/.config/Bitwarden CLI/data.json` | Bitwarden session/vault state |
| `~/.vault-token` | live Vault token |
| `~/.ssh/` | **15 private keys** + `known_hosts`. Filenames withheld — several name the system they open, which is exactly the pairing not to publish |
| `~/.ssh/config` | not opened during this inventory. It sits beside 15 private keys and names hosts by definition, so it stays out by default; if the secrets ticket wants it, it must be reviewed line by line first |
| *(path withheld)* | **1 Ansible Vault password file**. Location withheld — the rule governing it forbids publishing where it lives |
| `~/.gnupg/` | private GPG keyring |
| `~/.kube/config`, `~/.talos/config` | already ruled out of scope on the map; restated here so the inventory is complete |
| `~/.ansible/galaxy_token` | Galaxy API token |
| `~/.devvit/token`, `~/.devvit/session-id` | Reddit devvit session |
| `~/.config/<project>/` | 2 files: project API keys + an env file |
| 2 × `~/backup-*.env.<date>` | env-file backups sitting loose in `$HOME`, mode `600`, dated 2026-07-25 |
| `~/.claude.json` | 78 KB Claude Code state, includes MCP server config which can carry tokens |
| `~/.config/pulse/cookie` | audio auth cookie (machine-local) |

The two loose env backups and a project values YAML sitting directly in `$HOME` are secret-bearing artifacts with no home — **input for the secrets-vault ticket** (#11), which needs to say where such things go.

### 3.4 Skip — not repo material

| Path | Why |
|---|---|
| `~/.config/Code/`, `~/.config/JetBrains/`, `~/.junie/` | IDE configs — ruled out of scope on the map |
| `~/.config/google-chrome/`, `~/.config/BraveSoftware/`, `~/.config/google-chrome-for-testing/` | browser profiles, huge, self-managed |
| `~/.config/go/telemetry`, `~/.config/gopls/prompt`, `~/.terraform.d/checkpoint_*`, `~/.atlas/`, `~/.dotnet/`, `~/.java/` | tool-generated state |
| `~/.config/systemd/user/` | WSL systemd units — machine-specific; revisit under the WSL-quirks fog |
| `~/.config/mimeapps.list` | desktop MIME assoc, WSLg-specific |
| `~/.playwright-cli/` | session logs |
| `~/.cache/`, `~/.npm/`, `~/.nvm/`, `~/.oh-my-zsh/` | installed/generated trees — `.oh-my-zsh` becomes a chezmoi `archive` external per the research ticket, not tracked content |
| `~/.zcompdump*` (4 files) | completion caches |
| `~/.bash_history`, `~/.zsh_history`, `~/.viminfo`, `~/.lesshst`, `~/.python_history`, `~/.wget-hsts` | history/state |
| `~/go1.26.1.linux-amd64.tar.gz` | 66 MB leftover installer — delete during migration |
| `~/.zshrc.bck` | superseded macOS copy — delete |
| `~/.shell.pre-oh-my-zsh` | omz install marker |
| `~/.agents/`, `~/.claude/`, `~/.copilot/`, `~/.hindsight/`, `~/.openclaw/` | agent tooling — separate concern from shell dotfiles; **not decided here**, flag for scoping |

### 3.5 Configs that do not exist yet

Installed but unconfigured, so nothing to migrate — though the repo could ship an opinionated default:

- `tmux` — no `~/.tmux.conf`
- `vim` — `EDITOR=vim` but no `~/.vimrc`, no `~/.vim/`
- `direnv` — no `~/.config/direnv/direnvrc`
- `mcfly` — no config file, configured purely by env vars (none set)
- `bat`, `eza` — no config, defaults only
- `npm` — no `~/.npmrc`

---

## 4. Findings that belong to other tickets

Decisions this inventory surfaced but does not make:

**Shell architecture (#4)**
- Drop `robbyrussell` (starship wins) and the 7 dead plugins; decide `gradle`/`mvn`.
- Fix the `HOMEBREW_PREFIX` ordering bug — an explicit `brew shellenv` early, independent of the omz `brew` plugin.
- Purge the 8 macOS leftovers listed in §2.2, and `.zshrc.bck`.
- Decide whether omz survives at all — the ordering bug and the auto-updater both argue for a lighter loader.
- Decide the fate of auto-`workon main` (virtualenvwrapper vs `uv`).
- The `garage` alias carries a hardcoded kube context — needs the per-machine override mechanism.

**Package manifest (#5)**
- Go is installed from an unmanaged tarball; `$HOME/go/bin` has 7 binaries with no manifest.
- npm globals are pinned to node `v24.18.0` and do not survive a node upgrade.
- `pnpm` is on PATH and aliased but not installed.
- Purge `hello`; place `mkdocs`/`swaks`/`ffmpeg` on the core-vs-optional line.
- apt vs brew for `ripgrep`; the Playwright/Chrome apt bundle needs a grouping decision.

**Secrets strategy (#6)**
- Concrete exclusion list is §3.3.
- `rclone.conf` and `~/.mc/config.json` are the hard cases — many secrets in one structured file; templating them means one vault lookup per remote.
- `~/.gitconfig` needs an identity/`gpg.program` split.

**Secrets vault (#11)**
- Loose secret files sitting directly in `$HOME` (2 env backups, a project values YAML) plus 1 Ansible Vault password file (location withheld) have no policy today.

**WSL-quirks fog (map)**
- `gpg.program` resolving to a Windows `gpg.exe` through `/usr/local/bin/gpg` is a real WSL interop dependency, not dead weight.
- `ubuntu-wsl` apt package and `~/.config/systemd/user` are the other WSL-only touchpoints.
- No `win32yank` or clipboard tooling is installed — that fog patch is currently empty.
