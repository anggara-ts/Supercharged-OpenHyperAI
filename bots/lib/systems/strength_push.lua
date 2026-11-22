-- Shared bot system: the strength push (#12). When our team is clearly stronger (bots/lib/systems/strength_rules.lua)
-- and nothing needs defending, the cores (and the supports near) take one lane's push for a window of ~40s, so a
-- team that is simply ahead pushes instead of farming jungle camps (game 074, 45:30-47:00). It only raises the lane
-- push desire (the push Think in bots/lib/systems/push.lua walks the group to the lane front with the creeps and hits
-- the buildings); farm stays under it (mode_farm_generic.lua, StrengthPush.FarmCap).
--
-- What the bot API lets us read (docs/BOT_API_RUNTIME.md): GetHeroLevel(playerId) and IsHeroAlive(playerId) for every
-- player of both teams, humans included. Net worth has no per-player-ID call: unit:GetNetWorth() is used on our own
-- heroes; on an enemy handle (only while it is visible) it is probed once per hero and logged (`strength-nw-probe`)
-- because nobody has confirmed it returns the real value there. Otherwise the compare falls back to the item cost of
-- the six slots + backpack (unit:GetItemInSlot, GetItemCost) for both teams, the highest seen per enemy, and to
-- levels only when an enemy has not been seen for 2 minutes. Enemy ultimates are not readable (no enemy cooldowns).
--
-- Logs: [SHy-PUSH] strength-push (start), strength-end why=, strength-skip why= (once per 30s per team),
-- strength-join (a bot raised by a window), strength-nw-probe; [SHy-FARM] yield-strength-push.
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Dota = require(GetScriptDirectory() .. "/lib/dota/index")
local Rules = require(GetScriptDirectory() .. "/lib/systems/strength_rules")
local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
local Barracks = Dota.Barracks
local Tower = Dota.Tower

local StrengthPush = {}
StrengthPush.Rules = Rules
-- The lane push desire of a bot in a window: above farm (0.6-0.77 in games 066/067, capped to FARM_CAP below during
-- a window), under retreat (capped under the bot's own retreat desire) and defend (a window ends when a lane needs
-- defending, StrengthRules.DEFAULTS.defendDesire).
StrengthPush.FLOOR = 0.78
StrengthPush.FARM_CAP = 0.7
local TICK_SECONDS = 2.5
local SKIP_LOG_SECONDS = 30
local MIN_HP = 0.45
local SUPPORT_RANGE = 4500
local FRONT_RADIUS = 1800
local BASE_HERO_RADIUS = 2200

local LANES = { LANE_TOP or 1, LANE_MID or 2, LANE_BOT or 3 }
local states = {}
local function TeamState(team)
	local state = states[team]
	if state == nil then
		state = {
			active = false,
			lastTick = -999,
			cooldownUntil = -999,
			lastSkipLog = -999,
			allyNw = {},
			allyItems = {},
			enemyNw = {},
			enemyItems = {},
			probed = {},
		}
		states[team] = state
	end
	return state
end
local function TeamName(team)
	return team == TEAM_DIRE and "dire" or "radiant"
end
local function ShortName(unit)
	return (string.gsub(unit:GetUnitName(), "npc_dota_hero_", ""))
end
local function ItemCost(hero)
	local total = 0
	for slot = 0, 8 do
		local item = hero:GetItemInSlot(slot)
		if item ~= nil then
			total = total + (GetItemCost(item:GetName()) or 0)
		end
	end
	return total
end
local function NetWorthOf(hero)
	local ok, value = pcall(function()
		return hero:GetNetWorth()
	end)
	if ok and type(value) == "number" then
		return value
	end
	return nil
end
local function RealHero(unit)
	return Fu.IsValidHero(unit)
		and not unit:IsIllusion()
		and not Fu.IsMeepoClone(unit)
		and not unit:HasModifier("modifier_arc_warden_tempest_double")
end

-- Reads every player's net worth / item cost into the team state, returns ourNw, theirNw, source.
local function ReadNetWorth(state, team, now)
	local allyIds = GetTeamPlayers(team) or {}
	local enemyIds = GetTeamPlayers(GetOpposingTeam()) or {}
	for i = 1, #allyIds do
		local member = GetTeamMember(i)
		if member ~= nil and not member:IsNull() then
			local pid = member:GetPlayerID()
			state.allyItems[pid] = { value = ItemCost(member), at = now }
			local nw = NetWorthOf(member)
			state.allyNw[pid] = nw ~= nil and nw > 0 and { value = nw, at = now } or nil
		end
	end
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES) or {}) do
		if RealHero(enemy) then
			local pid = enemy:GetPlayerID()
			local items = ItemCost(enemy)
			local prev = state.enemyItems[pid]
			state.enemyItems[pid] = { value = math.max(items, prev and prev.value or 0), at = now }
			local nw = NetWorthOf(enemy)
			if not state.probed[pid] then
				state.probed[pid] = true
				print(
					string.format(
						"[SHy-PUSH] t=%.0f %s strength-nw-probe hero=%s nw=%s items=%d",
						now,
						TeamName(team),
						ShortName(enemy),
						tostring(nw),
						items
					)
				)
			end
			if nw ~= nil and nw > 0 then
				local prevNw = state.enemyNw[pid]
				state.enemyNw[pid] = { value = math.max(nw, prevNw and prevNw.value or 0), at = now }
			end
		end
	end
	local maxAge = Rules.DEFAULTS.maxNwAge
	local ourNw = Rules.TeamTotal(allyIds, state.allyNw, now, nil)
	local theirNw = Rules.TeamTotal(enemyIds, state.enemyNw, now, maxAge)
	if ourNw ~= nil and theirNw ~= nil then
		return ourNw, theirNw, "nw"
	end
	-- Like with like: our items against their items seen.
	local ourItems = Rules.TeamTotal(allyIds, state.allyItems, now, nil)
	local theirItems = Rules.TeamTotal(enemyIds, state.enemyItems, now, maxAge)
	if ourItems ~= nil and theirItems ~= nil then
		return ourItems, theirItems, "items"
	end
	return ourItems, nil, "unknown"
