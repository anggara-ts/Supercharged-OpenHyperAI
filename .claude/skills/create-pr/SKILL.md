---
name: create-pr
description: Finish work on an OpenHyperAI branch and open or update its PR - checks, signed commit, push, CI, change-log description, and tracker entry. Use when code for an issue or fix is done.
---

# Create or update a PR

Rules: `AGENTS.md` (Branches and pull requests, Commits, Checks, Logging). Checklist:

1. **Branch, in that issue's worktree.** Start the issue with `node tools/issue-prs.js <N>` (branch + draft PR; it
   does not switch the checkout), reuse its existing PR branch, or make a new `<fix|feat|docs|chore>/<topic>`
   from `origin/main`. Edit only in `git worktree add .worktree/oha-issue-<N> <branch>` (AGENTS.md step 3). Never
   in the main clone, and never on another issue's checkout. If `main` moved, `git merge origin/main` first (merge commits are allowed; never
   force-push). A branch from before the layout change of #221 (no `bots/` folder yet): `--migrate-branch` instead
   (AGENTS.md, Branches and pull requests).
2. **Code rules.** Readable names, no new globals, team slots not player IDs, guard nil handles, Dota facts from
   game data. Every new or uncertain behaviour gets a throttled `[SHy-<TAG>] t=%.0f <hero> ...` log.
3. **Checks before committing:**
   - `luajit tests/run.lua` if LuaJIT is available (CI runs it anyway);
   - parse all Lua; StyLua formats on commit (pre-commit hook), re-run `stylua --check` if it changed files;
   - luacheck rules by hand if luacheck isn't installed (CI is the gate).
4. **Commit** with a conventional message (what was wrong, what changed, which log shows it). Commits are
   signed automatically. Never stage `bots/customize/general.lua` (test lineup). The build number is generated
   (`bots/customize/build_info.lua`); don't bump versions by hand.
5. **Push**, then start a background CI wait (`gh pr checks <pr> --watch` with run_in_background, or the GitHub API in a background loop) and continue with the next steps; never block the session polling CI. Fix a red check when the background task reports it; CI must be green before merging.
6. **Description** from `.github/pull_request_template.md`, change-log format: one entry per change with
   type (crash/mechanic/behaviour/cleanup), **Before:** and **Now:** in one or two sentences; group same-issue
   objects but give each hero/object its own sub-bullet. "How to verify in game" lists the `[SHy-*]` lines; add
   `<!-- expect: ...; heroes: ... -->` to a bullet when a machine can check it (see `tools/verify.js`).
   Create with `gh pr create --body-file ...` or update with `gh pr edit <n> --body-file ...`; mark ready with
   `gh pr ready <n>` when the code is done.
7. **Track it:** `node tools/verify.js add <pr>` for anything visible in a game; if it needs specific heroes, run
   `node tools/verify.js lineup --suggest` (and `--write` when slots are free). The game sees a lineup change
   only after the export (skill `prepare-game` step 4).
