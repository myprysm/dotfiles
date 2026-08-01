# Runbook — relocate a secret file whose path was published

Use this when a secret file's *location* has leaked (committed to a public repo, pasted into
an issue, quoted in a doc). Rewriting history does not undo it: existing clones keep the old
objects, and force-pushed commits stay reachable until the host garbage-collects. Only moving
the file makes the published location worthless.

The path itself is an infrastructure identifier under the redaction rule in
[`../secrets.md`](../secrets.md), so it never enters this repo. The guardrails that must name
the location read it from `secretsDir`, a machine-local chezmoi variable seeded at
`chezmoi init` and stored only in `~/.config/chezmoi/chezmoi.toml`.

Run every step in one shell session, in order.

---

## Step 0 — choose the new location

```sh
export NEWDIR=~/.local/state/<opaque-name>
```

Requirements:

- under `~/.local/state/` — machine-local, non-config data
- opaque name. Not `secrets`, not `ansible`, not `vault`
- **not** a sibling of the old directory, and **not** beside
  `~/.local/share/dotfiles-secrets` — that one is published in `scripts/secrets-common.sh`,
  so anything next to it is guessable
- letters, digits, dashes. No dots (they become regex metacharacters), no trailing slash

`~` is expanded at assignment, so `$NEWDIR` is absolute from here on. Keep this shell open.

Three consumers want three different forms. Every command below produces the right one —
never type `$NEWDIR` into a prompt or a vault field, always its expanded value:

| where | form |
|---|---|
| tool config that must hold a literal | absolute path to the **file** |
| `chezmoi init` `secretsDir` prompt | absolute path to the **directory** |
| vault restore item `path` field | `$HOME`-relative path to the **file** |

---

## Step 1 — enumerate before moving

```sh
ls -l <old directory>
```

Record every filename and mode. Step 3 checks them again.

## Step 2 — create the new directory

```sh
mkdir -p "$NEWDIR" && chmod 700 "$NEWDIR"
```

## Step 3 — move, preserving mode

```sh
stat -c '%a %U %n' <old directory>/*        # macOS: stat -f '%Lp %Su %N'
mv <old directory>/* "$NEWDIR"/
stat -c '%a %U %n' "$NEWDIR"/*
```

Modes must be identical before and after. A vault password file with the wrong mode fails
silently — the tool reports a wrong password, not a permission problem.

## Step 4 — repoint the consumers

Find them first; do not work from memory:

```sh
grep -rn '~/<old dir>\|\$HOME/<old dir>\|'"$HOME"'/<old dir>' ~/projects \
  | grep -v '/\.git/'
```

Split the hits into two classes:

- **Config that must resolve a literal path** (`ansible.cfg` `vault_password_file`, service
  units, wrappers) — rewrite to the new absolute path.
- **Prose: agent instruction files, READMEs, comments** — do *not* write the new path here.
  Replace with a pointer: *"location per the local secrets policy — never hardcode, echo, or
  commit it."* A path written in prose gets copied into agent transcripts and memory.

Re-run the `grep` until it returns nothing but deliberate mentions of the **old** location.

## Step 5 — seed `secretsDir` and apply

**If this machine is not on chezmoi yet, skip steps 5 and 6.** Write the chosen directory
down for the eventual `chezmoi init`, and carry on at step 7. The move is what neutralises
the published path; the guardrails follow whenever the machine is migrated.


The guardrails reference a variable the machine config does not have yet, so `chezmoi apply`
fails loudly until this runs. That is intended.

```sh
chezmoi init      # answer the secretsDir prompt with the absolute directory path
chezmoi apply
chezmoi status    # expect no output
```

If the chezmoi source directory is a working tree on a feature branch, merge to `main`
first — `chezmoi init` runs `git pull` inside the source directory.

## Step 6 — verify the guardrails picked it up

```sh
grep -n 'secret_re=' ~/.claude/hooks/block-secret-reads.sh   # new dir present, dots as [.]
jq '.permissions.deny' ~/.claude/settings.json               # Read(<newdir>/**) present
printf '{"tool_name":"Read","tool_input":{"file_path":"'"$NEWDIR"'/x"}}' \
  | bash ~/.claude/hooks/block-secret-reads.sh
```

The last command must print a `deny` decision.

## Step 7 — verify the tool still works

For an Ansible Vault password file where nothing is wholly encrypted — only inline `!vault |`
values — `ansible-vault view` does not apply. Extract one block and decrypt it to stdout,
which the shell drops:

```sh
vaultcheck() {
  awk '/!vault[[:space:]]*\|/{g=1;next}
       g{ if ($0 !~ /^[[:space:]]/) exit; sub(/^[[:space:]]+/,""); print }' "$1" > /tmp/vblob
  grep -q '\$ANSIBLE_VAULT' /tmp/vblob || { echo "NO BLOCK FOUND in $1"; rm -f /tmp/vblob; return 1; }
  ansible-vault decrypt --output=- /tmp/vblob > /dev/null && echo "VAULT-OK  $PWD"
  rm -f /tmp/vblob
}
```

