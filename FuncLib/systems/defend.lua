-- Tower defense desire, and the team chat that asks allies to come defend.
local function arrayFilter(self, callback, thisArg)
	local result = {}
	local count = 0
	for i = 1, #self do
		if callback(thisArg, self[i], i - 1, self) then
			count = count + 1
			result[count] = self[i]
		end
	end
	return result
end
local function stringIncludes(self, searchString, position)
	if not position then
		position = 1
	else
		position = position + 1
	end
	local foundIndex = string.find(self, searchString, position, true)
	return foundIndex ~= nil
end
local function arraySort(self, compareFn)
	if compareFn ~= nil then
		table.sort(self, function(left, right)
			return compareFn(nil, left, right) < 0
		end)
	else
		table.sort(self)
	end
	return self
end
local function arrayFind(self, callback, thisArg)
	for i = 1, #self do
		local element = self[i]
		if callback(thisArg, element, i - 1, self) then
			return element
		end
	end
	return nil
end
local Defend = {}
local getDefendState, getGameState, getLaneState, getUnitLists, locationKey, locationRadiusKey, countRecentlySeenEnemies, isAliveBuilding, isBaseDefenseActive, isDefendingOtherLane, getWeightedEnemyCount, getMostThreatenedLane, getClosestPosition, noOtherTravelBootsDefender, getHighGroundWaitPoint, pingForDefense, localizationLoaded, Localization, humanPingSeconds, maxDefendDesire, ancientThreatRadius, baseDefenseSeconds, enemyCountCacheSeconds, lastSeenSeconds, ourTeam, threatLaneLock, baseDefenseUntil, travelBootsDefenderTime, enemyCountCache, stateCacheSeconds, gameStateCache, laneStateCache, unitListCache
local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
local Dota = require(GetScriptDirectory() .. "/FuncLib/dota/index")
local Barracks = Dota.Barracks
local BotMode = Dota.BotMode
local BotModeDesire = Dota.BotModeDesire
local Lane = Dota.Lane
local Tower = Dota.Tower
local UnitType = Dota.UnitType
local NativeOperators = require(GetScriptDirectory() .. "/FuncLib/lib/native_operators")
local vectorAdd = NativeOperators.add
local Utils = require(GetScriptDirectory() .. "/FuncLib/systems/utils")
local getLocationToLocationDistance = Utils.GetLocationToLocationDistance
local CacheKeys = require(GetScriptDirectory() .. "/FuncLib/systems/cache_keys")
function getDefendState(bot)
	if not bot._defend then
		bot._defend = {
			defendLoc = GetLaneFrontLocation(ourTeam, Lane.Mid, 0),
			weAreStronger = false,
			nInRangeAlly = {},
			nInRangeEnemy = {},
			distanceToLane = { [Lane.Top] = 0, [Lane.Mid] = 0, [Lane.Bot] = 0 },
		}
	end
	return bot._defend
end
function getGameState()
	local now = DotaTime()
	if gameStateCache and now - gameStateCache.lastUpdate < stateCacheSeconds then
		return gameStateCache
	end
	local team = GetTeam()
	local enemyTeam = GetOpposingTeam()
	local dotaTime = DotaTime()
	local gameMode = GetGameMode()
	local currentTime = gameMode == 23 and dotaTime * 1.65 or dotaTime
	local ourAncient = GetAncient(team)
	local ancientLocation = ourAncient ~= nil and ourAncient:GetLocation() or nil
	local defendersAtAncient = 0
	if ancientLocation ~= nil then
		local alliesNearAncient = Fu.GetAlliesNearLoc(ancientLocation, 2500)
		for _, ally in ipairs(alliesNearAncient) do
			if Fu.IsValidHero(ally) then
				defendersAtAncient = defendersAtAncient + 1
			end
		end
	end
	gameStateCache = {
		lastUpdate = now,
		currentTime = currentTime,
		gameMode = gameMode,
		team = team,
		enemyTeam = enemyTeam,
		ourAncient = ourAncient,
		enemyAncient = GetAncient(enemyTeam),
		aliveAllyCount = Fu.GetNumOfAliveHeroes(false),
		aliveEnemyCount = Fu.GetNumOfAliveHeroes(true),
		isLaningPhase = Fu.IsInLaningPhase(),
		isEarlyGame = Fu.IsEarlyGame(),
		isMidGame = Fu.IsMidGame(),
		isLateGame = Fu.IsLateGame(),
		teamFountain = Fu.GetTeamFountain(),
		teamFountainTpPoint = Fu.Utils.GetTeamFountainTpPoint(),
		enemiesOnHG = Fu.Utils.CountEnemyHeroesOnHighGround(team),
		enemiesAtAncient = ancientLocation ~= nil and Fu.Utils.CountEnemyHeroesNear(ancientLocation, 2200) or 0,
		ancientHP = ourAncient ~= nil and ourAncient:IsAlive() and Fu.GetHP(ourAncient) or 1,
		defendersAtAncient = defendersAtAncient,
	}
	return gameStateCache
end
function getLaneState()
	local now = DotaTime()
	if laneStateCache and now - laneStateCache.lastUpdate < stateCacheSeconds then
		return laneStateCache
	end
	local team = GetTeam()
	local enemyTeam = GetOpposingTeam()
	laneStateCache = {
		lastUpdate = now,
		laneFronts = {
			[Lane.Top] = GetLaneFrontLocation(team, Lane.Top, 0),
			[Lane.Mid] = GetLaneFrontLocation(team, Lane.Mid, 0),
			[Lane.Bot] = GetLaneFrontLocation(team, Lane.Bot, 0),
		},
		enemyLaneFronts = {
			[Lane.Top] = GetLaneFrontLocation(enemyTeam, Lane.Top, 0),
			[Lane.Mid] = GetLaneFrontLocation(enemyTeam, Lane.Mid, 0),
			[Lane.Bot] = GetLaneFrontLocation(enemyTeam, Lane.Bot, 0),
		},
		highGroundEdgeWaitPoints = {
			[Lane.Top] = getHighGroundWaitPoint(team, Lane.Top),
			[Lane.Mid] = getHighGroundWaitPoint(team, Lane.Mid),
			[Lane.Bot] = getHighGroundWaitPoint(team, Lane.Bot),
		},
	}
	return laneStateCache
