-- Hero-specific helper: rubick.
local X = {}
local bot = GetBot()
local Abaddon = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/abaddon")
local AbyssalUnderlord = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/abyssal_underlord")
local Alchemist = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/alchemist")
local AncientApparition = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/ancient_apparition")
local Antimage = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/antimage")
local ArcWarden = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/arc_warden")
local Axe = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/axe")
local Bane = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bane")
local Batrider = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/batrider")
local Beastmaster = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/beastmaster")
local Bloodseeker = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bloodseeker")
local BountyHunter = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bounty_hunter")
local Brewmaster = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/brewmaster")
local Bristleback = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bristleback")
local Broodmother = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/broodmother")
local Centaur = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/centaur")
local ChaosKnight = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/chaos_knight")
local Chen = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/chen")
local Clinkz = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/clinkz")
local CrystalMaiden = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/crystal_maiden")
local Rattletrap = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/rattletrap")
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local botTarget = nil
-- A handler returns "cast" when it cast, true when the spell is its own and it declined, nil otherwise.
-- SmartCast runs only for a spell no handler owns (heroes without a rubick_hero file).
local stolenSpellHandlers = {
	Abaddon,
	AbyssalUnderlord,
	Alchemist,
	AncientApparition,
	Antimage,
	ArcWarden,
	Axe,
	Bane,
	Batrider,
	Beastmaster,
	Bloodseeker,
	BountyHunter,
	Brewmaster,
	Bristleback,
	Broodmother,
	Centaur,
	ChaosKnight,
	Chen,
	Clinkz,
	CrystalMaiden,
	Rattletrap,
}
if DOTA_ABILITY_BEHAVIOR_UNIT_TARGET == nil then
	DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8
end
if DOTA_ABILITY_BEHAVIOR_NO_TARGET == nil then
	DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
end
if DOTA_ABILITY_BEHAVIOR_POINT == nil then
	DOTA_ABILITY_BEHAVIOR_POINT = 16
end
if DOTA_ABILITY_BEHAVIOR_AOE == nil then
	DOTA_ABILITY_BEHAVIOR_AOE = 32
end
if DOTA_UNIT_TARGET_HERO == nil then
	DOTA_UNIT_TARGET_HERO = 1
end
if DOTA_UNIT_TARGET_TEAM_FRIENDLY == nil then
	DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
end
if DOTA_UNIT_TARGET_TEAM_ENEMY == nil then
	DOTA_UNIT_TARGET_TEAM_ENEMY = 2
end
if DOTA_UNIT_TARGET_TEAM_BOTH == nil then
	DOTA_UNIT_TARGET_TEAM_BOTH = 3
end
function X.LogStolenCast(spellName, path, target)
	local now = DotaTime()
	X._stolenLogAt = X._stolenLogAt or {}
	if now < (X._stolenLogAt[spellName] or -999) then
		return
	end
	X._stolenLogAt[spellName] = now + 3
	local targetName = "none"
	if type(target) == "table" and target.GetUnitName ~= nil then
		targetName = string.gsub(target:GetUnitName() or "none", "npc_dota_hero_", "")
	elseif type(target) == "table" and target.x ~= nil then
		targetName = string.format("%.0f,%.0f", target.x or 0, target.y or 0)
	end
	local heroName = string.gsub(bot:GetUnitName() or "rubick", "npc_dota_hero_", "")
	pcall(
		print,
		string.format(
			"[SHy-RUBICK] t=%.0f %s stolen-cast spell=%s path=%s target=%s",
			now,
			heroName,
			spellName,
			path,
			targetName
		)
	)
end
function X.ConsiderStolenSpell(ability)
	local spellName = ability:GetName()
	if spellName == "rubick_empty1" or spellName == "rubick_empty2" or not ability:IsFullyCastable() then
		return
	end
	if ability:IsPassive() then
		return
	end
	bot = GetBot()
	if Fu.CanNotUseAbility(bot) then
		return
	end
	botTarget = Fu.GetProperTarget(bot)
	for _, handler in ipairs(stolenSpellHandlers) do
		local owned = handler.ConsiderStolenSpell(ability)
		if owned == "cast" then
			X.LogStolenCast(spellName, "custom", nil)
			return
		end
		if owned then
			return
		end
	end
	local abilityInfo = X.ClassifyAbility(ability)
	local castDesire, castTarget = X.SmartCast(ability, abilityInfo)
	if castDesire > 0 then
		X.LogStolenCast(spellName, "smart", castTarget)
		Fu.SetQueuePtToINT(bot, true)
		if abilityInfo.isNoTarget or abilityInfo.isToggle then
			bot:ActionQueue_UseAbility(ability)
		elseif abilityInfo.isUnitTarget and castTarget and type(castTarget) ~= "number" then
			bot:ActionQueue_UseAbilityOnEntity(ability, castTarget)
		elseif (abilityInfo.isPointTarget or abilityInfo.isAOE) and castTarget then
			bot:ActionQueue_UseAbilityOnLocation(ability, castTarget)
		else
			bot:ActionQueue_UseAbility(ability)
		end
	end