end
local function AverageLevel(team)
	local total, count = 0, 0
	for _, pid in ipairs(GetTeamPlayers(team) or {}) do
		total = total + (GetHeroLevel(pid) or 0)
		count = count + 1
	end
	return count > 0 and total / count or 0
end
local function AliveCount(team)
	local count = 0
	for _, pid in ipairs(GetTeamPlayers(team) or {}) do
		if IsHeroAlive(pid) then
			count = count + 1
		end
	end
	return count
end
-- Our alive cores' ultimates: ready, learned.
local function UltsReady(team)
	local ready, total = 0, 0
	for i = 1, #(GetTeamPlayers(team) or {}) do
		local member = GetTeamMember(i)
		if member ~= nil and member:IsAlive() and Fu.IsCore(member) then
			for slot = 0, 5 do
				local ability = member:GetAbilityInSlot(slot)
				if ability ~= nil and ability:IsUltimate() and not ability:IsHidden() and ability:GetLevel() > 0 then
					total = total + 1
					if
						ability:IsPassive()
						or ability:GetCooldownTimeRemaining() <= 0 and member:GetMana() >= ability:GetManaCost()
					then
						ready = ready + 1
					end
					break
				end
			end
		end
	end
	return ready, total
end
-- The lane's next enemy building: tier 1-3 tower, else 4 (barracks, T4, Ancient).
local LANE_TOWERS = {
	[LANES[1]] = { Tower.Top1, Tower.Top2, Tower.Top3 },
	[LANES[2]] = { Tower.Mid1, Tower.Mid2, Tower.Mid3 },
	[LANES[3]] = { Tower.Bot1, Tower.Bot2, Tower.Bot3 },
}
local LANE_BARRACKS = {
	[LANES[1]] = { Barracks.TopRanged, Barracks.TopMelee },
	[LANES[2]] = { Barracks.MidRanged, Barracks.MidMelee },
	[LANES[3]] = { Barracks.BotRanged, Barracks.BotMelee },
}
local function Alive(unit)
	return unit ~= nil and not unit:IsNull() and unit:IsAlive()
end
local function LaneTarget(lane)
	local enemyTeam = GetOpposingTeam()
	for tier, towerId in ipairs(LANE_TOWERS[lane] or {}) do
		local tower = GetTower(enemyTeam, towerId)
		if Alive(tower) then
			return tower, tier
		end
	end
	for _, barracksId in ipairs(LANE_BARRACKS[lane] or {}) do
		local barracks = GetBarracks(enemyTeam, barracksId)
		if Alive(barracks) then
			return barracks, 4
		end
	end
	for _, towerId in ipairs({ Tower.Base1, Tower.Base2 }) do
		local tower = GetTower(enemyTeam, towerId)
		if Alive(tower) then
			return tower, 4
		end
	end
	local ancient = GetAncient(enemyTeam)
	if Alive(ancient) then
		return ancient, 4
	end
	return nil, 0
end
local function CoresAverageDistance(team, location)
	local total, count, allTotal, allCount = 0, 0, 0, 0
	for i = 1, #(GetTeamPlayers(team) or {}) do
		local member = GetTeamMember(i)
		if member ~= nil and member:IsAlive() then
			local dist = GetUnitToLocationDistance(member, location)
			allTotal, allCount = allTotal + dist, allCount + 1
			if Fu.IsCore(member) then
				total, count = total + dist, count + 1
			end
		end
	end
	if count > 0 then
		return total / count
	end
	return allCount > 0 and allTotal / allCount or 0
