---
name: prepare-workshop
description: Put a clean, ready-to-upload copy of the OpenHyperAI bot scripts (origin/main or a release tag, exactly as committed - no lineup, no git, env, tests, tools or logs) into Dota's vscripts/bots for the Steam Workshop uploader. Use when the maintainer wants to publish or update the bot script on the Workshop, or asks for a clean copy.
---

# Prepare a Workshop upload

Tool: `tools/export-bots.js` (`--help`). Rules: `AGENTS.md` (Commits: version files; Things not to do).
The Workshop Tools uploader publishes the contents of `vscripts/bots`, so that folder must hold only the bot
scripts. Never upload the clone or a link to it: it has `.git`, `.env` (API tokens), `local/match-logs/` (the
host's Steam ID and server IPs) and the local test lineup.

1. **Ask first:** is a test game prepared or about to be played? The export replaces what Local Dev Script runs,
   so do this between games and run `/prepare-game` again afterwards.
2. **What to publish:** a release tag (after `/release publish`, so the version files carry the release number
   the Workshop copy shows: it has no `build_info.lua`, `[SHy-BUILD]` prints `commit=release`) or `origin/main`.
   `git fetch origin --tags`, then `node tools/export-bots.js --dry-run [--ref vX.Y]`.
3. **Check the dry run:**
   - the ref and commit are the ones to publish, `left out` lists the non-script folders, no `required files
     missing` error;
   - `is a link`: `vscripts/bots` is the old dev link to the clone. Ask the maintainer before renaming it (e.g. to
     `bots-dev`);
   - `has files this tool did not write`: show them to the maintainer; `--force` (deletes them) only after they
     agree.
   - `is not a clean Workshop copy`: the committed `bots/customize/general.lua` of that ref has test settings (`TEST #N`
     comments, forced picks in `Radiant_Heros` / `Dire_Heros` / `Debug_*_Heros`, `Weak_Hero_Cap` other than 1, a
     `Debug_* = true`). Never edit the copy by hand: put the release defaults back in `general.lua` in a PR, merge,
     and release / export that commit. The local, uncommitted lineup never reaches a Workshop copy (the export
     reads git, not the working tree).
4. **Export:** the same command without `--dry-run`. A copy left by `/prepare-game` is updated in place (the tool
   deletes only files it wrote; the lineup and `build_info.lua` go away).
   After writing, the tool checks that the folder holds exactly the copied files (nothing added or edited, no
   `build_info.lua`) and prints `READY TO UPLOAD: ... version <number> / <patch version>`. Only that line means
   the folder can be uploaded; any error stops it. Show the line to the maintainer.
5. **Optional smoke test:** a Local Host lobby with Local Dev Script; `[SHy-BUILD]` shows `commit=release` and the
   release number, the default lineup drafts.
6. **Upload (the maintainer does it; publishing is outward-facing, never do it yourself):** Dota 2 Workshop Tools →
   Bot Scripting → create a new bot script or pick the existing one → title, description, preview image
   (`workshop/cover.png`, or the smaller `workshop/cover-512.png`, in the repo) → submit. (From Valve's 22 July 2017 patch notes; the menu may have moved since.) The Steam account must not be a
   limited account.
7. **After:** leave the copy, or `node tools/export-bots.js --remove`, then `/prepare-game` before the next test
   game.

Not in the copy on purpose (maintainer's decision, #177): `install/` and docs. The Workshop copy is
the bot scripts plus `LICENSE` (the MIT notice has to ship with every copy, #215; `NOTICE_FILES` in
`tools/export-bots.js`). After an upload, check once that the Workshop item kept `LICENSE` (the uploader may skip
files that are not `.lua`; unverified). Our Workshop item is 3843444501 (https://steamcommunity.com/sharedfiles/filedetails/?id=3843444501): update it,
not a new item.

New Lua files: a committed `.lua` file under `bots/` is in the copy automatically, at the same path below
`vscripts/bots`. A `.lua` file outside `bots/` in a new folder stops the export until it moves under `bots/` or
the folder is added to `NOT_RUNTIME_DIRS` in `tools/export-bots.js`. A release tag from before the layout change
(#221, e.g. v0.4) has no `bots/` folder: the tool says so; export it with that tag's own `Util/export-bots.js` <!-- restructure:keep -->
from a worktree of the tag.
