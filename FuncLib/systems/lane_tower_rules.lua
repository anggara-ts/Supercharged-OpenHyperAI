-- Pure rules for laning next to an enemy tower and for the creep / tower aggro tricks (#71). No API calls: the modes
-- pass plain numbers and booleans, so Tests/ can check them.
local LaneTowerRules = {}

-- Tower attack range. Game data: scripts/npc/npc_units.txt in pak01_dir.vpk (7.42), every lane tower
-- (npc_dota_goodguys_tower1_top ... tower4) has "AttackRange" "700" and "BoundsHullName" "DOTA_HULL_SIZE_TOWER"; the
-- hull size itself is not in the file. Attack range counts edge to edge, so the centre-to-centre reach is 700 + the
-- tower's radius + the target's radius, both read with GetBoundingRadius() at runtime (as push.lua does: game 040
-- printed `[OHA-PUSH] wait-outside-tower range=868` for a hero, so 168 for both radii together).
LaneTowerRules.TOWER_RANGE = 700
-- Inside an enemy tower's range "plus a margin": a step out goes this much past the edge first.
LaneTowerRules.EXIT_MARGIN = 100
-- The exit spot lies this far beyond reach + margin, so the next think starts outside the zone.
LaneTowerRules.EXIT_STEP = 150
-- Staying inside is allowed only while the tower shoots a creep and the bot has at least this much HP...
LaneTowerRules.STAY_HP = 0.7
-- ... and no enemy hero is closer than his own attack range + this (he could hit the bot after a short step).
LaneTowerRules.ENEMY_REACH_PAD = 200
-- Hit inside an enemy tower's range under this HP: retreat beats Valve's evasive mode (game 071, Largo at 58%).
LaneTowerRules.ESCAPE_HP = 0.6
-- Aggro pull: an enemy hero within this distance of the bot is the preferred bait.
LaneTowerRules.BAIT_NEAR = 1000

-- Centre-to-centre distance at which a tower with this attack range reaches a unit (missing values: 700, no radius).
function LaneTowerRules.Reach(range, towerRadius, unitRadius)
	local base = (type(range) == "number" and range > 0) and range or LaneTowerRules.TOWER_RANGE
	return base + (towerRadius or 0) + (unitRadius or 0)
end

-- Is the bot inside the tower's reach plus the exit margin?
function LaneTowerRules.InZone(dist, reach)
	return dist <= reach + LaneTowerRules.EXIT_MARGIN
end

-- A laning bot inside an enemy tower's range (plus the margin) with an enemy hero near: why it steps out, or nil when
-- it may stay. It stays only while the tower shoots a creep, its HP is STAY_HP or more and no enemy hero is within
-- that hero's own attack range + ENEMY_REACH_PAD of it.
--   towerOnMe     the tower's attack target is the bot
--   towerOnCreep  the tower's attack target is a creep
--   hp            the bot's HP ratio
--   reachGap      smallest (distance - enemy hero's attack range) over the enemy heroes near; nil: none near
-- Returns "tower-on-me", "tower-free" (the tower shoots nothing or a hero), "hp", "hero-reach" or nil.
function LaneTowerRules.ExitReason(towerOnMe, towerOnCreep, hp, reachGap)
	if reachGap == nil then
		return nil
	end
	if towerOnMe then
		return "tower-on-me"
	end
	if not towerOnCreep then
		return "tower-free"
	end
	if hp < LaneTowerRules.STAY_HP then
		return "hp"
	end
	if reachGap <= LaneTowerRules.ENEMY_REACH_PAD then
		return "hero-reach"
	end
	return nil
end

-- Retreat over Valve's evasive mode by an enemy tower (game 071 5:47-5:55: Largo at 58% HP, inside Dire's T1 range, hit
-- by Phantom Assassin; evasive at 0.60 held him there until he died). Returns "start", "hold" or nil.
--   evasive   the active mode is evasive maneuvers
--   holding   the tower escape already won the last think (retreat is the active mode)
--   inZone    inside an enemy tower's reach + EXIT_MARGIN
--   hp        HP ratio
--   hit       the tower shoots the bot, or a hero damaged it in the last 1.5s
-- The hold ends once the bot is out of the zone or at ESCAPE_HP or more, so a support at 58% does not walk home.
function LaneTowerRules.TowerEscape(evasive, holding, inZone, hp, hit)
	if not inZone or hp >= LaneTowerRules.ESCAPE_HP then
		return nil
	end
	if evasive and hit then
		return "start"
	end
	if holding then
		return "hold"
	end
	return nil
end

-- [OHA-AGGRO] tower-deflect result: what became of one attempt, checked ~0.8s after it.
--   died       the bot died since the attempt (its death count went up) or is dead now
--   left-range the bot is out of the tower's reach, or the tower is gone
--   switched   the tower shoots something else
--   still-on-me
function LaneTowerRules.DeflectResult(died, towerValid, dist, reach, towerOnMe)
	if died then
		return "died"
	end
	if not towerValid or dist > reach then
		return "left-range"
	end
	if towerOnMe then
		return "still-on-me"
	end
	return "switched"
end

-- The aggro pull's bait: the nearest enemy hero within BAIT_NEAR of the bot, else the first one (any distance; the
-- pull-result line shows whether a far bait still turns the creeps). dists: distances in list order. Returns the
-- index, or nil for an empty list.
function LaneTowerRules.PickBait(dists)
	local best, bestDist = nil, math.huge
	for i, dist in ipairs(dists or {}) do
		if dist <= LaneTowerRules.BAIT_NEAR and dist < bestDist then
			best, bestDist = i, dist
		end
	end
	if best ~= nil then
		return best
	end
	if dists ~= nil and #dists > 0 then
		return 1
	end
	return nil
end

return LaneTowerRules
