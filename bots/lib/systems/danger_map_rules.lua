-- Pure danger map rules (#227, no bot API calls), so tests/test_danger_map_rules.lua drives them with plain numbers.
-- bots/lib/systems/danger_map.lua builds the team's enemy list from the last-seen info and calls these.
-- Game 073: 29 of 86 deaths came with no ally within 1200 ([SHy-DEATH] allies=0), 22 of them against 3-5 enemies,
-- many of them on the bot's own half (Dire jungle at 2663,3483 / 4093,3443 / 3984,1702 with 4-5 Radiant heroes).
-- An enemy entry: { x =, y =, unseen = seconds since seen (0 = visible), speed = move speed }.
local Rules = {}

Rules.HORIZON = 5 -- seconds ahead: where an enemy could be within this time
Rules.RADIUS = 1200 -- an enemy within this of the spot counts as a danger there
Rules.UNSEEN_CAP = 10 -- the reach stops growing after this long unseen (the enemy is "missing", see Missing)
Rules.MISSING_AFTER = 10 -- unseen this long (and alive): missing
-- No enemy movement speed read yet: 300, the middle of the heroes' base MovementSpeed (270-330) in npc_heroes.txt
-- (installed game files). danger_map.lua keeps the latest speed it has seen for each enemy, at least this.
Rules.DEFAULT_SPEED = 300
Rules.ISOLATED_RADIUS = 1500 -- no other enemy could be this close: the target is alone
Rules.ISOLATED_SEEN = 3 -- the target itself was seen within this many seconds
Rules.ISOLATED_BONUS = 1.25 -- attack target score factor for an isolated enemy
-- Farm skip thresholds (FarmSkipWhy).
Rules.DANGER_ANY = 3 -- any spot: this many enemies could reach it in HORIZON and no ally is near
Rules.DANGER_FAR = 2 -- a far-side spot
Rules.MISSING_FAR = 3 -- a far-side spot while this many enemies are missing
Rules.ALLY_RADIUS = 1500 -- an ally within this of the spot: the farm is not alone
-- Own-tower cover (game 084 t=1023-1029: Underlord at our mid T2 skipped the wave there with danger=4 missing=4, no
-- enemy seen, and farm, assemble and push took turns 16 times in 20s). Tower attack range 700 (scripts/npc/npc_units.txt,
-- npc_dota_goodguys_tower1_mid..tower4 "AttackRange" "700", 7.42). A lane wave this close to one of our living towers
-- counts only the enemies seen in the last SEEN_RECENT seconds: the tower and a short walk home cover the rest.
Rules.TOWER_RANGE = 700
Rules.COVER_T1 = Rules.TOWER_RANGE + 400 -- a tier 1 tower: inside its range and a step out
Rules.COVER_DEEP = Rules.TOWER_RANGE + 1100 -- tier 2 and deeper: about 3.5s of walking (300) back into its range
Rules.SEEN_RECENT = 2 -- "seen": visible now, or stepped into the fog in the last 2s
Rules.SKIP_HOLD = 10 -- a spot skipped for danger stays skipped this long after its last skip
Rules.FALLBACK_TOWER_REACH = 3000 -- no-alternative fallback: a lane front at most this far from one of our towers

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

-- How many enemies could be within `radius` of (x, y) within `horizon` seconds. maxUnseen: count only the enemies
-- unseen at most this long (Rules.SEEN_RECENT for the "seen" count under our towers); nil = all.
function Rules.Danger(enemies, x, y, radius, horizon, maxUnseen)
	radius = radius or Rules.RADIUS
	horizon = horizon or Rules.HORIZON
	local count = 0
	for _, e in ipairs(enemies or {}) do
		if
			(maxUnseen == nil or (e.unseen or 0) <= maxUnseen)
			and dist(e.x, e.y, x, y) - Rules.Reach(e.unseen, e.speed, horizon) <= radius
		then
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

-- Our nearest living tower to (x, y) and whether it covers a lane wave there. towers: { x =, y =, tier = 1..4 }.
-- Returns the distance (math.huge: none), covered, and the nearest tower.
function Rules.OwnTowerCover(x, y, towers)
	local best, bestTower, covered = math.huge, nil, false
	for _, tower in ipairs(towers or {}) do
		local d = dist(tower.x, tower.y, x, y)
		if d < best then
			best, bestTower = d, tower
		end
		if d <= ((tower.tier or 1) >= 2 and Rules.COVER_DEEP or Rules.COVER_T1) then
			covered = true
		end
	end
	return best, covered, bestTower
end

-- Why a farm spot (camp or lane front) is skipped, or nil to keep it; second value "own-tower" when the spot is kept
-- only because our tower covers it (the rule below would skip it). s:
--   danger      Rules.Danger at the spot
--   seen        Rules.Danger at the spot counting only enemies seen in the last SEEN_RECENT seconds
--   missing     Rules.Missing
--   allies      allied heroes within ALLY_RADIUS of the spot, not counting the bot
--   farSide     Rules.FarSide (or an enemy camp)
--   covered     a lane wave under our tower's cover (Rules.OwnTowerCover); camps never are
--   strictness  DangerMap.Strictness: 0 = off (a lower difficulty can turn the rule off)
function Rules.FarmSkipWhy(s)
	if (s.strictness or 1) <= 0 or (s.allies or 0) > 0 then
		return nil
	end
	if s.covered then
		if (s.seen or 0) >= Rules.DANGER_ANY then
			return "danger-visible"
		end
		local uncovered = Rules.FarmSkipWhy({
			danger = s.danger,
			missing = s.missing,
			allies = 0,
			farSide = s.farSide,
			strictness = s.strictness,
		})
		if uncovered ~= nil then
			return nil, "own-tower"
		end
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

-- The skip hold: a spot skipped for danger stays skipped SKIP_HOLD seconds after its last skip, so the farm does not
-- pick and drop it every think while a count hovers at a threshold (game 084: 16 mode changes in 20s). held: what
-- this returned last time for the spot (nil at first); fresh: this think's FarmSkipWhy; covered: the spot is under
-- our tower's cover now. A hold from a skip outside the cover ends when the spot comes under it (a wave walking to
-- our tower). Returns the reason to use (nil = farm it) and the entry to keep for the spot.
function Rules.HoldSkip(held, now, fresh, covered)
	if fresh ~= nil then
		return fresh, { why = fresh, untilT = now + Rules.SKIP_HOLD, covered = covered == true }
	end
	if held ~= nil and now < held.untilT and (held.covered or not covered) then
		return held.why, held
	end
	return nil, nil
