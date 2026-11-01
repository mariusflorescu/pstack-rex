---
name: how
description: "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this the right layer\"). Explains subsystem architecture, runtime flow, onboarding mental models. Use why for motivation."
disable-model-invocation: true
---

# How

A skill named in bold or in backticks, or run as `/<name>`, is the file `../<name>/SKILL.md` beside this skill's directory, and a principle named without its prefix is `../principle-<name>/SKILL.md`. Read the file and follow it. Most pstack skills are user-only, so your skill tool cannot load them. Every subagent is a Rex worker pane: spawn, wait and close it per `../rex-subagents/SKILL.md`, with the defaults in the Subagents section of `../poteto-mode/SKILL.md`.

Explore the codebase to answer "how does X work?" questions. Produce architectural explanations at the level of a senior engineer onboarding onto a subsystem, enough to build a working mental model, not so much that it reads like annotated source code.

Every spawn is a worker with `--read-only` and a plain brief: the filled prompt template. Explorers are named `how explorer <angle>` and use the `how explorer` line in `~/.config/pstack/pstack-models.md`, and every explainer is named `how explainer` and uses the `how explainer` line. Pass the entry to `subagent spawn --entry` as written. When the value is `auto` or `inherit-parent`, or the file or the line is missing, run the worker on your own harness and its default model. With no file, say so and suggest `/setup-pstack`. If a worker's model is rejected, run it on that harness's default model and say so. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **poteto-mode** skill. End the turn after spawning and let the wake-up lines start your next turns.

## 1. Assess complexity

If the scope is ambiguous, state your interpretation and explore. The user can redirect.

- **Simple** (a single module, a small utility, a narrow question such as "how does function X work"): no explorers. Spawn one explainer that explores and explains in one pass, built from `references/explainer-prompt.md` without the explorer-findings section. Go to step 4.
- **Complex** (a subsystem spanning multiple files or services, a cross-cutting feature, a full architectural overview): go to step 2.

When in doubt, take the simple path.

## 2. Explore (complex only)

Decompose the question into 2 to 4 angles, each a distinct slice of the subsystem. Spawn all explorers in a single turn, each with `references/explorer-prompt.md` and its angle filled in.

## 3. Synthesize (complex only)

Once all explorers have returned, spawn one explainer with `references/explainer-prompt.md` and every explorer's findings filled in.

## 4. Present

Present the explainer's output. Light edits for clarity or context from the conversation are fine. Do not substantially rewrite it.

## Output format

The explanation uses the sections defined in `references/explainer-prompt.md`, dropping any that do not apply: Overview, Key Concepts, How It Works, Where Things Live, Gotchas.
