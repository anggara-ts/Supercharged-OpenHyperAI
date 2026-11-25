-- Getting to a far objective (Roshan, Tormentor) faster than walking: a TP to our tower nearest
-- the target, or a Twin Gate. Used by the gather walks, and by the Roshan time estimate so a
-- call counts an ally across the map by how fast they can really get there.
--
-- TP scroll: 3s channel, 80s cooldown (Valve data).
-- Twin Gate warp, 7.42 game data (pak01_dir.vpk scripts/npc/npc_abilities.txt, "twin_gate_portal_warp"):
-- cast on the gate unit, AbilityCastRange 200, AbilityChannelTime 4.0, AbilityManaCost 30, a root
-- interrupts it (DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES). The channel time is read from the ability when the
-- hero has it.
--
-- 7.42 (issue #53): heroes no longer carry twin_gate_portal_warp or abyssal_underlord_portal_warp. The
-- [SHy-API] abilities dump of games 049-062 (slots 0-35) lists no system ability at all; before 7.42 the
-- engine's own ability list (game 043, Rubick) had ability_capture, abyssal_underlord_portal_warp,
-- twin_gate_portal_warp and ability_lamp_use in slots 23-26. That is the change that broke outpost capture
-- (#111, ValveSoftware/Dota2-Gameplay#32850). Without the ability the gate is never part of the plan
-- (Best / Eta): bots walk. A probe that tried move-to-unit / use-shrine / attack on a gate was dropped once
-- the limitation was confirmed (the #226 interaction probe found no warp in games 076-077); if Valve gives
-- heroes the ability back, [SHy-TRAVEL] warp-abilities shows it and the gate route turns on by itself.
local ObjectiveTravel = {}

local TP_CHANNEL = 3
local MIN_SAVED = 8 -- seconds a TP or gate has to save over walking
local GATE_CHANNEL = 4 -- twin_gate_portal_warp AbilityChannelTime (7.42 game data, above)
local GATE_RANGE = 200 -- twin_gate_portal_warp AbilityCastRange

local function Speed(unit)
	local ok, speed = pcall(function()
		return unit:GetCurrentMovementSpeed()
	end)
	return (ok and type(speed) == "number" and speed > 100) and speed or 300
end

local function Dist(locA, locB)
	local dx, dy = locA.x - locB.x, locA.y - locB.y
	return math.sqrt(dx * dx + dy * dy)
end

local function HeroName(unit)
	return (string.gsub(unit:GetUnitName(), "npc_dota_hero_", ""))
end

-- Our tower closest to loc (or the fountain area when loc is in our base).
local function TpSpot(loc)
	local best, bestD = nil, math.huge
	for id = 0, 10 do
		local tower = GetTower(GetTeam(), id)
		if tower ~= nil and tower:IsAlive() then
			local distance = GetUnitToLocationDistance(tower, loc)
			if distance < bestD then
				best, bestD = tower:GetLocation(), distance
			end
		end
	end
	return best, bestD
end

local function TpItem(unit)
	for _, slot in ipairs({ 15, 0, 1, 2, 3, 4, 5 }) do
		local ok, item = pcall(function()
			return unit:GetItemInSlot(slot)
		end)
		if ok and item ~= nil then
			local name = item:GetName()
			if name == "item_tpscroll" or name == "item_travel_boots" or name == "item_travel_boots_2" then
				if item:IsFullyCastable() then
					return item
				end
			end
		end
	end
	return nil
end

local gates = nil
local function Gates()
	if gates == nil or #gates < 2 then
		gates = {}
		for _, unit in pairs(GetUnitList(UNIT_LIST_ALL) or {}) do
			if unit ~= nil and unit:GetUnitName() == "npc_dota_unit_twin_gate" then
				gates[#gates + 1] = unit
			end
		end
	end
	return gates
end

-- The gate nearer to unit, and the other one.
local function NearFar(unit, list)
	local near, far = list[1], list[2]
	if GetUnitToUnitDistance(unit, list[2]) < GetUnitToUnitDistance(unit, near) then
		near, far = list[2], list[1]
	end
	return near, far
end

local function GateWarp(unit)
	local ok, warpAbility = pcall(function()
		return unit:GetAbilityByName("twin_gate_portal_warp")
	end)
	if ok and warpAbility ~= nil and warpAbility:IsFullyCastable() then
		return warpAbility
	end
	return nil
end

-- Seconds for the gate route: walk to the near gate, channel, 1s spare, walk from the far gate.
function ObjectiveTravel.GateSeconds(toNearGate, farGateToTarget, speed, channel)
	if channel == nil or channel <= 0 then
		channel = GATE_CHANNEL
	end
	return toNearGate / speed + channel + 1 + farGateToTarget / speed
end

-- Whether anyone on the team can walk through a Fiend's Gate: the warp ability (gone from heroes in 7.42),
-- or a human player. (A Scepter gate's Pit of Malice is decided in the Underlord hero file.)
function ObjectiveTravel.PortalWalkable(hasWarpAbility, humanPlayers)
	return hasWarpAbility == true or (humanPlayers or 0) > 0
end

-- Fastest way for unit to reach loc. Returns seconds, how ("walk" / "tp" / "gate"), and the
-- spot, item / gate to use.
function ObjectiveTravel.Best(unit, loc)
	local speed = Speed(unit)
	local here = unit:GetLocation()
	local walk = Dist(here, loc) / speed
	local best, how, extra, spot = walk, "walk", nil, nil
	local tp = TpItem(unit)
	if tp ~= nil then
		local towerLoc, towerToTarget = TpSpot(loc)
		if towerLoc ~= nil and Dist(here, towerLoc) > 2500 then
			local tpTime = TP_CHANNEL + 1 + towerToTarget / speed
			if tpTime + MIN_SAVED < best then
				best, how, extra, spot = tpTime, "tp", tp, towerLoc
			end
		end
	end
	local warp = GateWarp(unit)
	local list = Gates()
	if warp ~= nil and #list >= 2 then
		local near, far = NearFar(unit, list)
		local gateTime = ObjectiveTravel.GateSeconds(
			GetUnitToUnitDistance(unit, near),
			GetUnitToLocationDistance(far, loc),
			speed,
			warp:GetChannelTime()
		)
		if gateTime + MIN_SAVED < best then
			best, how, extra, spot = gateTime, "gate", warp, near
		end
	end
	return best, how, extra, spot
end

-- Seconds for unit to reach loc the fastest way (for timing estimates).
function ObjectiveTravel.Eta(unit, loc)
	local ok, seconds = pcall(ObjectiveTravel.Best, unit, loc)
	if ok and type(seconds) == "number" then
		return seconds
	end
	return GetUnitToLocationDistance(unit, loc) / Speed(unit)
end

-- Once per bot: does the engine give this hero the warp abilities (gone in 7.42)?
local function LogWarpAbilities(bot)
	if bot._travelWarpLogged then
		return
	end
	bot._travelWarpLogged = true
	local twin = bot:GetAbilityByName("twin_gate_portal_warp")
	local portal = bot:GetAbilityByName("abyssal_underlord_portal_warp")
	pcall(
		print,
		string.format(
			"[SHy-TRAVEL] t=%.0f %s warp-abilities twin=%s portal=%s",
			DotaTime(),
			HeroName(bot),
			tostring(twin ~= nil),
			tostring(portal ~= nil)
		)
	)
end

-- Issue a TP or gate order for bot toward loc when it is clearly faster than walking. Returns
-- true when it issued an order (or one is channeling), so the caller does not walk.
function ObjectiveTravel.Go(bot, loc, tag)
	LogWarpAbilities(bot)
	if bot:IsChanneling() then
		return true
	end
	if bot:WasRecentlyDamagedByAnyHero(2) or bot:IsRooted() then
		return false
	end
	local ok, seconds, how, extra, spot = pcall(ObjectiveTravel.Best, bot, loc)
	if not ok or how == "walk" or extra == nil then
		return false
	end
	local function Log()
		if DotaTime() >= (bot._travelLogAt or -999) then
			bot._travelLogAt = DotaTime() + 5
			pcall(
				print,
				string.format(
					"[SHy-TRAVEL] t=%.0f %s %s for=%s eta=%.0f walk=%.0f",
					DotaTime(),
					HeroName(bot),
					how,
					tostring(tag),
					seconds,
					GetUnitToLocationDistance(bot, loc) / Speed(bot)
				)
			)
		end
	end
	if how == "tp" then
		Log()
		bot:Action_UseAbilityOnLocation(extra, spot)
		return true
	end
	if how == "gate" then
		Log()
		if GetUnitToUnitDistance(bot, spot) > GATE_RANGE + 150 then
			bot:Action_MoveToLocation(spot:GetLocation())
		else
			bot:Action_UseAbilityOnEntity(extra, spot)
		end
		return true
	end
	return false
end

return ObjectiveTravel