end

-- No alternative (every camp and lane front skipped): the safest lane front near our towers. cands: { key =,
-- seen = (Rules.Danger counting seen enemies only), ownTower = (distance to our nearest tower), dist = (from the
-- bot) }. A front with 3+ seen enemies able to reach it, or farther than FALLBACK_TOWER_REACH from our towers, is
-- out. Fewest seen enemies first, then the nearest to our tower, then to the bot. Returns the candidate or nil.
function Rules.SafestTowerWave(cands)
	local best = nil
	for _, c in ipairs(cands or {}) do
		local seen, ownTower = c.seen or 0, c.ownTower or math.huge
		if seen < Rules.DANGER_ANY and ownTower <= Rules.FALLBACK_TOWER_REACH then
			local better = best == nil
				or seen < best.seen
				or seen == best.seen and ownTower < best.ownTower
				or seen == best.seen and ownTower == best.ownTower and (c.dist or 0) < best.dist
			if better then
				best = { key = c.key, seen = seen, ownTower = ownTower, dist = c.dist or 0, cand = c }
			end
		end
	end
	return best ~= nil and best.cand or nil
end

-- Where to wait for that wave: the front itself when it is within `radius` of the tower, else the point `radius`
-- from the tower on the line to the front (the wave walks to the tower). Returns x, y.
function Rules.CoverPoint(frontX, frontY, towerX, towerY, radius)
	local d = dist(frontX, frontY, towerX, towerY)
	if d <= radius then
		return frontX, frontY
	end
	local f = radius / d
	return towerX + (frontX - towerX) * f, towerY + (frontY - towerY) * f
end

return Rules
