-- Pure rules for Alchemist's Berserk Potion (Aghanim's Shard, #184): plain values in, so
-- Tests/test_berserk_potion_rules.lua can check them without the bot API.
-- Game data, 7.42 pak01_dir.vpk scripts/npc/heroes/npc_dota_hero_alchemist.txt (read 2026-11-21) and the Valve
-- datafeed hero_id=73: UNIT_TARGET, AbilityUnitTargetTeam FRIENDLY, AbilityUnitTargetType HERO | BASIC, no
-- AbilityUnitTargetFlags (datafeed flags=0, so nothing excludes himself), SPELL_IMMUNITY_ALLIES_YES (a spell-immune
-- ally can be targeted), cast range 800, cast point 0.2, cooldown 35, mana 75; duration 15, attack_speed 50,
-- move_speed 30 (%), hp_regen 40; "applying a basic dispel" (datafeed description).
local BerserkPotionRules = {}

-- The save rule: an ally below this HP being hit by enemy heroes close to him.
BerserkPotionRules.SAVE_HP = 0.4
-- The dispel rule: the summed severity (FuncLib/systems/dispel.lua) of the listed debuffs a basic dispel removes.
-- 4 = a Rod of Atos root alone (5) or a Bounty Hunter Track (4); a Bristleback goo (2) alone is not worth 75 mana.
BerserkPotionRules.DISPEL_MIN_SCORE = 4
-- The order the rules win in when several allies qualify.
BerserkPotionRules.RANK = { dispel = 3, save = 2, fight = 1 }

-- The reason to throw the potion at one candidate, or nil. c (all optional, false / 0 when unknown):
--   buffed       already has modifier_alchemist_berserk_potion
--   basicScore   severity of the listed basic-dispellable debuffs on him (Dispel.AnalyzeDebuffs)
--   rootSilence  rooted or silenced while neither stunned nor hexed (a stun and a hex need a strong dispel:
--                lion_voodoo / shadow_shaman_voodoo / item_sheepstick are SPELL_DISPELLABLE_YES_STRONG in 7.42)
--   threatened   an enemy hero within 1200 of him, or he was hit by a hero in the last 2 s
--   hp           health ratio 0..1
--   chasers      enemy heroes within 900 of him
--   recentlyHit  hit by an enemy hero in the last 2 s
--   core         position 1-3
--   fighting     attacking an enemy hero within his attack range
function BerserkPotionRules.Why(c)
	if c.buffed then
		return nil
	end
	if ((c.basicScore or 0) >= BerserkPotionRules.DISPEL_MIN_SCORE or c.rootSilence) and c.threatened then
		return "dispel"
	end
	if (c.hp or 1) < BerserkPotionRules.SAVE_HP and (c.chasers or 0) >= 1 and c.recentlyHit then
		return "save"
	end
	if c.fighting and c.core then
		return "fight"
	end
	return nil
end

-- The best candidate: the highest-ranked rule, then the lowest HP. Returns index, why (nil, nil if none).
function BerserkPotionRules.Pick(candidates)
	local bestIndex, bestWhy, bestRank, bestHp = nil, nil, 0, 2
	for i, c in ipairs(candidates) do
		local why = BerserkPotionRules.Why(c)
		if why ~= nil then
			local rank = BerserkPotionRules.RANK[why]
			local hp = c.hp or 1
			if rank > bestRank or (rank == bestRank and hp < bestHp) then
				bestIndex, bestWhy, bestRank, bestHp = i, why, rank, hp
			end
		end
	end
	return bestIndex, bestWhy
end

-- A refused order starts no cooldown and would repeat every think. The order counts as refused only when the same
-- target was ordered on every think (no gap over ORDER_GAP s) for ORDER_WAIT s in cast range and the cooldown has
-- still not started. A gap (he died, the reason ended, another spell took the think) starts the count again.
BerserkPotionRules.ORDER_GAP = 1
BerserkPotionRules.ORDER_WAIT = 3

-- One order think. order: the record from the last think (or nil); name: the target; now: game time; inRange: the
-- target is within cast range; cooldownReady: the potion has not been thrown. Returns the new record, refused.
function BerserkPotionRules.OrderStep(order, name, now, inRange, cooldownReady)
	if order == nil or order.name ~= name or now - order.last > BerserkPotionRules.ORDER_GAP then
		order = { name = name, last = now, inRangeAt = nil }
	end
	order.last = now
	if not inRange then
		order.inRangeAt = nil
		return order, false
	end
	order.inRangeAt = order.inRangeAt or now
	if cooldownReady and now - order.inRangeAt >= BerserkPotionRules.ORDER_WAIT then
		return nil, true
	end
	return order, false
end

return BerserkPotionRules