end
function X.ClassifyAbility(ability)
	local behavior = ability:GetBehavior()
	local targetTeam = ability:GetTargetTeam()
	local targetType = ability:GetTargetType()
	return {
		name = ability:GetName(),
		castRange = ability:GetCastRange(),
		manaCost = ability:GetManaCost(),
		damage = ability:GetAbilityDamage(),
		aoeRadius = ability:GetAOERadius() or 0,
		isUltimate = ability:IsUltimate(),
		isNoTarget = bit.band(DOTA_ABILITY_BEHAVIOR_NO_TARGET, behavior) ~= 0,
		isUnitTarget = bit.band(DOTA_ABILITY_BEHAVIOR_UNIT_TARGET, behavior) ~= 0,
		isPointTarget = bit.band(DOTA_ABILITY_BEHAVIOR_POINT, behavior) ~= 0,
		isAOE = bit.band(DOTA_ABILITY_BEHAVIOR_AOE, behavior) ~= 0,
		-- docs/BOT_API_RUNTIME.md: ABILITY_BEHAVIOR_TOGGLE = 512. IsToggle is on the ability API.
		isToggle = ability:IsToggle(),
		targetsEnemy = bit.band(DOTA_UNIT_TARGET_TEAM_ENEMY, targetTeam) ~= 0,
		targetsAlly = bit.band(DOTA_UNIT_TARGET_TEAM_FRIENDLY, targetTeam) ~= 0,
		targetsHero = bit.band(DOTA_UNIT_TARGET_HERO, targetType) ~= 0,
	}