end
local function LaneEntries(team)
	local entries = {}
	for _, lane in ipairs(LANES) do
		local target, tier = LaneTarget(lane)
		if target ~= nil then
			entries[#entries + 1] = {
				lane = lane,
				tier = tier,
				hp = target:GetHealth() / math.max(1, target:GetMaxHealth()),
				allyDist = CoresAverageDistance(team, GetLaneFrontLocation(team, lane, 0)),
				target = target,
			}
		end
	end
	return entries
end
local function DefendPinged()
	local gameStates = Fu.Utils.GameStates
	return gameStates ~= nil
		and gameStates.defendPings ~= nil
		and GameTime() - (gameStates.defendPings.pingedTime or -999) <= 5
end
local function ReadInputs(state, team, bot, now)
	local ourNw, theirNw, nwSrc = ReadNetWorth(state, team, now)
	local defendDesire = 0
	for _, lane in ipairs(LANES) do
		defendDesire = math.max(defendDesire, GetDefendLaneDesire(lane) or 0)
	end
	local ourAncient = GetAncient(team)
	local baseHeroes = ourAncient ~= nil and Utils.CountEnemyHeroesNear(ourAncient:GetLocation(), BASE_HERO_RADIUS) or 0
	local ultsReady, ultsTotal = UltsReady(team)
	return {
		laning = Fu.IsInLaningPhase(),
		baseThreat = baseHeroes >= 1 or Utils.BaseUnderCreeps(bot),
		defendPing = DefendPinged(),
		defendDesire = defendDesire,
		aliveUs = AliveCount(team),
		aliveThem = AliveCount(GetOpposingTeam()),
		ourNw = ourNw,
		theirNw = theirNw,
		nwSrc = nwSrc,
		ourLvl = AverageLevel(team),
		theirLvl = AverageLevel(GetOpposingTeam()),
		aegis = Fu.DoesTeamHaveAegis() == true,
		ultsReady = ultsReady,
		ultsTotal = ultsTotal,
	}
end
local function Fields(i, nwPct, lvlLead)
	return string.format(
		"nw=%s/%s nwsrc=%s nwLead=%s lvl=%.1f/%.1f lvlLead=%.1f ults=%d/%d alive=%d/%d aegis=%s defend=%.2f scale=%.2f",
		i.ourNw ~= nil and string.format("%.0f", i.ourNw) or "-",
		i.theirNw ~= nil and string.format("%.0f", i.theirNw) or "-",
		tostring(i.nwSrc),
		nwPct ~= nil and string.format("%.2f", nwPct) or "-",
		i.ourLvl or 0,
		i.theirLvl or 0,
		lvlLead or 0,
		i.ultsReady or 0,
		i.ultsTotal or 0,
		i.aliveUs or 0,
		i.aliveThem or 0,
		tostring(i.aegis),
		i.defendDesire or 0,
		Rules.GetScale()
	)
end
local function TargetName(target)
	if target == nil or target:IsNull() then
		return "-"
	end
	return (string.gsub(target:GetUnitName(), "^npc_dota_", ""))
end
local function EndWindow(state, team, now, why, i)
	state.active = false
	state.cooldownUntil = now + Rules.Cooldown(why)
	print(
		string.format(
			"[SHy-PUSH] t=%.0f %s strength-end why=%s lane=%s target=%s held=%.0f alive=%d/%d",
			now,
			TeamName(team),
			why,
			tostring(state.lane),
			state.targetName or "-",
			now - (state.startedAt or now),
			i.aliveUs or 0,
			i.aliveThem or 0
		)
	)
end
local function TickTeam(bot)
	local team = GetTeam()
	local state = TeamState(team)
	local now = DotaTime()
	if now - state.lastTick < TICK_SECONDS then
		return state
	end
	state.lastTick = now
	if now < 0 then
		return state
	end
	local i = ReadInputs(state, team, bot, now)
	if state.active then
		i.factor = Rules.DEFAULTS.endFactor
		i.targetAlive = Alive(state.target)
		local front = GetLaneFrontLocation(team, state.lane, 0)
		i.enemiesAtFront = #Fu.GetEnemiesNearLoc(front, FRONT_RADIUS)
		i.alliesAtFront = #Fu.GetAlliesNearLoc(front, FRONT_RADIUS)
		local why = Rules.EndWhy(state, now, i)
		if why ~= nil then
			EndWindow(state, team, now, why, i)
		end
		return state
	end
	if now < state.cooldownUntil then
		return state
	end
	local ok, why, nwPct, lvlLead = Rules.Decide(i)
	local pick = ok and Rules.PickLane(LaneEntries(team)) or nil
	if ok and pick == nil then
		ok, why = false, "no-target"
	end
	if not ok then
		if why ~= "laning" and now - state.lastSkipLog >= SKIP_LOG_SECONDS then
			state.lastSkipLog = now
			print(
				string.format(
					"[SHy-PUSH] t=%.0f %s strength-skip why=%s %s",
					now,
					TeamName(team),
					tostring(why),
					Fields(i, nwPct, lvlLead)
				)
			)
		end
		return state
	end
	state.active = true
	state.lane = pick.lane
	state.target = pick.target
	state.targetName = TargetName(pick.target)
	state.startedAt = now
	state.aliveAtStart = i.aliveUs
	print(
		string.format(
			"[SHy-PUSH] t=%.0f %s strength-push lead=%s %s lane=%d target=%s tier=%d targetHp=%.2f allyDist=%.0f",
			now,
			TeamName(team),
			tostring(why),
			Fields(i, nwPct, lvlLead),
			pick.lane,
			state.targetName,
			pick.tier,
			pick.hp,
			pick.allyDist
		)
	)
	return state
