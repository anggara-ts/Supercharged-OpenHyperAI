-- Phoenix: skill build, item build, and ability use for this hero.
-- Accidental globals made file-local (#13): every bot shares one Lua state, so these were shared.
local AllyCast
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local CastRules = require(GetScriptDirectory() .. "/lib/systems/hero_cast_rules")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 0, 10 }, ["t20"] = { 0, 10 }, ["t15"] = { 10, 0 }, ["t10"] = { 0, 10 } }
local tAllAbilityBuildList = { { 2, 1, 2, 3, 2, 6, 2, 3, 3, 3, 6, 1, 1, 1, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 35,254 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_branches",
	"item_magic_stick",
	"item_circlet",
	"item_magic_wand",
	"item_urn_of_shadows",
	"item_tranquil_boots",
	"item_spirit_vessel",
	"item_aghanims_shard",
	"item_shivas_guard",
	"item_ultimate_scepter",
	"item_sheepstick",
	"item_lotus_orb",
	"item_ultimate_scepter_2",
	-- Rod of Atos instead of Veil of Discord: roots the Sun Ray target so it cannot walk out.
	"item_rod_of_atos",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 20,322 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_branches",
	"item_magic_stick",
	"item_circlet",
	"item_magic_wand",
	"item_tranquil_boots",
	"item_spirit_vessel",
	"item_aghanims_shard",
	"item_shivas_guard",
	"item_ultimate_scepter",
	"item_sheepstick",
	"item_aeon_disk",
	"item_ultimate_scepter_2",
	"item_meteor_hammer",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 20,134 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_circlet",
	"item_faerie_fire",
	"item_gauntlets",
	"item_bracer",
	"item_magic_wand",
	"item_urn_of_shadows",
	"item_tranquil_boots",
	"item_spirit_vessel",
	"item_shivas_guard",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_refresher",
	"item_ultimate_scepter_2",
	"item_veil_of_discord",
	"item_meteor_hammer",
	"item_bloodstone",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1 has 239 matches, built from pos 3 (21,347) (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_double_branches",
	"item_circlet",
	"item_gauntlets",
	"item_faerie_fire",
	"item_bracer",
	"item_magic_wand",
	"item_urn_of_shadows",
	"item_tranquil_boots",
	"item_spirit_vessel",
	"item_shivas_guard",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_refresher",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_veil_of_discord",
	"item_sheepstick",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 21,347 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_double_branches",
	"item_circlet",
	"item_gauntlets",
	"item_faerie_fire",
	"item_bracer",
	"item_magic_wand",
	"item_urn_of_shadows",
	"item_tranquil_boots",
	"item_spirit_vessel",
	"item_shivas_guard",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_refresher",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_veil_of_discord",
	"item_sheepstick",
	"item_moon_shard",
	"item_travel_boots_2",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_heart", "item_magic_wand" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_antimage" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDeafaultAbility"] = false
-- Cast when cornered (retreating into 3+ enemies with no way out), before running further.
X["LastStandSpells"] = { { name = "phoenix_supernova", kind = "none" } }
X["bDeafaultItem"] = false
function X.MinionThink(hMinionUnit)
	Minion.MinionThink(hMinionUnit)
end
local icarusDiveAbility = SafeAbility(bot:GetAbilityByName("phoenix_icarus_dive"), "phoenix_icarus_dive", "phoenix")
local icarusDiveStopAbility =
	SafeAbility(bot:GetAbilityByName("phoenix_icarus_dive_stop"), "phoenix_icarus_dive_stop", "phoenix")
local fireSpiritsAbility = SafeAbility(bot:GetAbilityByName("phoenix_fire_spirits"), "phoenix_fire_spirits", "phoenix")
local launchFireSpiritAbility =
	SafeAbility(bot:GetAbilityByName("phoenix_launch_fire_spirit"), "phoenix_launch_fire_spirit", "phoenix")
local sunRayAbility = SafeAbility(bot:GetAbilityByName("phoenix_sun_ray"), "phoenix_sun_ray", "phoenix")
local sunRayStopAbility = SafeAbility(bot:GetAbilityByName("phoenix_sun_ray_stop"), "phoenix_sun_ray_stop", "phoenix")
local sunRayToggleMoveAbility =
	SafeAbility(bot:GetAbilityByName("phoenix_sun_ray_toggle_move"), "phoenix_sun_ray_toggle_move", "phoenix")
local supernovaAbility = SafeAbility(bot:GetAbilityByName("phoenix_supernova"), "phoenix_supernova", "phoenix")
local icarusDiveDesire, icarusDiveLocation
local icarusDiveStopDesire
local fireSpiritsDesire
local launchFireSpiritDesire, launchFireSpiritLocation
local sunRayDesire, sunRayLocation
local sunRayStopDesire
local toggleMovementDesire, toggleMovementState
local supernovaDesire, supernovaTarget
-- The dive ordered last (#47): why, where from, its target, and what happened, for the Stop rule and one
-- [SHy-PHOENIX] dive-result line. Kept from the order to the result, so nothing in between can lose the reason.
local DIVE_MODIFIER = "modifier_phoenix_icarus_dive"
local diveRecord = nil
local diveNotStartedLogAt = -999
local hasDiveStop = icarusDiveStopAbility:GetName() == "phoenix_icarus_dive_stop"
local lastLaunchTime = 0
if bot.sun_ray_target == nil then
	bot.sun_ray_target = bot
end
local botTarget
local isGoingOnSomeone
local isAttacking
local hpRatio
function X.SkillsComplement()
	X.DiveTick()
	local context = AbilityContext.Build(bot)
	isGoingOnSomeone = context.isEngaging
	isAttacking = Fu.IsAttacking(bot)
	hpRatio = context.hp
	-- Sun Ray / dive stop + ray move must run while channeling.
	-- CanNotUseAbility() is true during channels, which previously blocked stop forever
	-- (Phoenix stood still on low HP until the ray finished).
	sunRayStopDesire = X.ConsiderSunRayStop()
	if sunRayStopDesire > 0 then
		bot:Action_UseAbility(sunRayStopAbility)
		bot.sun_ray_engage = false
		bot.sun_ray_heal_ally = false
		return
	end
	toggleMovementDesire, toggleMovementState = X.ConsiderToggleMovement()
	if toggleMovementDesire > 0 then
		if toggleMovementState == "on" then
			if not sunRayToggleMoveAbility:GetToggleState() then
				bot:Action_UseAbility(sunRayToggleMoveAbility)
			end
		else
			if sunRayToggleMoveAbility:GetToggleState() then
				bot:Action_UseAbility(sunRayToggleMoveAbility)
			end
		end
		return
	end
	-- Root the Sun Ray target with Rod of Atos so it cannot walk out of the beam. Runs here
	-- because the busy check below is true during the ray and blocks the shared item logic.
	local atos, atosTarget = X.ConsiderAtosOnSunRay()
	if atos ~= nil then
		bot:Action_UseAbilityOnEntity(atos, atosTarget)
		return
	end
	-- Fire Spirits work during Sun Ray too, but the busy check below blocked them for the
	-- whole beam. During the ray, only against enemy heroes and with HP to spare (the cast
	-- costs a share of HP on top of the ray's own cost).
	if bot:HasModifier("modifier_phoenix_sun_ray") and (hpRatio or Fu.GetHP(bot)) > 0.35 then
		local spiritRange = Fu.GetProperCastRange(false, bot, fireSpiritsAbility:GetCastRange())
		local foes = bot:GetNearbyHeroes(math.min(spiritRange, 1600), true, BOT_MODE_NONE) or {}
		if #foes > 0 then
			if X.ConsiderFireSpirits() > 0 then
				X.LogSunRaySpirits("summon", foes[1])
				bot:Action_UseAbility(fireSpiritsAbility)
				return
			end
			local launch, loc = X.ConsiderFireSpiritsLaunch()
			if launch > 0 and loc ~= nil then
				local hit = Fu.GetEnemiesNearLoc(loc, fireSpiritsAbility:GetSpecialValueInt("radius") + 150)
				if hit ~= nil and #hit >= 1 then
					X.LogSunRaySpirits("launch", hit[1])
					bot:Action_UseAbilityOnLocation(launchFireSpiritAbility, loc)
					lastLaunchTime = DotaTime()
					return
				end
			end
		end
	end
	icarusDiveStopDesire = X.ConsiderIcarusDiveStop()
	if icarusDiveStopDesire > 0 then
		bot:Action_UseAbility(icarusDiveStopAbility)
		return
	end
	if Fu.CanNotUseAbility(bot) then
		return
	end
	fireSpiritsDesire = X.ConsiderFireSpirits()
	if fireSpiritsDesire > 0 then
		bot:Action_UseAbility(fireSpiritsAbility)
		return
	end
	launchFireSpiritDesire, launchFireSpiritLocation = X.ConsiderFireSpiritsLaunch()
	if launchFireSpiritDesire > 0 then
		bot:Action_UseAbilityOnLocation(launchFireSpiritAbility, launchFireSpiritLocation)
		lastLaunchTime = DotaTime()
		return
	end
	supernovaDesire, supernovaTarget, AllyCast = X.ConsiderSupernova()
	if supernovaDesire > 0 then
		if string.find(GetBot():GetUnitName(), "phoenix") and bot:HasScepter() and AllyCast then
			bot:Action_UseAbilityOnEntity(supernovaAbility, supernovaTarget)
			return
		else
			if Fu.CanCastAbility(fireSpiritsAbility) then
				bot:ActionQueue_UseAbility(fireSpiritsAbility)
				local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
				for _, enemy in pairs(nearbyEnemies) do
					if
						Fu.IsValidHero(enemy)
						and Fu.IsInRange(bot, enemy, fireSpiritsAbility:GetCastRange())
						and Fu.CanCastOnNonMagicImmune(enemy)
						and not Fu.IsEnemyChronosphereInLocation(enemy:GetLocation())
						and not Fu.IsEnemyBlackHoleInLocation(enemy:GetLocation())
						and not enemy:HasModifier("modifier_necrolyte_reapers_scythe")
						and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
					then
						bot:ActionQueue_UseAbilityOnLocation(launchFireSpiritAbility, enemy:GetLocation())
					end
				end
				bot:ActionQueue_UseAbility(supernovaAbility)
				return
			else
				bot:Action_UseAbility(supernovaAbility)
				return
			end
		end
	end
	local diveWhy, diveTarget
	icarusDiveDesire, icarusDiveLocation, diveWhy, diveTarget = X.ConsiderIcarusDive()
	if icarusDiveDesire > 0 then
		bot:Action_UseAbilityOnLocation(icarusDiveAbility, icarusDiveLocation)
		X.DiveOrdered(icarusDiveLocation, diveWhy, diveTarget)
		return
	end
	sunRayDesire, sunRayLocation = X.ConsiderSunRay()
	if sunRayDesire > 0 then
		bot:Action_UseAbilityOnLocation(sunRayAbility, sunRayLocation)
		return
	end
end
function X.ConsiderIcarusDive()
	if
		not Fu.CanCastAbility(icarusDiveAbility)
		or bot:IsRooted()
		or bot:HasModifier(DIVE_MODIFIER)
		or bot:HasModifier("modifier_phoenix_supernova_hiding")
		or bot:HasModifier("modifier_bloodseeker_rupture")
	then
		return BOT_ACTION_DESIRE_NONE
	end
	local dashLength = icarusDiveAbility:GetSpecialValueInt("dash_length")
	local dashWidth = icarusDiveAbility:GetSpecialValueInt("dash_width")
	local hpCost = icarusDiveAbility:GetSpecialValueInt("hp_cost_perc") / 100 * bot:GetHealth()
	local damage = icarusDiveAbility:GetSpecialValueInt("damage_per_second")
		* icarusDiveAbility:GetSpecialValueFloat("burn_duration")
	local hpAfterCast = (bot:GetHealth() - hpCost) / bot:GetMaxHealth()
	botTarget = Fu.GetProperTarget(bot)
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, enemy in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemy)
			and Fu.IsInRange(bot, enemy, dashLength)
			and Fu.CanCastOnNonMagicImmune(enemy)
			and Fu.CanKillTarget(enemy, damage, DAMAGE_TYPE_MAGICAL)
			and not enemy:HasModifier("modifier_abaddon_borrowed_time")
			and not enemy:HasModifier("modifier_dazzle_shallow_grave")
			and not enemy:HasModifier("modifier_necrolyte_reapers_scythe")
			and not enemy:HasModifier("modifier_oracle_false_promise_timer")
			and not Fu.IsEnemyChronosphereInLocation(enemy:GetLocation())
			and not Fu.IsEnemyBlackHoleInLocation(enemy:GetLocation())
			and hpAfterCast > 0.4
		then
			return BOT_ACTION_DESIRE_HIGH, enemy:GetLocation(), "kill", enemy
		end
	end
	if Fu.IsStuck(bot) then
		return BOT_ACTION_DESIRE_HIGH, Fu.Site.GetXUnitsTowardsLocation(bot, Fu.GetTeamFountain(), dashLength), "stuck"
	end
	if Fu.IsInTeamFight(bot, 1200) then
		local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), dashLength, dashWidth / 1.5, 0, 0)
		if
			aoe.count >= 2
			and not Fu.IsEnemyChronosphereInLocation(aoe.targetloc)
			and not Fu.IsEnemyBlackHoleInLocation(aoe.targetloc)
			and hpAfterCast > 0.3
		then
			return BOT_ACTION_DESIRE_HIGH, aoe.targetloc, "engage"
		end
	end
	if isGoingOnSomeone then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, dashLength)
			and not Fu.IsEnemyChronosphereInLocation(botTarget:GetLocation())
			and not Fu.IsEnemyBlackHoleInLocation(botTarget:GetLocation())
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			and hpAfterCast > 0.3
		then
			if #nearbyAllies >= #nearbyEnemies + 1 then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation(), "engage", botTarget
			end
		end
	end
	if Fu.IsRetreating(bot) and bot:GetActiveModeDesire() > 0.75 and not Fu.IsSuspiciousIllusion(bot) then
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and not Fu.IsSuspiciousIllusion(enemy)
				and bot:WasRecentlyDamagedByHero(enemy, 3.0)
				and hpAfterCast > 0.15
			then
				return BOT_ACTION_DESIRE_HIGH,
					Fu.Site.GetXUnitsTowardsLocation(bot, Fu.GetTeamFountain(), dashLength),
					"retreat"
			end
		end
		if hpRatio < 0.5 and bot:WasRecentlyDamagedByTower(2.5) and hpAfterCast > 0.2 then
			return BOT_ACTION_DESIRE_HIGH,
				Fu.Site.GetXUnitsTowardsLocation(bot, Fu.GetTeamFountain(), dashLength),
				"retreat"
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
-- #47: Icarus Dive and its Stop. Game 085: 36 dive orders, no Stop at all, and two of the three retreat dives
-- ended where they began, among the enemies, and Phoenix died there within 3s. Game data (datafeed hero 110):
-- dive_duration 2, hit_radius 200, dash_width 500, dash_length 1100/1200/1300/1400, AbilityCastPoint 0.2,
-- cooldown 40/35/30/25. Stop now follows the dive itself (when it started, where Phoenix is against where she
-- started and against the target), not the time of the order, and every order ends in one dive-result line that
-- says whether the dive started, whether Stop could be cast, and where Phoenix ended.
local function diveDeaths()
	local ok, deaths = pcall(GetHeroDeaths, bot:GetPlayerID())
	return ok and deaths or nil
end
-- Phoenix is in the dive: the dive modifier, or the Stop ability shown (it is hidden outside the dive; the API
-- dump lists phoenix_icarus_dive_stop(h)). Either one is enough, so a wrong modifier name cannot hide the dive.
function X.InDive()
	if bot:HasModifier(DIVE_MODIFIER) then
		return true
	end
	return hasDiveStop and not icarusDiveStopAbility:IsNull() and not icarusDiveStopAbility:IsHidden()
end
function X.DiveOrdered(location, why, target)
	if diveRecord ~= nil then
		X.FinishDive("reordered")
	end
	local hitRadius = icarusDiveAbility:GetSpecialValueInt("hit_radius")
	local dashWidth = icarusDiveAbility:GetSpecialValueInt("dash_width")
	local duration = icarusDiveAbility:GetSpecialValueFloat("dive_duration")
	diveRecord = {
		why = why or "none",
		orderAt = DotaTime(),
		from = bot:GetLocation(),
		aim = location,
		target = target,
		dashLength = icarusDiveAbility:GetSpecialValueInt("dash_length"),
		-- datafeed hero 110: hit_radius 200, dash_width 500, dive_duration 2 (fallbacks when the API reads 0)
		hitRadius = hitRadius > 0 and hitRadius or 200,
		dashWidth = dashWidth > 0 and dashWidth or 500,
		duration = duration > 0 and duration or 2,
		hpStart = Fu.GetHP(bot),
		deathsStart = diveDeaths(),
		thinks = 0,
		fromStartMax = 0,
		lastTickAt = DotaTime(),
	}
	pcall(
		print,
		string.format(
			"[SHy-PHOENIX] t=%.0f phoenix dive why=%s dist=%.0f target=%s hp=%.2f",
			DotaTime(),
			diveRecord.why,
			GetUnitToLocationDistance(bot, location),
			Fu.IsValidHero(target) and string.gsub(target:GetUnitName(), "npc_dota_hero_", "") or "-",
			diveRecord.hpStart
		)
	)
end
-- Where the dive is going: the target hero while it can be seen, else the spot it was cast at.
local function diveTargetLocation(rec)
	if Fu.IsValidHero(rec.target) and rec.target:CanBeSeen() then
		return rec.target:GetLocation()
	end
	return rec.aim
end
local function hasDiveTarget(rec)
	return rec.why == "kill" or rec.why == "engage"
end
-- Every think from the order on (top of SkillsComplement, before any early return).
function X.DiveTick()
	local rec = diveRecord
	if rec == nil then
		return
	end
	local now = DotaTime()
	-- A long gap: Phoenix died, or the think did not run. Close the record with what is known.
	if now - rec.lastTickAt > 2.5 then
		X.FinishDive("gap")
		return
	end
	rec.lastTickAt = now
	-- Past the whole dive and a margin: close it even if the in-dive check still says yes (Stop never hidden).
	if rec.startedAt ~= nil and now - rec.startedAt > rec.duration + 1.5 then
		X.FinishDive(rec.inDiveSeen and "overrun" or "never-seen")
		return
	end
	local inDive = X.InDive()
	local hasModifier = bot:HasModifier(DIVE_MODIFIER)
	if rec.startedAt == nil and (inDive or icarusDiveAbility:GetCooldownTimeRemaining() > 0) then
		rec.startedAt = now
		rec.startHow = hasModifier and "modifier" or inDive and "stop-shown" or "cooldown"
	end
	if hasModifier then
		rec.modifierSeen = true
	end
	if inDive then
		rec.inDiveSeen = true
		rec.thinks = rec.thinks + 1
		if rec.stopCastableAt == nil and Fu.CanCastAbility(icarusDiveStopAbility) then
			rec.stopCastableAt = now
		end
		local fromStart = GetUnitToLocationDistance(bot, rec.from)
		rec.fromStart = fromStart
		rec.fromStartMax = math.max(rec.fromStartMax, fromStart)
		if hasDiveTarget(rec) and rec.aim ~= nil then
			local targetDist = GetUnitToLocationDistance(bot, diveTargetLocation(rec))
			rec.targetDist = targetDist
			rec.targetDistMin = math.min(rec.targetDistMin or targetDist, targetDist)
		end
		return
	end
	if rec.inDiveSeen then
		X.FinishDive("ended")
	elseif rec.startedAt == nil and now - rec.orderAt > 1.5 then
		-- Turn and cast point (0.2s) are over and the dive is not on cooldown: the order never became a cast.
		X.FinishDive("not-started")
	end
end
-- [SHy-PHOENIX] dive-result: one line per dive order.
--   started=yes|no (the dive went on cooldown or Phoenix was seen in it), how= (what showed it first)
--   ended= ended (the dive finished) | not-started | never-seen (on cooldown, never seen in the dive: the in-dive
--   check is wrong) | overrun (still "in the dive" 1.5s after it should end) | gap (died, or no think for 2.5s) |
--   reordered
--   stop= yes (the dive ended within 0.8s of the first Stop order, before its natural end) | no-end (ordered,
--         the dive went on) | blocked (the rule wanted it, Stop could not be cast) | none (the rule never asked)
--   rule= why Stop was ordered, orders= Stop orders sent (1-3), stopAt= (first order) / endAt= seconds after the
--   start, stopCastable= seconds after the start Stop first read castable (- = never), thinks= thinks inside the
--   dive, away= distance from the start at the end, peak= farthest from the start, targetMin= closest to the target,
--   hp= before -> after, died=yes|no
function X.FinishDive(ended)
	local rec = diveRecord
	diveRecord = nil
	if rec == nil then
		return
	end
	local now = DotaTime()
	local started = rec.startedAt ~= nil
	if not started then
		-- Orders that never cast can repeat; print at most one every 3s.
		if now < diveNotStartedLogAt then
			return
		end
		diveNotStartedLogAt = now + 3
	end
	local startAt = rec.startedAt or rec.orderAt
	local stop = "none"
	if rec.stopFirstAt ~= nil then
		-- yes: the dive ended within 0.8s of the first Stop order (room for the two repeats) and clearly before it
		-- would have ended by itself. A dive that only ended at its natural end after ignored Stops is no-end.
		local endedByStop = ended == "ended" and now - rec.stopFirstAt <= 0.8 and now - startAt < rec.duration - 0.2
		stop = endedByStop and "yes" or "no-end"
	elseif rec.stopBlocked then
		stop = "blocked"
	end
	local deathsNow = diveDeaths()
	local died = rec.deathsStart ~= nil and deathsNow ~= nil and deathsNow > rec.deathsStart
	pcall(
		print,
		string.format(
			"[SHy-PHOENIX] t=%.0f phoenix dive-result why=%s started=%s how=%s ended=%s stop=%s rule=%s orders=%d stopAt=%s endAt=%.1f stopCastable=%s modifier=%s thinks=%d away=%.0f peak=%.0f targetMin=%s hp=%.2f->%.2f died=%s",
			now,
			rec.why,
			started and "yes" or "no",
			rec.startHow or "-",
			ended,
			stop,
			rec.stopRule or "-",
			rec.stopOrders or 0,
			rec.stopFirstAt and string.format("%.1f", rec.stopFirstAt - startAt) or "-",
			now - startAt,
			rec.stopCastableAt and string.format("%.1f", rec.stopCastableAt - startAt) or "-",
			rec.modifierSeen and "yes" or "no",
			rec.thinks,
			(bot:IsAlive() and not died) and GetUnitToLocationDistance(bot, rec.from) or -1,
			rec.fromStartMax,
			rec.targetDistMin and string.format("%.0f", rec.targetDistMin) or "-",
			rec.hpStart,
			(bot:IsAlive() and not died) and Fu.GetHP(bot) or 0,
			died and "yes" or "no"
		)
	)
end
-- Stop exists only DURING the dive: the old guard returned when Phoenix had the dive modifier, so Stop never
-- fired, and the later timing (2s after the order for kill / engage, the whole dive) could never be reached.
function X.ConsiderIcarusDiveStop()
	local rec = diveRecord
	if rec == nil or not X.InDive() or bot:HasModifier("modifier_phoenix_supernova_hiding") then
		return BOT_ACTION_DESIRE_NONE
	end
	local now = DotaTime()
	-- One order, then up to two repeats 0.3s apart if the dive goes on.
	if rec.stopOrderedAt ~= nil and (now - rec.stopOrderedAt < 0.3 or (rec.stopOrders or 0) >= 3) then
		return BOT_ACTION_DESIRE_NONE
	end
	local stop, rule = CastRules.IcarusDiveStop({
		kind = rec.why,
		elapsed = now - (rec.startedAt or now),
		duration = rec.duration,
		fromStart = rec.fromStart or 0,
		fromStartMax = rec.fromStartMax,
		dashLength = rec.dashLength,
		targetDist = rec.targetDist,
		targetDistMin = rec.targetDistMin,
		hitRadius = rec.hitRadius,
		dashWidth = rec.dashWidth,
	})
	if not stop then
		return BOT_ACTION_DESIRE_NONE
	end
	local castable = Fu.CanCastAbility(icarusDiveStopAbility)
	if not castable then
		if not rec.stopBlocked then
			rec.stopBlocked = true
			local stopAbility = icarusDiveStopAbility
			pcall(
				print,
				string.format(
					"[SHy-PHOENIX] t=%.0f phoenix dive-stop-blocked why=%s rule=%s handle=%s hidden=%s trained=%s castable=%s activated=%s level=%s",
					now,
					rec.why,
					rule,
					tostring(hasDiveStop),
					tostring(stopAbility:IsHidden()),
					tostring(stopAbility:IsTrained()),
					tostring(stopAbility:IsFullyCastable()),
					tostring(stopAbility:IsActivated()),
					tostring(stopAbility:GetLevel())
				)
			)
		end
		-- Shown but not castable by our check (e.g. it reads untrained): order it anyway, the result line
		-- says whether the dive ended. Hidden or missing: nothing to order.
		if not hasDiveStop or icarusDiveStopAbility:IsHidden() then
			return BOT_ACTION_DESIRE_NONE
		end
	end
	rec.stopOrders = (rec.stopOrders or 0) + 1
	if rec.stopOrderedAt == nil then
		rec.stopRule = rule
		rec.stopFirstAt = now
		pcall(
			print,
			string.format(
				"[SHy-PHOENIX] t=%.0f phoenix dive-stop why=%s rule=%s since=%.1f away=%.0f targetDist=%s via=%s hp=%.2f",
				now,
				rec.why,
				rule,
				now - (rec.startedAt or now),
				rec.fromStart or 0,
				rec.targetDist and string.format("%.0f", rec.targetDist) or "-",
				castable and "castable" or "forced",
				Fu.GetHP(bot)
			)
		)
	end
	rec.stopOrderedAt = now
	return BOT_ACTION_DESIRE_HIGH
end
function X.ConsiderFireSpirits()
	if
		not Fu.CanCastAbility(fireSpiritsAbility)
		or bot:HasModifier("modifier_phoenix_icarus_dive")
		or bot:HasModifier("modifier_phoenix_supernova_hiding")
		or bot:HasModifier("modifier_phoenix_fire_spirit_count")
	then
		return BOT_ACTION_DESIRE_NONE
	end
	local castRange = Fu.GetProperCastRange(false, bot, fireSpiritsAbility:GetCastRange())
	local radius = fireSpiritsAbility:GetSpecialValueInt("radius")
	local hpCost = fireSpiritsAbility:GetSpecialValueInt("hp_cost_perc") / 100 * bot:GetHealth()
	local damage = fireSpiritsAbility:GetSpecialValueInt("damage_per_second")
		* fireSpiritsAbility:GetSpecialValueFloat("duration")
	local spiritSpeed = fireSpiritsAbility:GetSpecialValueInt("spirit_speed")
	local hpAfterCast = (bot:GetHealth() - hpCost) / bot:GetMaxHealth()
	botTarget = Fu.GetProperTarget(bot)
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, enemy in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemy)
			and Fu.IsInRange(bot, enemy, castRange)
			and Fu.CanCastOnNonMagicImmune(enemy)
			and Fu.CanKillTarget(enemy, damage, DAMAGE_TYPE_MAGICAL)
			and not enemy:HasModifier("modifier_abaddon_borrowed_time")
			and not enemy:HasModifier("modifier_dazzle_shallow_grave")
			and not enemy:HasModifier("modifier_oracle_false_promise_timer")
			and not enemy:HasModifier("modifier_templar_assassin_refraction_absorb")
			and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
			and hpAfterCast > 0.25
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if isGoingOnSomeone then
		local strongestEnemy = nil
		local maxDps = 0
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.IsInRange(bot, enemy, castRange)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and not Fu.IsEnemyChronosphereInLocation(enemy:GetLocation())
				and not Fu.IsEnemyBlackHoleInLocation(enemy:GetLocation())
				and not enemy:HasModifier("modifier_necrolyte_reapers_scythe")
				and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
			then
				local dps = enemy:GetAttackDamage() * enemy:GetAttackSpeed()
				if dps > maxDps then
					strongestEnemy = enemy
					maxDps = dps
				end
			end
		end
		if strongestEnemy ~= nil then
			if Fu.IsInLaningPhase() then
				for _, ally in pairs(nearbyAllies) do
					if
						Fu.IsValidHero(ally)
						and not ally:IsIllusion()
						and (
							Fu.IsAttacking(strongestEnemy) == ally
							or Fu.IsChasingTarget(strongestEnemy, ally)
							or strongestEnemy:GetAttackTarget() == ally
						)
					then
						return BOT_ACTION_DESIRE_HIGH
					end
				end
			else
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	-- Laning: harass a farming enemy core (last-hits / near wave), not only when they hit an ally.
	if Fu.IsInLaningPhase() and hpAfterCast > 0.4 and Fu.GetMP(bot) > 0.2 and not Fu.IsRetreating(bot) then
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.IsCore(enemy)
				and not Fu.IsSuspiciousIllusion(enemy)
				and Fu.IsInRange(bot, enemy, castRange)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
				and not enemy:HasModifier("modifier_necrolyte_reapers_scythe")
			then
				local atk = enemy:GetAttackTarget()
				local farming = atk ~= nil
					and not atk:IsNull()
					and atk:IsAlive()
					and not atk:IsHero()
					and atk:GetTeam() ~= enemy:GetTeam()
				local nearWave = #enemy:GetNearbyLaneCreeps(500, true) >= 1
				if farming or nearWave then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	end
	local laneCreeps = bot:GetNearbyLaneCreeps(math.min(castRange, 1600), true)
	if (Fu.IsPushing(bot) or Fu.IsDefending(bot)) and not Fu.IsThereNonSelfCoreNearby(1200) then
		if
			#laneCreeps >= 4
			and Fu.CanBeAttacked(laneCreeps[1])
			and not Fu.IsRunning(laneCreeps[1])
			and #nearbyEnemies == 0
			and Fu.GetMP(bot) > 0.35
			and hpAfterCast > 0.5
			and not Fu.DoesSomeoneHaveModifier(laneCreeps, "modifier_phoenix_fire_spirit_burn")
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if Fu.IsFarming(bot) and Fu.GetMP(bot) > 0.35 and hpAfterCast > 0.4 then
		local neutralCreeps = bot:GetNearbyNeutralCreeps(math.min(castRange, 1600))
		if
			(#neutralCreeps >= 2 or #neutralCreeps >= 1 and neutralCreeps[1]:IsAncientCreep())
			and not Fu.DoesSomeoneHaveModifier(neutralCreeps, "modifier_phoenix_fire_spirit_burn")
		then
			return BOT_ACTION_DESIRE_HIGH
		end
		if
			#laneCreeps >= 3
			and not Fu.DoesSomeoneHaveModifier(laneCreeps, "modifier_phoenix_fire_spirit_burn")
			and not Fu.IsThereNonSelfCoreNearby(1200)
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.CanBeAttacked(botTarget)
			and Fu.GetHP(botTarget) > 0.25
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
			and hpAfterCast > 0.6
			and not botTarget:HasModifier("modifier_phoenix_fire_spirit_burn")
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if
			Fu.IsTormentor(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
			and hpAfterCast > 0.7
			and not botTarget:HasModifier("modifier_phoenix_fire_spirit_burn")
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderFireSpiritsLaunch()
	if
		not Fu.CanCastAbility(launchFireSpiritAbility)
		or bot:HasModifier("modifier_phoenix_icarus_dive")
		or bot:HasModifier("modifier_phoenix_supernova_hiding")
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = fireSpiritsAbility:GetCastRange()
	local radius = fireSpiritsAbility:GetSpecialValueInt("radius")
	local spiritSpeed = fireSpiritsAbility:GetSpecialValueInt("spirit_speed")
	-- datafeed: Fire Spirits' burn length is "duration" (4); "burn_duration" is Icarus Dive's key and read 0 here
	local burnDuration = fireSpiritsAbility:GetSpecialValueFloat("duration")
	local damage = fireSpiritsAbility:GetSpecialValueInt("damage_per_second") * burnDuration
	botTarget = Fu.GetProperTarget(bot)
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, enemy in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemy)
			and Fu.IsInRange(bot, enemy, castRange)
			and Fu.CanCastOnNonMagicImmune(enemy)
			and Fu.CanKillTarget(enemy, damage, DAMAGE_TYPE_MAGICAL)
			and not enemy:HasModifier("modifier_abaddon_borrowed_time")
			and not enemy:HasModifier("modifier_dazzle_shallow_grave")
			and not enemy:HasModifier("modifier_oracle_false_promise_timer")
			and not enemy:HasModifier("modifier_templar_assassin_refraction_absorb")
			and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
		then
			local travelTime = GetUnitToUnitDistance(bot, enemy) / spiritSpeed
			local predictedLocation = Fu.GetCorrectLoc(enemy, travelTime)
			local aoe = bot:FindAoELocation(true, true, predictedLocation, castRange, radius, 0, 0)
			if travelTime > X.GetModifierTime(enemy, "modifier_phoenix_fire_spirit_burn") then
				if aoe.count >= 2 then
					return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
				else
					return BOT_ACTION_DESIRE_HIGH, predictedLocation
				end
			end
		end
	end
	if isGoingOnSomeone then
		local strongestEnemy = nil
		local maxDps = 0
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.IsInRange(bot, enemy, castRange)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and not Fu.IsEnemyChronosphereInLocation(enemy:GetLocation())
				and not Fu.IsEnemyBlackHoleInLocation(enemy:GetLocation())
				and not enemy:HasModifier("modifier_necrolyte_reapers_scythe")
				and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
			then
				local dps = enemy:GetAttackDamage() * enemy:GetAttackSpeed()
				if dps > maxDps then
					strongestEnemy = enemy
					maxDps = dps
				end
			end
		end
		if strongestEnemy ~= nil then
			local travelTime = GetUnitToUnitDistance(bot, strongestEnemy) / spiritSpeed
			local predictedLocation = Fu.GetCorrectLoc(strongestEnemy, travelTime)
			local aoe = bot:FindAoELocation(true, true, predictedLocation, castRange, radius, 0, 0)
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(strongestEnemy, "modifier_phoenix_fire_spirit_burn")
			then
				if Fu.IsInLaningPhase() then
					for _, ally in pairs(nearbyAllies) do
						if
							Fu.IsValidHero(ally)
							and not ally:IsIllusion()
							and (
								Fu.IsAttacking(strongestEnemy) == ally
								or Fu.IsChasingTarget(strongestEnemy, ally)
								or strongestEnemy:GetAttackTarget() == ally
							)
						then
							if aoe.count >= 2 then
								return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
							else
								return BOT_ACTION_DESIRE_HIGH, predictedLocation
							end
						end
					end
				else
					if aoe.count >= 2 then
						return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
					else
						return BOT_ACTION_DESIRE_HIGH, predictedLocation
					end
				end
			end
		end
	end
	-- Laning: launch spirits onto farming enemy cores.
	if Fu.IsInLaningPhase() and not Fu.IsRetreating(bot) then
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.IsCore(enemy)
				and not Fu.IsSuspiciousIllusion(enemy)
				and Fu.IsInRange(bot, enemy, castRange)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and not enemy:HasModifier("modifier_phoenix_fire_spirit_burn")
			then
				local atk = enemy:GetAttackTarget()
				local farming = atk ~= nil
					and not atk:IsNull()
					and atk:IsAlive()
					and not atk:IsHero()
					and atk:GetTeam() ~= enemy:GetTeam()
				local nearWave = #enemy:GetNearbyLaneCreeps(500, true) >= 1
				if farming or nearWave then
					local travelTime = GetUnitToUnitDistance(bot, enemy) / spiritSpeed
					local predictedLocation = Fu.GetCorrectLoc(enemy, travelTime)
					if
						DotaTime() > lastLaunchTime + travelTime + 0.25
						and travelTime > X.GetModifierTime(enemy, "modifier_phoenix_fire_spirit_burn")
					then
						return BOT_ACTION_DESIRE_HIGH, predictedLocation
					end
				end
			end
		end
	end
	local laneCreeps = bot:GetNearbyLaneCreeps(math.min(castRange, 1600), true)
	local laneCreepCenter = Fu.GetCenterOfUnits(laneCreeps)
	if (Fu.IsPushing(bot) or Fu.IsDefending(bot)) and not Fu.IsThereNonSelfCoreNearby(1200) then
		if
			#laneCreeps >= 4
			and Fu.CanBeAttacked(laneCreeps[1])
			and not Fu.IsRunning(laneCreeps[1])
			and #nearbyEnemies == 0
		then
			local travelTime = GetUnitToLocationDistance(bot, laneCreepCenter) / spiritSpeed
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(laneCreeps[1], "modifier_phoenix_fire_spirit_burn")
			then
				return BOT_ACTION_DESIRE_HIGH, laneCreepCenter
			end
		end
	end
	if Fu.IsFarming(bot) then
		local neutralCreeps = bot:GetNearbyNeutralCreeps(math.min(castRange, 1600))
		local neutralCreepCenter = Fu.GetCenterOfUnits(neutralCreeps)
		if
			(#neutralCreeps >= 2 or #neutralCreeps >= 1 and neutralCreeps[1]:IsAncientCreep()) and not Fu.IsRunning(bot)
		then
			local travelTime = GetUnitToLocationDistance(bot, neutralCreepCenter) / spiritSpeed
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(neutralCreeps[1], "modifier_phoenix_fire_spirit_burn")
			then
				return BOT_ACTION_DESIRE_HIGH, neutralCreepCenter
			end
		end
		if
			#laneCreeps >= 3
			and Fu.CanBeAttacked(laneCreeps[1])
			and not Fu.IsRunning(laneCreeps[1])
			and not Fu.IsThereNonSelfCoreNearby(1200)
		then
			local travelTime = GetUnitToLocationDistance(bot, laneCreepCenter) / spiritSpeed
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(laneCreeps[1], "modifier_phoenix_fire_spirit_burn")
			then
				return BOT_ACTION_DESIRE_HIGH, laneCreepCenter
			end
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.CanBeAttacked(botTarget)
			and Fu.GetHP(botTarget) > 0.25
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
		then
			local travelTime = GetUnitToUnitDistance(bot, botTarget) / spiritSpeed
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(botTarget, "modifier_phoenix_fire_spirit_burn")
			then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
			end
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if
			Fu.IsTormentor(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
			and not botTarget:HasModifier("modifier_phoenix_fire_spirit_burn")
		then
			local travelTime = GetUnitToUnitDistance(bot, botTarget) / spiritSpeed
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(botTarget, "modifier_phoenix_fire_spirit_burn")
			then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
			end
		end
	end
	local nearbyCreeps = bot:GetNearbyCreeps(castRange, true)
	if Fu.IsValid(nearbyCreeps[2]) and Fu.CanBeAttacked(nearbyCreeps[2]) and not Fu.IsRunning(nearbyCreeps[2]) then
		local aoe = bot:FindAoELocation(true, false, Fu.GetCenterOfUnits(nearbyCreeps), radius, radius, 0, 0)
		if aoe.count >= 3 then
			local travelTime = GetUnitToLocationDistance(bot, aoe.targetloc) / spiritSpeed
			if
				DotaTime() > lastLaunchTime + travelTime + 0.25
				and travelTime > X.GetModifierTime(nearbyCreeps[2], "modifier_phoenix_fire_spirit_burn")
			then
				return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderSunRay()
	if
		not Fu.CanCastAbility(sunRayAbility)
		or bot:HasModifier("modifier_phoenix_icarus_dive")
		or bot:HasModifier("modifier_phoenix_sun_ray")
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, sunRayAbility:GetCastRange())
	local currentHp = hpRatio
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	if isGoingOnSomeone then
		local weakestEnemy = nil
		local lowestHealth = 99999
		local attackingAllies = Fu.GetSpecialModeAllies(bot, 900, BOT_MODE_ATTACK)
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.IsInRange(bot, enemy, castRange * 0.8)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and not enemy:HasModifier("modifier_abaddon_borrowed_time")
				and not enemy:HasModifier("modifier_dazzle_shallow_grave")
				and not enemy:HasModifier("modifier_necrolyte_reapers_scythe")
				and currentHp > 0.4
			then
				local health = enemy:GetHealth()
				if health < lowestHealth then
					weakestEnemy = enemy
					lowestHealth = health
				end
			end
		end
		if weakestEnemy ~= nil and #attackingAllies >= 2 then
			bot.sun_ray_engage = true
			bot.sun_ray_target = weakestEnemy
			return BOT_ACTION_DESIRE_HIGH, weakestEnemy:GetLocation()
		end
	end
	local nearbyAllies = bot:GetNearbyHeroes(castRange, false, BOT_MODE_NONE)
	for _, ally in pairs(nearbyAllies) do
		if
			Fu.IsValidHero(ally)
			and Fu.IsCore(ally)
			and Fu.GetHP(ally) < 0.5
			and ally:WasRecentlyDamagedByAnyHero(3.5)
			and not ally:IsIllusion()
			and currentHp > 0.38
			and not (Fu.IsRetreating(bot) and Fu.IsRealInvisible(bot))
		then
			if
				not Fu.IsRunning(ally)
				or ally:HasModifier("modifier_faceless_void_chronosphere_freeze")
				or ally:HasModifier("modifier_enigma_black_hole_pull")
			then
				bot.sun_ray_heal_ally = true
				bot.sun_ray_target = ally
				return BOT_ACTION_DESIRE_HIGH, ally:GetLocation()
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
-- [SHy-PHOENIX] sun-ray-spirits summon|launch, at most once per 2s per kind.
function X.LogSunRaySpirits(kind, target)
	bot._sunRaySpiritsLogAt = bot._sunRaySpiritsLogAt or {}
	if DotaTime() < (bot._sunRaySpiritsLogAt[kind] or -999) then
		return
	end
	bot._sunRaySpiritsLogAt[kind] = DotaTime() + 2
	pcall(
		print,
		string.format(
			"[SHy-PHOENIX] t=%.0f sun-ray-spirits %s target=%s hp=%.2f",
			DotaTime(),
			kind,
			target and (string.gsub(target:GetUnitName(), "npc_dota_hero_", "")) or "-",
			Fu.GetHP(bot)
		)
	)
end
-- Rod of Atos and the enemy to root while an engage Sun Ray is on it, or nil.
function X.ConsiderAtosOnSunRay()
	if not bot.sun_ray_engage or not bot:HasModifier("modifier_phoenix_sun_ray") then
		return nil
	end
	local sunRayTarget = bot.sun_ray_target
	if
		not Fu.IsValidHero(sunRayTarget)
		or sunRayTarget:GetTeam() == bot:GetTeam()
		or Fu.IsSuspiciousIllusion(sunRayTarget)
	then
		return nil
	end
	local slot = bot:FindItemSlot("item_rod_of_atos")
	if slot < 0 or slot > 5 then
		return nil
	end
	local atos = bot:GetItemInSlot(slot)
	if atos == nil or not atos:IsFullyCastable() then
		return nil
	end
	local range = Fu.GetProperCastRange(false, bot, atos:GetCastRange())
	if
		not Fu.IsInRange(bot, sunRayTarget, range)
		or not Fu.CanCastOnNonMagicImmune(sunRayTarget)
		or Fu.IsDisabled(sunRayTarget)
		or sunRayTarget:IsRooted()
	then
		return nil
	end
	pcall(
		print,
		string.format(
			"[SHy-PHOENIX] t=%.0f atos-sun-ray target=%s hp=%.2f dist=%d",
			DotaTime(),
			(string.gsub(sunRayTarget:GetUnitName(), "npc_dota_hero_", "")),
			Fu.GetHP(sunRayTarget),
			math.floor(GetUnitToUnitDistance(bot, sunRayTarget))
		)
	)
	return atos, sunRayTarget
end
function X.ConsiderSunRayStop()
	if not Fu.CanCastAbility(sunRayStopAbility) or bot:HasModifier("modifier_phoenix_icarus_dive") then
		return BOT_ACTION_DESIRE_NONE
	end
	if not bot:HasModifier("modifier_phoenix_sun_ray") then
		return BOT_ACTION_DESIRE_NONE
	end
	local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1600)
	local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1600)
	local currentHp = hpRatio or Fu.GetHP(bot)
	local underFire = bot:WasRecentlyDamagedByAnyHero(2.0) or X.IsBeingAttackedByRealHero(nearbyEnemies, bot)
	-- Abort early so retreat / dive can run instead of standing still.
	if Fu.IsRetreating(bot) and underFire then
		return BOT_ACTION_DESIRE_HIGH
	end
	if underFire and currentHp < 0.4 then
		return BOT_ACTION_DESIRE_HIGH
	end
	if currentHp < 0.28 then
		return BOT_ACTION_DESIRE_HIGH
	end
	if bot.sun_ray_engage then
		if
			underFire and currentHp < 0.35
			or #nearbyAllies + 1 < #nearbyEnemies
			or #nearbyEnemies == 0
			or #nearbyAllies == 0 and #nearbyEnemies == 0
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if bot.sun_ray_heal_ally then
		if underFire and currentHp < 0.35 then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if math.floor(DotaTime()) % 2 == 0 then
		if Fu.IsValidHero(bot.sun_ray_target) and not bot:IsFacingLocation(bot.sun_ray_target:GetLocation(), 45) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderToggleMovement()
	if
		not Fu.CanCastAbility(sunRayToggleMoveAbility)
		or not bot:HasModifier("modifier_phoenix_sun_ray")
		or bot:HasModifier("modifier_phoenix_supernova_hiding")
		or bot:IsRooted()
	then
		return BOT_ACTION_DESIRE_NONE, ""
	end
	local followRange = 1150
	if Fu.IsValidHero(bot.sun_ray_target) then
		if not Fu.IsInRange(bot, bot.sun_ray_target, followRange) then
			if sunRayToggleMoveAbility:GetToggleState() == false then
				return BOT_ACTION_DESIRE_HIGH, "on"
			end
			return BOT_ACTION_DESIRE_NONE, ""
		end
	end
	if sunRayToggleMoveAbility:GetToggleState() == true then
		return BOT_ACTION_DESIRE_HIGH, "off"
	end
	return BOT_ACTION_DESIRE_NONE, ""
