-- Pure rules for hero casts that were never made (#47): plain numbers in, a decision out, so the
-- thresholds can be tested without the bot API. Each hero file reads its numbers from the game and
-- passes them here.
local Rules = {}

-- Chen, Hand of God (heals every allied hero on the map; 7.42 npc_dota_hero_chen.txt heal_amount 200/300/400
-- plus 20/30/40 per second for 10s). It was cast only for cores under 50% HP; supports and Chen himself
-- never counted. A support needs to be lower before the long-cooldown ultimate (150/130/110s) goes on them.
Rules.HAND_OF_GOD_CORE_HP = 0.5
Rules.HAND_OF_GOD_SUPPORT_HP = 0.35
function Rules.HandOfGodHpLimit(isCore)
	if isCore then
		return Rules.HAND_OF_GOD_CORE_HP
	end
	return Rules.HAND_OF_GOD_SUPPORT_HP
end
-- hp: the ally's HP ratio; inDanger: in a team fight, or retreating while chased and hit.
function Rules.HandOfGodWorth(hp, isCore, inDanger)
	return inDanger == true and hp < Rules.HandOfGodHpLimit(isCore)
end

-- Huskar, Berserker's Blood with Aghanim's Shard (7.42 npc_dota_hero_huskar.txt: activation_healthcost_pct 30,
-- activation_cooldown 20, activation_delay 3, activation_heal_pct_per_debuff 3; basic dispel). The cast costs
-- HP now and gives it back 3s later, so it is worth it only to drop a root or a damage-over-time debuff in a
-- fight, and never when the HP cost could leave him at a one-shot.
Rules.CAUTERIZE_MIN_HP = 0.25
function Rules.HuskarCauterize(hp, rooted, damageOverTime, hitByHero, enemiesNear)
	if hp < Rules.CAUTERIZE_MIN_HP or enemiesNear < 1 or not hitByHero then
		return false
	end
	return rooted == true or damageOverTime == true
end

-- Pugna, Life Drain on an ally (7.42 pugna_life_drain: AbilityUnitTargetTeam BOTH; datafeed: "When cast on an
-- ally, Pugna heals his ally and takes magical damage equal to the amount healed. This damage cannot kill
-- Pugna."). Heal a hurt ally who is under attack, while Pugna himself is healthy enough to pay.
Rules.DRAIN_ALLY_HP = 0.4
Rules.DRAIN_SELF_MIN_HP = 0.5
Rules.DRAIN_STOP_ALLY_HP = 0.9
Rules.DRAIN_STOP_SELF_HP = 0.3
function Rules.LifeDrainAllyWorth(allyHp, pugnaHp, allyHit, enemiesNearAlly)
	return allyHp < Rules.DRAIN_ALLY_HP and pugnaHp >= Rules.DRAIN_SELF_MIN_HP and allyHit and enemiesNearAlly >= 1
end
-- Stop an ally drain once the ally is healed or Pugna is low.
function Rules.LifeDrainAllyStop(allyHp, pugnaHp)
	return allyHp >= Rules.DRAIN_STOP_ALLY_HP or pugnaHp < Rules.DRAIN_STOP_SELF_HP
end

-- Tiny, Toss onto an allied hero: the thrown enemy should land among allies, not next to the enemy team.
-- candidates: list of { spotDist = distance from the tossed unit, ok = valid ally }; returns the index of the
-- nearest ally at least minDist from the tossed unit and within the toss cast range of Tiny, or nil.
-- (Toss throws "the nearest unit in a 300 radius around Tiny ... at the target unit"; 7.42 tiny_toss
-- grab_radius 300, cast range 800/900/1000/1100.)
Rules.TOSS_ALLY_MIN_DIST = 400
function Rules.PickTossAlly(candidates, castRange, minDist)
	local best, bestDist = nil, math.huge
	for i, candidate in ipairs(candidates) do
		if
			candidate.ok
			and candidate.spotDist >= minDist
			and candidate.tinyDist <= castRange
			and candidate.spotDist < bestDist
		then
			best, bestDist = i, candidate.spotDist
		end
	end
	return best
end

-- Keeper of the Light, Illuminate in Spirit Form heals allies in its path (datafeed: Spirit Form "allows
-- Illuminate to be channeled by a separate spirit and heal allies"; 7.42 illuminate_heal 60, +40 with Shard).
Rules.SPIRIT_HEAL_ALLY_HP = 0.6
function Rules.SpiritIlluminateHealWorth(allyHp, allyHit, inSpiritForm)
	return inSpiritForm == true and allyHit == true and allyHp < Rules.SPIRIT_HEAL_ALLY_HP
end

-- Phoenix, Icarus Dive Stop. Game data (Valve datafeed hero 110, 7.42): dash_length 1100/1200/1300/1400,
-- dash_width 500, hit_radius 200, dive_duration 2, AbilityCastPoint 0.2; "dives forward in an arc with a fixed
-- distance in the targeted direction ... and then orbiting back to its original position". A dive left alone ends
-- where it started. The far end of the arc should come about half way through (1s), but the path shape is not in
-- the game files, so the rules watch the distances and use the time only as a cap. The arc is dash_width wide, so
-- it can pass up to about 250 beside the aimed spot instead of over it.
-- d: kind ("kill", "engage", "retreat", "stuck"), elapsed (seconds since the dive started), duration
-- (dive_duration), fromStart / fromStartMax (distance from the start now / the most so far), dashLength,
-- targetDist / targetDistMin (to the dive's target now / the least so far; nil without a target), hitRadius,
-- dashWidth. Returns stop (bool) and the reason:
--   kill / engage: "reached" (within hit_radius of the target) or "passed" (came within half the arc width plus
--     hit_radius and is moving away again). No time cap: if the target left the path, the dive finishes and
--     carries Phoenix back to where she started, as before.
--   retreat / stuck: "far-end" (the distance from the start turned back after half the dash) or "half" (half the
--     dive duration, the far end of the arc).
Rules.DIVE_TURN = 40
-- Kill / engage: let the dive touch the target first (the burn lands on contact) before it may stop.
Rules.DIVE_MIN_ELAPSED = 0.1
function Rules.IcarusDiveStop(d)
	if d.elapsed == nil or d.elapsed < 0 then
		return false, nil
	end
	if d.kind == "kill" or d.kind == "engage" then
		if d.targetDist == nil or d.targetDistMin == nil or d.elapsed < Rules.DIVE_MIN_ELAPSED then
			return false, nil
		end
		if d.targetDist <= d.hitRadius then
			return true, "reached"
		end
		if d.targetDistMin <= d.dashWidth / 2 + d.hitRadius and d.targetDist >= d.targetDistMin + Rules.DIVE_TURN then
			return true, "passed"
		end
		return false, nil
	end
	if d.kind == "retreat" or d.kind == "stuck" then
		if d.fromStartMax >= d.dashLength / 2 and d.fromStart <= d.fromStartMax - Rules.DIVE_TURN then
			return true, "far-end"
		end
		if d.elapsed >= d.duration / 2 then
			return true, "half"
		end
	end
	return false, nil
end

return Rules
