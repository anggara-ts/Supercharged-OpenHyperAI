-- Shared bot system: the walk home from behind an enemy tower round its range (#12, game 072 19:48-19:56: Puck walked
-- home down the lane through Dire's mid T2 after a dive and died). The rules are DiveRules.BehindTower /
-- HomeDetourStart / HomeDetourStop / PathAvoids (FuncLib/systems/dive_rules.lua, tested). mode_outpost_generic.lua
-- hosts it: its GetDesire returns HomeDetour.Desire(bot) and its Think calls HomeDetour.Think(bot) while it is on
-- (our retreat mode has no Think, Valve's retreat walk goes down the lane).
--
-- The path comes from the engine's GeneratePath(start, goal, zones, callback) with this bot's own avoidance zones:
-- the tower's range + DETOUR_RING_MARGIN and the enemy heroes last seen near (AddAvoidanceZone would be team-wide and
-- keep pushers off towers). The zone format (Vector(x, y, radius), as AddAvoidanceZone takes) and the callback's
-- arguments (distance, waypoints) are from Valve's bot scripting docs and unverified in game: the start line prints
-- what came back, and a path that still cuts the tower's range is not walked (used=no why=crosses).
local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
local DiveRules = require(GetScriptDirectory() .. "/FuncLib/systems/dive_rules")

local HomeDetour = {}

-- The path request waits this long for the callback; then the plain walk (used=no why=no-path).
local PATH_WAIT = 1.0
-- After a detour ends (or a request fails) no new one for this long.
local COOLDOWN = 4
-- Enemy heroes seen in the last 5s within this of the bot get an avoidance zone of HERO_ZONE.
local HERO_NEAR = 2500
local HERO_ZONE = 700
-- Above retreat's tower hold (BOT_DESIRE_OVERRIDE * 1.1) and its usual walk-home desires.
local DETOUR_DESIRE = 1.15

local function ShortName(bot)
	return (string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""))
end

-- The nearest standing enemy tower whose range the straight way home crosses, with the numbers for the rules.
local function TowerBehind(bot, home)
	local here = bot:GetLocation()
	local botHome = Fu.GetLocationToLocationDistance(here, home)
	for _, tower in pairs(bot:GetNearbyTowers(1600, true) or {}) do
		local ok, standing = pcall(function()
			return not tower:IsNull() and tower:IsAlive()
		end)
		if ok and standing then
			local okRange, rawRange = pcall(function()
				return tower:GetAttackRange()
			end)
			local range = (okRange and type(rawRange) == "number" and rawRange > 0) and rawRange or 700
			local towerLoc = tower:GetLocation()
			local ring = range + DiveRules.DETOUR_RING_MARGIN
			local s = {
				botHome = botHome,
				towerHome = Fu.GetLocationToLocationDistance(towerLoc, home),
				crosses = DiveRules.SegmentNearPoint(here.x, here.y, home.x, home.y, towerLoc.x, towerLoc.y, ring),
			}
			if DiveRules.BehindTower(s) then
				return tower, range, s
			end
		end
	end
	return nil
end

local function HeadingHome(bot, home)
	if bot:GetActiveMode() == BOT_MODE_RETREAT then
		return true
	end
	local now = GetUnitToLocationDistance(bot, home)
	local ahead = Fu.GetLocationToLocationDistance(bot:GetExtrapolatedLocation(0.5), home)
	return ahead < now - 50
end

local function EndDetour(bot, why)
	local detour = bot._homeDetour
	if detour == nil then
		return
	end
	if detour.used then
		pcall(
			print,
			string.format(
				"[OHA-RETREAT] t=%.0f %s tower-detour-end why=%s tower=%s crossed=%s minDist=%d range=%d hpLost=%.2f took=%.1f",
				DotaTime(),
				ShortName(bot),
				why,
				tostring(detour.name),
				detour.minDist < detour.range and "yes" or "no",
				math.floor(detour.minDist),
				math.floor(detour.range),
				detour.hpStart - Fu.GetHP(bot),
				DotaTime() - detour.startAt
			)
		)
	end
	bot._homeDetour = nil
	bot._homeDetourCooldownUntil = DotaTime() + COOLDOWN
end

local function LogStart(bot, detour, pathLength, count, used, why)
	pcall(
		print,
		string.format(
			"[OHA-RETREAT] t=%.0f %s tower-detour why=behind-tower tower=%s path=%d waypoints=%d used=%s%s dist=%d range=%d zones=%d hp=%.2f mode=%d",
			DotaTime(),
			ShortName(bot),
			tostring(detour.name),
			math.floor(pathLength or 0),
			count or 0,
			used and "yes" or "no",
			why ~= nil and (" skip=" .. why) or "",
			math.floor(GetUnitToLocationDistance(bot, detour.towerLoc)),
			math.floor(detour.range),
			detour.zoneCount,
			Fu.GetHP(bot),
			bot:GetActiveMode()
		)
	)
end

