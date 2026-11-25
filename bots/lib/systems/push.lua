-- Push desire and which lane the team should push.
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
local function arraySome(self, callback, thisArg)
	for i = 1, #self do
		if callback(thisArg, self[i], i - 1, self) then
			return true
		end
	end
	return false
end
local Push = {}
local refreshThreatState, getGameState, getLocationState, getUnitState, discountLaneCost, getLaneTargetBuilding, enemyAncient, lastThreatTick, teamPushLane, enemyHeroesAtAncient, enemyHeroesOnHighGround, laneFrontHasEnemies, wasDefendPinged, recentDefendTime, maxPushDesire, lockedPushLane, lockedPushLaneUntil, isBotOnlyGame, pushAfterDefendUntil, lastDefendDesire, pushAfterDefendSeconds, stateCacheSeconds, gameStateCache, locationStateCache, unitStateCache, ancientThreatRadius, laneTargetCache
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Dota = require(GetScriptDirectory() .. "/lib/dota/index")
local Barracks = Dota.Barracks
local BotMode = Dota.BotMode
local BotModeDesire = Dota.BotModeDesire
local DamageType = Dota.DamageType
local Lane = Dota.Lane
local Team = Dota.Team
local Tower = Dota.Tower
local UnitType = Dota.UnitType
local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
local isValidUnit = Utils.IsValidUnit
local getLocationToLocationDistance = Utils.GetLocationToLocationDistance
local radiantFountainTpPoint = Utils.RadiantFountainTpPoint
local direFountainTpPoint = Utils.DireFountainTpPoint
local Cache = require(GetScriptDirectory() .. "/lib/systems/cache")
local KillWindow = require(GetScriptDirectory() .. "/lib/systems/kill_window")
local HumanOrders = require(GetScriptDirectory() .. "/lib/systems/human_orders")
-- Our base is being hit. A fresh kill must not pull the team away from it, since
-- defend desire tops out at 0.6 and the kill floor is 0.91 or 0.99.
local BASE_CREEP_RADIUS = 1600
local baseThreat = { exposed = false, why = "" }
-- Our Ancient's HP per team, and when it last went down (#12 / #196, game 068 52:00-52:30: a regenerating Ancient at
-- 60% with nothing at our base counted as a threat and kept pushers home). The Ancient counts while it lost HP in the
-- last 3s, not for being under 95%.
local ancientHpByTeam = {}
local function AncientLosingHp(ancient)
	local team = GetTeam()
	local now = DotaTime()
	local hp = ancient:GetHealth()
	local track = ancientHpByTeam[team]
	if track == nil then
		track = { hp = hp, lostAt = -999 }
		ancientHpByTeam[team] = track
	end
	if hp < track.hp then
		track.lostAt = now
	end
	track.hp = hp
	return now - track.lostAt <= 3
