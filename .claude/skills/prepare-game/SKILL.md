---
name: prepare-game
description: Get the local OpenHyperAI checkout ready for the next test game - build the test/next integration branch from main plus every tracked PR, set the test lineup, copy the build (with the uncommitted lineup) into Dota's vscripts/bots, and tell the user what the game will test. Use before the user plays, or when asked "what does the next game test".
---

# Prepare the next game

Rules: `AGENTS.md` (workflow steps 4-6). Checklist:

1. **Status:** `node tools/verify.js show` - which PRs are still testing and which items are pending.
2. **Build:** `node tools/test-build.js --dry-run`, then `node tools/test-build.js` (add `--with <branch>` for an
   untracked branch you need, e.g. tooling not yet on main), then `node tools/build-info.js`. It resets the local
   `test/next` branch to `origin/main`, merges every tracked PR branch, reports conflicts (fix those in the PR,
   not in test/next), and switches the working tree to it. Never push `test/next`. The maintainer's uncommitted
   `bots/customize/general.lua` stays as it is.
3. **Lineup:** `node tools/verify.js lineup`, then `lineup --suggest`; apply with `--write` only into free slots
   (Random / unset / "can free"); if none are free, the hero waits for a later game.
4. **Copy the build into Dota** (last, after the lineup is final): `node tools/export-bots.js --test-game`, run in
   the main clone. It copies only the bot scripts of `HEAD` (`test/next`), plus the uncommitted lineup and a
   `bots/customize/build_info.lua` for that commit, into `vscripts/bots`, so `[SHy-BUILD]` names the build and editing
   or switching branches in the clone during the game changes nothing in it. Check its output:
   - `NOT in the copy: ...` lists uncommitted bot scripts, edited or `(new)`, that the game will not run. Commit
     them in their PR and rebuild, or tell the maintainer.
   - `.lua files outside bots/ in a folder the export does not know`: a PR added Lua files outside `bots/` (the
     game only gets `bots/`). Move them under `bots/`, or add a tooling folder to `NOT_RUNTIME_DIRS` in
     `tools/export-bots.js` (in that PR). A PR branch from before the layout change (#221) shows up in
     `test-build.js` as `NEEDS MIGRATION`: run `node tools/restructure.js --migrate-branch` on it (AGENTS.md, Repo map).
   - `is a link`: `vscripts/bots` is still the old dev link to the clone. Ask the maintainer before renaming it
     (e.g. to `bots-dev`); renaming changes what the game loads.
   - `has files this tool did not write`: list them to the maintainer. Use `--force` only after they agree.
   Any later change to the lineup or the build needs this step again before the game.
5. **Tell the user:** branch and build that will run (the `[SHy-BUILD]` version the export printed), the lineup
   table (pos / hero / what it tests), and the log lines to expect. Remind them to launch with `-condebug` in a
   Local Host lobby with Local Dev Script.
   - **A/B measurement:** `git grep -n "PerfAb.Define" HEAD -- bots ":!bots/dev"`. No hit (the usual case): the
     harness is off, say nothing. A hit: a measurement PR is in the build; name its experiment and say that
     `[SHy-AB]` lines print every 5 minutes and that the review posts the last line of every arm on the issue
     (`docs/MEASURING_PERFORMANCE.md`). Nothing has to be switched on.
