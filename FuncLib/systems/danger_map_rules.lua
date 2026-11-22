-- Pure danger map rules (#227, no bot API calls), so Tests/test_danger_map_rules.lua drives them with plain numbers.
-- FuncLib/systems/danger_map.lua builds the team's enemy list from the last-seen info and calls these.
-- Game 073: 29 of 86 deaths came with no ally within 1200 ([OHA-DEATH] allies=0), 22 of them against 3-5 enemies,
-- most of them on the bot's own half (Dire jungle at 2663,3483 / 4093,3443 / 3984,1702 with 4-5 Radiant heroes).
-- An enemy entry: { x =, y =, unseen = seconds since seen (0 = visible), speed = move speed }.
local Rules = {}

Rules.HORIZON = 5 -- seconds ahead: where an enemy could be within this time
Rules.RADIUS = 1200 -- an enemy within this of the spot counts as a danger there
Rules.UNSEEN_CAP = 10 -- the reach stops growing after this long unseen (the enemy is "missing", see Missing)
Rules.MISSING_AFTER = 10 -- unseen this long (and alive): missing
-- No enemy movement speed read yet: 300, the middle of the heroes' base MovementSpeed (270-330) in npc_heroes.txt
-- (installed game files). danger_map.lua keeps the fastest speed it has seen for each enemy.
Rules.DEFAULT_SPEED = 300
Rules.ISOLATED_RADIUS = 1500 -- no other enemy could be this close: the target is alone
Rules.ISOLATED_SEEN = 3 -- the target itself was seen within this many seconds
Rules.ISOLATED_BONUS = 1.25 -- attack target score factor for an isolated enemy
-- Farm skip thresholds (FarmSkipWhy).
Rules.DANGER_ANY = 3 -- any spot: this many enemies could reach it in HORIZON and no ally is near
Rules.DANGER_FAR = 2 -- a far-side spot
Rules.MISSING_FAR = 3 -- a far-side spot while this many enemies are missing
Rules.ALLY_RADIUS = 1500 -- an ally within this of the spot: the farm is not alone

local function dist(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

-- How far an enemy unseen for `unseen` seconds could be from where it was seen, `horizon` seconds from now.
function Rules.Reach(unseen, speed, horizon)
	local t = math.min(math.max(unseen or 0, 0), Rules.UNSEEN_CAP) + (horizon or 0)
	return (speed or Rules.DEFAULT_SPEED) * t
end

-- Where to read an enemy: its last-seen spot, or its fountain when it respawned after it was last seen (the
-- last-seen spot is then where it died). respawnedAgo: seconds since the respawn was noticed, or nil.
-- Returns x, y, unseen.
function Rules.EnemyPosition(seenX, seenY, sinceSeen, respawnedAgo, fountainX, fountainY)
	if respawnedAgo ~= nil and sinceSeen > respawnedAgo then
		return fountainX, fountainY, respawnedAgo
	end
	return seenX, seenY, sinceSeen
end

-- How many enemies could be within `radius` of (x, y) within `horizon` seconds.
function Rules.Danger(enemies, x, y, radius, horizon)
	radius = radius or Rules.RADIUS
	horizon = horizon or Rules.HORIZON
	local count = 0
	for _, e in ipairs(enemies or {}) do
		if dist(e.x, e.y, x, y) - Rules.Reach(e.unseen, e.speed, horizon) <= radius then
			count = count + 1
		end
	end
	return count
end

-- Alive enemies unseen for MISSING_AFTER seconds or more.
function Rules.Missing(enemies)
	local count = 0
	for _, e in ipairs(enemies or {}) do
		if (e.unseen or 0) >= Rules.MISSING_AFTER then
			count = count + 1
		end
	end
	return count
end

-- An enemy seen within ISOLATED_SEEN seconds with no other enemy that could be within ISOLATED_RADIUS of it now.
-- others: the other alive enemies (same entry shape).
function Rules.Isolated(target, others)
	if target == nil or (target.unseen or 0) > Rules.ISOLATED_SEEN then
		return false
	end
	for _, e in ipairs(others or {}) do
		if
			e ~= target
			and dist(e.x, e.y, target.x, target.y) - Rules.Reach(e.unseen, e.speed, 0) <= Rules.ISOLATED_RADIUS
		then
			return false
		end
	end
	return true
end

-- Far side: the nearest living lane tower to the spot is theirs (enemy half, or past our fallen T1 / T2: a camp
-- by our dead T1 is nearer their T1 than our T2). No towers of ours left: far side. Towers: lists of { x =, y = }.
function Rules.FarSide(x, y, ourTowers, theirTowers)
	local function nearest(towers)
		local best = math.huge
		for _, tower in ipairs(towers or {}) do
			local d = dist(tower.x, tower.y, x, y)
			if d < best then
				best = d
			end
		end
		return best
	end
	return nearest(theirTowers) < nearest(ourTowers)
end

-- Why a farm spot (camp or lane front) is skipped, or nil to keep it. s:
--   danger      Rules.Danger at the spot
--   missing     Rules.Missing
--   allies      allied heroes within ALLY_RADIUS of the spot, not counting the bot
--   farSide     Rules.FarSide (or an enemy camp)
--   strictness  DangerMap.Strictness: 0 = off (a lower difficulty can turn the rule off)
function Rules.FarmSkipWhy(s)
	if (s.strictness or 1) <= 0 or (s.allies or 0) > 0 then
		return nil
	end
	if s.danger >= Rules.DANGER_ANY then
		return "danger"
	end
	if s.farSide and s.danger >= Rules.DANGER_FAR then
		return "danger-far"
	end
	if s.farSide and s.missing >= Rules.MISSING_FAR then
		return "missing-far"
	end
	return nil
end

return Rules