end
function X.ConsiderSupernova()
	if not Fu.CanCastAbility(supernovaAbility) or bot:HasModifier("modifier_phoenix_supernova_hiding") then
		return BOT_ACTION_DESIRE_NONE, nil, false
	end
	local castRange = Fu.GetProperCastRange(false, bot, supernovaAbility:GetCastRange())
	local auraRadius = supernovaAbility:GetSpecialValueInt("aura_radius")
	if Fu.IsInTeamFight(bot, 1200) then
		local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1200)
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), auraRadius / 2 + 250)
		if #nearbyEnemies >= 2 then
			if string.find(GetBot():GetUnitName(), "phoenix") and bot:HasScepter() then
				local near = Fu.GetAlliesNearLoc(bot:GetLocation(), castRange)
				for _, ally in pairs(near) do
					if
						Fu.IsValidHero(ally)
						and not Fu.IsAttacking(ally)
						and Fu.GetHP(ally) < 0.25
						and ally:WasRecentlyDamagedByAnyHero(3.0)
					then
						return BOT_ACTION_DESIRE_HIGH, ally, true
					end
				end
			end
			-- With Scepter and no ally to save, still self-cast: the old else-branch meant a
			-- Scepter Phoenix never cast Supernova in a fight unless an ally was low.
			if #nearbyAllies < #nearbyEnemies + 2 then
				return BOT_ACTION_DESIRE_HIGH, nil, false
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil, false
end
function X.IsBeingAttackedByRealHero(enemies, unit)
	for _, enemy in pairs(enemies) do
		if
			Fu.IsValidHero(enemy)
			and not Fu.IsSuspiciousIllusion(enemy)
			and (enemy:GetAttackTarget() == unit or Fu.IsChasingTarget(enemy, unit))
		then
			return true
		end
	end
	return false
end
function X.GetModifierTime(unit, modifierName)
	if unit:HasModifier(modifierName) then
		return unit:GetModifierRemainingDuration(unit:GetModifierByName(modifierName))
	else
		return 0
	end
end
return X
