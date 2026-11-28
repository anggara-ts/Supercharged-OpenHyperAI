---
name: patch-update
description: Update OpenHyperAI after Valve ships a Dota patch - triage the patch notes, refresh the game data, fix items, abilities, skill and item builds, map coordinates, record API changes from the [SHy-API] dump, then a test game and a release. Use when a new Dota patch (7.xx or a letter patch) is out, or the maintainer says "new patch" or /patch-update.
---

# Patch update

A Dota patch can rename or remove abilities and items, change how a spell is cast, move map objectives and change
the bot API. This skill turns one patch into issue cards, PRs and a tested release. Rules: `AGENTS.md` (Dota facts
from game data, Game facts, After every Dota patch, the regular workflow). Sources and their ranking:
`docs/PATCH_UPDATE.md`.

**Every number comes from the game files or the Valve datafeed.** The upstream guide this skill is adapted from was
written for 7.41a; its examples are claims, not facts. It even contradicts itself: one section says Bloodstone's
active was changed, another that it was removed. The game file settles such a question: the 7.42 `items.txt` gives
`item_bloodstone` an `AbilityBehavior` of `NO_TARGET | IMMEDIATE` and a 30s cooldown, so it has an active.

## 1. Is there a new patch?
- `https://www.dota2.com/datafeed/patchnoteslist?language=english` (JSON): the last `patch_number`. Compare it
  with `Version.number` in `bots/lib/systems/version.lua` (the patch of the last release) and `"patch"` in
  `tools/item-builds/status.json` (the patch of the item builds).
- Major patch (7.43): every step. Letter patch (7.42a): usually numbers and talents; do steps 2-3 and only the
  later steps the triage points to.

## 2. Game files
- Extract from the installed `dota 2 beta/game/dota/pak01_dir.vpk` with any VPK tool (the repo has none):
  `scripts/npc/items.txt`, `scripts/npc/npc_abilities.txt`, `scripts/npc/heroes/npc_dota_hero_*.txt`,
  `scripts/npc/npc_heroes.txt`, `scripts/npc/neutral_items.txt`, `scripts/shops.txt` and
  `resource/localization/abilities_english.txt` (tooltips). Put them under `local/` (git-ignored), one folder per
  patch, and keep the old patch's copy: a diff of the two `items.txt` and hero files is the most reliable change list.

## 3. Triage
- `https://www.dota2.com/datafeed/patchnotes?version=<X>&language=english` (JSON): `general_notes`, `items`,
  `neutral_items`, `heroes` (`hero_id`, `hero_notes`, `talent_notes`, `abilities` with `ability_id` and
  `ability_notes`), `neutral_creeps`. Names for the ids: `datafeed/herolist`, `datafeed/abilitylist` (it has
  `is_innate`) and `datafeed/itemlist` (it has `neutral_item_tier`), each with `?language=english`.
- Sort every note into one of three groups:
  - **Structural** (code changes): renames, new or removed abilities and items, an ability becoming innate or
    learnable, targeting and cast-rule changes, a new or removed active, new heroes, map changes (pits, runes,
    outposts, watchers, shops) and timings (neutral tiers, Roshan, day and night).
  - **Numbers only**: not free here. The code hard-codes many game values with their source in a comment (about
    270 comment lines cite the datafeed or `items.txt`). Grep `bots/` for the changed ability or item and update
    every cited value, and the rule tests (`tests/test_*_rules.lua`) that pin it.
  - **Talents**: `tTalentTreeList` in the hero file weighs the two sides of each tier (`["t10"] = { 0, 10 }`). A
    replaced or moved talent can flip the side we want.
- Patch-note wording can be vague or wrong; the game files decide. File the structural list with `/start-issue` as
  task items on grouped cards (one card per area: items, abilities, map, API). A removed name the code still calls
  is `P1 critical`.

## 4. Items
- `node tools/item-builds/game-items.js <items.txt>` rewrites `tools/item-builds/items.json` and
  `tests/data/item_recipes_742.lua`. `tests/data/item_names_742.lua` (which `tests/test_item_names.lua` checks every
  build against) has no generator in the repo (#115 made it from `items.txt`): regenerate it the same way (`true` =
  a hero can buy it, `false` = neutral, obsolete or not purchasable) or teach `game-items.js` to write it. The file
  names carry `742`: on a major patch rename them together with their readers (`tests/stub_api.lua`, the tests,
  `game-items.js`), or keep the names and say so in the PR.
