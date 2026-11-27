-- Abyssal Underlord: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local ObjectiveTravel = require(GetScriptDirectory() .. "/lib/systems/objective_travel")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 0, 10 }, ["t20"] = { 0, 10 }, ["t15"] = { 10, 0 }, ["t10"] = { 10, 0 } }
local tAllAbilityBuildList = { { 1, 3, 1, 2, 1, 6, 1, 2, 2, 2, 6, 3, 3, 3, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
local sUtilityList = { "item_lotus_orb", "item_crimson_guard", "item_heavens_halberd" }
local sUtility = sUtilityList[RandomInt(1, #sUtilityList)]
-- Stratz 7.41f, week of 9 Nov 2026: pos 1 has 466 matches, built from pos 3 (83,563) (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_double_gauntlets",
	"item_double_branches",
	"item_quelling_blade",
	"item_bracer",
	"item_soul_ring",
	"item_magic_wand",
	"item_arcane_boots",
	"item_rod_of_atos",
	"item_ultimate_scepter",
	"item_aghanims_shard",
	"item_shivas_guard",
	"item_ultimate_scepter_2",
	"item_blade_mail",
	"item_crimson_guard",
	"item_octarine_core",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 2,344 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_gauntlets",
	"item_quelling_blade",
	"item_circlet",
	"item_soul_ring",
	"item_magic_wand",
	"item_arcane_boots",
	"item_rod_of_atos",
	"item_ultimate_scepter",
	"item_aghanims_shard",
	"item_gungir",
	"item_shivas_guard",
	"item_ultimate_scepter_2",
	"item_heart",
	"item_octarine_core",
	"item_harpoon",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 83,563 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_double_gauntlets",
	"item_double_branches",
	"item_quelling_blade",
	"item_bracer",
	"item_soul_ring",
	"item_magic_wand",
	"item_arcane_boots",
	"item_rod_of_atos",
	"item_ultimate_scepter",
	"item_aghanims_shard",
	"item_shivas_guard",
	"item_ultimate_scepter_2",
	"item_blade_mail",
	"item_crimson_guard",
	"item_octarine_core",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 6,352 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_magic_stick",
	"item_branches",
	"item_gauntlets",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_headdress",
	"item_rod_of_atos",
	"item_mekansm",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_guardian_greaves",
	sUtility,
	"item_vanguard",
	"item_ultimate_scepter_2",
	"item_heart",
	"item_veil_of_discord",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 3,717 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_magic_stick",
	"item_branches",
	"item_gauntlets",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_headdress",
	"item_rod_of_atos",
	"item_mekansm",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_guardian_greaves",
	"item_ultimate_scepter_2",
	"item_crimson_guard",
	"item_heart",
	"item_lotus_orb",
	"item_moon_shard",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = {
	"item_travel_boots",
	"item_quelling_blade",
	"item_abyssal_blade",
	"item_magic_wand",
	"item_shivas_guard",
	"item_bracer",
	"item_assault",
	"item_soul_ring",
}
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_antimage" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDefaultItem"] = false
function X.MinionThink(hMinionUnit)
	Minion.MinionThink(hMinionUnit)
end
local firestormAbility =
	SafeAbility(bot:GetAbilityByName("abyssal_underlord_firestorm"), "abyssal_underlord_firestorm", "abyssal_underlord")
local pitOfMaliceAbility = SafeAbility(
	bot:GetAbilityByName("abyssal_underlord_pit_of_malice"),
	"abyssal_underlord_pit_of_malice",
	"abyssal_underlord"
)
local fiendsGateAbility = SafeAbility(
	bot:GetAbilityByName("abyssal_underlord_dark_portal"),
	"abyssal_underlord_dark_portal",
	"abyssal_underlord"
)
local firestormDesire, firestormLocation
local pitOfMaliceDesire, pitOfMaliceLocation
local fiendsGateDesire, fiendsGateLocation
local botTarget
local isGoingOnSomeone
local isAttacking
local mpRatio
local fiendsGateWhy, fiendsGateTarget
function X.SkillsComplement()
	X.GateSelfWatch()
	if Fu.CanNotUseAbility(bot) then
		return
	end
	local context = AbilityContext.Build(bot)
	isGoingOnSomeone = context.isEngaging
	isAttacking = Fu.IsAttacking(bot)
	mpRatio = context.mp
	botTarget = context.target
	pitOfMaliceDesire, pitOfMaliceLocation = X.ConsiderPitOfMalice()
	if pitOfMaliceDesire > 0 then
		bot:Action_UseAbilityOnLocation(pitOfMaliceAbility, pitOfMaliceLocation)
		return
	end
	firestormDesire, firestormLocation = X.ConsiderFirestorm()
	if firestormDesire > 0 then
		bot:Action_UseAbilityOnLocation(firestormAbility, firestormLocation)
		return
	end
	fiendsGateWhy, fiendsGateTarget = nil, nil
	fiendsGateDesire, fiendsGateLocation = X.ConsiderFiendsGate()
	if fiendsGateDesire > 0 then
		bot:Action_UseAbilityOnLocation(fiendsGateAbility, fiendsGateLocation)
		X.GateSelfStart(fiendsGateLocation, fiendsGateWhy or "travel", fiendsGateTarget)
		return
	end
end
-- fix: Firestorm and Pit were aimed with GetXUnitsTowardsLocation(bot, loc, castRange), which always returns a
-- point exactly castRange (cast range 675 + 200) from Underlord, so a close enemy group was missed by ~400+
-- units (radius 425 / 400). Aim at the spot itself; clamp to castRange only when it is beyond it (far targets as before).
function X.CastSpot(loc, castRange)
	if GetUnitToLocationDistance(bot, loc) <= castRange then
		return loc
	end
	return Fu.Site.GetXUnitsTowardsLocation(bot, loc, castRange)
end
function X.ConsiderFirestorm()
	if not firestormAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, firestormAbility:GetCastRange())
	local radius = firestormAbility:GetSpecialValueInt("radius")
	local castPoint = firestormAbility:GetCastPoint()
	if Fu.IsInTeamFight(bot, 1200) then
		local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange + radius, radius, castPoint, 0)
		local enemiesInAoe = Fu.GetEnemiesNearLoc(aoe.targetloc, radius)
		if enemiesInAoe ~= nil and #enemiesInAoe >= 2 then
			return BOT_ACTION_DESIRE_HIGH, X.CastSpot(aoe.targetloc, castRange)
		end
	end
	if isGoingOnSomeone then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange + radius)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			local alliesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			local enemiesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			if alliesNearTarget ~= nil and enemiesNearTarget ~= nil and #alliesNearTarget >= #enemiesNearTarget then
				enemiesNearTarget = Fu.GetEnemiesNearLoc(botTarget:GetLocation(), castRange + radius)
				if enemiesNearTarget ~= nil and #enemiesNearTarget >= 1 then
					return BOT_ACTION_DESIRE_HIGH, X.CastSpot(Fu.GetCenterOfUnits(enemiesNearTarget), castRange)
				end
				return BOT_ACTION_DESIRE_HIGH, X.CastSpot(botTarget:GetLocation(), castRange)
			end
		end
	end
	if Fu.IsPushing(bot) then
		local enemyLaneCreeps = bot:GetNearbyLaneCreeps(castRange + radius, true)
		if enemyLaneCreeps ~= nil and #enemyLaneCreeps >= 4 then
			return BOT_ACTION_DESIRE_HIGH, Fu.GetCenterOfUnits(enemyLaneCreeps)
		end
	end
	if Fu.IsFarming(bot) then
		if isAttacking then
			local neutralCreeps = bot:GetNearbyNeutralCreeps(castRange + radius)
			if neutralCreeps ~= nil and #neutralCreeps >= 3 and mpRatio > 0.3 then
				return BOT_ACTION_DESIRE_HIGH, Fu.GetCenterOfUnits(neutralCreeps)
			end
			local enemyLaneCreeps = bot:GetNearbyLaneCreeps(castRange + radius, true)
			if enemyLaneCreeps ~= nil and #enemyLaneCreeps >= 3 and mpRatio > 0.3 then
				return BOT_ACTION_DESIRE_HIGH, Fu.GetCenterOfUnits(enemyLaneCreeps)
			end
		end
	end
	if Fu.IsLaning(bot) then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
		local enemyLaneCreeps = bot:GetNearbyLaneCreeps(castRange + radius, true)
		if
			nearbyEnemies ~= nil
			and #nearbyEnemies == 0
			and enemyLaneCreeps ~= nil
			and #enemyLaneCreeps >= 4
			and isAttacking
			and mpRatio > 0.5
		then
			return BOT_ACTION_DESIRE_HIGH, Fu.GetCenterOfUnits(enemyLaneCreeps)
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, 500)
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if Fu.IsTormentor(botTarget) and Fu.IsInRange(bot, botTarget, 500) and isAttacking then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderPitOfMalice()
	if not pitOfMaliceAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, pitOfMaliceAbility:GetCastRange())
	local radius = pitOfMaliceAbility:GetSpecialValueInt("radius")
	local enemiesInRange = Fu.GetNearbyHeroes(bot, castRange + radius, true, BOT_MODE_NONE)
	for _, enemy in pairs(enemiesInRange) do
		if
			Fu.IsValidHero(enemy)
			and Fu.CanCastOnNonMagicImmune(enemy)
			and enemy:IsChanneling()
			and not Fu.IsSuspiciousIllusion(enemy)
		then
			return BOT_ACTION_DESIRE_HIGH, X.CastSpot(enemy:GetLocation(), castRange)
		end
	end
	if isGoingOnSomeone then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange + radius)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			local alliesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			local enemiesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			if alliesNearTarget ~= nil and enemiesNearTarget ~= nil and #alliesNearTarget >= #enemiesNearTarget then
				enemiesNearTarget = Fu.GetEnemiesNearLoc(botTarget:GetLocation(), castRange + radius)
				if enemiesNearTarget ~= nil and #enemiesNearTarget >= 1 then
					return BOT_ACTION_DESIRE_HIGH, X.CastSpot(Fu.GetCenterOfUnits(enemiesNearTarget), castRange)
				end
				return BOT_ACTION_DESIRE_HIGH, X.CastSpot(botTarget:GetLocation(), castRange)
			end
		end
	end
	if Fu.IsRetreating(bot) then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and Fu.IsChasingTarget(enemy, bot)
				and not Fu.IsSuspiciousIllusion(enemy)
				and not Fu.IsDisabled(enemy)
			then
				local alliesNearChaser = Fu.GetNearbyHeroes(enemy, 1200, true, BOT_MODE_NONE)
				local enemiesNearChaser = Fu.GetNearbyHeroes(enemy, 1200, false, BOT_MODE_NONE)
				if
					alliesNearChaser ~= nil
					and enemiesNearChaser ~= nil
					and (#enemiesNearChaser > #alliesNearChaser or bot:WasRecentlyDamagedByAnyHero(2.5))
					and GetUnitToUnitDistance(bot, enemy) < radius + 100
				then
					return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
				end
			end
		end
	end
	if Fu.IsPushing(bot) or Fu.IsDefending(bot) then
		local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange + radius, radius, 0, 0)
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
		local enemiesInAoe = Fu.GetEnemiesNearLoc(aoe.targetloc, radius)
		if
			nearbyAllies ~= nil
			and enemiesInAoe ~= nil
			and #enemiesInAoe >= 1
			and #nearbyAllies <= #enemiesInAoe + 1
		then
			return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, 500)
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
-- Fiend's Gate / Pit of Malice values, 7.42 game data (pak01_dir.vpk
-- scripts/npc/heroes/npc_dota_hero_abyssal_underlord.txt): abyssal_underlord_dark_portal AbilityCastRange 0
-- (global point cast), minimum_distance 1500, distance_from_fountain 1425, spawn_pit_on_cast with Scepter
-- (datafeed: "Summons a Pit of Malice around the furthermost of the portals"); abyssal_underlord_pit_of_malice
-- radius 400, ensnare_duration 1.5-1.8 (a root).
local GATE_MIN_DISTANCE = 1500
local GATE_FOUNTAIN_DISTANCE = 1425
local PIT_RADIUS = 400
local PIT_AIM_RADIUS = PIT_RADIUS - 50 -- enemies keep moving: count only those well inside the pit
local GATE_TRAVEL_DISTANCE = 4000 -- a defend / fight / ally in trouble this far away is worth a gate trip
local GATE_SELF_WATCH = 7 -- seconds watched after the first cast (warp_channel_duration is 3.5 at most)
local GATE_SELF_JUMP = 1500 -- moved this far between two thinks: Underlord was teleported

