# Rex-native contract

pstack upstream (`cursor/plugins`, path `pstack/`) is written for Cursor. This repo ships the same skills for Claude Code and Codex running in [Rex](https://www.superlogical.com/rex), where every subagent is a Claude Code or Codex agent in a Rex pane next to the main agent. This file is the translation contract. Every skill follows it, and every upstream sync applies it to the incoming change. When upstream text and this contract disagree, this contract wins.

Keep upstream wording wherever it is harness-neutral. Change only what names a Cursor mechanism, and replace it with the mechanism below, not with vague "whatever the harness offers" prose. `node scripts/check-rex-native.mjs` enforces the mechanical part. [DESIGN.md](./DESIGN.md) explains the runtime.

## What reaches an agent

`npx skills add mariusflorescu/pstack-rex -g -a claude-code -a codex` copies each `skills/<name>/` directory into `~/.agents/skills/<name>/` (Codex reads it there) and symlinks `~/.claude/skills/<name>` to it (Claude Code reads it there). Nothing else in this repo reaches an agent: not this file, not `README.md`, not `scripts/`. A skill links only inside its own directory or to a sibling skill (`../<other-skill>/...`). Anything a skill needs at runtime lives under its own `references/`, `playbooks/` or `scripts/`.

## The Rex layer

- `skills/rex-subagents/` is new and holds the whole runtime: `scripts/subagent` (spawn, run, status, result, say, answer, close, wait, whoami, poke), `scripts/watch.lua` (the watcher), `scripts/sessions` (Claude Code transcripts and Codex rollouts). Its `SKILL.md` is the one place that explains workers to an agent. Other skills point to it and don't restate it.
- Every other change is a line edit to upstream text, made by this contract. `scripts/sync-upstream.sh --layer` prints all of them as one diff against the pinned upstream commit.

## Harness facts

Probed in Rex `0.0.1793299046` with Claude Code 2.1.316 and Codex 0.166.0 on 2026-11-01. Re-probe before changing a rule that rests on one.

| Fact | Claude Code | Codex |
| --- | --- | --- |
| User skills | `~/.claude/skills/` | `~/.agents/skills/` |
| Project skills | `<cwd>/.claude/skills/` | `.agents/skills/` in every directory from the project root to the cwd |
| Where a loaded skill's location shows | `Base directory for this skill: <dir>` | `<path><dir>/SKILL.md</path>` with the injected skill |
| `disable-model-invocation: true` | Hidden from the model | Ignored. Codex reads `agents/openai.yaml` |
| `agents/openai.yaml` `policy.allow_implicit_invocation: false` | Ignored | Hidden from the skills list. `$<name>` still loads it |
| How the user runs a skill | `/<name>` | `$<name>` |
| Built-in subagents | Agent tool | Its own agents (`/root` and children) |
| Program Status (OSC 7501) | `idle`, `working` (with `msg`), `done`, `blocked` | `idle`, `working`, `done`. A redraw or resize turns `done` into `idle` |
| A command run by the agent sees | Its own pane's environment (`REX_BLOCK`, `CLAUDE_CODE_SESSION_ID`) | `CODEX_THREAD_ID` always. A plain `codex` runs commands on its shared app-server daemon, whose environment is the pane that started the daemon. Any `-c` override keeps it in-process with its own pane's environment |
| Input from outside | Typed text plus Enter starts a turn when idle and is taken between tool calls when busy | `codex queue --thread <id> --message` starts a turn when idle and lands as the next turn when busy. A slash command sent this way arrives as plain text. Typed text is read as a paste, so an Enter right after it is dropped |
| First run in a repository root | A trust dialog with "No, exit" preselected, and no status | A trust dialog, even with a trusted parent, and no status. A `-c` trust override doesn't skip it |
| Conversation name | `-n <name>` | `/rename <name>` typed while idle |
| Transcript | `~/.claude/projects/<cwd with / and . as ->/<session id>.jsonl` | `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<thread id>.jsonl`, names in `~/.codex/session_index.jsonl` |

## Skills, paths and briefs

- **A skill named in bold or in backticks, or run as `/<name>`, in agent-facing text** is the file `../<name>/SKILL.md`, resolved from the naming skill's base directory. A principle named without its prefix is `../principle-<name>/SKILL.md`. Keep upstream's short form in the text. Read the file. Do not expect the harness's skill tool to load it: almost every pstack skill is user-only.
- **Standalone skills.** A skill that names another skill carries this sentence right after its title: "A skill named in bold or in backticks, or run as `/<name>`, is the file `../<name>/SKILL.md` beside this skill's directory, and a principle named without its prefix is `../principle-<name>/SKILL.md`. Read the file and follow it. Most pstack skills are user-only, so your skill tool cannot load them." A skill that spawns subagents adds "Every subagent is a Rex worker pane: spawn, wait and close it per `../rex-subagents/SKILL.md`, with the defaults in the Subagents section of `../poteto-mode/SKILL.md`." The checker enforces both. Principles, `poteto-mode` and `rex-subagents` are exempt.
- **Base directory.** Take it from the harness (see Harness facts). If the harness gave none, the global install puts skills in `~/.claude/skills/<name>/` on Claude Code and `~/.agents/skills/<name>/` on Codex.
- **Scripts** run from the skill's base directory (`<poteto-mode dir>/scripts/watch-pr/watch-pr`). Upstream's repo-relative `pstack/skills/...` paths become base-directory paths. Give a worker every script and `SKILL.md` it needs as an absolute path, and say to read a skill in full before any work. Never start a brief with `/<name>` or `$<name>`.
- **Skill text that tells the user to run a skill** keeps upstream's `/<name>`. The README says once that Codex runs skills as `$<name>`.
- **User-only skills.** Keep `disable-model-invocation: true` exactly where upstream has it, and ship `agents/openai.yaml` with `policy.allow_implicit_invocation: false` beside it. The checker fails when the two disagree.
- **`paths:` skills** drop `disable-model-invocation` so the model can load them on a matching file (`typescript-best-practices`).
- **Frontmatter.** `name` equals the directory name. Drop Cursor UI fields (`mode`, `icon`, `color`, `reminder`).

## Skill locations

A skill that creates or finds skills covers both harnesses, since a Rex window can hold Claude Code and Codex side by side.

- **Create** the real directory at `.agents/skills/<name>/`, then the relative symlink `.claude/skills/<name> -> ../../.agents/skills/<name>`. Commit both.
- **Find** in `.agents/skills/`, `.claude/skills/`, `~/.agents/skills/` and `~/.claude/skills/`. Entries that resolve to the same real path are one skill.
- Any line that names `.agents/skills` also names `.claude/skills`, and the reverse.

## Delegation

A subagent is a worker pane opened by `subagent spawn`. These defaults replace upstream's `Task` defaults. `rex-subagents/SKILL.md` has the commands.

- **Spawn** with `--name` naming the role and the slice, `--brief` (a file), and the role's model as `--entry`. Spawns are always asynchronous. After a fan-out, say what you wait for and end the turn. A wake-up line (`[pstack-rex] ...`) arrives as your next message for each worker that finishes, blocks, fails or exits. Never poll.
- **Never** use the harness's built-in subagents (Claude Code's Agent tool, Codex's own agents) for pstack work.
- **Briefs stand alone.** The worker gets only the brief: the goal, absolute file pointers rather than inlined context, constraints, the report format, and whether it may delegate further ("Do not delegate" otherwise). `subagent` appends the `TASK STATUS` report contract.
- **Read-only** workers get `--read-only`, which adds "read-only: inspect only, no writes, no git commands." Their tools stay as they are.
- **Results.** `subagent result <id>` reads the worker's final message from its own transcript. Close a worker once you have what you need from it.
- **Fresh by default.** A fix round, follow-up, retry or next queue item is a new `spawn` with consolidated scope: the original brief, every later directive, the prior report and branch. `subagent say` only to a worker that holds needed state (its worktree, uncommitted changes, a dev server).
- **Worktrees.** Workers without `--worktree` share the main checkout, so parallel writers there own disjoint files and run no git commands. A writer that needs its own tree gets `--worktree <branch> --base <commit or branch>`. Commit first. One writer per worktree or branch.
- **Permissions** never change: Claude workers run with `--dangerously-skip-permissions`, Codex workers with `--dangerously-bypass-approvals-and-sandbox`, and `subagent` passes no agent flags.

## Model roles

`/setup-pstack` writes `~/.config/pstack/pstack-models.md`. Skills name that exact path whenever they mention the file. Nothing loads it up front. A skill reads it when it spawns.

```
# budget: large (xhigh)
feature, refactoring: <harness>/<model> (<effort>)
interrogate reviewers: <entry>, <entry>, <entry>
```

- An entry is `claude/<model>` or `codex/<model>` with an optional `(<effort>)` from `low`, `medium`, `high`, `xhigh`, `max` that the model supports (`subagent models` lists them). `claudeAgent/<model>` (the pstack-t3 spelling) reads as `claude/<model>`. `inherit-parent` (or `auto`) runs the role on the main agent's own harness and default model. Pass an entry to `subagent spawn --entry` as written.
- **A family is the harness**: `claude` or `codex`. Arena's cross-judge and every diverse panel diversify on it.
- The effort ladder is `max` > `xhigh` > `high` > `medium` > `low`.
- A role with no line keeps the skill's default. Defaults name the harness, not a model: "a `claude` worker at xhigh" is `--agent claude --effort xhigh` on Claude Code's default model, and a `codex` worker uses the model in `~/.codex/config.toml`. With no file at all, single roles run `inherit-parent`, and a panel role takes one `claude` and one `codex` worker. Say so in the reply and suggest `/setup-pstack`.
- **A rejected model.** A worker whose model doesn't exist fails on its first turn: the wake-up says it hit an error, and its pane names the model. That entry counts as rejected. Close the worker and continue with the calling skill's fallback, or the role's harness on its default model when there is none. Say so.
- Role names stay exactly as upstream: `feature, refactoring`, `bug-fix`, `perf-issue`, `hillclimb`, `judgment and prose`, `hardest tasks`, `how explorer`, `how explainer`, `why investigators`, `why synthesizer`, `reflect tooling`, `reflect judgment, divergent, synthesizer`, `arena runners`, `arena cross-judge pool`, `swarm workers`, `architect runners`, `interrogate reviewers`.

## Translation table

| Cursor / upstream | Rex |
| --- | --- |
| `Task` tool, "spawn a subagent", `subagent_type`, `run_in_background: true`, `is_background` | `subagent spawn` per Delegation. |
| `subagent_type: "poteto-agent"`, `agents/poteto-agent.md` | The brief opens with the text of `poteto-mode/references/poteto-agent.md`, its `<poteto-mode SKILL.md>` placeholder replaced by the absolute path. Routed skills (`how`, `why`, `interrogate`, `reflect`, `swarm`) keep the briefs they prescribe. |
| `agents/comment-sicko.md` | `no-comments/references/comment-sicko.md`, pasted verbatim at the top of the worker's brief. |
| `generalPurpose` | A plain brief, without the `poteto-agent` text. |
| `readonly: true`, "readonly strips MCP" | `--read-only`. |
| Model slugs (`grok-*`, `claude-*-xhigh`, `gpt-*`, `composer-*`), "default model X" | The role name ("your `bug-fix` model"), resolved per Model roles. A default names a harness. |
| Families by slug prefix | The harness: `claude` or `codex`. |
| The Task tool rejecting a slug | A rejected model, per Model roles. |
| `/setup-pstack` rule, `~/.cursor/rules/pstack-models.mdc`, `alwaysApply` | `~/.config/pstack/pstack-models.md`, read on demand. |
| Resume, message or queue a follow-up on a subagent | A fresh `spawn`. `subagent say` only to a worker that holds needed state. |
| Cloud agent, `environment: "cloud"`, cloud VM, background agent, `cloud_base_branch` | A worker pane, with `--worktree <branch> --base <ref>` when it needs its own tree or branch. Everything runs on this machine. |
| `environment: "local"` | Drop it. Every worker is local. |
| `/loop`, polling loops, wake-ups, "sleep and check again" | `subagent run --name <label> -- <command>`: the command's exit wakes you. A timer is `-- sleep <seconds>`. Arm it and end the turn. |
| `scripts/watch-pr/watch-pr` as a blocking poller | Unchanged. Run it with `subagent run` so its exit wakes you. |
| Graphite (`gt`) stack bookkeeping | `gh` and git. Stack order comes from each PR's base branch (`gh pr list --author @me --json number,headRefName,baseRefName`). |
| A run's built-in PR tool, `draft: false` | `gh pr create` (ready unless the playbook says draft). |
| Origin forge (`origin pr ...`, `command -v origin`) | `gh` only. |
| `agent-transcripts/*.jsonl`, `~/.cursor/projects/...` | `rex-subagents/scripts/sessions list` and `sessions read <id>`: Claude Code transcripts and Codex rollouts for the current repository. |
| Cursor restart, "local agents are dead" | The Rex server keeps sessions, panes and agents across app restarts. `subagent status` lists the workers and restarts the watcher. Agents die only with their pane, the Rex server, or a reboot. |
| `AskQuestion` | Ask plainly in the chat. |
| Cursor's todo list ("open a todolist") | The harness's task list (Claude Code's task tools, Codex's plan tool). Without one, a checklist file at `~/.local/state/pstack/checklists/<repo>-<branch>.md`. |
| `control-ui`, `control-cli` (`cursor-team-kit`) | The project's own verification skill if it has one (see `create-verification-skill`). Otherwise a browser automation tool for web UIs, the simulator CLIs (`xcrun simctl`, `adb`) for mobile, and a Rex pane for CLIs and TUIs (`rex send`, `rex send-key`, `rex capture`). |
| `deslop` from `cursor-team-kit` | The bundled `deslop` skill. |
| `create-skill` (Cursor built-in) | The `skill-creator` skill when installed, otherwise the Authoring-a-skill playbook. |
| Cursor's built-in `babysit` skill | Drop the reference. The Babysit playbook stands alone. |
| Cursor hooks, `.cursor/` rules, Cursor settings | `AGENTS.md` / `CLAUDE.md` (project or user), project skills per Skill locations, `~/.config/pstack/pstack-models.md`. |
| Cursor custom modes, `mode: true`, `reminder:` | Skills run by name (`/poteto-mode`, `$poteto-mode` on Codex). |
| `git show origin/main:pstack/skills/<path>` | Read `<skills dir>/<path>` from the installed copy. `npx skills update -g` refreshes it. |
| Secrets typed into chat | Never in chat. The user puts the secret in a file or the macOS Keychain on this machine, and the agent reads it from there without printing it. |
| A Cursor webhook routine, a secret-request card | A local server that wakes the agent with `subagent poke`, per `make-bot-ui`. |
| Screenshots or video for the human | The browser automation tool's capture, or `screencapture` for the screen. |
| Bugbot | Keep the name. It is a GitHub review bot, and the same triage applies to any review bot on the PR. |
| Transcript scope (`~/.cursor/projects/<workspace>/`) | `sessions list` defaults to the current repository. Pass `--all-projects` only when the user asks: other projects hold unrelated private chats. |

## Scripts

- `watch-pr`: upstream's poller, unchanged. A skill runs it through `subagent run`, so its exit is the wake-up.
- `worktree-audit.sh`: `gh` for PR state, `sessions` for the last agent activity per worktree.
- `check-plan.mjs`, `bootstrap.ts`, `package.json`, `bun.lock`: unchanged unless a ported playbook changes the markers `check-plan.mjs` requires.

`bun test` and `bun run typecheck` in `skills/poteto-mode/scripts` stay green.

## Writing rules

- Thin over complete. Keep the shortest text that still changes behavior.
- pstack's voice: terse, declarative, no filler. No long-dash character in text you write. Verbatim upstream sentences keep theirs.
- Never mention a Cursor tool, even as a fallback.

## Definition of done

`node scripts/check-rex-native.mjs` exits 0 (pass skill names to check a subset). It fails on Cursor mechanisms in skill text, a bold skill name that resolves to no directory, a broken or escaping relative link, a frontmatter `name` that differs from its directory, a `disable-model-invocation` skill without the matching `agents/openai.yaml` (or the reverse), a `paths` skill that is also user-only, a models-file mention without its full path, a skill-location line that names only one harness's folder, a missing standard sentence, and a mention of the harness's built-in subagent tools as the way to delegate.