end
function X.SmartCast(ability, abilityInfo)
	local castRange = abilityInfo.castRange + 200
	local radius = abilityInfo.aoeRadius > 0 and abilityInfo.aoeRadius or 300
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) or {}
	local nearbyAllies = bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE) or {}
	local hpRatio = Fu.GetHP(bot)
	local isInTeamFight = Fu.IsInTeamFight(bot, 1200)
	local isGoingOnSomeone = Fu.IsGoingOnSomeone(bot)
	local isRetreating = Fu.IsRetreating(bot)
	-- Stolen toggles (Rot, Pulse Nova, attribute shift) have no custom file. Turn one on into a fight
	-- and off once the enemies are gone. A stance toggle follows the same rule.
	if abilityInfo.isToggle then
		local toggledOn = ability:GetToggleState() == true
		local enemyNear = false
		for _, enemyHero in pairs(nearbyEnemies) do
			if Fu.IsValidHero(enemyHero) and Fu.IsInRange(bot, enemyHero, math.max(castRange, radius)) then
				enemyNear = true
				break
			end
		end
		if not toggledOn and enemyNear and (isInTeamFight or isGoingOnSomeone) then
			return BOT_ACTION_DESIRE_HIGH, nil
		end
		if toggledOn and #nearbyEnemies == 0 then
			return BOT_ACTION_DESIRE_MODERATE, nil
		end
		return BOT_ACTION_DESIRE_NONE
	end
	-- A no-target spell with no team used to match neither the enemy branch nor the ally branch.
	-- Lone Druid's Savage Roar is one: datafeed hero_id=80, behavior 4, target team 0.
	if abilityInfo.isNoTarget and not abilityInfo.targetsEnemy and not abilityInfo.targetsAlly then
		if isInTeamFight or isGoingOnSomeone or (isRetreating and #nearbyEnemies >= 1) then
			return BOT_ACTION_DESIRE_MODERATE, nil
		end
		return BOT_ACTION_DESIRE_NONE
	end
	if abilityInfo.isUltimate then
		return X.ConsiderUltimate(ability, abilityInfo, nearbyEnemies, nearbyAllies, castRange, radius, isInTeamFight)
	end
	if abilityInfo.targetsEnemy or not abilityInfo.targetsAlly and not abilityInfo.isNoTarget then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and enemyHero:IsChanneling()
				and Fu.IsInRange(bot, enemyHero, castRange)
				and not enemyHero:IsMagicImmune()
			then
				if abilityInfo.isUnitTarget then
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				elseif abilityInfo.isPointTarget or abilityInfo.isAOE then
					return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
				elseif abilityInfo.isNoTarget and Fu.IsInRange(bot, enemyHero, radius) then
					return BOT_ACTION_DESIRE_HIGH, nil
				end
			end
		end
		local tpTarget = Fu.GetTPTarget(bot, castRange)
		if tpTarget and not tpTarget:IsMagicImmune() then
			if abilityInfo.isUnitTarget then
				return BOT_ACTION_DESIRE_HIGH, tpTarget
			elseif abilityInfo.isPointTarget or abilityInfo.isAOE then
				return BOT_ACTION_DESIRE_HIGH, tpTarget:GetLocation()
			end
		end
		if abilityInfo.damage > 0 then
			for _, enemyHero in pairs(nearbyEnemies) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.IsInRange(bot, enemyHero, castRange)
					and not enemyHero:IsMagicImmune()
					and enemyHero:GetHealth() < abilityInfo.damage * 0.8
				then
					if abilityInfo.isUnitTarget then
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					elseif abilityInfo.isPointTarget then
						return BOT_ACTION_DESIRE_HIGH, enemyHero:GetExtrapolatedLocation(0.3)
					end
				end
			end
		end
		if isInTeamFight and #nearbyEnemies >= 2 then
			if abilityInfo.isAOE or abilityInfo.isPointTarget then
				local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
				if aoeLocation.count >= 2 then
					return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
				end
			end
			if abilityInfo.isNoTarget and #nearbyEnemies >= 2 then
				return BOT_ACTION_DESIRE_HIGH, nil
			end
		end
		if
			isGoingOnSomeone
			and Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.CanBeAttacked(botTarget)
			and not botTarget:IsMagicImmune()
		then
			if abilityInfo.isUnitTarget then
				return BOT_ACTION_DESIRE_MODERATE, botTarget
			elseif abilityInfo.isPointTarget then
				return BOT_ACTION_DESIRE_MODERATE, botTarget:GetExtrapolatedLocation(0.3)
			elseif abilityInfo.isNoTarget then
				return BOT_ACTION_DESIRE_MODERATE, nil
			end
		end
		if isRetreating and #nearbyEnemies >= 1 and hpRatio < 0.5 then
			local nearestEnemy = nearbyEnemies[1]
			if Fu.IsValidHero(nearestEnemy) and Fu.IsInRange(bot, nearestEnemy, castRange) then
				if abilityInfo.isUnitTarget then
					return BOT_ACTION_DESIRE_HIGH, nearestEnemy
				elseif abilityInfo.isPointTarget then
					return BOT_ACTION_DESIRE_HIGH, nearestEnemy:GetLocation()
				elseif abilityInfo.isNoTarget then
					return BOT_ACTION_DESIRE_HIGH, nil
				end
			end
		end
	end
	if abilityInfo.targetsAlly and abilityInfo.isUnitTarget then
		for _, allyHero in pairs(nearbyAllies) do
			if Fu.IsValidHero(allyHero) and allyHero ~= bot and Fu.IsInRange(bot, allyHero, castRange) then
				local allyHpRatio = Fu.GetHP(allyHero)
				if allyHpRatio < 0.3 and allyHero:WasRecentlyDamagedByAnyHero(2.0) then
					return BOT_ACTION_DESIRE_HIGH, allyHero
				end
				if allyHpRatio < 0.5 and isInTeamFight then
					return BOT_ACTION_DESIRE_MODERATE, allyHero
				end
			end
		end
		if hpRatio < 0.35 and bot:WasRecentlyDamagedByAnyHero(2.0) then
			return BOT_ACTION_DESIRE_HIGH, bot
		end
	end
	if abilityInfo.isNoTarget and abilityInfo.targetsAlly and isInTeamFight then
		return BOT_ACTION_DESIRE_MODERATE, nil
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderUltimate(ability, abilityInfo, nearbyEnemies, nearbyAllies, castRange, radius, isInTeamFight)
	if not isInTeamFight and #nearbyEnemies < 2 then
		if
			abilityInfo.damage > 0
			and Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and botTarget:GetHealth() < abilityInfo.damage * 0.8
			and not botTarget:IsMagicImmune()
		then
			if abilityInfo.isUnitTarget then
				return BOT_ACTION_DESIRE_HIGH, botTarget
			elseif abilityInfo.isPointTarget then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetExtrapolatedLocation(0.3)
			end
		end
		return BOT_ACTION_DESIRE_NONE
	end
	if not Fu.IsSafeToUseUltimate(bot, bot:GetLocation(), 1200) then
		return BOT_ACTION_DESIRE_NONE
	end
	if abilityInfo.isAOE or abilityInfo.isPointTarget then
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
		if aoeLocation.count >= 2 then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	if abilityInfo.isUnitTarget then
		local weakestEnemy = nil
		local lowestHpRatio = 1
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsInRange(bot, enemyHero, castRange)
				and not enemyHero:IsMagicImmune()
				and Fu.CanBeAttacked(enemyHero)
				and Fu.GetHP(enemyHero) < lowestHpRatio
			then
				lowestHpRatio = Fu.GetHP(enemyHero)
				weakestEnemy = enemyHero
			end
		end
		if weakestEnemy then
			return BOT_ACTION_DESIRE_HIGH, weakestEnemy
		end
	end
	if abilityInfo.isNoTarget and #nearbyEnemies >= 2 then
		return BOT_ACTION_DESIRE_HIGH, nil
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.CanCastAbilityROnTarget(target)
	if Fu.CanCastOnTargetAdvanced(target) and not target:HasModifier("modifier_arc_warden_tempest_double") then
		return Fu.CanCastOnNonMagicImmune(target)
	end
	return false
end
return X
