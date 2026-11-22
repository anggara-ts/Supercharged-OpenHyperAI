-- Shared bot system: pure rules for which lane a defender takes and when it teleports there (#53). No bot API calls,
-- so they can be tested with game numbers.
local DefendLaneRules = {}

-- How long a defender keeps the lane it picked after it left that lane's defend mode (s).
DefendLaneRules.HOLD_SECONDS = 10
-- Reasons of the other lane that are never capped: a siege group-up, heroes at the Ancient, the last stand, the base
-- floor (bots/lib/systems/defend.lua, bot._defendWhy).
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
--   s.alliesAtRim      our heroes who can take part at the rim (this bot included, allies within 2500)
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

-- Base defence split over the rims (#53, maintainer 2026-11-22: "walking back and forth between pushed top and bottom
-- wouldn't be efficient"; an enemy wave near the high ground is a threat when our creeps are pushed hard). A rim is a
-- lane whose T3 is down (its spot remembered), or "base": the T4s / the Ancient. Map-scale choices, not game data:
--   AT_RIM            enemy creeps this close to the rim are at our high ground: a threat whatever our creeps do
--   WAVE_RADIUS       enemy creeps this close are the rim's wave (HIGH_GROUND_RADIUS)
--   CREEPS_PER_HERO   one defender per this many creeps, +1 for a siege or mega creep
DefendLaneRules.AT_RIM = 1000
DefendLaneRules.CREEPS_PER_HERO = 5
-- Is a rim threatened? s.enemyAtRim (within AT_RIM), s.enemyNear (within WAVE_RADIUS, at-rim ones included),
-- s.alliedNear (our lane creeps within WAVE_RADIUS), s.heroes (enemy heroes seen at the rim), s.ancientHit (base rim
-- only: the Ancient lost HP in the last seconds).
-- s.waveEta / s.waveCreeps / s.waveAllied: the next wave on the lane (enemy creeps at its enemy lane front), its ETA
-- to the rim (WaveEta) and our creeps meeting it there.
-- Returns the reason ("heroes", "wave", "pushed", "ancient-hit", "early") or nil. A wave further out that our creeps hold
-- (as many of ours as of theirs) is no threat.
function DefendLaneRules.RimThreat(s)
	if (s.heroes or 0) > 0 then
		return "heroes"
	end
	if (s.enemyAtRim or 0) >= 2 then
		return "wave"
	end
	local near = s.enemyNear or 0
	if near >= 2 and (s.alliedNear or 0) < near then
		return "pushed"
	end
	if s.ancientHit then
		return "ancient-hit"
	end
	-- #53, game 069 (maintainer: the bots start walking when the creeps reach the T3, too late): the next wave further
	-- down the lane (its enemy lane front) with fewer of our creeps meeting it, within EARLY_HORIZON seconds.
	if
		s.waveEta ~= nil
		and s.waveEta <= DefendLaneRules.EARLY_HORIZON
		and (s.waveCreeps or 0) >= 2
		and (s.waveAllied or 0) < s.waveCreeps
	then
		return "early"
	end
	return nil
end
-- Early start (#53, game 069). Game data (installed scripts/npc/npc_units.txt, read 2026-11-22): lane creeps
-- (melee, ranged, siege, mega) have MovementSpeed 325; item_tpscroll AbilityChannelTime 3.0 (items.txt, 7.42).
-- EARLY_MARGIN (s) and EARLY_HORIZON (s) are choices.
DefendLaneRules.CREEP_SPEED = 325
DefendLaneRules.TP_CHANNEL = 3
DefendLaneRules.EARLY_MARGIN = 3
DefendLaneRules.EARLY_HORIZON = 25
-- Seconds the wave needs to walk distLeft to the rim.
function DefendLaneRules.WaveEta(distLeft)
	return math.max(0, distLeft or 0) / DefendLaneRules.CREEP_SPEED
end
-- Seconds the defender needs: walking, or a TP (channel + walk from the landing building) when one is ready and
-- faster. Returns the time and "walk" or "tp".
function DefendLaneRules.DefenderEta(walkDist, moveSpeed, tpReady, tpWalkDist)
	local speed = math.max(100, moveSpeed or 300)
	local walk = math.max(0, walkDist or 0) / speed
	if tpReady and tpWalkDist ~= nil then
		local tp = DefendLaneRules.TP_CHANNEL + math.max(0, tpWalkDist) / speed
		if tp < walk then
			return tp, "tp"
		end
	end
	return walk, "walk"
end
-- Start for an early rim now? When the defender would reach it with the wave or just after (myEta >= waveEta -
-- EARLY_MARGIN), so it arrives with or before the wave.
function DefendLaneRules.StartEarly(waveEta, myEta)
	return waveEta ~= nil and myEta ~= nil and myEta >= waveEta - DefendLaneRules.EARLY_MARGIN
end
-- Defenders a rim needs: everyone for enemy heroes there (the high-ground fight rules decide fight or fall back), else
-- 1 per CREEPS_PER_HERO creeps (at least 1), +1 for a siege or mega creep, at most 5.
function DefendLaneRules.RimNeed(why, creeps, siege)
	if why == nil then
		return 0
	end
	if why == "heroes" then
		return 5
	end
	local need = math.max(1, math.ceil((creeps or 0) / DefendLaneRules.CREEPS_PER_HERO))
	if siege then
		need = need + 1
	end
	return math.min(5, need)
end
-- Assign defenders to rims.
--   rims     list of { lane = key, why = RimThreat reason or nil, need = RimNeed, alive = RimAlive,
--            heroes = enemy heroes there }
--   bots     list of { id = key, dist = { [lane] = distance to that rim } } (the bots that can defend)
--   previous { [bot id] = lane } from the last assignment
-- Rules: enemy heroes at a rim pull every bot there (the rim with the most heroes). Otherwise a bot keeps its rim while
-- that rim's wave is alive (no walking rim to rim mid-wave), then the nearest free bots fill each rim up to its need,
-- nearest pair first. A bot no rim needs gets nothing (it leaves the defence).
-- Returns { [bot id] = lane }, { [lane] = assigned count } and the map to pass as previous next time (empty after a
-- hero pull: once the heroes leave, the bots are reassigned by need, not kept where the heroes were).
function DefendLaneRules.AssignRims(rims, bots, previous)
	local assign, count = {}, {}
	local byLane = {}
	for _, rim in ipairs(rims) do
		byLane[rim.lane] = rim
		count[rim.lane] = 0
	end
	local heroRim = nil
	for _, rim in ipairs(rims) do
		if rim.why == "heroes" and (heroRim == nil or (rim.heroes or 0) > (heroRim.heroes or 0)) then
			heroRim = rim
		end
	end
	if heroRim ~= nil then
		for _, b in ipairs(bots) do
			assign[b.id] = heroRim.lane
			count[heroRim.lane] = count[heroRim.lane] + 1
		end
		return assign, count, {}
	end
	previous = previous or {}
	local free = {}
	for _, b in ipairs(bots) do
		local lane = previous[b.id]
		local rim = lane ~= nil and byLane[lane] or nil
		if rim ~= nil and rim.alive then
			assign[b.id] = lane
			count[lane] = count[lane] + 1
		else
			free[#free + 1] = b
		end
	end
	while true do
		local bestBot, bestRim, bestDist = nil, nil, math.huge
		for _, rim in ipairs(rims) do
			if (rim.need or 0) > count[rim.lane] then
				for i, b in ipairs(free) do
					local d = b.dist[rim.lane] or math.huge
					if d < bestDist then
						bestBot, bestRim, bestDist = i, rim, d
					end
				end
			end
		end
		if bestBot == nil then
			break
		end
		local b = table.remove(free, bestBot)
		assign[b.id] = bestRim.lane
		count[bestRim.lane] = count[bestRim.lane] + 1
	end
	return assign, count, assign
end
-- Does a rim keep its bots? While it is threatened, and while its wave lives up to RELEASE_SECONDS after the last
-- threat (a wave that our creeps now hold frees its bots after that, instead of keeping them all game).
DefendLaneRules.RELEASE_SECONDS = 5
function DefendLaneRules.RimAlive(why, enemyNear, sinceThreat)
	if why ~= nil then
		return true
	end
	return (enemyNear or 0) >= 1 and (sinceThreat or math.huge) <= DefendLaneRules.RELEASE_SECONDS
end

-- T1 / T2 lane defence: after a lane-back (outnumbered at the tower) the bot stays back LANE_BACK_SECONDS, unless the
-- numbers have been even or better for LANE_EVEN_SECONDS (game 069, 11:12-12:40: Nyx flipped lane-defend / lane-back
-- 13 times at the Dire mid T1, Io 8). Choices, not game data.
--   now        game time
--   even       allies at the tower >= enemy heroes there (or the fight reads as ours) right now
--   backUntil  the hold set by the last lane-back (nil: none)
--   evenSince  when the numbers became even (nil: not even)
-- Returns true while the bot should stay back.
DefendLaneRules.LANE_BACK_SECONDS = 4
DefendLaneRules.LANE_EVEN_SECONDS = 3
function DefendLaneRules.LaneStayBack(now, even, backUntil, evenSince)
	if not even then
		return true
	end
	if backUntil == nil or now >= backUntil then
		return false
	end
	return evenSince == nil or now - evenSince < DefendLaneRules.LANE_EVEN_SECONDS
end

return DefendLaneRules
