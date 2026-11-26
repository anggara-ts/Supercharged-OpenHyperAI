-- Phantom Assassin: skill build, item build, and ability use for this hero.
-- Accidental globals made file-local (#13): every bot shares one Lua state, so these were shared.
local botTarget
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local PaBlurRules = require(GetScriptDirectory() .. "/lib/systems/pa_blur_rules")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 10, 0 }, ["t20"] = { 10, 0 }, ["t15"] = { 10, 0 }, ["t10"] = { 0, 10 } }
local tAllAbilityBuildList = { { 1, 2, 1, 2, 1, 6, 1, 2, 2, 5, 6, 5, 5, 5, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1, 228,341 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_quelling_blade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_power_treads",
	"item_bfury",
	"item_desolator",
	"item_black_king_bar",
	"item_basher",
	"item_satanic",
	"item_abyssal_blade",
	"item_aghanims_shard",
	"item_ultimate_scepter_2",
	"item_travel_boots",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 11,942 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_quelling_blade",
	"item_double_branches",
	"item_magic_stick",
	"item_magic_wand",
	"item_wraith_band",
	"item_power_treads",
	"item_bfury",
	"item_desolator",
	"item_black_king_bar",
	"item_basher",
	"item_abyssal_blade",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_moon_shard",
	"item_nullifier",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 1,795 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_double_branches",
	"item_quelling_blade",
	"item_magic_stick",
	"item_magic_wand",
	"item_power_treads",
	"item_bfury",
	"item_desolator",
	"item_basher",
	"item_black_king_bar",
	"item_abyssal_blade",
	"item_travel_boots",
	"item_monkey_king_bar",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 3,037 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_quelling_blade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_power_treads",
	"item_bfury",
	"item_desolator",
	"item_black_king_bar",
	"item_basher",
	"item_abyssal_blade",
	"item_satanic",
	"item_travel_boots",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 5,188 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_quelling_blade",
	"item_double_branches",
	"item_magic_stick",
	"item_magic_wand",
	"item_power_treads",
	"item_bfury",
	"item_desolator",
	"item_black_king_bar",
	"item_basher",
	"item_abyssal_blade",
	"item_aghanims_shard",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_moon_shard",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = {}
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_PA" }, { "item_power_treads", "item_quelling_blade" }
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDefaultItem"] = false
function X.MinionThink(minionUnit)
	Minion.MinionThink(minionUnit)
end
local stiflingDaggerAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[1]), "sAbilityList[1]", "phantom_assassin")
local phantomStrikeAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[2]), "sAbilityList[2]", "phantom_assassin")
local blurAbility = SafeAbility(bot:GetAbilityByName(sAbilityList[3]), "sAbilityList[3]", "phantom_assassin")
-- Scepter: Fan of Knives (#184), by name: the slot list only lines up while the granted spell sits in slot 3.
local fanOfKnivesAbility = SafeAbility(
	bot:GetAbilityByName("phantom_assassin_fan_of_knives"),
	"phantom_assassin_fan_of_knives",
	"phantom_assassin"
)
local immaterialAbility =
	SafeAbility(bot:GetAbilityByName("phantom_assassin_immaterial"), "phantom_assassin_immaterial", "phantom_assassin")
local stiflingDaggerDesire, stiflingDaggerTarget
local phantomStrikeDesire, phantomStrikeTarget
local blurDesire
local fanOfKnivesDesire, fanOfKnivesTarget
local lastDaggerCreep
local botLevel, mpRatio, hpRatio
-- Was an accidental global (#13): set from the ability context each think.
local aetherRange = 0
function X.SkillsComplement()
	-- Before the gate below: a stun on her is exactly when CanNotUseAbility is true.
	X.WatchBlurDodge()
	if Fu.CanNotUseAbility(bot) then
		return
	end
	local context = AbilityContext.Build(bot)
	aetherRange = context.aetherRange
	botLevel = context.level
	mpRatio = context.mp
	hpRatio = context.hp
	botTarget = context.target
	blurDesire = X.ConsiderE()
	if blurDesire > 0 then
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbility(blurAbility)
		return
	end
	local fanOfKnivesWhy, fanOfKnivesTarget
	fanOfKnivesDesire, fanOfKnivesWhy, fanOfKnivesTarget = X.ConsiderAS()
	if fanOfKnivesDesire > 0 then
		-- [SHy-GRANTED] the order, at most once per 3 s (a refused order repeats every think).
		if DotaTime() >= (bot._grantedLogAt or -999) then
			bot._grantedLogAt = DotaTime() + 3
			pcall(
				print,
				string.format(
					"[SHy-GRANTED] t=%.0f phantom_assassin cast=phantom_assassin_fan_of_knives why=%s target=%s dist=%d hp=%.2f",
					DotaTime(),
					fanOfKnivesWhy or "-",
					fanOfKnivesTarget ~= nil and (string.gsub(fanOfKnivesTarget:GetUnitName(), "npc_dota_hero_", ""))
						or "-",
					fanOfKnivesTarget ~= nil and math.floor(GetUnitToUnitDistance(bot, fanOfKnivesTarget)) or -1,
					hpRatio or 0
				)
			)
		end
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbility(fanOfKnivesAbility)
		return
	end
	stiflingDaggerDesire, stiflingDaggerTarget = X.ConsiderQ()
	if stiflingDaggerDesire > 0 then
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnEntity(stiflingDaggerAbility, stiflingDaggerTarget)
		return
	end
	phantomStrikeDesire, phantomStrikeTarget = X.ConsiderW()
	if phantomStrikeDesire > 0 then
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnEntity(phantomStrikeAbility, phantomStrikeTarget)
		return
	end
end
function X.ConsiderQ()
	if not stiflingDaggerAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end
	local attackDamage = bot:GetAttackDamage()
	local castRange = stiflingDaggerAbility:GetCastRange()
	if castRange < 700 then
		castRange = 700
	end
	local castPoint = stiflingDaggerAbility:GetCastPoint()
	local manaCost = stiflingDaggerAbility:GetManaCost()
	local abilityLevel = stiflingDaggerAbility:GetLevel()
	local attackDamageFactor = 0.1 + 0.15 * abilityLevel
	local damage = 65 + attackDamage * attackDamageFactor
	local extraDamage = 8 * attackDamageFactor
	local damageType = DAMAGE_TYPE_PHYSICAL
	local alliesNearby = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	local enemiesNearby = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
	local enemiesInRange = Fu.GetNearbyHeroes(bot, castRange + 50, true, BOT_MODE_NONE)
	local enemiesInWideRange = Fu.GetNearbyHeroes(bot, castRange + 200, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(enemiesInWideRange) do
		if
			Fu.IsValid(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanCastOnTargetAdvanced(enemyHero)
			and GetUnitToUnitDistance(bot, enemyHero) <= castRange + 80
			and (
				Fu.CanKillTarget(enemyHero, damage * 1.6, damageType)
				or enemyHero:IsChanneling() and Fu.CanKillTarget(enemyHero, damage * 4.5, damageType)
			)
		then
			return BOT_ACTION_DESIRE_HIGH, enemyHero
		end
	end
	if Fu.IsGoingOnSomeone(bot) then
		local target = Fu.GetProperTarget(bot)
		if
			Fu.IsValidHero(target)
			and Fu.CanCastOnNonMagicImmune(target)
			and Fu.CanCastOnTargetAdvanced(target)
			and Fu.IsInRange(target, bot, castRange + 50)
		then
			if
				abilityLevel >= 3
				or mpRatio > 0.6
				or hpRatio < 0.4
				or Fu.GetHP(target) < 0.38
				or DotaTime() > 6 * 60
			then
				return BOT_ACTION_DESIRE_HIGH, target
			end
		end
	end
	if Fu.IsInTeamFight(bot, 1200) then
		local weakestEnemy = nil
		local lowestHealth = 10000
		for _, enemyHero in pairs(enemiesInRange) do
			if
				Fu.IsValid(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.CanCastOnTargetAdvanced(enemyHero)
			then
				local enemyHealth = enemyHero:GetHealth()
				if enemyHealth < lowestHealth then
					lowestHealth = enemyHealth
					weakestEnemy = enemyHero
				end
			end
		end
		if weakestEnemy ~= nil then
			return BOT_ACTION_DESIRE_HIGH, weakestEnemy
		end
	end
	if Fu.IsRetreating(bot) then
		for _, enemyHero in pairs(enemiesInRange) do
			if
				Fu.IsValid(enemyHero)
				and bot:WasRecentlyDamagedByHero(enemyHero, 5.0)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.CanCastOnTargetAdvanced(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and (
					bot:IsFacingLocation(enemyHero:GetLocation(), 60)
					or not Fu.IsInRange(enemyHero, bot, castRange - 300)
				)
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
		end
	end
	if
		(bot:GetActiveMode() == BOT_MODE_LANING or botLevel <= 14 and not Fu.IsGoingOnSomeone(bot))
		and not Fu.IsValid(botTarget)
	then
		local laneCreeps = bot:GetNearbyLaneCreeps(castRange + 168, true)
		local creepType = "ranged"
		for _, creep in pairs(laneCreeps) do
			if
				Fu.IsValid(creep)
				and not creep:HasModifier("modifier_fountain_glyph")
				and Fu.IsKeyWordUnit(creepType, creep)
				and (GetUnitToUnitDistance(creep, bot) > 300 or damage + extraDamage - 10 > attackDamage + 24)
			then
				local hitTime = castPoint + GetUnitToUnitDistance(bot, creep) / 1250
				if Fu.WillKillTarget(creep, damage + extraDamage, damageType, hitTime * 0.94) then
					lastDaggerCreep = creep
					return BOT_ACTION_DESIRE_HIGH, creep
				end
			end
		end
		if bot:GetMana() > 80 + botLevel * 10 and (botLevel <= 9 or #enemiesInWideRange == 0) then
			local creepType = "melee"
			for _, creep in pairs(laneCreeps) do
				if
					Fu.IsValid(creep)
					and not creep:HasModifier("modifier_fountain_glyph")
					and Fu.IsKeyWordUnit(creepType, creep)
					and GetUnitToUnitDistance(creep, bot) > 240 + botLevel * 20
				then
					local hitTime = castPoint + GetUnitToUnitDistance(bot, creep) / 1250
					if Fu.WillKillTarget(creep, damage + extraDamage, damageType, hitTime * 0.9) then
						lastDaggerCreep = creep
						return BOT_ACTION_DESIRE_HIGH, creep
					end
				end
			end
		end
		local weakestCreep = Fu.GetVulnerableWeakestUnit(bot, false, true, castRange + 100)
		local weakestHero = Fu.GetVulnerableWeakestUnit(bot, true, true, castRange + 40)
		if weakestCreep == nil or not Fu.CanKillTarget(weakestCreep, (damage + extraDamage) * 2, damageType) then
			if weakestHero ~= nil and (Fu.GetHP(weakestHero) <= 0.48 or Fu.IsInRange(bot, weakestHero, 400)) then
				return BOT_ACTION_DESIRE_HIGH, weakestHero
			end
		end
		for _, enemyHero in pairs(enemiesInRange) do
			if
				Fu.IsValid(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and GetUnitToUnitDistance(bot, enemyHero) <= castRange + 80
				and (
					enemyHero:HasModifier("modifier_flask_healing")
					or enemyHero:HasModifier("modifier_clarity_potion")
					or enemyHero:HasModifier("modifier_bottle_regeneration")
					or enemyHero:HasModifier("modifier_rune_regen")
				)
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
		end
	end
	if Fu.IsFarming(bot) and (abilityLevel >= 2 or mpRatio > 0.5) and Fu.IsAllowedToSpam(bot, manaCost) then
		local neutralCreeps = bot:GetNearbyNeutralCreeps(castRange)
		local farmTarget = Fu.GetMostHpUnit(neutralCreeps)
		if
			Fu.IsValid(farmTarget)
			and GetUnitToUnitDistance(farmTarget, bot) >= 300
			and not Fu.IsRoshan(farmTarget)
			and not Fu.IsTormentor(farmTarget)
			and (not Fu.CanKillTarget(farmTarget, damage + extraDamage, damageType) or #neutralCreeps == 1)
		then
			return BOT_ACTION_DESIRE_HIGH, farmTarget
		end
	end
	if
		(Fu.IsPushing(bot) or Fu.IsDefending(bot) or Fu.IsFarming(bot))
		and Fu.IsAllowedToSpam(bot, manaCost)
		and (bot:GetAttackDamage() >= 90 or botLevel >= 15)
		and #enemiesNearby == 0
		and #alliesNearby <= 2
	then
		local laneCreeps = bot:GetNearbyLaneCreeps(castRange + 188, true)
		local creepType = "ranged"
		for _, creep in pairs(laneCreeps) do
			if Fu.IsValid(creep) and not creep:HasModifier("modifier_fountain_glyph") then
				if Fu.IsKeyWordUnit(creepType, creep) then
					local hitTime = castPoint + GetUnitToUnitDistance(bot, creep) / 1250
					if Fu.WillKillTarget(creep, damage + extraDamage, damageType, hitTime * 0.9) then
						return BOT_ACTION_DESIRE_HIGH, creep
					end
				end
				if
					not Fu.CanKillTarget(creep, bot:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
					and not Fu.IsInRange(creep, bot, castRange - 300)
					and (
						Fu.CanKillTarget(creep, damage - 2, damageType)
						or Fu.GetUnitAllyCountAroundEnemyTarget(creep, 450) <= 1
					)
				then
					return BOT_ACTION_DESIRE_HIGH, creep
				end
			end
		end
		local creepType = "melee"
		for _, creep in pairs(laneCreeps) do
			if
				Fu.IsValid(creep)
				and not creep:HasModifier("modifier_fountain_glyph")
				and Fu.IsKeyWordUnit(creepType, creep)
				and GetUnitToUnitDistance(creep, bot) > 350
				and not bot:IsFacingLocation(creep:GetLocation(), 50)
			then
				local hitTime = castPoint + GetUnitToUnitDistance(bot, creep) / 1250
				if Fu.WillKillTarget(creep, damage + extraDamage, damageType, hitTime * 0.9) then
					return BOT_ACTION_DESIRE_HIGH, creep
				end
			end
		end
	end
	if bot:GetActiveMode() == BOT_MODE_ROSHAN and bot:GetMana() >= manaCost + 50 then
		local target = bot:GetAttackTarget()
		if Fu.IsRoshan(target) and Fu.IsInRange(target, bot, castRange) then
			return BOT_ACTION_DESIRE_HIGH, target
		end
	end
	if Fu.IsDoingTormentor(bot) and bot:GetMana() >= manaCost + 50 then
		local target = bot:GetAttackTarget()
		if Fu.IsValid(target) and Fu.IsTormentor(target) and Fu.IsInRange(target, bot, castRange) then
			return BOT_ACTION_DESIRE_HIGH, target
		end
	end
	if
		(#enemiesNearby > 0 or bot:WasRecentlyDamagedByAnyHero(3.0))
		and (bot:GetActiveMode() ~= BOT_MODE_RETREAT or #alliesNearby >= 2)
		and #enemiesInRange >= 1
		and botLevel >= 7
	then
		for _, enemyHero in pairs(enemiesInRange) do
			if
				Fu.IsValid(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.CanCastOnTargetAdvanced(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and bot:IsFacingLocation(enemyHero:GetLocation(), 80)
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
		end
	end
	return 0
end
function X.ConsiderW()
	if not phantomStrikeAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local attackDamage = bot:GetAttackDamage()
	local castRange = phantomStrikeAbility:GetCastRange()
	local castPoint = phantomStrikeAbility:GetCastPoint()
	local manaCost = phantomStrikeAbility:GetManaCost()
	local abilityLevel = phantomStrikeAbility:GetLevel()
	local bonusDamage = 18
	local damage = attackDamage
	local damageType = DAMAGE_TYPE_PHYSICAL
	local alliesNearby = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	local enemiesNearby = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
	local enemyTowers = bot:GetNearbyTowers(1400, true)
	local aliveEnemyCount = Fu.GetNumOfAliveHeroes(true)
	local target = Fu.GetProperTarget(bot)
	if
		Fu.IsValid(target)
		and not target:IsAttackImmune()
		and Fu.CanCastOnNonMagicImmune(target)
		and GetUnitToUnitDistance(bot, target) <= castRange + 80
		and (
			Fu.CanKillTarget(target, damage * 1.28, damageType)
			or target:IsChanneling() and Fu.CanKillTarget(target, damage * 2.28, damageType)
		)
	then
		return BOT_ACTION_DESIRE_HIGH, target
	end
	if
		Fu.IsGoingOnSomeone(bot)
		and (botLevel >= 2 or #enemiesNearby <= 1)
		and (#alliesNearby >= 2 or #enemiesNearby <= 1 or botLevel >= 6)
	then
		if
			Fu.IsValidHero(target)
			and not target:IsAttackImmune()
			and Fu.CanCastOnNonMagicImmune(target)
			and Fu.IsInRange(target, bot, castRange + 50)
		then
			local enemiesNearTarget = Fu.GetNearbyHeroes(target, 800, false, BOT_MODE_NONE)
			local alliesNearTarget = Fu.GetNearbyHeroes(target, 800, true, BOT_MODE_NONE)
			local enemiesAroundTarget = Fu.GetNearbyHeroes(target, 1600, false, BOT_MODE_NONE)
			if
				Fu.WillKillTarget(target, attackDamage * 3, DAMAGE_TYPE_PHYSICAL, 1.0)
				or #enemiesNearTarget <= #alliesNearTarget
				or #enemiesAroundTarget <= 1
				or GetUnitToUnitDistance(bot, target) <= 400
				or aliveEnemyCount <= 2
			then
				return BOT_ACTION_DESIRE_HIGH, target
			end
		end
	end
	if Fu.IsRetreating(bot) and bot:WasRecentlyDamagedByAnyHero(2.0) then
		local attackingAllies = Fu.GetNearbyHeroes(bot, 600, false, BOT_MODE_ATTACK)
		if #attackingAllies == 0 or hpRatio < 0.16 then
			local alliesInRange = Fu.GetNearbyHeroes(bot, castRange + 80, false, BOT_MODE_NONE)
			local allyCreeps = bot:GetNearbyCreeps(castRange + 80, false)
			local enemyCreeps = bot:GetNearbyCreeps(castRange + 80, true)
			local alliesAndCreeps = Fu.CombineTwoTable(alliesInRange, allyCreeps)
			local jumpCandidates = Fu.CombineTwoTable(alliesAndCreeps, enemyCreeps)
			local bestJumpUnit = nil
			local closestFountainDistance = Fu.GetDistanceFromAllyFountain(bot)
			for _, unit in pairs(jumpCandidates) do
				if
					Fu.IsValid(unit)
					and GetUnitToUnitDistance(unit, bot) > 260
					and Fu.GetDistanceFromAllyFountain(unit) < closestFountainDistance
				then
					bestJumpUnit = unit
					closestFountainDistance = Fu.GetDistanceFromAllyFountain(unit)
				end
			end
			if bestJumpUnit ~= nil then
				return BOT_ACTION_DESIRE_HIGH, bestJumpUnit
			end
		end
	end
	if bot:GetActiveMode() == BOT_MODE_LANING and #enemiesNearby == 0 and #enemyTowers == 0 then
		local laneCreeps = bot:GetNearbyLaneCreeps(castRange + 80, true)
		local creepType = "ranged"
		for _, creep in pairs(laneCreeps) do
			if
				Fu.IsValid(creep)
				and creep ~= lastDaggerCreep
				and not creep:HasModifier("modifier_fountain_glyph")
				and Fu.IsKeyWordUnit(creepType, creep)
				and GetUnitToUnitDistance(creep, bot) > 400
			then
				local hitTime = castPoint * 3
				if Fu.WillKillTarget(creep, damage + bonusDamage, damageType, hitTime) then
					return BOT_ACTION_DESIRE_HIGH, creep
				end
			end
		end
	end
	if
		Fu.IsFarming(bot)
		and (bot:GetAttackTarget() == nil or not bot:GetAttackTarget():IsBuilding())
		and botLevel >= 4
	then
		local neutralCreeps = bot:GetNearbyNeutralCreeps(castRange)
		local farmTarget = Fu.GetProperTarget(bot)
		if
			Fu.IsValid(farmTarget)
			and not Fu.IsRoshan(farmTarget)
			and (
				not Fu.CanKillTarget(farmTarget, damage * 2, damageType)
				or GetUnitToUnitDistance(farmTarget, bot) >= 650
			)
		then
			if Fu.IsAllowedToSpam(bot, manaCost) then
				if
					#neutralCreeps >= 3 and GetUnitToUnitDistance(farmTarget, bot) <= 400
					or #neutralCreeps >= 2 and not Fu.CanKillTarget(farmTarget, damage * 3, damageType)
					or #neutralCreeps >= 1 and not Fu.CanKillTarget(farmTarget, damage * 6, damageType)
				then
					return BOT_ACTION_DESIRE_HIGH, farmTarget
				end
			end
			if bot:GetMana() >= 100 and GetUnitToUnitDistance(farmTarget, bot) >= 550 then
				return BOT_ACTION_DESIRE_HIGH, farmTarget
			end
		end
	end
	if
		(Fu.IsPushing(bot) or Fu.IsDefending(bot) or Fu.IsFarming(bot))
		and botLevel >= 8
		and #enemiesNearby == 0
		and #alliesNearby <= 2
	then
		local laneCreeps = bot:GetNearbyLaneCreeps(castRange + 300, true)
		if
			Fu.IsValid(target)
			and not target:IsHero()
			and not target:HasModifier("modifier_fountain_glyph")
			and (
				not Fu.IsInRange(bot, target, 630) and bot:GetMana() >= 100
				or #laneCreeps >= 3 and Fu.IsAllowedToSpam(bot, manaCost)
			)
		then
			if not Fu.IsEnemyHeroAroundLocation(target:GetLocation(), 660) then
				return BOT_ACTION_DESIRE_HIGH, target
			end
		end
	end
	if bot:GetActiveMode() == BOT_MODE_ROSHAN then
		local target = bot:GetAttackTarget()
		if Fu.IsRoshan(target) and Fu.GetHP(target) > 0.15 and Fu.IsInRange(target, bot, castRange) then
			return BOT_ACTION_DESIRE_HIGH, target
		end
	end
	if Fu.IsDoingTormentor(bot) then
		local target = bot:GetAttackTarget()
		if Fu.IsValid(target) and Fu.IsTormentor(target) and Fu.IsInRange(target, bot, castRange) then
			return BOT_ACTION_DESIRE_HIGH, target
		end
	end
	return 0
end
-- The first stun projectile on its way to her within `range`, by spell name (Fu.IsStunProjectileIncoming's test).
local function IncomingStunSpell(range)
	for _, projectile in pairs(bot:GetIncomingTrackingProjectiles() or {}) do
		if
			not projectile.is_attack
			and projectile.ability ~= nil
			and GetUnitToLocationDistance(bot, projectile.location) < range
		then
			local name = projectile.ability:GetName()
			if Fu.IsStunProjectileSpell(name) then
				return name
			end
		end
	end
	return nil
end
local function LogBlur(why, fmt, ...)
	if DotaTime() < (bot._paBlurWhyAt or -999) then
		return
	end
	bot._paBlurWhyAt = DotaTime() + 3
	pcall(print, string.format("[SHy-PA] t=%.0f blur why=%s " .. fmt, DotaTime(), why, ...))
end
-- (#48) The dodge result: 1s after a blur-disjoint decision, was she stunned in between? The stun is latched on
-- every think of the window, since a short stun can be over by the time the line prints.
function X.WatchBlurDodge()
	local watch = bot._paBlurWatch
	if watch == nil then
		return
	end
	-- thinks: how many thinks ran in the window, so the line shows whether the watcher ran during a stun at all.
	watch.thinks = watch.thinks + 1
	if bot:IsAlive() and (bot:IsStunned() or bot:HasModifier("modifier_stunned")) then
		watch.stunned = true
	end
	local now = DotaTime()
	local stunned = PaBlurRules.DodgeResult(watch, now)
	if stunned == nil then
		return
	end
	bot._paBlurWatch = nil
	local cast = blurAbility:GetCooldownTimeRemaining() > 0 or bot:HasModifier("modifier_phantom_assassin_blur_active")
	pcall(
		print,
		string.format(
			"[SHy-PA] t=%.0f blur-dodge-result stunned=%s cast=%s spell=%s after=%.1f thinks=%d alive=%s hp=%.2f",
			now,
			stunned,
			cast and "yes" or "no",
			watch.spell,
			now - watch.at,
			watch.thinks,
			tostring(bot:IsAlive()),
			Fu.GetHP(bot)
		)
	)
end
function X.ConsiderE()
	if not blurAbility:IsFullyCastable() or bot:IsInvisible() then
		return BOT_ACTION_DESIRE_NONE
	end
	-- Dodge: Blur disjoints incoming projectiles (datafeed), so a stun projectile on its way is cast
	-- out of the air, near a tower too. It was only used to hide, never to dodge. 1000 range: Blur has
	-- a 0.3s cast point (game data), and any projectile already in flight is dodged.
	local stunSpell = IncomingStunSpell(1000)
	if stunSpell ~= nil then
		if DotaTime() >= (bot._paBlurLogAt or -999) then
			bot._paBlurLogAt = DotaTime() + 3
			pcall(print, string.format("[SHy-PA] t=%.0f blur-disjoint hp=%.2f", DotaTime(), Fu.GetHP(bot)))
		end
		if bot._paBlurWatch == nil then
			bot._paBlurWatch = { at = DotaTime(), spell = stunSpell, stunned = false, thinks = 0 }
		end
		return BOT_ACTION_DESIRE_HIGH
	end
	if bot:DistanceFromFountain() < 600 then
		return BOT_ACTION_DESIRE_NONE
	end
	local nearTowers = bot:GetNearbyTowers(878, true)
	local towerNear = nearTowers ~= nil and #nearTowers >= 1
	-- Escape: enemy heroes within 740 or a tower within 878 used to stop it. Maintainer (game 069): "not completely
	-- wasted, casting blur near tower or enemy hero has 0.8 vanish buffer" (datafeed fade_duration 0.8), and the
	-- disjoint and +12% speed work anyway.
	if Fu.IsRetreating(bot) then
		local heroesNear = Fu.GetNearbyHeroes(bot, 740, true, BOT_MODE_NONE)
		local ok, why = PaBlurRules.Escape({
			retreating = true,
			hitByHero = bot:WasRecentlyDamagedByAnyHero(3.1),
			level = botLevel,
			hp = hpRatio,
			heroesNear = heroesNear and #heroesNear or 0,
			towerNear = towerNear,
		})
		if ok then
			LogBlur(
				"escape",
				"near=%s heroes=%d tower=%s hp=%.2f",
				why,
				heroesNear and #heroesNear or 0,
				towerNear and "yes" or "no",
				hpRatio
			)
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	-- Chase-approach (maintainer, game 069: only when hunting a lone enemy): close in unseen and 12% faster.
	local hunting = Fu.IsGoingOnSomeone(bot)
	if hunting and Fu.IsValidHero(botTarget) and not Fu.IsSuspiciousIllusion(botTarget) then
		local dist = GetUnitToUnitDistance(bot, botTarget)
		local targetLoc = botTarget:GetLocation()
		local targetId = botTarget:GetPlayerID()
		local others = 0
		for _, playerId in pairs(Fu.GetLastSeenEnemiesNearLoc(targetLoc, PaBlurRules.LONE_RADIUS)) do
			if playerId ~= targetId then
				others = others + 1
			end
		end
		local attackTarget = bot:GetAttackTarget()
		local strikeReach = 0
		if phantomStrikeAbility:IsFullyCastable() then
			strikeReach = phantomStrikeAbility:GetCastRange() + aetherRange
		end
		local ok = PaBlurRules.Approach({
			hunting = true,
			dist = dist,
			othersNearTarget = others,
			-- 1000: the 600 reveal radius plus a tower's reach; IsLocHaveTower also counts the enemy base.
			towerNearTarget = towerNear or Fu.IsLocHaveTower(1000, true, targetLoc),
			attackingOther = attackTarget ~= nil and attackTarget ~= botTarget,
			hp = hpRatio,
			strikeReach = strikeReach,
			manaAfter = bot:GetMana() - blurAbility:GetManaCost(),
			strikeCost = phantomStrikeAbility:GetManaCost(),
		})
		if ok then
			LogBlur(
				"approach",
				"target=%s dist=%d hp=%.2f",
				(string.gsub(botTarget:GetUnitName(), "npc_dota_hero_", "")),
				math.floor(dist),
				hpRatio
			)
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	-- Hide in the enemy half, or while farming where enemies were seen (#48). Maintainer (game 069): only the reveal
	-- radius matters (datafeed radius 600): heroes farther away don't see her, and hitting lane or jungle creeps
	-- does not end Blur while no enemy hero or tower is near. Not while going on someone (the approach rule owns
	-- that) and not under 50% HP (the 45s cooldown is also her escape).
	local revealHeroes = Fu.GetLastSeenEnemiesNearLoc(bot:GetLocation(), PaBlurRules.HIDE_CLEAR)
	local revealTowers = bot:GetNearbyTowers(PaBlurRules.HIDE_CLEAR, true)
	local seenNear = Fu.GetLastSeenEnemiesNearLoc(bot:GetLocation(), PaBlurRules.FARM_SEEN_RADIUS)
	local inEnemyArea = Fu.IsInEnemyArea(bot)
	local ok, why = PaBlurRules.Hide({
		hunting = hunting,
		level = botLevel,
		hp = hpRatio,
		inEnemyArea = inEnemyArea,
		farming = Fu.IsFarming(bot),
		enemySeenNear = #seenNear > 0,
		heroesInReveal = #revealHeroes,
		towerInReveal = revealTowers ~= nil and #revealTowers > 0,
	})
	if ok then
		LogBlur(why, "enemyArea=%s seen=%d hp=%.2f", inEnemyArea and "yes" or "no", #seenNear, hpRatio)
		return BOT_ACTION_DESIRE_HIGH
	end
	return 0
end
function X.ConsiderAS()
	if not fanOfKnivesAbility:IsTrained() or not fanOfKnivesAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end
	local radius = 550 - 30
	local enemiesInRadius = Fu.GetNearbyHeroes(bot, radius, true, BOT_MODE_NONE)
	if #enemiesInRadius <= 0 then
		return BOT_ACTION_DESIRE_NONE
	end
	if Fu.IsRetreating(bot) or Fu.IsInTeamFight(bot, 800) then
		for _, enemyHero in pairs(enemiesInRadius) do
			if Fu.CanCastOnMagicImmune(enemyHero) then
				return BOT_ACTION_DESIRE_MODERATE, Fu.IsRetreating(bot) and "retreat" or "teamfight", enemyHero
			end
		end
	end
	if Fu.IsGoingOnSomeone(bot) then
		local target = Fu.GetProperTarget(bot)
		if Fu.IsValidHero(target) and Fu.CanCastOnMagicImmune(target) and Fu.IsInRange(bot, target, radius - 160) then
			return BOT_ACTION_DESIRE_MODERATE, "engage", target
		end
	end
	return 0
end
return X