end

-- Whether this bot joins the window: a core, or a support within SUPPORT_RANGE of the lane front; alive, level 6+,
-- HP 45%+, not outnumbered where it stands.
local function Joins(bot, lane)
	if not bot:IsAlive() or bot:IsIllusion() or bot:GetLevel() < 6 or Fu.GetHP(bot) < MIN_HP then
		return false
	end
	local location = bot:GetLocation()
	local enemiesNear = #Fu.GetEnemiesNearLoc(location, 1600)
	if enemiesNear >= 2 and enemiesNear > #Fu.GetAlliesNearLoc(location, 1600) then
		return false
	end
	return Fu.IsCore(bot) or GetUnitToLocationDistance(bot, GetLaneFrontLocation(GetTeam(), lane, 0)) <= SUPPORT_RANGE
end

-- The lane push desire with the strength push: baseDesire (Push.GetPushDesire) raised to FLOOR on the window's lane
-- for a bot that joins, kept under the bot's own retreat desire (mode_retreat_generic.lua bot._retreatFinalDesire).
function StrengthPush.LaneDesire(bot, lane, baseDesire)
	local base = type(baseDesire) == "number" and baseDesire or 0
	local okTick, state = pcall(TickTeam, bot)
	if not okTick then
		if not StrengthPush._errorLogged then
			StrengthPush._errorLogged = true
			print(string.format("[SHy-ERROR] t=%.0f strength-push tick: %s", DotaTime(), tostring(state)))
		end
		return baseDesire
	end
	if not state.active or state.lane ~= lane or not Joins(bot, lane) then
		return baseDesire
	end
	local now = DotaTime()
	local floor = StrengthPush.FLOOR
	local retreat = bot._retreatFinalDesire
	if retreat ~= nil and now - (retreat.t or -999) <= 1 and (retreat.d or 0) >= 0.2 then
		floor = math.min(floor, retreat.d - 0.02)
	end
	if floor <= base then
		return baseDesire
	end
	-- #87's group-push mark (farm stays under it there) and our own one for StrengthPush.FarmCap.
	bot._groupPushJoin = { at = now, desire = floor, why = "strength" }
	bot._strengthPushAt = now
	if bot._strengthJoinedAt ~= state.startedAt and not Fu.IsMeepoClone(bot) then
		bot._strengthJoinedAt = state.startedAt
		print(
			string.format(
				"[SHy-PUSH] t=%.0f %s strength-join lane=%d desire=%.2f was=%.2f hp=%.2f core=%s target=%s",
				now,
				ShortName(bot),
				lane,
				floor,
				base,
				Fu.GetHP(bot),
				tostring(Fu.IsCore(bot)),
				state.targetName or "-"
			)
		)
	end
	return floor
end

-- Farm desire during a window for a bot raised by it: at most FARM_CAP, so the bot walks to the lane.
function StrengthPush.FarmCap(bot, desire)
	if type(desire) ~= "number" or desire <= StrengthPush.FARM_CAP then
		return desire
	end
	local now = DotaTime()
	if now - (bot._strengthPushAt or -999) > 1 then
		return desire
	end
	if now >= (bot._farmYieldStrengthLogAt or -999) then
		bot._farmYieldStrengthLogAt = now + 8
		print(
			string.format(
				"[SHy-FARM] t=%.0f %s yield-strength-push farm=%.2f cap=%.2f",
				now,
				ShortName(bot),
				desire,
				StrengthPush.FARM_CAP
			)
		)
	end
	return StrengthPush.FARM_CAP
end

-- For tests: the team tick.
StrengthPush._Tick = TickTeam
-- For tests and other systems: the team's window (active, lane, targetName, startedAt).
function StrengthPush.State(team)
	return TeamState(team or GetTeam())
end

return StrengthPush
