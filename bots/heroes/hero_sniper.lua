-- Sniper: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local ChargeTracker = require(GetScriptDirectory() .. "/lib/systems/charge_tracker")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 0, 10 }, ["t20"] = { 0, 10 }, ["t15"] = { 0, 10 }, ["t10"] = { 10, 0 } }
local tAllAbilityBuildList = { { 1, 2, 1, 3, 1, 6, 1, 2, 2, 2, 6, 3, 3, 3, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1, 55,804 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_slippers",
	"item_circlet",
	"item_double_branches",
	"item_faerie_fire",
	"item_wraith_band",
	"item_magic_wand",
	"item_power_treads",
	"item_dragon_lance",
	"item_mjollnir",
	"item_hurricane_pike",
	"item_lesser_crit",
	"item_monkey_king_bar",
	"item_aghanims_shard",
	"item_greater_crit",
	"item_satanic",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 236,898 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_slippers",
	"item_circlet",
	"item_double_branches",
	"item_faerie_fire",
	"item_wraith_band",
	"item_magic_wand",
	"item_power_treads",
	"item_maelstrom",
	"item_hurricane_pike",
	"item_mjollnir",
	"item_ultimate_scepter",
	"item_lesser_crit",
	"item_aghanims_shard",
	"item_greater_crit",
	"item_moon_shard",
	"item_satanic",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_blink",
	"item_swift_blink",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 52,876 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_branches",
	"item_circlet",
	"item_slippers",
	"item_wraith_band",
	"item_magic_wand",
	"item_power_treads",
	"item_phylactery",
	"item_ultimate_scepter",
	"item_invis_sword",
	"item_soul_booster",
	"item_greater_crit",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_hydras_breath",
	"item_silver_edge",
	"item_octarine_core",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 21,386 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_branches",
	"item_circlet",
	"item_slippers",
	"item_wraith_band",
	"item_magic_wand",
	"item_power_treads",
	"item_phylactery",
	"item_ultimate_scepter",
	"item_invis_sword",
	"item_soul_booster",
	"item_greater_crit",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_hydras_breath",
	"item_silver_edge",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 12,125 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_slippers",
	"item_circlet",
	"item_branches",
	"item_faerie_fire",
	"item_wraith_band",
	"item_magic_wand",
	"item_power_treads",
	"item_maelstrom",
	"item_dragon_lance",
	"item_ultimate_scepter",
	"item_invis_sword",
	"item_specialists_array",
	"item_mjollnir",
	"item_hydras_breath",
	"item_greater_crit",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_mask_of_madness",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_travel_boots_2",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_mjollnir", "item_magic_wand", "item_greater_crit", "item_hand_of_midas" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_mid" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDeafaultAbility"] = false
X["bDeafaultItem"] = false
function X.MinionThink(minion)
	Minion.MinionThink(minion)
end
local shrapnelAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[1]), "sAbilityList[1]", "sniper")
local takeAimAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[3]), "sAbilityList[3]", "sniper")
local concussiveGrenadeAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[4]), "sAbilityList[4]", "sniper")
local assassinateAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[6]), "sAbilityList[6]", "sniper")
local shrapnelDesire, shrapnelLocation
local takeAimDesire
local assassinateDesire, assassinateTarget, assassinateWhy, assassinateVia
-- The last Assassinate fired by the kill rule (#48), watched until it should have landed: one assassinate-result line.
local assassinateShot = nil
local concussiveGrenadeDesire, concussiveGrenadeLocation
local retainMana, botLevel, nearbyEnemies
local lastShrapnelTime = 0
local lastShrapnelLocation = Vector(0, 0)
local botTarget
function X.SkillsComplement()
	X.WatchAssassinate()
	X.ConsiderTarget()
	Fu.ConsiderForMkbDisassembleMask(bot)
	if Fu.CanNotUseAbility(bot) or bot:IsInvisible() then
		return
	end
	local context = AbilityContext.Build(bot)
	retainMana = 280
	aetherRange = context.aetherRange
	botLevel = context.level
	botTarget = context.target
	nearbyEnemies = context.enemies
	assassinateDesire, assassinateTarget, assassinateWhy, assassinateVia = X.ConsiderR()
	if assassinateDesire > 0 then
		Fu.SetQueuePtToINT(bot, true)
		bot:ActionQueue_UseAbilityOnEntity(assassinateAbility, assassinateTarget)
		if assassinateWhy == "kill" then
			X.TrackAssassinate(assassinateTarget, assassinateVia)
		end
		return
	end
	takeAimDesire = X.ConsiderE()
	if takeAimDesire > 0 then
		bot:Action_ClearActions(false)
		bot:ActionQueue_UseAbility(takeAimAbility)
		return
	end
	shrapnelDesire, shrapnelLocation = X.ConsiderQ()
	if shrapnelDesire > 0 then
		pcall(ChargeTracker.Issued, bot, shrapnelAbility)
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(shrapnelAbility, shrapnelLocation)
		lastShrapnelTime = DotaTime()
		lastShrapnelLocation = shrapnelLocation
		return
	end
	concussiveGrenadeDesire, concussiveGrenadeLocation = X.ConsiderAS()
	if concussiveGrenadeDesire > 0 then
		Fu.SetQueuePtToINT(bot, true)
		bot:ActionQueue_UseAbilityOnLocation(concussiveGrenadeAbility, concussiveGrenadeLocation)
		return
	end
end
function X.ConsiderTarget()
	if not Fu.IsRunning(bot) or bot:HasModifier("modifier_item_hurricane_pike_range") then
		return
	end
	local attackRange = bot:GetAttackRange() + 60
	if attackRange > 1600 then
		attackRange = 1600
	end
	local weakestUnit = Fu.GetAttackableWeakestUnit(bot, attackRange, true, true)
	local newTarget = nil
	if
		Fu.IsValidHero(botTarget)
		and GetUnitToUnitDistance(botTarget, bot) > attackRange
		and Fu.IsValidHero(weakestUnit)
	then
		newTarget = weakestUnit
		bot:SetTarget(newTarget)
		return
	end
end
function X.ConsiderQ()
	if not shrapnelAbility:IsFullyCastable() or DotaTime() - lastShrapnelTime < 1.5 then
		return 0
	end
	local castRange = 1600
	local abilityLevel = shrapnelAbility:GetLevel()
	local damage = (15 + 20 * (abilityLevel - 1)) * 11
	local radius = shrapnelAbility:GetAOERadius()
	local castPoint = shrapnelAbility:GetCastPoint()
	local botLocation = bot:GetLocation()
	local laneCreeps = bot:GetNearbyLaneCreeps(1600, true)
	local enemyHeroes = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
	local creepAoe = bot:FindAoELocation(true, false, botLocation, castRange, radius, 0.8, 0)
	local creepAoeCount = creepAoe.count
	if creepAoe == nil or Fu.GetInLocLaneCreepCount(bot, 1600, radius, creepAoe.targetloc) <= 2 then
		creepAoeCount = 0
	end
	local heroAoe = bot:FindAoELocation(true, true, botLocation, castRange, radius - 30, 0.8, 0)
	-- Typo fix: the field is .count (FindAoELocation); .cout was always nil, so this 2+ hero Shrapnel never fired.
	if
		#enemyHeroes >= 2
		and (heroAoe.count ~= nil and heroAoe.count >= 2)
		and bot:GetActiveMode() ~= BOT_MODE_LANING
		and (bot:GetActiveMode() ~= BOT_MODE_RETREAT or bot:GetActiveMode() == BOT_MODE_RETREAT and bot:GetActiveModeDesire() < 0.6)
		and not X.IsAbiltyQCastedHere(heroAoe.targetloc, radius)
	then
		return BOT_ACTION_DESIRE_HIGH, heroAoe.targetloc
	end
	if
		Fu.IsValidHero(botTarget)
		and not botTarget:HasModifier("modifier_sniper_shrapnel_slow")
		and Fu.CanCastOnNonMagicImmune(botTarget)
		and Fu.IsInRange(botTarget, bot, castRange + 300)
		and (abilityLevel >= 3 or bot:GetMana() >= retainMana)
		and not X.IsAbiltyQCastedHere(botTarget:GetLocation(), radius)
	then
		if
			botTarget:IsFacingLocation(Fu.GetEnemyFountain(), 30)
			and Fu.GetHP(botTarget) < 0.4
			and Fu.IsRunning(botTarget)
		then
			for offset = 0, 800, 200 do
				local aheadLocation =
					Fu.GetLocationTowardDistanceLocation(botTarget, Fu.GetEnemyFountain(), radius + 800 - offset)
				if GetUnitToLocationDistance(bot, aheadLocation) <= castRange + 200 then
					return BOT_ACTION_DESIRE_HIGH, aheadLocation
				end
			end
		end
		local predictedLocation = Fu.GetCorrectLoc(botTarget, castPoint + 1.8)
		if
			Fu.GetLocationToLocationDistance(botTarget:GetLocation(), predictedLocation) > 300
			and botTarget:GetMovementDirectionStability() > 0.4
		then
			return BOT_ACTION_DESIRE_HIGH, predictedLocation
		end
		local distance = GetUnitToUnitDistance(bot, botTarget)
		if botTarget:IsFacingLocation(botLocation, 30) and Fu.IsMoving(botTarget) then
			if distance > 400 then
				distance = distance - 200
			end
			return BOT_ACTION_DESIRE_HIGH, Fu.GetUnitTowardDistanceLocation(bot, botTarget, distance)
		end
		if bot:IsFacingLocation(botTarget:GetLocation(), 30) then
			if distance <= castRange - 200 then
				distance = distance + 400
			else
				distance = castRange + 300
			end
			return BOT_ACTION_DESIRE_HIGH, Fu.GetUnitTowardDistanceLocation(bot, botTarget, distance)
		end
		return BOT_ACTION_DESIRE_HIGH,
			Fu.GetLocationTowardDistanceLocation(botTarget, Fu.GetEnemyFountain(), radius / 2)
	end
	if Fu.IsRetreating(bot) and not bot:IsInvisible() then
		local retreatAoe = bot:FindAoELocation(true, true, botLocation, castRange - 400, radius, 1.5, 0)
		if retreatAoe.count >= 2 and not X.IsAbiltyQCastedHere(retreatAoe.targetloc, radius) then
			return BOT_ACTION_DESIRE_HIGH, retreatAoe.targetloc
		end
		if bot:GetActiveModeDesire() > 0.8 then
			local closeEnemies = Fu.GetNearbyHeroes(bot, 800, true, BOT_MODE_NONE)
			for _, enemyHero in pairs(closeEnemies) do
				if
					Fu.IsValid(enemyHero)
					and bot:WasRecentlyDamagedByHero(enemyHero, 2.0)
					and Fu.CanCastOnNonMagicImmune(enemyHero)
				then
					local midpoint = (botLocation + enemyHero:GetLocation()) / 2
					if not X.IsAbiltyQCastedHere(midpoint, radius) then
						return BOT_ACTION_DESIRE_HIGH, midpoint
					end
				end
			end
		end
	end
	if
		#nearbyEnemies == 0
		and abilityLevel >= 3
		and bot:GetActiveMode() ~= BOT_MODE_ATTACK
		and bot:GetActiveMode() ~= BOT_MODE_LANING
		and bot:GetMana() >= retainMana
		and #laneCreeps >= 2
		and creepAoeCount >= 5
		and (botLevel < 25 or creepAoeCount >= 7)
		and (botLevel < 20 or GetUnitToLocationDistance(bot, creepAoe.targetloc) >= 1100)
		and not X.IsAbiltyQCastedHere(creepAoe.targetloc, radius)
	then
		return BOT_ACTION_DESIRE_HIGH, creepAoe.targetloc
	end
	if Fu.IsFarming(bot) and bot:GetMana() >= retainMana then
		local neutralCreeps = bot:GetNearbyNeutralCreeps(800)
		if
			#neutralCreeps >= 4
			and Fu.IsValid(botTarget)
			and not Fu.CanKillTarget(botTarget, bot:GetAttackDamage() * 3.88, DAMAGE_TYPE_PHYSICAL)
		then
			local neutralAoe = bot:FindAoELocation(true, false, botLocation, castRange, radius, 0.8, 0)
			if neutralAoe.count >= 5 then
				return BOT_ACTION_DESIRE_HIGH, neutralAoe.targetloc
			end
		end
	end
	if Fu.IsDoingRoshan(bot) then
		local attackTarget = bot:GetAttackTarget()
		if
			Fu.IsValid(attackTarget)
			and Fu.IsRoshan(attackTarget)
			and Fu.IsInRange(attackTarget, bot, castRange)
			and Fu.GetManaAfter(shrapnelAbility:GetManaCost()) > 0.4
			and not attackTarget:HasModifier("modifier_sniper_shrapnel_slow")
			and not X.IsAbiltyQCastedHere(attackTarget:GetLocation(), radius)
		then
			return BOT_ACTION_DESIRE_HIGH, attackTarget:GetLocation()
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if
			Fu.IsTormentor(botTarget)
			and Fu.IsInRange(botTarget, bot, radius)
			and Fu.IsAttacking(bot)
			and not botTarget:HasModifier("modifier_sniper_shrapnel_slow")
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	if
		Fu.IsFarming(bot)
		and #nearbyEnemies == 0
		and Fu.GetManaAfter(shrapnelAbility:GetManaCost()) > 0.4
		and (ChargeTracker.Count(bot, shrapnelAbility) or 0) >= 2
	then
		local neutralCreeps = bot:GetNearbyNeutralCreeps(castRange)
		if #neutralCreeps >= 3 then
			local neutralAoe = bot:FindAoELocation(true, false, botLocation, castRange, radius, 0.8, 0)
			if neutralAoe.count >= 3 and not X.IsAbiltyQCastedHere(neutralAoe.targetloc, radius) then
				return BOT_ACTION_DESIRE_HIGH, neutralAoe.targetloc
			end
		end
	end
	return 0
end
function X.ConsiderE()
	if not takeAimAbility:IsFullyCastable() or bot:IsDisarmed() then
		return 0
	end
	local attackRange = bot:GetAttackRange()
	local abilityLevel = takeAimAbility:GetLevel()
	local attackDamage = bot:GetAttackDamage()
	local attackTarget = bot:GetAttackTarget()
	if
		Fu.IsValidHero(attackTarget)
		and not attackTarget:IsAttackImmune()
		and Fu.IsInRange(bot, attackTarget, attackRange)
	then
		if GetHeightLevel(bot:GetLocation()) < GetHeightLevel(attackTarget:GetLocation()) then
			return BOT_ACTION_DESIRE_HIGH
		end
		if Fu.IsInRange(bot, attackTarget, attackRange - 100) and Fu.IsAttacking(bot) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
-- What one Assassinate does to this target: the magical bonus damage and Sniper's own attack, after resistances.
-- Datafeed 7.42: the shot "deals Sniper's attack damage ... and bonus damage". Game files: "damage" 300/400/500
-- (magical) and attack_factor 0, an offset from a full attack (Stifling Dagger's -70 is its 30%).
function X.AssassinateDamage(enemyHero, bonusDamage)
	local bonusTaken = enemyHero:GetActualIncomingDamage(bonusDamage * (1 + bot:GetSpellAmp()), DAMAGE_TYPE_MAGICAL)
	local attackTaken = 0
	if not enemyHero:IsAttackImmune() then
		attackTaken = enemyHero:GetActualIncomingDamage(bot:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
	end
	return bonusTaken, attackTaken
end
-- The kill check counted only the bonus damage. Now the attack counts too, at 90% (damage spread), except on
-- targets whose defence only the magic check models (Mana Shield, Refraction, Bristleback, Ghost Ship rum).
-- Returns "magic" (the bonus alone kills), "attack" (the kill needs the shot's attack part) or nil.
-- Timing: both parts land together when the shot hits (datafeed hero 35: the shot "deals Sniper's attack damage
-- ... and bonus damage", attack_factor_tooltip 100), hitDelay later (AbilityCastPoint 2.0 plus the flight at
-- projectile_speed 2500); the target's regen over hitDelay is added to its HP. No right-click Sniper would make
-- before the shot is counted (the rule only fires outside his attack range).
function X.AssassinateKills(enemyHero, bonusDamage, hitDelay)
	if Fu.WillMagicKillTarget(bot, enemyHero, bonusDamage, hitDelay) then
		return "magic"
	end
	if
		enemyHero:HasModifier("modifier_medusa_mana_shield")
		or enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
		or enemyHero:HasModifier("modifier_kunkka_ghost_ship_damage_delay")
		or enemyHero:GetUnitName() == "npc_dota_hero_bristleback"
	then
		return nil
	end
	local bonusTaken, attackTaken = X.AssassinateDamage(enemyHero, bonusDamage)
	local healthAtHit = enemyHero:GetHealth() + enemyHero:GetHealthRegen() * hitDelay
	if bonusTaken + attackTaken * 0.9 >= healthAtHit then
		return "attack"
	end
	return nil
end
-- [SHy-SNIPER] assassinate-kill: a shot fired because it should kill, at most once per 3s. bonus= and attack= are
-- the two parts of the shot after the target's resistances; hp above bonus means the kill counts on the attack.
-- via= magic (the bonus alone kills) or attack (the kill needs the attack part); delay= the expected time to the hit.
function X.LogAssassinateKill(enemyHero, bonusDamage, via, hitDelay)
	if DotaTime() < (bot._assassinateLogAt or -999) then
		return
	end
	bot._assassinateLogAt = DotaTime() + 3
	local bonusTaken, attackTaken = X.AssassinateDamage(enemyHero, bonusDamage)
	pcall(
		print,
		string.format(
			"[SHy-SNIPER] t=%.0f assassinate-kill target=%s hp=%.0f bonus=%.0f attack=%.0f dist=%.0f via=%s delay=%.2f",
			DotaTime(),
			(string.gsub(enemyHero:GetUnitName(), "npc_dota_hero_", "")),
			enemyHero:GetHealth(),
			bonusTaken,
			attackTaken,
			GetUnitToUnitDistance(bot, enemyHero),
			tostring(via),
			hitDelay or -1
		)
	)
end
-- [SHy-SNIPER] assassinate-result (#48): one line per kill shot, 3s after it should have hit (game 085 could not
-- tell whether a kill that needed the attack part worked: one target lived with a few HP and died to an ally, one
-- died before the shot could land).
--   cast=yes|no   Assassinate went on cooldown (the shot left); no = the order never became a cast
--   died=yes|no|fog  the target died by the expected hit + 3s; fog = not seen at the end, unknown
--   when=before|hit|later|-  the death came before the expected hit (someone else), within 0.5s after it (the
--                 shot), or later; offset= the death time minus the expected hit (the hit time is taken on the
--                 first think after the cooldown starts, so it can run a think late: "before" allows 0.3s)
--   hp= the target's HP when last seen; hpOrder= at the order; hpBefore= / hpAfter= the last HP seen before the
--   expected hit / the first after it; immune=yes when the target was magic immune around the hit; gap=yes when
--   Sniper's think did not run for 1.5s or more on the way (Sniper died, or the think was skipped); end=checked |
--   not-cast | replaced (another kill shot was ordered)
-- A death is the target's death count going up (GetHeroDeaths); IsAlive() on an enemy hero may read false when it
-- only left vision (docs/BOT_API_RUNTIME.md), so it counts only when the death count cannot be read and the target
-- was seen in the last 0.5s.
function X.TrackAssassinate(target, via)
	if not Fu.IsValidHero(target) then
		return
	end
	if assassinateShot ~= nil then
		if assassinateShot.target == target and assassinateShot.castAt == nil then
			return
		end
		X.FinishAssassinate("replaced")
	end
	local castPoint = assassinateAbility:GetCastPoint()
	local speed = assassinateAbility:GetSpecialValueInt("projectile_speed")
	assassinateShot = {
		target = target,
		name = (string.gsub(target:GetUnitName(), "npc_dota_hero_", "")),
		via = via or "-",
		orderAt = DotaTime(),
		-- datafeed hero 35: AbilityCastPoint 2, projectile_speed 2500 (fallbacks when the API reads 0)
		castPoint = castPoint > 0 and castPoint or 2,
		speed = speed > 0 and speed or 2500,
		dist = GetUnitToUnitDistance(bot, target),
		hpOrder = target:GetHealth(),
		hpLast = target:GetHealth(),
		seenAt = DotaTime(),
		lastWatchAt = DotaTime(),
		deathsStart = X.EnemyDeaths(target),
	}
end
function X.EnemyDeaths(target)
	local ok, deaths = pcall(function()
		return GetHeroDeaths(target:GetPlayerID())
	end)
	if ok and type(deaths) == "number" then
		return deaths
	end
	return nil
end
function X.WatchAssassinate()
	local shot = assassinateShot
	if shot == nil then
		return
	end
	local now = DotaTime()
	-- No think for a while (Sniper died, or his think was skipped): keep watching, but say so on the line.
	if now - shot.lastWatchAt > 1.5 then
		shot.gap = true
	end
	shot.lastWatchAt = now
	local target = shot.target
	local valid = target ~= nil and not target:IsNull()
	if shot.castAt == nil and assassinateAbility:GetCooldownTimeRemaining() > 0 then
		-- The cooldown starts when the cast point ends and the shot leaves; it lands after the flight.
		shot.castAt = now
		local dist = (valid and target:CanBeSeen()) and GetUnitToUnitDistance(bot, target) or shot.dist
		shot.hitAt = now + dist / shot.speed
	end
	local deaths = valid and shot.deathsStart ~= nil and X.EnemyDeaths(target) or nil
	if deaths ~= nil then
		if deaths > shot.deathsStart then
			shot.diedAt = shot.diedAt or now
		end
	elseif valid and not target:IsAlive() and now - shot.seenAt <= 0.5 then
		shot.diedAt = shot.diedAt or now
	end
	if shot.diedAt == nil and valid and target:CanBeSeen() then
		local hp = target:GetHealth()
		shot.hpLast, shot.seenAt = hp, now
		if shot.hitAt == nil or now < shot.hitAt then
			shot.hpBefore = hp
		elseif shot.hpAfter == nil then
			shot.hpAfter = hp
		end
		if target:IsMagicImmune() and (shot.hitAt == nil or now <= shot.hitAt + 0.2) then
			shot.immune = true
		end
	end
	if shot.hitAt ~= nil then
		if now >= shot.hitAt + 3 then
			X.FinishAssassinate("checked")
		end
	elseif now > shot.orderAt + shot.castPoint + 1.5 then
		X.FinishAssassinate("not-cast")
	end
end
-- Pure: did the target die by the expected hit + 3s, and when. diedAt / seenAt nil-able game times.
function X.AssassinateDeath(diedAt, hitAt, seenAt, now)
	if diedAt ~= nil and diedAt <= hitAt + 3 then
		if diedAt < hitAt - 0.3 then
			return "yes", "before"
		elseif diedAt <= hitAt + 0.5 then
			return "yes", "hit"
		end
		return "yes", "later"
	end
	if seenAt == nil or now - seenAt > 0.5 then
		return "fog", "-"
	end
	return "no", "-"
end
function X.FinishAssassinate(ending)
	local shot = assassinateShot
	assassinateShot = nil
	if shot == nil then
		return
	end
	local now = DotaTime()
	local hitAt = shot.hitAt or (shot.orderAt + shot.castPoint + shot.dist / shot.speed)
	local died, when = X.AssassinateDeath(shot.diedAt, hitAt, shot.seenAt, now)
	pcall(
		print,
		string.format(
			"[SHy-SNIPER] t=%.0f assassinate-result target=%s via=%s cast=%s died=%s within=3s when=%s offset=%s hp=%.0f hpOrder=%.0f hpBefore=%s hpAfter=%s immune=%s gap=%s end=%s",
			now,
			shot.name,
			shot.via,
			shot.castAt ~= nil and "yes" or "no",
			died,
			when,
			shot.diedAt and string.format("%.1f", shot.diedAt - hitAt) or "-",
			died == "yes" and 0 or shot.hpLast,
			shot.hpOrder,
			shot.hpBefore and string.format("%.0f", shot.hpBefore) or "-",
			shot.hpAfter and string.format("%.0f", shot.hpAfter) or "-",
			shot.immune and "yes" or "no",
			shot.gap and "yes" or "no",
			ending
		)
	)
end
function X.ConsiderR()
	if not assassinateAbility:IsFullyCastable() then
		return 0
	end
	local castRange = assassinateAbility:GetCastRange()
	local castPoint = assassinateAbility:GetCastPoint()
	local attackRange = bot:GetAttackRange()
	if attackRange > 1550 then
		attackRange = 1550
	end
	local damage = assassinateAbility:GetSpecialValueInt("damage")
	local projectileSpeed = assassinateAbility:GetSpecialValueInt("projectile_speed")
	local damageType = DAMAGE_TYPE_MAGICAL
	local enemyHeroes = GetUnitList(UNIT_LIST_ENEMY_HEROES)
	local enemiesInAttackRange = Fu.GetNearbyHeroes(bot, math.min(attackRange + 50, 1600), true, BOT_MODE_NONE)
	local attackTarget = enemiesInAttackRange[1]
	if Fu.IsValidHero(botTarget) and Fu.IsInRange(bot, botTarget, attackRange + 50) then
		attackTarget = botTarget
	end
	local weakestEnemy = X.GetWeakestUnitInRangeExRadius(enemyHeroes, castRange, attackRange - 300, bot)
	local channelingEnemy = X.GetChannelingUnitInRange(enemyHeroes, castRange, bot)
	local target = nil
	for _, enemyHero in pairs(enemyHeroes) do
		local hitDelay = castPoint
		if projectileSpeed > 0 then
			hitDelay = GetUnitToUnitDistance(bot, enemyHero) / projectileSpeed + castPoint
		end
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanBeAttacked(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.IsInRange(bot, enemyHero, castRange)
			and not Fu.IsInRange(bot, enemyHero, attackRange)
			and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
			and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
			and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
		then
			local via = X.AssassinateKills(enemyHero, damage, hitDelay)
			if via ~= nil then
				X.LogAssassinateKill(enemyHero, damage, via, hitDelay)
				return BOT_ACTION_DESIRE_HIGH, enemyHero, "kill", via
			end
		end
	end
	if Fu.IsValid(weakestEnemy) then
		local hitDelay = castPoint
		if projectileSpeed > 0 then
			hitDelay = GetUnitToUnitDistance(bot, weakestEnemy) / projectileSpeed + castPoint
		end
		if
			Fu.WillMagicKillTarget(bot, weakestEnemy, damage, hitDelay)
			or X.ShouldUseR(attackTarget, weakestEnemy, damage)
				and (bot:GetMana() > retainMana * 1.28 or bot:HasScepter())
		then
			target = weakestEnemy
			return BOT_ACTION_DESIRE_HIGH, target
		end
	end
	if Fu.IsValid(channelingEnemy) and not bot:IsInvisible() and not Fu.IsRetreating(bot) then
		target = channelingEnemy
		return BOT_ACTION_DESIRE_HIGH, target
	end
	return 0
end
function X.GetWeakestUnitInRangeExRadius(units, range, excludeRadius, bot)
	if units[1] == nil then
		return nil
	end
	local attackRange = bot:GetAttackRange()
	local attackDamage = bot:GetAttackDamage()
	local weakestUnit = nil
	local lowestHealth = 9999
	for _, unit in pairs(units) do
		if
			Fu.IsInRange(unit, bot, range)
			and not Fu.IsInRange(unit, bot, excludeRadius)
			and Fu.CanCastOnNonMagicImmune(unit)
			and not Fu.IsOtherAllyCanKillTarget(bot, unit)
			and unit:GetHealth() < lowestHealth
			and not unit:HasModifier("modifier_teleporting")
			and not (
				Fu.IsInRange(unit, bot, attackRange) and Fu.CanKillTarget(unit, attackDamage, DAMAGE_TYPE_PHYSICAL)
			)
		then
			weakestUnit = unit
			lowestHealth = unit:GetHealth()
		end
	end
	return weakestUnit
end
function X.GetChannelingUnitInRange(units, range, bot)
	if units[1] == nil then
		return nil
	end
	local channelingUnit = nil
	for _, unit in pairs(units) do
		if
			Fu.IsInRange(unit, bot, range)
			and not unit:IsMagicImmune()
			and unit:IsChanneling()
			and not (
				unit:HasModifier("modifier_teleporting")
				and X.GetCastPoint(bot, unit) > Fu.GetModifierTime(unit, "modifier_teleporting")
			)
		then
			channelingUnit = unit
			break
		end
	end
	return channelingUnit
end
function X.GetCastPoint(bot, target)
	local castPoint = assassinateAbility:GetCastPoint()
	local distance = GetUnitToUnitDistance(bot, target)
	local travelTime = distance / 2500
	return castPoint + travelTime
end
function X.IsAbiltyQCastedHere(location, radius)
	if Fu.GetLocationToLocationDistance(lastShrapnelLocation, location) > radius * 1.14 then
		return false
	end
	return true
end
function X.ShouldUseR(attackTarget, target, damage)
	if
		Fu.IsRetreating(bot)
		or Fu.IsValidHero(attackTarget)
			and Fu.CanBeAttacked(attackTarget)
			and (GetUnitToUnitDistance(bot, attackTarget) <= bot:GetAttackRange() - 300 or Fu.CanKillTarget(
				attackTarget,
				bot:GetAttackDamage(),
				DAMAGE_TYPE_PHYSICAL
			))
	then
		return false
	end
	if Fu.IsValid(target) then
		local teamPlayers = GetTeamPlayers(GetTeam())
		for i = 1, #teamPlayers do
			local teammate = GetTeamMember(i)
			if
				Fu.IsValid(teammate)
				and teammate ~= bot
				and GetUnitToUnitDistance(teammate, target) <= 600
				and (
					teammate:IsFacingLocation(target:GetLocation(), 20)
					or not (
						Fu.IsValidHero(attackTarget)
						and GetUnitToUnitDistance(bot, attackTarget) <= bot:GetAttackRange()
					)
				)
			then
				return true
			end
			if
				Fu.IsValid(teammate)
				and teammate:GetUnitName() == "npc_dota_hero_zuus"
				and not Fu.CanNotUseAbility(teammate)
			then
				local thundergodsWrathAbility = teammate:GetAbilityByName("zuus_thundergods_wrath")
				if thundergodsWrathAbility:IsFullyCastable() then
					local wrathDamage = thundergodsWrathAbility:GetAbilityDamage()
					if
						target:GetHealth() + 66
						< target:GetActualIncomingDamage(wrathDamage + damage, DAMAGE_TYPE_MAGICAL)
					then
						return true
					end
				end
			end
		end
	end
	return false
end
function X.ConsiderAS()
	if not concussiveGrenadeAbility:IsTrained() or not concussiveGrenadeAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local radius = 375
	local castRange = concussiveGrenadeAbility:GetCastRange()
	local castPoint = concussiveGrenadeAbility:GetCastPoint()
	local manaCost = concussiveGrenadeAbility:GetManaCost()
	if Fu.IsRetreating(bot) then
		local closeEnemies = Fu.GetNearbyHeroes(bot, radius, true, BOT_MODE_NONE)
		local nearestEnemy = closeEnemies[1]
		if
			Fu.IsValidHero(nearestEnemy)
			and Fu.CanCastOnNonMagicImmune(nearestEnemy)
			and not nearestEnemy:IsDisarmed()
		then
			-- Review fix: the grenade landed on Sniper's own spot, so no knockback direction was defined
			-- for the attacker on top of him. Land it 150 toward the attacker so the attacker is pushed
			-- away from Sniper. Unverified: which way Sniper himself (self_push 1) is pushed.
			if DotaTime() - (X.lastGrenadeLog or -99) > 10 then
				X.lastGrenadeLog = DotaTime()
				pcall(
					print,
					string.format(
						"[SHy-SNIPER] t=%.0f grenade-retreat enemy=%s dist=%d",
						DotaTime(),
						nearestEnemy:GetUnitName(),
						GetUnitToUnitDistance(bot, nearestEnemy)
					)
				)
			end
			return BOT_ACTION_DESIRE_HIGH,
				Fu.GetUnitTowardDistanceLocation(
					bot,
					nearestEnemy,
					math.min(150, GetUnitToUnitDistance(bot, nearestEnemy))
				)
		end
	end
	if Fu.IsInTeamFight(bot, 1400) then
		local aoeLocation = Fu.GetAoeEnemyHeroLocation(bot, castRange, radius, 2)
		if aoeLocation ~= nil then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation
		end
	end
	if Fu.IsGoingOnSomeone(bot) then
		if
			Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.CanCastOnNonMagicImmune(botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
return X
