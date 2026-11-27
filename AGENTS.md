# AGENTS.md

Working rules for anyone (people or AI coding agents) changing this repo. Read this before the first change.
Setting up a machine (hooks, signing, linking Dota to the clone) is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

OpenHyperAI is a set of Lua bot scripts for Dota 2. The game runs them with LuaJIT. There is no build step and
no unit-test harness: the checks below plus a real bot game are the test.

## Repo map

`bots/` is exactly what goes into Dota's `vscripts/bots` (`GetScriptDirectory()` is that folder in game); everything
else is tooling, tests and docs.

| Path | What it is |
|---|---|
| `bots/heroes/hero_<name>.lua` | One file per hero: skill build, item build, ability use (`X.SkillsComplement`, `X.Consider*`). |
| `bots/lib/func_utils.lua` (`Fu`) | Shared helpers, assembled from `bots/lib/general_utils/*.lua`. |
| `bots/lib/systems/` | Shared systems: push, defend, wards, items, roles, logging, version. |
| `bots/lib/hero/` | Shared hero code: minions/illusions, Rubick's stolen spells (`rubick_hero/`), sub-units. |
| `bots/lib/data/` | Static tables (hero names, matchups, position weights, spell lists). |
| `bots/lib/dota/` | Dota API names and constants (`index`, `enums`, `interfaces`, `heroes`). |
| `bots/lib/vendor/` | Generic libraries: `json` (dkjson), `native_operators`. |
| `bots/mode_*_generic.lua` | Bot modes (laning, farm, retreat, push, defend, roshan, rune, ward, ...). |
| `bots/ability_item_usage_generic.lua`, `bots/item_purchase_generic.lua`, `bots/hero_selection.lua`, `bots/bot_generic.lua` | Item/ability use, buying, drafting, per-bot think. |
| `bots/customize/general.lua` | User settings and **local test lineups**. |
| `bots/customize/version.lua` | Build number shown in game. |
| `tests/` | LuaJIT tests against a stub bot API (`tests/run.lua`, `tests/stub_api.lua`). |
| `tools/` | Node.js developer tools (log splitter, build checks); see `tools/README.md`. |
| `docs/` | Notes such as `BOT_API_RUNTIME.md` (what the bot API really exposes). |
| `install/` | Link helpers for players who install from the Workshop folder. |
| `workshop/` | Workshop page assets: the cover images (`cover.png`, `cover-512.png`). |
| `local/` | Git-ignored local data: match logs, the verify tracker, generated reports and caches. |