local function Dist2D(locA, locB)
	local dx, dy = locA.x - locB.x, locA.y - locB.y
	return math.sqrt(dx * dx + dy * dy)
end

-- The spot for a pit of radius aimRadius that covers the most of locs (enemy positions): each position, each
-- midpoint of two and the centre of all are tried. Returns the spot (or nil) and how many it covers.
function X.GatePitSpot(locs, aimRadius)
	local candidates = {}
	local sumX, sumY = 0, 0
	for i, loc in ipairs(locs) do
		candidates[#candidates + 1] = { x = loc.x, y = loc.y }
		sumX, sumY = sumX + loc.x, sumY + loc.y
		for j = i + 1, #locs do
			candidates[#candidates + 1] = { x = (loc.x + locs[j].x) / 2, y = (loc.y + locs[j].y) / 2 }
		end
	end
	if #locs > 0 then
		candidates[#candidates + 1] = { x = sumX / #locs, y = sumY / #locs }
	end
	local best, bestCount = nil, 0
	for _, spot in ipairs(candidates) do
		local count = 0
		for _, loc in ipairs(locs) do
			local dx, dy = loc.x - spot.x, loc.y - spot.y
			if dx * dx + dy * dy <= aimRadius * aimRadius then
				count = count + 1
			end
		end
		if count > bestCount then
			best, bestCount = spot, count
		end
	end
	return best, bestCount
end

-- Whether a Scepter gate's pit is worth it. why "save": an ally under attack by enemy heroes (hurt, or 2+ of
-- them on him); why "fight": a group of 2+ enemies our team is engaging. Either way the far portal must be at
-- least minimum_distance (+100) from Underlord, and the pit must catch enough of them.
function X.GatePitWorth(why, distance, pitCount, allyHpRatio, enemiesNearAlly)
	if distance < GATE_MIN_DISTANCE + 100 then
		return false
	end
	if why == "save" then
		return pitCount >= 1 and (allyHpRatio < 0.65 or enemiesNearAlly >= 2)
	end
	return pitCount >= 2
end

local function GateLocationOk(loc)
	return GetUnitToLocationDistance(bot, loc) >= GATE_MIN_DISTANCE + 100
		and Dist2D(loc, Fu.GetEnemyFountain()) > GATE_FOUNTAIN_DISTANCE + 100
		and Dist2D(loc, Fu.GetTeamFountain()) > GATE_FOUNTAIN_DISTANCE + 100
		and IsLocationPassable(loc)
		and not Fu.IsLocationInChrono(loc)
		and not Fu.IsLocationInBlackHole(loc)
		and not Fu.IsLocationInArena(loc, 600)
end

local function RealEnemiesNear(loc, radius)
	local enemies = {}
	for _, enemyHero in pairs(Fu.GetEnemiesNearLoc(loc, radius)) do
		if Fu.IsValidHero(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
			enemies[#enemies + 1] = enemyHero
		end
	end
	return enemies
end

-- With Scepter the far portal drops a Pit of Malice, so a gate on a remote fight roots enemies there even though
-- no bot can walk through it (7.42, #53). Returns desire and location; logs [SHy-UNDERLORD] gate-pit.
function X.ConsiderGatePit()
	if pitOfMaliceAbility:GetLevel() < 1 then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Unless the self-test showed the gate leaves him where he is, he may land on the far portal himself: only
	-- while he is healthy and not running away.
	local selfState = bot._gateSelf ~= nil and bot._gateSelf.state or "untested"
	if selfState ~= "no" and (Fu.IsRetreating(bot) or Fu.GetHP(bot) < 0.5) then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local best
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
		if
			Fu.IsValidHero(allyHero)
			and allyHero ~= bot
			and not allyHero:IsIllusion()
			and GetUnitToUnitDistance(bot, allyHero) >= GATE_MIN_DISTANCE + 100
		then
			local hpRatio = Fu.GetHP(allyHero)
			-- save: enemy heroes on a hurt ally
			if allyHero:WasRecentlyDamagedByAnyHero(1.5) then
				local enemies = RealEnemiesNear(allyHero:GetLocation(), 900)
				local locs = {}
				for _, enemyHero in ipairs(enemies) do
					locs[#locs + 1] = enemyHero:GetLocation()
				end
				local spot, count = X.GatePitSpot(locs, PIT_AIM_RADIUS)
				if spot ~= nil then
					local loc = Vector(spot.x, spot.y, allyHero:GetLocation().z)
					local distance = GetUnitToLocationDistance(bot, loc)
					if
						X.GatePitWorth("save", distance, count, hpRatio, #enemies)
						and GateLocationOk(loc)
						and (best == nil or best.why ~= "save" or hpRatio < best.hp)
					then
						best =
							{ why = "save", loc = loc, ally = allyHero, count = count, dist = distance, hp = hpRatio }
					end
				end
			end
			-- fight: an ally engaging a remote enemy group
			local allyTarget = allyHero:GetAttackTarget()
			if
				(best == nil or best.why == "fight")
				and Fu.IsGoingOnSomeone(allyHero)
				and Fu.IsValidHero(allyTarget)
				and not Fu.IsSuspiciousIllusion(allyTarget)
				and GetUnitToUnitDistance(allyHero, allyTarget) <= 1000
			then
				local locs = {}
				for _, enemyHero in ipairs(RealEnemiesNear(allyTarget:GetLocation(), 900)) do
					locs[#locs + 1] = enemyHero:GetLocation()
				end
				local spot, count = X.GatePitSpot(locs, PIT_AIM_RADIUS)
				if spot ~= nil then
					local loc = Vector(spot.x, spot.y, allyTarget:GetLocation().z)
					local distance = GetUnitToLocationDistance(bot, loc)
					if
						X.GatePitWorth("fight", distance, count, hpRatio, #locs)
						and GateLocationOk(loc)
						and (best == nil or count > best.count)
					then
						best =
							{ why = "fight", loc = loc, ally = allyHero, count = count, dist = distance, hp = hpRatio }
					end
				end
			end
		end
	end
	if best == nil then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	fiendsGateWhy = "pit-" .. best.why
	fiendsGateTarget = (string.gsub(best.ally:GetUnitName(), "npc_dota_hero_", ""))
	if DotaTime() >= (bot._gatePitLogAt or -999) then
		bot._gatePitLogAt = DotaTime() + 5
		pcall(
			print,
			string.format(
				"[SHy-UNDERLORD] t=%.0f abyssal_underlord gate-pit why=%s ally=%s enemies=%d dist=%.0f hp=%.2f",
				DotaTime(),
				best.why,
				(string.gsub(best.ally:GetUnitName(), "npc_dota_hero_", "")),
				best.count,
				best.dist,
				best.hp
			)
		)
	end
	return BOT_ACTION_DESIRE_HIGH, best.loc
end

-- Self-test (#53): does Underlord himself get teleported by his own gate in 7.42, with no portal_warp ability?
-- The datafeed only says "Heroes can channel a portal ... to teleport"; the maintainer remembers Underlord being
-- moved automatically. The first gate cast of the game (any reason) is watched for GATE_SELF_WATCH seconds after
-- the gate goes on cooldown: a jump of GATE_SELF_JUMP+ between two thinks means he teleported. TPs are held while
-- it runs; a TP channel or a landing at our fountain (a respawn) voids the try. state: untested / watch / yes / no.
local function GateSelf()
	if bot._gateSelf == nil then
		bot._gateSelf = { state = "untested", retryAt = -999 }
	end
	return bot._gateSelf
end

local function ModifierNames()
	local names = {}
	pcall(function()
		for index = 0, bot:NumModifiers() - 1 do
			names[#names + 1] = tostring(bot:GetModifierName(index))
		end
	end)
	return #names > 0 and table.concat(names, ",") or "-"
end

-- The outcome of a watched order: "yes" (cast, then teleported), "no" (cast, no jump), "retry" (no cast, a jump
-- without a cast, or a void reason: a TP, a respawn).
function X.GateSelfResult(castSeen, maxJump, void)
	if void ~= nil or not castSeen then
		return "retry"
	end
	return maxJump >= GATE_SELF_JUMP and "yes" or "no"
end

-- Called after every gate order; starts the watch on the first one of the game.
function X.GateSelfStart(loc, why, target)
	local selfTest = GateSelf()
	if selfTest.state ~= "untested" then
		return
	end
	local from = bot:GetLocation()
	selfTest.state, selfTest.orderAt, selfTest.castAt, selfTest.at, selfTest.from = "watch", DotaTime(), nil, loc, from
	selfTest.lastLoc, selfTest.lastTime, selfTest.maxJump, selfTest.maxGap = from, DotaTime(), 0, 0
	selfTest.castSeen, selfTest.channel, selfTest.void = false, false, nil
	selfTest.why, selfTest.target = why, target
	pcall(
		print,
		string.format(
			"[SHy-UNDERLORD] t=%.0f abyssal_underlord gate-self cast why=%s at=%.0f,%.0f target=%s from=%.0f,%.0f dist=%.0f",
			DotaTime(),
			why,
			loc.x,
			loc.y,
			tostring(target),
			from.x,
			from.y,
			Dist2D(from, loc)
		)
	)
end

local function ChannelingTp()
	local ok, name = pcall(function()
		local active = bot:GetCurrentActiveAbility()
		return active ~= nil and active ~= 0 and active:GetName() or ""
	end)
	return ok
		and type(name) == "string"
		and (string.find(name, "tpscroll", 1, true) ~= nil or string.find(name, "travel_boots", 1, true) ~= nil)
end

function X.GateSelfWatch()
	local selfTest = bot._gateSelf
	if selfTest == nil or selfTest.state ~= "watch" then
		return
	end
	local now = DotaTime()
	local loc = bot:GetLocation()
	-- No TP while the test runs (the TP wrapper in ability_item_usage_generic.lua and ObjectiveTravel.Go read it).
	bot._noTpUntil = math.max(bot._noTpUntil or -999, now + 0.5)
	local jump = Dist2D(loc, selfTest.lastLoc)
	selfTest.maxJump = math.max(selfTest.maxJump, jump)
	selfTest.maxGap = math.max(selfTest.maxGap, now - selfTest.lastTime)
	selfTest.lastLoc, selfTest.lastTime = loc, now
	if
		jump >= GATE_SELF_JUMP
		and Dist2D(loc, Fu.GetTeamFountain()) < 2000
		and Dist2D(selfTest.at, Fu.GetTeamFountain()) > 3000
	then
		selfTest.void = "respawn"
	end
	if bot:IsChanneling() then
		if ChannelingTp() then
			selfTest.void = "tp"
		else
			selfTest.channel = true
		end
	end
	if not selfTest.castSeen and (fiendsGateAbility:GetCooldownTimeRemaining() or 0) > 0 then
		selfTest.castSeen, selfTest.castAt = true, now
	end
	local done
	if selfTest.void ~= nil then
		done = true
	elseif not selfTest.castSeen then
		-- The order did not turn into a cast yet; the trigger keeps ordering it. A jump without a cast is not the gate.
		done = now - selfTest.orderAt >= 3 or selfTest.maxJump >= GATE_SELF_JUMP
	else
		done = now - selfTest.castAt >= GATE_SELF_WATCH or selfTest.maxJump >= GATE_SELF_JUMP
	end
	if not done then
		return
	end
	local result = X.GateSelfResult(selfTest.castSeen, selfTest.maxJump, selfTest.void)
	pcall(
		print,
		string.format(
			"[SHy-UNDERLORD] t=%.0f abyssal_underlord gate-self result=%s moved=%.0f at=%.0f,%.0f nearTarget=%s channel=%s cast=%s after=%.1f gap=%.1f void=%s why=%s mods=%s",
			now,
			result,
			selfTest.maxJump,
			loc.x,
			loc.y,
			Dist2D(loc, selfTest.at) < 1200 and "yes" or "no",
			tostring(selfTest.channel),
			tostring(selfTest.castSeen),
			now - (selfTest.castAt or selfTest.orderAt),
			selfTest.maxGap,
			tostring(selfTest.void or "-"),
			tostring(selfTest.why),
			ModifierNames()
		)
	)
	if result == "retry" then
		selfTest.state, selfTest.retryAt = "untested", now + 30
	else
		selfTest.state = result
	end
end

-- A far place Underlord should be at fast: a defend call, a team fight, or an ally under attack, all
-- GATE_TRAVEL_DISTANCE+ away, while he is healthy and not in a fight himself. Returns the location, why, target.
function X.GateTravelSpot()
	if
		Fu.IsInLaningPhase()
		or Fu.IsRetreating(bot)
		or Fu.GetHP(bot) < 0.5
		or #RealEnemiesNear(bot:GetLocation(), 1200) > 0
		or (isGoingOnSomeone and Fu.IsValidHero(botTarget) and GetUnitToUnitDistance(bot, botTarget) < 1600)
	then
		return nil
	end
	local function Far(loc)
		return loc ~= nil and GetUnitToLocationDistance(bot, loc) >= GATE_TRAVEL_DISTANCE and GateLocationOk(loc)
	end
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
		if
			Fu.IsValidHero(allyHero)
			and allyHero ~= bot
			and not allyHero:IsIllusion()
			and allyHero:WasRecentlyDamagedByAnyHero(1.5)
			and #RealEnemiesNear(allyHero:GetLocation(), 900) > 0
			and Far(allyHero:GetLocation())
		then
			return allyHero:GetLocation(), "ally", (string.gsub(allyHero:GetUnitName(), "npc_dota_hero_", ""))
		end
	end
	local fightLocation = Fu.GetTeamFightLocation(bot)
	if Far(fightLocation) and #RealEnemiesNear(fightLocation, 1200) > 0 then
		return fightLocation, "fight", "teamfight"
	end
	if Fu.IsDefending(bot) then
		local mode = bot:GetActiveMode()
		local lane = (mode == BOT_MODE_DEFEND_TOWER_TOP and LANE_TOP)
			or (mode == BOT_MODE_DEFEND_TOWER_MID and LANE_MID)
			or LANE_BOT
		local defendLocation = GetLaneFrontLocation(GetTeam(), lane, 0)
		if Far(defendLocation) then
			return defendLocation, "defend", "lane" .. lane
		end
	end
	return nil
end

function X.ConsiderFiendsGate()
	if not fiendsGateAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- With Scepter: a remote Pit of Malice for an ally in trouble or a fight (no one has to walk through).
	local hasScepter = bot:HasScepter()
	if hasScepter then
		local pitDesire, pitLocation = X.ConsiderGatePit()
		if pitDesire > 0 then
			return pitDesire, pitLocation
		end
	end
	-- The self-test (once a game, until a cast is measured), and once it showed Underlord teleports with his own
	-- gate: a global trip like Nature's Prophet's Teleportation.
	local selfTest = GateSelf()
	local selfTeleports = selfTest.state == "yes"
	if
		selfTeleports
		or (selfTest.state == "untested" and DotaTime() >= selfTest.retryAt)
		or (selfTest.state == "watch" and not selfTest.castSeen)
	then
		local travelLocation, why, target = X.GateTravelSpot()
		if travelLocation ~= nil then
			fiendsGateWhy = (selfTeleports and "travel-" or "selftest-") .. why
			fiendsGateTarget = target
			if selfTeleports and DotaTime() >= (bot._gateTravelLogAt or -999) then
				bot._gateTravelLogAt = DotaTime() + 5
				pcall(
					print,
					string.format(
						"[SHy-UNDERLORD] t=%.0f abyssal_underlord gate-travel why=%s target=%s dist=%.0f",
						DotaTime(),
						why,
						tostring(target),
						GetUnitToLocationDistance(bot, travelLocation)
					)
				)
			end
			return BOT_ACTION_DESIRE_HIGH, travelLocation
		end
	end
	-- 7.42: heroes have no abyssal_underlord_portal_warp any more, so no bot ally can walk through the portals
	-- (#53). Open them to move someone only for a human ally, Underlord himself when the self-test showed he
	-- teleports, or if the ability comes back.
	local humans = Fu.NumHumanBotPlayersInTeam()
	local hasWarp = bot:GetAbilityByName("abyssal_underlord_portal_warp") ~= nil
	if not ObjectiveTravel.PortalWalkable(hasWarp or selfTeleports, humans) then
		if not Fu.IsInLaningPhase() and DotaTime() >= (bot._fiendsGateOffLogAt or -999) then
			bot._fiendsGateOffLogAt = DotaTime() + 60
			pcall(
				print,
				string.format(
					"[SHy-TRAVEL] t=%.0f abyssal_underlord fiends-gate-off why=no-warp humans=%d scepter=%s self=%s",
					DotaTime(),
					humans,
					tostring(hasScepter),
					selfTest.state
				)
			)
		end
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local teamFightLocation = Fu.GetTeamFightLocation(bot)
	if
		teamFightLocation ~= nil
		and GetUnitToLocationDistance(bot, teamFightLocation) > 2500
		and not isGoingOnSomeone
		and not Fu.IsRetreating(bot)
		and not Fu.IsInLaningPhase()
	then
		local alliesNearFight = Fu.GetAlliesNearLoc(teamFightLocation, 1200)
		local enemiesNearFight = Fu.GetEnemiesNearLoc(teamFightLocation, 1200)
		if
			alliesNearFight ~= nil
			and enemiesNearFight ~= nil
			and #alliesNearFight + 1 >= #enemiesNearFight
			and #enemiesNearFight >= 1
		then
			local portalLocation = Fu.GetCenterOfUnits(alliesNearFight)
			if
				IsLocationPassable(portalLocation)
				and not Fu.IsLocationInChrono(portalLocation)
				and not Fu.IsLocationInBlackHole(portalLocation)
				and not Fu.IsLocationInArena(portalLocation, 600)
			then
				bot:SetTarget(enemiesNearFight[1])
				return BOT_ACTION_DESIRE_HIGH, portalLocation
			end
		end
	end
	if isGoingOnSomeone then
		if
			Fu.IsValidTarget(botTarget)
			and GetUnitToUnitDistance(bot, botTarget) > 2500
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not Fu.IsInLaningPhase()
		then
			local alliesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			local enemiesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			local nearbyAllies = Fu.GetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)
			local nearbyEnemyTowers = bot:GetNearbyTowers(700, true)
			if
				alliesNearTarget ~= nil
				and enemiesNearTarget ~= nil
				and nearbyAllies ~= nil
				and nearbyEnemyTowers ~= nil
				and #alliesNearTarget >= #enemiesNearTarget
				and #nearbyAllies == 0
				and #nearbyEnemyTowers == 0
			then
				local portalLocation = Fu.GetCenterOfUnits(alliesNearTarget)
				if
					IsLocationPassable(portalLocation)
					and not Fu.IsLocationInChrono(portalLocation)
					and not Fu.IsLocationInBlackHole(portalLocation)
					and not Fu.IsLocationInArena(portalLocation, 600)
				then
					bot:SetTarget(botTarget)
					return BOT_ACTION_DESIRE_HIGH, portalLocation
				end
			end
		end
	end
	local laneDistanceSum = { 0, 0, 0 }
	local lanePusherCount = { 0, 0, 0 }
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
		if
			Fu.IsValidHero(allyHero)
			and Fu.IsGoingOnSomeone(allyHero)
			and GetUnitToUnitDistance(bot, allyHero) > 2500
			and not allyHero:IsIllusion()
			and not Fu.IsInLaningPhase()
		then
			local allyTarget = allyHero:GetAttackTarget()
			local alliesNearAlly = Fu.GetNearbyHeroes(allyHero, 800, false, BOT_MODE_NONE)
			if
				Fu.IsValidTarget(allyTarget)
				and Fu.IsInRange(allyHero, allyTarget, 800)
				and Fu.GetHP(allyHero) > 0.5
				and not Fu.IsSuspiciousIllusion(allyTarget)
			then
				local enemiesNearAllyTarget = Fu.GetNearbyHeroes(allyTarget, 800, false, BOT_MODE_NONE)
				local nearbyAllies = Fu.GetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE)
				local nearbyEnemyTowers = bot:GetNearbyTowers(700, true)
				if
					alliesNearAlly ~= nil
					and enemiesNearAllyTarget ~= nil
					and #alliesNearAlly + 1 >= #enemiesNearAllyTarget
					and #enemiesNearAllyTarget >= 1
					and nearbyAllies ~= nil
					and nearbyEnemyTowers ~= nil
					and #nearbyAllies == 0
					and #nearbyEnemyTowers == 0
				then
					-- GetCenterOfUnits takes a unit list; given a Vector it gave Vector(0,0) (map centre)
					-- or errored. Open the portal at the ally's predicted spot instead.
					local portalLocation = allyHero:GetExtrapolatedLocation(1)
					if
						IsLocationPassable(portalLocation)
						and not Fu.IsLocationInChrono(portalLocation)
						and not Fu.IsLocationInBlackHole(portalLocation)
						and not Fu.IsLocationInArena(portalLocation, 600)
					then
						bot:SetTarget(allyTarget)
						return BOT_ACTION_DESIRE_HIGH, portalLocation
					end
				end
			end
		end
		if
			Fu.IsValidHero(allyHero)
			and bot ~= allyHero
			and not Fu.IsSuspiciousIllusion(allyHero)
			and not Fu.IsMeepoClone(allyHero)
		then
			if
				allyHero:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP
				and bot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP
			then
				lanePusherCount[1] = lanePusherCount[1] + 1
				laneDistanceSum[1] = laneDistanceSum[1]
					+ GetUnitToLocationDistance(allyHero, GetLaneFrontLocation(GetTeam(), LANE_TOP, 0))
			end
			if
				allyHero:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID
				and bot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID
			then
				lanePusherCount[2] = lanePusherCount[2] + 1
				laneDistanceSum[2] = laneDistanceSum[2]
					+ GetUnitToLocationDistance(allyHero, GetLaneFrontLocation(GetTeam(), LANE_MID, 0))
			end
			if
				allyHero:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT
				and bot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT
			then
				lanePusherCount[3] = lanePusherCount[3] + 1
				laneDistanceSum[3] = laneDistanceSum[3]
					+ GetUnitToLocationDistance(allyHero, GetLaneFrontLocation(GetTeam(), LANE_BOT, 0))
			end
		end
	end
	if lanePusherCount[1] ~= nil and lanePusherCount[1] >= 3 and laneDistanceSum[1] / lanePusherCount[1] <= 1200 then
		if GetUnitToLocationDistance(bot, GetLaneFrontLocation(GetTeam(), LANE_TOP, 0)) > 4000 then
			return BOT_ACTION_DESIRE_HIGH, GetLaneFrontLocation(GetTeam(), LANE_TOP, 0)
		end
	elseif
		lanePusherCount[2] ~= nil
		and lanePusherCount[2] >= 3
		and laneDistanceSum[2] / lanePusherCount[2] <= 1200
	then
		if GetUnitToLocationDistance(bot, GetLaneFrontLocation(GetTeam(), LANE_MID, 0)) > 4000 then
			return BOT_ACTION_DESIRE_HIGH, GetLaneFrontLocation(GetTeam(), LANE_MID, 0)
		end
	elseif
		lanePusherCount[3] ~= nil
		and lanePusherCount[3] >= 3
		and laneDistanceSum[3] / lanePusherCount[3] <= 1200
	then
		if GetUnitToLocationDistance(bot, GetLaneFrontLocation(GetTeam(), LANE_BOT, 0)) > 4000 then
			return BOT_ACTION_DESIRE_HIGH, GetLaneFrontLocation(GetTeam(), LANE_BOT, 0)
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
return X
