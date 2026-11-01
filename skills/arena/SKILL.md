---
name: arena
description: "Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. Use for /arena, 'arena this', 'throw it in the arena', or when one attempt at a non-trivial artifact would lock in the wrong shape."
disable-model-invocation: true
---

# Arena

A skill named in bold or in backticks, or run as `/<name>`, is the file `../<name>/SKILL.md` beside this skill's directory, and a principle named without its prefix is `../principle-<name>/SKILL.md`. Read the file and follow it. Most pstack skills are user-only, so your skill tool cannot load them. Every subagent is a Rex worker pane: spawn, wait and close it per `../rex-subagents/SKILL.md`, with the defaults in the Subagents section of `../poteto-mode/SKILL.md`.

Open a task list (your harness's task tool, or a checklist file at `~/.local/state/pstack/checklists/<repo>-<branch>.md` when it has none) with one entry per phase (Frame, Fan out, Cross-judge, Pick, Graft, Verify) before launching anything.

## Phase A: Frame

Every candidate gets the same prompt, so the prompt is the contract.

1. State the artifact each candidate is producing.
2. Derive the rubric, 3-6 concrete gradeable criteria for what success looks like on *this* task. It is the picker's tool in Phase D. Candidates only see the task.
3. Pick the runners. Use the `arena runners` line in `~/.config/pstack/pstack-models.md`, one seat per entry, each passed to `subagent spawn --entry` as written. If the file or that line is missing, default to one `claude` seat and one `codex` seat at xhigh, each on its harness's default model. Say so and suggest `/setup-pstack`. An `auto` or `inherit-parent` entry in this line means your own harness on its default model. A family is the harness: `claude` or `codex`. If a configured entry's model is rejected, run that seat on its harness's default model and say so. If that fails too, drop the seat and say so. If dropped seats leave fewer than two runners, add runners until there are two, or one when the line has one entry. Run each added runner on a remaining runner's entry, or on your own harness when none remain, and say so. Spawn more runners when the arena covers multiple design directions. Use the same model N times when the work is generation-bound rather than judgment-sensitive. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **poteto-mode** skill.
4. Give each candidate its own output location (a git worktree where possible, otherwise `/tmp/arena-<slug>/candidate-<n>/`), per the **separate-before-serializing-shared-state** principle skill. A candidate that writes code gets `--worktree arena-<slug>-<n> --base <base commit>`. Commit the base first, because uncommitted edits do not reach a new worktree.

## Phase B: Fan out

Spawn all N candidates in one turn, one `subagent spawn` each named `arena <slug> <n>`, each with the task, the absolute path to the shared grounding, its own output path, and instructions to produce the artifact and a short rationale naming the alternatives it considered and what it rejected. End the turn. Each candidate's wake-up line starts your next turn, and `subagent status` shows each candidate's worktree.

If a candidate produces no output, proceed with N-1 and note the dropout.

## Phase C: Cross-judge

After all Phase B candidates complete, choose one model from the `arena cross-judge pool` line in `~/.config/pstack/pstack-models.md`. If the file or that line is missing, the pool is one `claude` and one `codex` entry at xhigh on their default models. Spawn one judge with `--read-only`. The judge is never from your own family, the harness you run in, as Phase A step 3 defines families. Try only the entries from another family, in pool order. An `auto` or `inherit-parent` entry is your own model, so it never judges. With the default pool, a Claude Code main gets the `codex` judge and a Codex main gets the `claude` judge. If an entry's model is rejected, move to the next entry. If no entry from another family runs, try the default pool's entries from another family the same way. If none of those runs, skip the judge, pick the base alone in Phase D, and say so. The judge sees the rubric and the candidates by path label, scores each criterion, and recommends a base with rationale. It runs in parallel with your reading in Phase D. Don't spawn it while candidates are still writing.

## Phase D: Pick a base

Read every candidate end to end before picking. Score each against the rubric criterion by criterion, not on holistic feel, and compare with the cross-judge when Phase C ran one. Agreement on the base confirms the pick. Disagreement means one of you is biased or the rubric was ambiguous. Read both rationales before deciding.

Pick the base a future maintainer can extend most easily without breaking invariants. When two feel tied, prefer the cleaner boundary or smaller API, per the Laziness Protocol.

## Phase E: Graft

Walk each losing candidate once more for what is worth porting into the base, usually one or two things per candidate, not most of it. Fold each graft in by hand, per the **redesign-from-first-principles** principle skill, so the result stays coherent under one mental model. Don't paste mechanically.

If the candidates converge on one shape, that is strong agreement. Note it and ship the consensus shape. No graft is needed. If they wildly diverge, Phase A was under-specified. Reframe and re-run rather than averaging the divergence.

## Phase F: Verify

Verify the synthesized artifact like any other output, per the **prove-it-works** principle skill. If verification finds a problem the arena missed, either Phase A was wrong (re-frame and re-run) or a candidate caught it and you missed the graft (go back to Phase E). Don't paper over it.

## Outputs

One synthesized artifact, with a short synthesis note alongside naming the base and why, the cross-judge's verdict or that Phase C skipped the judge, each graft with its source candidate, what was rejected and why, any convergence or dropouts, and the verification result.
