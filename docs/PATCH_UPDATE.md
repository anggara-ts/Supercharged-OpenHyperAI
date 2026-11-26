# Updating the bots for a new Dota patch

When Valve ships a patch, run the [`/patch-update`](../.claude/skills/patch-update/SKILL.md) skill. It walks through
the triage of the patch notes, the game data, items, abilities, item builds, map coordinates, the bot API dump, a
test game and the release. This page lists the sources it uses and how far to trust each.

Adapted from the upstream OpenHyperAI docs (forest0xia/dota2bot-OpenHyperAI, `docs/PATCH_UPDATE_GUIDE.md`,
[branch `pr-140-refactor`](https://github.com/forest0xia/dota2bot-OpenHyperAI/blob/pr-140-refactor/docs/PATCH_UPDATE_GUIDE.md),
written for 7.41a). Its paths map to ours: `BotsLib/hero_*.lua` is `bots/heroes/`, `FuncLib/` is `bots/lib/`.
Its TypeScript sources and the Buff / Fretbots neutral tables have no counterpart on `main` (the Fretbots plugin is
on the `plugin-fretbots` branch). Its mechanic examples are claims from 7.41, not facts: check each against the
game files.

## Sources, most trusted first

1. **The installed game files.** `dota 2 beta/game/dota/pak01_dir.vpk`, read with any VPK tool:
   `scripts/npc/items.txt`, `scripts/npc/npc_abilities.txt`, `scripts/npc/heroes/npc_dota_hero_<name>.txt`,
   `scripts/npc/npc_heroes.txt`, `scripts/npc/neutral_items.txt`, `scripts/shops.txt`, and the tooltips in
   `resource/localization/abilities_english.txt`. They are what the game runs, on the day of the patch. Our tools
   read them: `tools/item-builds/game-items.js` (`items.txt`) and `tools/skill-builds/gen-fixture.js`
   (`scripts/npc`).
2. **The Valve datafeed** (JSON, `language=english`):
   - `https://www.dota2.com/datafeed/patchnoteslist?language=english`: every patch with its date.
   - `https://www.dota2.com/datafeed/patchnotes?version=<X>&language=english`: the notes of one patch, by item,
     neutral item, hero, ability and talent (ids, not names).
   - `herodata?hero_id=N`, `herolist`, `abilitylist`, `itemdata?item_id=N`, `itemlist`: values and the names for
     the ids. See AGENTS "Game facts" for the enum codes.
3. **Match data: Stratz and Dotabuff.** What players buy and pick on the patch: the item builds
   (`tools/item-builds/`, Stratz API, needs `STRATZ_TOKEN` in `.env`) and the role weights (`tools/role-weights/`,
   Dotabuff). It lags: a new patch needs a full week of games, and Stratz may not know brand-new items for a while.
4. **Online stand-ins**, for when the game files are not at hand. Use them to find a name, then confirm it in 1 or 2:
   - [d2vpkr](https://github.com/dotabuff/d2vpkr) (raw copies of the game files, e.g.
     `https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts/shops.txt`, `.../scripts/npc/items.txt`,
     `.../scripts/npc/neutral_items.txt`, `.../scripts/npc/npc_heroes.txt`). Check its last commit date: it can be
     behind the patch.
   - [Liquipedia](https://liquipedia.net/dota2/) (hero and item pages; the `Cheats` page lists internal names).
     Community-written. It refuses scripted requests (curl gets 403): read it in a browser.
   - Patch-note summaries from anyone (including AI): least trusted. An AI-written list in upstream's 7.41 update
     had wrong innates and wrong ability names (its guide, "Lessons Learned").

The bot API is a separate source: the `[SHy-API]` dump of a real game, recorded in
[`BOT_API_RUNTIME.md`](BOT_API_RUNTIME.md). The online API docs are older than the game.