end
local function ReadBaseThreat(ancient, heroesAtAncient, heroesOnHG)
	local threat = { exposed = false, why = "", creeps = 0, ancHP = 1 }
	if ancient == nil or not ancient:IsAlive() then
		return threat
	end
	threat.ancHP = ancient:GetHealth() / math.max(1, ancient:GetMaxHealth())
	threat.ancLosing = AncientLosingHp(ancient)
	local loc = ancient:GetLocation()
	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS) or {}) do
		if unit ~= nil and unit:IsAlive() and GetUnitToLocationDistance(unit, loc) <= BASE_CREEP_RADIUS then
			threat.creeps = threat.creeps + 1
		end
	end
	local why = {}
	if (heroesAtAncient or 0) >= 1 then
		why[#why + 1] = "heroes=" .. heroesAtAncient
	end
	if (heroesOnHG or 0) >= 1 then
		why[#why + 1] = "hg=" .. heroesOnHG
	end
	if threat.ancLosing then
		why[#why + 1] = string.format("anc=%.2f-losing", threat.ancHP)
	end
	if threat.creeps >= 2 then
		why[#why + 1] = "creeps=" .. threat.creeps
	end
	threat.exposed = #why > 0
	threat.why = table.concat(why, ",")
	threat.heroes = (heroesAtAncient or 0) + (heroesOnHG or 0)
	return threat
end
-- Creeps only (no enemy hero at the Ancient or on high ground): only the allies closest to the
-- Ancient stay for it, 1 (2 with 8+ creeps or the Ancient losing HP); the rest may take the kill
-- push. Game 018: after Radiant lost barracks, super creeps kept 2+ creeps near the Ancient most
-- of the time, so all five held 75 kill windows (54:55: Gyrocopter, Techies and Warlock dead,
-- held for 4 creeps) and Dire lost no building after 47:28 while Radiant had 22 kills to 8.
local function MustStayForBase(bot)
	if not baseThreat.exposed then
		return false
	end
	if (baseThreat.heroes or 0) >= 1 then
		return true
	end
	local ancient = GetAncient(GetTeam())
	if ancient == nil then
		return true
	end
	local keep = ((baseThreat.creeps or 0) >= 8 or baseThreat.ancLosing) and 2 or 1
	local myDist = GetUnitToUnitDistance(bot, ancient)
	local closer = 0
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
		if
			ally ~= nil
			and ally ~= bot
			and ally:IsAlive()
			and not ally:IsIllusion()
			and GetUnitToUnitDistance(ally, ancient) < myDist
		then
			closer = closer + 1
		end
	end
	return closer < keep
end
local PushRules = require(GetScriptDirectory() .. "/lib/systems/push_rules")
-- Advantage window (#12, PushRules.Advantage): one state for the team (all its bots share this module), read at
-- most every 0.5s, kept per team (both teams' bots may share this module). A start and an end line once per change.
local advantageByTeam = {}
local function ShortHeroName(unit)
	return (string.gsub(unit:GetUnitName(), "npc_dota_hero_", ""))
end
local function ReadAdvantage(gameState, bot)
	local now = DotaTime()
	local team = GetTeam()
	advantageByTeam[team] = advantageByTeam[team] or { at = -999, desire = nil, why = "none" }
	local advantage = advantageByTeam[team]
	if now - advantage.at < 0.5 then
		return advantage
	end
	advantage.at = now
	local dead, deadLong, minLeft, names = KillWindow.DeadCounts()
	-- Our high ground (maintainer: "as long as our base is not being pushed"): enemy heroes on it or at the Ancient
	-- (ReadBaseThreat), or enemy creeps there: 2+ at the Ancient or a wave at a T3 / barracks (Utils.BaseUnderCreeps,
	-- the `hgcreeps=` of the [SHy-DEFEND] line).
	local baseHeroes = baseThreat.heroes or 0
	local baseCreeps = baseHeroes == 0 and Utils.BaseUnderCreeps(bot) or false
	local baseHit = baseHeroes >= 1 or baseCreeps
	local desire, why = PushRules.Advantage({
		aegis = gameState.hasAegis == true,
		alliesAlive = gameState.aliveAllyCount or 0,
		enemiesAlive = gameState.aliveEnemyCount or 5,
		dead = dead,
		deadLong = deadLong,
		baseThreat = baseHit,
	})
	local was = advantage.desire
	if (desire ~= nil) ~= (was ~= nil) then
		local endWhy = why
		if desire == nil then
			if baseHit then
				endWhy = "base-threat"
			elseif string.find(advantage.why or "", "aegis", 1, true) and not gameState.hasAegis then
				endWhy = "aegis-gone"
			elseif KillWindow.Tick().buyback then
				endWhy = "buyback"
			else
				endWhy = "respawn"
			end
		end
		pcall(
			print,
			string.format(
				"[SHy-PUSH] t=%.0f %s advantage-%s why=%s dead=%d deadLong=%d respawnLeft=%s aegis=%s alive=%d/%d desire=%.2f baseHeroes=%d baseCreeps=%s",
				now,
				GetTeam() == TEAM_DIRE and "dire" or "radiant",
				desire ~= nil and "start" or "end",
				desire ~= nil and why or endWhy,
				dead,
				deadLong,
				minLeft ~= nil and string.format("%.0f", minLeft) or "-",
				tostring(gameState.hasAegis == true),
				gameState.aliveAllyCount or 0,
				gameState.aliveEnemyCount or 0,
				desire or 0,
				baseHeroes,
				tostring(baseCreeps)
			)
		)
	end
	advantage.desire = desire
	advantage.why = why
	advantage.dead = dead
	advantage.deadLong = deadLong
	advantage.minLeft = minLeft
	advantage.names = names
	return advantage
end
-- How many living allies are closer to `location` than this bot (0 = the closest).
local function AllyRankTo(bot, location)
	local myDist = GetUnitToLocationDistance(bot, location)
	local closer = 0
	for i = 1, 5 do
		local member = GetTeamMember(i)
		if
			member ~= nil
			and member ~= bot
			and member:IsAlive()
			and GetUnitToLocationDistance(member, location) < myDist
		then
			closer = closer + 1
		end
	end
	return closer
end
-- The caps that lowered maxPushDesire in this GetPushDesireHelper call, for the lock-capped and advantage-push lines
-- (`src=`).
local pushCapSrc = ""
local function LogAdvantagePush(bot, lane, adv, desire, allies, gameState)
	if DotaTime() < (bot._advPushLogAt or -999) or Fu.IsMeepoClone(bot) then
		return
	end
	bot._advPushLogAt = DotaTime() + 8
	pcall(
		print,
		string.format(
			"[SHy-PUSH] t=%.0f %s advantage-push lane=%s why=%s dead=%d deadLong=%d respawnLeft=%s aegis=%s alive=%d/%d desire=%.2f hp=%.2f allies=%d src=%s",
			DotaTime(),
			ShortHeroName(bot),
			tostring(lane),
			tostring(adv.why),
			adv.dead or 0,
			adv.deadLong or 0,
			adv.minLeft ~= nil and string.format("%.0f", adv.minLeft) or "-",
			tostring(gameState.hasAegis == true),
			gameState.aliveAllyCount or 0,
			gameState.aliveEnemyCount or 0,
			desire,
			Fu.GetHP(bot),
			allies,
			pushCapSrc == "" and "-" or pushCapSrc
		)
	)
end
-- A bot joins a group push with every enemy alive (PushRules.FiveAliveCap), with the cap's inputs.
local function LogGroupJoin(bot, lane, why, desire, rank, joiners, inputs)
	if DotaTime() < (bot._groupJoinLogAt or -999) or Fu.IsMeepoClone(bot) then
		return
	end
	bot._groupJoinLogAt = DotaTime() + 8
	pcall(
		print,
		string.format(
			"[SHy-PUSH] t=%.0f %s group-join lane=%s why=%s desire=%.2f rank=%d/%d nwLead=%d lvlLead=%.1f tier=%d alive=%d/%d",
			DotaTime(),
			ShortHeroName(bot),
			tostring(lane),
			tostring(why),
			desire,
			rank + 1,
			joiners,
			math.floor(inputs.nwLead or 0),
			inputs.levelLead or 0,
			inputs.tier or 0,
			inputs.alliesAlive or 0,
			inputs.enemiesAlive or 0
		)
	)
end
local getGlobalGameState = Cache.getGlobalGameState
local getGlobalLocationState = Cache.getGlobalLocationState
local getCachedAlliesNearLoc = Cache.getCachedAlliesNearLoc
local getCachedEnemiesNearLoc = Cache.getCachedEnemiesNearLoc
local autoCleanupCache = Cache.autoCleanupCache
local NativeOperators = require(GetScriptDirectory() .. "/lib/vendor/native_operators")
local add = NativeOperators.add
local CacheKeys = require(GetScriptDirectory() .. "/lib/systems/cache_keys")
local function CapPush(value, src)
	if value < maxPushDesire then
		maxPushDesire = value
		pushCapSrc = pushCapSrc == "" and src or (pushCapSrc .. "+" .. src)
	end
end
-- Both enemy T4s down (their Ancient can be hit) and us ahead (2000+ net worth or 1+ average level, as in
-- PushRules.FiveAliveCap). Per team, read at most every 1s.
local ancientOpenByTeam = {}
local function AncientOpenAndAhead(gameState)
	local team = GetTeam()
	local cached = ancientOpenByTeam[team]
	if cached ~= nil and DotaTime() - cached.at < 1 then
		return cached.open, cached.ahead
	end
	local enemyTeam = GetOpposingTeam()
	local base1, base2 = GetTower(enemyTeam, Tower.Base1), GetTower(enemyTeam, Tower.Base2)
	local open = (base1 == nil or not base1:IsAlive()) and (base2 == nil or not base2:IsAlive())
	local ahead = (gameState.teamNetworth or 0) - (gameState.enemyNetworth or 0) >= 2000
		or (gameState.averageLevel or 0) - Fu.GetAverageLevel(true) >= 1
	ancientOpenByTeam[team] = { at = DotaTime(), open = open, ahead = ahead }
	return open, ahead
end
-- A spot below the enemy high ground on `lane` (#12 hg-gather): back along our lane front until it is 5200+ from
-- their fountain (the high-ground cap looks 5000 around it) and out of every live enemy T3 / T4's range + 300.
-- Per team and lane, every 3s. nil when no point up to 4000 back qualifies.
local gatherSpotCache = {}
local function HgGatherSpot(team, lane, enemyFountain)
	local key = team * 10 + lane
	local cached = gatherSpotCache[key]
	if cached ~= nil and DotaTime() - cached.at < 3 then
		return cached.spot
	end
	local enemyTeam = GetOpposingTeam()
	local towers = {}
	for _, towerId in ipairs({ Tower.Top3, Tower.Mid3, Tower.Bot3, Tower.Base1, Tower.Base2 }) do
		local tower = GetTower(enemyTeam, towerId)
		if tower ~= nil and tower:IsAlive() then
			towers[#towers + 1] = tower
		end
	end
	local spot = nil
	for back = 800, 4000, 400 do
		local location = GetLaneFrontLocation(team, lane, -back)
		if getLocationToLocationDistance(location, enemyFountain) >= 5200 then
			local safe = true
			for _, tower in ipairs(towers) do
				if GetUnitToLocationDistance(tower, location) < (tower:GetAttackRange() or 700) + 300 then
					safe = false
					break
				end
			end
			if safe then
				spot = location
				break
			end
		end
	end
	gatherSpotCache[key] = { at = DotaTime(), spot = spot }
	return spot
end
-- The high-ground cap or a gather below it (PushRules.HgGather) for this bot on this lane, with the state it keeps
-- per lane (bot._hgGather[lane]: since, releasedUntil, coolUntil) and the gather PushThink walks to
-- (bot._hgGatherActive: lane, at, spot). Returns "none", "go", "cap" or "gather".
-- Lines: hg-gather (throttled), hg-gather-go, hg-gather-give-up.
-- One gather lane per team (game 069 45:57-46:42: four bots gathered for three lanes and nobody met). Game 085 50:43:
-- the first bot that asked set it (Ringmaster, 15000 away, picked bot) and the three heroes at the mid T3 were capped
-- to 0.15. Now the lane is worked out from the team's positions (PushRules.HgGatherLane: most allies at a lane's
-- front, then the advantage push's lane), the same for every bot; a gathering bot within 4000 of its spot keeps it
-- (it lapses 3s after the last one), a farther one never sets it; and a lane whose group is already there goes
-- (PushRules.HgGather's "go" checks come before the other-lane cap). Line: hg-gather-lane (per team, on change).
local gatherLaneByTeam = {}
local GATHER_SET_DIST = 4000
local GATHER_FRONT_RADIUS = 3000
local gatherPickByTeam = {}
local function TeamGatherLane(bot, team, enemyFountain)
	local now = DotaTime()
	local pick = gatherPickByTeam[team]
	if pick ~= nil and now - pick.at < 1 and now >= pick.at then
		return pick
	end
	local counts, hgLanes, fronts, spots = {}, {}, {}, {}
	for lane = 1, 3 do
		counts[lane] = 0
		fronts[lane] = GetLaneFrontLocation(team, lane, 0)
		hgLanes[lane] = getLocationToLocationDistance(fronts[lane], enemyFountain) < 5000
		spots[lane] = hgLanes[lane] and HgGatherSpot(team, lane, enemyFountain) or nil
	end
	-- Each ally counts once, for the lane whose front (or gather spot) is nearest, when within reach of it: the three
	-- fronts at their T3s can be closer than 3000 to each other.
	for i = 1, 5 do
		local member = GetTeamMember(i)
		if member ~= nil and member:IsAlive() and not member:IsIllusion() then
			local bestLane, bestDist = nil, math.huge
			for lane = 1, 3 do
				local dist = GetUnitToLocationDistance(member, fronts[lane])
				if dist > GATHER_FRONT_RADIUS then
					dist = math.huge
				end
				if spots[lane] ~= nil then
					local spotDist = GetUnitToLocationDistance(member, spots[lane])
					if spotDist <= 1600 and spotDist < dist then
						dist = spotDist
					end
				end
				if dist < bestDist then
					bestLane, bestDist = lane, dist
				end
			end
			if bestLane ~= nil then
				counts[bestLane] = counts[bestLane] + 1
			end
		end
	end
	local kept = gatherLaneByTeam[team]
	local keptLane = kept ~= nil and now - kept.at <= 3 and now >= kept.at and kept.lane or nil
	local advLane = lockedPushLane ~= nil and now < (lockedPushLaneUntil or -999) and lockedPushLane or nil
	local lane, why = PushRules.HgGatherLane({ counts = counts, kept = keptLane, advLane = advLane, hgLanes = hgLanes })
	local was = pick ~= nil and pick.lane or nil
	pick = { at = now, lane = lane, why = why, counts = counts, logAt = pick ~= nil and pick.logAt or -999 }
	gatherPickByTeam[team] = pick
	if (lane ~= was or now >= pick.logAt + 10) and not Fu.IsMeepoClone(bot) then
		pick.logAt = now
		pcall(
			print,
			string.format(
				"[SHy-PUSH] t=%.0f %s hg-gather-lane pick=%d why=%s allies=%d counts=%d/%d/%d adv=%s kept=%s from=%s was=%s",
				now,
				team == TEAM_DIRE and "dire" or "radiant",
				lane,
				why,
				counts[lane] or 0,
				counts[1],
				counts[2],
				counts[3],
				tostring(advLane or "-"),
				tostring(keptLane or "-"),
				ShortHeroName(bot),
				tostring(was or "-")
			)
		)
	end
	return pick
end
local function ReadHgGather(bot, lane, s)
	local now = DotaTime()
	local active = bot._hgGatherActive
	if active ~= nil and active.lane ~= lane and now - (active.at or -999) <= 1 then
		-- Gathering for another lane this think: this one stays capped.
		return "cap"
	end
	local teamPick = TeamGatherLane(bot, s.team, s.enemyFountain)
	bot._hgGather = bot._hgGather or {}
	local state = bot._hgGather[lane]
	-- A gap of 5s+ without a push think on this lane (the bot died, or did something else): start over (game 069:
	-- Axe's gather from 2493 outlived his death at 2538 and read waited=212 at 2705).
	if state == nil or now - (state.seenAt or -999) > 5 then
		state = {}
		bot._hgGather[lane] = state
	end
	state.seenAt = now
	local spot = s.groupAllowed and HgGatherSpot(s.team, lane, s.enemyFountain) or nil
	local atSpot = spot ~= nil and #getCachedAlliesNearLoc(spot, 1600) or nil
	local mode = PushRules.HgGather({
		nearEnemyFountain = true,
		enemiesAlive = s.enemiesAlive,
		alliesAlive = s.alliesAlive,
		alliesNear = s.alliesNear,
		atSpot = atSpot,
		need = s.need,
		groupAllowed = s.groupAllowed,
		released = now < (state.releasedUntil or -999),
		gatherAge = state.since ~= nil and now - state.since or 0,
		coolDown = now < (state.coolUntil or -999),
		atFront = teamPick.counts[lane] or 0,
		otherLane = teamPick.lane ~= lane,
	})
	local name = ShortHeroName(bot)
	if mode == "go" then
		local atFront = teamPick.counts[lane] or 0
		local groupUp = atFront >= 3 and s.enemiesAlive <= atFront
		if s.alliesNear >= s.need or (atSpot or 0) >= s.need or groupUp then
			if state.since ~= nil then
				pcall(
					print,
					string.format(
						"[SHy-PUSH] t=%.0f %s hg-gather-go lane=%s need=%d atSpot=%d allies=%d front=%d waited=%.0f why=%s",
						now,
						name,
						tostring(lane),
						s.need,
						atSpot or 0,
						s.alliesNear,
						atFront,
						now - state.since,
						tostring(s.why)
					)
				)
			end
			state.releasedUntil = now + 12
		end
		state.since = nil
		bot._hgGatherActive = nil
	elseif mode == "gather" then
		state.since = state.since or now
		bot._hgGatherActive = { lane = lane, at = now, spot = spot }
		if GetUnitToLocationDistance(bot, spot) <= GATHER_SET_DIST then
			gatherLaneByTeam[s.team] = { lane = lane, at = now }
		end
		if now >= (state.logAt or -999) and not Fu.IsMeepoClone(bot) then
			state.logAt = now + 6
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s hg-gather lane=%s need=%d atSpot=%d allies=%d dist=%d age=%.0f alive=%d/%d why=%s",
					now,
					name,
					tostring(lane),
					s.need,
					atSpot or 0,
					s.alliesNear,
					math.floor(GetUnitToLocationDistance(bot, spot)),
					now - state.since,
					s.alliesAlive,
					s.enemiesAlive,
					tostring(s.why)
				)
			)
		end
	else
		if state.since ~= nil and now - state.since > 45 then
			state.coolUntil = now + 30
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s hg-gather-give-up lane=%s need=%d atSpot=%d waited=%.0f",
					now,
					name,
					tostring(lane),
					s.need,
					atSpot or 0,
					now - state.since
				)
			)
		end
		state.since = nil
		if active ~= nil and active.lane == lane then
			bot._hgGatherActive = nil
		end
	end
	return mode
end
function refreshThreatState(team)
	local gameTime = GameTime()
	if math.floor(gameTime * 10) == lastThreatTick then
		return
	end
	lastThreatTick = math.floor(gameTime * 10)
	local gameState = getGlobalGameState()
	local ourAncient = gameState.ourAncient
	enemyHeroesAtAncient = ourAncient ~= nil
			and Fu.Utils.CountEnemyHeroesNear(ourAncient:GetLocation(), ancientThreatRadius)
		or 0
	enemyHeroesOnHighGround = Fu.Utils.CountEnemyHeroesOnHighGround(team)
	baseThreat = ReadBaseThreat(ourAncient, enemyHeroesAtAncient, enemyHeroesOnHighGround)
	laneFrontHasEnemies = {}
	for _, lane in ipairs({ Lane.Top, Lane.Mid, Lane.Bot }) do
		local laneFrontLocation = GetLaneFrontLocation(team, lane, 0)
		laneFrontHasEnemies[lane] = Push.LaneFrontBlocked(team, lane, laneFrontLocation)
	end
	local gameStates = Fu.Utils.GameStates
	wasDefendPinged = gameStates ~= nil
		and gameStates.defendPings ~= nil
		and gameTime - gameStates.defendPings.pingedTime <= 5
	recentDefendTime = (gameStates or {}).recentDefendTime or 0
	teamPushLane = nil
end
-- Lane-front gate (#12, game 084 43:52-43:59; bots/lib/systems/tempo_rules.lua LaneFrontBlocks): 2+ enemy heroes
-- within 2200 of the lane front block the lane's push only when they outnumber our heroes there (within 2200, or in
-- that lane's push mode within 4000: walking in), or when we have fewer alive. It used to block on 2 enemies whatever
-- our numbers. The ally count is read only with 2+ enemies there, at most once per second per lane.
-- Logs (per team and lane, on change, repeated every 15s): [SHy-PUSH] push-gate why=lane-front-enemies / push-keep
-- why=outnumber.
local TempoRules = require(GetScriptDirectory() .. "/lib/systems/tempo_rules")
local LANE_FRONT_RADIUS = 2200
local LANE_FRONT_WALK_IN = 4000
local LANE_PUSH_MODE = {
	[Lane.Top] = BotMode.PushTowerTop,
	[Lane.Mid] = BotMode.PushTowerMid,
	[Lane.Bot] = BotMode.PushTowerBot,
}
local laneFrontAllies, laneFrontLog = {}, {}
local function CountLaneFrontAllies(lane, laneFrontLocation)
	local count = 0
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
		if Fu.IsValidHero(ally) and not ally:IsIllusion() then
			local dist = GetUnitToLocationDistance(ally, laneFrontLocation)
			if
				dist <= LANE_FRONT_RADIUS
				or dist <= LANE_FRONT_WALK_IN and ally:GetActiveMode() == LANE_PUSH_MODE[lane]
			then
				count = count + 1
			end
		end
	end
	return count
end
local function LogLaneFront(team, lane, why, enemies, allies, aliveUs, aliveThem)
	local now = DotaTime()
	local byTeam = laneFrontLog[team] or {}
	laneFrontLog[team] = byTeam
	local last = byTeam[lane] or { why = nil, at = -999 }
	local changed = last.why ~= why
	if changed and now - last.at < 3 or not changed and (why == nil or now - last.at < 15) then
		return
	end
	byTeam[lane] = { why = why, at = now }
	if why == nil then
		return
	end
	print(
		string.format(
			"[SHy-PUSH] t=%.0f %s %s lane=%d enemies=%d allies=%d alive=%d/%d",
			now,
			team == TEAM_DIRE and "dire" or "radiant",
			why == "outnumber" and "push-keep why=outnumber"
				or ("push-gate why=lane-front-enemies gate=" .. tostring(why)),
			lane,
			enemies,
			allies,
			aliveUs,
			aliveThem
		)
	)
end
function Push.LaneFrontBlocked(team, lane, laneFrontLocation)
	local enemies = Fu.Utils.CountEnemyHeroesNear(laneFrontLocation, LANE_FRONT_RADIUS)
	if enemies < TempoRules.LANE_FRONT_MIN_ENEMIES then
		LogLaneFront(team, lane, nil, enemies, 0, 0, 0)
		return false
	end
	local now = DotaTime()
	local byTeam = laneFrontAllies[team] or {}
	laneFrontAllies[team] = byTeam
	local cached = byTeam[lane]
	if cached == nil or now - cached.at >= 1 or now < cached.at then
		cached = { at = now, allies = CountLaneFrontAllies(lane, laneFrontLocation) }
		byTeam[lane] = cached
	end
	local gameState = getGlobalGameState()
	local aliveUs, aliveThem = gameState.aliveAllyCount or 0, gameState.aliveEnemyCount or 0
	local blocked, why = TempoRules.LaneFrontBlocks(enemies, cached.allies, aliveUs, aliveThem)
	LogLaneFront(team, lane, why, enemies, cached.allies, aliveUs, aliveThem)
	return blocked
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
	local currentTime = gameMode == 23 and dotaTime * 2 or dotaTime
	gameStateCache = {
		lastUpdate = now,
		currentTime = currentTime,
		gameMode = gameMode,
		team = team,
		enemyTeam = enemyTeam,
		ourAncient = GetAncient(team),
		enemyAncient = GetAncient(enemyTeam),
		aliveAllyCount = Fu.GetNumOfAliveHeroes(false),
		aliveEnemyCount = Fu.GetNumOfAliveHeroes(true),
		aliveAllyCoreCount = Fu.GetAliveCoreCount(false),
		aliveEnemyCoreCount = Fu.GetAliveCoreCount(true),
		teamNetworth = Fu.GetInventoryNetworth(),
		enemyNetworth = select(2, Fu.GetInventoryNetworth()),
		averageLevel = Fu.GetAverageLevel(false),
		hasAegis = Fu.DoesTeamHaveAegis(),
		isEarlyGame = Fu.IsEarlyGame(),
		isMidGame = Fu.IsMidGame(),
		isLateGame = Fu.IsLateGame(),
		isLaningPhase = Fu.IsInLaningPhase(),
	}
	return gameStateCache
end
function getLocationState()
	local now = DotaTime()
	if locationStateCache and now - locationStateCache.lastUpdate < stateCacheSeconds then
		return locationStateCache
	end
	local team = GetTeam()
	locationStateCache = {
		lastUpdate = now,
		laneFronts = {
			[Lane.Top] = GetLaneFrontLocation(team, Lane.Top, 0),
			[Lane.Mid] = GetLaneFrontLocation(team, Lane.Mid, 0),
			[Lane.Bot] = GetLaneFrontLocation(team, Lane.Bot, 0),
		},
		teamFountain = Fu.GetTeamFountain(),
		enemyFountain = Fu.GetTeamFountain(),
		roshanLocation = Fu.GetCurrentRoshanLocation(),
		tormentorLocation = Fu.GetTormentorLocation(team),
		tormentorWaitingLocation = Fu.GetTormentorWaitingLocation(team),
	}
	return locationStateCache
end
function getUnitState()
	local now = DotaTime()
	if unitStateCache and now - unitStateCache.lastUpdate < stateCacheSeconds then
		return unitStateCache
	end
	unitStateCache = {
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
	}
	return unitStateCache
end
-- The gate that returned no push this think, for [SHy-PUSH] push-gate (#12, game 072 10:11-10:38: Winter Wyvern's push
-- of a nearly dead T1 fell to 0 every other think and nobody could tell which rule did it).
local function NoPush(bot, why)
	bot._pushGate = why
	return BotModeDesire.None
end
-- This lane's push group for a bot that is alone (PushRules.AloneGate): other allies within 3000 of the lane front, or
-- in this lane's push mode within 6000 of it (walking in). Returns the group size, how many of them are at the front,
-- and where they stand (their average position: where PushThink walks a joiner).
local JOIN_FRONT_RADIUS = 3000
local JOIN_WALK_IN_RADIUS = 6000
local function LaneGroup(bot, lane, laneFrontLocation)
	local group, atFront, sumX, sumY = 0, 0, 0, 0
	for i = 1, 5 do
		local member = GetTeamMember(i)
		if member ~= nil and member ~= bot and member:IsAlive() and not member:IsIllusion() then
			local dist = GetUnitToLocationDistance(member, laneFrontLocation)
			local front = dist <= JOIN_FRONT_RADIUS
			if front or dist <= JOIN_WALK_IN_RADIUS and member:GetActiveMode() == LANE_PUSH_MODE[lane] then
				group = group + 1
				atFront = atFront + (front and 1 or 0)
				local location = member:GetLocation()
				sumX, sumY = sumX + location.x, sumY + location.y
			end
		end
	end
	if group == 0 then
		return 0, 0, nil
	end
	return group, atFront, Vector(sumX / group, sumY / group, laneFrontLocation.z or 0)
end
function Push.GetPushDesireHelper(bot, lane)
	if bot.laneToPush == nil then
		bot.laneToPush = lane
	end
	maxPushDesire = 0.525
	pushCapSrc = ""
	autoCleanupCache()
	local gameState = getGlobalGameState()
	local locationState = getGlobalLocationState()
	local team = gameState.team
	refreshThreatState(team)
	local killWindow = KillWindow.Tick()
	local killOpen = killWindow.fresh >= 1
		and not killWindow.buyback
		and gameState.aliveAllyCount > gameState.aliveEnemyCount
		and Fu.GetHP(bot) >= 0.3
	local killPush = killOpen and enemyHeroesAtAncient < 1 and not MustStayForBase(bot)
	if killOpen and not killPush then
		KillWindow.LogPushHeld(bot, lane, killWindow, baseThreat.why)
	end
	if killWindow.buyback then
		return NoPush(bot, "buyback")
	end
	local activeMode = bot:GetActiveMode()
	local isAssignedLane = bot:GetAssignedLane() == lane
	enemyAncient = gameState.enemyAncient
	if gameState.isLateGame then
		maxPushDesire = 0.65
	elseif gameState.isMidGame then
		maxPushDesire = 0.575
	end
	-- Advantage window (#12): Aegis with 4+ alive, or enemies dead (PushRules.Advantage). The group push may go up to
	-- its desire; the all-alive cap (0.41) and fewer-than-alive (0.4) are lifted for it below, the own-HP, high-ground
	-- and alone-vs-2 caps stay.
	local adv = ReadAdvantage(gameState, bot)
	local advDesire = (not gameState.isLaningPhase) and adv.desire or nil
	if advDesire ~= nil then
		maxPushDesire = math.max(maxPushDesire, advDesire)
	end
	if gameState.isLaningPhase and not isAssignedLane and Fu.IsCore(bot) then
		return NoPush(bot, "laning-not-assigned")
	end
	if gameState.aliveAllyCount <= gameState.aliveEnemyCount - 2 then
		return NoPush(bot, "outnumbered-alive")
	end
	if wasDefendPinged then
		return NoPush(bot, "defend-ping")
	end
	-- Base threat still cancels most pushes, but allow finishing a live HG fight.
	if enemyHeroesAtAncient >= 1 then
		local isNearEnemyAncient = enemyAncient and GetUnitToUnitDistance(bot, enemyAncient) < 2500
		local alliesNearby = #Fu.GetAlliesNearLoc(bot:GetLocation(), 1600)
		if not (isNearEnemyAncient and alliesNearby >= 3 and gameState.aliveAllyCount >= gameState.aliveEnemyCount) then
			return NoPush(bot, "base-heroes")
		end
	end
	if laneFrontHasEnemies[lane] then
		return NoPush(bot, "lane-front-enemies")
	end
	if gameState.isLaningPhase then
		do
			local i = 1
			while i <= 5 do
				local teamMember = GetTeamMember(i)
				if teamMember ~= nil and teamMember:GetLevel() < 6 then
					return NoPush(bot, "laning-low-level")
				end
				i = i + 1
			end
		end
	end
	local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1600)
	local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1600)
	local allyCoreCount = 0
	local enemyCoreCount = 0
	for _, allyHero in ipairs(nearbyAllies) do
		if Fu.IsValidHero(allyHero) and Fu.IsCore(allyHero) then
			allyCoreCount = allyCoreCount + 1
		end
	end
	for _, enemyHero in ipairs(nearbyEnemies) do
		if Fu.IsValidHero(enemyHero) and Fu.IsCore(enemyHero) then
			enemyCoreCount = enemyCoreCount + 1
		end
	end
	if
		#nearbyAllies < #nearbyEnemies and allyCoreCount < enemyCoreCount
		or #nearbyAllies <= 1 and #nearbyEnemies > 0
	then
		return NoPush(bot, "outnumbered-near")
	end
	if activeMode == BotMode.PushTowerTop then
		bot.laneToPush = Lane.Top
	elseif activeMode == BotMode.PushTowerMid then
		bot.laneToPush = Lane.Mid
	elseif activeMode == BotMode.PushTowerBot then
		bot.laneToPush = Lane.Bot
	end
	local alliesNearBot = getCachedAlliesNearLoc(bot:GetLocation(), 1600)
	local enemiesNearBot = getCachedEnemiesNearLoc(bot:GetLocation(), 1600)
	local enemyFountainTpPoint = team == Team.Radiant and direFountainTpPoint or radiantFountainTpPoint
	local laneFrontLocation = GetLaneFrontLocation(team, lane, 0)
	-- All enemies alive (#12, game 067 33:00: `lock-capped why=cap desire=0.41 allies=2 alive=5/5`, 3 of 5 farmed):
	-- ahead (2000+ net worth or 1+ level) or the target a T1/T2, 3-4 bots (closest to the lane front) may join a group
	-- push that is already on this lane (PushRules.FiveAliveCap); the rest keep the 0.41 cap.
	-- Worked out only with every enemy alive and a group already on this lane (per think, per lane: keep it cheap).
	local fiveCap, fiveJoiners, fiveWhy = nil, 5, "off"
	local fiveInputs = { nwLead = 0, levelLead = 0, tier = 0 }
	local laneRank = -1
	if gameState.aliveEnemyCount >= 5 and gameState.aliveAllyCount <= gameState.aliveEnemyCount then
		fiveCap, fiveJoiners, fiveWhy = 0.41, 2, "no-group"
		if lockedPushLane == lane and DotaTime() < (lockedPushLaneUntil or -999) then
			fiveInputs = {
				enemiesAlive = gameState.aliveEnemyCount,
				alliesAlive = gameState.aliveAllyCount,
				nwLead = (gameState.teamNetworth or 0) - (gameState.enemyNetworth or 0),
				levelLead = (gameState.averageLevel or 0) - Fu.GetAverageLevel(true),
				tier = Push.GetLaneBuildingTier(lane),
			}
			fiveCap, fiveJoiners, fiveWhy = PushRules.FiveAliveCap(fiveInputs)
			laneRank = AllyRankTo(bot, laneFrontLocation)
		end
	end
	local fiveJoiner = fiveCap ~= nil and fiveCap > 0.41 and laneRank >= 0 and laneRank < fiveJoiners
	-- Alone (no ally within 1600, 3+ enemies alive; PushRules.AloneGate): in an advantage window or as a joiner of an
	-- all-alive group push the bot comes to the group as before. Otherwise it walks to this lane's push group when there
	-- is one (2+ allies at the front or walking in, push-gate why=alone-join; PushThink walks it to them) and drops
	-- only when nobody else is on this lane's push. While it walks in, the caps that count allies near the bot count
	-- the group it is joining: fewer-than-alive and hurt-near-ancient the whole group (alliesCounted), the high-ground
	-- cap only the allies already at the front (hgAlliesCounted).
	local alliesCounted, hgAlliesCounted = #alliesNearBot, #alliesNearBot
	bot._pushJoin = bot._pushJoin or {}
	local now = DotaTime()
	local join = bot._pushJoin[lane]
	if join ~= nil and now - (join.seenAt or -999) > 5 then
		join = nil
		bot._pushJoin[lane] = nil
	end
	if #alliesNearBot <= 1 and gameState.aliveEnemyCount >= 3 then
		local group, atFront, spot = 0, 0, nil
		if #enemiesNearBot == 0 and advDesire == nil and not fiveJoiner then
			group, atFront, spot = LaneGroup(bot, lane, laneFrontLocation)
		end
		join = join or { since = now }
		join.seenAt = now
		local gate, gateWhy = PushRules.AloneGate({
			alliesNear = #alliesNearBot,
			enemiesAlive = gameState.aliveEnemyCount,
			enemiesNear = #enemiesNearBot,
			window = advDesire ~= nil or fiveJoiner,
			group = group,
			joinAge = now - join.since,
		})
		-- The join clock runs only while walking to a group; a timed-out join stays out until the bot is not alone.
		bot._pushJoin[lane] = (gate == "join" or gateWhy == "join-timeout") and join or nil
		if gate == "drop" then
			return NoPush(bot, gateWhy)
		elseif gate == "join" then
			alliesCounted = math.max(alliesCounted, group + 1)
			-- The high-ground cap counts only the group already at the front (not allies still walking in), so a joiner
			-- is never released up their high ground with nobody standing there.
			hgAlliesCounted = math.max(hgAlliesCounted, atFront + 1)
			join.at, join.spot, join.group, join.atFront, join.age = now, spot, group, atFront, now - join.since
		end
	elseif join ~= nil then
		-- Not alone any more: met the group (one line when it had walked to them).
		bot._pushJoin[lane] = nil
		if
			join.walked
			and #alliesNearBot >= 2
			and now - join.since <= PushRules.ALONE_JOIN_MAX_SECONDS
			and not Fu.IsMeepoClone(bot)
		then
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s push-join-arrived lane=%s group=%d allies=%d age=%.0f",
					now,
					ShortHeroName(bot),
					tostring(lane),
					join.group or 0,
					#alliesNearBot,
					now - join.since
				)
			)
		end
	end
	if fiveCap ~= nil and advDesire == nil then
		if fiveJoiner then
			maxPushDesire = math.max(maxPushDesire, fiveCap)
		else
			CapPush(0.41, "five")
		end
	end
	local isNearEnemyFountain = getLocationToLocationDistance(laneFrontLocation, enemyFountainTpPoint) < 5000
	-- Their Ancient open and us ahead (#12, game 068 50:33): the fewer-than-alive caps count the enemies seen near.
	local ancientOpen, ahead = AncientOpenAndAhead(gameState)
	-- Not when every enemy hero is dead (game 045, 28:18: 3 alive vs 0, push capped at 0.15, Dire left for Roshan).
	-- In a window from enemy deaths, 2 allies at the high ground are enough (an Aegis window still needs 3).
	-- A bot of an allowed group push gathers below their high ground instead of being cut to 0.15 (PushRules.HgGather,
	-- game 068 52:33-54:00): an advantage window, or a joiner of an all-alive push whose group the fewer-than-alive cap
	-- would let up (their Ancient open and us ahead).
	local hgAllies = (advDesire ~= nil and (adv.dead or 0) >= 2) and 2 or 3
	local hgMode = "none"
	if isNearEnemyFountain and gameState.aliveEnemyCount > 0 then
		hgMode = ReadHgGather(bot, lane, {
			team = team,
			enemyFountain = enemyFountainTpPoint,
			enemiesAlive = gameState.aliveEnemyCount,
			alliesAlive = gameState.aliveAllyCount,
			alliesNear = hgAlliesCounted,
			need = hgAllies,
			groupAllowed = advDesire ~= nil or fiveJoiner and hgAllies >= PushRules.FewerThanAliveCount(
				ancientOpen,
				ahead,
				gameState.aliveEnemyCount,
				#enemiesNearBot
			),
			why = advDesire ~= nil and ("adv:" .. tostring(adv.why)) or ("join:" .. fiveWhy),
		})
		if hgMode == "cap" then
			CapPush(0.15, "hg")
		end
	end
	-- With every enemy dead (wipe) the own-HP cap starts at 30% (game 067 t=1376: `lock-capped why=cap desire=0.25
	-- alive=4/0` held the push of a bot at 30-50% HP while nobody could defend). In an advantage window (dead enemies
	-- or the Aegis) with no enemy hero near: 40%; the Aegis holder 30%; a capped bot lets go 5% higher
	-- (PushRules.OwnHpCap, game 068 2331-2376, game 069 1543-1640).
	local wipeWindow = advDesire ~= nil and gameState.aliveEnemyCount == 0
	local ownHpCapped = Fu.GetHP(bot)
		< PushRules.OwnHpCap({
			wipe = wipeWindow,
			window = advDesire ~= nil,
			aegisHolder = advDesire ~= nil and Fu.IsHaveAegis(bot),
			enemiesNear = #enemiesNearBot,
			wasCapped = bot._ownHpCapped == true,
		})
	bot._ownHpCapped = ownHpCapped
	if ownHpCapped then
		CapPush(0.25, "own-hp")
	end
	if Fu.IsDoingRoshan(bot) and #Fu.GetAlliesNearLoc(locationState.roshanLocation, 2800) >= 3 then
		return NoPush(bot, "roshan")
	end
	local ourAncient = gameState.ourAncient
	if Fu.IsValidBuilding(ourAncient) and Push.IsHealthyInsideFountain(bot) then
		local enemiesNearAncient = Fu.GetEnemiesNearLoc(ourAncient:GetLocation(), 1000)
		if
			gameState.aliveAllyCount >= #enemiesNearAncient
			and gameState.aliveAllyCoreCount >= gameState.aliveEnemyCoreCount
		then
			return 0.6
		end
	end
	if
		enemyAncient
		and GetUnitToUnitDistance(bot, enemyAncient) < 1000
		and Fu.CanBeAttacked(enemyAncient)
		and Fu.GetHP(bot) > 0.4
		and not Push.HasBackdoorProtect(enemyAncient)
	then
		bot:SetTarget(enemyAncient)
		bot:Action_AttackUnit(enemyAncient, true)
		return 0.6
	end
	-- Game 037 (30:34 and 33:36, 3-0 each): with all five Dire alive and Dire ahead, the lock capped
	-- push to 0.40 at the Dire bottom T2 and the bots stayed there (capped push was still their top
	-- mode) until Dire came. Behind (enemy net worth 2000+ higher, or our average level 1+ lower) with
	-- every enemy alive and the lane's next target a T2 or deeper: no push on that lane. An Aegis push
	-- still goes. The per-lane flag (GameStates.enemyHalfOff[lane]) also walks farm off the enemy half
	-- on that lane for 20s (mode_farm_generic).
	do
		local enemyPlayers = #GetTeamPlayers(GetOpposingTeam())
		local allEnemiesAlive = enemyPlayers > 0 and gameState.aliveEnemyCount >= enemyPlayers
		local behindNetworth = (gameState.enemyNetworth or 0) > (gameState.teamNetworth or 0) + 2000
		local behindLevel = Fu.GetAverageLevel(true) >= (gameState.averageLevel or 0) + 1
		local tier = Push.GetLaneBuildingTier(lane)
		if
			allEnemiesAlive
			and gameState.aliveEnemyCount >= gameState.aliveAllyCount
			and (behindNetworth or behindLevel)
			and tier >= 2
			and not (gameState.hasAegis and gameState.aliveAllyCount >= 4)
			and not gameState.isLaningPhase
		then
			Fu.Utils.GameStates = Fu.Utils.GameStates or {}
			Fu.Utils.GameStates.enemyHalfOff = Fu.Utils.GameStates.enemyHalfOff or {}
			Fu.Utils.GameStates.enemyHalfOff[lane] = DotaTime() + 20
			if DotaTime() >= (bot._pushBehindLogAt or -999) and not Fu.IsMeepoClone(bot) then
				bot._pushBehindLogAt = DotaTime() + 5
				pcall(
					print,
					string.format(
						"[SHy-PUSH] t=%.0f %s behind-stop lane=%s tier=%d alive=%d/%d nw=%d/%d lvl=%.1f/%.1f",
						DotaTime(),
						(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
						tostring(lane),
						tier,
						gameState.aliveAllyCount,
						gameState.aliveEnemyCount,
						math.floor(gameState.teamNetworth or 0),
						math.floor(gameState.enemyNetworth or 0),
						gameState.averageLevel or 0,
						Fu.GetAverageLevel(true)
					)
				)
			end
			return NoPush(bot, "behind-stop")
		end
	end
	local attackTarget = bot:GetAttackTarget()
	-- Wait for creeps instead of fully dropping push when backdoor protection is up.
	-- Not in a wipe. Not for the Glyph (#12, game 074): it ends in 7s and the group waits it out at the tower
	-- (GlyphWaitThink), so the push is not capped for it.
	if Fu.IsValidBuilding(attackTarget) and Push.HasBackdoorOnly(attackTarget) and not wipeWindow then
		CapPush(0.25, "backdoor")
	end
	local anyLaneBarracksDown = not Fu.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Top)
		or not Fu.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Mid)
		or not Fu.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Bot)
	local isSiegingAncient = false
	if anyLaneBarracksDown and enemyAncient then
		local distanceToAncient = GetUnitToUnitDistance(bot, enemyAncient)
		local alliesNearAncient = Fu.GetAlliesNearLoc(enemyAncient:GetLocation(), 3000)
		if distanceToAncient < 3000 and #alliesNearAncient >= 2 then
			isSiegingAncient = true
		end
	end
	local aliveAllyCount = gameState.aliveAllyCount
	local aliveEnemyCount = gameState.aliveEnemyCount
	if teamPushLane == nil then
		teamPushLane = Push.WhichLaneToPush(bot, lane)
	end
	local isTeamPushLane = teamPushLane == lane
	local hasHumanEnemy = Fu.Utils.IsHumanPlayerInTeam(GetOpposingTeam())
	if hasHumanEnemy then
		local laneTarget = getLaneTargetBuilding(lane)
		if laneTarget == nil or not Fu.IsValidBuilding(laneTarget) then
			return NoPush(bot, "no-lane-target")
		end
	else
		local distanceToEnemyFountain = getLocationToLocationDistance(bot:GetLocation(), enemyFountainTpPoint)
		local isBotNearEnemyFountain = distanceToEnemyFountain < 5000
		local botLaneToPush = bot.laneToPush
		local isLaneBarracksAlive = Fu.Utils.IsAnyBarracksOnLaneAlive(false, lane)
		if isBotNearEnemyFountain and lane == botLaneToPush and isLaneBarracksAlive then
		elseif not isTeamPushLane then
			return NoPush(bot, "not-team-lane")
		end
	end
	local pushingTeammates = 0
	local teamPlayers = GetTeamPlayers(gameState.team)
	do
		local i = 1
		while i <= #teamPlayers do
			local teamMember = GetTeamMember(i)
			if teamMember ~= nil and teamMember:IsAlive() and teamMember ~= bot then
				local memberMode = teamMember:GetActiveMode()
				local isMemberPushing = memberMode == BotMode.PushTowerTop
					or memberMode == BotMode.PushTowerMid
					or memberMode == BotMode.PushTowerBot
				local isMemberAtFront = GetUnitToLocationDistance(teamMember, laneFrontLocation) < 2500
				if isMemberPushing or isMemberAtFront then
					pushingTeammates = pushingTeammates + 1
				end
			end
			i = i + 1
		end
	end
	if isBotOnlyGame == nil then
		isBotOnlyGame = not Fu.Utils.IsHumanPlayerInTeam(GetTeam())
			and not Fu.Utils.IsHumanPlayerInTeam(GetOpposingTeam())
	end
	-- Finish a tower the group can kill (#12, game 047 ~18:00: Radiant went back and forth under Dire's bottom T2 while
	-- it was nearly dead, the backdoor and low-HP caps holding push at 0.25). Under 25% HP, or the damage of the allies
	-- near it over 5s beats its HP, with 2+ allies there: push at 0.9 whatever the caps.
	local function FinishTower()
		local tower = (bot:GetNearbyTowers(1200, true) or {})[1]
		if not Fu.IsValidBuilding(tower) or not tower:IsAlive() then
			return false
		end
		local frontDist = getLocationToLocationDistance(GetLaneFrontLocation(team, lane, 0), tower:GetLocation())
		-- A save Glyph kills our wave at the tower and the lane front jumps back (game 073 t=1492-1496: front=6392, all
		-- five walked 5000-6500 away from Dire's top T2 at 655 HP). While the tower has the Glyph and no backdoor
		-- protection, the group at it still counts (the hold waits the Glyph out).
		local glyphOnly = tower:HasModifier("modifier_fountain_glyph") and not Push.HasBackdoorOnly(tower)
		if frontDist >= 2500 and not glyphOnly then
			if
				tower:GetHealth() / math.max(1, tower:GetMaxHealth()) < 0.5
				and DotaTime() >= ((bot._finishTowerCheckAt or {})[lane] or -999)
			then
				bot._finishTowerCheckAt = bot._finishTowerCheckAt or {}
				bot._finishTowerCheckAt[lane] = DotaTime() + 15
				pcall(
					print,
					string.format(
						"[SHy-PUSH] t=%.0f %s finish-tower-check hp=%d why=lane-front front=%d lane=%s",
						DotaTime(),
						(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
						tower:GetHealth(),
						math.floor(frontDist),
						tostring(lane)
					)
				)
			end
			return false
		end
		do
			local towerAllies = 0
			local damage5s = 0
			for _, ally in pairs(Fu.GetAlliesNearLoc(tower:GetLocation(), 1200) or {}) do
				if Fu.IsValidHero(ally) and not ally:IsIllusion() then
					towerAllies = towerAllies + 1
					damage5s = damage5s + (ally:GetEstimatedDamageToTarget(true, tower, 5.0, DAMAGE_TYPE_ALL) or 0)
				end
			end
			local towerHp = tower:GetHealth()
			local finish = towerAllies >= 2
				and (towerHp / math.max(1, tower:GetMaxHealth()) < 0.25 or damage5s >= towerHp)
			-- Diagnostic: a hurt tower near the group, whether the rule fires (game 048: it never did).
			if not finish and towerHp / math.max(1, tower:GetMaxHealth()) < 0.5 then
				if DotaTime() >= ((bot._finishTowerCheckAt or {})[lane] or -999) then
					bot._finishTowerCheckAt = bot._finishTowerCheckAt or {}
					bot._finishTowerCheckAt[lane] = DotaTime() + 15
					pcall(
						print,
						string.format(
							"[SHy-PUSH] t=%.0f %s finish-tower-check hp=%d dmg5s=%d allies=%d lane=%s",
							DotaTime(),
							(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
							towerHp,
							math.floor(damage5s),
							towerAllies,
							tostring(lane)
						)
					)
				end
			end
			if finish then
				-- Read by the Roshan yield in Push.GetPushDesire: a tower about to fall goes first.
				bot._finishTowerAt = DotaTime()
				-- The finish hold (FinishHoldDesire) keeps this push through the other gates until the tower falls.
				local hold = bot._finishHold
				if hold == nil or hold.tower ~= tower or hold.lane ~= lane then
					bot._finishHold = { lane = lane, tower = tower, start = DotaTime() }
				end
				if DotaTime() >= (bot._finishTowerLogAt or -999) then
					bot._finishTowerLogAt = DotaTime() + 10
					pcall(
						print,
						string.format(
							"[SHy-PUSH] t=%.0f %s finish-tower hp=%d dmg5s=%d allies=%d lane=%s",
							DotaTime(),
							(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
							towerHp,
							math.floor(damage5s),
							towerAllies,
							tostring(lane)
						)
					)
				end
				return true
			end
		end
		return false
	end
	if isBotOnlyGame and not gameState.isLaningPhase and not gameState.isEarlyGame then
		if pushingTeammates >= 2 and lane == teamPushLane then
			local laneFront = GetLaneFrontLocation(team, lane, 0)
			local ourFountainTpPoint = team == Team.Radiant and radiantFountainTpPoint or direFountainTpPoint
			local distanceToOurFountain = getLocationToLocationDistance(laneFront, ourFountainTpPoint)
			local distanceToEnemyFountain = getLocationToLocationDistance(laneFront, enemyFountainTpPoint)
			if distanceToEnemyFountain < distanceToOurFountain then
				lockedPushLane = lane
				lockedPushLaneUntil = DotaTime() + 8
			end
		end
		if lockedPushLane ~= nil and DotaTime() < lockedPushLaneUntil then
			if lane == lockedPushLane then
				-- Game 036 (23:25, 30:01, 35:11): this lock returned before every later safety cap, so
				-- four bots stayed on the Dire high ground with all 5 Dire alive and got wiped. The
				-- caps now apply inside the lock: maxPushDesire already holds the HG / own-HP / 5-alive caps.
				local lockDesire = math.max(0.55, RemapValClamped(GetPushLaneDesire(lane), 0, 1, 0, maxPushDesire))
				-- Advantage window / a joiner of an all-alive push (#12): raised to the group's desire, then the caps' order
				-- (PushRules.LockDesire, tested in tests/test_push_rules.lua). A wipe (no enemy alive) skips group-hurt; the
				-- advantage window skips fewer-than-alive.
				local groupHurt = false
				if isNearEnemyFountain and #alliesNearBot >= 2 then
					local hurtCount, hpSum = 0, 0
					for _, allyHero in ipairs(alliesNearBot) do
						if Fu.IsValidHero(allyHero) then
							local allyHp = Fu.GetHP(allyHero)
							hpSum = hpSum + allyHp
							if allyHp < 0.4 then
								hurtCount = hurtCount + 1
							end
						end
					end
					groupHurt = hurtCount >= 2 and hpSum / #alliesNearBot < 0.6
				end
				local capReason, raisedWhy
				lockDesire, capReason, raisedWhy = PushRules.LockDesire({
					base = lockDesire,
					advantage = advDesire,
					joinCap = fiveJoiner and fiveCap or nil,
					maxPush = maxPushDesire,
					alliesNear = alliesCounted,
					enemiesNear = #enemiesNearBot,
					enemiesAlive = gameState.aliveEnemyCount,
					tier = Push.GetLaneBuildingTier(lane),
					nearAncient = enemyAncient ~= nil and GetUnitToUnitDistance(bot, enemyAncient) < 6000,
					groupHurt = groupHurt,
					gathering = hgMode == "gather",
					ancientOpen = ancientOpen,
					ahead = ahead,
				})
				if raisedWhy == "advantage" then
					raisedWhy = "advantage:" .. tostring(adv.why)
				elseif raisedWhy == "join" then
					raisedWhy = "join:" .. fiveWhy
				end
				if capReason ~= nil and DotaTime() >= (bot._pushLockCapLogAt or -999) and not Fu.IsMeepoClone(bot) then
					bot._pushLockCapLogAt = DotaTime() + 5
					pcall(
						print,
						string.format(
							"[SHy-PUSH] t=%.0f %s lock-capped lane=%s why=%s desire=%.2f allies=%d enemies=%d alive=%d/%d hg=%s five=%s cap=%s joiners=%d rank=%d nwLead=%d lvlLead=%.1f tier=%d adv=%s hp=%.2f src=%s hgMode=%s",
							DotaTime(),
							(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
							tostring(lane),
							capReason,
							lockDesire,
							#alliesNearBot,
							#enemiesNearBot,
							gameState.aliveAllyCount,
							gameState.aliveEnemyCount,
							tostring(isNearEnemyFountain),
							fiveWhy,
							fiveCap ~= nil and string.format("%.2f", fiveCap) or "-",
							fiveJoiners,
							laneRank,
							math.floor(fiveInputs.nwLead),
							fiveInputs.levelLead,
							fiveInputs.tier,
							advDesire ~= nil and tostring(adv.why) or "-",
							Fu.GetHP(bot),
							pushCapSrc == "" and "-" or pushCapSrc,
							hgMode
						)
					)
				end
				if FinishTower() then
					return math.max(lockDesire, 0.9)
				end
				if raisedWhy ~= nil and capReason == nil then
					bot._pushRaisedAt, bot._pushRaisedWhy = DotaTime(), raisedWhy
					if advDesire ~= nil then
						LogAdvantagePush(bot, lane, adv, lockDesire, #alliesNearBot, gameState)
					else
						LogGroupJoin(bot, lane, fiveWhy, lockDesire, laneRank, fiveJoiners, fiveInputs)
					end
				end
				return lockDesire
			else
				return NoPush(bot, "lock-other-lane")
			end
		else
			lockedPushLane = nil
		end
	end
	local laneDesire = RemapValClamped(GetPushLaneDesire(lane), 0, 1, 0, maxPushDesire)
	local botLevel = bot:GetLevel()
	local hpRatio = Fu.GetHP(bot)
	local allyCoreCount = gameState.aliveAllyCoreCount
	local enemyCoreCount = gameState.aliveEnemyCoreCount
	local canPush = aliveEnemyCount == 0
		or allyCoreCount >= enemyCoreCount
		or allyCoreCount >= 1 and aliveAllyCount >= aliveEnemyCount + 2
		or enemyAncient and GetUnitToUnitDistance(bot, enemyAncient) < 3500 and #alliesNearBot >= #enemiesNearBot
	if not canPush then
		return NoPush(bot, "cannot-push")
	end
	if not gameState.isEarlyGame then
		if gameState.hasAegis and aliveAllyCount >= 4 then
			laneDesire = laneDesire + 0.25
			-- Not over a cap that already applied (#12, games 082-085: `advantage-push why=aegis desire=0.60` from Puck at
			-- 12-32% HP with allies=1: this lift undid the own-HP and high-ground caps; which cap held the healthy ones with
			-- allies=3 at 0.60, e.g. Largo at the mid T3 in game 082 t=1091, is unverified: aegis-lift-skip names it).
			if pushCapSrc == "" then
				maxPushDesire = math.max(maxPushDesire, 0.6)
			elseif DotaTime() >= (bot._aegisLiftSkipLogAt or -999) and not Fu.IsMeepoClone(bot) then
				bot._aegisLiftSkipLogAt = DotaTime() + 8
				pcall(
					print,
					string.format(
						"[SHy-PUSH] t=%.0f %s aegis-lift-skip lane=%s src=%s max=%.2f hp=%.2f allies=%d enemies=%d",
						DotaTime(),
						ShortHeroName(bot),
						tostring(lane),
						pushCapSrc,
						maxPushDesire,
						Fu.GetHP(bot),
						#alliesNearBot,
						#enemiesNearBot
					)
				)
			end
		end
		if aliveAllyCount >= aliveEnemyCount and gameState.averageLevel >= 12 then
			local networthLead = gameState.teamNetworth - gameState.enemyNetworth
			laneDesire = laneDesire + RemapValClamped(networthLead, 5000, 10000, 0, 0.5)
		end
	end
	local isReadyToPush = botLevel >= 6
		and (
			not gameState.isLaningPhase
			or aliveAllyCount >= aliveEnemyCount + 2
			or aliveEnemyCount <= 2 and aliveAllyCount >= 4
		)
	if enemyHeroesOnHighGround >= 2 and DotaTime() - recentDefendTime < 10 then
		return NoPush(bot, "hg-defend")
	end
	-- Not while gathering below their high ground; with their Ancient open and us ahead, against the enemies seen near
	-- (PushRules.FewerThanAliveCount, game 068 50:33).
	if enemyAncient and Push.GetLaneBuildingTier(lane) >= 2 and hgMode ~= "gather" then
		local distanceToEnemyAncient = GetUnitToUnitDistance(bot, enemyAncient)
		local enemyCount = PushRules.FewerThanAliveCount(ancientOpen, ahead, aliveEnemyCount, #enemiesNearBot)
		if
			distanceToEnemyAncient < 6000
			and alliesCounted + 1 < enemyCount
			and hpRatio < 0.65
			and not (killPush and #alliesNearBot >= 2 and #enemiesNearBot < #alliesNearBot)
		then
			return NoPush(bot, "hurt-near-ancient")
		elseif distanceToEnemyAncient < 6000 and alliesCounted < enemyCount and advDesire == nil then
			CapPush(0.4, "fewer-than-alive")
		end
	end
	local pushDesire = math.min(math.max(laneDesire, 0), maxPushDesire)
	-- Advantage window (#12): the team's push lane goes at the window's desire, under the caps still in maxPushDesire
	-- (own HP, high ground, backdoor); alone-vs-2 below still holds.
	if advDesire ~= nil and (teamPushLane == nil or teamPushLane == lane) and pushDesire < advDesire then
		local raised = math.min(advDesire, maxPushDesire)
		if raised > pushDesire then
			pushDesire = raised
			if raised >= 0.5 then
				bot._pushRaisedAt, bot._pushRaisedWhy = DotaTime(), "advantage:" .. tostring(adv.why)
				LogAdvantagePush(bot, lane, adv, raised, #alliesNearBot, gameState)
			end
		end
	end
	local earlyGameEnd = gameState.gameMode == 23 and 12 * 60 or 15 * 60
	if DotaTime() < earlyGameEnd then
		local laneTier = Push.GetLaneBuildingTier(lane)
		if laneTier >= 3 then
			local deadEnemyCount = 5 - aliveEnemyCount
			if deadEnemyCount < 2 then
				local otherLanes = lane == Lane.Top and { Lane.Mid, Lane.Bot }
					or (lane == Lane.Mid and { Lane.Top, Lane.Bot } or { Lane.Top, Lane.Mid })
				local anyOtherLaneOpen = arraySome(otherLanes, function(_, otherLane)
					return Push.GetLaneBuildingTier(otherLane) <= 2
				end)
				if anyOtherLaneOpen then
					pushDesire = math.min(pushDesire, 0.1)
				end
			end
		end
	end
	if #alliesNearBot <= 1 and #enemiesNearBot >= 2 then
		pushDesire = math.min(pushDesire, 0.2)
	end
	-- Wipe push (#12): with no enemy hero alive, a bot above 30% HP near this lane's front pushes it above Roshan
	-- and the walk home.
	if
		aliveEnemyCount == 0
		and Fu.GetHP(bot) >= 0.3
		and getLocationToLocationDistance(GetLaneFrontLocation(team, lane, 0), bot:GetLocation()) < 4000
	then
		pushDesire = math.max(pushDesire, 0.9)
		if DotaTime() >= (bot._wipePushLogAt or -999) then
			bot._wipePushLogAt = DotaTime() + 10
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s wipe-push lane=%s alive=%d/0 hp=%.2f",
					DotaTime(),
					(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
					tostring(lane),
					gameState.aliveAllyCount,
					Fu.GetHP(bot)
				)
			)
		end
	end
	if FinishTower() then
		pushDesire = math.max(pushDesire, 0.9)
	end
	local groupHurt = false
	if isNearEnemyFountain and #alliesNearBot >= 2 then
		local hurtCount = 0
		local hpSum = 0
		for _, allyHero in ipairs(alliesNearBot) do
			if Fu.IsValidHero(allyHero) then
				local allyHp = Fu.GetHP(allyHero)
				hpSum = hpSum + allyHp
				if allyHp < 0.4 then
					hurtCount = hurtCount + 1
				end
			end
		end
		local averageHp = #alliesNearBot > 0 and hpSum / #alliesNearBot or 1
		if hurtCount >= 2 and averageHp < 0.6 and aliveEnemyCount > 0 and aliveEnemyCount >= #alliesNearBot - 2 then
			pushDesire = math.min(pushDesire, 0.15)
			groupHurt = true
		end
	end
	if isBotOnlyGame then
		if not gameState.isLaningPhase then
			pushDesire = math.max(pushDesire, 0.02)
		end
		if isReadyToPush and hpRatio > 0.4 and not gameState.isEarlyGame then
			if aliveEnemyCount <= 2 and aliveAllyCount >= 4 then
				pushDesire = math.max(pushDesire, aliveEnemyCount == 0 and 0.525 or 0.45)
			end
			if isSiegingAncient then
				pushDesire = math.max(pushDesire, 0.5)
			end
		end
		if isTeamPushLane and Fu.GetPosition(bot) >= 4 then
			local laneMode = lane == Lane.Top and BotMode.PushTowerTop
				or (lane == Lane.Mid and BotMode.PushTowerMid or BotMode.PushTowerBot)
			local laneModeAllies = 0
			do
				local i = 1
				while i <= #GetTeamPlayers(GetTeam()) do
					local teamMember = GetTeamMember(i)
					if
						teamMember
						and teamMember ~= bot
						and teamMember:IsAlive()
						and teamMember:GetActiveMode() == laneMode
					then
						laneModeAllies = laneModeAllies + 1
					end
					i = i + 1
				end
			end
			if laneModeAllies >= 3 then
				pushDesire = math.max(pushDesire, maxPushDesire)
			end
		end
	end
	if isBotOnlyGame then
		local defendDesire = GetDefendLaneDesire(lane)
		local previousDefendDesire = lastDefendDesire[lane] or 0
		lastDefendDesire[lane] = defendDesire
		if previousDefendDesire > 0.3 and defendDesire < 0.15 then
			pushAfterDefendUntil[lane] = DotaTime() + pushAfterDefendSeconds
		end
		if pushAfterDefendUntil[lane] and DotaTime() < pushAfterDefendUntil[lane] then
			pushDesire = math.max(pushDesire, 0.45)
		end
	end
	-- A fresh kill lifts the high-ground caps. Buyback already returned none above.
	if
		killPush
		and not groupHurt
		and #alliesNearBot >= 2
		and #enemiesNearBot < #alliesNearBot
		and (teamPushLane == nil or teamPushLane == lane)
	then
		-- One death beats farm (VERYHIGH ~0.9) and loses to a close outpost (0.95).
		-- Two deaths beat the outpost channel itself (0.98 on the point).
		local floor = 0.91
		if killWindow.fresh >= 2 and Fu.GetHP(bot) >= 0.4 then
			floor = 0.99
		end
		if pushDesire < floor then
			KillWindow.LogPush(
				bot,
				lane,
				pushDesire,
				floor,
				killWindow,
				Fu.GetHP(bot),
				gameState.aliveAllyCount,
				gameState.aliveEnemyCount
			)
			pushDesire = floor
		end
	end
	return pushDesire
end
function discountLaneCost(cost, location)
	local alliesNearLocation = #Fu.GetAlliesNearLoc(location, 1600)
	return cost / (1 + 0.25 * alliesNearLocation)
end
function getLaneTargetBuilding(lane)
	local tick = math.floor(GameTime() * 10)
	local cached = laneTargetCache[lane]
	if cached and cached.tick == tick then
		return cached.result
	end
	local enemyTeam = GetOpposingTeam()
	local target = nil
	local towerIds = lane == Lane.Top and { Tower.Top1, Tower.Top2, Tower.Top3 }
		or (lane == Lane.Mid and { Tower.Mid1, Tower.Mid2, Tower.Mid3 } or { Tower.Bot1, Tower.Bot2, Tower.Bot3 })
	for _, towerId in ipairs(towerIds) do
		local tower = GetTower(enemyTeam, towerId)
		if tower ~= nil and tower:IsAlive() then
			target = tower
			break
		end
	end
	if not target then
		local barracksIds = lane == Lane.Top and { Barracks.TopRanged, Barracks.TopMelee }
			or (
				lane == Lane.Mid and { Barracks.MidRanged, Barracks.MidMelee }
				or { Barracks.BotRanged, Barracks.BotMelee }
			)
		for _, barracksId in ipairs(barracksIds) do
			local barracks = GetBarracks(enemyTeam, barracksId)
			if barracks ~= nil and barracks:IsAlive() then
				target = barracks
				break
			end
		end
	end
	if not target then
		local baseTower1 = GetTower(enemyTeam, Tower.Base1)
		local baseTower2 = GetTower(enemyTeam, Tower.Base2)
		if baseTower1 ~= nil and baseTower1:IsAlive() then
			target = baseTower1
		elseif baseTower2 ~= nil and baseTower2:IsAlive() then
			target = baseTower2
		end
	end
	if not target then
		local ancient = GetAncient(enemyTeam)
		if ancient ~= nil and ancient:IsAlive() then
			target = ancient
		end
	end
	laneTargetCache[lane] = { tick = tick, result = target }
	return target
end
function Push.WhichLaneToPush(bot, lane)
	local locationState = getLocationState()
	local gameState = getGameState()
	local topLaneCost = 0
	local midLaneCost = 0
	local botLaneCost = 0
	local topLaneFront = locationState.laneFronts[Lane.Top]
	local midLaneFront = locationState.laneFronts[Lane.Mid]
	local botLaneFront = locationState.laneFronts[Lane.Bot]
	local topLaneTarget = getLaneTargetBuilding(Lane.Top)
	local midLaneTarget = getLaneTargetBuilding(Lane.Mid)
	local botLaneTarget = getLaneTargetBuilding(Lane.Bot)
	local alliedHeroes = GetUnitList(UnitType.AlliedHeroes)
	for _, allyHero in ipairs(alliedHeroes) do
		if Fu.IsValidHero(allyHero) then
			local topCost = GetUnitToLocationDistance(allyHero, topLaneFront) * 0.9 * 0.6
			local midCost = GetUnitToLocationDistance(allyHero, midLaneFront) * 0.6
			local botCost = GetUnitToLocationDistance(allyHero, botLaneFront) * 0.9 * 0.6
			if topLaneTarget ~= nil then
				topCost = topCost + GetUnitToUnitDistance(allyHero, topLaneTarget) * 0.9 * 0.4
			end
			if midLaneTarget ~= nil then
				midCost = midCost + GetUnitToUnitDistance(allyHero, midLaneTarget) * 0.4
			end
			if botLaneTarget ~= nil then
				botCost = botCost + GetUnitToUnitDistance(allyHero, botLaneTarget) * 0.9 * 0.4
			end
			if Fu.IsCore(allyHero) and allyHero and not allyHero:IsBot() then
				topCost = topCost * 0.2
				midCost = midCost * 0.2
				botCost = botCost * 0.2
			elseif not Fu.IsCore(allyHero) then
				topCost = topCost * 1.5
				midCost = midCost * 1.5
				botCost = botCost * 1.5
			end
			topLaneCost = topLaneCost + topCost
			midLaneCost = midLaneCost + midCost
			botLaneCost = botLaneCost + botCost
		end
	end
	local enemiesAtTop = 0
	local enemiesAtMid = 0
	local enemiesAtBot = 0
	for _, playerId in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
		if IsHeroAlive(playerId) then
			local lastSeenInfo = GetHeroLastSeenInfo(playerId)
			if lastSeenInfo and lastSeenInfo ~= nil then
				local lastSeen = lastSeenInfo[1]
				if lastSeen and lastSeen ~= nil then
					if Fu.GetDistance(topLaneFront, lastSeen.location) <= 1600 then
						enemiesAtTop = enemiesAtTop + 1
					elseif Fu.GetDistance(midLaneFront, lastSeen.location) <= 1600 then
						enemiesAtMid = enemiesAtMid + 1
					elseif Fu.GetDistance(botLaneFront, lastSeen.location) <= 1600 then
						enemiesAtBot = enemiesAtBot + 1
					end
				end
			end
		end
	end
	local incomingTeleports = GetIncomingTeleports()
	for _, teleport in ipairs(incomingTeleports) do
		if teleport and Push.IsEnemyTP(teleport.playerid) then
			if Fu.GetDistance(topLaneFront, teleport.location) <= 1600 then
				enemiesAtTop = enemiesAtTop + 1
			elseif Fu.GetDistance(midLaneFront, teleport.location) <= 1600 then
				enemiesAtMid = enemiesAtMid + 1
			elseif Fu.GetDistance(botLaneFront, teleport.location) <= 1600 then
				enemiesAtBot = enemiesAtBot + 1
			end
		end
	end
	topLaneCost = topLaneCost * (0.05 * enemiesAtTop + 1)
	midLaneCost = midLaneCost * (0.05 * enemiesAtMid + 1)
	botLaneCost = botLaneCost * (0.05 * enemiesAtBot + 1)
	local topTier = Push.GetLaneBuildingTier(Lane.Top)
	local midTier = Push.GetLaneBuildingTier(Lane.Mid)
	local botTier = Push.GetLaneBuildingTier(Lane.Bot)
	topLaneCost = topLaneCost * RemapValClamped(topTier, 1, 3, 0.25, 1)
	midLaneCost = midLaneCost * RemapValClamped(midTier, 1, 3, 0.25, 1)
	botLaneCost = botLaneCost * RemapValClamped(botTier, 1, 3, 0.25, 1)
	local topBarracksDown = not Fu.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Top)
	local midBarracksDown = not Fu.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Mid)
	local botBarracksDown = not Fu.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Bot)
	if topBarracksDown and Fu.Utils.IsAnyBarracksOnLaneAlive(true, Lane.Top) then
		topLaneCost = topLaneCost * 0.15
	end
	if midBarracksDown and Fu.Utils.IsAnyBarracksOnLaneAlive(true, Lane.Mid) then
		midLaneCost = midLaneCost * 0.15
	end
	if botBarracksDown and Fu.Utils.IsAnyBarracksOnLaneAlive(true, Lane.Bot) then
		botLaneCost = botLaneCost * 0.15
	end
	topLaneCost = discountLaneCost(topLaneCost, topLaneFront)
	midLaneCost = discountLaneCost(midLaneCost, midLaneFront)
	botLaneCost = discountLaneCost(botLaneCost, botLaneFront)
	if topLaneCost < midLaneCost and topLaneCost < botLaneCost then
		return Lane.Top
	end
	if midLaneCost < topLaneCost and midLaneCost < botLaneCost then
		return Lane.Mid
	end
	if botLaneCost < topLaneCost and botLaneCost < midLaneCost then
		return Lane.Bot
	end
	return Lane.Mid
end
function Push.IsEnemyTP(playerId)
	local gameState = getGameState()
	for _, enemyPlayerId in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
		if enemyPlayerId == playerId then
			return true
		end
	end
	return false
end
function Push.GetSpecialUnitsNearby(bot, units, range)
	local unitState = getUnitState()
	local specialUnits = { unpack(units) }
	for _, unit in ipairs(unitState.enemyHeroes) do
		if isValidUnit(unit) and Fu.IsInRange(bot, unit, range) then
			local unitName = unit:GetUnitName()
			if
				stringIncludes(unitName, "invoker_forge_spirit")
				or stringIncludes(unitName, "lycan_wolf")
				or stringIncludes(unitName, "eidolon")
				or stringIncludes(unitName, "beastmaster_boar")
				or stringIncludes(unitName, "beastmaster_greater_boar")
				or stringIncludes(unitName, "furion_treant")
				or stringIncludes(unitName, "broodmother_spiderling")
				or stringIncludes(unitName, "skeleton_warrior")
				or stringIncludes(unitName, "warlock_golem")
				or unit:HasModifier("modifier_dominated")
				or unit:HasModifier("modifier_chen_holy_persuasion")
			then
				specialUnits[#specialUnits + 1] = unit
			end
		end
	end
	return specialUnits
end
function Push.IsHealthyInsideFountain(unit)
	return unit:HasModifier("modifier_fountain_aura_buff") and Fu.GetHP(unit) > 0.9 and Fu.GetMP(unit) > 0.85
end
function Push.GetAllyHeroesAttackingUnit(unit)
	local unitState = getUnitState()
	local attackers = {}
	for _, allyHero in ipairs(unitState.alliedHeroes) do
		if
			Fu.IsValidHero(allyHero)
			and not Fu.IsSuspiciousIllusion(allyHero)
			and not Fu.IsMeepoClone(allyHero)
			and allyHero:GetAttackTarget() == unit
		then
			attackers[#attackers + 1] = allyHero
		end
	end
	return attackers
end
function Push.GetAllyCreepsAttackingUnit(unit)
	local unitState = getUnitState()
	local attackers = {}
	for _, creep in ipairs(unitState.alliedCreeps) do
		if Fu.IsValid(creep) and creep:GetAttackTarget() == unit then
			attackers[#attackers + 1] = creep
		end
	end
	return attackers
end
function Push.GetLaneBuildingTier(lane)
	local gameState = getGameState()
	local enemyTeam = gameState.enemyTeam
	if lane == Lane.Top then
		if GetTower(enemyTeam, Tower.Top1) ~= nil then
			return 1
		elseif GetTower(enemyTeam, Tower.Top2) ~= nil then
			return 2
		elseif
			GetTower(enemyTeam, Tower.Top3) ~= nil
			or GetBarracks(enemyTeam, Barracks.TopMelee) ~= nil
			or GetBarracks(enemyTeam, Barracks.TopRanged) ~= nil
		then
			return 3
		else
			return 4
		end
	elseif lane == Lane.Mid then
		if GetTower(enemyTeam, Tower.Mid1) ~= nil then
			return 1
		elseif GetTower(enemyTeam, Tower.Mid2) ~= nil then
			return 2
		elseif
			GetTower(enemyTeam, Tower.Mid3) ~= nil
			or GetBarracks(enemyTeam, Barracks.MidMelee) ~= nil
			or GetBarracks(enemyTeam, Barracks.MidRanged) ~= nil
		then
			return 3
		else
			return 4
		end
	elseif lane == Lane.Bot then
		if GetTower(enemyTeam, Tower.Bot1) ~= nil then
			return 1
		elseif GetTower(enemyTeam, Tower.Bot2) ~= nil then
			return 2
		elseif
			GetTower(enemyTeam, Tower.Bot3) ~= nil
			or GetBarracks(enemyTeam, Barracks.BotMelee) ~= nil
			or GetBarracks(enemyTeam, Barracks.BotRanged) ~= nil
		then
			return 3
		else
			return 4
		end
	end
	return 1
end
function Push.HasBackdoorProtect(building)
	return building:HasModifier("modifier_fountain_glyph")
		or building:HasModifier("modifier_backdoor_protection")
		or building:HasModifier("modifier_backdoor_protection_in_base")
		or building:HasModifier("modifier_backdoor_protection_active")
end
function Push.IsAnyTargetBackdooredAt(bot, lane)
	local locationState = getLocationState()
	local unitState = getUnitState()
	local laneFront = locationState.laneFronts[lane]
	local nearestBuilding = nil
	local nearestDistance = math.huge
	for _, building in ipairs(unitState.enemyBuildings) do
		if Fu.IsValidBuilding(building) then
			local distance = GetUnitToLocationDistance(building, laneFront)
			if distance < nearestDistance then
				nearestBuilding = building
				nearestDistance = distance
			end
		end
	end
	return not not (nearestBuilding and Push.HasBackdoorProtect(nearestBuilding))
end
local CustomLoader = require(GetScriptDirectory() .. "/lib/systems/custom_loader")
CustomLoader.ThinkLess = CustomLoader.Enable and CustomLoader.ThinkLess or 1
enemyAncient = nil
lastThreatTick = -1
teamPushLane = nil
enemyHeroesAtAncient = 0
enemyHeroesOnHighGround = 0
laneFrontHasEnemies = {}
wasDefendPinged = false
recentDefendTime = 0
maxPushDesire = 0.525
lockedPushLane = nil
lockedPushLaneUntil = 0
isBotOnlyGame = nil
pushAfterDefendUntil = {}
lastDefendDesire = {}
pushAfterDefendSeconds = 10
stateCacheSeconds = 0.5
local botStateCacheSeconds = 0.2
gameStateCache = nil
locationStateCache = nil
unitStateCache = nil
local botStateCache = {}
local function getBotState(bot, targetLocation)
	local now = DotaTime()
	local playerId = bot:GetPlayerID()
	local cached = botStateCache[playerId]
	if cached and now - cached.lastUpdate < botStateCacheSeconds then
		return cached
	end
	local location = bot:GetLocation()
	local attackRange = bot:GetAttackRange()
	local gameState = getGameState()
	botStateCache[playerId] = {
		lastUpdate = now,
		botId = playerId,
		attackRange = attackRange,
		location = location,
		hp = Fu.GetHP(bot),
		mp = Fu.GetMP(bot),
		nearbyTowers = bot:GetNearbyTowers(1200, true),
		nearbyLaneCreeps = bot:GetNearbyLaneCreeps(1200, false),
		nearbyCreeps = bot:GetNearbyCreeps(1600, true),
		attackTarget = bot:GetAttackTarget(),
		distanceToAncient = gameState.enemyAncient and GetUnitToUnitDistance(bot, gameState.enemyAncient) or math.huge,
		distanceToTargetLoc = targetLocation and GetUnitToLocationDistance(bot, targetLocation) or 0,
	}
	return botStateCache[playerId]
end
local targetLockSeconds = 1.2
local switchTargetMargin = 0.25
local maxTargetDistance = 2600
local rangedBarracksCost = 0
local meleeBarracksCost = 0.1
local tier3TowerCost = 0.5
local baseTowerCost = 1.8
ancientThreatRadius = 2200
local targetLocks = {}
local hasLocalization, Localization = pcall(require, GetScriptDirectory() .. "/lib/systems/localization")
if not hasLocalization then
	Localization = {
		Get = function()
			return nil
		end,
	}
end
local FarmDefend = require(GetScriptDirectory() .. "/lib/systems/farm_defend")
local ChatRules = require(GetScriptDirectory() .. "/lib/systems/chat_rules")
local function getLocalizedLine(key)
	local lines = Localization.Get(key)
	if type(lines) == "table" and #lines > 0 then
		return lines[RandomInt(1, #lines)]
	end
	if type(lines) == "string" then
		return lines
	end
	return nil
end
-- Finish hold (#12, game 072 10:11-10:38: Undying and Winter Wyvern had Radiant's bottom T1 at 970 HP with 1006
-- damage in 5s and nobody defending, but the push fell to 0 every other think, the step walked to creeps 1250 away,
-- and Wyvern TP'd to a creep-only defend; the tower lived). Once FinishTower fires, the push holds at 0.9 on that lane
-- through every gate while PushRules.FinishHold says so: no TP out, PushThink hits the tower.
-- Lines: [SHy-PUSH] finish-hold why=gate:<the gate it overrode> (throttled), finish-drop why=, finish-done.
local function FinishHoldDesire(bot, lane, desire)
	local hold = bot._finishHold
	if hold == nil or hold.lane ~= lane then
		return desire
	end
	local now = DotaTime()
	local tower = hold.tower
	local towerAlive = Fu.IsValidBuilding(tower) and tower:IsAlive()
	local allies, damage5s, enemiesNear = 0, 0, 0
	if towerAlive then
		for _, ally in pairs(Fu.GetAlliesNearLoc(tower:GetLocation(), 1200) or {}) do
			if Fu.IsValidHero(ally) and not ally:IsIllusion() then
				allies = allies + 1
				damage5s = damage5s + (ally:GetEstimatedDamageToTarget(true, tower, 5.0, DAMAGE_TYPE_ALL) or 0)
			end
		end
		enemiesNear = #(Fu.GetEnemiesNearLoc(tower:GetLocation(), 1200) or {})
	end
	-- The Glyph pauses the hold (PushRules.FinishHold): its seconds don't count toward the 15s cap.
	local glyphed = towerAlive and tower:HasModifier("modifier_fountain_glyph")
	if glyphed and hold.lastAt ~= nil then
		hold.paused = (hold.paused or 0) + math.max(0, now - hold.lastAt)
	end
	hold.lastAt = now
	local keep, why = PushRules.FinishHold({
		towerAlive = towerAlive,
		glyphed = glyphed,
		baseThreat = (baseThreat.heroes or 0) >= 1,
		allies = allies,
		enemiesNear = enemiesNear,
		damage5s = damage5s,
		towerHp = towerAlive and tower:GetHealth() or 0,
		hp = Fu.GetHP(bot),
		age = now - hold.start - (hold.paused or 0),
	})
	if not keep then
		bot._finishHold = nil
		bot._finishHoldActiveAt = nil
		-- FinishTower arms a new hold on the next think while the tower still qualifies, so the same drop came every
		-- think (game 074 t=1308-1325: 88 lines of finish-drop why=glyph). Printed when the reason or the tower changes,
		-- or 10s after the last one.
		local dropKey = tostring(why) .. "|" .. tostring(tower)
		local repeated = why ~= "fell" and bot._finishDropKey == dropKey and now < (bot._finishDropLogAt or -999)
		bot._finishDropKey, bot._finishDropLogAt = dropKey, repeated and bot._finishDropLogAt or now + 10
		if not repeated and not Fu.IsMeepoClone(bot) then
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s %s why=%s lane=%s held=%.0f allies=%d enemies=%d dmg5s=%d towerHp=%d hp=%.2f",
					now,
					ShortHeroName(bot),
					why == "fell" and "finish-done" or "finish-drop",
					why,
					tostring(lane),
					now - hold.start,
					allies,
					enemiesNear,
					math.floor(damage5s),
					towerAlive and tower:GetHealth() or 0,
					Fu.GetHP(bot)
				)
			)
		end
		return desire
	end
	bot._finishHoldActiveAt = now
	bot._finishTowerAt = now
	-- No TP away while it holds (game 072: a creep-only defend TP took Wyvern off a 970 HP tower). Read by the TP rule
	-- wrapper in ability_item_usage_generic.lua.
	bot._noTpUntil = math.max(bot._noTpUntil or -999, now + 2)
	if desire < 0.9 then
		if now >= (bot._finishHoldLogAt or -999) and not Fu.IsMeepoClone(bot) then
			bot._finishHoldLogAt = now + 5
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s finish-hold why=gate:%s lane=%s desire=%.2f->0.90 dmg5s=%d towerHp=%d allies=%d",
					now,
					ShortHeroName(bot),
					tostring(bot._pushGate or "cap"),
					tostring(lane),
					desire,
					math.floor(damage5s),
					tower:GetHealth(),
					allies
				)
			)
		end
		desire = 0.9
	end
	return desire
end
-- Backdoor protection alone (not the Glyph): Push.HasBackdoorProtect counts both.
function Push.HasBackdoorOnly(building)
	return building:HasModifier("modifier_backdoor_protection")
		or building:HasModifier("modifier_backdoor_protection_in_base")
		or building:HasModifier("modifier_backdoor_protection_active")
end
-- Glyph wait (#12, maintainer, live game 074 2026-11-23: "bots are running away from t1 when glyph is active". Game 074
-- t=1308-1325: Alchemist and Largo stepped back from Dire's bottom T1 at 106 HP through two save Glyphs). While an
-- enemy tower within 1600 has the Glyph, PushThink keeps the bot at it, just outside its range at every tier
-- (PushRules.GlyphWait; game 078 dropped the tier 1 "stay": "standing still is bad. enemy could easily land disables
-- or setup team fight to standstill heroes"), hitting creeps and heroes outside the tower's range, and the finish hold
-- resumes when the Glyph ends. The edge is an arc centred on the lane back toward our side. With nothing to hit the
-- bot never stands still: it side-steps along the edge every 0.5-1s, alternating, at least 300 from the other waiting
-- allies, on passable ground (PushRules.GlyphSideStep), and steps further back
-- (up to the tower's reach + 500) while an enemy hero it can't hit is within 800 or a hero or creep hit it in the last
-- second. Lines (on change): [SHy-PUSH] glyph-wait lane= tower= mode= why= left= src= allies= enemies= creeps= dist=,
-- and glyph-end why= held= maxDist= holdMaxDist= (the farthest from the tower after the first 2s, step-backs included)
-- moves= (move goals given: out of range, side-steps, step-backs) backs= (step-backs started) spread= (closest
-- waiting ally on the thinks with nothing to hit after 2s; -1 when nobody waited with it).
local GLYPH_MODIFIER = "modifier_fountain_glyph"
local GLYPH_THREAT_RADIUS = 800
local GLYPH_BACK_STEP = 300
local GLYPH_BACK_MAX = 500
local function IsStandingTower(unit)
	return unit ~= nil and not unit:IsNull() and unit:IsAlive() and unit:CanBeSeen()
end
-- The tower's reach for this bot: attack range (700 for every tower, npc_units.txt 7.42; GetAttackRange read under
-- pcall like the backdoor wait) plus both hulls. Games 069-074 printed 852-868 for it (wait-outside-tower range=).
local function TowerReach(bot, tower)
	local okRange, rawRange = pcall(function()
		return tower:GetAttackRange()
	end)
	local baseRange = (okRange and type(rawRange) == "number" and rawRange > 0) and rawRange or 700
	return baseRange + tower:GetBoundingRadius() + bot:GetBoundingRadius()
end
-- The Glyph's remaining seconds from the modifier, or nil when the API gives none (unverified on enemy buildings).
local function GlyphRemaining(tower)
	local okIdx, idx = pcall(function()
		return tower:GetModifierByName(GLYPH_MODIFIER)
	end)
	if okIdx and type(idx) == "number" and idx >= 0 then
		local okDur, dur = pcall(function()
			return tower:GetModifierRemainingDuration(idx)
		end)
		if okDur and type(dur) == "number" then
			return dur
		end
	end
	return nil
end
local function GlyphWaitEnd(bot, why)
	local wait = bot._glyphWait
	bot._glyphWait = nil
	if wait == nil or Fu.IsMeepoClone(bot) then
		return
	end
	pcall(
		print,
		string.format(
			"[SHy-PUSH] t=%.0f %s glyph-end why=%s lane=%s tower=%s held=%.1f mode=%s allies=%d enemies=%d creeps=%d maxDist=%d holdMaxDist=%d moves=%d backs=%d spread=%d",
			DotaTime(),
			ShortHeroName(bot),
			why,
			tostring(wait.lane),
			wait.name,
			(wait.seenAt or wait.start) - wait.start,
			tostring(wait.mode),
			wait.allies or 0,
			wait.enemies or 0,
			wait.creeps or 0,
			math.floor(wait.maxDist or 0),
			math.floor(wait.holdMaxDist or 0),
			wait.moves or 0,
			wait.backs or 0,
			wait.spread ~= nil and math.floor(wait.spread) or -1
		)
	)
end
-- Once per think from Push.GetPushDesire: ends the episode when the Glyph is gone, the tower fell, or PushThink has not
-- run it for 2s (the bot left push mode or died).
local function GlyphWaitTick(bot)
	local wait = bot._glyphWait
	if wait == nil then
		return
	end
	if not IsStandingTower(wait.tower) then
		GlyphWaitEnd(bot, "fell")
	elseif not wait.tower:HasModifier(GLYPH_MODIFIER) then
		GlyphWaitEnd(bot, "ended")
	elseif DotaTime() - (wait.seenAt or -999) > 2 then
		GlyphWaitEnd(bot, "left")
	end
end
-- The centre of the edge arc: the unit vector from the tower back along the lane toward our side (the lane point 4% of
-- the lane either way that is nearer our fountain), so bots coming up a side lane wait on their own bearing instead of
-- all at the arc's end (the line to our fountain is 60-70 degrees off the lane at the bottom and top T1s). Falls back
-- to the direction of our fountain.
local function GlyphEdgeDirection(tower, lane)
	local towerLocation = tower:GetLocation()
	local fountain = Fu.GetTeamFountain()
	local point = fountain
	local ok, amount = pcall(function()
		return GetAmountAlongLane(lane, towerLocation).amount
	end)
	if ok and type(amount) == "number" then
		local before = GetLocationAlongLane(lane, math.max(0, amount - 0.04))
		local after = GetLocationAlongLane(lane, math.min(1, amount + 0.04))
		if before ~= nil and after ~= nil then
			point = Fu.GetLocationToLocationDistance(before, fountain)
						<= Fu.GetLocationToLocationDistance(after, fountain)
					and before
				or after
		end
	end
	local x, y = point.x - towerLocation.x, point.y - towerLocation.y
	local length = math.sqrt(x * x + y * y)
	if length < 100 then
		x, y = fountain.x - towerLocation.x, fountain.y - towerLocation.y
		length = math.max(1, math.sqrt(x * x + y * y))
	end
	return x / length, y / length
end
-- Where the other bots waiting at the same tower stand, or walk to (their move goal): { x =, y = } each.
local function GlyphWaitingAllies(bot, tower, now)
	local points, here = {}, {}
	for i = 1, 5 do
		local member = GetTeamMember(i)
		local wait = member ~= nil and member ~= bot and member._glyphWait or nil
		if
			wait ~= nil
			and wait.tower == tower
			and now - (wait.seenAt or -999) <= 0.5
			and Fu.IsValidHero(member)
			and member:IsAlive()
		then
			local location = member:GetLocation()
			here[#here + 1] = { x = location.x, y = location.y }
			local goal = wait.goal or location
			points[#points + 1] = { x = goal.x, y = goal.y }
		end
	end
	return points, here
end
-- Returns true when it gave the bot an order this think.
local function GlyphWaitThink(bot, lane)
	-- The Glyph covers every building of theirs: a wait starts only at a tower the bot is at (within 1200, the finish
	-- radius) or holds a finish on, and then follows that tower while it is within 1600.
	local tower = nil
	local wait = bot._glyphWait
	local hold = bot._finishHold
	for _, nearbyTower in ipairs(bot:GetNearbyTowers(1600, true) or {}) do
		if
			IsStandingTower(nearbyTower)
			and nearbyTower:HasModifier(GLYPH_MODIFIER)
			and (
				wait ~= nil and wait.tower == nearbyTower
				or hold ~= nil and hold.tower == nearbyTower
				or GetUnitToUnitDistance(bot, nearbyTower) <= 1200
			)
		then
			tower = nearbyTower
			break
		end
	end
	if tower == nil then
		return false
	end
	local now = DotaTime()
	local towerLocation = tower:GetLocation()
	local reach = TowerReach(bot, tower)
	local distance = GetUnitToUnitDistance(bot, tower)
	-- Heroes at the tower (1200); the bot counts itself when it stands farther. Enemies: the larger of those at the
	-- tower and those within 1600 of the bot (PushThink's own count), so a flank counts too.
	local allies = distance > 1200 and 1 or 0
	for _, ally in pairs(Fu.GetAlliesNearLoc(towerLocation, 1200) or {}) do
		if Fu.IsValidHero(ally) and not ally:IsIllusion() then
			allies = allies + 1
		end
	end
	local enemies = math.max(
		#(Fu.GetEnemiesNearLoc(towerLocation, 1200) or {}),
		#(Fu.GetEnemiesNearLoc(bot:GetLocation(), 1600) or {})
	)
	local creeps = 0
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(1600, false) or {}) do
		if Fu.IsValid(creep) and GetUnitToUnitDistance(creep, tower) <= reach then
			creeps = creeps + 1
		end
	end
	local tier = PushRules.TowerTier(tower:GetUnitName()) or 1
	local mode, why = PushRules.GlyphWait({
		tier = tier,
		hp = Fu.GetHP(bot),
		allies = allies,
		enemies = enemies,
		creeps = creeps,
	})
	if wait == nil or wait.tower ~= tower then
		if wait ~= nil then
			GlyphWaitEnd(bot, "retarget")
		end
		local name = string.gsub(tower:GetUnitName(), "npc_dota_", "")
		wait = {
			tower = tower,
			name = name,
			start = now,
			seenAt = now,
			maxDist = 0,
			holdMaxDist = 0,
			moves = 0,
			backs = 0,
		}
		bot._glyphWait = wait
	end
	wait.lane, wait.seenAt = lane, now
	wait.allies, wait.enemies, wait.creeps = allies, enemies, creeps
	wait.maxDist = math.max(wait.maxDist, distance)
	if mode ~= "back" and now - wait.start >= 2 then
		wait.holdMaxDist = math.max(wait.holdMaxDist, distance)
	end
	if (mode ~= wait.mode or why ~= wait.why) and now >= (wait.logAt or -999) then
		wait.mode, wait.why, wait.logAt = mode, why, now + 1
		if not Fu.IsMeepoClone(bot) then
			local left, source = PushRules.GlyphLeft(GlyphRemaining(tower), now - wait.start)
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s glyph-wait lane=%s tower=%s tier=%d mode=%s why=%s left=%.1f src=%s allies=%d enemies=%d creeps=%d dist=%d hp=%.2f",
					now,
					ShortHeroName(bot),
					tostring(lane),
					wait.name,
					tier,
					mode,
					why,
					left,
					source,
					allies,
					enemies,
					creeps,
					math.floor(distance),
					Fu.GetHP(bot)
				)
			)
		end
	end
	if mode == "back" then
		wait.goal = nil
		return false
	end
	if wait.baseX == nil then
		wait.baseX, wait.baseY = GlyphEdgeDirection(tower, lane)
	end
	local baseX, baseY = wait.baseX, wait.baseY
	local botLocation = bot:GetLocation()
	local function edgeAt(radius)
		local x, y = PushRules.GlyphEdgePoint(
			towerLocation.x,
			towerLocation.y,
			botLocation.x,
			botLocation.y,
			baseX,
			baseY,
			radius,
			PushRules.GLYPH_EDGE_ARC
		)
		return Vector(x, y, botLocation.z)
	end
	-- A move order; a new goal (100+ from the last one) counts as a move.
	local function moveTo(goal)
		if wait.goal == nil or Fu.GetLocationToLocationDistance(wait.goal, goal) > 100 then
			wait.moves = wait.moves + 1
		end
		wait.goal = goal
		bot:Action_MoveToLocation(goal)
		return true
	end
	-- Out of the tower's reach first, on the bot's own bearing (no walk of the whole group to one spot).
	if distance < reach + 50 then
		return moveTo(edgeAt(reach + 100))
	end
	-- Hit a hero, else a creep: one the bot reaches from where it stands, or one it walks to that stands outside the
	-- tower's reach and within 300 of it (no chase away from it). Glyphed creeps (3s) and the tower itself fail
	-- Fu.CanBeAttacked.
	local attackRange = bot:GetAttackRange()
	local function canHit(unit)
		if not Fu.IsValid(unit) or not Fu.CanBeAttacked(unit) then
			return false
		end
		if GetUnitToUnitDistance(bot, unit) <= attackRange + 50 then
			return true
		end
		local toTower = GetUnitToUnitDistance(unit, tower)
		return toTower <= reach + 300 and toTower > reach
	end
	local target, lowestHealth = nil, math.huge
	local threatHero = false
	local heroRadius = math.max(math.min(attackRange + 150, 1600), GLYPH_THREAT_RADIUS)
	for _, enemyHero in ipairs(bot:GetNearbyHeroes(heroRadius, true, BotMode.None) or {}) do
		if Fu.IsValidHero(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
			local heroDistance = GetUnitToUnitDistance(bot, enemyHero)
			if heroDistance <= attackRange + 150 and canHit(enemyHero) then
				if enemyHero:GetHealth() < lowestHealth then
					target, lowestHealth = enemyHero, enemyHero:GetHealth()
				end
			elseif heroDistance <= GLYPH_THREAT_RADIUS then
				threatHero = true
			end
		end
	end
	if target == nil then
		for _, creep in ipairs(bot:GetNearbyLaneCreeps(math.min(attackRange + 200, 1600), true) or {}) do
			if canHit(creep) then
				target = creep
				break
			end
		end
	end
	if target ~= nil then
		bot:Action_AttackUnit(target, true)
		return true
	end
	-- Nothing to hit: never stand still (game 078). Closest waiting ally, from 2s into the wait (they arrive together).
	local allyGoals, allyHere = GlyphWaitingAllies(bot, tower, now)
	if now - wait.start >= 2 then
		local closest = PushRules.NearestDistance(botLocation.x, botLocation.y, allyHere)
		if closest ~= nil then
			wait.spread = math.min(wait.spread or math.huge, closest)
		end
	end
	-- Step back toward our side while an enemy hero it can't hit is near enough to cast, or a hero or creep (a glyphed
	-- one, or one inside the tower's range) hit it in the last second; 1s more after that, up to reach + 500.
	local radius = reach + 100
	if threatHero or bot:WasRecentlyDamagedByAnyHero(1) or bot:WasRecentlyDamagedByCreep(1) then
		if now >= (wait.backUntil or -999) then
			wait.backs = wait.backs + 1
		end
		wait.backRadius = math.min(math.max(distance, reach + 100) + GLYPH_BACK_STEP, reach + GLYPH_BACK_MAX)
		wait.backUntil = now + 1
	end
	if now < (wait.backUntil or -999) then
		radius = wait.backRadius or radius
		if distance < radius - 100 then
			return moveTo(edgeAt(radius))
		end
	end
	-- Side-step along the edge (at the step-back distance while backing): a new step every 0.5-1s or on arrival,
	-- alternating, away from the other waiting allies.
	if wait.goal == nil or now >= (wait.stepAt or -999) or GetUnitToLocationDistance(bot, wait.goal) < 50 then
		local interval = RandomFloat(0.5, 1.0)
		local step = math.min(350, math.max(150, bot:GetCurrentMovementSpeed() * interval))
		if wait.side == nil then
			-- Start toward the side of the tower -> fountain line the bot is on (away from the middle), so bots that
			-- start on the same think don't slide as a clump.
			local ux, uy = botLocation.x - towerLocation.x, botLocation.y - towerLocation.y
			wait.side = (baseX * uy - baseY * ux) >= 0 and 1 or -1
		end
		local x, y, side = PushRules.GlyphSideStep({
			tx = towerLocation.x,
			ty = towerLocation.y,
			x = botLocation.x,
			y = botLocation.y,
			bx = baseX,
			by = baseY,
			radius = radius,
			step = step,
			side = wait.side,
			maxAngle = PushRules.GLYPH_EDGE_ARC,
			allies = allyGoals,
			minGap = PushRules.GLYPH_SPREAD,
			passable = function(x, y)
				return IsLocationPassable(Vector(x, y, botLocation.z))
			end,
		})
		wait.side, wait.stepAt = -side, now + interval
		return moveTo(Vector(x, y, botLocation.z))
	end
	bot:Action_MoveToLocation(wait.goal)
	return true
end
-- A lane's push that was on (0.5+) and is now off: one line naming the gate (throttled per bot).
local function LogPushGate(bot, lane, desire)
	bot._pushLastDesire = bot._pushLastDesire or {}
	local was = bot._pushLastDesire[lane] or 0
	bot._pushLastDesire[lane] = desire
	if was >= 0.5 and desire <= 0 and bot._pushGate ~= nil then
		if DotaTime() >= (bot._pushGateLogAt or -999) and not Fu.IsMeepoClone(bot) then
			bot._pushGateLogAt = DotaTime() + 5
			pcall(
				print,
				string.format(
					"[SHy-PUSH] t=%.0f %s push-gate lane=%s why=%s was=%.2f mode=%s",
					DotaTime(),
					ShortHeroName(bot),
					tostring(lane),
					bot._pushGate,
					was,
					tostring(bot:GetActiveMode())
				)
			)
		end
	end
end
-- Lane-done episodes (#12, maintainer 2026-11-22: "stay on the target" first, with stats to choose between it and
-- handing the push to the building's lane). An episode starts when PushThink keeps a bot on another lane's building
-- (LaneDoneFrontDistance) and ends when the target falls, the bot leaves push mode for 2s+, stops thinking for 3s+
-- (died), switches target, or after 20s. One line per episode:
-- [SHy-PUSH] lane-done-result lane= target= held= hits= hpDrop= fell= modeFlips= end=
--   held: seconds within attack range + 300 of the target; hits: its attacks on the target (GetLastAttackTime
--   changes while it targets it); hpDrop: target HP lost while the bot was there; modeFlips: switches between two
--   push_tower modes in the episode.
local function IsPushMode(mode)
	return mode == BotMode.PushTowerTop or mode == BotMode.PushTowerMid or mode == BotMode.PushTowerBot
end
local function LaneDoneEnd(bot, why)
	local episode = bot._laneDoneEpisode
	bot._laneDoneEpisode = nil
	if episode == nil or Fu.IsMeepoClone(bot) then
		return
	end
	local fell = not Fu.IsValidBuilding(episode.target) or not episode.target:IsAlive()
	pcall(
		print,
		string.format(
			"[SHy-PUSH] t=%.0f %s lane-done-result lane=%s target=%s held=%.0f hits=%d hpDrop=%d fell=%s modeFlips=%d age=%.0f end=%s",
			DotaTime(),
			ShortHeroName(bot),
			tostring(episode.lane),
			episode.name,
			episode.held,
			episode.hits,
			math.floor(episode.hpDrop),
			fell and "yes" or "no",
			episode.modeFlips,
			DotaTime() - episode.start,
			why
		)
	)
end
local function LaneDoneStart(bot, lane, target)
	local episode = bot._laneDoneEpisode
	if episode ~= nil and episode.target == target then
		return
	end
	if episode ~= nil then
		LaneDoneEnd(bot, "retarget")
	end
	local now = DotaTime()
	bot._laneDoneEpisode = {
		lane = lane,
		target = target,
		name = tostring(target:GetUnitName()),
		start = now,
		tickAt = now,
		held = 0,
		hits = 0,
		hpDrop = 0,
		hp = target:GetHealth(),
		modeFlips = 0,
		mode = bot:GetActiveMode(),
		lastAttackAt = bot:GetLastAttackTime(),
		pushSeenAt = now,
	}
end
-- Once per think (Push.GetPushDesire runs for each lane).
local function LaneDoneTick(bot)
	local episode = bot._laneDoneEpisode
	local now = DotaTime()
	if episode == nil or episode.tickAt == now then
		return
	end
	local dt = now - episode.tickAt
	episode.tickAt = now
	local why = PushRules.LaneDoneEpisodeEnd({
		targetAlive = Fu.IsValidBuilding(episode.target) and episode.target:IsAlive(),
		botAlive = bot:IsAlive(),
		gap = dt,
		outOfPush = now - episode.pushSeenAt,
		age = now - episode.start,
	})
	if why ~= nil then
		LaneDoneEnd(bot, why)
		return
	end
	local mode = bot:GetActiveMode()
	if IsPushMode(mode) then
		episode.pushSeenAt = now
		if IsPushMode(episode.mode) and mode ~= episode.mode then
			episode.modeFlips = episode.modeFlips + 1
		end
		episode.mode = mode
	end
	local hp = episode.target:GetHealth()
	local near = GetUnitToUnitDistance(bot, episode.target) <= bot:GetAttackRange() + 300
	if near then
		episode.held = episode.held + dt
		episode.hpDrop = episode.hpDrop + math.max(0, episode.hp - hp)
	end
	episode.hp = hp
	local lastAttackAt = bot:GetLastAttackTime()
	if lastAttackAt ~= episode.lastAttackAt and bot:GetAttackTarget() == episode.target then
		episode.hits = episode.hits + 1
	end
	episode.lastAttackAt = lastAttackAt
end
function Push.GetPushDesire(bot, lane)
	LaneDoneTick(bot)
	if
		bot:IsInvulnerable()
		or not bot:IsHero()
		or not bot:IsAlive()
		or not stringIncludes(bot:GetUnitName(), "hero")
		or bot:IsIllusion()
	then
		return BotModeDesire.None
	end
	-- A human's push order (#222, bots/lib/systems/human_orders.lua: `!push <lane>`, a ping on an enemy building or
	-- its wave, of any ping type): before the level and lane checks below, which would refuse it.
	local orderDesire = HumanOrders.PushDesire(bot, lane)
	if orderDesire ~= nil then
		bot.pushDesire = orderDesire
		return orderDesire
	end
	if bot:GetLevel() < 6 then
		return BotModeDesire.None
	end
	-- Set by the helper when this lane's desire was raised for a group push (read below, this call only).
	bot._pushRaisedAt = nil
	bot._pushGate = nil
	local desire = math.min(Push.GetPushDesireHelper(bot, lane), 1)
	desire = FinishHoldDesire(bot, lane, desire)
	GlyphWaitTick(bot)
	LogPushGate(bot, lane, desire)
	-- A Roshan call the team answers outranks a push (#12, game 067 32:11: four bots called a kill-window Roshan and
	-- a 0.99 kill push won; 20s later every call was dropped window-short). bot._roshDesireNow / _roshDesireAt come
	-- from mode_roshan_generic.lua's GetDesire.
	local now = DotaTime()
	local roshDesire = bot._roshDesireNow
	local pushBefore, yielded = desire, false
	desire, yielded =
		PushRules.PushUnderRosh(desire, roshDesire, now - (bot._roshDesireAt or -999), bot._finishTowerAt == now)
	if yielded and now >= (bot._roshVsPushLogAt or -999) and not Fu.IsMeepoClone(bot) then
		bot._roshVsPushLogAt = now + 5
		pcall(
			print,
			string.format(
				"[SHy-ROSH] t=%.0f %s call-vs-push winner=roshan rosh=%.2f why=%s push=%.2f->%.2f lane=%s",
				now,
				ShortHeroName(bot),
				roshDesire,
				tostring(bot._roshWhy),
				pushBefore,
				desire,
				tostring(lane)
			)
		)
	end
	-- Farm stays under a group push this bot was asked into (mode_farm_generic.lua reads it).
	if bot._pushRaisedAt == now and desire >= 0.5 and not yielded then
		bot._groupPushJoin = { at = now, desire = desire, why = bot._pushRaisedWhy }
		-- Every enemy dead and the bot at the push: no TP away to farm or another lane (game 067 50:53-51:27: Clinkz and Death
		-- Prophet TP'd off Radiant's bottom T3 at 1246 HP with all five Radiant dead). bot._noTpUntil is read by the TP
		-- rule wrapper in ability_item_usage_generic.lua. A bot far from the lane may still TP to it.
		if
			bot._pushRaisedWhy == "advantage:wipe"
			and GetUnitToLocationDistance(bot, GetLaneFrontLocation(GetTeam(), lane, 0)) < 3000
		then
			bot._noTpUntil = math.max(bot._noTpUntil or -999, now + 2)
			if now >= (bot._wipeTpHoldLogAt or -999) then
				bot._wipeTpHoldLogAt = now + 10
				pcall(
					print,
					string.format(
						"[SHy-PUSH] t=%.0f %s wipe-tp-hold lane=%s desire=%.2f hp=%.2f",
						now,
						ShortHeroName(bot),
						tostring(lane),
						desire,
						Fu.GetHP(bot)
					)
				)
			end
		end
	end
	bot.pushDesire = desire
	-- Read by farm's enemy-half withdraw (mode_farm_generic.lua): a bot pushing at their Ancient doesn't walk home.
	if desire >= 0.3 then
		bot._pushActiveAt = now
	end
	if desire >= 0.5 and (bot._lastPushChatDesire or 0) < 0.5 and FarmDefend.ClaimDecisionChat("late_push") then
		local chatKey = lane == Lane.Top and "say_push_top" or (lane == Lane.Mid and "say_push_mid" or "say_push_bot")
		local chatLine = getLocalizedLine(chatKey) or getLocalizedLine("say_leave_farm_push")
		if chatLine then
			ChatRules.SayDecision(bot, chatLine, chatKey)
		end
	end
	bot._lastPushChatDesire = desire
	-- A bot carrying out a human's forced order elsewhere (#222): this lane stays under the order's desire, so a kill
	-- push (0.99) does not pull it away (maintainer, game 078: the human insisting outranks the team's calls).
	local orderCap = HumanOrders.CapForOrder(bot)
	if orderCap ~= nil and desire > orderCap then
		bot.pushDesire = orderCap
		return orderCap
	end
	return desire
end
local function isAttackableBuilding(unit)
	return not not unit and Fu.IsValidBuilding(unit) and Fu.CanBeAttacked(unit)
end
local function isBarracks(unit)
	local unitName = unit ~= nil and unit:GetUnitName() or ""
	return stringIncludes(unitName, "rax")
end
local function isMeleeBarracks(unit)
	return isBarracks(unit) and not not unit and stringIncludes(unit:GetUnitName(), "melee")
end
local function isRangedBarracks(unit)
	return isBarracks(unit) and not not unit and stringIncludes(unit:GetUnitName(), "ranged")
end
local function isExposedMeleeBarracks(unit)
	if not isMeleeBarracks(unit) then
		return false
	end
	local enemyTeam = GetOpposingTeam()
	local unitName = unit:GetUnitName()
	local rangedBarracks = nil
	if stringIncludes(unitName, "top") then
		rangedBarracks = GetBarracks(enemyTeam, Barracks.TopRanged)
	elseif stringIncludes(unitName, "mid") then
		rangedBarracks = GetBarracks(enemyTeam, Barracks.MidRanged)
	else
		rangedBarracks = GetBarracks(enemyTeam, Barracks.BotRanged)
	end
	return rangedBarracks == nil or not rangedBarracks:IsAlive()
end
local function isTier3Tower(unit)
	return unit == GetTower(GetOpposingTeam(), Tower.Top3)
		or unit == GetTower(GetOpposingTeam(), Tower.Mid3)
		or unit == GetTower(GetOpposingTeam(), Tower.Bot3)
end
local function isBaseTower(unit)
	return unit == GetTower(GetOpposingTeam(), Tower.Base1)
		or unit == GetTower(GetOpposingTeam(), Tower.Base2)
		or GetUnitToUnitDistance(unit, GetAncient(GetOpposingTeam())) < 500
end
local function isOuterTower(unit)
	local enemyTeam = GetOpposingTeam()
	return unit == GetTower(enemyTeam, Tower.Top1)
		or unit == GetTower(enemyTeam, Tower.Mid1)
		or unit == GetTower(enemyTeam, Tower.Bot1)
		or unit == GetTower(enemyTeam, Tower.Top2)
		or unit == GetTower(enemyTeam, Tower.Mid2)
		or unit == GetTower(enemyTeam, Tower.Bot2)
end
local outerTowerCost = 0.2
local function getBuildingCost(bot, building, targetLocation)
	if not isAttackableBuilding(building) then
		return math.huge
	end
	local baseCost = 2
	if isRangedBarracks(building) then
		baseCost = rangedBarracksCost
	elseif isMeleeBarracks(building) then
		baseCost = isExposedMeleeBarracks(building) and rangedBarracksCost or meleeBarracksCost
	elseif isOuterTower(building) then
		baseCost = outerTowerCost
	elseif isTier3Tower(building) then
		baseCost = tier3TowerCost
	elseif isBaseTower(building) then
		baseCost = baseTowerCost
	end
	local distance = GetUnitToUnitDistance(bot, building)
	if distance > maxTargetDistance then
		return math.huge
	end
	local distanceCost = distance / 2000
	local targetLocationCost = targetLocation and GetUnitToLocationDistance(building, targetLocation) / 2500 or 0
	return baseCost + 0.35 * distanceCost + 0.2 * targetLocationCost
end
local function pickPushTarget(bot, lane, targetLocation)
	local playerId = bot:GetPlayerID()
	targetLocks[playerId] = targetLocks[playerId] or {}
	targetLocks[playerId][lane] = targetLocks[playerId][lane] or {}
	local lock = targetLocks[playerId][lane]
	local now = GameTime()
	local lockedTarget = lock.target or nil
	if lockedTarget and isAttackableBuilding(lockedTarget) and now < (lock.lockUntil or 0) then
		return lockedTarget
	end
	local lockedCost = lockedTarget and getBuildingCost(bot, lockedTarget, targetLocation) or math.huge
	local unitState = getUnitState()
	local bestBuilding = nil
	local bestCost = math.huge
	for _, building in ipairs(unitState.enemyBuildings) do
		local cost = getBuildingCost(bot, building, targetLocation)
		if cost < bestCost then
			bestBuilding = building
			bestCost = cost
		end
	end
	if lockedTarget and isAttackableBuilding(lockedTarget) then
		if bestBuilding and bestCost + switchTargetMargin < lockedCost then
			lock.target = bestBuilding
			lock.lockUntil = now + targetLockSeconds
			return bestBuilding
		else
			lock.lockUntil = now + 0.6
			return lockedTarget
		end
	end
	if bestBuilding then
		lock.target = bestBuilding
		lock.lockUntil = now + targetLockSeconds
		return bestBuilding
	end
	lock.target = nil
	lock.lockUntil = nil
	return nil
end
laneTargetCache = {}
-- The distance PushThink's walk to the lane front reads. A lane with none of its own buildings left (T3 and both
-- barracks down) picks another lane's building or the T4s; walking back to this lane's own front then undoes the
-- approach every 2s (#12, game 071 47:20-47:41: five Radiant bots alternated between Dire's mid melee barracks and the
-- top lane front, and nobody hit it). With PushRules.FrontWalk "lane-done" it returns 0 (no walk) and logs
-- [SHy-PUSH] lane-done; else the real distance.
local function LaneDoneFrontDistance(bot, lane, laneFront)
	local distanceToFront = GetUnitToLocationDistance(bot, laneFront)
	local tier = distanceToFront > 2000 and Push.GetLaneBuildingTier(lane) or 0
	local target = tier >= 4 and pickPushTarget(bot, lane, nil) or nil
	local walk = PushRules.FrontWalk({
		distanceToFront = distanceToFront,
		recentlyHit = bot:WasRecentlyDamagedByAnyHero(3),
		laneTier = tier,
		hasTarget = target ~= nil,
	})
	if walk ~= "lane-done" then
		return distanceToFront
	end
	LaneDoneStart(bot, lane, target)
	if DotaTime() >= (bot._laneDoneLogAt or -999) and not Fu.IsMeepoClone(bot) then
		bot._laneDoneLogAt = DotaTime() + 10
		pcall(
			print,
			string.format(
				"[SHy-PUSH] t=%.0f %s lane-done lane=%s target=%s dist=%d front=%d",
				DotaTime(),
				ShortHeroName(bot),
				tostring(lane),
				tostring(target:GetUnitName()),
				math.floor(GetUnitToUnitDistance(bot, target)),
				math.floor(distanceToFront)
			)
		)
	end
	return 0
end
-- A hero the enemy tower covers is not the push's hero target (#12, game 068 16:52-16:58: `step=hit-hero` walked
-- Clinkz past Radiant's mid T2 toward Alchemist behind it; push is exempt from the tower stop rules, so only attack
-- mode stopped him at 29% HP next to the tower and he died). PushRules.HitHeroBehindTower; [SHy-PUSH] hit-hero-skip.
local function HeroCoveredByTower(bot, enemyHero, alliesNear, enemiesNear, lane)
	local tower = (bot:GetNearbyTowers(1600, true) or {})[1]
	if not Fu.IsValidBuilding(tower) or not tower:IsAlive() then
		return false
	end
	local botLoc, targetLoc, towerLoc = bot:GetLocation(), enemyHero:GetLocation(), tower:GetLocation()
	local reach = tower:GetAttackRange() + 150
	local targetToTower = GetUnitToUnitDistance(enemyHero, tower)
	local pathToTower = PushRules.PointToSegment(towerLoc.x, towerLoc.y, botLoc.x, botLoc.y, targetLoc.x, targetLoc.y)
	local botToTarget = GetUnitToUnitDistance(bot, enemyHero)
	local botToTower = GetUnitToUnitDistance(bot, tower)
	-- Cheap geometry first: the rest is read only for a hero the tower covers.
	if targetToTower > reach and pathToTower > reach or botToTarget <= botToTower then
		return false
	end
	-- Enemies who can respond: alive and not seen (in the last 5s) more than 3000 from the target.
	local responders = 0
	for _, pid in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(pid) then
			local info = GetHeroLastSeenInfo(pid)
			local seen = info ~= nil and info[1] or nil
			local far = seen ~= nil
				and (seen.time_since_seen or 99) <= 5
				and GetUnitToLocationDistance(enemyHero, seen.location) > 3000
			if not far then
				responders = responders + 1
			end
		end
	end
	-- Our heroes on the chase (within 1200 of this bot) and their damage on the target over 3s.
	local chasers, damage3s = 0, 0
	for _, ally in ipairs(Fu.GetAlliesNearLoc(botLoc, 1200) or {}) do
		if Fu.IsValidHero(ally) and not ally:IsIllusion() then
			chasers = chasers + 1
			local okDamage, estimate = pcall(function()
				return ally:GetEstimatedDamageToTarget(true, enemyHero, 3.0, DAMAGE_TYPE_ALL)
			end)
			damage3s = damage3s + (okDamage and type(estimate) == "number" and estimate or 0)
		end
	end
	local travel = math.max(0, botToTarget - bot:GetAttackRange()) / math.max(100, bot:GetCurrentMovementSpeed())
	local killTime = travel + enemyHero:GetHealth() / math.max(1, damage3s / 3)
	-- The tower's hits on this bot per second (its attack after our armor).
	local okTower, towerDps = pcall(function()
		return bot:GetActualIncomingDamage(tower:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
			/ math.max(0.5, tower:GetSecondsPerAttack())
	end)
	local surviveTime = bot:GetHealth() / math.max(1, okTower and type(towerDps) == "number" and towerDps or 150)
	local adv = advantageByTeam[GetTeam()]
	local towerTarget = tower:GetAttackTarget()
	local creepsTanking = false
	if towerTarget ~= nil and towerTarget ~= bot and not towerTarget:IsHero() then
		-- Our lane creeps inside the tower's range, from the bot's own list (a tower handle's own lists are untested).
		local inRange = 0
		for _, creep in ipairs(bot:GetNearbyLaneCreeps(1600, false) or {}) do
			if Fu.IsValid(creep) and GetUnitToUnitDistance(creep, tower) <= tower:GetAttackRange() + 100 then
				inRange = inRange + 1
			end
		end
		creepsTanking = inRange >= 3
	end
	local skip, why = PushRules.HitHeroBehindTower({
		targetToTower = targetToTower,
		pathToTower = pathToTower,
		towerRange = tower:GetAttackRange(),
		botToTarget = botToTarget,
		botToTower = botToTower,
		towerHp = tower:GetHealth() / math.max(1, tower:GetMaxHealth()),
		creepsTanking = creepsTanking,
		fightOurs = alliesNear >= enemiesNear + 1,
		advantage = adv ~= nil and adv.desire ~= nil,
		responders = responders,
		chasers = chasers,
		killTime = killTime,
		surviveTime = surviveTime,
	})
	-- A covered hero taken anyway: one line on why (the 33:30 kind of chase).
	if not skip and DotaTime() >= (bot._hitHeroTakeLogAt or -999) and not Fu.IsMeepoClone(bot) then
		bot._hitHeroTakeLogAt = DotaTime() + 5
		pcall(
			print,
			string.format(
				"[SHy-PUSH] t=%.0f %s hit-hero-take why=%s target=%s responders=%d chasers=%d kill=%.1f survive=%.1f path=%d",
				DotaTime(),
				ShortHeroName(bot),
				why,
				ShortHeroName(enemyHero),
				responders,
				chasers,
				killTime,
				surviveTime,
				math.floor(pathToTower)
			)
		)
	end
	if skip and DotaTime() >= (bot._hitHeroSkipLogAt or -999) and not Fu.IsMeepoClone(bot) then
		bot._hitHeroSkipLogAt = DotaTime() + 5
		pcall(
			print,
			string.format(
				"[SHy-PUSH] t=%.0f %s hit-hero-skip why=%s target=%s tower=%s lane=%s targetToTower=%d botToTower=%d botToTarget=%d towerHp=%.2f path=%d responders=%d chasers=%d kill=%.1f survive=%.1f",
				DotaTime(),
				ShortHeroName(bot),
				why,
				ShortHeroName(enemyHero),
				tostring(tower:GetUnitName()),
				tostring(lane),
				math.floor(GetUnitToUnitDistance(enemyHero, tower)),
				math.floor(GetUnitToUnitDistance(bot, tower)),
				math.floor(GetUnitToUnitDistance(bot, enemyHero)),
				tower:GetHealth() / math.max(1, tower:GetMaxHealth()),
				math.floor(pathToTower),
				responders,
				chasers,
				killTime,
				surviveTime
			)
		)
	end
	return skip
end
local function getAllyLaneTower(team, lane)
	local towerIds = lane == Lane.Top and { 0, 3, 6 } or (lane == Lane.Mid and { 1, 4, 7 } or { 2, 5, 8 })
	for _, towerId in ipairs(towerIds) do
		local tower = GetTower(team, towerId)
		if tower and tower:IsAlive() then
			return tower
		end
	end
	return nil
end
function Push.PushThink(bot, lane)
	if Fu.CanNotUseAction(bot) then
		return
	end
	-- A forced push order (#222): a far bot TPs first when that is clearly faster (game 077: they walked).
	if HumanOrders.TravelThink(bot, "push", lane) then
		return
	end
	if Fu.TryDropTowerAggro(bot) then
		return
	end
	if Fu.TryDenyTower(bot) then
		return
	end
	if Fu.TryDenyAllyHero(bot) then
		return
	end
	local enemyFountainTpPoint = GetTeam() == Team.Radiant and direFountainTpPoint or radiantFountainTpPoint
	local botUnit = bot
	if getLocationToLocationDistance(bot:GetLocation(), enemyFountainTpPoint) < 1500 then
		botUnit._fountainRetreatUntil = DotaTime() + 4
		local allyLaneCreeps = bot:GetNearbyLaneCreeps(1600, false)
		if allyLaneCreeps and #allyLaneCreeps >= 1 then
			local lastCreepLocation = allyLaneCreeps[#allyLaneCreeps]:GetLocation()
			botUnit._fountainRetreatLoc = Fu.AdjustLocationWithOffsetTowardsFountain(lastCreepLocation, 200)
		else
			botUnit._fountainRetreatLoc = GetLaneFrontLocation(GetTeam(), lane, -500)
		end
	end
	if botUnit._fountainRetreatUntil and DotaTime() <= botUnit._fountainRetreatUntil then
		if bot:WasRecentlyDamagedByAnyHero(1) then
		elseif botUnit._fountainRetreatLoc and GetUnitToLocationDistance(bot, botUnit._fountainRetreatLoc) > 300 then
			bot:Action_MoveToLocation(botUnit._fountainRetreatLoc)
			return
		else
			botUnit._fountainRetreatUntil = 0
		end
	end
	-- Finish hold (FinishHoldDesire, #12 game 072): hit the tower, not creeps 1000+ away.
	do
		local hold = bot._finishHold
		if
			hold ~= nil
			and hold.lane == lane
			and DotaTime() - (bot._finishHoldActiveAt or -999) <= 1
			and Fu.IsValidBuilding(hold.tower)
			and hold.tower:IsAlive()
			and Fu.CanBeAttacked(hold.tower)
		then
			bot:Action_AttackUnit(hold.tower, true)
			return
		end
		-- An enemy tower with the Glyph (#12, game 074): wait at it instead of the lane-front step back below. Not while
		-- gathering below their high ground (the gather block next).
		local gather = bot._hgGatherActive
		local gathering = gather ~= nil and gather.lane == lane and DotaTime() - (gather.at or -999) <= 1
		if not gathering and GlyphWaitThink(bot, lane) then
			return
		end
	end
	-- Gathering below the enemy high ground (#12 hg-gather, set by Push.GetPushDesireHelper this think): walk to the
	-- spot and wait there, hitting creeps in range, until enough allies are there. Before the walk to the lane front,
	-- which at their T4s is inside their base.
	do
		local gather = bot._hgGatherActive
		if
			gather ~= nil
			and gather.lane == lane
			and gather.spot ~= nil
			and DotaTime() - (gather.at or -999) <= 1
			and not bot:WasRecentlyDamagedByAnyHero(1)
		then
			if GetUnitToLocationDistance(bot, gather.spot) > 350 then
				bot:Action_MoveToLocation(gather.spot)
				return
			end
			local creeps = bot:GetNearbyLaneCreeps(math.min(bot:GetAttackRange() + 150, 1600), true) or {}
			if #creeps > 0 and Fu.IsValid(creeps[1]) and Fu.CanBeAttacked(creeps[1]) then
				bot:Action_AttackUnit(creeps[1], true)
			end
			return
		end
	end
	-- Alone, joining this lane's push group (Push.GetPushDesireHelper this think, PushRules.AloneGate): walk to where
	-- the group stands, not to the lane front alone. Within 1200 of them the normal push takes over (the helper prints
	-- push-join-arrived once 2+ allies are within 1600). Line: push-gate why=alone-join (every 6s while walking).
	do
		local join = bot._pushJoin ~= nil and bot._pushJoin[lane] or nil
		if join ~= nil and join.spot ~= nil and DotaTime() - (join.at or -999) <= 1 then
			local dist = GetUnitToLocationDistance(bot, join.spot)
			if dist > 1200 and not bot:WasRecentlyDamagedByAnyHero(1) then
				join.walked = true
				-- One line per bot every 6s while it walks (it is in this lane's push mode here, so the join took effect).
				if DotaTime() >= (bot._aloneJoinLogAt or -999) and not Fu.IsMeepoClone(bot) then
					bot._aloneJoinLogAt = DotaTime() + 6
					local modeDesire = bot:GetActiveModeDesire()
					pcall(
						print,
						string.format(
							"[SHy-PUSH] t=%.0f %s push-gate lane=%s why=alone-join group=%d atFront=%d dist=%d age=%.0f desire=%.2f",
							DotaTime(),
							ShortHeroName(bot),
							tostring(lane),
							join.group or 0,
							join.atFront or 0,
							math.floor(dist),
							join.age or 0,
							type(modeDesire) == "number" and modeDesire or 0
						)
					)
				end
				bot:Action_MoveToLocation(join.spot)
				return
			end
		end
	end
	do
		local laneFront = GetLaneFrontLocation(GetTeam(), lane, 0)
		-- 0 while the lane is done and its target is in reach (LaneDoneFrontDistance), so the walk below doesn't run.
		local distanceToFront = LaneDoneFrontDistance(bot, lane, laneFront)
		if distanceToFront > 2000 and not bot:WasRecentlyDamagedByAnyHero(3) then
			bot:Action_MoveToLocation(add(laneFront, RandomVector(100)))
			return
		end
	end
	autoCleanupCache()
	local gameState = getGlobalGameState()
	local locationState = getGlobalLocationState()
	local botState = getBotState(bot)
	local botLocation = botState.location
	local alliesNearBot = getCachedAlliesNearLoc(botLocation, 1600)
	local enemiesNearBot = getCachedEnemiesNearLoc(botLocation, 1600)
	local attackRange = botState.attackRange
	local hpRatio = botState.hp
	local laneFrontOffset = math.min(hpRatio, 0.7) * 1000 - 700 + RemapValClamped(attackRange, 300, 700, 0, -600)
	local enemyTowers = botState.nearbyTowers
	local allyLaneCreeps = botState.nearbyLaneCreeps
	if #alliesNearBot < #enemiesNearBot or Push.IsAnyTargetBackdooredAt(bot, lane) then
		local maxEnemyRange = 0
		for _, enemyHero in ipairs(enemiesNearBot) do
			if Fu.IsValidHero(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
				local enemyRange = enemyHero:GetAttackRange()
				if enemyRange > maxEnemyRange then
					maxEnemyRange = enemyRange
				end
			end
		end
		laneFrontOffset = -1000 - maxEnemyRange
	end
	local targetLocation = GetLaneFrontLocation(gameState.team, lane, laneFrontOffset)
	local ourFountainTpPoint = gameState.team == Team.Radiant and radiantFountainTpPoint or direFountainTpPoint
	if getLocationToLocationDistance(targetLocation, ourFountainTpPoint) < 3000 then
		local allyTower = getAllyLaneTower(gameState.team, lane)
		if allyTower then
			targetLocation = allyTower:GetLocation()
		else
			targetLocation = GetLaneFrontLocation(gameState.team, lane, 0)
		end
	end
	local botDistanceToFountain = getLocationToLocationDistance(botLocation, ourFountainTpPoint)
	local targetDistanceToFountain = getLocationToLocationDistance(targetLocation, ourFountainTpPoint)
	if botDistanceToFountain > targetDistanceToFountain + 500 then
		if #allyLaneCreeps >= 2 or #alliesNearBot >= 3 then
			targetLocation = botLocation
		end
	end
	if
		not botState.distanceToTargetLoc
		or math.abs(botState.distanceToTargetLoc - GetUnitToLocationDistance(bot, targetLocation)) > 50
	then
		getBotState(bot, targetLocation)
	end
	if
		Fu.IsValidBuilding(enemyTowers[1])
		and (enemyTowers[1]:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(#allyLaneCreeps <= 2 and 4 or 2))
	then
		local safeDistance = enemyTowers[1]:GetAttackRange() + 200
		local shouldStepOut = false
		-- Also step out when an attack order on an allied creep failed to move the tower's aggro
		-- in the last 6s (ability_item_usage_generic DeflectTowerAggro).
		if hpRatio < 0.6 or DotaTime() < (bot._deaggroFailedAt or -99) + 6 then
			shouldStepOut = true
		else
			local towerDamage = enemyTowers[1]:GetAttackDamage() * enemyTowers[1]:GetAttackSpeed() * 5
				- bot:GetHealthRegen() * 5
			if bot:GetActualIncomingDamage(towerDamage, DamageType.Physical) / bot:GetHealth() > 0.4 then
				shouldStepOut = true
			end
		end
		if shouldStepOut then
			local retreatLocation =
				Fu.AdjustLocationWithOffsetTowardsFountain(enemyTowers[1]:GetLocation(), safeDistance)
			bot:Action_MoveToLocation(add(retreatLocation, RandomVector(80)))
			return
		end
	end
	do
		local laneBuilding = enemyTowers[1] or getLaneTargetBuilding(lane)
		if
			laneBuilding ~= nil
			and Fu.Utils.IsValidTower(laneBuilding)
			and laneBuilding:HasModifier("modifier_fountain_glyph")
		then
			local maxEnemyRange = 0
			local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1600)
			for _, enemyHero in ipairs(nearbyEnemies) do
				if Fu.IsValidHero(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
					local enemyRange = enemyHero:GetAttackRange()
					if enemyRange > maxEnemyRange then
						maxEnemyRange = enemyRange
					end
				end
			end
			local backOffset = -1000 - maxEnemyRange
			local retreatLocation = GetLaneFrontLocation(GetTeam(), lane, backOffset)
			local enemyCreeps = bot:GetNearbyCreeps(attackRange + 200, true) or {}
			if
				#enemyCreeps > 0
				and Fu.CanBeAttacked(enemyCreeps[1])
				and not enemyCreeps[1]:HasModifier("modifier_fountain_glyph")
			then
				bot:Action_AttackUnit(enemyCreeps[1], true)
			else
				bot:Action_MoveToLocation(add(retreatLocation, RandomVector(200)))
			end
			return
		end
	end
	do
		local enemyLaneCreeps = bot:GetNearbyLaneCreeps(1200, true)
		local creepOnMe = false
		if enemyLaneCreeps then
			for _, creep in ipairs(enemyLaneCreeps) do
				if Fu.IsValid(creep) and creep:GetAttackTarget() == bot then
					creepOnMe = true
					break
				end
			end
		end
		if not creepOnMe then
			creepOnMe = bot:WasRecentlyDamagedByCreep(1.0)
		end
		-- targetLocation can be the hero's own spot once they are ahead of the wave, so moving there
		-- left them standing in the creeps that were already hitting them.
		if creepOnMe then
			local heroes = bot:GetNearbyHeroes(1000, true, BotMode.None) or {}
			if #heroes == 0 then
				local away = Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 700)
				bot:Action_MoveToLocation(away)
				return
			end
		end
	end
	-- Allow hitting a tower already in attack range even without a creep wave
	-- (supports like Shadow Shaman often stand on tower with no ally creeps).
	local buildingInHitRange = false
	do
		local earlyBuilding = enemyTowers[1] or getLaneTargetBuilding(lane)
		if
			earlyBuilding ~= nil
			and Fu.IsValidBuilding(earlyBuilding)
			and Fu.CanBeAttacked(earlyBuilding)
			and not Push.HasBackdoorProtect(earlyBuilding)
			and Fu.IsInRange(bot, earlyBuilding, attackRange + 150)
		then
			buildingInHitRange = true
		end
	end
	local hasPushSupport = #allyLaneCreeps >= 1 or #alliesNearBot > #enemiesNearBot or buildingInHitRange
	local enemyFountainPoint = gameState.team == Team.Radiant and direFountainTpPoint or radiantFountainTpPoint
	local distanceToEnemyFountain = getLocationToLocationDistance(botLocation, enemyFountainPoint)
	if distanceToEnemyFountain < 3000 or botState.distanceToAncient < 1500 then
		local wasHitByTower = bot:WasRecentlyDamagedByTower(3)
		local isUnsupported = #allyLaneCreeps < 2 and #alliesNearBot < 3
		if wasHitByTower and isUnsupported then
			local retreatLocation = GetLaneFrontLocation(GetTeam(), lane, -500)
			bot:Action_MoveToLocation(add(retreatLocation, RandomVector(100)))
			return
		end
		if distanceToEnemyFountain < 2000 and not bot:WasRecentlyDamagedByAnyHero(1) then
			enemyAncient = gameState.enemyAncient
			if
				enemyAncient
				and Fu.CanBeAttacked(enemyAncient)
				and not Push.HasBackdoorProtect(enemyAncient)
				and botState.distanceToAncient < 1000
			then
				bot:Action_AttackUnit(enemyAncient, true)
				return
			end
			local retreatLocation = GetLaneFrontLocation(GetTeam(), lane, -500)
			bot:Action_MoveToLocation(add(retreatLocation, RandomVector(100)))
			return
		end
	end
	enemyAncient = gameState.enemyAncient
	local alliesNearAncient = enemyAncient and Fu.GetAlliesNearLoc(enemyAncient:GetLocation(), 1600)
	if
		enemyAncient
		and botState.distanceToAncient < 1000
		and Fu.CanBeAttacked(enemyAncient)
		and not Push.HasBackdoorProtect(enemyAncient)
		and (
			#Push.GetAllyHeroesAttackingUnit(enemyAncient) >= 3
			or #Push.GetAllyCreepsAttackingUnit(enemyAncient) >= 4
			or enemyAncient:GetHealthRegen() < 20
			or (alliesNearAncient and #alliesNearAncient or 0) >= 4
		)
	then
		bot:Action_AttackUnit(enemyAncient, true)
		return
	end
	if not hasPushSupport then
		local distanceToTarget = GetUnitToLocationDistance(bot, targetLocation)
		if distanceToTarget > 300 then
			bot:Action_MoveToLocation(targetLocation)
			return
		end
		local laneFront = GetLaneFrontLocation(GetTeam(), lane, -300)
		bot:Action_AttackMove(laneFront)
		return
	end
	local specialUnitRange = math.min(700 + attackRange, 1600)
	if enemyAncient and botState.distanceToAncient < 2600 then
		specialUnitRange = 1600
	end
	local specialUnits = botState.nearbyCreeps
	local cacheKey = CacheKeys.PUSH_SPECIAL_CREEPS + bot:GetPlayerID()
	local cachedUnits = Fu.Utils.GetCachedVars(cacheKey, 0.2)
	if cachedUnits then
		specialUnits = cachedUnits
	else
		specialUnits = Push.GetSpecialUnitsNearby(bot, specialUnits, specialUnitRange)
		Fu.Utils.SetCachedVars(cacheKey, specialUnits)
	end
	local teamFountain = locationState.teamFountain
	local hasEnemyTower = Fu.IsValidBuilding(enemyTowers[1])
	local towerDistanceToFountain = hasEnemyTower and GetUnitToLocationDistance(enemyTowers[1], teamFountain) or 0
	-- Priority while pushing: heroes > creeps > towers.
	do
		local nearbyEnemies = bot:GetNearbyHeroes(1200, true, BotMode.None) or {}
		if #nearbyEnemies > 0 and #alliesNearBot >= #nearbyEnemies then
			local weakestEnemy = nil
			local lowestHealth = 999999
			for _, enemyHero in ipairs(nearbyEnemies) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.CanBeAttacked(enemyHero)
					and not Fu.IsSuspiciousIllusion(enemyHero)
					and not HeroCoveredByTower(bot, enemyHero, #alliesNearBot, #nearbyEnemies, lane)
				then
					local health = enemyHero:GetHealth()
					if health < lowestHealth then
						lowestHealth = health
						weakestEnemy = enemyHero
					end
				end
			end
			if weakestEnemy then
				bot:Action_AttackUnit(weakestEnemy, true)
				return
			end
		end
	end
	-- Attack the first special unit that qualifies; skip the rest (was a repeat/break "continue").
	for _, unit in ipairs(specialUnits) do
		if not Fu.IsValid(unit) or not Fu.CanBeAttacked(unit) then
			goto continue
		end
		if Fu.IsTormentor(unit) or Fu.IsRoshan(unit) then
			goto continue
		end
		-- Game 032, 13:25: Techies, Pudge and OD, pushing mid, paced by a neutral camp next to
		-- the Dire outpost (moved 98-215 in 10s): the nearby-creep list includes neutrals, so
		-- they hit the camp, then walked back toward the lane. Pushing leaves neutrals alone
		-- unless one is hitting this hero.
		if unit:GetTeam() == TEAM_NEUTRAL and unit:GetAttackTarget() ~= bot then
			goto continue
		end
		if hasEnemyTower and GetUnitToLocationDistance(unit, teamFountain) >= towerDistanceToFountain + 500 then
			goto continue
		end
		bot:Action_AttackUnit(unit, true)
		do
			return
		end
		::continue::
	end
	local pushTarget = pickPushTarget(bot, lane, targetLocation)
	if
		pushTarget
		and Fu.IsValidBuilding(pushTarget)
		and Fu.CanBeAttacked(pushTarget)
		and not Push.HasBackdoorProtect(pushTarget)
	then
		if Fu.IsInRange(bot, pushTarget, attackRange + 150) then
			bot:Action_AttackUnit(pushTarget, true)
		else
			local approachLocation = Fu.AdjustLocationWithOffsetTowardsFountain(pushTarget:GetLocation(), attackRange)
			bot:Action_MoveToLocation(add(approachLocation, RandomVector(50)))
		end
		return
	end
	local laneTarget = getLaneTargetBuilding(lane)
	if
		laneTarget ~= nil
		and Fu.IsValidBuilding(laneTarget)
		and Fu.CanBeAttacked(laneTarget)
		and not Push.HasBackdoorProtect(laneTarget)
	then
		local distance = GetUnitToUnitDistance(bot, laneTarget)
		if distance <= attackRange + 150 then
			bot:Action_AttackUnit(laneTarget, true)
			return
		else
			local approachLocation = Fu.AdjustLocationWithOffsetTowardsFountain(laneTarget:GetLocation(), attackRange)
			bot:Action_MoveToLocation(approachLocation)
			return
		end
	end
	-- The tower ahead is backdoor-protected (no creeps of ours at it): wait for the wave outside its attack
	-- range. The fallback below attack-moves to the lane front, which is right under that tower: game 038,
	-- 27:50, Dire's five idled under Radiant's bottom T2 (push capped to 0.25 by the backdoor) taking hits.
	for _, tower in ipairs(bot:GetNearbyTowers(1200, true) or {}) do
		if Fu.IsValidBuilding(tower) and Push.HasBackdoorProtect(tower) then
			-- GetAttackRange on a building is not in docs/BOT_API_RUNTIME.md: guarded, with 700 as an unverified
			-- fallback; the log prints the range used so a game confirms it.
			local okRange, rawRange = pcall(function()
				return tower:GetAttackRange()
			end)
			local baseRange = (okRange and type(rawRange) == "number" and rawRange > 0) and rawRange or 700
			local towerRange = baseRange + tower:GetBoundingRadius() + bot:GetBoundingRadius()
			local towerDistance = GetUnitToUnitDistance(bot, tower)
			if towerDistance < towerRange + 150 then
				if DotaTime() >= (bot._pushWaitOutsideLogAt or -999) then
					bot._pushWaitOutsideLogAt = DotaTime() + 5
					pcall(
						print,
						string.format(
							"[SHy-PUSH] t=%.0f %s wait-outside-tower why=backdoor tower=%s dist=%d range=%d",
							DotaTime(),
							(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
							tower:GetUnitName(),
							towerDistance,
							towerRange
						)
					)
				end
				local waitLocation = Fu.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), towerRange + 250)
				bot:Action_MoveToLocation(add(waitLocation, RandomVector(80)))
				return
			end
		end
	end
	if distanceToEnemyFountain > 2500 then
		local nearbyEnemies = bot:GetNearbyHeroes(attackRange + 300, true, BotMode.None) or {}
		for _, enemyHero in ipairs(nearbyEnemies) do
			if Fu.IsValidHero(enemyHero) and Fu.CanBeAttacked(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
				bot:Action_AttackUnit(enemyHero, true)
				return
			end
		end
	end
	if distanceToEnemyFountain < 2500 and #allyLaneCreeps < 2 then
		local retreatLocation = GetLaneFrontLocation(GetTeam(), lane, -500)
		bot:Action_MoveToLocation(add(retreatLocation, RandomVector(100)))
	else
		local distanceToTarget = GetUnitToLocationDistance(bot, targetLocation)
		if distanceToTarget > 300 then
			bot:Action_MoveToLocation(targetLocation)
		else
			local laneFront = GetLaneFrontLocation(gameState.team, lane, 200)
			bot:Action_AttackMove(laneFront)
		end
	end
end
function Push.TryClearingOtherLaneHighGround(bot, location)
	local gameState = getGameState()
	local unitState = getUnitState()
	local enemyBuildings = unitState.enemyBuildings
	local function isTargetable(building)
		return Fu.IsValidBuilding(building) and Fu.CanBeAttacked(building) and not Push.HasBackdoorProtect(building)
	end
	local nearestBarracks = nil
	local nearestDistance = math.huge
	for _, building in ipairs(enemyBuildings) do
		if
			isTargetable(building)
			and (
				building == GetBarracks(gameState.enemyTeam, Barracks.TopMelee)
				or building == GetBarracks(gameState.enemyTeam, Barracks.TopRanged)
				or building == GetBarracks(gameState.enemyTeam, Barracks.MidMelee)
				or building == GetBarracks(gameState.enemyTeam, Barracks.MidRanged)
				or building == GetBarracks(gameState.enemyTeam, Barracks.BotMelee)
				or building == GetBarracks(gameState.enemyTeam, Barracks.BotRanged)
			)
		then
			local distance = GetUnitToLocationDistance(building, location)
			if distance < nearestDistance then
				nearestBarracks = building
				nearestDistance = distance
			end
		end
	end
	if nearestBarracks then
		return nearestBarracks
	end
	local nearestTier3Tower = nil
	nearestDistance = math.huge
	for _, building in ipairs(enemyBuildings) do
		if
			isTargetable(building)
			and (
				building == GetTower(gameState.enemyTeam, Tower.Top3)
				or building == GetTower(gameState.enemyTeam, Tower.Mid3)
				or building == GetTower(gameState.enemyTeam, Tower.Bot3)
			)
		then
			local distance = GetUnitToLocationDistance(building, location)
			if distance < nearestDistance then
				nearestTier3Tower = building
				nearestDistance = distance
			end
		end
	end
	if nearestTier3Tower then
		return nearestTier3Tower
	end
	return nil
end
function Push.CanBeAttacked(unit)
	return not not unit and unit:CanBeSeen() and not unit:IsInvulnerable()
end
function Push.IsInDangerWithinTower(unit, threshold, seconds)
	local unitState = getUnitState()
	local incomingDamage = 0
	for _, enemyHero in ipairs(unitState.enemyHeroes) do
		if
			Fu.IsValid(enemyHero)
			and Fu.IsInRange(unit, enemyHero, 1600)
			and (enemyHero:GetAttackTarget() == unit or Fu.IsChasingTarget(enemyHero, unit))
		then
			incomingDamage = incomingDamage
				+ unit:GetActualIncomingDamage(
					enemyHero:GetAttackDamage() * enemyHero:GetAttackSpeed() * seconds,
					DamageType.Physical
				)
		end
	end
	return incomingDamage / unit:GetHealth() * 1.2 > threshold
end
function Push.ShouldWaitForImportantItemsSpells(bot)
	return false
end
function Push.FindBestHGTarget(bot, maxDistance, targetLocation)
	local gameState = getGameState()
	local unitState = getUnitState()
	local function isBarracks(building)
		return stringIncludes(building:GetUnitName(), "rax")
	end
	local function isMelee(building)
		return stringIncludes(building:GetUnitName(), "melee")
	end
	local function isRanged(building)
		return stringIncludes(building:GetUnitName(), "ranged")
	end
	local function isTier3Tower(building)
		return building == GetTower(gameState.enemyTeam, Tower.Top3)
			or building == GetTower(gameState.enemyTeam, Tower.Mid3)
			or building == GetTower(gameState.enemyTeam, Tower.Bot3)
	end
	local function isBaseTower(building)
		return building == GetTower(gameState.enemyTeam, Tower.Base1)
			or building == GetTower(gameState.enemyTeam, Tower.Base2)
	end
	local meleeBarracks = nil
	local meleeDistance = math.huge
	local rangedBarracks = nil
	local rangedDistance = math.huge
	local tier3Tower = nil
	local tier3Distance = math.huge
	local baseTower = nil
	local baseDistance = math.huge
	local otherBuilding = nil
	local otherDistance = math.huge
	for _, building in ipairs(unitState.enemyBuildings) do
		if Fu.IsValidBuilding(building) and Fu.CanBeAttacked(building) and not Push.HasBackdoorProtect(building) then
			local distance = GetUnitToUnitDistance(bot, building)
			if distance <= maxDistance then
				local targetDistance = targetLocation and GetUnitToLocationDistance(building, targetLocation) or 0
				if isBarracks(building) then
					if isMelee(building) then
						if
							distance < meleeDistance
							or distance == meleeDistance
								and targetDistance < (meleeBarracks and GetUnitToLocationDistance(
									meleeBarracks,
									targetLocation
								) or targetDistance)
						then
							meleeBarracks = building
							meleeDistance = distance
						end
					elseif isRanged(building) then
						if
							distance < rangedDistance
							or distance == rangedDistance
								and targetDistance < (rangedBarracks and GetUnitToLocationDistance(
									rangedBarracks,
									targetLocation
								) or targetDistance)
						then
							rangedBarracks = building
							rangedDistance = distance
						end
					end
				elseif isTier3Tower(building) then
					if
						distance < tier3Distance
						or distance == tier3Distance
							and targetDistance < (tier3Tower and GetUnitToLocationDistance(tier3Tower, targetLocation) or targetDistance)
					then
						tier3Tower = building
						tier3Distance = distance
					end
				elseif isBaseTower(building) then
					if
						distance < baseDistance
						or distance == baseDistance
							and targetDistance < (baseTower and GetUnitToLocationDistance(baseTower, targetLocation) or targetDistance)
					then
						baseTower = building
						baseDistance = distance
					end
				else
					if
						distance < otherDistance
						or distance == otherDistance
							and targetDistance < (otherBuilding and GetUnitToLocationDistance(
								otherBuilding,
								targetLocation
							) or targetDistance)
					then
						otherBuilding = building
						otherDistance = distance
					end
				end
			end
		end
	end
	return meleeBarracks or rangedBarracks or tier3Tower or otherBuilding
end
-- Lanes our creeps press (#12, PushRules.LaneUnderPressure): the lane's next target is their T3 or deeper and our
-- lane front, with 2+ of our lane creeps within 1000 of it, stands within 1500 of that target. Per team, every 2s.
-- Returns the count and a "top,mid" style list for the logs.
local pressureByTeam = {}
function Push.CreepPressureLanes()
	local team = GetTeam()
	local cached = pressureByTeam[team]
	if cached ~= nil and DotaTime() - cached.at < 2 then
		return cached.count, cached.names
	end
	local creeps = GetUnitList(UnitType.AlliedCreeps) or {}
	local count, names = 0, {}
	for _, lane in ipairs({ Lane.Top, Lane.Mid, Lane.Bot }) do
		local tier = Push.GetLaneBuildingTier(lane)
		local target = tier >= 3 and getLaneTargetBuilding(lane) or nil
		if target ~= nil then
			local front = GetLaneFrontLocation(team, lane, 0)
			local atFront = 0
			for _, creep in ipairs(creeps) do
				if
					creep ~= nil
					and not creep:IsNull()
					and creep:IsAlive()
					and creep:IsCreep()
					and GetUnitToLocationDistance(creep, front) <= 1000
				then
					atFront = atFront + 1
					if atFront >= 2 then
						break
					end
				end
			end
			if PushRules.LaneUnderPressure(tier, GetUnitToLocationDistance(target, front), atFront) then
				count = count + 1
				names[#names + 1] = lane == Lane.Top and "top" or (lane == Lane.Mid and "mid" or "bot")
			end
		end
	end
	local list = #names > 0 and table.concat(names, ",") or "-"
	pressureByTeam[team] = { at = DotaTime(), count = count, names = list }
	return count, list
end
-- Roshan first (#12, PushRules.RoshanFirst, maintainer 2026-11-22): every enemy alive, their base open, Roshan up,
-- no advantage window and our base not hit: the Aegis before the high ground. Read by mode_roshan_generic.lua.
-- Per team, every 1s; one [SHy-ROSH] aegis-first line when it turns on or off.
local roshanFirstByTeam = {}
function Push.RoshanFirstState(bot)
	local team = GetTeam()
	local state = roshanFirstByTeam[team]
	if state ~= nil and DotaTime() - state.at < 1 then
		return state.on, state.why, state.pressure
	end
	local gameState = getGlobalGameState()
	refreshThreatState(team)
	local adv = ReadAdvantage(gameState, bot)
	local baseOpen = false
	for _, lane in ipairs({ Lane.Top, Lane.Mid, Lane.Bot }) do
		if Push.GetLaneBuildingTier(lane) >= 3 then
			baseOpen = true
			break
		end
	end
	local _, ahead = AncientOpenAndAhead(gameState)
	local pressure, pressureNames = Push.CreepPressureLanes()
	local baseHeroes = baseThreat.heroes or 0
	local on, why = PushRules.RoshanFirst({
		enemiesAlive = gameState.aliveEnemyCount or 0,
		enemyPlayers = #GetTeamPlayers(GetOpposingTeam()),
		alliesAlive = gameState.aliveAllyCount or 0,
		baseOpen = baseOpen,
		roshAlive = Fu.IsRoshanAlive(),
		ourAegis = gameState.hasAegis == true,
		advantage = adv.desire ~= nil and not gameState.isLaningPhase,
		baseThreat = baseHeroes >= 1 or Utils.BaseUnderCreeps(bot),
		ahead = ahead,
		pressureLanes = pressure,
	})
	local was = state ~= nil and state.on or false
	if on ~= was then
		pcall(
			print,
			string.format(
				"[SHy-ROSH] t=%.0f %s aegis-first %s why=%s alive=%d/%d baseOpen=%s ahead=%s pressure=%s",
				DotaTime(),
				team == TEAM_DIRE and "dire" or "radiant",
				on and "on" or "off",
				why,
				gameState.aliveAllyCount or 0,
				gameState.aliveEnemyCount or 0,
				tostring(baseOpen),
				tostring(ahead),
				pressureNames
			)
		)
	end
	roshanFirstByTeam[team] = { at = DotaTime(), on = on, why = why, pressure = pressure }
	return on, why, pressure
end
return Push
