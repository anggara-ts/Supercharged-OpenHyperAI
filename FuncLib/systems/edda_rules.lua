-- Pure rules for Winter Wyvern's Eldwurm's Edda (#47), used by ability_item_usage_generic.lua: plain values in,
-- so Tests/test_edda_rules.lua can check them without the bot API.
--
-- Game data (7.42):
-- - Datafeed hero_id=112, winter_wyvern_eldwurms_edda (innate): "Grants Winter Wyvern the item Eldwurm's Edda, which
--   can be consumed to increase the current and maximum level of a basic ability by one and Winter Wyvern's base
--   intelligence by 25% of its current value at the time of consumption." KV tooltip_seconds 420 ("purely for
--   tooltips on variant selection", scripts/npc/heroes/npc_dota_hero_winter_wyvern.txt); Warlock's Black Grimoire
--   uses the same KV for "STARTING COOLDOWN" and its item "Starts on cooldown".
-- - scripts/npc/items.txt item_eldwurms_edda: AbilityBehavior PASSIVE | UNSWAPPABLE, AbilityCooldown 600,
--   ItemCanBeConsumed 1, SpeciallyAllowedInNeutralSlot 1, AllowedInBackpack 0, ItemSellable 0, intellect_pct 25.
-- - abilities_english.txt: "When consumed, increases Winter Wyvern's base intelligence by 25% of its current value
--   at the time of consumption, and increases the current and maximum level of a basic ability by one. All values
--   except for Mana Cost scale by 50% of the difference between their existing levels for the additional level".
-- The in-game consume offers a choice of the basic ability. The bot API has no order for such a choice
-- (Docs/BOT_API_RUNTIME.md), so the first consume is a probe: [OHA-ITEM] edda-result shows what the engine did.
local EddaRules = {}

EddaRules.ITEM = "item_eldwurms_edda"
-- Retry a consume that left the item in place only this often, at most this many times: the order may be a no-op
-- for a passive item, and a retry replaces her current action.
EddaRules.RETRY_GAP = 60
EddaRules.MAX_TRIES = 4
-- The probe reads the result this long after the order (the last read also shows a choice call made at +1s/+5s).
EddaRules.RESULT_AFTER = { 1, 5, 10 }

-- Her basic abilities, in the order the log prints them. The one to take the extra level, if the bot could choose:
-- Splinter Blast, the ability the skill build maxes first (BotsLib/hero_winter_wyvern.lua build 1,2,2,3,2,6,2: 4/4
-- by hero level 7, before the Edda's cooldown ends), her main nuke and slow, so the consume gives it a level 5 at once.
EddaRules.BASIC_ABILITIES = {
	"winter_wyvern_arctic_burn",
	"winter_wyvern_splinter_blast",
	"winter_wyvern_cold_embrace",
}
EddaRules.KEY_ABILITY = "winter_wyvern_splinter_blast"

-- Items a hero's innate puts in the neutral slot. They are not neutral items: logs that count neutral items skip them.
local INNATE_SLOT_ITEMS = {
	item_eldwurms_edda = true,
	item_grisgris = true,
}
function EddaRules.IsInnateSlotItem(name)
	return INNATE_SLOT_ITEMS[name] == true
end

-- Why to consume now, or nil and the reason to wait.
-- s: { cooldown = seconds left on the item, tries = consume orders sent so far, sinceTry = seconds since the last
-- order (nil before the first), canAct = alive and not muted/stunned/hexed/channelling, inDanger = hit by a hero
-- just now }.
-- Consumed as soon as the item is off cooldown: the level is worth most early (a level-5 Splinter Blast for the rest
-- of the game), and the int part only grows by 25% of 3.6 int per hero level she waits (datafeed int_gain 3.6).
function EddaRules.ConsumeWhy(s)
	if not s.canAct then
		return nil, "cannot-act"
	end
	if (s.cooldown or 0) > 0 then
		return nil, "cooldown"
	end
	if (s.tries or 0) >= EddaRules.MAX_TRIES then
		return nil, "gave-up"
	end
	if s.sinceTry ~= nil and s.sinceTry < EddaRules.RETRY_GAP then
		return nil, "retry-gap"
	end
	if s.inDanger then
		return nil, "danger"
	end
	return (s.tries or 0) == 0 and "ready" or "retry"
end

-- The int the consume adds: 25% of her base int (datafeed: int_base 26, int_gain 3.6 per level).
function EddaRules.BaseInt(heroLevel, intBase, intGain)
	return (intBase or 26) + (intGain or 3.6) * math.max(0, (heroLevel or 1) - 1)
end
function EddaRules.IntBonus(baseInt, pct)
	return (baseInt or 0) * (pct or 25) / 100
end

-- levels: list of { name =, level =, max = } in BASIC_ABILITIES order. "arctic_burn:1/4,splinter_blast:4/4,...".
function EddaRules.LevelsText(levels)
	local parts = {}
	for _, entry in ipairs(levels or {}) do
		parts[#parts + 1] = string.format(
			"%s:%d/%d",
			(string.gsub(entry.name or "?", "^winter_wyvern_", "")),
			entry.level or -1,
			entry.max or -1
		)
	end
	return table.concat(parts, ",")
end

-- What the consume did, from the state before and after:
-- "not-consumed" (the item is still there), "level" (a basic ability gained a level or a max level),
-- "pending" (no level yet but an ability point appeared: the choice may be waiting), "no-level" (item gone, no level).
-- Also the name of the ability that changed, or nil.
function EddaRules.Outcome(before, after)
	if after.itemPresent then
		return "not-consumed", nil
	end
	for i, entry in ipairs(after.levels or {}) do
		local old = (before.levels or {})[i]
		if old ~= nil and ((entry.level or 0) > (old.level or 0) or (entry.max or 0) > (old.max or 0)) then
			return "level", entry.name
		end
	end
	if (after.points or 0) > (before.points or 0) then
		return "pending", nil
	end
	return "no-level", nil
end

-- Whether to try ActionImmediate_LevelAbility once as the answer to the choice: only when the consume went through
-- with no level, and either the consume added an ability point (the call takes that one) or she has no point at all
-- (the call can only answer a hidden choice), so it can not spend a normal skill point out of the build order.
function EddaRules.ShouldTryChoice(after, outcome)
	if outcome == "pending" then
		return true
	end
	return outcome == "no-level" and (after.points or 0) == 0
end

return EddaRules