Folder names are lowercase (`bots/heroes`, `bots/lib`, `tools`, `docs`; maintainer, 2026-11-23); files use snake_case.
The layout came from one codemod, `tools/restructure.js` (#221): a branch from before it migrates with
`node tools/restructure.js --migrate-branch` (a branch without the file runs main's copy:
`git show origin/main:tools/restructure.js > ../restructure.js && node ../restructure.js --migrate-branch`), and
`--check` lists old paths or log tags left in a branch.
The optional Fretbots / Buff plugin lives on the orphan branch `plugin-fretbots`, not here.

### Files the engine loads from the root

Dota loads these only from the root of the `bots` folder (`bots/` in the repo), by exact name; a copy in a
subfolder is never run (the bot silently falls back to Valve's default): `mode_<mode>_generic.lua`,
`bot_generic.lua`, `hero_selection.lua`, `ability_item_usage_generic.lua`, `item_purchase_generic.lua`. Keep them
directly in `bots/` and put shared logic in `bots/lib/`. A mode file whose name doesn't match a real mode (e.g. `mode_roam_generic_wip`)
is never loaded either; don't keep such copies.

### Valve default modes we keep on purpose

Adding `mode_<name>_generic.lua` replaces Valve's built-in mode **entirely**: the script cannot call Valve's own
`GetDesire`/`Think` for that mode. Two modes stay Valve's on purpose; do not add files for them:

- **Item mode (`mode_item_generic.lua`)** - Valve's item mode is what picks up the river bounty and water runes
  (`mode_rune_generic.lua` walks a bot to the river spot and holds it for the item mode). Our own item mode
  (own drops, Gem, Rapier, tokens only) stopped the river gold being taken, so it was removed (2026-11-17).
  The cost: bots may still pick up another hero's dropped item.
  A GetDesire-only `mode_item_generic.lua` was tried (#141, game 063): Valve's item Think did not run behind it
  and no river rune was picked up.
- **Evasive maneuvers (`mode_evasive_maneuvers_generic.lua`)** - Valve's projectile/AoE dodging. Overriding
  it would drop the dodging. Where it gets bots killed (low HP, outnumbered), `mode_retreat_generic.lua`
  returns a desire above it instead (`[SHy-RETREAT] over-evasive`).

Prefix a file with `--` only for a short local test, never as a long-term "disabled" copy: delete it instead.

## Branches and pull requests

- Branch every change from the **current `origin/main`**. Never stack a branch on an unmerged branch: PRs are
  **squash-merged**, so a stacked branch conflicts with `main` afterwards. If `main` moved under your branch,
  merge `origin/main` into it (merge commits are allowed on feature branches) or replay your commits onto
  `origin/main` in a new branch. Do not force-push.
  A branch from before the layout change (#221: it has no `bots/` folder yet) migrates
  with `node tools/restructure.js --migrate-branch` instead (main's copy: see Repo map): a plain merge conflicts on
  every line it changed next to a rewritten path or log tag.
- Branch names: `fix/<topic>`, `feat/<topic>`, `chore/<topic>`, `docs/<topic>`, releases `release-vX.Y`.
- Every commit must be **signed** (the branch rules reject unverified commits).
- PR title: a conventional-commit style summary, e.g. `fix: bugs found in game 037`.
- PR description: use `.github/pull_request_template.md`. The change log is the important part:
  - One entry per change: **what** changed, its **type**, **Before:** the old behaviour and **Now:** the new
    behaviour, each in one or two plain sentences a player understands (no code names needed).
  - Type is one of `crash` (runtime error), `mechanic` (how an ability/item is used: targeting, cast rules,
    values from game data), `behaviour` (a decision: fight, retreat, push, farm, which target or ally),
    `cleanup` (no in-game effect).
  - Objects with the same issue may share a group heading (e.g. "Crashes: stolen-spell handles"), but every
    hero / object in the group still gets its own sub-bullet with its own Before/Now. Never write a bare list
    like "Tusk, Grimstroke, Ogre Magi" without saying what changed for each.
  - List what was looked at and skipped on purpose, with the reason, and the `[SHy-*]` lines to check in game.
- CI must be green before merging (see Checks).

## Commits

- Conventional messages: `fix(scope): ...`, `feat(scope): ...`, `refactor: ...`, `style: ...`, `ci: ...`,
  `docs: ...`, `chore: ...`. The body says what was wrong, what changed, and which `[SHy-*]` log shows it.
- **No manual version bump.** The git hooks (see pre-commit hooks) run `tools/build-info.js` after every checkout,
  commit, merge and rebase; it writes the git-ignored `bots/customize/build_info.lua`, and the game prints
  `[SHy-BUILD] version=<commit date>-<sha>[+dirty] commit= branch= dirty=` at the start of every game, so each
  log names the exact build. `bots/customize/version.lua`'s `number` is only the fallback for Workshop installs
  (no git): bump it, and `bots/lib/systems/version.lua` (`"0.7.41 - YYYY/MM/DD"`), only for a Workshop release.
- **Never commit test lineups** in `bots/customize/general.lua` (forced picks, unbans, `Weak_Hero_Cap` debug values).
  Only commit real setting changes there, staged on their own.

## Checks (CI blocks on all of them)

`.github/workflows/lua-check.yml` runs on pushes to `main`, `release-*`, `fix/**`, `feat/**`, `chore/**`,
`docs/**` and on every PR:

1. **Syntax** - every tracked `.lua` compiled with LuaJIT (the game's Lua, so `goto` is fine).
2. **Lint** - `luacheck` with `.luacheckrc`. Globals, unused locals, unused values, shadowing and empty
   `if` branches are ignored. Unreachable code still fails the check. Write `x < y` not `not (x >= y)`,
   never `not a == b` (it means `(not a) == b`).
3. **Format** - `stylua --check .` (StyLua 2.6.0, `stylua.toml`: LuaJIT, tabs, 120 columns, double quotes).
   The commit hook runs StyLua on the staged Lua. If it changes a file, the commit stops: look at the change,
   stage it, and commit again.
4. **Tests** - `luajit tests/run.lua`: a stub bot API loads every hero file, checks every `require` path,
   team-slot helpers (stub player IDs are deliberately not 1-5) and pure helpers. Add a test when you fix a bug
   a test could have caught. Tests live in `tests/test_*.lua` and get the runner as `local T = ...`
   (`T.test`, `T.xfail`, `T.eq`, `T.near`, `T.ok`, `T.stub`, `T.files`, `T.read`); `luajit tests/run.lua <word>`
   runs matching files. An API call the stub doesn't cover fails with `stub missing: <name>`: add it to
   `tests/stub_api.lua`. A real bug that isn't fixed in the same PR stays as `T.xfail(name, reason, fn)` plus an
   issue; an XPASS means it got fixed, so remove the xfail.

**Do not run CI on this machine** (maintainer, 2026-11-26). While developing, do not run `luajit`,
`tests/run.lua`, `luacheck`, a syntax compile, or the GitHub workflow, and do not install LuaJIT or the other CI
tools to reproduce it. The commit hook still formats the staged Lua. Push, wait for the GitHub Actions run, and
read the result. Fix a red check with a new commit. Look at that result before merging.

**pre-commit hooks.** Once per clone: `pip install pre-commit` then `pre-commit install --install-hooks`
(`.pre-commit-config.yaml`; installs the commit hooks and the post-checkout/commit/merge/rewrite hooks that
write `bots/customize/build_info.lua`). Keep `.pre-commit-config.yaml` staged when you edit it (an unstaged config
makes the post-* hooks fail). On every commit:
- `no-commit-to-branch`: commits directly on `main` are refused. Work on a branch and open a PR.
- `check-added-large-files`: a new file over 500 KB is refused (match logs, dumps, binaries).
- `stylua-github`: StyLua 2.6.0 formats the staged `.lua` files. If it changed anything the commit stops:
  check the changes, `git add` them and commit again. `pre-commit run --all-files`
formats the whole repo. A branch without `.pre-commit-config.yaml` (older branches cut before it was added)
needs `PRE_COMMIT_ALLOW_NO_CONFIG=1` to commit.

## Code conventions

- Readable names. Hero files: `X` (the returned table), `bot`, `Fu` (func_utils), `AbilityContext`, `Minion`,
  `<spell>Ability`, `<spell>Desire` / `<spell>Target` / `<spell>Location`, `hpRatio`, `nearbyEnemies`, ...
  Short names only for loop counters (`i`, `j`), unused values (`_`) and coordinates.
- Locals only. A helper used before its definition goes on the module table (`X.Helper`) or is forward-declared;
  never add a global (several heroes once shared a global `HasBlink` / `CanBKB` and ran each other's copy).
- `GetTeamMember(i)` takes a team **slot** 1..5, not a player ID from `GetTeamPlayers()`.
- Guard handles that may be nil (stolen spells, optional items) before calling methods on them.
- **Per-frame answers** (#52, #251): `Fu.GetNearbyHeroes` checks a hero (valid, not our Meepo clone) once per frame
  (one `GameTime()` value; `bots/lib/systems/frame_cache.lua`, which spot-checks 1 kept answer in 64 and prints
  `[SHy-FRAMECACHE]`), and `Fu.IsModeTurbo` / `Utils.IsModeTurbo` scan the allied units once per frame. The
  nearby-hero lists themselves are asked from the engine on every call: reusing them was measured slower (games 083
  and 084). A cache for anything a cast decision reads may not outlive the frame. In a test, a hero whose state
  changes is seen once `Stub.time` moves too (a frame is `1 / 30`).
- **A performance change is measured in a game** (maintainer, 2026-11-25: "the lua may call fewer API but overall
  CPU usage (API engine vs Lua) should be measured"). Fewer engine calls are not proof, and neither are two games,
  one before and one after: two games of one build differ by 7% to 12% in script time (#153). Put the change behind
  a switch and run it against the old code on neighbouring frames of one game with the A/B harness of #251
  (`bots/lib/systems/perf_ab.lua`, taken out when #252 merged: `git fetch origin pull/252/head` then
  `git show 4865f1e8:bots/lib/systems/perf_ab.lua`, its hooks in `perf.lua` in the same commit): `[SHy-AB]` prints
  each variant's script time per frame, its difference from the old code and the standard error of that
  difference. The `off` variant must be the old code with one test in front of it, and a build that still has the
  switch is not merged.
- Bot chat stays short (maintainer, 2026-11-23): a line that narrates a decision ("Going for X", "Pushing top",
  "Defend mid", lotus / shrine) goes through `ChatRules.SayDecision` (`bots/lib/systems/chat_rules.lua`), which says
  it only while the team's `!chatty` chat mode is on. There is no `!debug` command (maintainer, 2026-11-24: "we
  have logger anyway"): technical output goes to `[SHy-*]` log lines, not chat. Plain `ActionImmediate_Chat` is for
  the welcome, the position line, replies to commands and human chat, and kill / gg banter.
- **Dota facts come from game data, not memory**: ability values, target types, radii and item data from the
  installed game files (`scripts/npc` inside the VPKs) or the Valve datafeed
  (`https://www.dota2.com/datafeed/herodata?language=english&hero_id=N`). Cite the source in a comment when it
  drives a number.
- The bot API differs from online docs; see `docs/BOT_API_RUNTIME.md` (e.g. no vector-targeted cast order).
- **Known limitations** (what bots can't do because the API or engine doesn't allow it) are listed in the main post
  of [discussion #50](https://github.com/anggara-ts/Supercharged-OpenHyperAI/discussions/50). When a game, test or source
  confirms a new limitation, disproves one, or a workaround is found, **edit the main post** (not only a reply):
  move the item between "Confirmed" and "Not confirmed yet", with the evidence (log line, test, Valve source) and
  the related issue. `gh_personal api graphql` with `updateDiscussion` edits it. The post is public: write it for readers outside the project, with no internal test-game numbers ("game 043") or match-log names; describe the evidence itself (the log line, the test, the game file). Record API facts in
  `docs/BOT_API_RUNTIME.md` too.

## Logging

- Diagnostic lines use `print(string.format("[SHy-<TAG>] t=%.0f <hero> <what> key=value ...", DotaTime(), ...))`.
  (The prefix was OHA until #221; the tools read both, so old logs, tracker items and PR texts still match.)
  Always include `t=` (game seconds) and the hero name.
- Throttle: at most once per few seconds per bot, or only when the decision changes. A line printed every think
  is a bug (it floods the console and costs FPS).
- Add a log to every new or uncertain behaviour so the next game proves it works. Remove or mute logs for
  features that are proven to work (`OHA_MUTED` in `bots/lib/systems/global_overrides.lua`).
- "Proven to work" means the game showed the **effect** (the right target, the HP saved, the rune taken), not only
  that the line prints. A line that only proves a rule fires stays until its effect is measured. Mute for noise
  (hundreds of lines per game), not as a reward for passing. Game 043: the kiting log had been muted because it
  fired, and nobody could tell whether kiting helped (#72).

## Testing in a game

1. The game runs a copy of the build in `dota 2 beta/game/dota/scripts/vscripts/bots`, made by
   `node tools/export-bots.js --test-game` (`/prepare-game` runs it): the bot scripts of `HEAD`, the uncommitted
   test lineup, a `bots/customize/build_info.lua` for that commit and `LICENSE`, nothing else. Editing or switching branches in
   the clone during a game changes nothing in it; run the export again after a change. (An old dev setup links
   `vscripts/bots` to the clone; the tool refuses to write through a link, so rename it, e.g. `bots-dev`.)
   Start a Custom Lobby, server **Local Host**, bots set to **Local Dev Script** (Valve
   only offers bot scripts in lobbies, and third-party scripts only load on a Local Host server).
2. Launch Dota with `-condebug` so the console is written to `game/dota/console*.log`.
3. The game prints `[SHy-BUILD]` (exact commit) at the start. After the game, `node tools/after-game.js` splits
   the console (`tools/split-console.js`) and writes the review skeleton (see Reviewing a game).
   `local/match-logs/` is git-ignored: the logs contain the host's Steam account ID and server IPs, never commit
   or publish them.

## Issue -> PR -> game test -> merge (the regular workflow)

Tools: `gh_personal` (GitHub CLI as the anggara-ts login), `tools/issue-prs.js`, `tools/verify.js`, `tools/test-build.js`,
`tools/after-game.js`, `tools/build-info.js`. Claude Code skills in `.claude/skills/` run each step
(see Skills below).

1. **Issues.** Every bug, finding or request is a GitHub issue. Group findings that share a cause or an area into
   one card (e.g. "Meepo: Poof and retreat", "Rubick stolen spells: leftover globals"), so a card is one focused
   fix. Each problem in a card is a **task item** `- [ ] (game NNN, m:ss) ...`; a new finding for an existing card
   is a new task item there, not a new card. Labels: `bug`, `enhancement`, `needs-confirmation` (seen once,
   verify next game), `design` (needs a decision), `game-review` (came from watching a game), `chore`; `no-pr`
   skips step 2.
   **Priority:** every issue gets exactly one priority label when it is filed, and its PRs carry the same label
   (`tools/issue-prs.js` copies it and lists untriaged issues):
   - `P1 critical`: a crash or script error, or a team-wide misplay that loses games (seen in most games).
   - `P2 high`: a frequent wrong decision in a common situation (all heroes), or a hero kit badly broken
     (several times per game).
   - `P3 medium`: a hero-specific misplay or a missed optimisation.
   - `P4 low`: polish, cosmetic, chat, nice-to-have.
   - `icebox` (instead of a priority): a parked idea, not scheduled. No priority label, not picked up by
     `/goodnight` or the lineup, until the maintainer moves it out.
   Work and test in priority order (P1 first; the test lineup favours the higher priority when slots are
   short). Re-check the priorities at every game review: raise an issue that keeps showing up, lower one
   that turned out rare.
2. **Start work (WIP) on an issue.** Filing an issue opens no PR. When work on it starts,
   `node tools/issue-prs.js <N> [<N> ...]` (or the `wip` label) creates the branch
   `<fix|feat|docs|chore>/issue-<N>-<slug>` from `origin/main`, one signed empty commit and a draft PR with the
   template and **`Refs #N`** (never `Closes #N`: merging a PR must not close the issue). Run without numbers it
   only copies each issue's priority label to its PRs and lists untriaged issues. It runs locally, not as a GitHub
   Action, because commits must be signed with the maintainer's key.
3. **Work on the PR branch, in its own worktree** (maintainer, 2026-11-26). Edit an issue's code only in
   `.worktree/oha-issue-<N>` inside this clone. That folder is gitignored. Never edit it in the main clone, and
   never on another issue's checkout: the main clone stays on `test/next` with the uncommitted lineup.
   `node tools/issue-prs.js <N>` creates the branch without switching the checkout. Then
   `git worktree add .worktree/oha-issue-<N> <branch>` and do the edits there. One issue card, one worktree.
   Before the first real commit, merge `origin/main` into it if `main` moved (a branch
   from before #221: `--migrate-branch`, see Branches and pull requests). Commit
   (signed, pre-commit hooks), push, keep CI green, and fill the PR description in the change-log format
   (see Branches and pull requests). Mark the PR ready for review when the code is done.
4. **Track what is not tested in a game yet.** `node tools/verify.js add <pr>` imports the PR's
   "How to verify in game" list into `local/verify/tracker.json` (git-ignored). Every PR with game-visible
   changes goes there until a game proves it. Make items machine-checkable where possible: end the bullet with
   `<!-- expect: seen>=1; allyDist<=500 -->` (rules: `seen>=N`, `absent`, `key<=X` / `>=` / `==` / `!=` / `<`
   / `>` on `key=value` fields; give such an item one tagged pattern) and/or `<!-- heroes: lion,mirana -->`, or
   set them later with `node tools/verify.js expect <pr> <item> "<rules>"` / `heroes <pr> <item> a,b`.
5. **Set the test lineup** (local only, `bots/customize/general.lua`, never committed). `node tools/verify.js lineup`
   shows each slot as keep (still testing a PR) or can free; `lineup --suggest [--write]` puts the heroes that
   pending items need into **free** slots (`"Random"`, unset, or can free) at the hero's best free position by
   pick rate (`local/role-weights/rows.json`), tagged `"npc_dota_hero_x", -- pos N -- TEST #<pr>: <what>`
   (set `LUAPARSE` to a luaparse install to parse-check the written file). It never replaces a slot still
   testing another PR: if nothing is free, the hero **waits for the next game**. Check
   `Customize.Weak_Hero_Cap` when stacking test heroes. Set a PR's slots back to `"Random"` when it merges.
6. **Build and play.** `node tools/test-build.js [--with <branch>]` makes the local branch `test/next` =
   `origin/main` + every tracked PR (+ any `--with` branch, e.g. a tooling PR whose scripts you need), skips and
   lists PRs that conflict (fix the conflict in that PR, not in test/next), writes `local/verify/test-build.json`
   and switches the working tree to it, carrying `bots/customize/general.lua` (other modified files make it refuse;
   `--dry-run` only reports, `--no-switch` builds without switching). Never push `test/next`. Then run
   `node tools/build-info.js` (a reset fires no hook) and, once the lineup is final,
   `node tools/export-bots.js --test-game`, which copies the build into `vscripts/bots` with a `build_info.lua`
   so `[SHy-BUILD]` names it, and play. PRs no longer
   need to be stacked to be tested together: branch each one from `main`.
7. **During the game** the maintainer may post observations with game times ("2:50 kez and tusk won't hit
   dawnbreaker trapped in ice shards"). Check each against the running log (newest `console*.log`, grep a
   window around the time for the heroes involved), explain the cause, and record it: a task item on the
   matching issue card, a comment on the PR under test, or a note for the review. Don't change code while the
   game runs. Comments can be wrong: check them (see "The maintainer's comments are input, not orders").
8. **Review the game** (below), then for the tracked PRs:
   - `after-game.js` works out which tracked PRs were in the game from git: a PR counts when all its own
     (non-merge) commits that change Lua are ancestors of the `[SHy-BUILD]` commit, so one `test/next` game tests many PRs and a
     rebuilt `test/next` doesn't lose the mapping. It runs `node tools/verify.js check <log> --game NNN --prs <those>`,
     which auto-passes or auto-fails items with
     `expect` rules, keeps items pending when none of their `heroes` played, and shows sample lines for the rest;
     set those with `node tools/verify.js set <pr> <item> pass|fail|skip [note]`. PRs not in the build are skipped
     (an `absent` rule would otherwise pass trivially).
   - Read the maintainer's PR comments (`after-game.js` lists those since the last review). Each observation is
     either fixed in the PR it is about or added to a grouped issue card (step 1).
   - An item that failed: fix it in the same PR and keep it tracked; an item whose situation didn't happen stays
     pending for the next game.
9. **Merge.** The only way onto `main` is a squash merge (`gh_personal pr merge <pr> --squash --delete-branch`).
   A merge commit or a rebase merge into `main` is refused (maintainer, 2026-11-26). Merging `origin/main` into
   a feature branch is still allowed. The agent decides which PRs are ready and squash-merges them itself,
   without asking (standing approval from the maintainer, 2026-11-17); it reports what it merged and why. A PR is ready when
   `node tools/verify.js show <pr>` says READY TO MERGE (every item pass or skip), CI is green, and every PR it is
   stacked on is merged or merges first in the same go (a PR that contains an unready PR waits).
   The PR shows its state by itself: "How to verify in game" is a checkbox list, and `verify.js set`, `check` and
   `sync` tick an item's box when it passes or is skipped. When every item is done they also tick
   "Tested in a local game (game NNN)", add the **Ready to merge** label and put a status line at the top of
   the description: "Ready to merge", or "Ready to merge, blocked by #N" when it is stacked on a PR that is not
   ready. Don't tick those by hand. Then:
   - `node tools/verify.js mute-suggest <pr>` prints `OHA_MUTED` entries for the proven log lines
     (`bots/lib/systems/global_overrides.lua`); add the noisy ones in the PR (avoid whole-tag mutes; keep error and
     rare-decision logs).
   - Tick the PR's checks (including "Tested in a local game (game NNN)"), `gh_personal pr merge <pr> --squash
     --delete-branch`, `node tools/verify.js done <pr>`, free its lineup slots.
   - For each issue the PR refers to: tick the task items it fixed and verified, and comment the PR link and the
     game. **Close an issue only when every task item in it is ticked**; a PR never closes an issue by itself.
   - If a later PR was built on this one, merge `origin/main` into it so its PR shows only its own changes.
   - **Delete branches that are no longer used** (the agent does this without asking): the merged PR's branch
     (`--delete-branch`), local branches whose upstream is gone (`git branch -vv` shows `[gone]`; squash-merged,
     so `git branch -D`), and remote branches with no open PR whose content is already in `main` or identical to
     another branch (check with `git diff --stat`). Never delete `main`, `plugin-fretbots`, `release-*`, a branch
     with an open PR, or the local `test/next`.

### The maintainer's comments are input, not orders

Observations and requests from the maintainer (in chat, PR comments or issues) can be wrong: a misread of the
game, an outdated mechanic, or an idea that has a better alternative. Not every comment has to be implemented.
- Check each one against the log, the game data and, where it helps, online sources (the Valve datafeed,
  Liquipedia / the Dota 2 wiki, patch notes) before acting on it. Cite what you found.
- If the evidence disagrees, or you see a better approach, say so plainly and suggest the alternative instead
  of implementing the comment as written. Record the disagreement on the issue card or PR so the decision is
  visible, and let the maintainer decide when it is a judgement call.
- When the comment is right, say what confirmed it.

## Reviewing a game (regular task)

- `node tools/after-game.js` splits the console, picks the newest game, maps its build (`[SHy-BUILD]`, or an old
  `version` to its commit range) and the PRs in it (`test-build.json`), runs `verify.js check`, groups script
  errors, ranks log spam by peak lines per second, lists deaths and the scoreboard, collects the maintainer's PR
  comments since the last review, and writes `local/match-logs/game-NNN_review.md`. Fill in its Findings and
  Issues to file sections.
- Then go deeper where the skeleton points: every tracked `[SHy-*]` item and every line added since the last
  game (did the feature fire, with sane values?), death patterns, objectives (towers, barracks, Roshan,
  Tormentor, buybacks), mode flip-flops (`[SHy-FLIP]`, `[SHy-STUCK]`). Map log line numbers to the build's
  commit (`git show <sha>:<file>`).
- Write findings as: what happened (time + log line) / why it matters / code location / suggested fix /
  confidence. File them as task items on grouped issue cards (step 1); PRs are opened when work on a card starts
  (step 2). A single `fix/game-NNN` PR is fine for many small fixes from one review.

## Skills (Claude Code)

`.claude/skills/` holds step-by-step playbooks for the steps above; `AGENTS.md` stays the source of the rules.

| Skill | When |
|---|---|
| `/start-issue` | file findings or requests as grouped issue cards with task items and a priority |
| `/create-pr` | code done: checks, signed commit, CI, change-log description, tracker entry |
| `/prepare-game` | before playing: tracker status, `test-build.js`, lineup, copy into `vscripts/bots`, what the game tests |
| `/prepare-workshop` | a Workshop upload: clean copy of `origin/main` or a release tag (no lineup, git, env, tests, logs) in `vscripts/bots` |
| `/check-live-event` | the maintainer reports an event during a live game |
| `/review-game` | the game ended: `after-game.js`, tracker, PR comments, findings, issues, next lineup |
| `/merge-pr` | a PR is READY TO MERGE: mute proven logs, tick checks, squash-merge, tick issue items |
| `/goodnight` | the maintainer is away: fix every open, unresolved issue in priority order, one ready PR each, build the next game |
| `/patch-update` | Valve shipped a Dota patch: triage the notes, refresh game data, items, abilities, builds, map, API dump, test game, release |
| `/release` | a release: next version, release notes from the PRs merged since the last tag (dry run by default), then version files, tag and GitHub release on "publish" |

## Working notes for AI agents

Project knowledge belongs in this repo (this file, `docs/`, `.claude/skills/`), not in an agent's local memory
(maintainer, 2026-11-22): when a session learns a rule, a fact or a working preference, write it here in the PR it
came with (or a small `docs/` PR).

- **Reporting.** End every summary to the maintainer with the test-game readiness as the last sentence ("Ready
  for a test game: `vscripts/bots` = export of test/next <sha>" or "Not ready yet: waiting for X"); the maintainer
  reads the end first. The ready sentence also says where to sit (maintainer, 2026-11-27): spectating, or which
  team, lobby slot and position to play, with the reason (a tracked item that needs a human, such as a chat
  command or a human on Dire) and which lineup hero the seat leaves out. Pick the seat that leaves out the
  lineup hero whose pending items matter least. Record every decision the maintainer makes on the issue card or PR it is about (a comment
  that quotes it), so later sessions and agents see it.
- **GitHub account.** Every GitHub call in this repo uses `gh_personal` (the anggara-ts login). The tools
  (`tools/github_cli.js`) pick `gh_personal` when it is on PATH, and `gh` only when that wrapper is missing.
  `GH` names another binary only in that fallback (maintainer, 2026-11-26).
- **Commits** are authored as the maintainer's GitHub account `anggara-ts` with its GitHub no-reply e-mail
  (`10489830+anggara-ts@users.noreply.github.com`), set in the repo-local git config; check `git config user.name`
  in a fresh clone or worktree.
- **Game facts.** Besides the hero datafeed, `.../datafeed/itemdata?language=english&item_id=N` (costs, values; no
  component list: use cost arithmetic for recipes) and `.../datafeed/itemlist?language=english` (item ids). Herodata
  enum fields: `damage` 2 = magical, 4 = pure; `immunity` 3 = pierces debuff immunity, 4 = does not; `dispellable`
  3 = not dispellable. When the data can't settle a point, say it is unverified.
- **Parallel agents** (used by `/goodnight` and fix rounds): one issue per agent, each in
  `.worktree/oha-issue-<N>` (step 3), branched from `origin/main`, never in the main clone (it stays on
  `test/next` with the uncommitted lineup). Give
  every agent one shared brief file (these rules, the latest game's log and review, which files another agent owns)
  and name only its issue in the prompt. Run waves of a few agents, highest priority first; an agent stopped by a
  usage limit keeps its worktree and is resumed, not restarted. Check each result yourself (CI, diff against the
  asked scope, tracker) before reporting it; say plainly when a PR covers less than asked.
- **Parallel game reviewers** are read-only: they return `node tools/verify.js set <pr> <item> <verdict> "<note>"`
  lines and findings, and the lead applies them one by one (the tracker file and the PR descriptions are not safe
  for concurrent writes).
- **Windows / Git Bash quirks** (the maintainer's laptop): `gh_personal` must be on PATH (the GitHub CLI
  itself often is not: `export PATH="$PATH:/c/Program Files/GitHub CLI"`); a doubled backslash in a heredoc or `node -e` string
  arrives as one and apostrophes break `node -e '...'`, so write scripts to files; run `git commit -F - <<'EOF'` as
  its own command; never chain `<check> | tail && git commit` (the chain sees tail's exit code).
- **Local test settings.** The maintainer's uncommitted `bots/customize/general.lua` keeps `Weak_Hero_Cap = 5` while
  testing (shipped default 1): remind the maintainer to set it back when a test series ends.
- **After every Dota patch** run [`/patch-update`](.claude/skills/patch-update/SKILL.md) (sources:
  `docs/PATCH_UPDATE.md`): it diffs the `[SHy-API]` dump. Also check whether outposts and watchers work for bots
  again (since 7.42 they can't: `ability_capture` / `ability_lamp_use` are gone, `[SHy-OUTPOST] capture-off`;
  #111, discussion #50); remind the maintainer to re-implement them when Valve fixes it.

## Things not to do

- Do not commit `bots/customize/general.lua` test lineups, match logs, or anything with the Steam ID.
- Do not upload the clone or a link to it to the Workshop (it has `.git`, `.env`, match logs, the test lineup):
  upload the clean copy from `/prepare-workshop` (`node tools/export-bots.js`).
- Do not commit `.env` or print, log or paste its values (API tokens; template and docs: `.env.example`,
  CONTRIBUTING.md step 6).
- Do not force-push, rewrite published history, or skip signing.
- Do not change a mechanic from memory; check the game data.
- Do not stack branches on unmerged branches; use `test-build.js` to test several PRs together.
- Do not edit an issue's code in the main clone or on another issue's checkout. Use `.worktree/oha-issue-<N>`.
- Do not merge or rebase a pull request into `main`. Squash-merge it (`gh_personal pr merge <pr> --squash`).
- Do not merge a PR with game-visible changes before its tracker items pass in a game.
- Do not close an issue while any of its task items is open; do not write `Closes #N` in a PR.
- Do not push `test/next`, and do not change code while a test game is running.
