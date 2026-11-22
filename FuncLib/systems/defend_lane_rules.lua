-- Shared bot system: pure rules for which lane a defender takes and when it teleports there (#53). No bot API calls,
-- so they can be tested with game numbers.
local DefendLaneRules = {}

-- How long a defender keeps the lane it picked after it left that lane's defend mode (s).
DefendLaneRules.HOLD_SECONDS = 10
-- Reasons of the other lane that are never capped: a siege group-up, heroes at the Ancient, the last stand, the base
-- floor (FuncLib/systems/defend.lua, bot._defendWhy).
DefendLaneRules.UNCAPPED = {
	["group-up"] = true,
	["ancient-heroes"] = true,
	["ancient-last-stand"] = true,
	["base-floor"] = true,
}

-- Keep the held lane over another threatened lane? Game 066, 81:41-81:55: Elder Titan defended the bottom high ground
-- (11-21 enemy creeps, 712-998 from his spot); when the base-lane gate let go for a moment, mid (8 creeps) read 0.85
-- against bottom's 0.37 and he took the mid defence, TP'd away and walked back for 34s. The desire alone can't tell:
-- mid's 0.85 came from a different rule than bottom's.
--   held / other: { desire = the lane's final defend desire, creeps = enemy creeps at the lane's threat, heroes = enemy
--                   heroes seen there, hp = HP ratio of the lane's furthest building, tier = its tier }
--   other.why     the other lane's defend reason (UNCAPPED reasons always win)
--   heldAge       seconds since the bot was last in the held lane's defend mode (0 while in it)
-- Returns true (keep the held lane; the other lane is capped below it), false (the other lane may win), and the
-- reason.
function DefendLaneRules.KeepLane(held, other, heldAge)
	if held == nil or other == nil or (held.desire or 0) <= 0.1 then
		return false, "no-held"
	end
	if (heldAge or math.huge) > DefendLaneRules.HOLD_SECONDS then
		return false, "expired"
	end
	if DefendLaneRules.UNCAPPED[other.why or ""] then
		return false, "urgent"
	end
	-- Both lanes end at the T4s or the Ancient (tier 4-5): one base defence, the lane label means nothing and the
	-- defend Think goes to the creeps either way (game 068, 41:40: "Defend mid!" while bottom pushed, both tier 4).
	local heldTier, otherTier = held.tier or 0, other.tier or 0
	if heldTier >= 4 and otherTier >= 4 then
		return true, "same-base"
	end
	if (other.heroes or 0) > (held.heroes or 0) then
		return false, "more-heroes"
	end
	-- Tier 0 = no building read (it just died, game 068 t=2457: bottom read tier 0 and lost to mid's tier 4 with 5
	-- enemy heroes and 10 creeps on bottom). Unknown, not shallower: no tier comparison then.
	if heldTier > 0 and otherTier > heldTier then
		return false, "deeper-tier"
	end
	local heldCreeps, otherCreeps = held.creeps or 0, other.creeps or 0
	if otherCreeps >= heldCreeps + 4 and otherCreeps >= heldCreeps * 1.5 then
		return false, "more-creeps"
	end
	if (other.hp or 1) + 0.25 < (held.hp or 1) then
		return false, "building-low"
	end
	return true, "hold"
end

-- Skip a defend teleport? Game 066, 81:55 and 82:35: Elder Titan TP'd to mid's far end (our own lane front, deep in
-- the enemy half), walked 10,000 back to his high ground in 34s, and TP'd out the same way again: the walk back
-- re-tripped the same condition.
--   now, lastLane, lastAt  the bot's last defend TP (lane and time), if any
--   lane                    the lane of this TP
--   baseThreat              enemy creeps or heroes are at our base (within 4000 of our Ancient)
--   botToAncient            the bot's distance to our Ancient
--   targetToAncient         the TP target's distance to our Ancient
-- Returns the reason ("recent", "away-from-base") or nil.
DefendLaneRules.TP_REPEAT_SECONDS = 20
function DefendLaneRules.DefendTpBlock(now, lastLane, lastAt, lane, baseThreat, botToAncient, targetToAncient)
	if lastLane == lane and lastAt ~= nil and now - lastAt < DefendLaneRules.TP_REPEAT_SECONDS then
		return "recent"
	end
	if baseThreat and targetToAncient > botToAncient + 1500 then
		return "away-from-base"
	end
	return nil
end

-- Lane threat (#53, game 068 41:40): each enemy creep counts once, for one lane. Map-scale choices, not game data:
--   BASE_RADIUS       a creep this close to our Ancient is at the base: every lane path ends there, so it belongs to no
--                     lane (the old ReadBaseThreat radius, defend.lua BASE_CREEP_RADIUS)
--   TOWER_RADIUS      reach of a T1 / T2 (the old lane-front radius)
--   HIGH_GROUND_RADIUS reach of a T3 / barracks / T4: a wave walking up the ramp counts (Utils.HG_WAVE_RADIUS)
DefendLaneRules.BASE_RADIUS = 1400
DefendLaneRules.TOWER_RADIUS = 1600
DefendLaneRules.HIGH_GROUND_RADIUS = 2600
function DefendLaneRules.ThreatRadius(tier)
	return (tier or 0) >= 3 and DefendLaneRules.HIGH_GROUND_RADIUS or DefendLaneRules.TOWER_RADIUS
end
-- The lane of a creep: "base" within BASE_RADIUS of our Ancient, else the lane whose path is nearest.
--   distances   { [lane] = distance from the lane path (GetAmountAlongLane(lane, loc).distance) }
--   lanes       the lane ids in order (ties go to the first)
--   ancientDist the creep's distance to our Ancient (nil: unknown)
function DefendLaneRules.CreepLane(distances, lanes, ancientDist)
	if ancientDist ~= nil and ancientDist <= DefendLaneRules.BASE_RADIUS then
		return "base"
	end
	local best, bestDist = nil, math.huge
	for _, lane in ipairs(lanes) do
		local d = distances[lane]
		if d ~= nil and d < bestDist then
			best, bestDist = lane, d
		end
	end
	return best
end
-- Does a creep of creepLane, anchorDist from the lane's furthest building (tier), count as that lane's threat? Base
-- creeps count for every lane whose furthest building is the T4s or the Ancient.
function DefendLaneRules.CountsForLane(creepLane, lane, tier, anchorDist)
	if creepLane == "base" then
		return (tier or 0) >= 4
	end
	return creepLane == lane and anchorDist ~= nil and anchorDist <= DefendLaneRules.ThreatRadius(tier)
end

-- The high-ground defence (#53, game 068 41:40 and 52:30): once a lane is down to its T3 or deeper, the bots hold the
-- rim (the T3 spot, remembered after the T3 falls) and meet the wave there with our creeps; they fall back to the
-- Ancient only for enemy heroes there, or for an Ancient being hit with no wave to meet.
--   s.heroesAtAncient  enemy heroes seen near our Ancient
--   s.heroesAtRim      enemy heroes seen near the rim
--   s.alliesAtRim      our heroes near the rim (this bot included)
--   s.stronger         Fu.WeAreStronger around the bot
--   s.waveNear         a wave creep within reach of the bot
--   s.wave             wave creeps (near the rim or the Ancient)
--   s.waveSafe         no enemy heroes by the wave creep the bot would walk to, or we can take them
--   s.ancientHit       the Ancient lost HP in the last seconds
-- Returns the step: ancient-heroes, hg-fight, hg-back, hg-near, hg-wave, ancient-hit, hg-spot.
function DefendLaneRules.HighGroundStep(s)
	if (s.heroesAtAncient or 0) > 0 then
		return "ancient-heroes"
	end
	local heroesAtRim = s.heroesAtRim or 0
	if heroesAtRim > 0 then
		if s.stronger or (s.alliesAtRim or 0) >= heroesAtRim + 1 then
			return "hg-fight"
		end
		return "hg-back"
	end
	if (s.wave or 0) > 0 and s.waveSafe then
		return s.waveNear and "hg-near" or "hg-wave"
	end
	if s.ancientHit and (s.wave or 0) == 0 then
		return "ancient-hit"
	end
	return "hg-spot"
end

return DefendLaneRules