end
function getUnitLists()
	local now = DotaTime()
	if unitListCache and now - unitListCache.lastUpdate < stateCacheSeconds then
		return unitListCache
	end
	local teamMembers = {}
	do
		local i = 1
		while i <= #GetTeamPlayers(GetTeam()) do
			local member = GetTeamMember(i)
			if member ~= nil then
				teamMembers[#teamMembers + 1] = member
			end
			i = i + 1
		end
	end
	unitListCache = {
		lastUpdate = now,
		enemyBuildings = GetUnitList(UnitType.EnemyBuildings),
		alliedHeroes = GetUnitList(UnitType.AlliedHeroes),
		enemyHeroes = arrayFilter(GetUnitList(UnitType.Enemies), function(_, unit)
			return Fu.IsValidHero(unit)
		end),
		alliedCreeps = GetUnitList(UnitType.AlliedCreeps),
		enemyCreeps = arrayFilter(GetUnitList(UnitType.Enemies), function(_, unit)
			return unit:IsCreep() or unit:IsAncientCreep()
		end),
		teamMembers = teamMembers,
	}
	return unitListCache
end
function locationKey(location)
	return location
			and (tostring(math.floor(location.x / 200) * 200) .. ":") .. tostring(math.floor(location.y / 200) * 200)
		or "0:0"
end
function locationRadiusKey(location, radius)
	return (locationKey(location) .. "|") .. tostring(math.floor(radius or 0))
end
function countRecentlySeenEnemies(location, radius, maxAge)
	if maxAge == nil then
		maxAge = lastSeenSeconds
	end
	local gameState = getGameState()
	local count = 0
	for _, playerId in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
		do
			local continued
			repeat
				if not IsHeroAlive(playerId) then
					continued = true
					break
				end
				local lastSeenInfo = GetHeroLastSeenInfo(playerId)
				if
					lastSeenInfo
					and lastSeenInfo[1]
					and lastSeenInfo[1].time_since_seen <= maxAge
					and getLocationToLocationDistance(lastSeenInfo[1].location, location) <= radius
				then
					count = count + 1
				end
				continued = true
			until true
			if not continued then
				break
			end
		end
	end
	return count
end
function isAliveBuilding(unit)
	return unit ~= nil and unit:IsAlive() and unit:IsBuilding()
end
function isBaseDefenseActive()
	return DotaTime() < (baseDefenseUntil or -1)
end
function isDefendingOtherLane(bot, lane)
	local mode = bot:GetActiveMode()
	if lane == Lane.Top then
		return mode == BotMode.DefendTowerMid or mode == BotMode.DefendTowerBot
	end
	if lane == Lane.Mid then
		return mode == BotMode.DefendTowerTop or mode == BotMode.DefendTowerBot
	end
	if lane == Lane.Bot then
		return mode == BotMode.DefendTowerTop or mode == BotMode.DefendTowerMid
	end
	return false
end
function getWeightedEnemyCount(location, radius)
	local now = DotaTime()
	local cacheKey = locationRadiusKey(location, radius)
	local cached = enemyCountCache[cacheKey]
	if cached and now - cached.t <= enemyCountCacheSeconds then
		return cached.count
	end
	local unitLists = getUnitLists()
	local weightedCount = 0
	-- Heroes and creeps both count. The list used to be heroes only, so the creep
	-- weights below never applied and a creep wave read as 0.
	local units = {}
	for _, unit in ipairs(unitLists.enemyHeroes) do
		units[#units + 1] = unit
	end
	for _, unit in ipairs(unitLists.enemyCreeps) do
		units[#units + 1] = unit
	end
	for _, unit in ipairs(units) do
		if Fu.IsValid(unit) and GetUnitToLocationDistance(unit, location) <= radius then
			local unitName = unit:GetUnitName() or ""
			if Fu.IsValidHero(unit) and not Fu.IsSuspiciousIllusion(unit) then
				weightedCount = weightedCount + (Fu.IsCore(unit) and 1 or 0.5)
			elseif string.find(unitName, "upgraded_mega", 1, true) ~= nil then
				weightedCount = weightedCount + 0.6
			elseif string.find(unitName, "upgraded", 1, true) ~= nil then
				weightedCount = weightedCount + 0.4
			elseif string.find(unitName, "siege", 1, true) ~= nil then
				weightedCount = weightedCount + 0.5
			elseif
				string.find(unitName, "warlock_golem", 1, true) ~= nil
				or string.find(unitName, "lone_druid_bear", 1, true) ~= nil
			then
				weightedCount = weightedCount + 1
			elseif
				unit:IsCreep()
				or unit:IsAncientCreep()
				or unit:IsDominated()
				or unit:HasModifier("modifier_chen_holy_persuasion")
				or unit:HasModifier("modifier_dominated")
			then
				weightedCount = weightedCount + 0.2
			end
		end
	end
	weightedCount = math.floor(weightedCount)
	enemyCountCache[cacheKey] = { t = now, count = weightedCount }
	return weightedCount
end
-- Plain count of enemy creeps and summons near a spot, no weights.
local function CountEnemyCreepsNear(loc, radius)
	if loc == nil then
		return 0
	end
	local count = 0
	for _, unit in ipairs(getUnitLists().enemyCreeps) do
		if Fu.IsValid(unit) and unit:IsAlive() and GetUnitToLocationDistance(unit, loc) <= radius then
			count = count + 1
		end
	end
	return count
end
-- Records why a lane's defend desire came back zero, for the [OHA-DEFEND] log.
local function DefNone(bot, why)
	bot._defendWhy = why
	return BotModeDesire.None
end
local BASE_CREEP_RADIUS = 1400
-- Our base is being hit: heroes at the Ancient or on high ground, the Ancient
-- below 95%, or a creep wave at the T4s.
local function ReadBaseThreat(gameState)
	local ourAncient = gameState.ourAncient
	local threat = {
		exposed = false,
		ancHP = gameState.ancientHP or 1,
		heroes = gameState.enemiesAtAncient or 0,
		hg = gameState.enemiesOnHG or 0,
		creeps = 0,
		t4 = 0,
	}
	if ourAncient == nil or not ourAncient:IsAlive() then
		return threat
	end
	threat.creeps = CountEnemyCreepsNear(ourAncient:GetLocation(), BASE_CREEP_RADIUS)
	for _, id in ipairs({ TOWER_BASE_1, TOWER_BASE_2 }) do
		local tower = GetTower(gameState.team, id)
		if tower ~= nil and tower:IsAlive() then
			threat.t4 = threat.t4 + 1
		end
	end
	threat.exposed = threat.heroes >= 1 or threat.hg >= 1 or threat.ancHP < 0.95 or threat.creeps >= 2
	return threat
end
function getMostThreatenedLane()
	local lanes = { Lane.Top, Lane.Mid, Lane.Bot }
	local bestLane = lanes[1]
	local bestScore = -1
	for _, lane in ipairs(lanes) do
		local building, healthScore, tier = unpack(Defend.GetFurthestBuildingOnLane(lane))
		local location = isAliveBuilding(building) and tier < 3 and building:GetLocation()
			or getHighGroundWaitPoint(ourTeam, lane)
		local heroCount = countRecentlySeenEnemies(location, 1800)
		local score = heroCount * 10
		if heroCount == 0 then
			local creepScore = math.min(getWeightedEnemyCount(location, 1200) * 0.4, 0.9)
			score = score + creepScore
		end
		if score > bestScore then
			bestScore = score
			bestLane = lane
		end
	end
	if DotaTime() <= threatLaneLock["until"] and threatLaneLock.lane ~= bestLane then
		if bestScore >= 10 then
			threatLaneLock = { lane = bestLane, ["until"] = DotaTime() + 3 }
			return bestLane
		end
		return threatLaneLock.lane
	end
	threatLaneLock = { lane = bestLane, ["until"] = DotaTime() + 3 }
	return bestLane
end
-- Lane of a base threat: most enemy heroes last seen (8s) within 2200 of that lane's high-ground
-- spot (getHighGroundWaitPoint: in front of the T3 / barracks). Kept 20s when they drop out of sight, so a Dire push
-- that steps into fog does not hand the base to the first lane in the list (top); creep-only
-- threats fall back to the getMostThreatenedLane() lane.
local baseLaneMem = { lane = nil, t = -999 }
local function BaseThreatLane(team, fallback)
	local best, bestN = nil, 0
	for _, lane in ipairs({ Lane.Top, Lane.Mid, Lane.Bot }) do
		local loc = getHighGroundWaitPoint(team, lane)
		if loc ~= nil then
			local heroCount = countRecentlySeenEnemies(loc, 2200, 8)
			if heroCount > bestN then
				best, bestN = lane, heroCount
			end
		end
	end
	if best ~= nil then
		baseLaneMem = { lane = best, t = DotaTime() }
		return best, "seen"
	end
	if baseLaneMem.lane ~= nil and DotaTime() - baseLaneMem.t <= 20 then
		return baseLaneMem.lane, "remembered"
	end
	return fallback, "fallback"
end
local laneNames = { [Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot" }
-- Base siege: 3+ enemy heroes seen (last 5s) within 1800 of one of our T3s, barracks, T4s or the
-- Ancient. Kept for 10s after the last sighting, since vision on them flickers (game 037, t=1567-1572:
-- hg=5, then Hoodwink TP'd out to farm). Shared in Fu.Utils.GameStates.baseSiege, read by farm and
-- by the TP rules in ability_item_usage_generic.
local BASE_SIEGE_HEROES = 3
local BASE_SIEGE_HOLD = 10
local function BaseSiegeBuildings(team)
	local list = {}
	for _, entry in ipairs({
		{ GetTower(team, Tower.Top3), Lane.Top },
		{ GetTower(team, Tower.Mid3), Lane.Mid },
		{ GetTower(team, Tower.Bot3), Lane.Bot },
		{ GetBarracks(team, Barracks.TopMelee), Lane.Top },
		{ GetBarracks(team, Barracks.TopRanged), Lane.Top },
		{ GetBarracks(team, Barracks.MidMelee), Lane.Mid },
		{ GetBarracks(team, Barracks.MidRanged), Lane.Mid },
		{ GetBarracks(team, Barracks.BotMelee), Lane.Bot },
		{ GetBarracks(team, Barracks.BotRanged), Lane.Bot },
		{ GetTower(team, Tower.Base1), nil },
		{ GetTower(team, Tower.Base2), nil },
		{ GetAncient(team), nil },
	}) do
		if isAliveBuilding(entry[1]) then
			list[#list + 1] = entry
		end
	end
	return list
end
function Defend.GetBaseSiege()
	Fu.Utils.GameStates = Fu.Utils.GameStates or {}
	local states = Fu.Utils.GameStates
	local now = DotaTime()
	if now - (states.baseSiegeCheckAt or -99) >= 0.5 then
		states.baseSiegeCheckAt = now
		local best, bestEntry = 0, nil
		for _, entry in ipairs(BaseSiegeBuildings(GetTeam())) do
			local n = countRecentlySeenEnemies(entry[1]:GetLocation(), 1800, 5)
			if n > best then
				best, bestEntry = n, entry
			end
		end
		if best >= BASE_SIEGE_HEROES and bestEntry ~= nil then
			states.baseSiege = { n = best, loc = bestEntry[1]:GetLocation(), lane = bestEntry[2], at = now }
		end
	end
	local siege = states.baseSiege
	if siege ~= nil and now - siege.at <= BASE_SIEGE_HOLD then
		return siege
	end
	return nil
end
-- Where heroes gather before taking on a siege: 900 from our Ancient toward the fountain (the T4s).
local function GroupUpPoint(team)
	local ancient = GetAncient(team)
	if ancient == nil then
		return nil
	end
	return Fu.AdjustLocationWithOffsetTowardsFountain(ancient:GetLocation(), 900)
end
-- Game 037, 24:09-27:28 (15-2): heroes went into the siege one at a time, by TP, by walking from
-- the fountain after respawn, and from the jungle. A bot away from the siege (over 1800 from it)
-- waits at the group point until 3 allies are with him (him included, within 1600 of him or of the
-- point), or 2 allies are already at the siege or teleporting to it.
local function SiegeGroupUp(bot, siege)
	local point = GroupUpPoint(GetTeam())
	if point == nil or GetUnitToLocationDistance(bot, siege.loc) <= 1800 then
		return nil
	end
	local grouped, engaged = 1, 0
	for i = 1, #GetTeamPlayers(GetTeam()) do
		local ally = GetTeamMember(i)
		if ally ~= nil and ally ~= bot and ally:IsAlive() and not ally:IsIllusion() then
			if GetUnitToUnitDistance(ally, bot) <= 1600 or GetUnitToLocationDistance(ally, point) <= 1600 then
				grouped = grouped + 1
			elseif GetUnitToLocationDistance(ally, siege.loc) <= 1800 then
				engaged = engaged + 1
			end
		end
	end
	for _, playerId in ipairs(Fu.Utils.GetAllyIdsInTpToLocation(siege.loc, 2500)) do
		if playerId ~= bot:GetPlayerID() then
			engaged = engaged + 1
		end
	end
	if grouped >= 3 or engaged >= 2 then
		return nil
	end
	return { point = point, grouped = grouped, engaged = engaged }
end
local GROUP_UP_DESIRE = 0.7
function getClosestPosition(positions, location)
	local closestPosition = nil
	local closestDistance = math.huge
	do
		local i = 1
		while i <= 5 do
			local member = GetTeamMember(i)
			if Fu.IsValidHero(member) then
				local position = Fu.GetPosition(member)
				do
					local j = 1
					while j <= #positions do
						-- Was positions[j + 1]: skipped the first position in the list (pos 4 in { 4, 5, 3 }).
						if position == positions[j] then
							local distance = GetUnitToLocationDistance(member, location)
							if distance < closestDistance then
								closestDistance = distance
								closestPosition = position
							end
						end
						j = j + 1
					end
				end
			end
			i = i + 1
		end
	end
	return closestPosition or positions[1]
end
function Defend.GetFurthestBuildingOnLane(lane)
	local cacheKey = CacheKeys.FURTHEST_BUILDING + ourTeam * 10 + (lane or 0)
	local cached = Fu.Utils.GetCachedVars(cacheKey, 1)
	if cached ~= nil then
		return cached
	end
	local result = Defend.GetFurthestBuildingOnLaneHelper(lane)
	Fu.Utils.SetCachedVars(cacheKey, result)
	return result
end
function Defend.GetFurthestBuildingOnLaneHelper(lane)
	local team = ourTeam
	local building
	local function remapHealth(unit, fromMin, fromMax, toMin, toMax)
		local healthRatio = unit:GetHealth() / unit:GetMaxHealth()
		return RemapValClamped(healthRatio, fromMin, fromMax, toMin, toMax)
	end
	if lane == Lane.Top then
		building = GetTower(team, Tower.Top1)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 0.5, 1), 1 }
		end
		building = GetTower(team, Tower.Top2)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 1, 2), 2 }
		end
		building = GetTower(team, Tower.Top3)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 1.5, 2), 3 }
		end
		building = GetBarracks(team, Barracks.TopMelee)
		if isAliveBuilding(building) then
			return { building, 2.5, 3 }
		end
		building = GetBarracks(team, Barracks.TopRanged)
		if isAliveBuilding(building) then
			return { building, 2.5, 3 }
		end
		building = GetTower(team, Tower.Base1)
		if isAliveBuilding(building) then
			return { building, 2.5, 4 }
		end
		building = GetTower(team, Tower.Base2)
		if isAliveBuilding(building) then
			return { building, 2.5, 4 }
		end
		building = GetAncient(team)
		if isAliveBuilding(building) then
			return { building, 3, 5 }
		end
	elseif lane == Lane.Mid then
		building = GetTower(team, Tower.Mid1)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 0.5, 1), 1 }
		end
		building = GetTower(team, Tower.Mid2)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 1, 2), 2 }
		end
		building = GetTower(team, Tower.Mid3)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 1.5, 2), 3 }
		end
		building = GetBarracks(team, Barracks.MidMelee)
		if isAliveBuilding(building) then
			return { building, 2.5, 3 }
		end
		building = GetBarracks(team, Barracks.MidRanged)
		if isAliveBuilding(building) then
			return { building, 2.5, 3 }
		end
		building = GetTower(team, Tower.Base1)
		if isAliveBuilding(building) then
			return { building, 2.5, 4 }
		end
		building = GetTower(team, Tower.Base2)
		if isAliveBuilding(building) then
			return { building, 2.5, 4 }
		end
		building = GetAncient(team)
		if isAliveBuilding(building) then
			return { building, 3, 5 }
		end
	else
		building = GetTower(team, Tower.Bot1)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 0.5, 1), 1 }
		end
		building = GetTower(team, Tower.Bot2)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 1, 2), 2 }
		end
		building = GetTower(team, Tower.Bot3)
		if isAliveBuilding(building) then
			return { building, remapHealth(building, 0.25, 1, 1.5, 2), 3 }
		end
		building = GetBarracks(team, Barracks.BotMelee)
		if isAliveBuilding(building) then
			return { building, 2.5, 3 }
		end
		building = GetBarracks(team, Barracks.BotRanged)
		if isAliveBuilding(building) then
			return { building, 2.5, 3 }
		end
		building = GetTower(team, Tower.Base1)
		if isAliveBuilding(building) then
			return { building, 2.5, 4 }
		end
		building = GetTower(team, Tower.Base2)
		if isAliveBuilding(building) then
			return { building, 2.5, 4 }
		end
		building = GetAncient(team)
		if isAliveBuilding(building) then
			return { building, 3, 5 }
		end
	end
	return { nil, 1, 0 }
end
function noOtherTravelBootsDefender(bot)
	local unitLists = getUnitLists()
	for _, member in ipairs(unitLists.teamMembers) do
		if bot ~= member and Fu.IsValidHero(member) and member.travel_boots_defender == true then
			return false
		end
	end
	return true
end
-- Where each lane's T3 stands, remembered after it falls (#53: the rim the bots hold once the T3 is down, game 068
-- 52:30). Read while the T3 is alive (the defend reads call this from the start of the game).
local tier3Spots = {}
local tier3TowerIds = { [Lane.Top] = Tower.Top3, [Lane.Mid] = Tower.Mid3, [Lane.Bot] = Tower.Bot3 }
local function Tier3Spot(team, lane)
	tier3Spots[team] = tier3Spots[team] or {}
	-- All three lanes on every read, so a lane is known before its own defence first asks.
	for spotLane, id in pairs(tier3TowerIds) do
		local tower = GetTower(team, id)
		if Fu.IsValidBuilding(tower) then
			tier3Spots[team][spotLane] = tower:GetLocation()
		end
	end
	return tier3Spots[team][lane]
