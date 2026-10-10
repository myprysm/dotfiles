---
name: cross-research
description: Research a question with a Claude agent and an independent Codex run, then reconcile the two into one cited note. Use when the Operator asks for research cross-checked with Codex, or a decision rests on facts one model family could get wrong.
---

Two model families answer the same questions apart, then one reconciles the other claim by claim, so an error one makes alone is caught. The reconciled note follows the `research` skill: primary sources, every claim cited, saved where the repo keeps research notes.

## 1. Plan, then approval

Write the question file in the scratchpad: the goal, the repos and refs to read (and which are read-only), the numbered questions, what each answer must carry (citations, verified or inferred, a size or verdict when asked), and "unknown stays unknown". Then show the Operator:

- the questions, one line each;
- the models: the Claude agent's model (a stronger one for cross-repo design questions, a cheaper one for lookup) and the Codex model and reasoning effort, matched to it per the Operator's standing rule when one exists; both read-only;
- where the note lands.

Done when the Operator approved the plan and both models. Dispatch nothing before.

## 2. Run both

In the same turn, both in the background:

- **Claude**: one agent (`Agent`, `run_in_background`), told to invoke `research`, to answer the question file, to write the note at the agreed path and change nothing else, to spawn no sub-agents, and to end with the note path and a short summary, then wait for a Codex report to reconcile.
- **Codex**, from the repo the questions centre on:

  ```bash
  HINDSIGHT_DISABLE_HOOKS=1 codex exec -m <model> -c model_reasoning_effort=<effort> -s read-only --ephemeral --add-dir <other repo> -o <scratchpad>/codex-<topic>.md - < <question file> > <scratchpad>/codex-<topic>.log 2>&1
  ```

  `HINDSIGHT_DISABLE_HOOKS=1` keeps recalled bank memories out of the Codex run, so it stays independent (#135).

Report each output's headline to the Operator as soon as it lands, marked not yet cross-checked.

## 3. Reconcile

When both are in, send the Codex report path to the Claude agent (`SendMessage`): check each Codex claim that differs from or adds to the note against the source, mark it confirmed, refuted, disputed (the source does not settle it) or unverified; fold confirmed ones in; fix what Codex shows wrong; keep both views on a dispute; add a `## Cross-check` section with the counts and one line per refuted or disputed claim.

Done when the note has the `## Cross-check` section and every Codex claim is counted.

## 4. Report

Read the whole note. Spot-check its load-bearing claims against the source yourself. Then report: the answers in a few lines, and one quiz per disputed point and per decision the note asks of the Operator, recommendation first. Commit the note only on the Operator's go.
