-- Team danger map (#227): where the enemy heroes could be, from the team's last-seen info. One snapshot per team,
-- rebuilt at most every REFRESH seconds by whichever bot of that team asks first (every bot runs in one Lua state
-- and `require` caches this module once), so the cost is per team, not per bot think. The rules are in
-- bots/lib/systems/danger_map_rules.lua (pure, tested).
--   DangerMap.Danger(loc[, team])   enemies that could be within 1200 of loc in the next 5s
--   DangerMap.Missing([team])       alive enemies unseen for 10s+
--   DangerMap.Isolated(enemy)       seen within 3s and no other enemy could be within 1500 of it
--   DangerMap.SeenDanger(loc)       like Danger, only the enemies seen in the last 2s
--   DangerMap.OwnTower(loc)         our nearest living tower: distance, covers a lane wave there, the tower
--   DangerMap.FarmSkip(bot, loc, enemyCamp, isWave)   why the farm skips a spot (nil = keep), and its numbers
-- The last-seen info is read from the asking bot's team, so a snapshot is only rebuilt for GetTeam().
local Rules = require(GetScriptDirectory() .. "/lib/systems/danger_map_rules")

local DangerMap = { byTeam = {}, REFRESH = 0.5, TOWER_REFRESH = 5, Rules = Rules }
-- How cautious the map is: 1 = default, 0 = off (no farm skips, no isolated bonus), between 0 and 1 a shorter
-- look-ahead (5s x Strictness). A difficulty profile can set it; nothing else here depends on one.
DangerMap.Strictness = 1

-- Fountain points (mode_farm_generic.lua radiantBaseLocation / direBaseLocation): where a respawned enemy starts.
local function FountainOf(team)
	if team == TEAM_RADIANT then
		return -7174, -6671
	end
	return 7023, 6450
end

-- Lane towers with their tier; the two tier 4 towers only for the own-tower cover (FarSide reads the lane towers).
local LANE_TOWERS, BASE_TOWERS = nil, nil
local function LivingTowers(team, withBase)
	LANE_TOWERS = LANE_TOWERS
		or {
			{ TOWER_TOP_1, 1 },
			{ TOWER_TOP_2, 2 },
			{ TOWER_TOP_3, 3 },
			{ TOWER_MID_1, 1 },
			{ TOWER_MID_2, 2 },
			{ TOWER_MID_3, 3 },
			{ TOWER_BOT_1, 1 },
			{ TOWER_BOT_2, 2 },
			{ TOWER_BOT_3, 3 },
		}
	BASE_TOWERS = BASE_TOWERS or { { TOWER_BASE_1, 4 }, { TOWER_BASE_2, 4 } }
	local list = {}
	for _, ids in ipairs(withBase and { LANE_TOWERS, BASE_TOWERS } or { LANE_TOWERS }) do
		for _, entry in ipairs(ids) do
			local tower = entry[1] ~= nil and GetTower(team, entry[1]) or nil
			if tower ~= nil and tower:IsAlive() then
				local loc = tower:GetLocation()
				list[#list + 1] = { x = loc.x, y = loc.y, tier = entry[2] }
			end
		end
	end
	return list
end

local function Horizon()
	return Rules.HORIZON * math.min(math.max(DangerMap.Strictness or 1, 0), 2)
end

local function Rebuild(snap, team, now)
	local enemyTeam = GetOpposingTeam()
	-- The latest speed seen per enemy, at least DEFAULT_SPEED (a slow reads low for a moment). Not the fastest ever:
	-- one haste rune or Charge of Darkness would keep a huge reach for the rest of the game.
	for _, hero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES) or {}) do
		if hero ~= nil and hero:IsAlive() and hero:IsHero() and not hero:IsIllusion() then
			local pid = hero:GetPlayerID()
			if pid ~= nil then
				snap.speeds[pid] = math.max(hero:GetCurrentMovementSpeed() or 0, Rules.DEFAULT_SPEED)
			end
		end
	end
	local fx, fy = FountainOf(enemyTeam)
	local enemies, byPid = {}, {}
	for _, pid in ipairs(GetTeamPlayers(enemyTeam) or {}) do
		if IsHeroAlive(pid) then
			if snap.dead[pid] then
				snap.dead[pid] = nil
				snap.respawnAt[pid] = now
			end
			local info = GetHeroLastSeenInfo(pid)
			local seen = info ~= nil and info[1] or nil
			local x, y, unseen
			if seen ~= nil and seen.location ~= nil then
				local respawnedAgo = snap.respawnAt[pid] ~= nil and now - snap.respawnAt[pid] or nil
				local sinceSeen = seen.time_since_seen or 0
				x, y, unseen = Rules.EnemyPosition(seen.location.x, seen.location.y, sinceSeen, respawnedAgo, fx, fy)
				if respawnedAgo ~= nil and sinceSeen <= respawnedAgo then
					snap.respawnAt[pid] = nil -- seen since the respawn
				end
			else
				x, y, unseen = fx, fy, math.max(now, 0)
			end
			local entry = { pid = pid, x = x, y = y, unseen = unseen, speed = snap.speeds[pid] or Rules.DEFAULT_SPEED }
			enemies[#enemies + 1] = entry
			byPid[pid] = entry
		else
			snap.dead[pid] = true
		end
	end
	local allies = {}
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
		if ally ~= nil and ally:IsAlive() and ally:IsHero() and not ally:IsIllusion() then
			local loc = ally:GetLocation()
			allies[#allies + 1] = { x = loc.x, y = loc.y, unit = ally }
		end
	end
	if now >= (snap.towersUntil or -math.huge) then
		snap.towersUntil = now + DangerMap.TOWER_REFRESH
		snap.ourTowers = LivingTowers(team)
		snap.theirTowers = LivingTowers(enemyTeam)
		snap.coverTowers = LivingTowers(team, true)
		snap.sideMemo, snap.coverMemo = {}, {}
	end
	snap.enemies, snap.byPid, snap.allies = enemies, byPid, allies
	snap.missing = Rules.Missing(enemies)
	snap.memo, snap.seenMemo = {}, {}
	snap.at = now
end

-- The snapshot of `team` (default GetTeam()), rebuilt when older than REFRESH. nil before the first build of a
-- team the caller is not on.
function DangerMap.Snapshot(team)
	team = team or GetTeam()
	local now = DotaTime()
	local snap = DangerMap.byTeam[team]
	local fresh = snap ~= nil and snap.at ~= nil and now >= snap.at and now - snap.at < DangerMap.REFRESH
	if fresh or team ~= GetTeam() then
		return snap
	end
	snap = snap or { speeds = {}, dead = {}, respawnAt = {}, sideMemo = {}, coverMemo = {}, memo = {}, seenMemo = {} }
	DangerMap.byTeam[team] = snap
	local ok, err = pcall(Rebuild, snap, team, now)
	if not ok then
		snap.at = now
		snap.enemies, snap.byPid, snap.allies, snap.missing = snap.enemies or {}, snap.byPid or {}, {}, 0
		snap.memo, snap.seenMemo = {}, {}
		if now >= (DangerMap.errorLogAt or -math.huge) then
			DangerMap.errorLogAt = now + 30
			pcall(print, string.format("[SHy-DANGER] t=%.0f team=%d rebuild-error %s", now, team, tostring(err)))
		end
	end
	return snap
end

function DangerMap.Danger(loc, team)
	local snap = DangerMap.Snapshot(team)
	if snap == nil or loc == nil or snap.enemies == nil then
		return 0
	end
	local key = math.floor(loc.x) * 100000 + math.floor(loc.y)
	local cached = snap.memo[key]
	if cached == nil then
		cached = Rules.Danger(snap.enemies, loc.x, loc.y, Rules.RADIUS, Horizon())
		snap.memo[key] = cached
	end
	return cached
end

-- Like Danger, counting only the enemies seen in the last Rules.SEEN_RECENT seconds (the count under our towers).
function DangerMap.SeenDanger(loc)
	local snap = DangerMap.Snapshot()
	if snap == nil or loc == nil or snap.enemies == nil then
		return 0
	end
	local key = math.floor(loc.x) * 100000 + math.floor(loc.y)
	local cached = snap.seenMemo[key]
	if cached == nil then
		cached = Rules.Danger(snap.enemies, loc.x, loc.y, Rules.RADIUS, Horizon(), Rules.SEEN_RECENT)
		snap.seenMemo[key] = cached
	end
	return cached
end

-- Our nearest living tower (T1-T4) to loc: distance (math.huge: none), whether it covers a lane wave at loc
-- (Rules.OwnTowerCover) and the tower as { x =, y =, tier = } (nil: none).
function DangerMap.OwnTower(loc)
	local snap = DangerMap.Snapshot()
	if snap == nil or loc == nil or snap.coverTowers == nil then
		return math.huge, false, nil
	end
	local key = math.floor(loc.x) * 100000 + math.floor(loc.y)
	local cached = snap.coverMemo[key]
	if cached == nil then
		local d, covered, tower = Rules.OwnTowerCover(loc.x, loc.y, snap.coverTowers)
		cached = { d = d, covered = covered, tower = tower }
		snap.coverMemo[key] = cached
	end
	return cached.d, cached.covered, cached.tower
end

function DangerMap.Missing(team)
	local snap = DangerMap.Snapshot(team)
	return snap ~= nil and snap.missing or 0
end

-- Allied heroes within radius of loc, not counting `except` (the asking bot).
function DangerMap.AlliesNear(loc, radius, except)
	local snap = DangerMap.Snapshot()
	local count = 0
	for _, ally in ipairs(snap ~= nil and snap.allies or {}) do
		local dx, dy = ally.x - loc.x, ally.y - loc.y
		if ally.unit ~= except and dx * dx + dy * dy <= radius * radius then
			count = count + 1
		end
	end
	return count
end

function DangerMap.FarSide(loc)
	local snap = DangerMap.Snapshot()
	if snap == nil or snap.ourTowers == nil then
		return false
	end
	-- Kept until the towers are read again (camp and lane points repeat every think).
	local key = math.floor(loc.x) * 100000 + math.floor(loc.y)
	local cached = snap.sideMemo[key]
	if cached == nil then
		cached = Rules.FarSide(loc.x, loc.y, snap.ourTowers, snap.theirTowers)
		snap.sideMemo[key] = cached
	end
	return cached
end

function DangerMap.Isolated(enemy)
	if (DangerMap.Strictness or 1) <= 0 or enemy == nil then
		return false
	end
	local snap = DangerMap.Snapshot()
	local entry = snap ~= nil and snap.byPid ~= nil and snap.byPid[enemy:GetPlayerID()] or nil
	return entry ~= nil and Rules.Isolated(entry, snap.enemies)
end

-- Why the farm skips the spot loc (nil = farm it), and the numbers behind it as a table { why =, kept =, danger =,
-- seen =, missing =, allies =, ownTower = (distance, -1: no tower), covered = }. enemyCamp: the spot is an enemy
-- camp (far side whatever the towers say). isWave: a lane wave or lane front, which our tower's cover can keep
-- (only the seen enemies count there, Rules.FarmSkipWhy); kept = "own-tower" when that is what kept it.
function DangerMap.FarmSkip(bot, loc, enemyCamp, isWave)
	local towerDist, covered = DangerMap.OwnTower(loc)
	local info = {
		danger = DangerMap.Danger(loc),
		seen = DangerMap.SeenDanger(loc),
		missing = DangerMap.Missing(),
		allies = DangerMap.AlliesNear(loc, Rules.ALLY_RADIUS, bot),
		ownTower = towerDist < math.huge and towerDist or -1,
		covered = isWave == true and covered,
	}
	info.why, info.kept = Rules.FarmSkipWhy({
		danger = info.danger,
		seen = info.seen,
		missing = info.missing,
		allies = info.allies,
		farSide = enemyCamp or DangerMap.FarSide(loc),
		covered = info.covered,
		strictness = DangerMap.Strictness,
	})
	return info.why, info
end

return DangerMap