- **Removed items:** grep `item_<name>` in `bots/` (hero build lists, `Item["sSellList"]` and `sCompositeItems` in
  `bots/lib/systems/item.lua`, `item_strategy.lua`, `bots/lib/data/must_have_items.lua`). Delete them; no
  commented-out copies (AGENTS). CI's `test_item_names.lua` fails on a removed item left in any build.
- **New items:** a build can only carry an item once it has buy and use logic (#105). A new active needs
  `Usage.ConsiderItemDesire["item_<name>"]` in `bots/ability_item_usage_generic.lua`; take the cast type from
  `AbilityBehavior` and `AbilityUnitTargetTeam` in `items.txt`.
- **Changed actives (the audit upstream missed):** list our item rules with
  `grep -o 'ConsiderItemDesire\["item_[^"]*"\]' bots/ability_item_usage_generic.lua | sort -u` and cross them with
  the items the notes and the `items.txt` diff change. Active removed (`PASSIVE`, no cast behaviour): delete the
  rule. Active changed (target, cost, effect): rewrite the rule; never switch it off just because it changed.
- **Neutral items:** the pool and tiers come from `neutral_items.txt` (or `neutral_item_tier` in the item list).
  A new active neutral needs a use rule (pure numbers in `bots/lib/systems/neutral_rules.lua`, tested by
  `tests/test_neutral_items.lua`; the cast in `ConsiderItemDesire`). There is no tier table to update here: the
  `Item.IsNeutralItem` / `GetNeutralItemLevel` helpers in `item.lua` read a `tNeutralItemLevelList` that nothing
  defines (unused). The Fretbots / Buff neutral tables live on the `plugin-fretbots` branch.
- In the first game, `[SHy-API] item <name> cost= parts=` shows what the engine knows. In 7.42 removed items
  still answered with a cost, so a cost is no proof an item can be bought.

## 5. Abilities
- `node tools/skill-builds/gen-fixture.js <folder with scripts/npc> <patch>` rewrites
  `tests/data/hero_abilities.lua`. CI's `tests/test_skill_builds.lua` then fails every hero whose level-up list no
  longer fits (an ability now innate, a new slot, another max level, the ultimate's levels).
- **Renames and removals:** grep the old name in `bots/heroes/hero_<name>.lua`, `bots/lib/data/spell_list.lua`,
  `bots/lib/systems/spell_steal_rules.lua` (Rubick's steal table, `KIND`; check new disables in the patch notes too), `bots/lib/hero/rubick_hero/<hero>.lua` (Rubick's stolen spells), modifier
  lists (`bots/lib/data/buff.lua`) and the spell-name lists in `bots/lib/systems/`. Add removed names to
  `tests/test_removed_abilities.lua`.
- **Innates:** a spell that became innate leaves the learnable slots. Fix `tAllAbilityBuildList` (its numbers are
  positions in `sAbilityList`, which `Fu.Skill.GetAbilityList` reads from the hero's slots), and nil-guard the
  handle and its `Consider` function.
- **Targeting:** look for "now no-target", "can no longer target self", "now an aura", "now point-target" and the
  like, and compare `AbilityBehavior` / `AbilityUnitTargetTeam` in `npc_dota_hero_<name>.txt` with the cast call:
  no target `Action_UseAbility`, unit `Action_UseAbilityOnEntity`, point `Action_UseAbilityOnLocation`. A
  self-target rule changes which units the `Consider` function may return. There is no vector-target order
  (`docs/BOT_API_RUNTIME.md`).
- **A new spell in a slot:** the build list, a `Consider` function and the Rubick file.
- **Unusual skill builds:** Invoker (two build lists), Meepo (the ultimate's levels) and every hero in
  `ULTIMATE_LATE` in `tests/test_skill_builds.lua`: check them by hand against the new fixture.
- New hero: a `bots/heroes/hero_<name>.lua` from a similar hero, plus `bots/lib/data/hero_names.lua`,
  `hero_display_names.lua`, `hero_roles_map.lua`, `spell_list.lua` and the role weights (`tools/role-weights/`).

## 6. Item builds (Stratz)
- Rerun on the **first full week** of the patch. Stratz weeks run Thursday to Wednesday UTC (#246). Move
  `local/item-builds/cache/raw/` away (the cache refuses another week), then
  `node tools/item-builds/generate.js --fetch --week <a day in that week> --patch <X>` (dry run), `--write`, StyLua
  on `bots/heroes`, and `node tools/item-builds/check.js` as the second opinion. `STRATZ_TOKEN` is in `.env`; never
  print it.
- **Stratz may not track brand-new items for a while** (for 7.42 its `gameVersions` still ended at 7.41f, #246).
  The generator prints `N item id(s) in the data are not in the Stratz constants (delete cache/stratz_constants.json
  and run --fetch)`: do that first. If an id stays unknown, or a new item has no purchase rows yet, the data cannot
  place it. Add it by hand as a `require` pin in `tools/item-builds/pins.json` (with the reason; the same decision
  goes into `tests/test_item_builds.lua`), and only once `items.json` knows the item and it has buy and use logic.
- Lists kept under 1,000 matches are listed in `status.json`; name them in the PR. A letter patch that changed no
  items needs no rerun.

## 7. Map
- Where the coordinates live: `Utils.RadiantRoshanLoc` / `DireRoshanLoc`, the fountain TP points and
  `Utils.WisdomRunes` (`bots/lib/systems/utils.lua`); `Fu.CheckTimeOfDay`, `Fu.GetCurrentRoshanLocation`,
  `Fu.GetTormentorLocation` with the Tormentor and wait spots, and the fountains (`bots/lib/general_utils/map_info.lua`,
  fountains also in `bots/ability_item_usage_generic.lua`); `Site.top_power_rune` / `bot_power_rune` / `roshan` and
  the outposts found by unit name (`bots/lib/data/site.lua`); `OUTPOST_FALLBACK` in `bots/mode_outpost_generic.lua`
  (used when the scan finds no outpost unit). Watchers have no coordinates: `bots/mode_watcher_generic.lua` finds the
  `npc_dota_lantern` units.
- "Pit preference switched" (Roshan, Tormentor) means swapping which spot day and night return, not new vectors. A
  new day or night length changes `Fu.CheckTimeOfDay`.
- Check them against the game, not the notes: `GetRuneSpawnLocation` (the `[SHy-RUNE] spots team= b1= b2= p1= p2=`
  line once #190 is merged; until then the `[SHy-RUNE] ... spot rune=` lines), `GetShopLocation`, the Roshan and
  Tormentor units' positions, `[SHy-OUTPOST] scan` and `[SHy-WATCHER] unit-survey`. Put the log line in the comment
  of a coordinate a game confirmed.
- Outposts and watchers: the AGENTS "After every Dota patch" check.

## 8. The `[SHy-API]` dump
- The dump runs once per game (Radiant's first bot). Diff the first game of the new patch against the last game of
  the old one:
  `grep -a "\[SHy-API\]" <game.log> | sed 's/^.*\[SHy-API\]/[SHy-API]/' | sort > api-<patch>.txt`, then `diff`.
- Ringmaster souvenirs (#49): 7.42 grants only set 1 (`ringmaster_dark_carnival_souvenirs` `use_souvenir_set_1` 1,
  `use_souvenir_set_2` 0), so `[SHy-API] abilities ringmaster` lists Funhouse Mirror, Strongman Tonic, Whoopee
  Cushion and Unicycle only. If a patch turns set 2 back on (Weighted Pie and Crystal Ball appear in the dump), the
  cast rules `X.ConsiderWeightedPie` / `X.ConsiderCrystalBall` in `bots/heroes/hero_ringmaster.lua` start working:
  check their `souvenir=` lines in the first game.
  The lines that describe the API (`globals`, `CDOTA_Bot_Script`, `CDOTABaseAbility_BotScript`,
  `CDOTA_TeamCommander`, `bot-handle`, `constants`, `item`, `item-names`, `shrine`) compare across games. Ignore
  `slots <hero>` (the items held at that moment) and the lines with `t=`; compare `abilities <hero>` only for heroes
  who played in both games.
- New or removed functions, methods and constants, and changed constant values, go into `docs/BOT_API_RUNTIME.md`
  as an "<X> check" section like "7.42 check". A changed constant matters where `bots/lib/dota/enums.lua` has a
  fallback value.
- A bot capability gained or lost (outposts, a cast order) goes into the main post of discussion #50 (AGENTS: edit
  the main post, written for outside readers).

## 9. Test game and release
- Every patch PR lists its "How to verify in game" items (`<!-- heroes: ... -->` for the changed heroes). Then
  `/prepare-game`, play, `/review-game`; look at script errors first (a removed name still called).
- When the patch PRs are merged and a game on `main` alone ran clean: `/release` (its "Patch <X>" section,
  `Version.number = "0.<X> - YYYY/MM/DD"`).

## 10. Report
The structural changes with the issue or PR for each, what was left as numbers-only and why, the Stratz week used
(or the day it is due), the API diff, and what is still open. End with the test-game readiness line (AGENTS).