local function RequestPath(bot, tower, range, home)
	local generatePath = rawget(_G, "GeneratePath")
	local towerLoc = tower:GetLocation()
	local detour = {
		tower = tower,
		name = tower:GetUnitName(),
		towerLoc = towerLoc,
		range = range,
		requestAt = DotaTime(),
		used = false,
		minDist = GetUnitToLocationDistance(bot, towerLoc),
		zoneCount = 1,
	}
	bot._homeDetour = detour
	if generatePath == nil then
		LogStart(bot, detour, 0, 0, false, "no-api")
		EndDetour(bot, "no-api")
		return
	end
	local zones = { Vector(towerLoc.x, towerLoc.y, range + DiveRules.DETOUR_RING_MARGIN) }
	for _, playerId in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(playerId) then
			local info = GetHeroLastSeenInfo(playerId)
			local seen = info ~= nil and info[1] or nil
			if
				seen ~= nil
				and seen.time_since_seen < 5.0
				and GetUnitToLocationDistance(bot, seen.location) < HERO_NEAR
			then
				zones[#zones + 1] = Vector(seen.location.x, seen.location.y, HERO_ZONE)
			end
		end
	end
	detour.zoneCount = #zones
	local start = bot:GetLocation()
	local ok = pcall(generatePath, start, home, zones, function(distance, waypoints)
		-- The bot may have died or ended the detour meanwhile.
		if bot._homeDetour ~= detour then
			return
		end
		detour.pathLength = distance
		detour.points = waypoints or {}
	end)
	if not ok then
		LogStart(bot, detour, 0, 0, false, "error")
		EndDetour(bot, "error")
	end
end

-- The path came back: walk it only when it keeps out of the tower's range.
local function AcceptPath(bot, detour)
	local points = detour.points
	local count = #points
	if count == 0 then
		return false, "no-path"
	end
	local here = bot:GetLocation()
	local sx, sy = here.x, here.y
	-- Already inside the range: the first leg goes out, so the check starts at the first waypoint.
	if GetUnitToLocationDistance(bot, detour.towerLoc) < detour.range and points[1] ~= nil then
		sx, sy = points[1].x, points[1].y
	end
	if not DiveRules.PathAvoids(sx, sy, points, detour.towerLoc.x, detour.towerLoc.y, detour.range) then
		return false, "crosses"
	end
	return true, nil
end

-- mode_outpost_generic.lua GetDesire: the detour desire, or nil.
function HomeDetour.Desire(bot)
	if not bot:IsAlive() then
		EndDetour(bot, "dead")
		return nil
	end
	if not bot:IsHero() or bot:IsIllusion() or DotaTime() < 0 then
		return nil
	end
	local home = Fu.GetTeamFountain()
	if home == nil then
		return nil
	end
	local now = DotaTime()
	local fight = bot:WasRecentlyDamagedByAnyHero(1.0)
	local detour = bot._homeDetour
	if detour == nil then
		local tower, range, s = TowerBehind(bot, home)
		if tower == nil then
			return nil
		end
		s.headingHome = HeadingHome(bot, home)
		s.fight = fight
		s.chasing = Fu.IsGoingOnSomeone(bot)
		s.cooldown = now < (bot._homeDetourCooldownUntil or -999)
		if not DiveRules.HomeDetourStart(s) then
			return nil
		end
		RequestPath(bot, tower, range, home)
		return nil
	end
	-- Waiting for the path.
	if not detour.used then
		if detour.points == nil then
			if now - detour.requestAt > PATH_WAIT then
				LogStart(bot, detour, 0, 0, false, "no-path")
				EndDetour(bot, "no-path")
			end
			return nil
		end
		local accepted, why = AcceptPath(bot, detour)
		LogStart(bot, detour, detour.pathLength, #detour.points, accepted, why)
		if not accepted then
			EndDetour(bot, why)
			return nil
		end
		detour.used = true
		detour.startAt = now
		detour.hpStart = Fu.GetHP(bot)
		detour.index = 1
	end
	local here = bot:GetLocation()
	local towerLoc = detour.towerLoc
	detour.minDist = math.min(detour.minDist, GetUnitToLocationDistance(bot, towerLoc))
	-- Next waypoint: skip the ones reached (within 200) and any a later one is nearer than.
	local points = detour.points
	while detour.index <= #points do
		local point = points[detour.index]
		local nextPoint = points[detour.index + 1]
		local toPoint = Fu.GetLocationToLocationDistance(here, point)
		if toPoint < 200 or nextPoint ~= nil and Fu.GetLocationToLocationDistance(here, nextPoint) < toPoint then
			detour.index = detour.index + 1
		else
			break
		end
	end
	local okStands, stands = pcall(function()
		return not detour.tower:IsNull() and detour.tower:IsAlive()
	end)
	local towerStands = okStands and stands == true
	local stop = DiveRules.HomeDetourStop({
		dead = false,
		fight = fight,
		botHome = Fu.GetLocationToLocationDistance(here, home),
		towerHome = Fu.GetLocationToLocationDistance(towerLoc, home),
		crosses = towerStands and DiveRules.SegmentNearPoint(
			here.x,
			here.y,
			home.x,
			home.y,
			towerLoc.x,
			towerLoc.y,
			detour.range + DiveRules.DETOUR_RING_MARGIN
		),
		done = detour.index > #points,
		age = now - detour.startAt,
	})
	if stop ~= nil then
		EndDetour(bot, stop)
		return nil
	end
	return DETOUR_DESIRE
end

-- mode_outpost_generic.lua Think, while the detour desire won: walk to the next waypoint.
function HomeDetour.Think(bot)
	local detour = bot._homeDetour
	if detour == nil or not detour.used or detour.points == nil then
		return false
	end
	local point = detour.points[detour.index]
	if point == nil then
		return false
	end
	bot:Action_MoveToLocation(point)
	return true
end

return HomeDetour
