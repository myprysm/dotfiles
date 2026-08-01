# Inventory — Mac

Resolves [#12](https://github.com/myprysm/dotfiles/issues/12). Snapshot taken 2026-07-31.

Host: macOS 26.5.2 (build 25F84), Apple Silicon (arm64), login shell `/bin/zsh` (zsh 5.9).

> **This file is published in a public repo.** Two rules applied throughout:
>
> 1. No secret values. Secret-bearing files are named and flagged only.
> 2. No infrastructure identifiers. Internal hostnames, object-store remote names, kube contexts, key ids and SSH key filenames are reduced to counts — publishing "which hosts exist and which key opens them" is reconnaissance even when no secret leaks. The counts are what the downstream decisions need; the names are on the machine.
>
> Additionally: several credential stores (`~/.ssh` contents, `rclone.conf`, `~/.mc/config.json`, `~/.docker/config.json`, `~/.npmrc`, `~/.composer/auth.json`) were **not opened** during this inventory — presence is flagged from directory metadata only, so some counts gathered on the WSL machine (remote counts, alias counts) are absent here by design.

---

## 1. Packages

### 1.1 Homebrew (macOS)

Prefix `/opt/homebrew` (Apple Silicon default). Homebrew 6.0.13 — same version as the WSL box.

Taps (7): `fairwindsops/tap`, `hashicorp/tap`, `k0sproject/tap`, `minio/stable`, `netbirdio/tap`, `qbit-ai/tap`, `siderolabs/tap`. Only `hashicorp/tap` is shared with WSL (which also has `ariga/tap`); no `homebrew/command-not-found` tap — see §2.1.

**Leaves (71) — vs 29 on WSL.** Shared with WSL marked ●:

| Formula | Purpose | Keep? |
|---|---|---|
| `argocd` | ArgoCD CLI, completion in `.zshrc` | keep |
| `automake`, `cmake` | build toolchain | keep — Mac's `build-essential` equivalent |
| `azure-cli` | Azure CLI (`~/.azure` state exists) | keep |
| `bat` ● | cat with syntax highlighting | keep |
| `btop` ● | resource monitor — configured here (`~/.config/btop`), unconfigured on WSL | keep |
| `caddy` | local dev server | borderline |
| `cilium-cli` | k8s CNI CLI | keep |
| `cloudflared` | Cloudflare tunnel client | keep — but `~/.cloudflared` is secret-bearing, §3.3 |
| `composer` | PHP — omz plugin live here (dead on WSL) | keep |
| `coreutils`, `gnu-sed`, `gnu-time`, `watch` | GNU userland | keep — **macOS-only**, Linux has them natively |
| `crane` | container registry tool | keep |
| `cyphernetes` | k8s query, completion in `.zshrc` | keep |
| `direnv` ● | per-dir env, hooked in `.zshrc` | keep |
| `dnsmasq` | local DNS (runs as brew service) | borderline — service config is machine setup |
| `doctl` | DigitalOcean CLI — omz plugin live here (dead on WSL) | keep |
| `exiftool`, `ghostscript`, `gifsicle`, `jpeg`, `mupdf-tools`, `qpdf`, `vips` | media/PDF tool belt | borderline as a group — `jpeg`/`vips` look like orphaned lib leaves |
| `eza` ● | `ll`/`la` aliases depend on it | keep |
| `fairwindsops/tap/pluto` | k8s deprecation scanner | keep |
| `ffmpeg` ● | media | borderline (same call as WSL) |
| `gh` ● | GitHub CLI | keep |
| `git-gui` | git GUI | borderline |
| `gptfdisk`, `squashfs` | disk/image tools | borderline |
| `hashicorp/tap/packer` | packer | keep |
| `hashicorp/tap/terraform` ● | terraform | keep |
| `hashicorp/tap/vault` ● | vault CLI, `complete -C` in `.zshrc` | keep |
| `hcloud` ● | Hetzner CLI — completion fpath entry is **live** here (stale on WSL) | keep |
| `helm` **and** `helm@3` | **both installed** — WSL pins `helm@3` only; PATH prepends `helm@3/bin` so the pin wins | **conflict — package ticket picks one** |
| `htop` ● | process viewer | keep |
| `icu4c@76`, `openblas`, `python@3.13`, `qt`, `unbound`, `zlib` | library leaves | audit — likely orphaned deps; `openblas` is deliberate (`.zshrc` exports its `LDFLAGS`/`CPPFLAGS`) |
| `jq` ● | JSON | keep |
| `k0sproject/tap/k0sctl` | k0s CLI | keep |
| `k9s` ● | k8s TUI | keep |
| `kind` | k8s-in-docker — **brew here, `go install` on WSL**; unify | keep |
| `kubernetes-cli` ● | `kubectl` | keep |
| `llama.cpp` | local LLM | borderline |
| `maven` | JVM — omz `mvn` plugin live here (dead on WSL) | keep |
| `mcfly` ● | history search, hooked in `.zshrc` | keep |
| `minio/stable/mc` ● | `mc`, completion in `.zshrc` | keep |
| `mkcert` | local dev TLS | keep |
| `mysql-client` | on PATH from `.zshrc` (the line that is dead on WSL) | keep |
| `netbirdio/tap/netbird` | VPN CLI | keep |
| `nmap`, `telnet` | network diagnostics | keep / borderline |
| `nvm` ● | node version manager | keep |
| `operator-sdk` | k8s operator dev | keep |
| `pinentry-mac` | GPG pinentry — pairs with `commit.gpgsign=true` | keep — **macOS-only** |
| `rclone` ● | object-store sync | keep |
| `rtk` | from `qbit-ai/tap` | unknown — package ticket |
| `starship` ● | prompt | keep |
| `talosctl` ● | Talos CLI | keep |
| `uv` ● | python packaging, 2 completion evals in `.zshrc` | keep |
| `velero` ● | k8s backup CLI | keep |
| `virtualenvwrapper` ● | `workon`, sourced in `.zshrc` | keep — same §2 question as WSL |
| `wget` | downloads | keep |
| `yq` ● | YAML | keep |

Full formula list is 273 (vs 73 on WSL) — the rest are transitive deps. Notably absent vs WSL: `gcc` (linuxbrew-only), `bind`, `swaks`, `mkdocs`, `tmux`, `helm@3`-only pin, `hello`. **`tmux` is not installed at all here.**

**Casks (9):** `1password-cli` (**`op` — the secrets CLI on this machine; no `bw`**), `devtoys`, `keycastr`, `macfuse`, `qbit`, `temurin` (JDK — but `JAVA_HOME` points at a *manually installed* GraalVM, §2.2), `warp`, `webpquicklook`, `xca`.

**Cask coverage is thin:** `/Applications` holds ~75 GUI apps (Docker Desktop, Slack, Figma, Alfred, Rectangle, 1Password, Bitwarden, JetBrains Toolbox, browsers, Adobe, games…), of which only 9 are cask-managed. Whether the repo encodes GUI apps as casks at all is a package-ticket decision.

**MAS:** `mas` CLI not installed; Apple-store apps (Keynote/Numbers/Pages/GarageBand/iMovie/Xcode) not enumerated.

### 1.2 Manual installs (`/usr/local/bin` and friends)

The Mac's equivalent of "apt vs brew" is "brew vs app-bundled vs hand-copied":

- App-bundled symlinks: Docker Desktop CLI set (`docker`, `docker-compose`, `kubectl.docker`, credential helpers incl. `docker-credential-osxkeychain`), VirtualBox suite, `mullvad`, `tailscale`, `netbird`, `newt`, `warp-cli`, `ollama`, `code`.
- Hand-copied binaries: `kubeone` (**same manual install as WSL** — `.zshrc` sources its completion), `kubent`, `clusterlint`, `talosctl-1.8.4` (old pinned copy beside the brew one), `rkdeveloptool`, `bcrypt-tool` (duplicate of the `~/go/bin` copy).
- `/usr/local/go` exists (tarball Go) **and** brew Go 1.26.5 is installed; PATH puts brew first, so the tarball is stale — same unify-Go flag as WSL, opposite direction.
- `/Library/Java/JavaVirtualMachines`: `graalvm-jdk-21.0.3` (manual, referenced by `JAVA_HOME`) + `temurin-21` + `temurin-26` (cask). Three JDKs, one hardcoded choice.

### 1.3 Node (nvm)

nvm via brew, loaded from `/opt/homebrew/opt/nvm/nvm.sh` (hardcoded prefix, vs `$HOMEBREW_PREFIX` on WSL). `NVM_DIR=$HOME/.nvm`. Default alias: `24` (WSL: `lts/*` — same effect, different spelling).

**10 node versions installed** (v20.11.1 → v24.18.0; WSL has 4). Globals on the active v24.18.0: `corepack`, `npm@11.18.0`, **`pnpm@11.14.0`** — pnpm is real here (it is aliased-but-missing on WSL; the Mac's `ccusage` alias uses `npx`, the WSL one `pnpx`). Older versions carry stray per-version globals (`@playwright`, `@npmcli`, others) — the same "globals don't survive a node upgrade" trap flagged on WSL, at 10-version scale.

### 1.4 Go

Brew-managed `go1.26.5` (vs unmanaged tarball on WSL). `~/go/bin`: `bcrypt-tool`, `gopls`, `staticcheck`, `tygo` — 4 binaries, partially overlapping WSL's 7 (`gopls`, `tygo` shared). Same `run_onchange_` manifest answer covers both.

### 1.5 Other tool paths

- `kubectl krew` plugins: `cnpg`, `krew`, `linstor`, `oidc-login` — WSL's set plus `linstor`.
- **Rust**: full rustup toolchain in `~/.cargo` (rustc, cargo, clippy, rust-analyzer, `dx`) — absent on WSL, where the omz `rust` plugin was flagged dead; here the toolchain exists but the plugin is *not* declared. Perfect inverses.
- **Composer globals**: `laravel/installer` (+ deps) — feeds the live `laravel` plugin.
- `~/.local/bin`: `claude`, `hermes`, `junie`, `playwright-cli`, `spacetime`, `node`/`npm`/`npx` shims, `python3.11`, `env` scripts — self-managed, not repo material.
- No `pipx`, no `uv tool` installs, no `mas`.

---

## 2. Shell stack

### 2.1 oh-my-zsh

`ZSH=$HOME/.oh-my-zsh`, theme `robbyrussell` — **dead weight here too**: `starship init zsh` runs near the end of `.zshrc` and overwrites the prompt.

**24 declared plugins.** Set difference vs WSL's 26:

- **Mac-only:** `1password` (tool `op` present — live).
- **WSL-only:** `bw`, `rust`, `terraform`, `vault` — yet terraform/vault/cargo binaries all exist here. Plugin lists drifted independently of tool reality on both machines.

**Status of the plugins WSL flagged dead — all six are LIVE on the Mac:** `dotnet`, `doctl`, `gradle`, `mvn`, `composer`, `laravel` all have their tool installed here. "Dead" is per-machine, not global — **the per-OS template must carry per-machine plugin lists, not one pruned list.**

Dead *on the Mac*: `colorize` (no `pygmentize` — live-by-accident on WSL), `command-not-found` (macOS handler needs the `homebrew/command-not-found` tap, which is not installed — inert), `direnv` (duplicate of the explicit `direnv hook zsh` eval, same as WSL).

Custom plugin dirs: `autoupdate`, `example`, `zsh-autosuggestions`, `zsh-claudecode-completion`, `zsh-completions`, `zsh-syntax-highlighting`. Two differences vs WSL: **`zsh-completions` actually exists here** (the `fpath+=` line is live, stale on WSL), and there is **no `bw` custom plugin**.

### 2.2 `.zshrc` — the other side of the fork

This file is the live ancestor of WSL's `.zshrc.bck`: same skeleton, hardcoded `/opt/homebrew` everywhere the WSL copy says `$HOMEBREW_PREFIX`. Line-by-line divergences that matter:

**No ordering bug here, for two reasons:** `~/.zprofile` runs `eval "$(/opt/homebrew/bin/brew shellenv)"` before `.zshrc` ever executes, and the PATH lines hardcode the prefix anyway. All three "ghost" dirs from the WSL report exist and are real here: `mysql-client`, `libpq` (installed as a dep), `helm@3` are all present. **The `.zprofile` `brew shellenv` is the correct pattern to standardize on both machines.**

Entries dead on WSL that are **live on the Mac**:

| Entry | Status here |
|---|---|
| `JAVA_HOME=…/graalvm-jdk-21.0.3…` | live — dir exists, `mvn`/`gradle` work because of it |
| `PATH=$PATH:~/.dotnet/tools` | live — dotnet installed |
| `CXXFLAGS="-stdlib=libc++"` | correct on macOS clang |
| DevToys entry points | half-live — DevToys.app is in `/Applications`, the vars point at `~/Applications`/`~/bin` |
| `fpath+=(~/.config/hcloud/completion/zsh)` | live — dir exists |
| tabtab source | live — `~/.config/tabtab/zsh` exists |
| `PATH=$HOME/Library/Python/3.9/bin` | dir exists (macOS system-python user bin) — likely vestigial, audit |

Mac-only additions with no WSL counterpart: openblas build flags (`LDFLAGS`/`CPPFLAGS`/`PKG_CONFIG_PATH`/`CMAKE_PREFIX_PATH`), `argocd`/`cyphernetes` completions, docker completions fpath, `. ~/.local/bin/env`, `. ~/.cargo/env` (also in `.zshenv` — double-sourced), qbit shell integration (guarded), and sourcing order differences (`compinit` runs *after* the completion `source`s here).

**Aliases** — shared: `cls`, `sail`, `jqd64`, `genpass`, `ll`/`la`, `garage` (same hardcoded kube context + pod — per-machine override material), `ccusage` (`npx` here vs `pnpx` on WSL). Mac-only: **3 work-scoped aliases** (names withheld — they carry a work project identifier). Two are path shortcuts, to a project root and to a jar; the third **embedded a tunnel credential inline** — see §3.3 (removed same day this inventory flagged it; the credential was already invalid).

`workon main` auto-activation: present here too, same open question (virtualenvwrapper vs `uv`).

### 2.3 Startup files beyond `.zshrc`

The Mac has a real startup-file constellation the WSL box lacks:

- `~/.zprofile` — brew shellenv (load-bearing), JetBrains Toolbox scripts PATH, `~/.local/bin` PATH.
- `~/.zshenv` — argcomplete fpath, `. ~/.cargo/env`.
- `~/.profile` — `.local/bin/env` + cargo env for sh-compat.

Any repo layout that only ships `.zshrc` misses where macOS actually does its PATH setup.

### 2.4 Startup noise in `$HOME`

**8 `.zcompdump*` files across 4 historical hostnames** (machine renamed repeatedly; hostnames withheld). Same `.chezmoiignore` exclusion as WSL, bigger pile.

### 2.5 vim — configured here, not on WSL

`~/.vimrc` + `~/.vim_runtime` = the amix/vimrc "awesome" distro (git clone, self-updating via its own scripts). WSL has `EDITOR=vim` and no config. Options for the shell ticket: chezmoi `external` (like oh-my-zsh) or drop. `~/.vim_mru_files`/`.viminfo` are state, ignore.

---

## 3. Config candidates

### 3.1 Keep — safe, no secrets

| Path | Content | Why / divergence |
|---|---|---|
| `~/.zshrc` | shell rc | core artifact — **after stripping the credential-bearing alias and the work aliases** (§3.3) |
| `~/.zprofile` | brew shellenv + PATH | keep — the correct home for `brew shellenv` on both OSes |
| `~/.config/starship.toml` | 29 bytes, `[kubernetes] disabled = false` | **byte-identical to WSL** — the first genuinely shared config |
| `~/Library/Application Support/k9s/config.yaml` | same shape as WSL's | **different path on macOS** — template data point; drift: `busybox:1.35.0` here vs `1.37.0` on WSL; `screenDumpDir` absolute under `$HOME` again; `clusters/` subdir is per-cluster state, skip |
| `~/Library/Application Support/k9s/aliases.yaml` | 8 resource aliases | same as WSL, keep verbatim |
| `~/.config/htop/htoprc` | field layout | keep, same drift caveat |
| `~/.config/btop/btop.conf` | btop config | keep — Mac-only, WSL btop unconfigured |
| `~/.config/git/ignore` | one line, Claude settings | **identical to WSL** |
| `~/.config/gh/config.yml` | `git_protocol: https`, alias `co: pr checkout` | same intent as WSL, newer schema with more (default) keys |
| `~/Library/Preferences/helm/repositories.yaml` | 36 chart repos (vs 14 on WSL) | **different path on macOS**; same `run_onchange_ helm repo add` answer — union or per-machine list is a package-ticket call; not audited for private URLs, review before encoding |
| `~/.zfunc/` | `_cargo`, `_rustup` | keep — different content than WSL's `_g`; union them |
| `~/.nuxtrc` | telemetry opt-out | **identical to WSL** |
| `~/.config/zed/settings.json` + `themes/` | Zed editor settings | small and portable — but the map ruled JetBrains out as "IDE configs"; whether Zed counts as IDE needs a one-line scoping call |

### 3.2 Keep, but templated — identity or host-specific

`~/.gitconfig` — richer than WSL's and differently scoped:

- Identity: `user.email` is the **personal** address here (WSL carries the work address), `user.name`, `user.signingkey` (GPG key id, value withheld). The work identity is layered on via **two `includeIf` blocks pointing at per-project `.gitconfig` files inside the work project tree** — a pattern the WSL box doesn't have, and a better answer to the work-vs-personal question the WSL inventory raised.
- `commit.gpgsign = true` (not present on WSL) with `gpg.program = /opt/homebrew/bin/gpg` — native, vs WSL's Windows-interop `gpg.exe` path. **`gpg.program` is now confirmed three-way divergent: hardcoded per-OS.** `pinentry-mac` completes the macOS signing stack.
- `core.sshCommand` pins a personal SSH key by filename with `IdentitiesOnly` (filename withheld) — identity-bearing, template value.
- Universal keepers: `pull.rebase`, `push.autoSetupRemote`, `rebase.autoStash`, alias `fo`, `core.autocrlf=input`. Machine-local oddity: `safe.directory /var/www/html` (container work) — per-machine override.

### 3.3 SECURITY FLAG — never in the repo, in any form

Repo is public. Flagged from metadata; contents not opened unless noted.

| Path | What it holds |
|---|---|
| **`~/.zshrc` (credential-bearing alias — since removed)** | **held a tunnel credential inline: client id + secret + internal endpoint URL** (values withheld; credential was already invalid). Removed from the rc on 2026-07-31 after this inventory flagged it. The lesson stands: secrets showed up *inside* rc content, so the migration must strip-and-review rc files, not only exclude secret files. |
| `~/.config/gh/hosts.yml` | GitHub OAuth token |
| `~/.config/rclone/rclone.conf` | object-store remotes with keys — not opened, remote count not gathered |
| `~/.mc/config.json` | minio aliases with key pairs — not opened |
| `~/.docker/config.json` | Docker Desktop auths (+ osxkeychain credsStore) — not opened |
| `~/.npmrc` | 459 bytes, mode 600 — likely registry auth, not opened; review before any npm config migrates |
| `~/.composer/auth.json` | if present — composer registry auth, not opened |
| `~/.ssh/` | 34 files, **14 public keys → ≈14 keypairs**; filenames withheld; `config` presence not confirmed (dir not listed beyond counts) |
| `~/.gnupg/` | private keyring (signing key lives here — `commit.gpgsign=true` depends on it) |
| `~/.vault-token` | Vault token (dated 2025) |
| *(path withheld)* | **two** Ansible Vault password files (personal + work) — vs one on WSL; input for the secrets-vault ticket (#11). Location withheld — the rule governing it forbids publishing where it lives |
| `~/.config/argocd/config` | ArgoCD CLI contexts + auth tokens — names the clusters, not opened |
| `~/.cloudflared/` | tunnel credentials |
| `~/.aws/`, `~/.azure/` | cloud credentials/state |
| `~/.kube/`, `~/.talos/` | out of scope per map; restated for completeness |
| `~/.config/op/`, `~/.config/1Password/` | 1Password CLI/app state — **`op` is this machine's secret CLI; WSL runs `bw`. Both ecosystems must stay first-class (map preference confirmed by hardware).** Bitwarden.app is installed here too, but no `bw` CLI |
| `~/.claude.json` | 123 KB Claude Code state incl. MCP config |
| `~/.config/spacetime/cli.toml`, `~/.hermes/`, `~/.qbit/` | tool state, possibly token-bearing — not opened |
| macOS Keychain | the OS-native store many app credentials live in — no file to exclude, but the secrets ticket should note it as the platform default |

### 3.4 Skip — not repo material

| Path | Why |
|---|---|
| `~/Library/Application Support/JetBrains`, JetBrains Toolbox, `~/.vscode`, `Code/`, `~/.junie` | IDE — out of scope per map (Zed exception raised in §3.1) |
| Browser profiles (Chrome/Brave/Firefox/Arc/Edge×4) | self-managed |
| `~/.cargo`, `~/.rustup`, `~/.nvm`, `~/.oh-my-zsh`, `~/.krew`, `~/.npm`, `~/.cache` | installed/generated trees |
| `~/.dotnet`, `~/.gradle`, `~/.m2`, `~/.nuget`, `~/.android`, `~/.mono`, `~/.templateengine` | toolchain state |
| `~/.babel.json`, `~/.configstore`, `~/.degit`, `~/.dlv`, `~/.dx`, `~/.skiko`, `~/.plastic4`, `~/.pm2`, `~/.yarn`, `~/.pnpm-state`, `~/.config/github-copilot`, `~/.config/psysh`, `~/.config/configstore`, `~/.config/jgit`, `~/.config/gtk-2.0` | tool-generated state |
| `~/.agents`, `~/.claude`, `~/.codex`, `~/.gemini`, `~/.copilot`, `~/.cline`, `~/.ai`, `~/.cagent`, `~/.codemod` | agent tooling — same "separate concern, flag for scoping" as WSL |
| `~/.config/fish/` | one uv-generated file; fish not installed — stale |
| `~/.zsh_sessions`, `.zsh_history`, `.viminfo`, `.lesshst`, `.mysql_history`, `.python_history`, `.node_repl_history`, `.wget-hsts` | history/state |
| Home-dir clutter | 2 JVM heap dumps (1.5 GB + 6.5 GB), a 2.8 GB disk image, stray `.glb`/`.png`/`.pdf`/`.yml` files, JetBrains crash logs — migration-day cleanup list, like WSL's 66 MB go tarball |

### 3.5 Configs that do not exist yet

- `tmux` — not even installed here (installed-but-unconfigured on WSL)
- `direnv`, `bat`, `eza`, `mcfly` — no config, same as WSL (mcfly keeps state in `~/Library/Application Support/McFly` — another macOS-path data point)

---

## 4. macOS-only surface

- **`defaults` / system preferences:** no `defaults write` script exists today, so there is nothing to migrate — tracking one would be *new* work, not adoption. Candidates if ever wanted: Rectangle, Alfred, KeyCastr, Dock/keyboard settings. Recommend: out of scope for the first pass, one line in the package ticket to confirm.
- **Login items (7):** OneDrive Sync, Cloudflare WARP, ClickUp, Rectangle, FigmaAgent, Alfred 5, Warp — machine setup, not repo material; recorded so the bootstrap doc can mention them as manual steps.
- **Path divergences the templates must encode:** k9s and helm configs live under `~/Library/Application Support` / `~/Library/Preferences` here vs `~/.config` on Linux; mcfly state likewise.
- **GUI app estate:** ~75 apps in `/Applications` + JetBrains fleet in `~/Applications`, 9 casks — the gap is the package ticket's biggest macOS question.
- **Keychain** as the ambient secret store; `pinentry-mac` + native gpg for signing.

---

## 5. Findings that belong to other tickets

**Shell architecture (#4)**
- The two `.zshrc`s are one fork: hardcoded `/opt/homebrew` here vs `$HOMEBREW_PREFIX` there. Standardize on early `brew shellenv` in `.zprofile` (the Mac already does this correctly) and template the prefix.
- Plugin lists must be **per-machine template data**: six plugins dead on WSL are live here; four declared on WSL are undeclared here; `1password` is Mac-only; `colorize`/`command-not-found` dead here for macOS reasons.
- The 2 remaining work aliases and `garage` need the per-machine/untracked override mechanism (the third, which embedded a credential, was removed on inventory day).
- `.zprofile`/`.zshenv`/`.profile` are part of the migration surface, not just `.zshrc`; cargo env is double-sourced.
- vim: adopt `~/.vim_runtime` as an external, or drop.
- Same `workon main` question, both machines.

**Package manifest (#5)**
- `helm` + `helm@3` conflict here vs clean `helm@3` pin on WSL.
- Go: brew here, tarball there (plus a stale `/usr/local/go` here) — one manifest answer, applied twice.
- Three JDKs, `JAVA_HOME` hardcoded to the manual one; `temurin` cask vs GraalVM decision.
- 10 node versions with stray per-version globals; pnpm real here, phantom on WSL.
- Lib leaves (`icu4c@76`, `jpeg`, `qt`, `zlib`, `unbound`, `python@3.13`) need an orphan audit; `rtk` unidentified.
- Manual `/usr/local/bin` binaries (`kubeone` on both machines) need a home in the manifest or an explicit skip.
- Casks vs the ~75 unmanaged GUI apps; no `mas`.

**Secrets strategy (#6)**
- The (removed) credential-bearing alias proved secrets can live *inside* shell rc files, not just beside them — the strategy must cover rc content, not only excluded files.
- `op` (Mac) vs `bw` (WSL) as resident CLIs — confirms the secret-source-agnostic map preference with hardware facts.
- `.gitconfig`: signing on here with a native gpg path, `includeIf` work-identity layering worth adopting repo-wide, `core.sshCommand` pins an identity key.
- Keychain noted as macOS-native store.

**Secrets vault (#11)**
- Two Ansible Vault password files (personal + work), location withheld; `~/.vault-token` from 2025.

**Fresh-machine auth fog (map)**
- Both 1Password (app + CLI) and Bitwarden (app only) are live on this machine — the unlock-sequence design has a concrete dual-manager host to test against.
