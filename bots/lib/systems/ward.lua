-- Shared bot system: ward.
local Ward = {}
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
-- Eye cliffs pinged in the current map. Ground point under the cliff, used after that lane's T1 falls.
local UBER_WALK = 7000
local OBS_GAP = 1500
-- Maintainer's pings, game 063 (#15): Radiant bottom (-1288, -4340) and Dire top (1028, 3581) are the spots already
-- here. Radiant top (-4365, -1012, by the Radiant outpost) and Dire bottom (4610, 770, by the Dire outpost) are back:
-- they are the right spots. As (-4348, -1008) and (4612, 767) they were not walkable, so ValidateSpot moved them to
-- (-4348, -1108) and (4439, 667), where the plant order did nothing (games 018-062: 36 and 39 give-ups
-- `why=in-range-no-plant`). keep = true (these two only): the ping stays the target (no move), and the plant retry
-- in mode_ward_generic.lua tries points around it when the order does not plant. label (the game 063 pings): a bare word
-- the [SHy-WARD] give-up, plant-retry and dispenser lines print, so a game check can name the spot.
local UberWardSpots = {
	{ location = Vector(1015, 3593, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "uber", side = "dire" },
	{
		location = Vector(4610, 770, 0),
		label = "uber-dire-bottom",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "uber",
		side = "dire",
		keep = true,
	},
	{ location = Vector(-1287, -4329, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "uber", side = "radiant" },
	{
		location = Vector(-4365, -1012, 0),
		label = "uber-radiant-top",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "uber",
		side = "radiant",
		keep = true,
	},
}
local RoshSpots = {
	{ location = Vector(-3379, 743, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "contest", side = "radiant" },
	{
		location = Vector(1230, -3082, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "contest",
		side = "radiant",
	},
	{ location = Vector(-1700, 2728, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "contest", side = "dire" },
	{ location = Vector(2588, -1248, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "contest", side = "dire" },
}
local HuntSpots = {
	{ location = Vector(-1921, 4464, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "hunt", side = "dire" },
	{ location = Vector(3796, -622, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "hunt", side = "dire" },
	{ location = Vector(36, -3778, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "hunt", side = "radiant" },
	{ location = Vector(-4876, 624, 0), plant_time_obs = 0, plant_time_sentry = 0, role = "hunt", side = "radiant" },
}
-- Lotus pools and twin gates. Same contest rules as Roshan: after 6:00, still blocked behind a living tier-1.
-- The first two are the lotus pools (pools at -7548,4209 and 7504,-4405 in [SHy-LOTUS] lines). Twin Gates (#15,
-- maintainer's pings, game 063): top (-2808, 8257) and bottom (2780, -8151) watch the gate ambush. The old gate
-- spots (-6244, 7147) and (6206, -6958) were removed (game 067, too risky to reach). Side of the
-- new spots by fountain distance, as LaneSpots does: top 10091 from the Dire base (-> dire), 15535 from the
-- Radiant one; bottom 10064 from the Radiant base (-> radiant), 15331 from the Dire one.
local GateSpots = {
	{
		location = Vector(-7421, 4238, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "contest",
		side = "radiant",
		deep = true,
	},
	{
		location = Vector(7309, -4419, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "contest",
		side = "dire",
		deep = true,
	},
	{
		location = Vector(-2808, 8257, 0),
		label = "gate-top",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "contest",
		side = "dire",
		deep = true,
		gate = "top",
	},
	{
		location = Vector(2780, -8151, 0),
		label = "gate-bottom",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "contest",
		side = "radiant",
		deep = true,
		gate = "bottom",
	},
}

local radiantEarlyWardSpots = {
	-- Radiant mid: the user's safe spots, pinged in game 022 (2026-11-16), on Radiant's side of the
	-- river so the support does not cross it. Replace the Dire bank of the top rune (-627, 850),
	-- where Mirana was killed walking back (game 020 and 021), and (-245, -996). safe = true lets
	-- them through the "early wards go on the enemy side" filter.
	-- Game 063 pings (#15): by the top river rune (-1223, -1) replaces (-1386, -171), and "option 1" (-300, -909)
	-- replaces (-303, -1001). (-882, -1000) is gone (game 067, maintainer: too close to our mid T1).
	[1] = {
		location = Vector(-1223, -1, 0),
		label = "mid-radiant-rune",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "radiant",
		safe = true,
	},
	[2] = {
		location = Vector(-300, -909, 0),
		label = "mid-radiant-1",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "radiant",
		safe = true,
	},
	[3] = {
		location = Vector(6113, -3427, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "dire",
	},
	[4] = {
		location = Vector(5308, -4362, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "radiant",
	},
}
local direEarlyWardSpots = {
	-- Dire mid: the user's safe spots, pinged in game 022 (2026-11-16): (-501, 696), (12, 257) and
	-- (632, -281), on Dire's side of the river. Replace the Radiant bank of the bottom rune
	-- (44, -1232; it planted, but across the river) and (-627, 850). safe = true lets them through
	-- the "early wards go on the enemy side" filter.
	-- Game 063 pings (#15; game 052: the Dire mid ward stood too close to the Dire mid T1): "option 1" (-533, 737)
	-- replaces (-501, 696), "option 2" (488, -100) replaces (632, -281), and the spot by the top river rune
	-- (-521, 901) is new ([6]). (12, 257) was not pinged again and stays.
	[1] = {
		location = Vector(-533, 737, 0),
		label = "mid-dire-1",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "dire",
		safe = true,
	},
	[2] = {
		location = Vector(12, 257, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "dire",
		safe = true,
	},
	[3] = {
		location = Vector(488, -100, 0),
		label = "mid-dire-2",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "dire",
		safe = true,
	},
	[4] = {
		location = Vector(-5305, 4281, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "dire",
	},
	[5] = {
		location = Vector(-5862, 3476, 0),
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "radiant",
	},
	[6] = {
		location = Vector(-521, 901, 0),
		label = "mid-dire-rune",
		plant_time_obs = 0,
		plant_time_sentry = 0,
		role = "early",
		side = "dire",
		safe = true,
	},
}
function Ward.GetEarlyGameWardSpots()
	return GetTeam() == TEAM_RADIANT and radiantEarlyWardSpots or direEarlyWardSpots
end
function Ward.GetGameStartWardSpots()
	return Ward.GetEarlyGameWardSpots()
end
-- A spot next to an enemy T2/T3, or deeper than a living T1, gets the ward killed and the support ganked.
local function EnemyWardTooDeep(loc)
	local enemy = GetOpposingTeam()
	local gates = {
		{ TOWER_TOP_2, TOWER_TOP_1 },
		{ TOWER_MID_2, TOWER_MID_1 },
		{ TOWER_BOT_2, TOWER_BOT_1 },
		{ TOWER_TOP_3, TOWER_TOP_2 },
		{ TOWER_MID_3, TOWER_MID_2 },
		{ TOWER_BOT_3, TOWER_BOT_2 },
		{ TOWER_TOP_3, TOWER_TOP_1 },
		{ TOWER_MID_3, TOWER_MID_1 },
		{ TOWER_BOT_3, TOWER_BOT_1 },
	}
	for i = 1, #gates do
		local inner = GetTower(enemy, gates[i][1])
		local outer = GetTower(enemy, gates[i][2])
		if inner ~= nil and outer ~= nil and GetUnitToLocationDistance(inner, loc) <= 1600 then
			return true
		end
	end
	local ancient = GetAncient(enemy)
	if ancient == nil then
		return false
	end
	local fronts = { TOWER_TOP_1, TOWER_MID_1, TOWER_BOT_1 }
	local nearest = nil
	local nearestDist = 3200
	for i = 1, #fronts do
		local t1 = GetTower(enemy, fronts[i])
		if t1 ~= nil then
			local dist = GetUnitToLocationDistance(t1, loc)
			if dist < nearestDist then
				nearestDist = dist
				nearest = t1
			end
		end
	end
	if nearest == nil then
		return false
	end
	local spotDepth = GetUnitToLocationDistance(ancient, loc)
	local towerDepth = GetUnitToUnitDistance(ancient, nearest)
	return spotDepth + 500 < towerDepth
end
local function DropDeepEnemySpots(list)
	local kept = {}
	for i = 1, #list do
		local spot = list[i]
		if spot.role == "early" then
			kept[#kept + 1] = spot
		elseif spot.location ~= nil and not EnemyWardTooDeep(spot.location) then
			kept[#kept + 1] = spot
		end
	end
	return kept
end
-- Twin Gates: only the new spots (game 067, maintainer: the old corner spots are too risky - Vengeful Spirit walked past
-- the enemy wave and heroes at 9:00 to plant a sentry there - so they were removed).
local function ConsiderGates(spots, consider)
	for i = 1, #GateSpots do
		consider(GateSpots[i])
	end
end
-- Home/defend ground spots sit on our T3. Skip them until that lane's T1 is gone,
-- unless enemies are already on the high ground (handled by the caller).
local function HomeWardTooEarly(loc)
	local team = GetTeam()
	local lanes = {
		{ TOWER_TOP_1, TOWER_TOP_3 },
		{ TOWER_MID_1, TOWER_MID_3 },
		{ TOWER_BOT_1, TOWER_BOT_3 },
	}
	local sawTower = false
	local laneOpen = false
	for i = 1, #lanes do
		local t1 = GetTower(team, lanes[i][1])
		local t3 = GetTower(team, lanes[i][2])
		if t1 ~= nil or t3 ~= nil then
			sawTower = true
		end
		if t1 == nil and t3 ~= nil then
			laneOpen = true
		end
		if t1 ~= nil and t3 ~= nil and GetUnitToLocationDistance(t3, loc) <= 1800 then
			return true
		end
	end
	return not sawTower or not laneOpen
end
-- Plant retry points around a spot (#15, mode_ward_generic.lua PlantRetry): 8 directions at 50, then at 100, as
-- { x, y } pairs, nearest first.
function Ward.RetryPoints(center)
	local points = {}
	for _, radius in ipairs({ 50, 100 }) do
		for step = 0, 7 do
			local angle = step * math.pi / 4
			points[#points + 1] = { center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius }
		end
	end
	return points
end
function Ward.WalkLimit(spot)
	if spot and spot.role == "uber" then
		return UBER_WALK
	end
	return 4000
end
local function ObsFree(spot)
	return spot ~= nil
		and spot.location ~= nil
		and not Ward.IsOtherWardClose(spot.location, "npc_dota_observer_wards", OBS_GAP, true, false)
		and not Ward.AllyGoingTo(spot.location, OBS_GAP)
		and not Ward.IsThereEnemySentry(spot.location, 1100)
		and (spot.plant_time_obs == 0 or DotaTime() > spot.plant_time_obs + 360)
end
local function SentryFree(spot)
	return spot ~= nil
		and spot.location ~= nil
		-- Sentry True Sight 1050 (game files): spots within 1200 of an allied sentry are skipped,
		-- more than the radius, so planted sentries never overlap. Towers: IsLocationHaveTrueSight.
		and not Ward.IsOtherWardClose(spot.location, "npc_dota_sentry_wards", 1200, true, false)
		and not Fu.Site.IsLocationHaveTrueSight(spot.location)
		and (spot.plant_time_sentry == 0 or DotaTime() > spot.plant_time_sentry + 360)
end
-- Towers have loaded and at least one enemy tier-1 is gone. All-nil is not "all down".
local function EnemyOuterDown()
	local enemy = GetOpposingTeam()
	local lanes = { TOWER_TOP_1, TOWER_MID_1, TOWER_BOT_1 }
	local alive = 0
	local loaded = GetTower(enemy, TOWER_TOP_2) ~= nil
		or GetTower(enemy, TOWER_MID_2) ~= nil
		or GetTower(enemy, TOWER_BOT_2) ~= nil
		or GetTower(enemy, TOWER_TOP_3) ~= nil
		or GetTower(enemy, TOWER_MID_3) ~= nil
		or GetTower(enemy, TOWER_BOT_3) ~= nil
	for i = 1, #lanes do
		if GetTower(enemy, lanes[i]) ~= nil then
			alive = alive + 1
			loaded = true
		end
	end
	return loaded and alive < #lanes
end
local function TeamSide()
	return GetTeam() == TEAM_RADIANT and "radiant" or "dire"
end
-- Cliffs, hunt spots and gates on the enemy side sit in their jungle. River banks do not. A lane
-- spot past the middle of the map is toward their towers.
local function NeedsCover(spot)
	return spot.role == "uber" or spot.role == "hunt" or spot.role == "lane" or spot.deep == true
end
-- Lane spots (user call: after towers fall, bots never warded along the lane paths, only the fixed
-- spots). For a lane where a tier-1 tower (either team's) is down, after 10:00: a point on the lane
-- path ahead of our wave (900, or farther to keep clear of our own towers, see PickLaneSpot), toward the
-- enemy, so the vision follows the front both ways.
-- Positions come from the game's lane data (GetLaneFrontLocation with a forward offset, as push.lua
-- uses it backward with -500), so they are on walkable ground on the lane path. One spot table per
-- lane is kept and moved only when the front has moved 900+, so a planted or given-up mark stays.
local LANE_AHEAD = 900
local laneSpots = {}
-- Within 1200 of a living enemy tower (tower attack range 700, plus the walk in to plant).
local ENEMY_TOWER_GAP = 1200
local function NearEnemyTower(loc)
	local enemy = GetOpposingTeam()
	for _, id in ipairs({
		TOWER_TOP_1,
		TOWER_TOP_2,
		TOWER_TOP_3,
		TOWER_MID_1,
		TOWER_MID_2,
		TOWER_MID_3,
		TOWER_BOT_1,
		TOWER_BOT_2,
		TOWER_BOT_3,
		TOWER_BASE_1,
		TOWER_BASE_2,
	}) do
		local tower = GetTower(enemy, id)
		if tower ~= nil and GetUnitToLocationDistance(tower, loc) <= ENEMY_TOWER_GAP then
			return true
		end
	end
	return false
end
local function LaneTier1Down(lane)
	local t1 = lane == LANE_TOP and TOWER_TOP_1 or lane == LANE_MID and TOWER_MID_1 or TOWER_BOT_1
	return GetTower(TEAM_RADIANT, t1) == nil or GetTower(TEAM_DIRE, t1) == nil
end
-- Gap between a lane observer and our own towers (#15, game 080, 23:40: Largo planted a lane observer at the rim of
-- our top T2's range, where the tower already sees most of what the ward sees). Maintainer's rule: the ward stands
-- at least the tower's attack range plus the observer's vision away from every living tower of ours, so its vision
-- starts where the tower's area ends. Observer vision 1600: 7.42 game files, item_ward_observer
-- vision_range_tooltip 1600 (Valve datafeed item 42, the same). Tower range from tower:GetAttackRange() at runtime
-- (700 in npc_units.txt for every tower, the fallback). LANE_GAP_MARGIN: the ward can land off the spot (the plant
-- retry tries up to 100 out, PlantShort plants up to ~230 short of it), so the spot keeps that much more.
local OBS_VISION = 1600
local LANE_GAP_MARGIN = 250
local OWN_TOWER_IDS = {
	TOWER_TOP_1,
	TOWER_TOP_2,
	TOWER_TOP_3,
	TOWER_MID_1,
	TOWER_MID_2,
	TOWER_MID_3,
	TOWER_BOT_1,
	TOWER_BOT_2,
	TOWER_BOT_3,
	TOWER_BASE_1,
	TOWER_BASE_2,
}
function Ward.OwnTowerGap(range)
	return (range or 700) + OBS_VISION
end
-- Our living towers as { x =, y =, range = } (plain numbers, for the pure helpers below).
function Ward.OwnTowerList()
	local towers = {}
	for _, id in ipairs(OWN_TOWER_IDS) do
		local tower = GetTower(GetTeam(), id)
		if tower ~= nil and not tower:IsNull() then
			local loc = tower:GetLocation()
			towers[#towers + 1] = { x = loc.x, y = loc.y, range = tower:GetAttackRange() or 700 }
		end
	end
	return towers
end
-- Pure: the distance from (x, y) to the nearest tower in towers, and the smallest margin (distance minus that
-- tower's OwnTowerGap) over all of them. Both nil without towers.
function Ward.OwnTowerClearance(x, y, towers)
	local nearest, margin = nil, nil
	for _, tower in ipairs(towers) do
		local dist = math.sqrt((tower.x - x) ^ 2 + (tower.y - y) ^ 2)
		local room = dist - Ward.OwnTowerGap(tower.range)
		if nearest == nil or dist < nearest then
			nearest = dist
		end
		if margin == nil or room < margin then
			margin = room
		end
	end
	return nearest, margin
end
-- Pure: picks the lane observer point. points are candidates on the lane path ahead of our wave, ordered from the
-- wave forward, each { x =, y =, enemyNear = bool, inBase = bool }; first is the index of the preferred point (900
-- ahead). Walks forward from it to the first point clear of our towers (margin >= extra); a point in enemy tower range
-- or inside a base ends the walk (deeper is worse). When the preferred point itself is in enemy tower range, the
-- points behind it are tried, back toward the wave (the old pull-back to 300), with the same own-tower rule.
-- Returns the index, or nil and why ("own-tower", "enemy-tower", "base").
function Ward.PickLaneSpot(points, first, towers, extra)
	extra = extra or 0
	local function clear(point)
		local _, margin = Ward.OwnTowerClearance(point.x, point.y, towers)
		return margin == nil or margin >= extra
	end
	local why = "own-tower"
	for i = first, #points do
		local point = points[i]
		if point.inBase then
			why = "base"
			break
		end
		if point.enemyNear then
			why = "enemy-tower"
			break
		end
		if clear(point) then
			return i
		end
	end
	if points[first] ~= nil and points[first].enemyNear then
		for i = first - 1, 1, -1 do
			local point = points[i]
			if not point.enemyNear and not point.inBase and clear(point) then
				return i
			end
		end
	end
	return nil, why
end
-- Offsets ahead of the wave the lane spot can take: 300 and 600 (pull-back), 900 (preferred), then forward in steps
-- of 300 up to 6900. A fixed list: GetLaneFrontLocation is called once per offset, at most every LANE_RECALC seconds.
local LANE_OFFSETS = {}
for offset = 300, 6900, 300 do
	LANE_OFFSETS[#LANE_OFFSETS + 1] = offset
end
local LANE_FIRST = LANE_AHEAD / 300
local LANE_RECALC = 2
local laneCalc = {}
local laneLog = {}
local LANE_NAMES = { [LANE_TOP] = "top", [LANE_MID] = "mid", [LANE_BOT] = "bot" }
-- One line per lane when its spot moves or when the lane has none (and why changed): `[SHy-WARD] lane-spot`.
local function LaneSpotLog(lane, key, text)
	if laneLog[lane] == key then
		return
	end
	laneLog[lane] = key
	local me = GetBot()
	pcall(
		print,
		string.format(
			"[SHy-WARD] t=%.0f %s lane-spot lane=%s %s",
			DotaTime(),
			me ~= nil and (string.gsub(me:GetUnitName(), "npc_dota_hero_", "")) or "?",
			LANE_NAMES[lane] or tostring(lane),
			text
		)
	)
end
-- The lane observer point for one lane: { loc =, offset = } or { why = } when there is none.
local function LaneSpotPick(lane, fountain, enemyFountain)
	local calc = laneCalc[lane]
	if calc ~= nil and DotaTime() - calc.t < LANE_RECALC then
		return calc
	end
	local points = {}
	for idx, offset in ipairs(LANE_OFFSETS) do
		local loc = GetLaneFrontLocation(GetTeam(), lane, offset)
		if loc == nil then
			break
		end
		-- Not under an enemy tower (user question: a wave pushing their T2 put the spot in its range; the deep filter
		-- only covers towers that still have an outer tower in front). Not inside either base: a front pushed to a
		-- barracks is a siege, not a ward spot.
		points[idx] = {
			x = loc.x,
			y = loc.y,
			loc = loc,
			offset = offset,
			enemyNear = NearEnemyTower(loc),
			inBase = fountain ~= nil
				and enemyFountain ~= nil
				and (Fu.GetDistance(loc, fountain) < 4000 or Fu.GetDistance(loc, enemyFountain) < 4000),
		}
	end
	local idx, why = nil, "no-front"
	if points[LANE_FIRST] ~= nil then
		idx, why = Ward.PickLaneSpot(points, LANE_FIRST, Ward.OwnTowerList(), LANE_GAP_MARGIN)
	end
	calc = { t = DotaTime() }
	if idx ~= nil then
		calc.loc, calc.offset = points[idx].loc, points[idx].offset
	else
		calc.why = why
	end
	laneCalc[lane] = calc
	return calc
end
local function LaneSpots()
	local out = {}
	if DotaTime() < 10 * 60 then
		return out
	end
	local fountain = Fu.GetTeamFountain and Fu.GetTeamFountain() or nil
	local enemyFountain = Fu.GetEnemyFountain and Fu.GetEnemyFountain() or nil
	for _, lane in ipairs({ LANE_TOP, LANE_MID, LANE_BOT }) do
		if LaneTier1Down(lane) then
			local pick = LaneSpotPick(lane, fountain, enemyFountain)
			local loc = pick.loc
			if loc ~= nil then
				local cur = laneSpots[lane]
				if cur == nil or Fu.GetDistance(cur.location, loc) >= 900 then
					local ours = fountain ~= nil
						and enemyFountain ~= nil
						and Fu.GetDistance(loc, fountain) < Fu.GetDistance(loc, enemyFountain)
					local ourSide = TeamSide()
					local side = ours and ourSide or (ourSide == "radiant" and "dire" or "radiant")
					cur = {
						location = loc,
						plant_time_obs = 0,
						plant_time_sentry = 0,
						role = "lane",
						side = side,
						lane = LANE_NAMES[lane],
					}
					laneSpots[lane] = cur
					local nearest = Ward.OwnTowerClearance(loc.x, loc.y, Ward.OwnTowerList())
					LaneSpotLog(
						lane,
						string.format("%.0f,%.0f", loc.x, loc.y),
						string.format(
							"at=%.0f,%.0f ahead=%d ownTower=%.0f",
							loc.x,
							loc.y,
							pick.offset or -1,
							nearest or 99999
						)
					)
				end
				out[#out + 1] = cur
			else
				LaneSpotLog(lane, "none:" .. tostring(pick.why), "none why=" .. tostring(pick.why))
			end
		end
	end
	return out
end
-- Walk into enemy jungle only behind our wave or with teammates, never into a visible bigger group.
local function EnemySideCovered(bot, loc)
	if bot == nil or loc == nil then
		return false
	end
	if bot:GetHealth() / math.max(1, bot:GetMaxHealth()) < 0.6 then
		return false
	end
	local allies = 0
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
		if
			ally ~= bot
			and ally:IsAlive()
			and not ally:IsIllusion()
			and GetUnitToLocationDistance(ally, loc) <= 1800
		then
			allies = allies + 1
		end
	end
	local enemies = 0
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES) or {}) do
		if enemy:IsAlive() and not enemy:IsIllusion() and GetUnitToLocationDistance(enemy, loc) <= 2000 then
			enemies = enemies + 1
		end
	end
	if enemies > allies then
		return false
	end
	-- Several enemies out of sight can be waiting in that jungle.
	local missing = 0
	for _, pid in pairs(GetTeamPlayers(GetOpposingTeam()) or {}) do
		if IsHeroAlive(pid) then
			local info = GetHeroLastSeenInfo(pid)
			local seen = info ~= nil and info[1] or nil
			if seen == nil or seen.time_since_seen > 5 then
				missing = missing + 1
			end
		end
	end
	if allies >= 2 then
		return true
	end
	if missing >= 3 then
		return false
	end
	local creeps = 0
	for _, creep in pairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS) or {}) do
		if creep:IsAlive() and GetUnitToLocationDistance(creep, loc) <= 2200 then
			creeps = creeps + 1
			if creeps >= 3 then
				return true
			end
		end
	end
	return false
end
local function DefendingHighGround()
	local ancient = GetAncient(GetTeam())
	local enemiesNearAncient = ancient ~= nil and Fu.Utils.CountEnemyHeroesNear(ancient:GetLocation(), 2500) or 0
	return enemiesNearAncient >= 1 or Fu.Utils.CountEnemyHeroesOnHighGround(GetTeam()) >= 1
end
function Ward.GetAvailabeObserverWardSpots(bot)
	local spots = {}
	if DotaTime() < 0 or Fu.IsEarlyGame() then
		local ourSide = TeamSide()
		for _, spot in pairs(Ward.GetEarlyGameWardSpots()) do
			-- Early observers go on the enemy side. Own-side cliffs look back into our jungle.
			if ObsFree(spot) and (spot.side ~= ourSide or spot.safe) then
				table.insert(spots, spot)
			end
		end
		if DotaTime() < 6 * 60 then
			return DropDeepEnemySpots(spots)
		end
	end
	local ourSide = TeamSide()
	local defending = DefendingHighGround()
	local pushing = not defending and EnemyOuterDown()
	local function consider(spot)
		if not ObsFree(spot) then
			return
		end
		local onOurs = spot.side == ourSide
		if not onOurs and NeedsCover(spot) and not EnemySideCovered(bot, spot.location) then
			return
		end
		if spot.role == "uber" then
			-- Own eye cliff looks back into our jungle. While pushing, ward the enemy cliff.
			if defending and not onOurs then
				return
			end
			if pushing and onOurs then
				return
			end
			-- Game 069 6:28 (maintainer): an observer on our own cliff with every tower up watches nothing. Our cliff is a
			-- defensive ward (a lane of ours with its T1 down, as the hunt spots use), the enemy's an offensive one
			-- (pushing, or past the early game).
			local skipWhy = nil
			if onOurs and not defending and HomeWardTooEarly(spot.location) then
				skipWhy = "home-too-early"
			elseif not onOurs and Fu.IsEarlyGame() and not pushing then
				skipWhy = "not-pushing"
			end
			if skipWhy ~= nil then
				if DotaTime() >= (spot._uberSkipLogAt or -999) then
					spot._uberSkipLogAt = DotaTime() + 60
					print(
						string.format(
							"[SHy-WARD] t=%.0f %s uber-skip why=%s spot=%s at=%.0f,%.0f",
							DotaTime(),
							(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
							skipWhy,
							tostring(spot.label or spot.side),
							spot.location.x,
							spot.location.y
						)
					)
				end
				return
			end
		elseif spot.role == "contest" then
			if defending and not onOurs then
				return
			end
		elseif spot.role == "hunt" then
			if onOurs then
				if not defending and HomeWardTooEarly(spot.location) then
					return
				end
			elseif defending or (Fu.IsEarlyGame() and not pushing) then
				return
			end
		elseif spot.role == "lane" then
			-- Defending our high ground: no lane ward on their half.
			if defending and not onOurs then
				return
			end
		else
			return
		end
		table.insert(spots, spot)
	end
	for _, spot in ipairs(LaneSpots()) do
		consider(spot)
	end
	for i = 1, #UberWardSpots do
		consider(UberWardSpots[i])
	end
	for i = 1, #RoshSpots do
		local spot = RoshSpots[i]
		local x, y = spot.location.x, spot.location.y
		local bottomRune = (x == 1230 and y == -3082) or (x == 2588 and y == -1248)
		-- Own bank of the bottom rune faces our jungle. Ward the enemy bank.
		if not (bottomRune and spot.side == ourSide) then
			consider(spot)
		end
	end
	ConsiderGates(spots, consider)
	for i = 1, #HuntSpots do
		consider(HuntSpots[i])
	end
	return DropDeepEnemySpots(spots)
end
function Ward.GetClosestObserverWardSpot(bot, spots)
	local closestDistance = 100000
	local closestSpot = nil
	local uberBest = nil
	local uberDist = 100000
	local uberMax = UBER_WALK
	for _, spot in pairs(spots) do
		local distance = GetUnitToLocationDistance(bot, spot.location)
		if spot.role == "uber" and distance < uberDist and distance <= uberMax then
			uberDist = distance
			uberBest = spot
		end
		if distance < closestDistance then
			closestDistance = distance
			closestSpot = spot
		end
	end
	return uberBest or closestSpot
end
-- Objective ward (user call): when a teammate heads for Roshan, or for the enemy-side outpost, a
-- support with an observer wards the enemy-side spot nearest that objective first: the side the
-- enemies come from. For Radiant at the bottom pit that is the Dire contest spot by the river and
-- the Dire outpost (2588, -1248); for Dire at the top pit, the Radiant contest spot (-3379, 743).
-- Contest and hunt spots only, never an eye cliff (uber): those mean walking deep into enemy
-- territory. A spot already covered by one of our observers (any, also a human's) or with an ally
-- already walking to it is skipped (ObsFree). Game 035, 34:04: Leshrac died at the Dire outpost to
-- three heroes nobody could see.
local OBJECTIVE_OUTPOSTS = { Vector(-4096, -448, 128), Vector(3392, -448, 128) }
local OBJECTIVE_WARD_RANGE = 2600
local function ObjectiveTarget()
	local ourSide = TeamSide()
	local rosh = Fu.GetCurrentRoshanLocation and Fu.GetCurrentRoshanLocation() or nil
	-- The enemy-side outpost: the one farther from our fountain.
	local fountain = Fu.GetTeamFountain and Fu.GetTeamFountain() or nil
	local enemyOutpost = OBJECTIVE_OUTPOSTS[2]
	if
		fountain ~= nil
		and Fu.GetDistance(OBJECTIVE_OUTPOSTS[1], fountain) > Fu.GetDistance(OBJECTIVE_OUTPOSTS[2], fountain)
	then
		enemyOutpost = OBJECTIVE_OUTPOSTS[1]
	end
	for i = 1, 5 do
		local ally = GetTeamMember(i)
		if Fu.IsValidHero(ally) then
			local mode = ally:GetActiveMode()
			if mode == BOT_MODE_ROSHAN and rosh ~= nil then
				return rosh, "roshan"
			end
			if
				BOT_MODE_OUTPOST ~= nil
				and mode == BOT_MODE_OUTPOST
				and GetUnitToLocationDistance(ally, enemyOutpost) <= 4000
			then
				return enemyOutpost, "enemy-outpost"
			end
		end
	end
	return nil
end
function Ward.GetObjectiveWardSpot(bot)
	local target, kind = ObjectiveTarget()
	if target == nil then
		return nil
	end
	local ourSide = TeamSide()
	local best, bestDist = nil, OBJECTIVE_WARD_RANGE
	local function consider(spot)
		if spot.side == ourSide then
			return
		end
		local distance = Fu.GetDistance(spot.location, target)
		if distance < bestDist then
			best, bestDist = spot, distance
		end
	end
	for i = 1, #RoshSpots do
		consider(RoshSpots[i])
	end
	for i = 1, #HuntSpots do
		consider(HuntSpots[i])
	end
	if best == nil or not ObsFree(best) then
		return nil
	end
	return best, kind
end
function Ward.GetPossibleSentryWardSpots(bot)
	local spots = {}
	local ourSide = TeamSide()
	local defending = DefendingHighGround()
	local pushing = not defending and EnemyOuterDown()
	if DotaTime() < 0 or Fu.IsEarlyGame() then
		for _, spot in pairs(Ward.GetEarlyGameWardSpots()) do
			if (spot.side ~= ourSide or spot.safe) and SentryFree(spot) then
				table.insert(spots, spot)
			end
		end
		if DotaTime() < 6 * 60 then
			return DropDeepEnemySpots(spots)
		end
	end
	local function consider(spot)
		if not SentryFree(spot) then
			return
		end
		local onOurs = spot.side == ourSide
		if not onOurs and NeedsCover(spot) and not EnemySideCovered(bot, spot.location) then
			return
		end
		local want = false
		if defending then
			want = onOurs
		elseif pushing then
			want = not onOurs
		else
			want = spot.role == "contest" or spot.role == "uber"
		end
		if want then
			table.insert(spots, spot)
		end
	end
	for i = 1, #UberWardSpots do
		consider(UberWardSpots[i])
	end
	for i = 1, #RoshSpots do
		consider(RoshSpots[i])
	end
	ConsiderGates(spots, consider)
	for i = 1, #HuntSpots do
		consider(HuntSpots[i])
	end
	return DropDeepEnemySpots(spots)
end
function Ward.GetClosestSentryWardSpot(bot, spots)
	local closestDistance = 100000
	local closestSpot = nil
	for _, spot in pairs(spots) do
		local distance = GetUnitToLocationDistance(bot, spot.location)
		if distance < closestDistance then
			closestDistance = distance
			closestSpot = spot
		end
	end
	return closestSpot
end
-- Another support already heading here would plant a second observer before the first exists.
function Ward.AllyGoingTo(loc, gap)
	local me = GetBot()
	for i = 1, 5 do
		local ally = GetTeamMember(i)
		if
			Fu.IsValidHero(ally)
			and ally ~= me
			and ally:GetActiveMode() == BOT_MODE_WARD
			and Fu.GetDistance(ally:GetExtrapolatedLocation(3), loc) <= gap
		then
			return true
		end
	end
	return false
end
function Ward.IsOtherWardClose(location, unitName, radius, isAllied, requireFreshWard)
	local wards = GetUnitList(UNIT_LIST_ALLIED_WARDS)
	if not isAllied then
		wards = GetUnitList(UNIT_LIST_ENEMY_WARDS)
	end
	for _, ward in pairs(wards) do
		if
			Fu.IsValid(ward)
			and string.find(ward:GetUnitName(), unitName)
			and GetUnitToLocationDistance(ward, location) <= radius
		then
			if requireFreshWard then
				if
					unitName == "npc_dota_observer_wards"
					and Fu.GetModifierTime(ward, "modifier_item_buff_ward") >= 360 / 2
				then
					return true
				end
			else
				return true
			end
		end
	end
	return false
end
function Ward.IsThereEnemySentry(location, radius)
	local enemyWards = GetUnitList(UNIT_LIST_ENEMY_WARDS)
	for _, ward in pairs(enemyWards) do
		if
			Fu.IsValid(ward)
			and ward:GetUnitName() == "npc_dota_sentry_wards"
			and GetUnitToLocationDistance(ward, location) <= radius
		then
			return true
		end
	end
	return false
end
return Ward