end
local laneBarracksIds = {
	[Lane.Top] = { Barracks.TopMelee, Barracks.TopRanged },
	[Lane.Mid] = { Barracks.MidMelee, Barracks.MidRanged },
	[Lane.Bot] = { Barracks.BotMelee, Barracks.BotRanged },
}
-- The high-ground wait point (the rim): 250 behind the lane's T3 toward our Ancient; after the T3 falls, where it stood.
-- It used to move to a barracks, and with both barracks down to our lane front + 600, which can be mid-map (#53).
-- A barracks only when the T3 was never seen.
function getHighGroundWaitPoint(team, lane)
	local ancient = GetAncient(team)
	local anchorLocation = Tier3Spot(team, lane)
	if anchorLocation == nil then
		for _, id in ipairs(laneBarracksIds[lane] or {}) do
			local barracks = GetBarracks(team, id)
			if anchorLocation == nil and Fu.IsValidBuilding(barracks) then
				anchorLocation = barracks:GetLocation()
			end
		end
	end
	if anchorLocation ~= nil and ancient ~= nil then
		local ancientLocation = ancient:GetLocation()
		local direction = Vector(ancientLocation.x - anchorLocation.x, ancientLocation.y - anchorLocation.y, 0)
		local length = math.max(1, math.sqrt(direction.x * direction.x + direction.y * direction.y))
		return Vector(anchorLocation.x + direction.x / length * 250, anchorLocation.y + direction.y / length * 250, 0)
	end
	return Fu.AdjustLocationWithOffsetTowardsFountain(GetLaneFrontLocation(team, lane, 0), 600)
end
local DefendLaneRules = require(GetScriptDirectory() .. "/FuncLib/systems/defend_lane_rules")
-- #53: every enemy creep with its lane (DefendLaneRules.CreepLane: "base" by our Ancient, else the lane whose path is
-- nearest), read once a second for the team. Game 068, 41:40: with mid and bottom both down to the T4s, the old count
-- (creeps within 1600 of each enemy lane front) counted the same creeps for both lanes.
local creepLaneCache = { at = -99, list = {} }
local creepLaneIds = { Lane.Top, Lane.Mid, Lane.Bot }
local function EnemyCreepLanes()
	local now = DotaTime()
	if now - creepLaneCache.at < 1 then
		return creepLaneCache.list
	end
	local ancient = GetAncient(ourTeam)
	local list = {}
	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS) or {}) do
		if Fu.IsValid(unit) then
			local location = unit:GetLocation()
			local distances = {}
			for _, lane in ipairs(creepLaneIds) do
				local along = GetAmountAlongLane(lane, location)
				distances[lane] = along ~= nil and along.distance or nil
			end
			local ancientDist = ancient ~= nil and GetUnitToUnitDistance(unit, ancient) or nil
			list[#list + 1] = { unit = unit, lane = DefendLaneRules.CreepLane(distances, creepLaneIds, ancientDist) }
		end
	end
	creepLaneCache = { at = now, list = list }
	return list
end
-- The lane's furthest building and its tier. Read again when the cached one (1s) has died, so a lane whose building
-- just fell doesn't read tier 0 (game 068 t=2457: bottom read tier 0 and lost the lane pick to mid).
local function LaneBuildingEntry(lane)
	local entry = Defend.GetFurthestBuildingOnLane(lane)
	local building = entry ~= nil and entry[1] or nil
	if building ~= nil and not building:IsAlive() then
		entry = Defend.GetFurthestBuildingOnLaneHelper(lane)
		building = entry[1]
	end
	if building == nil or not building:IsAlive() then
		return nil, 0
	end
	return building, entry[3] or 0
end
-- HP ratio and tier of the lane's furthest building.
local function LaneBuilding(lane)
	local building, tier = LaneBuildingEntry(lane)
	if building == nil then
		return 1, 0
	end
	return building:GetHealth() / math.max(1, building:GetMaxHealth()), tier
end
-- Enemy creeps that threaten a lane: its own creeps within reach of its furthest building
-- (DefendLaneRules.ThreatRadius: 1600 for a T1 / T2, 2600 from a T3 on), and the base creeps once the lane is down to
-- the T4s. Each creep counts for one lane. Returns the count, the building's location (else the enemy lane front)
-- and the tier. Once a second per lane for the team.
local laneThreatCache = {}
local function LaneThreat(lane)
	local now = DotaTime()
	local cached = laneThreatCache[lane]
	if cached ~= nil and now - cached.at < 1 then
		return cached.creeps, cached.anchor, cached.tier
	end
	local building, tier = LaneBuildingEntry(lane)
	local anchor = building ~= nil and building:GetLocation() or nil
	local creeps = 0
	for _, entry in ipairs(EnemyCreepLanes()) do
		if Fu.IsValid(entry.unit) then
			local anchorDist = anchor ~= nil and GetUnitToLocationDistance(entry.unit, anchor) or nil
			if DefendLaneRules.CountsForLane(entry.lane, lane, tier, anchorDist) then
				creeps = creeps + 1
			end
		end
	end
	anchor = anchor or GetLaneFrontLocation(GetOpposingTeam(), lane, 0)
	laneThreatCache[lane] = { at = now, creeps = creeps, anchor = anchor, tier = tier }
	return creeps, anchor, tier
end
function Defend.ShouldDefend(bot, building, radius)
	if not isAliveBuilding(building) then
		return false
	end
	local gameState = getGameState()
	local heroThreat = 0
	for _, playerId in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
		if IsHeroAlive(playerId) then
			local lastSeenInfo = GetHeroLastSeenInfo(playerId)
			if lastSeenInfo ~= nil then
				local lastSeen = lastSeenInfo[1]
				if
					lastSeen ~= nil
					and lastSeen.time_since_seen <= lastSeenSeconds
					and GetUnitToLocationDistance(building, lastSeen.location) <= 1600
				then
					heroThreat = heroThreat + 1
				end
			end
		end
	end
	local unitLists = getUnitLists()
	local creepThreat = 0
	for _, unit in ipairs(unitLists.enemyCreeps) do
		if Fu.IsValid(unit) and GetUnitToUnitDistance(building, unit) <= radius then
			local unitName = unit:GetUnitName()
			-- NOTE: a table literal is never nil, so these tests do not do what they say: every
			-- creep lands in the upgraded_mega branch (0.6). Left as is on purpose, since the
			-- current tower defense is tuned around that count.
			if { string.find(unitName, "siege") } ~= nil and { string.find(unitName, "upgraded") } == nil then
				creepThreat = creepThreat + 0.5
			elseif { string.find(unitName, "upgraded_mega") } ~= nil then
				creepThreat = creepThreat + 0.6
			elseif { string.find(unitName, "upgraded") } ~= nil then
				creepThreat = creepThreat + 0.4
			elseif
				{ string.find(unitName, "warlock_golem") } ~= nil
				or { string.find(unitName, "shadow_shaman_ward") } ~= nil
			then
				creepThreat = creepThreat + 1
			elseif { string.find(unitName, "lone_druid_bear") } ~= nil then
				heroThreat = heroThreat + 1
			elseif
				unit:IsCreep()
				or unit:IsAncientCreep()
				or unit:IsDominated()
				or unit:HasModifier("modifier_chen_holy_persuasion")
				or unit:HasModifier("modifier_dominated")
			then
				creepThreat = creepThreat + 0.2
			end
		end
	end
	local threatCount = heroThreat + math.floor(creepThreat)
	local position = Fu.GetPosition(bot)
	local shouldDefend = false
	if threatCount == 1 then
		if position == 2 or position == 3 or position == getClosestPosition({ 4, 5 }, building:GetLocation()) then
			shouldDefend = true
		end
	elseif threatCount == 2 then
		if
			position == 2
			or position == 3
			or position == getClosestPosition({ 4, 5 }, building:GetLocation())
			or position == 1 and GetUnitToUnitDistance(bot, building) <= 3200
		then
			shouldDefend = true
		end
	elseif threatCount == 3 then
		if
			position == 2
			or position == 3
			or position == 4
			or position == 5
			or position == 1 and GetUnitToUnitDistance(bot, building) <= 3200
		then
			shouldDefend = true
		end
	elseif threatCount >= 4 then
		shouldDefend = true
	end
	if not shouldDefend then
		if DotaTime() - travelBootsDefenderTime >= 20 then
			bot.travel_boots_defender = false
		end
		if
			bot:GetUnitName() == "npc_dota_hero_tinker"
			and bot:GetLevel() >= 6
			and Fu.CanCastAbility(bot:GetAbilityByName("tinker_keen_teleport"))
			and noOtherTravelBootsDefender(bot)
		then
			bot.travel_boots_defender = true
			travelBootsDefenderTime = DotaTime()
			shouldDefend = true
		else
			local travelBoots = Fu.GetItem2(bot, "item_travel_boots") or Fu.GetItem2(bot, "item_travel_boots_2")
			if Fu.CanCastAbility(travelBoots) and noOtherTravelBootsDefender(bot) then
				bot.travel_boots_defender = true
				travelBootsDefenderTime = DotaTime()
				shouldDefend = true
			end
		end
		if not shouldDefend and position == getClosestPosition({ 2, 3 }, building:GetLocation()) then
			shouldDefend = true
		end
	end
	local recentlyDamaged = bot:WasRecentlyDamagedByAnyHero(5)
	if recentlyDamaged and shouldDefend then
		local closestPosition = getClosestPosition({ 2, 3, 4, 5 }, building:GetLocation())
		if Fu.GetPosition(bot) ~= closestPosition then
			return false
		end
	end
	return shouldDefend
end
function pingForDefense(bot, lane, desire, building, tier, alliesComing, enemyCount)
	local gameState = getGameState()
	if gameState.isLaningPhase or gameState.aliveAllyCount == 0 then
		return
	end
	if not isAliveBuilding(building) then
		return
	end
	if tier < 2 or desire <= 0.5 then
		return
	end
	if not Defend.ShouldDefend(bot, building, 1600) then
		return
	end
	Fu.Utils.GameStates = Fu.Utils.GameStates or {}
	Fu.Utils.GameStates.defendPings = Fu.Utils.GameStates.defendPings or { pingedTime = GameTime() }
	local defendPings = Fu.Utils.GameStates.defendPings
	if alliesComing >= 1 and alliesComing >= enemyCount then
		return
	end
	if GameTime() - defendPings.pingedTime <= 6 then
		return
	end
	local pingLocation =
		vectorAdd(Fu.AdjustLocationWithOffsetTowardsFountain(building:GetLocation(), 850), RandomVector(50))
	local retreatingAllies = Fu.GetRetreatingAlliesNearLoc(pingLocation, 1600)
	if #retreatingAllies == 0 then
		bot:ActionImmediate_Chat(Localization.Get("say_come_def"), false)
		bot:ActionImmediate_Ping(pingLocation.x, pingLocation.y, false)
		defendPings.pingedTime = GameTime()
		defendPings.lane = lane
	end
end
function Defend.GetDefendDesireHelper(bot, lane)
	if bot.DefendLaneDesire == nil then
		bot.DefendLaneDesire = {}
	end
	if bot._defendCommitLane == nil then
		bot._defendCommitLane = 0
	end
	if bot._defendCommitUntil == nil then
		bot._defendCommitUntil = 0
	end
	local gameState = getGameState()
	local laneState = getLaneState()
	local team = gameState.team
	local ourAncient = gameState.ourAncient
	local commitLane = bot._defendCommitLane
	local commitUntil = bot._defendCommitUntil
	local candidates = {}
	for _, candidateLane in ipairs({ Lane.Top, Lane.Mid, Lane.Bot }) do
		local laneDesire = GetDefendLaneDesire(candidateLane)
		if laneDesire > 0.1 then
			local laneFront = laneState.laneFronts[candidateLane]
			local distance = GetUnitToLocationDistance(bot, laneFront)
			local enemyCount = #Fu.GetLastSeenEnemiesNearLoc(laneFront, 2500)
			local building, healthScore, tier = unpack(Defend.GetFurthestBuildingOnLane(candidateLane))
			local tierWeight = tier >= 5 and 3 or (tier >= 4 and 2.5 or (tier >= 3 and 2 or (tier >= 2 and 1.5 or 1)))
			candidates[#candidates + 1] = {
				lane = candidateLane,
				desire = laneDesire * tierWeight,
				dist = distance,
				enemies = enemyCount,
				tier = tier,
			}
		end
	end
	if #candidates >= 2 then
		arraySort(candidates, function(_, left, right)
			if left.desire ~= right.desire then
				return right.desire - left.desire
			end
			return left.dist - right.dist
		end)
		local priorityLane = candidates[1].lane
		if commitLane ~= 0 and DotaTime() < commitUntil and lane ~= commitLane then
			local committedCandidate = arrayFind(candidates, function(_, candidate)
				return candidate.lane == commitLane
			end)
			local thisCandidate = arrayFind(candidates, function(_, candidate)
				return candidate.lane == lane
			end)
			if
				thisCandidate
				and committedCandidate
				and thisCandidate.tier > committedCandidate.tier
				and thisCandidate.enemies >= 1
			then
				bot._defendCommitLane = lane
				bot._defendCommitUntil = DotaTime() + 5
			else
				return DefNone(bot, "committed-other")
			end
		elseif lane ~= priorityLane then
			bot._defendCommitLane = priorityLane
			bot._defendCommitUntil = DotaTime() + 5
			return DefNone(bot, "other-lane")
		else
			bot._defendCommitLane = priorityLane
			bot._defendCommitUntil = DotaTime() + 5
		end
	elseif DotaTime() >= commitUntil then
		bot._defendCommitLane = 0
	end
	local defendState = getDefendState(bot)
	defendState.defendLoc = laneState.laneFronts[lane]
	local distanceToDefendLoc = GetUnitToLocationDistance(bot, defendState.defendLoc)
	local botLevel = bot:GetLevel()
	if
		bot:GetAssignedLane() ~= lane
		and distanceToDefendLoc > 3000
		and (
			Fu.GetPosition(bot) == 1 and botLevel < 7
			or Fu.GetPosition(bot) == 2 and botLevel < 7
			or Fu.GetPosition(bot) == 3 and botLevel < 6
			or Fu.GetPosition(bot) == 4 and botLevel < 4
			or Fu.GetPosition(bot) == 5 and botLevel < 4
		)
	then
		return DefNone(bot, "level")
	end
	if botLevel < 3 then
		return DefNone(bot, "level")
	end
	if gameState.isLaningPhase and bot:GetAssignedLane() == lane then
		local enemiesNearDefendLoc = Fu.GetLastSeenEnemiesNearLoc(defendState.defendLoc, 1200)
		if #enemiesNearDefendLoc <= 1 then
			return DefNone(bot, "laning")
		end
	end
	local isGroupPushing = false
	local activeMode = bot:GetActiveMode()
	local isPushing = activeMode == BotMode.PushTowerTop
		or activeMode == BotMode.PushTowerMid
		or activeMode == BotMode.PushTowerBot
	if isPushing then
		local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1600)
		local nearbyEnemies = Fu.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 1400)
		if #nearbyAllies >= #nearbyEnemies then
			local pushingAllies = 0
			for _, ally in ipairs(nearbyAllies) do
				if Fu.IsValidHero(ally) and ally:GetActiveMode() == activeMode then
					pushingAllies = pushingAllies + 1
					if pushingAllies >= 3 then
						isGroupPushing = true
						break
					end
				end
			end
		end
	end
	local recentlyDamaged = bot:WasRecentlyDamagedByAnyHero(5) or bot:WasRecentlyDamagedByTower(5)
	local threatLane = getMostThreatenedLane()
	local enemiesOnHG = gameState.enemiesOnHG
	local enemiesAtAncient = gameState.enemiesAtAncient
	-- Three allies pushing together keep pushing, unless our own base is being hit.
	-- A creep wave at the T4s used to lose the Ancient while the group pushed.
	local baseThreat = ReadBaseThreat(gameState)
	local baseHit = baseThreat.ancHP < 0.95 or baseThreat.creeps >= 2 or enemiesAtAncient >= 1
	if isGroupPushing and enemiesOnHG < 2 and not baseHit then
		return DefNone(bot, "push-group")
	end
	local ancientLow = ourAncient and ourAncient:IsAlive() and gameState.ancientHP < 0.4
	-- Last stand: enemy heroes at our Ancient while it is hurt or both T4s are gone. Game 036,
	-- 55:00-55:28: defend read 0.30-0.46 ("ancient-heroes", capped at maxDefendDesire) and 0.06-0.12 for Ogre
	-- ("hg-outnumbered"), and the Ancient fell from 0.77 to 0.13 with all five Radiant alive.
	-- Then: no outnumbered cut, no half desire, and the desire may reach 0.9 (above farm, push and
	-- most retreat rules; attack at 0.95 still fights). Not for a bot under 30% HP.
	local lastStand = ourAncient
		and ourAncient:IsAlive()
		and enemiesAtAncient >= 1
		and (gameState.ancientHP < 0.95 or baseThreat.t4 == 0)
		and Fu.GetHP(bot) >= 0.3
	local lastStandDesire = 0.9
	if lastStand and DotaTime() >= (bot._ancLastStandLogAt or -999) then
		bot._ancLastStandLogAt = DotaTime() + 5
		pcall(
			print,
			string.format(
				"[OHA-DEFEND] t=%.0f %s ancient-last-stand lane=%s anc=%.2f heroesAtAnc=%d t4=%d hp=%.2f",
				DotaTime(),
				(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
				tostring(laneNames[lane]),
				gameState.ancientHP or -1,
				enemiesAtAncient,
				baseThreat.t4,
				Fu.GetHP(bot)
			)
		)
	end
	-- Group up before taking on a base siege (SiegeGroupUp). 0.7: above the 0.65 attack "follow ally"
	-- that pulled heroes in from 2000-4000 away, and above farm's usual 0.6.
	local siege = Defend.GetBaseSiege()
	if siege ~= nil and not lastStand and not ancientLow and Fu.GetHP(bot) >= 0.3 then
		local group = SiegeGroupUp(bot, siege)
		if group ~= nil then
			local siegeLane = siege.lane or threatLane
			bot._defendGroupUpUntil = DotaTime() + 1
			bot._defendGroupUpPoint = group.point
			if DotaTime() >= (bot._groupUpLogAt or -999) then
				bot._groupUpLogAt = DotaTime() + 5
				pcall(
					print,
					string.format(
						"[OHA-DEFEND] t=%.0f %s group-up lane=%s siege=%d at=%.0f,%.0f grouped=%d engaged=%d dist=%d fountainDist=%d",
						DotaTime(),
						(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
						tostring(laneNames[siegeLane]),
						siege.n,
						siege.loc.x,
						siege.loc.y,
						group.grouped,
						group.engaged,
						math.floor(GetUnitToLocationDistance(bot, group.point)),
						math.floor(bot:DistanceFromFountain())
					)
				)
			end
			if lane ~= siegeLane then
				return DefNone(bot, "group-up-other-lane")
			end
			defendState.defendLoc = group.point
			bot.laneToDefend = lane
			bot._defendWhy = "group-up"
			return GROUP_UP_DESIRE
		end
	end
	local outnumbered = not ancientLow
		and not lastStand
		and gameState.aliveEnemyCount >= 3
		and gameState.aliveEnemyCount > gameState.aliveAllyCount + 1
	local outnumberedDesire = maxDefendDesire * 0.5
	if enemiesOnHG >= 1 and not lastStand then
		local nearbyEnemies = Fu.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 2000)
		if #nearbyEnemies >= 2 then
			local alliesNearby = 0
			for _, ally in ipairs(Fu.GetAlliesNearLoc(bot:GetLocation(), 1600)) do
				if Fu.IsValidHero(ally) and ally ~= bot then
					alliesNearby = alliesNearby + 1
				end
			end
			local weAreStronger = Fu.WeAreStronger(bot, 2500)
			if not weAreStronger and #nearbyEnemies >= alliesNearby then
				bot._defendWhy = "hg-outnumbered"
				return lane == threatLane and maxDefendDesire * 0.2 or maxDefendDesire * 0.1
			end
		end
	end
	local baseFloor = { active = false, floor = 0 }
	-- Lane creeps hit the Ancient or the T4s with no hero nearby. Only the closest bot answers.
	local ancientCreeps = baseThreat.creeps
	if ourAncient and ourAncient:IsAlive() then
		local ancientHP = gameState.ancientHP
		local defendersAtAncient = gameState.defendersAtAncient
		local heroFloor = lane == threatLane and (outnumbered and outnumberedDesire or maxDefendDesire)
			or (outnumbered and outnumberedDesire * 0.7 or maxDefendDesire * 0.7)
		local creepFloor = lane == threatLane and maxDefendDesire * 0.9 or maxDefendDesire * 0.6
		if enemiesAtAncient >= 2 or enemiesAtAncient >= 1 and ancientHP < 0.95 then
			local defendersNeeded = enemiesAtAncient + 1
			if defendersAtAncient < defendersNeeded then
				baseDefenseUntil = DotaTime() + baseDefenseSeconds
				baseFloor = {
					active = true,
					floor = heroFloor,
					forceLoc = Fu.AdjustLocationWithOffsetTowardsFountain(ourAncient:GetLocation(), 300),
				}
				if lane == threatLane then
					bot.laneToDefend = lane
				end
			end
		elseif enemiesAtAncient == 0 and (ancientHP < 0.95 or ancientCreeps >= 2) then
			-- defendersAtAncient counts every ally within 2500 of the Ancient, this bot included. A hero who
			-- just respawned is ~1800 away, so it counted itself as the defender already there
			-- and walked out to farm while creeps hit the base.
			local selfAtBase = GetUnitToUnitDistance(bot, ourAncient) <= 3500
			local others = defendersAtAncient - ((GetUnitToUnitDistance(bot, ourAncient) <= 2500) and 1 or 0)
			local position = Fu.GetPosition(bot)
			local closestPosition = getClosestPosition({ 4, 5, 3 }, ourAncient:GetLocation())
			-- A full wave (5+) or a hurt Ancient needs more than the one closest support.
			local bigWave = ancientCreeps >= 5 or ancientHP < 0.85
			local rest = {}
			for _, pos in ipairs({ 4, 5, 3 }) do
				if pos ~= closestPosition then
					rest[#rest + 1] = pos
				end
			end
			local secondB = getClosestPosition(rest, ourAncient:GetLocation())
			if
				selfAtBase
				or others <= 0 and position == closestPosition
				or bigWave and others <= 1 and position == secondB
			then
				baseFloor = {
					active = true,
					floor = creepFloor,
					forceLoc = Fu.AdjustLocationWithOffsetTowardsFountain(ourAncient:GetLocation(), 300),
				}
				if lane == threatLane then
					bot.laneToDefend = lane
				end
			end
		end
	end
	if lastStand then
		if not baseFloor.active then
			baseFloor = {
				active = true,
				floor = 0,
				forceLoc = Fu.AdjustLocationWithOffsetTowardsFountain(ourAncient:GetLocation(), 300),
			}
		end
		baseFloor.floor = math.max(baseFloor.floor, lastStandDesire)
		baseDefenseUntil = DotaTime() + baseDefenseSeconds
	end
	if enemiesOnHG >= 2 and not recentlyDamaged then
		baseDefenseUntil = DotaTime() + baseDefenseSeconds
		local hgFloor = outnumbered and outnumberedDesire
			or (lane == threatLane and maxDefendDesire or maxDefendDesire * 0.7)
		local hgDefendLoc = ourAncient and Fu.AdjustLocationWithOffsetTowardsFountain(ourAncient:GetLocation(), 300)
			or defendState.defendLoc
		if not baseFloor.active then
			baseFloor = { active = true, floor = hgFloor, forceLoc = hgDefendLoc }
		else
			baseFloor.floor = math.max(baseFloor.floor, hgFloor)
		end
		if lane == threatLane then
			bot.laneToDefend = lane
		end
	end
	-- Base under threat: only the threatened lane defends. Every other lane used to keep a 0.7 share
	-- of the base floor, so when the attacked lane dipped for a moment (game 036, 37:09: Radiant
	-- enemies at the bottom T3 out of sight, bot read 0 "no-threat", top 0.30 "base-floor"), Primal
	-- Beast's defend mode flipped to top and he TPed from the fountain to the top T2, chatting
	-- "Defending the base!". The bot then stays on the base lane: no "no-threat" exit below either.
	local baseLane = nil
	if baseFloor.active or enemiesAtAncient >= 2 then
		local why
		baseLane, why = BaseThreatLane(gameState.team, threatLane)
		if baseLane ~= nil and lane ~= baseLane then
			if DotaTime() >= (bot._baseLaneLogAt or -999) and not Fu.IsMeepoClone(bot) then
				bot._baseLaneLogAt = DotaTime() + 5
				pcall(
					print,
					string.format(
						"[OHA-DEFEND] t=%.0f %s base-lane=%s(%s) d8lane=%s hg=%d anc=%d skip=%s",
						DotaTime(),
						(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
						tostring(laneNames[baseLane]),
						why,
						tostring(laneNames[threatLane]),
						enemiesOnHG or 0,
						enemiesAtAncient or 0,
						tostring(laneNames[lane])
					)
				)
			end
			return DefNone(bot, "base-other-lane")
		end
		if baseLane ~= nil and baseLane ~= threatLane then
			-- The defend location and the lane to defend follow the threatened lane.
			bot.laneToDefend = baseLane
		end
	end
	local baseDefenseActive = isBaseDefenseActive()
	if ourAncient then
		if enemiesAtAncient >= 1 then
			baseDefenseUntil = DotaTime() + baseDefenseSeconds
		elseif baseDefenseActive then
			local weightedEnemies = getWeightedEnemyCount(ourAncient:GetLocation(), ancientThreatRadius)
			if weightedEnemies >= 2 then
				baseDefenseUntil = DotaTime() + 1.5
			end
		end
	end
	if baseFloor.active and baseFloor.forceLoc then
		defendState.defendLoc = baseFloor.forceLoc
	elseif baseDefenseActive and ourAncient and lane == threatLane then
		defendState.defendLoc = Fu.AdjustLocationWithOffsetTowardsFountain(ourAncient:GetLocation(), 300)
	end
	if baseDefenseActive then
		if lane ~= threatLane and not lastStand then
			bot._defendDesireHalved = true
		end
	else
		if Fu.Utils.GetLocationToLocationDistance(gameState.teamFountainTpPoint, defendState.defendLoc) < 3000 then
			local enemyLaneFront = laneState.enemyLaneFronts[lane]
			local enemiesNearFront = Fu.GetLastSeenEnemiesNearLoc(enemyLaneFront, 1600)
			local alliesNearFront = Fu.GetAlliesNearLoc(enemyLaneFront, 1600)
			if
				GetUnitToLocationDistance(bot, enemyLaneFront) > bot:GetAttackRange()
				and #enemiesNearFront <= #alliesNearFront + 1
			then
				defendState.defendLoc = enemyLaneFront
			end
		end
	end
	defendState.distanceToLane[lane] = GetUnitToLocationDistance(bot, defendState.defendLoc)
	defendState.nInRangeAlly = Fu.GetNearbyHeroes(bot, 1600, false, BotMode.None)
	defendState.nInRangeEnemy = Fu.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 1600)
	defendState.weAreStronger = Fu.WeAreStronger(bot, 2500)
	local position = Fu.GetPosition(bot)
	local isAssignedLane = bot:GetAssignedLane() == lane
	if
		not isAssignedLane and position == 1 and gameState.isLaningPhase
		or Fu.IsDoingRoshan(bot) and #Fu.GetAlliesNearLoc(Fu.GetCurrentRoshanLocation(), 2800) >= 3
		or Fu.IsDoingTormentor(bot)
			and (#Fu.GetAlliesNearLoc(Fu.GetTormentorLocation(team), 1600) >= 2 or #Fu.GetAlliesNearLoc(
				Fu.GetTormentorWaitingLocation(team),
				2500
			) >= 2)
			and enemiesAtAncient == 0
	then
		return DefNone(bot, "roshan-tormentor")
	end
	local pingDesire = 0
	local pingingHuman, ping = Fu.GetHumanPing()
	if pingingHuman and ping and not ping.normal_ping and DotaTime() > 0 then
		local isNearTower, pingLane = Fu.IsPingCloseToValidTower(gameState.team, ping, 800, 5)
		if isNearTower and lane == pingLane and GameTime() < ping.time + humanPingSeconds then
			bot.laneToDefend = lane
			pingDesire = maxDefendDesire
		end
	end
	local building, healthScore, tier = unpack(Defend.GetFurthestBuildingOnLane(lane))
	if not isAliveBuilding(building) then
		return DefNone(bot, "no-building")
	end
	if tier >= 4 and ourAncient and ourAncient:IsAlive() and enemiesAtAncient >= 2 then
		bot._defendWhy = "ancient-heroes"
		if lastStand then
			bot._defendWhy = "ancient-last-stand"
			return lastStandDesire
		end
		if outnumbered then
			return outnumberedDesire
		end
		return lane == threatLane and maxDefendDesire or maxDefendDesire * 0.7
	end
	local distanceToBuilding = GetUnitToUnitDistance(bot, building)
	local walkTime = distanceToBuilding / math.max(1, bot:GetCurrentMovementSpeed())
	local tpScroll = Fu.Utils.GetItemFromFullInventory(bot, "item_tpscroll")
	local canTp = Fu.CanCastAbility(tpScroll)
	local canFurionTeleport = Fu.CanCastAbility(bot:GetAbilityByName("furion_teleportation"))
	local canKeenTeleport = Fu.CanCastAbility(bot:GetAbilityByName("tinker_keen_teleport"))
	local canReach = canTp or canFurionTeleport or canKeenTeleport or walkTime <= 11
	local shouldDefend = Defend.ShouldDefend(bot, building, 1600)
	-- Creeps alone on our high ground (T3 or deeper, no enemy hero near). Any hero already
	-- there clears it; if nobody is, the closest support or anyone within 4000 comes. The
	-- old rule counted a creep as 0.2 (a 5-creep wave read as 1, needed 2) and only sent a
	-- support while no ally was near, itself included, so he arrived, quit, and came back.
	-- The wave counts from HG_WAVE_RADIUS (2600) out, not when it reaches the building, so a
	-- hero has time to walk there.
	if tier >= 3 and not baseFloor.active then
		local hgLoc = building:GetLocation()
		local hgRadius = Fu.Utils.HG_WAVE_RADIUS or 2600
		-- #53: this lane's creeps only (LaneThreat: each creep counts for the lane whose path it is nearest; the base
		-- creeps for a lane down to the T4s). Utils.CountHighGroundWave split them by the nearest T3 still standing.
		local hgCreeps = LaneThreat(lane)
		if hgCreeps >= 2 and #Fu.GetLastSeenEnemiesNearLoc(hgLoc, hgRadius) == 0 then
			local myDist = GetUnitToLocationDistance(bot, hgLoc)
			local others = #Fu.Utils.GetAllyIdsInTpToLocation(hgLoc, 2500)
			for _, ally in ipairs(Fu.GetAlliesNearLoc(hgLoc, 2500)) do
				if ally ~= bot then
					others = others + 1
				end
			end
			-- Rank among the living allied heroes by distance to the wave (1 = closest).
			local rank = 1
			for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
				if
					ally ~= bot
					and ally:IsAlive()
					and not ally:IsIllusion()
					and GetUnitToLocationDistance(ally, hgLoc) < myDist
				then
					rank = rank + 1
				end
			end
			-- A big wave (6+) or one already at the T4s / Ancient: 0.85, above farm, Roshan and
			-- rune (game 020, 64:23-64:40: 7-12 creeps on the Dire high ground with one T4 left,
			-- the only defender got 0.5 and every Dire hero stayed on attack, Roshan or farm).
			-- With nobody near, the closest ally always counts; with 8+ creeps the second
			-- closest comes too.
			local severe = hgCreeps >= 6 or tier >= 4
			local desire = severe and 0.85 or 0.5
			if
				myDist <= 2500
				or others == 0 and (Fu.GetPosition(bot) == getClosestPosition({ 4, 5, 3 }, hgLoc) or myDist <= 4000 or rank == 1)
				or hgCreeps >= 8 and others <= 1 and rank <= 2
			then
				bot._defendWhy = severe and "hg-creeps-big" or "hg-creeps"
				return desire
			end
		end
	end
	if not shouldDefend and baseLane == nil then
		local enemiesNearBuilding = Fu.GetLastSeenEnemiesNearLoc(building:GetLocation(), 1200)
		if
			not canReach and #enemiesNearBuilding == 0
			or #enemiesNearBuilding == 0 and #Fu.GetAlliesNearLoc(building:GetLocation(), 1600) >= 1
		then
			return DefNone(bot, "no-threat")
		end
	end
	local defendLocation = isAliveBuilding(building) and building:GetLocation()
		or GetLaneFrontLocation(ourTeam, lane, 0)
	local enemiesNearDefendLoc = Fu.GetLastSeenEnemiesNearLoc(defendLocation, 2500)
	local alliesNearDefendLoc = Fu.GetAlliesNearLoc(defendLocation, 2500)
	local alliesComing = #alliesNearDefendLoc + #Fu.Utils.GetAllyIdsInTpToLocation(defendLocation, 2500)
	local position = Fu.GetPosition(bot)
	local distanceToDefendLoc = GetUnitToLocationDistance(bot, defendLocation)
	local hasTpScroll = Fu.CanCastAbility(Fu.Utils.GetItemFromFullInventory(bot, "item_tpscroll"))
	local isHighGround = tier >= 3
	if #enemiesNearDefendLoc == 0 and not baseFloor.active then
		if isHighGround and shouldDefend and alliesComing == 0 then
			local weightedEnemies = getWeightedEnemyCount(defendLocation, 1600)
			if weightedEnemies >= 2 then
				local closestPosition = getClosestPosition({ 4, 5, 3 }, defendLocation)
				if position == closestPosition then
					bot._defendWhy = "hg-creeps"
					return 0.4
				end
			end
		end
		return DefNone(bot, "no-heroes")
	end
	local neededDefenders = #enemiesNearDefendLoc + 2
	local missingDefenders = neededDefenders - alliesComing
	if isHighGround and #enemiesNearDefendLoc >= 3 and not baseFloor.active then
		local selfCount = (distanceToDefendLoc < 3000 or hasTpScroll) and 1 or 0
		local defenders = alliesComing + selfCount
		if #enemiesNearDefendLoc > defenders + 1 then
			local ancientLow = ourAncient and ourAncient:IsAlive() and gameState.ancientHP < 0.4
			if not ancientLow then
				bot._defendWhy = "outnumbered"
				return maxDefendDesire * 0.3
			end
		end
	end
	if missingDefenders <= 0 and not baseFloor.active then
		if distanceToDefendLoc > 2000 then
			return DefNone(bot, "far")
		end
	end
	local alliesNearCount = #alliesNearDefendLoc
	if alliesNearCount < 3 then
		if missingDefenders > 0 and missingDefenders < 5 then
			local closerAllies = 0
			do
				local i = 1
				while i <= #GetTeamPlayers(ourTeam) do
					local member = GetTeamMember(i)
					if member ~= nil and member:IsAlive() and member ~= bot and not member:IsIllusion() then
						local distance = GetUnitToLocationDistance(member, defendLocation)
						if distance > 2500 and distance < distanceToDefendLoc - 500 then
							closerAllies = closerAllies + 1
						end
					end
					i = i + 1
				end
			end
			if closerAllies >= missingDefenders then
				return DefNone(bot, "others-closer")
			end
		end
	end
	if #enemiesNearDefendLoc >= 4 or alliesNearCount >= 3 then
	elseif not isHighGround then
		if distanceToDefendLoc > 4000 then
			for _, otherLane in ipairs({ Lane.Top, Lane.Mid, Lane.Bot }) do
				do
					local continued
					repeat
						if otherLane == lane then
							continued = true
							break
						end
						local otherLaneFront = GetLaneFrontLocation(ourTeam, otherLane, 0)
						local otherLaneDistance = GetUnitToLocationDistance(bot, otherLaneFront)
						local enemiesNearOtherLane = Fu.GetLastSeenEnemiesNearLoc(otherLaneFront, 2500)
						if #enemiesNearOtherLane >= 1 and otherLaneDistance < distanceToDefendLoc - 1500 then
							return DefNone(bot, "closer-lane")
						end
						continued = true
					until true
					if not continued then
						break
					end
				end
			end
		end
	end
	if gameState.isLaningPhase and tier == 2 and #enemiesNearDefendLoc <= 1 and not baseFloor.active then
		local enemiesHealthy = true
		for _, enemyHero in ipairs(enemiesNearDefendLoc) do
			if Fu.IsValidHero(enemyHero) and Fu.GetHP(enemyHero) < 0.8 then
				enemiesHealthy = false
				break
			end
		end
		if enemiesHealthy and Fu.GetHP(bot) > 0.8 then
			return DefNone(bot, "laning-safe")
		end
	end
	local defendDesire = RemapValClamped(GetDefendLaneDesire(lane), 0, 1, 0, 0.7)
	local defendingOtherLane = isDefendingOtherLane(bot, lane)
	if tier <= 1 then
		if defendingOtherLane then
			return DefNone(bot, "defending-other")
		end
		local buildingHP = isAliveBuilding(building) and Fu.GetHP(building) or 1
		if buildingHP < 0.25 and #enemiesNearDefendLoc > 0 or not canReach then
			return DefNone(bot, "tower-low-or-no-tp")
		end
	elseif tier == 2 then
		if defendingOtherLane then
			return DefNone(bot, "defending-other")
		end
		local buildingHP = isAliveBuilding(building) and Fu.GetHP(building) or 1
		if buildingHP < 0.25 and #enemiesNearDefendLoc > 0 or not canReach then
			return DefNone(bot, "tower-low-or-no-tp")
		end
		defendDesire = defendDesire * 3
	else
		defendDesire = defendDesire * 5
	end
	bot._defendWhy = "lane"
	if baseFloor.active then
		if baseFloor.floor > defendDesire then
			bot._defendWhy = "base-floor"
		end
		defendDesire = math.max(defendDesire, baseFloor.floor)
	end
	if pingDesire > 0 then
		if pingDesire > defendDesire then
			bot._defendWhy = "ping"
		end
		defendDesire = math.max(defendDesire, pingDesire)
	end
	if (#enemiesNearDefendLoc >= 4 or alliesNearCount >= 3) and not outnumbered then
		defendDesire = math.max(defendDesire, maxDefendDesire)
	end
	pingForDefense(bot, lane, defendDesire, building, tier, alliesComing, #enemiesNearDefendLoc)
	if defendDesire > maxDefendDesire * 0.8 then
		Fu.Utils.GameStates = Fu.Utils.GameStates or {}
		Fu.Utils.GameStates.recentDefendTime = DotaTime()
	end
	local laneDesires = bot.DefendLaneDesire
	laneDesires[lane] = defendDesire
	local topDesire = laneDesires[Lane.Top] or 0
	local midDesire = laneDesires[Lane.Mid] or 0
	local botDesire = laneDesires[Lane.Bot] or 0
	local maxDesire = math.max(topDesire, midDesire, botDesire)
	if maxDesire < 0.1 then
		bot.laneToDefend = nil
	else
		bot.laneToDefend = topDesire >= midDesire and topDesire >= botDesire and Lane.Top
			or (midDesire >= botDesire and Lane.Mid or Lane.Bot)
	end
	if distanceToDefendLoc < 1200 and not baseFloor.active then
		defendDesire = math.min(defendDesire, 0.55)
	end
	if distanceToDefendLoc < 900 and not baseFloor.active then
		local nearbyEnemies = Fu.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 1200)
		if #nearbyEnemies > 0 then
			defendDesire = defendDesire * 0.5
		end
	end
	if bot._defendDesireHalved then
		defendDesire = defendDesire * 0.5
		bot._defendDesireHalved = false
	end
	do
		local topDistance = GetUnitToLocationDistance(bot, laneState.laneFronts[Lane.Top])
		local midDistance = GetUnitToLocationDistance(bot, laneState.laneFronts[Lane.Mid])
		local botDistance = GetUnitToLocationDistance(bot, laneState.laneFronts[Lane.Bot])
		local closestLane = Lane.Mid
		if topDistance < midDistance and topDistance < botDistance then
			closestLane = Lane.Top
		elseif botDistance < midDistance and botDistance < topDistance then
			closestLane = Lane.Bot
		end
		if closestLane == lane and defendDesire > 0 and defendDesire < 0.35 then
			defendDesire = math.max(0.05, defendDesire)
		end
	end
	return math.min(math.max(defendDesire, 0), lastStand and lastStandDesire or maxDefendDesire)
end
localizationLoaded, Localization = pcall(require, GetScriptDirectory() .. "/FuncLib/systems/localization")
if not localizationLoaded then
	Localization = {
		Get = function(key)
			return "Defend here!"
		end,
	}
end
local CustomLoader = require(GetScriptDirectory() .. "/FuncLib/systems/custom_loader")
local FarmDefend = require(GetScriptDirectory() .. "/FuncLib/systems/farm_defend")
CustomLoader.ThinkLess = CustomLoader.Enable and CustomLoader.ThinkLess or 1
humanPingSeconds = 5
local defendRadius = 1600
maxDefendDesire = 0.6
ancientThreatRadius = 2600
baseDefenseSeconds = 4
enemyCountCacheSeconds = 0.35
lastSeenSeconds = 5
ourTeam = GetTeam()
threatLaneLock = { lane = Lane.Mid, ["until"] = -1 }
baseDefenseUntil = -1
travelBootsDefenderTime = 0
enemyCountCache = {}
stateCacheSeconds = 0.5
gameStateCache = nil
laneStateCache = nil
unitListCache = nil
local MODE_NAMES = nil
local function ModeName(mode)
	if MODE_NAMES == nil then
		MODE_NAMES = {}
		for _, name in ipairs({
			"NONE",
			"LANING",
			"ATTACK",
			"ROAM",
			"RETREAT",
			"SECRET_SHOP",
			"SIDE_SHOP",
			"PUSH_TOWER_TOP",
			"PUSH_TOWER_MID",
			"PUSH_TOWER_BOT",
			"DEFEND_TOWER_TOP",
			"DEFEND_TOWER_MID",
			"DEFEND_TOWER_BOT",
			"ASSEMBLE",
			"TEAM_ROAM",
			"FARM",
			"DEFEND_ALLY",
			"EVASIVE_MANEUVERS",
			"ROSHAN",
			"ITEM",
			"WARD",
			"RUNE",
			"OUTPOST",
		}) do
			local id = _G ~= nil and _G["BOT_MODE_" .. name] or nil
			if id ~= nil then
				MODE_NAMES[id] = string.lower(name)
			end
		end
	end
	return MODE_NAMES[mode] or tostring(mode)
end
-- [OHA-DEFEND]: every 5s per bot while our base is being hit. One line holds all
-- three lane desires with the reason each one came out, plus what the bot is doing.
local function LogBaseDefense(bot, defendLane, desire, why, gameState)
	bot._defendLaneDesire = bot._defendLaneDesire or {}
	bot._defendLaneWhy = bot._defendLaneWhy or {}
	bot._defendLaneDesire[defendLane] = desire
	bot._defendLaneWhy[defendLane] = why
	local now = DotaTime()
	-- Checked at most once a second (#52): the line prints at most every 5s, but until it printed the threat and
	-- high-ground wave reads below (every enemy creep, once per high-ground building) ran on every defend desire of
	-- all three lanes. The lane desires above are still stored on every call.
	if now < (bot._defendLogAt or -999) or now < (bot._defendLogCheckAt or -999) or Fu.IsMeepoClone(bot) then
		return
	end
	bot._defendLogCheckAt = now + 1
	local threat = ReadBaseThreat(gameState)
	local hgBuilding, hgCreeps = Fu.Utils.HighGroundCreepWaveNear(bot, 30000)
	if not threat.exposed and hgBuilding == nil then
		return
	end
	bot._defendLogAt = now + 5
	local function lane(id)
		return string.format("%.2f(%s)", bot._defendLaneDesire[id] or 0, bot._defendLaneWhy[id] or "-")
	end
	local ourAncient = gameState.ourAncient
	local ok, modeDesire = pcall(function()
		return bot:GetActiveModeDesire()
	end)
	pcall(
		print,
		string.format(
			"[OHA-DEFEND] t=%.0f %s %s mode=%s/%.2f dist=%d top=%s mid=%s bot=%s anc=%.2f creeps=%d heroes=%d hg=%d hgcreeps=%d t4=%d hp=%.2f",
			now,
			GetTeam() == TEAM_DIRE and "dire" or "radiant",
			string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""),
			ModeName(bot:GetActiveMode()),
			ok and type(modeDesire) == "number" and modeDesire or -1,
			ourAncient ~= nil and math.floor(GetUnitToUnitDistance(bot, ourAncient)) or -1,
			lane(Lane.Top),
			lane(Lane.Mid),
			lane(Lane.Bot),
			threat.ancHP,
			threat.creeps,
			threat.heroes,
			threat.hg,
			hgCreeps or 0,
			threat.t4,
			Fu.GetHP(bot)
		)
	)
end
local defendModeLane = {
	[BotMode.DefendTowerTop] = Lane.Top,
	[BotMode.DefendTowerMid] = Lane.Mid,
	[BotMode.DefendTowerBot] = Lane.Bot,
}
function Defend.GetDefendDesire(bot, lane)
	if
		bot:IsInvulnerable()
		or not bot:IsHero()
		or not bot:IsAlive()
		or not stringIncludes(bot:GetUnitName(), "hero")
		or bot:IsIllusion()
	then
		return BotModeDesire.None
	end
	bot._defendWhy = "?"
	-- Refresh the base-siege latch every think (farm and the TP rules read it), also when the
	-- helper returns early.
	Defend.GetBaseSiege()
	local desire = math.min(Defend.GetDefendDesireHelper(bot, lane), 1)
	local why = bot._defendWhy or "?"
	local defendLoc = getDefendState(bot).defendLoc or GetLaneFrontLocation(ourTeam, lane, 0)
	local alliesNearDefendLoc = Fu.GetAlliesNearLoc(defendLoc, 2000)
	local enemiesNearDefendLoc = Fu.GetEnemiesNearLoc(defendLoc, 2000)
	local isStrongGroup = #alliesNearDefendLoc >= 3
		and #enemiesNearDefendLoc >= 1
		and #alliesNearDefendLoc > #enemiesNearDefendLoc
		and Fu.WeAreStronger(bot, 2500)
	if isStrongGroup and desire < 0.9 then
		if desire > 0.55 then
			why = why .. "+group-cap"
		end
		desire = math.min(desire, 0.55)
	end
	local gameState = getGameState()
	-- Treat any HG presence as base defense so nearby skirmishes do not zero desire.
	local isBaseThreat = gameState.enemiesAtAncient >= 1 or gameState.enemiesOnHG >= 1 or desire >= 0.45
	if not isBaseThreat then
		local botLocation = bot:GetLocation()
		local attackRange = bot:GetAttackRange()
		local searchRadius = math.max(1600, attackRange)
		for _, enemyHero in ipairs(Fu.GetLastSeenEnemiesNearLoc(botLocation, searchRadius)) do
			do
				local continued
				repeat
					if not Fu.IsValidHero(enemyHero) then
						continued = true
						break
					end
					local distance = GetUnitToUnitDistance(bot, enemyHero)
					if
						distance <= 1200
						or distance <= attackRange
						or distance <= 1600 and distance <= enemyHero:GetAttackRange()
					then
						if desire > 0 then
							why = why .. "+skirmish"
						end
						desire = desire * 0.35
						break
					end
					continued = true
				until true
				if not continued then
					break
				end
			end
		end
	end
	-- Don't call a defence the team is already holding. Game 038, 17:50: "They're pushing bot!" while four of
	-- ours were at the bottom T2 winning 4v1.
	local defenceHeld = false
	if desire >= 0.5 and (bot._lastDefendChatDesire or 0) < 0.5 then
		local front = GetLaneFrontLocation(ourTeam, lane, 0)
		local alliesAtFront = Fu.GetAlliesNearLoc(front, 1600) or {}
		local enemiesAtFront = Fu.GetLastSeenEnemiesNearLoc(front, 1600) or {}
		if #alliesAtFront >= 2 and #alliesAtFront > #enemiesAtFront then
			defenceHeld = true
			pcall(
				print,
				string.format(
					"[OHA-DEFEND] t=%.0f %s chat-skip why=already-held lane=%s allies=%d enemies=%d",
					DotaTime(),
					(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
					tostring(lane),
					#alliesAtFront,
					#enemiesAtFront
				)
			)
		end
	end
	if desire >= 0.5 and (bot._lastDefendChatDesire or 0) < 0.5 and not defenceHeld then
		if FarmDefend.ClaimDecisionChat("defend_commit") then
			local chatKey = lane == Lane.Top and "say_defend_top"
				or (lane == Lane.Mid and "say_defend_mid" or "say_defend_bot")
			-- #53, game 068 41:40: "Defend mid!" while bottom pushed; both lanes were down to the T4s. A lane whose
			-- furthest building is a T4 or the Ancient is a base defence.
			local _, chatTier = LaneBuilding(lane)
			if gameState.enemiesAtAncient >= 1 or gameState.enemiesOnHG >= 1 or chatTier >= 4 then
				chatKey = "say_base_defend"
			end
			pcall(
				print,
				string.format(
					"[OHA-DEFEND] t=%.0f %s defend-chat key=%s lane=%s tier=%d heroesAtAnc=%d hg=%d",
					DotaTime(),
					(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
					chatKey,
					tostring(laneNames[lane]),
					chatTier,
					gameState.enemiesAtAncient or 0,
					gameState.enemiesOnHG or 0
				)
			)
			local chatLines = Localization.Get(chatKey)
			if type(chatLines) == "table" and #chatLines > 0 then
				bot:ActionImmediate_Chat(chatLines[RandomInt(1, #chatLines)], false)
			elseif type(chatLines) == "string" then
				bot:ActionImmediate_Chat(chatLines, false)
			end
		end
	end
	bot._lastDefendChatDesire = desire
	bot.defendDesire = desire
	LogBaseDefense(bot, lane, desire, why, gameState)
	return desire
end
function Defend.OnEnd() end
-- #53, game 066 81:41-81:55: Elder Titan defended the bottom high ground (11-21 creeps) until the base-lane gate let
-- go for a moment; mid (8 creeps) then read 0.85 against bottom's 0.37, the engine switched him to mid, and he TP'd
-- to the far end of the map. A defender keeps the lane whose defend mode it is in (and for 10s after it leaves that
-- mode) unless another lane is clearly worse (DefendLaneRules.KeepLane); that lane is capped just below the held one.
-- Compares the final desires (after the group cap and the skirmish cut), so it wraps Defend.GetDefendDesire.
local function HoldDefendLane(bot, lane, desire, reason)
	local now = DotaTime()
	local activeLane = defendModeLane[bot:GetActiveMode()]
	if activeLane ~= nil then
		bot._defendHeldLane, bot._defendHeldAt = activeLane, now
	elseif bot._defendHeldLane ~= nil and now - (bot._defendHeldAt or -999) > DefendLaneRules.HOLD_SECONDS then
		bot._defendHeldLane = nil
	end
	bot._defendLaneRead = bot._defendLaneRead or {}
	bot._defendLaneRead[lane] = { desire = desire, at = now }
	local heldLane = bot._defendHeldLane
	if heldLane == nil or heldLane == lane or desire <= 0 then
		return desire
	end
	local heldRead = bot._defendLaneRead[heldLane]
	if heldRead == nil or now - heldRead.at > 1 or desire < heldRead.desire then
		return desire
	end
	local heldCreeps, heldFront, heldTier = LaneThreat(heldLane)
	local otherCreeps, otherFront, otherTier = LaneThreat(lane)
	local heldHp = LaneBuilding(heldLane)
	local otherHp = LaneBuilding(lane)
	local held = {
		desire = heldRead.desire,
		creeps = heldCreeps,
		heroes = #Fu.GetLastSeenEnemiesNearLoc(heldFront, DefendLaneRules.ThreatRadius(heldTier)),
		hp = heldHp,
		tier = heldTier,
	}
	local other = {
		desire = desire,
		creeps = otherCreeps,
		heroes = #Fu.GetLastSeenEnemiesNearLoc(otherFront, DefendLaneRules.ThreatRadius(otherTier)),
		hp = otherHp,
		tier = otherTier,
		why = reason,
	}
	local keep, why = DefendLaneRules.KeepLane(held, other, now - (bot._defendHeldAt or -999))
	local decision = why
	if (decision ~= bot._lanePickLast or now >= (bot._lanePickLogAt or -999)) and why ~= "no-held" then
		bot._lanePickLast = decision
		bot._lanePickLogAt = now + 5
		pcall(
			print,
			string.format(
				"[OHA-DEFEND] t=%.0f %s lane-pick chose=%s other=%s myDist=%d threat=%d/%d heroes=%d/%d hp=%.2f/%.2f tier=%d/%d desire=%.2f/%.2f otherWhy=%s why=%s",
				now,
				(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
				tostring(laneNames[keep and heldLane or lane]),
				tostring(laneNames[keep and lane or heldLane]),
				math.floor(GetUnitToLocationDistance(bot, heldFront)),
				held.creeps,
				other.creeps,
				held.heroes,
				other.heroes,
				held.hp,
				other.hp,
				held.tier,
				other.tier,
				held.desire,
				desire,
				tostring(reason),
				decision
			)
		)
	end
	if keep then
		return math.max(0, heldRead.desire - 0.05)
	end
	return desire
end
do
	local getDefendDesire = Defend.GetDefendDesire
	Defend.GetDefendDesire = function(bot, lane)
		local desire = getDefendDesire(bot, lane)
		if bot == nil or not bot:IsAlive() then
			return desire
		end
		return HoldDefendLane(bot, lane, desire, bot._defendWhy)
	end
end
-- #53: the defend modes' Think (mode_defend_tower_*_generic.lua). It replaces Valve's defend Think, which walked the bot
-- to the lane's furthest building (game 068: the T4s, then the Ancient; 0 hg-step lines in games 064-068 because this
-- had no caller). Every path issues one order through DefendStep, which logs
-- [OHA-DEFEND] hg-step step= lane= why= dist= ancDist= (each step at most every 5s). Teleports stay with the TP rule
-- (ability_item_usage_generic.lua: DefendLaneRules.DefendTpBlock and the bot._defendTpAt stamp); this only holds it.
-- How far out from the rim a bot walks to meet a wave (map-scale choice: the ramp below the T3, not the T2 area).
local STEP_DOWN = 1600
local function StableOffset(bot)
	local now = DotaTime()
	if bot._defendOffset == nil or now >= (bot._defendOffsetUntil or -999) then
		bot._defendOffset = Fu.RandomForwardVector(150)
		bot._defendOffsetUntil = now + 4
	end
	return bot._defendOffset
end
local function DefendStep(bot, lane, step, why, order, target, info)
	local now = DotaTime()
	local targetLoc = order == "attack" and target:GetLocation() or target
	-- Throttled per step name, so two steps that alternate print at most twice per 5s.
	bot._defendStepLogAt = bot._defendStepLogAt or {}
	if now >= (bot._defendStepLogAt[step] or -999) then
		bot._defendStepLogAt[step] = now + 5
		local ancient = GetAncient(ourTeam)
		pcall(
			print,
			string.format(
				"[OHA-DEFEND] t=%.0f %s hg-step step=%s lane=%s why=%s dist=%d ancDist=%d spot=%s tier=%d wave=%d heroes=%d order=%s",
				now,
				(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
				step,
				tostring(laneNames[lane]),
				tostring(why),
				math.floor(GetUnitToLocationDistance(bot, targetLoc)),
				ancient ~= nil and math.floor(GetUnitToUnitDistance(bot, ancient)) or -1,
				tostring(laneNames[info.spotLane] or info.spotLane),
				info.tier or 0,
				info.wave or 0,
				info.heroes or 0,
				order
			)
		)
	end
	if order == "attack" then
		bot:Action_AttackUnit(target, true)
	elseif order == "move" then
		bot:Action_MoveToLocation(target)
	else
		bot:Action_AttackMove(target)
	end
end
-- The Ancient lost HP in the last 3s (read twice a second for the team).
local ancientHitState = { hp = nil, at = -999, checkAt = -999 }
local function AncientBeingHit(ancient)
	if ancient == nil or not ancient:IsAlive() then
		return false
	end
	local now = DotaTime()
	if now >= ancientHitState.checkAt then
		ancientHitState.checkAt = now + 0.5
		local hp = ancient:GetHealth()
		if ancientHitState.hp ~= nil and hp < ancientHitState.hp then
			ancientHitState.at = now
		end
		ancientHitState.hp = hp
	end
	return now - ancientHitState.at <= 3
end
local function CreepScore(creep)
	local score = creep:GetAttackDamage() * creep:GetAttackSpeed() * (1 - Fu.GetHP(creep))
	local name = creep:GetUnitName() or ""
	if stringIncludes(name, "siege") then
		score = score + 10000
	elseif stringIncludes(name, "shadow_shaman_ward") then
		score = score + 9000
	elseif stringIncludes(name, "warlock_golem") then
		score = score + 8000
	end
	return score
end
-- A base defence (the lane is down to the T4s or the Ancient) holds one rim for the whole team, picked from the threat,
-- not from the mode's lane label (game 068 t=3120-3137: the base lane flipped top / mid every few seconds with no
-- creeps). The lane of the wave nearest our Ancient on a base lane; else of the enemy heroes seen at a base rim; else the
-- base lane whose enemy lane front is nearest our Ancient (kept until a wave or heroes move it).
local baseSpot = { lane = nil, why = nil, at = -999, checkAt = -999 }
local function BaseSpotLane(fallbackLane)
	local now = DotaTime()
	if baseSpot.lane ~= nil and now < baseSpot.checkAt then
		return baseSpot.lane, baseSpot.why
	end
	baseSpot.checkAt = now + 2
	local ancient = GetAncient(ourTeam)
	local baseLanes, rims = {}, {}
	for _, lane in ipairs(creepLaneIds) do
		local _, tier = LaneBuildingEntry(lane)
		if tier >= 4 then
			baseLanes[#baseLanes + 1] = lane
			rims[lane] = getHighGroundWaitPoint(ourTeam, lane)
		end
	end
	if #baseLanes == 0 then
		return fallbackLane, "no-base-lane"
	end
	local pick, why = nil, nil
	if ancient ~= nil then
		local nearest = math.huge
		for _, entry in ipairs(EnemyCreepLanes()) do
			local rim = rims[entry.lane]
			if
				rim ~= nil
				and Fu.IsValid(entry.unit)
				and GetUnitToLocationDistance(entry.unit, rim) <= DefendLaneRules.HIGH_GROUND_RADIUS
			then
				local d = GetUnitToUnitDistance(entry.unit, ancient)
				if d < nearest then
					pick, why, nearest = entry.lane, "wave", d
				end
			end
		end
	end
	if pick == nil then
		local most = 0
		for _, lane in ipairs(baseLanes) do
			local n = #Fu.GetLastSeenEnemiesNearLoc(rims[lane], 2200)
			if n > most then
				pick, why, most = lane, "heroes", n
			end
		end
	end
	if pick == nil and ancient ~= nil then
		local nearest = math.huge
		for _, lane in ipairs(baseLanes) do
			local d = GetUnitToLocationDistance(ancient, GetLaneFrontLocation(GetOpposingTeam(), lane, 0))
			if d < nearest then
				pick, why, nearest = lane, "front", d
			end
		end
	end
	pick, why = pick or baseLanes[1], why or "first"
	-- A wave takes the spot at once; heroes replace a front pick at once, a wave or heroes pick after 8s; a front pick
	-- never replaces a spot that is still a base lane (enemy lane fronts move with every wave).
	local oldIsBase = baseSpot.lane ~= nil and rims[baseSpot.lane] ~= nil
	local keepOld = oldIsBase
		and pick ~= baseSpot.lane
		and why ~= "wave"
		and (
			why == "front"
			or why == "first"
			or why == "heroes" and baseSpot.why ~= "front" and baseSpot.why ~= "first" and now - baseSpot.at < 8
		)
	if not keepOld then
		if pick ~= baseSpot.lane then
			baseSpot.at = now
		end
		baseSpot.lane, baseSpot.why = pick, why
	end
	return baseSpot.lane, baseSpot.why
end
-- A lone TP into 3+ enemy heroes waits until 2 allies are there or teleporting there (game 037: Kez, Meepo, Night Stalker
-- and Hoodwink TP'd into the bottom siege one after another). Holds the TP rule through bot._noTpUntil.
local function DefendTpHold(bot, lane, spot)
	if spot == nil or GetUnitToLocationDistance(bot, spot) <= 4000 then
		return
	end
	local enemiesThere = #Fu.GetLastSeenEnemiesNearLoc(spot, 2000)
	if enemiesThere < 3 then
		return
	end
	local alliesThere = #Fu.Utils.GetAllyIdsInTpToLocation(spot, 2500)
	for _, ally in ipairs(Fu.GetAlliesNearLoc(spot, 2000)) do
		if ally ~= bot then
			alliesThere = alliesThere + 1
		end
	end
	if alliesThere >= 2 then
		return
	end
	bot._noTpUntil = math.max(bot._noTpUntil or -999, DotaTime() + 1)
	if DotaTime() >= (bot._defendTpHoldLogAt or -999) then
		bot._defendTpHoldLogAt = DotaTime() + 5
		pcall(
			print,
			string.format(
				"[OHA-TP] t=%.0f %s defend-tp hold lane=%s enemies=%d allies=%d to=%.0f,%.0f",
				DotaTime(),
				(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
				tostring(laneNames[lane]),
				enemiesThere,
				alliesThere,
				spot.x,
				spot.y
			)
		)
	end
end
-- Our heroes who can take part at a spot: this bot, and the allies within radius of it.
local function AlliesWithin(bot, location, radius)
	local count = 1
	for _, ally in ipairs(Fu.GetAlliesNearLoc(location, radius)) do
		if ally ~= bot and not ally:IsIllusion() then
			count = count + 1
		end
	end
	return count
end
local function NearestAttackableHero(location, radius, bot)
	local best, bestDist = nil, math.huge
	for _, enemy in ipairs(Fu.GetEnemiesNearLoc(location, radius)) do
		if Fu.IsValidHero(enemy) and Fu.CanBeAttacked(enemy) then
			local d = GetUnitToUnitDistance(bot, enemy)
			if d < bestDist then
				best, bestDist = enemy, d
			end
		end
	end
	return best, bestDist
end
-- T1 / T2 still standing: hold the building, take on heroes there when we can, clear its creeps.
local function LaneDefendThink(bot, lane, building, info)
	local defendLocation = building:GetLocation()
	local offset = StableOffset(bot)
	local enemies = Fu.GetEnemiesNearLoc(defendLocation, defendRadius)
	info.heroes = #enemies
	if #enemies >= 1 then
		local ancient = GetAncient(ourTeam)
		local ancientLow = ancient ~= nil and ancient:IsAlive() and Fu.GetHP(ancient) < 0.5
		local allies = Fu.GetAlliesNearLoc(defendLocation, defendRadius)
		if #allies >= #enemies or ancientLow or Fu.WeAreStronger(bot, 2500) then
			local attackRange = bot:GetAttackRange()
			local engageRange = attackRange < 900 and 900 or math.min(attackRange, defendRadius)
			local target, targetDist = NearestAttackableHero(defendLocation, defendRadius, bot)
			if target ~= nil and targetDist <= engageRange then
				return DefendStep(bot, lane, "lane-fight", "heroes-at-building", "attack", target, info)
			end
			return DefendStep(
				bot,
				lane,
				"lane-defend",
				"heroes-at-building",
				"move",
				vectorAdd(defendLocation, offset),
				info
			)
		end
		local fallback = Fu.AdjustLocationWithOffsetTowardsFountain(defendLocation, 400)
		return DefendStep(bot, lane, "lane-back", "outnumbered", "move", vectorAdd(fallback, offset), info)
	end
	local best, bestScore, nearest, nearestDist = nil, -1, nil, math.huge
	for _, entry in ipairs(EnemyCreepLanes()) do
		local creep = entry.unit
		if
			Fu.IsValid(creep)
			and GetUnitToLocationDistance(creep, defendLocation) <= DefendLaneRules.TOWER_RADIUS
			and Fu.CanBeAttacked(creep)
		then
			info.wave = info.wave + 1
			local d = GetUnitToUnitDistance(bot, creep)
			if d <= 900 then
				local score = CreepScore(creep)
				if score > bestScore then
					best, bestScore = creep, score
				end
			end
			if d < nearestDist then
				nearest, nearestDist = creep, d
			end
		end
	end
	if best ~= nil then
		return DefendStep(bot, lane, "lane-creep", "creeps-near", "attack", best, info)
	end
	if nearest ~= nil then
		return DefendStep(bot, lane, "lane-wave", "creeps-at-building", "attack", nearest, info)
	end
	if GetUnitToLocationDistance(bot, defendLocation) > 500 then
		return DefendStep(bot, lane, "lane-defend", "walk", "move", vectorAdd(defendLocation, offset), info)
	end
	return DefendStep(bot, lane, "lane-defend", "hold", "attack-move", vectorAdd(defendLocation, offset), info)
end
function Defend.DefendThink(bot, lane)
	if Fu.CanNotUseAction(bot) then
		return
	end
	local now = DotaTime()
	local offset = StableOffset(bot)
	local ancient = GetAncient(ourTeam)
	local ancientLoc = ancient ~= nil and ancient:GetLocation() or Fu.GetTeamFountain()
	local homeSpot = Fu.AdjustLocationWithOffsetTowardsFountain(ancientLoc, 300)
	local building, tier = LaneBuildingEntry(lane)
	local info = { tier = tier, wave = 0, heroes = 0, spotLane = lane }
	-- Group-up (GetDefendDesireHelper): go to the group point and hold there; hit an enemy hero that comes within reach.
	if (bot._defendGroupUpUntil or -1) > now and bot._defendGroupUpPoint ~= nil then
		local point = bot._defendGroupUpPoint
		local reach = math.max(700, bot:GetAttackRange() + 150)
		local closeEnemies = bot:GetNearbyHeroes(reach, true, BotMode.None) or {}
		if
			Fu.IsValidHero(closeEnemies[1])
			and Fu.CanBeAttacked(closeEnemies[1])
			and GetUnitToLocationDistance(bot, point) <= 1200
		then
			return DefendStep(bot, lane, "group-up", "enemy-in-reach", "attack", closeEnemies[1], info)
		end
		if GetUnitToLocationDistance(bot, point) > 300 then
			return DefendStep(bot, lane, "group-up", "walk", "move", vectorAdd(point, offset), info)
		end
		return DefendStep(bot, lane, "group-up", "hold", "attack-move", vectorAdd(point, offset), info)
	end
	-- Enemy heroes at our Ancient: every defender goes home.
	local heroesAtAncient = ancient ~= nil and #Fu.GetLastSeenEnemiesNearLoc(ancientLoc, 2200) or 0
	if heroesAtAncient > 0 then
		info.heroes = heroesAtAncient
		local target, targetDist = NearestAttackableHero(ancientLoc, 2200, bot)
		if target ~= nil and targetDist <= 1600 then
			return DefendStep(bot, lane, "ancient-heroes", "fight", "attack", target, info)
		end
		if GetUnitToLocationDistance(bot, homeSpot) > 600 then
			return DefendStep(bot, lane, "ancient-heroes", "walk", "move", homeSpot, info)
		end
		return DefendStep(bot, lane, "ancient-heroes", "hold", "attack-move", vectorAdd(ancientLoc, offset), info)
	end
	-- Hit by heroes and outnumbered around the bot: step back toward the fountain.
	if bot:WasRecentlyDamagedByAnyHero(2) then
		local enemiesNearMe = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1200)
		if #enemiesNearMe > #Fu.GetAlliesNearLoc(bot:GetLocation(), 1200) and not Fu.WeAreStronger(bot, 1600) then
			info.heroes = #enemiesNearMe
			local away = Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 600)
			return DefendStep(bot, lane, "back-off", "hit-outnumbered", "move", away, info)
		end
	end
	local baseDefence = building == nil or tier >= 4
	if not baseDefence and tier <= 2 then
		DefendTpHold(bot, lane, building:GetLocation())
		return LaneDefendThink(bot, lane, building, info)
	end
	-- High ground: the T3 is the furthest building, or it is down. Hold the rim and meet the wave there.
	local spotLane, spotWhy = lane, "lane"
	if baseDefence then
		spotLane, spotWhy = BaseSpotLane(lane)
	end
	info.spotLane = spotLane
	local rim = getHighGroundWaitPoint(ourTeam, spotLane)
	DefendTpHold(bot, lane, rim)
	-- The rims whose waves count: this lane's, or in a base defence every lane down to the T4s; plus the base creeps.
	local rims = { [spotLane] = rim }
	if baseDefence then
		for _, otherLane in ipairs(creepLaneIds) do
			local _, otherTier = LaneBuildingEntry(otherLane)
			if otherTier >= 4 then
				rims[otherLane] = getHighGroundWaitPoint(ourTeam, otherLane)
			end
		end
	end
	local best, bestScore, nearest, nearestDist = nil, -1, nil, math.huge
	for _, entry in ipairs(EnemyCreepLanes()) do
		local creep = entry.unit
		local creepRim = rims[entry.lane]
		if
			(entry.lane == "base" or creepRim ~= nil)
			and Fu.IsValid(creep)
			and (entry.lane == "base" or GetUnitToLocationDistance(creep, creepRim) <= STEP_DOWN)
			and Fu.CanBeAttacked(creep)
		then
			info.wave = info.wave + 1
			local d = GetUnitToUnitDistance(bot, creep)
			if d <= 1200 then
				local score = CreepScore(creep)
				if score > bestScore then
					best, bestScore = creep, score
				end
			end
			if d < nearestDist then
				nearest, nearestDist = creep, d
			end
		end
	end
	local stronger = Fu.WeAreStronger(bot, 2500)
	local waveTarget = best or nearest
	local waveSafe = false
	if waveTarget ~= nil then
		local heroesByWave = #Fu.GetLastSeenEnemiesNearLoc(waveTarget:GetLocation(), 1200)
		waveSafe = heroesByWave == 0
			or stronger
			or AlliesWithin(bot, waveTarget:GetLocation(), 2000) >= heroesByWave + 1
	end
	local heroesAtRim = #Fu.GetLastSeenEnemiesNearLoc(rim, 1600)
	info.heroes = heroesAtRim
	local step = DefendLaneRules.HighGroundStep({
		heroesAtAncient = 0,
		heroesAtRim = heroesAtRim,
		alliesAtRim = AlliesWithin(bot, rim, 2500),
		stronger = stronger,
		waveNear = best ~= nil,
		wave = info.wave,
		waveSafe = waveSafe,
		ancientHit = AncientBeingHit(ancient),
	})
	local why = baseDefence and ("base-" .. tostring(spotWhy)) or (tier == 3 and "t3" or "lane")
	if step == "hg-fight" then
		-- Only a hero within reach of the bot: no chase down the ramp, out of the T3's range.
		local attackRange = bot:GetAttackRange()
		local engageRange = attackRange < 900 and 900 or math.min(attackRange, defendRadius)
		local target, targetDist = NearestAttackableHero(rim, 1600, bot)
		if target ~= nil and targetDist <= engageRange then
			return DefendStep(bot, lane, step, why, "attack", target, info)
		end
		return DefendStep(bot, lane, step, why, "attack-move", vectorAdd(rim, offset), info)
	elseif step == "hg-back" then
		-- With the T3 standing, just behind it; once it is down, back to the Ancient.
		local backSpot = homeSpot
		if tier == 3 and Fu.IsValidBuilding(GetTower(ourTeam, tier3TowerIds[lane])) then
			backSpot = Fu.AdjustLocationWithOffsetTowardsFountain(rim, 400)
		end
		if GetUnitToLocationDistance(bot, backSpot) > 400 then
			return DefendStep(bot, lane, step, why, "move", backSpot, info)
		end
		return DefendStep(bot, lane, step, why, "attack-move", vectorAdd(backSpot, offset), info)
	elseif step == "hg-near" and best ~= nil then
		return DefendStep(bot, lane, step, why, "attack", best, info)
	elseif step == "hg-wave" and nearest ~= nil then
		return DefendStep(bot, lane, step, why, "attack", nearest, info)
	elseif step == "ancient-hit" then
		if GetUnitToLocationDistance(bot, homeSpot) > 1200 then
			return DefendStep(bot, lane, step, why, "move", homeSpot, info)
		end
		return DefendStep(bot, lane, step, why, "attack-move", vectorAdd(ancientLoc, offset), info)
	end
	if info.wave > 0 then
		why = why .. "+wave-unsafe"
	end
	if GetUnitToLocationDistance(bot, rim) > 1200 then
		return DefendStep(bot, lane, "hg-spot", why, "move", vectorAdd(rim, offset), info)
	end
	return DefendStep(bot, lane, "hg-spot", why, "attack-move", vectorAdd(rim, offset), info)
end
return Defend
