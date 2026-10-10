# Runbook — bump the skill pin

Use this to move the Matt Pocock skills to a new upstream commit. The skill pin is the sha in
the `.local/share/mattpocock-skills` entry of `home/.chezmoiexternal.toml.tmpl`. Dotfiles owns
this pin. It is not linked to the Loop pin, and the two pins can differ. Only the operator
changes it (#114).

Run the [collision check](#collision-check) also after each `brew upgrade` of codex or
opencode (#114, item 8). Claude Code updates itself, so a new Claude Code collision can stay
unknown until the next bump. This risk is accepted.

The commands below use these variables. Set them in one shell session:

```sh
PIN=<new 40-hex sha>
SRC=$(chezmoi source-path)
```

The payload has no plugin manifest: the external excludes `.claude-plugin/`, so that codex
lists bare names. The delivered names are the `symlink_` entries in `$SRC/dot_agents/skills`.

---

## Step 1 — pick the pin

Use a tag if one exists. If not, use a commit on upstream `main`. Record the full 40-hex sha
and the commit subject:

```sh
curl -s https://api.github.com/repos/mattpocock/skills/commits/$PIN | jq -r '.sha, (.commit.message | split("\n")[0])'
```

## Step 2 — read the changes

Get the new manifest. Compare its paths with the targets of the delivered links:

```sh
NEW=$(mktemp -d)
curl -sL https://github.com/mattpocock/skills/archive/$PIN.tar.gz | tar xz -C "$NEW" --strip-components=1
diff <(sed 's#.*/mattpocock-skills/##' "$SRC"/dot_agents/skills/symlink_*.tmpl | sort) \
     <(jq -r '.skills[] | ltrimstr("./")' "$NEW/.claude-plugin/plugin.json" | sort)
```

Write down the added, removed and renamed names. A path that moves to a different category
is a change too: its symlink target changes. Read the upstream changelog.

Each frontmatter `name` must be equal to its directory name (#113). Check it for each new
name:

```sh
for p in $(jq -r '.skills[]' "$NEW/.claude-plugin/plugin.json"); do
  n=$(sed -n 's/^name: *//p' "$NEW/$p/SKILL.md" | head -1)
  [ "$n" = "${p##*/}" ] || echo "MISMATCH $p: $n"
done
```

## Step 3 — collision check

Do the [collision check](#collision-check) with the names of the new manifest. A new
collision stops the bump. The operator
decides it, as in #113.

## Step 4 — edit

1. In `home/.chezmoiexternal.toml.tmpl`, change the sha in the URL and the subject comment.
2. For each added name, add two files. Each holds one line:
   - `home/dot_agents/skills/symlink_<name>.tmpl`
   - `home/dot_claude/skills/symlink_<name>.tmpl`

   ```
   {{ .chezmoi.homeDir }}/.local/share/mattpocock-skills/skills/<category>/<name>
   ```

   Both links go to the payload. Do not chain one link to the other (ADR 0002).
3. For each removed name, remove its two files. For a moved or renamed name, change them.
   For each removed or renamed name, add the two old link paths to `home/.chezmoiremove`:

   ```
   .agents/skills/<name>
   .claude/skills/<name>
   ```

   Without these entries, chezmoi keeps the old links, and they point at nothing.
4. Do not deliver a skill under `skills/in-progress/`.

## Step 5 — apply and verify

Run `chezmoi diff`, then `chezmoi apply`. Then run the [checks](#checks).

## Step 6 — commit

Make one commit:

```
chore(skills): bump skill pin to <short-sha>
```

Put the full sha and the subject in the body. Open a PR for review. The operator merges it.

---

## Collision check

Compare each skill name with the built-in skills of each agent and with the other skills in
`~/.claude/skills` and `~/.agents/skills` (#113). At a bump, use the names of the new
manifest. After an agent upgrade, use the delivered names:

```sh
names=$(jq -r '.skills[] | split("/")[-1]' "$NEW/.claude-plugin/plugin.json" | paste -sd'|')   # at a bump
names=$(ls "$SRC/dot_agents/skills" | sed -n 's/^symlink_\(.*\)\.tmpl$/\1/p' | paste -sd'|')  # after an upgrade
```

**Claude Code.** Search the binary for `name:` literals, assignments and `aliases:` entries:

```sh
bin=$(readlink -f "$(command -v claude)")
grep -aoE "(name:|[A-Za-z_\$][A-Za-z0-9_\$]*=)\"($names)\"|aliases:\[[^]]*\"($names)\"[^]]*\]" "$bin" | sort -u
```

At Claude Code 2.1.289 this prints `code-review` and `prototype`, as two assignments. These
two are known and accepted (#113). A name that the binary builds in a different way is not
found by this check.

**codex.** The system skills are directories:

```sh
ls ~/.codex/skills/.system | grep -xE "$names"
```

**opencode.** Write the list to a file before you read it. Through a pipe, the output stops
at 64 KiB and `jq` fails on the cut JSON (opencode 1.18.34):

```sh
opencode debug skill </dev/null > /tmp/opencode-skills.json
jq -r '.[] | select(.location == "<built-in>") | .name' /tmp/opencode-skills.json | grep -xE "$names"
```

**Other skills in the two dirs.** An entry that is not a link into the payload and has a
delivered name is a collision:

```sh
for d in ~/.agents/skills ~/.claude/skills; do
  for e in "$d"/*; do
    case "$(readlink "$e" 2>/dev/null)" in */mattpocock-skills/*) continue ;; esac
    basename "$e"
  done
done | grep -xE "$names"
```

Each command prints nothing when there is no new collision. The agent versions that #113
checked are Claude Code 2.1.289, codex 0.160 and opencode 1.18.34.

---

## Checks

Run these on each machine after the apply.

1. **Payload at the pin.** The external URL has the new sha:

   ```sh
   grep -o 'mattpocock/skills/archive/[0-9a-f]*' "$(chezmoi source-path)/.chezmoiexternal.toml.tmpl"
   ```

2. **Names at the pin.** Each delivered name has a link in both dirs, and the payload has no
   plugin manifest. This prints nothing:

   ```sh
   for n in $(ls "$SRC/dot_agents/skills" | sed -n 's/^symlink_\(.*\)\.tmpl$/\1/p'); do
     for d in ~/.agents/skills ~/.claude/skills; do [ -L "$d/$n" ] || echo "MISSING $d/$n"; done
   done
   ls -d ~/.local/share/mattpocock-skills/.claude-plugin 2>/dev/null
   ```

3. **No dangling link.** This prints nothing:

   ```sh
   find -L ~/.agents/skills ~/.claude/skills -maxdepth 1 -type l
   ```

4. **No `in-progress` skill.** This prints nothing:

   ```sh
   for d in ~/.agents/skills ~/.claude/skills; do for l in "$d"/*; do [ -L "$l" ] && readlink "$l"; done; done | grep in-progress
   ```

5. **Claude Code.** The init event lists the bare names, and no `mattpocock-skills:` name. Hook
   events come before the init event, so select it by its subtype:

   ```sh
   HINDSIGHT_DISABLE_HOOKS=1 claude -p hi --model claude-haiku-4-5-20251001 --output-format stream-json --verbose --max-turns 1 </dev/null \
     | jq -r 'select(.type == "system" and .subtype == "init") | .skills[]'
   ```

   A `skillOverrides` entry in `~/.claude/settings.local.json` hides a delivered name here.

6. **opencode.** The list has each delivered name:

   ```sh
   opencode debug skill </dev/null > /tmp/opencode-skills.json
   jq -r '.[].name' /tmp/opencode-skills.json
   ```

7. **codex.** No command lists skills without a model turn. Run one turn, then read the skill
   catalog that codex wrote into the session file. The catalog does not come from the model:

   ```sh
   (cd /tmp && HINDSIGHT_DISABLE_HOOKS=1 codex exec --skip-git-repo-check -s read-only "Reply with the single word ok." </dev/null >/dev/null 2>&1)
   f=$(ls -t $(find ~/.codex/sessions -name '*.jsonl' -mmin -5) | head -1)
   jq -r '.. | strings' "$f" | grep -oE '^- [a-z0-9:-]+: ' | sort -u
   ```

   Without `</dev/null`, `codex exec` waits for input and does not stop (codex 0.160.0).

   Expect bare names, and no `mattpocock-skills:` name. codex lists only the skills that the
   model can invoke: the skills without `disable-model-invocation: true`.