Not `--output=/dev/null`: ansible tests whether the *directory* `/dev` is writable, which it
is not, and refuses before decrypting anything. With `--output=-` the plaintext goes through
a pipe only — never to disk, never to the terminal.

No `--vault-password-file` argument on purpose: the tool falls back to the `ansible.cfg` of
the current directory, which is what step 4 changed and what this is testing.

Run it once **per config file**, not once per repository — a repository with a second
`ansible.cfg` in a subdirectory has a second copy of the path.

`ansible` is often absent from the default non-interactive `PATH`; run this in whichever
venv/uv environment normally has it.

## Step 8 — repoint the vault restore item

Skip this and `secrets-restore.sh` puts the file straight back at the published path on the
next fresh machine.

The `path` field is **`$HOME`-relative** — the script does `place "$HOME/$path"`. No leading
slash, no `~`.

```sh
export BW_SESSION="$(bw unlock --raw)"
bw sync
RID="$(bw list folders --search 'dotfiles/restore' \
        | jq -r '.[] | select(.name=="dotfiles/restore") | .id')"

# ids, names and field NAMES only — no values
bw list items --folderid "$RID" \
  | jq -r '.[] | [.id, .name, ((.fields//[])|map(.name)|join(","))] | @tsv'

ITEM=<id>
bw get item "$ITEM" | jq -r '[(.fields//[])[]|select(.name=="path").value][0]'
bw get item "$ITEM" | jq -r '[(.fields//[])[]|select(.name=="mode").value][0]'
```

`mode` must match what step 3 showed. Then:

```sh
NEWREL="${NEWDIR#$HOME/}/<filename>"
echo "$NEWREL"          # sanity: no leading slash, no ~

bw get item "$ITEM" \
  | jq --arg p "$NEWREL" '(.fields[] | select(.name=="path") | .value) = $p' \
  | bw encode | bw edit item "$ITEM"
bw sync
bw get item "$ITEM" | jq -r '[(.fields//[])[]|select(.name=="path").value][0]'
```

On a work-domain item the same shape applies through `op` instead of `bw`.

Never paste raw `bw get item` output anywhere — it carries the secret itself, in `notes` or
as an attachment. The `jq` filters above print one field each.

## Step 9 — audit and clean up

```sh
scripts/secrets-audit.sh
rmdir <old directory>
```

`secrets-audit.sh` only checks that restore items *exist*; it does not validate their `path`.
Step 8's final read is the only proof the repoint landed.

`rmdir` refuses if anything is left behind — if it refuses, go back to step 3.

## Step 10 — commit the consumer edits

Conventional commits, in whichever repositories step 4 touched. Do not put the new path in a
commit message.

---

## For an agent driving this

This runbook is deliberately machine-agnostic: the concrete file list differs per machine and
naming it here would breach the redaction rule. Rebuild it by discovery, never from memory or
from another machine's list.

**Discover the consumers.** Ask the human for the old directory, then:

```sh
ls -l <old directory>                          # the file set — names and modes
grep -rn '<old directory>' ~/projects | grep -v '/\.git/'
```

Every hit is either config-that-must-hold-a-literal or prose. Classify each one and say which
class it is before editing anything — the two get opposite treatment in step 4.

Count config files, not repositories. A repository with a nested second `ansible.cfg` needs
two edits and two verifications.

**What you cannot do, by design.** State these as human steps rather than attempting them:

- Reading anything under the secrets directory. The `block-secret-reads.sh` hook denies it,
  and so does the `Read(...)` deny rule in `settings.json`.
- `ansible-vault view|decrypt|edit|cat|rekey`. Unconditionally denied for agents, so step 7's
  verification is the human's.
- Unlocking the vault (step 8).

**What you must not do.** Do not ask for, echo, or write down the new path. Prefer handing
the human a checklist whose commands reference `$NEWDIR` so the value never reaches your
context — anything in your context is in a transcript on disk, and may be ingested by a
memory service. If it does reach you anyway, say so plainly and let the human decide whether
to re-pick; do not quietly continue.

Do not put the new path in a commit message, an issue, or any tracked file.

**Verify by evidence.** After the human reports back, re-run the `grep` from step 4, confirm
the old directory is gone, and read the rendered guardrails. Do not report success from the
absence of errors.

---

## What stays behind, deliberately

The **old** location keeps its guardrail entries — the deny-list row and the hook's pattern
list — for as long as any machine still has it. They protect a machine that has not been
through this runbook yet, and they publish nothing that was not already public.

The new location appears in no tracked file, in any repository. That is the whole point.
