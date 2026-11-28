-- Rubick: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local Rubick = dofile(GetScriptDirectory() .. "/lib/hero/rubick")
local SpellStealRules = require(GetScriptDirectory() .. "/lib/systems/spell_steal_rules")
local EnemySpells = require(GetScriptDirectory() .. "/lib/systems/enemy_spell_tracker")
-- #290: the cast callback records each enemy hero's last spell (what Spell Steal takes), also out of vision.
EnemySpells.InstallCastProbe({})
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 10, 0 }, ["t20"] = { 0, 10 }, ["t15"] = { 0, 10 }, ["t10"] = { 10, 0 } }
local tAllAbilityBuildList = { { 2, 1, 2, 3, 2, 6, 2, 3, 3, 3, 6, 1, 1, 1, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 74,552 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_circlet",
	"item_mantle",
	"item_magic_wand",
	"item_null_talisman",
	"item_boots",
	"item_phylactery",
	"item_blink",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_cyclone",
	"item_aghanims_shard",
	"item_soul_booster",
	"item_wind_waker",
	"item_ultimate_scepter_2",
	"item_aether_lens",
	"item_arcane_blink",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 127,655 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_magic_stick",
	"item_double_branches",
	"item_faerie_fire",
	"item_magic_wand",
	"item_arcane_boots",
	"item_blink",
	"item_aether_lens",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_soul_booster",
	"item_aeon_disk",
	"item_phylactery",
	"item_octarine_core",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 206,111 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_arcane_boots",
	"item_blink",
	"item_aether_lens",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_soul_booster",
	"item_aeon_disk",
	"item_phylactery",
	"item_octarine_core",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1, 1,271 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_arcane_boots",
	"item_blink",
	"item_aether_lens",
	"item_ultimate_scepter",
	"item_aghanims_shard",
	"item_cyclone",
	"item_travel_boots",
	"item_wind_waker",
	"item_ultimate_scepter_2",
	"item_phylactery",
	"item_aeon_disk",
	"item_moon_shard",
	"item_travel_boots_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 5,714 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_null_talisman",
	"item_magic_wand",
	"item_arcane_boots",
	"item_phylactery",
	"item_blink",
	"item_ultimate_scepter",
	"item_aghanims_shard",
	"item_travel_boots",
	"item_soul_booster",
	"item_ultimate_scepter_2",
	"item_glimmer_cape",
	"item_force_staff",
	"item_moon_shard",
	"item_travel_boots_2",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_black_king_bar", "item_quelling_blade" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_antimage" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDefaultItem"] = false
function X.MinionThink(minionUnit)
	Minion.MinionThink(minionUnit)
end
local telekinesisAbility = SafeAbility(bot:GetAbilityByName("rubick_telekinesis"), "rubick_telekinesis", "rubick")
local telekinesisLandAbility =
	SafeAbility(bot:GetAbilityByName("rubick_telekinesis_land"), "rubick_telekinesis_land", "rubick")
local fadeBoltAbility = SafeAbility(bot:GetAbilityByName("rubick_fade_bolt"), "rubick_fade_bolt", "rubick")
local stolenSpell1 = SafeAbility(bot:GetAbilityByName("rubick_empty1"), "rubick_empty1", "rubick")
local stolenSpell2 = SafeAbility(bot:GetAbilityByName("rubick_empty2"), "rubick_empty2", "rubick")
local spellStealAbility = SafeAbility(bot:GetAbilityByName("rubick_spell_steal"), "rubick_spell_steal", "rubick")
local telekinesisDesire, telekinesisTarget
local telekinesisLandDesire, telekinesisLandLocation
local fadeBoltDesire, fadeBoltTarget
local spellStealDesire, spellStealTarget
local botTarget
local lastSpellStealTime = 0
if bot.shouldBlink == nil then
	bot.shouldBlink = false
end
local isRetreating
function X.SkillsComplement()
	X.WatchStealResult()
	if Fu.CanNotUseAbility(bot) then
		return
	end
	local context = AbilityContext.Build(bot)
	isRetreating = context.isRetreating
	if
		Fu.GetHP(bot) > 0.3
		and not isRetreating
		and (bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility())
	then
		-- nRadius is a local of ConsiderFadeBolt and nil here, so this line raised an error every
		-- time he was casting; use the 1200 radius the rest of the file checks.
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
		if nearbyEnemies ~= nil and #nearbyEnemies > 0 then
			return
		end
	end
	botTarget = context.target
	stolenSpell1 = bot:GetAbilityInSlot(3)
	stolenSpell2 = bot:GetAbilityInSlot(4)
	X.ConsiderStolenSpell1()
	X.ConsiderStolenSpell2()
	spellStealDesire, spellStealTarget = X.ConsiderSpellSteal()
	if spellStealDesire > 0 then
		bot:Action_UseAbilityOnEntity(spellStealAbility, spellStealTarget)
		lastSpellStealTime = DotaTime()
		-- #290: X.WatchStealResult logs what arrived; the order is given again each think until it is cast, so the
		-- spell expected is the latest pick's.
		if bot._stealPending == nil then
			bot._stealPending = { orderAt = DotaTime() }
		end
		bot._stealPending.expected = bot._stealExpected
		bot._stealPending.from = bot._stealFrom
		return
	end
	telekinesisDesire, telekinesisTarget = X.ConsiderTelekinesis()
	if telekinesisDesire > 0 then
		bot.teleTarget = telekinesisTarget
		bot:Action_UseAbilityOnEntity(telekinesisAbility, telekinesisTarget)
		return
	end
	telekinesisLandDesire, telekinesisLandLocation = X.ConsiderTelekinesisLand()
	if telekinesisLandDesire > 0 then
		bot:Action_UseAbilityOnLocation(telekinesisLandAbility, telekinesisLandLocation)
		bot.isChannelLand = false
		bot.isSaveUltLand = false
		bot.isEngagingLand = false
		bot.isRetreatLand = false
		bot.isSaveAllyLand = false
		return
	end
	fadeBoltDesire, fadeBoltTarget = X.ConsiderFadeBolt()
	if fadeBoltDesire > 0 then
		bot:Action_UseAbilityOnEntity(fadeBoltAbility, fadeBoltTarget)
		return
	end
end
function X.ConsiderTelekinesis()
	if telekinesisAbility:IsHidden() or not telekinesisAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, telekinesisAbility:GetCastRange())
	-- Clear the landing reason: flags were only cleared when Land was cast, so a lift that ended without
	-- a Land left a stale flag that the next lift's landing used first.
	bot.isChannelLand, bot.isSaveUltLand, bot.isEngagingLand, bot.isRetreatLand, bot.isSaveAllyLand =
		false, false, false, false, false
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange + 300, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanCastOnTargetAdvanced(enemyHero)
			and not Fu.IsSuspiciousIllusion(enemyHero)
		then
			if enemyHero:IsChanneling() or Fu.IsCastingUltimateAbility(enemyHero) then
				bot.isChannelLand = true
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
		end
	end
	if Fu.IsGoingOnSomeone(bot) then
		local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1200)
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1200)
		-- Telekinesis targets ENEMY units (game files); only the Shard adds teammates
		-- (shard_teammate_throw_delay). Without it this order on an ally is refused every frame.
		for _, allyHero in pairs(Fu.HasAghanimsShard(bot) and nearbyAllies or {}) do
			if
				Fu.IsValidHero(allyHero)
				and Fu.IsCore(allyHero)
				and not Fu.IsSuspiciousIllusion(allyHero)
				and not allyHero:IsInvulnerable()
				and not allyHero:IsAttackImmune()
				and not allyHero:HasModifier("modifier_furion_sprout_damage")
				and not allyHero:HasModifier("modifier_legion_commander_duel")
				and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			then
				if
					allyHero:HasModifier("modifier_enigma_black_hole_pull")
					or allyHero:HasModifier("modifier_faceless_void_chronosphere_freeze")
				then
					bot.isSaveUltLand = true
					return BOT_ACTION_DESIRE_HIGH, allyHero
				end
			end
		end
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.CanCastOnTargetAdvanced(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange + 150)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not Fu.IsDisabled(botTarget)
			and not botTarget:HasModifier("modifier_furion_sprout_damage")
			and not botTarget:HasModifier("modifier_legion_commander_duel")
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			nearbyAllies = Fu.GetAlliesNearLoc(botTarget:GetLocation(), 1200)
			nearbyEnemies = Fu.GetEnemiesNearLoc(botTarget:GetLocation(), 1200)
			if
				nearbyAllies ~= nil
				and nearbyEnemies ~= nil
				and #nearbyAllies >= #nearbyEnemies
				and not (#nearbyEnemies == 0 and #nearbyAllies >= #nearbyEnemies + 2)
			then
				bot.isEngagingLand = true
				return BOT_ACTION_DESIRE_HIGH, botTarget
			end
		end
	end
	if isRetreating then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.CanCastOnTargetAdvanced(enemyHero)
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and not enemyHero:HasModifier("modifier_furion_sprout_damage")
			then
				local ourHeroesNearTarget = Fu.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local theirHeroesNearTarget = Fu.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
				if
					ourHeroesNearTarget ~= nil
					and theirHeroesNearTarget ~= nil
					and (#theirHeroesNearTarget > #ourHeroesNearTarget or bot:WasRecentlyDamagedByAnyHero(2))
				then
					bot.isRetreatLand = true
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				end
			end
		end
	end
	local alliesInRange = Fu.GetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)
	for _, allyHero in pairs(alliesInRange) do
		local allyNearbyEnemies = Fu.GetNearbyHeroes(allyHero, 1200, true, BOT_MODE_NONE)
		if
			Fu.IsValidHero(allyHero)
			and Fu.IsRetreating(allyHero)
			and allyHero:WasRecentlyDamagedByAnyHero(2)
			and not allyHero:IsIllusion()
		then
			if
				allyNearbyEnemies ~= nil
				and #allyNearbyEnemies >= 1
				and Fu.IsValidHero(allyNearbyEnemies[1])
				and Fu.CanCastOnNonMagicImmune(allyNearbyEnemies[1])
				and Fu.CanCastOnTargetAdvanced(allyNearbyEnemies[1])
				and Fu.IsInRange(bot, allyNearbyEnemies[1], castRange)
				and Fu.IsChasingTarget(allyNearbyEnemies[1], allyHero)
				and allyNearbyEnemies[1]:IsFacingLocation(allyHero:GetLocation(), 30)
				and not Fu.IsDisabled(allyNearbyEnemies[1])
				and not Fu.IsTaunted(allyNearbyEnemies[1])
				and not Fu.IsSuspiciousIllusion(allyNearbyEnemies[1])
				and not allyNearbyEnemies[1]:HasModifier("modifier_legion_commander_duel")
				and not allyNearbyEnemies[1]:HasModifier("modifier_enigma_black_hole_pull")
				and not allyNearbyEnemies[1]:HasModifier("modifier_faceless_void_chronosphere_freeze")
				and not allyNearbyEnemies[1]:HasModifier("modifier_furion_sprout_damage")
				and not allyNearbyEnemies[1]:HasModifier("modifier_necrolyte_reapers_scythe")
			then
				bot.isSaveAllyLand = true
				return BOT_ACTION_DESIRE_HIGH, allyNearbyEnemies[1]
			end
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.IsAttacking(bot)
			and botTarget:HasModifier("modifier_roshan_spell_block")
		then
			return BOT_ACTION_DESIRE_LOW, botTarget
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderTelekinesisLand()
	if telekinesisLandAbility:IsHidden() or not telekinesisLandAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	-- Throw distance is Telekinesis' max_land_distance (375, Shard +225), not the impact "radius"; the
	-- rubick_8 talent is landing DAMAGE (game files), so it no longer adds 300 to the distance.
	local landDistance = telekinesisAbility:GetSpecialValueInt("max_land_distance")
	if landDistance <= 0 then
		landDistance = 375
	end
	local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1200)
	local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1200)
	if Fu.IsValidHero(botTarget) and not Fu.IsSuspiciousIllusion(botTarget) then
		nearbyAllies = Fu.GetAlliesNearLoc(botTarget:GetLocation(), 1200)
		nearbyEnemies = Fu.GetEnemiesNearLoc(botTarget:GetLocation(), 1200)
	end
	if nearbyAllies ~= nil and nearbyEnemies ~= nil and Fu.IsValid(bot.teleTarget) then
		if bot.isChannelLand ~= nil and bot.isChannelLand == true then
			if #nearbyAllies >= #nearbyEnemies then
				if Fu.IsInRange(bot, bot.teleTarget, landDistance) then
					return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
				end
				if not Fu.IsInRange(bot, bot.teleTarget, landDistance) then
					return BOT_ACTION_DESIRE_HIGH,
						Fu.Site.GetXUnitsTowardsLocation(bot, bot:GetLocation(), landDistance)
				end
			end
			if #nearbyEnemies > #nearbyAllies then
				return BOT_ACTION_DESIRE_HIGH,
					Fu.Site.GetXUnitsTowardsLocation(bot, Fu.GetEnemyFountain(), landDistance)
			end
		end
		if bot.isSaveUltLand ~= nil and bot.isSaveUltLand == true then
			return BOT_ACTION_DESIRE_HIGH, Fu.Site.GetXUnitsTowardsLocation(bot, Fu.GetTeamFountain(), landDistance)
		end
		if bot.isEngagingLand ~= nil and bot.isEngagingLand == true then
			return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
		end
		-- datafeed: Land "throws the enemy in a targeted direction", so the point is read from the lifted
		-- unit. Both cases aimed S units from RUBICK (retreat) or toward OUR fountain (save-ally), which
		-- dropped the chaser next to Rubick or onto the fleeing ally. Throw it toward its own fountain.
		if bot.isRetreatLand ~= nil and bot.isRetreatLand == true then
			X.LogLand("retreat")
			return BOT_ACTION_DESIRE_HIGH,
				Fu.Site.GetXUnitsTowardsLocation(bot.teleTarget, Fu.GetEnemyFountain(), landDistance)
		end
		if bot.isSaveAllyLand ~= nil and bot.isSaveAllyLand == true then
			X.LogLand("save-ally")
			return BOT_ACTION_DESIRE_HIGH,
				Fu.Site.GetXUnitsTowardsLocation(bot.teleTarget, Fu.GetEnemyFountain(), landDistance)
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
-- [SHy-RUBICK] telekinesis land why, at most once per 5s.
function X.LogLand(why)
	if DotaTime() < (bot._landLogAt or -999) then
		return
	end
	bot._landLogAt = DotaTime() + 5
	pcall(
		print,
		string.format(
			"[SHy-RUBICK] t=%.0f tele-land %s target=%s",
			DotaTime(),
			why,
			Fu.IsValid(bot.teleTarget) and bot.teleTarget:GetUnitName() or "-"
		)
	)
end
function X.ConsiderFadeBolt()
	if not fadeBoltAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, fadeBoltAbility:GetCastRange())
	local damage = fadeBoltAbility:GetSpecialValueInt("damage")
	local nRadius = fadeBoltAbility:GetSpecialValueInt("radius")
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanCastOnTargetAdvanced(enemyHero)
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and not enemyHero:HasModifier("modifier_rubick_telekinesis")
		then
			if Fu.IsInEtherealForm(enemyHero) then
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
			if
				Fu.CanKillTarget(enemyHero, damage, DAMAGE_TYPE_MAGICAL)
				and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
				and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
				and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
				and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
				and not enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
		end
	end
	local alliesInRange = Fu.GetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)
	for _, allyHero in pairs(alliesInRange) do
		local allyNearbyEnemies = Fu.GetNearbyHeroes(allyHero, 1200, true, BOT_MODE_NONE)
		if
			Fu.IsValidHero(allyHero)
			and Fu.IsRetreating(allyHero)
			and allyHero:WasRecentlyDamagedByAnyHero(1.5)
			and not allyHero:IsIllusion()
		then
			if
				allyNearbyEnemies ~= nil
				and #allyNearbyEnemies >= 1
				and Fu.IsValidHero(allyNearbyEnemies[1])
				and Fu.CanCastOnNonMagicImmune(allyNearbyEnemies[1])
				and Fu.CanCastOnTargetAdvanced(allyNearbyEnemies[1])
				and Fu.IsInRange(bot, allyNearbyEnemies[1], castRange)
				and Fu.IsChasingTarget(allyNearbyEnemies[1], allyHero)
				and Fu.IsAttacking(allyNearbyEnemies[1])
				and allyNearbyEnemies[1]:IsFacingLocation(allyHero:GetLocation(), 30)
				and not Fu.IsChasingTarget(allyNearbyEnemies[1], bot)
				and not Fu.IsDisabled(allyNearbyEnemies[1])
				and not Fu.IsTaunted(allyNearbyEnemies[1])
				and not Fu.IsSuspiciousIllusion(allyNearbyEnemies[1])
				and not allyNearbyEnemies[1]:HasModifier("modifier_necrolyte_reapers_scythe")
				and not allyNearbyEnemies[1]:HasModifier("modifier_rubick_telekinesis")
			then
				return BOT_ACTION_DESIRE_HIGH, allyNearbyEnemies[1]
			end
		end
	end
	if Fu.IsInTeamFight(bot, 1200) then
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), castRange)
		local weakestTarget = nil
		local weakestHealth = 100000
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.CanCastOnTargetAdvanced(enemyHero)
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
				and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
				and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
				and not enemyHero:HasModifier("modifier_rubick_telekinesis")
				and not enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
			then
				local enemiesNearTarget = Fu.GetEnemiesNearLoc(enemyHero:GetLocation(), nRadius)
				local health = enemyHero:GetHealth()
				if enemiesNearTarget ~= nil and #enemiesNearTarget >= 1 and health < weakestHealth then
					weakestHealth = health
					weakestTarget = enemyHero
				end
			end
		end
		if weakestTarget ~= nil then
			return BOT_ACTION_DESIRE_HIGH, weakestTarget
		end
	end
	if Fu.IsGoingOnSomeone(bot) then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.CanCastOnTargetAdvanced(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not Fu.IsDisabled(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			and not botTarget:HasModifier("modifier_rubick_telekinesis")
			and not botTarget:HasModifier("modifier_templar_assassin_refraction_absorb")
		then
			local nearbyAllies = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
			local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
			if nearbyAllies ~= nil and nearbyEnemies ~= nil and #nearbyAllies >= #nearbyEnemies then
				return BOT_ACTION_DESIRE_HIGH, botTarget
			end
		end
	end
	if isRetreating then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.CanCastOnTargetAdvanced(enemyHero)
				and Fu.IsChasingTarget(enemyHero, bot)
				and Fu.IsAttacking(enemyHero)
				and not Fu.IsInRange(bot, enemyHero, 300)
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
			then
				local ourHeroesNearTarget = Fu.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local theirHeroesNearTarget = Fu.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
				if
					ourHeroesNearTarget ~= nil
					and theirHeroesNearTarget ~= nil
					and (#theirHeroesNearTarget > #ourHeroesNearTarget or bot:WasRecentlyDamagedByAnyHero(2))
				then
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				end
			end
		end
	end
	if Fu.IsPushing(bot) or Fu.IsDefending(bot) then
		local nearbyLaneCreeps = bot:GetNearbyLaneCreeps(1200, true)
		if nearbyLaneCreeps ~= nil and #nearbyLaneCreeps >= 3 and Fu.CanBeAttacked(nearbyLaneCreeps[1]) then
			return BOT_ACTION_DESIRE_HIGH, nearbyLaneCreeps[1]
		end
	end
	if Fu.IsLaning(bot) and not Fu.IsThereNonSelfCoreNearby(800) then
		local killableCreeps = {}
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1200)
		local nearbyLaneCreeps = bot:GetNearbyLaneCreeps(castRange, true)
		for _, creep in pairs(nearbyLaneCreeps) do
			if
				Fu.IsValid(creep)
				and Fu.CanBeAttacked(creep)
				and (Fu.IsKeyWordUnit("ranged", creep) or Fu.IsKeyWordUnit("siege", creep) or Fu.IsKeyWordUnit(
					"flagbearer",
					creep
				))
				and creep:GetHealth() <= damage
				and Fu.GetMP(bot) > 0.3
			then
				if
					nearbyEnemies ~= nil
					and #nearbyEnemies >= 1
					and GetUnitToUnitDistance(creep, nearbyEnemies[1]) < 500
				then
					return BOT_ACTION_DESIRE_HIGH, creep
				end
			end
			if Fu.IsValid(creep) and creep:GetHealth() <= damage then
				table.insert(killableCreeps, creep)
			end
		end
		if
			Fu.GetMP(bot) > 0.3
			and nearbyEnemies ~= nil
			and #nearbyEnemies >= 1
			and #killableCreeps >= 2
			and Fu.CanBeAttacked(killableCreeps[1])
		then
			return BOT_ACTION_DESIRE_HIGH, killableCreeps[1]
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and not botTarget:HasModifier("modifier_roshan_spell_block")
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if Fu.IsTormentor(botTarget) and Fu.IsInRange(bot, botTarget, castRange) and Fu.IsAttacking(bot) then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderStolenSpell1()
	if stolenSpell1:GetName() == "rubick_empty1" or not stolenSpell1:IsFullyCastable() then
		return BOT_ACTION_DESIRE_HIGH, 0, ""
	end
	Rubick.ConsiderStolenSpell(stolenSpell1)
	return BOT_ACTION_DESIRE_HIGH, 0, ""
end
function X.ConsiderStolenSpell2()
	if stolenSpell2:GetName() == "rubick_empty2" or not stolenSpell2:IsFullyCastable() then
		return BOT_ACTION_DESIRE_HIGH, 0, ""
	end
	Rubick.ConsiderStolenSpell(stolenSpell2)
	return BOT_ACTION_DESIRE_HIGH, 0, ""
end
-- #290: what an ability handle reads, for SpellStealRules.Value (nil when it does not read).
local function StealInfo(ability)
	if ability == nil then
		return nil
	end
	local ok, info = pcall(function()
		local behavior = ability:GetBehavior() or 0
		return {
			isPassive = ability:IsPassive(),
			isUltimate = ability:IsUltimate(),
			isAOE = bit.band(behavior, DOTA_ABILITY_BEHAVIOR_AOE or 32) ~= 0,
			damage = ability:GetAbilityDamage() or 0,
		}
	end)
	return ok and info or nil
end
local function SafeName(ability)
	if ability == nil then
		return nil
	end
	local ok, name = pcall(function()
		return ability:GetName()
	end)
	return ok and name or nil
end
-- A held stolen spell: name, value, kind, cooldown left, full cooldown, damage.
local function HeldSpell(ability)
	local name = SafeName(ability)
	if SpellStealRules.IsEmpty(name) then
		return { name = name, value = 0, kind = "empty", cd = 0, fullCd = 0, damage = 0 }
	end
	local info = SpellStealRules.KIND[name] == nil and StealInfo(ability) or nil
	local value, kind = SpellStealRules.Value(name, info)
	local okCd, cd = pcall(function()
		return ability:GetCooldownTimeRemaining()
	end)
	local okFull, fullCd = pcall(function()
		return ability:GetCooldown()
	end)
	local okDamage, damage = pcall(function()
		return ability:GetAbilityDamage()
	end)
	return {
		name = name,
		value = value,
		kind = kind,
		cd = okCd and cd or 0,
		fullCd = okFull and fullCd or 0,
		damage = okDamage and damage or 0,
	}
end
local function ShortHero(unit)
	return (string.gsub(unit:GetUnitName(), "npc_dota_hero_", ""))
end
-- The spell `enemyHero` would give: the one it is casting now (it is the last cast once its cast point ends; a cast
-- that is cancelled is unverified), else its last cast the cast callback reported. via: casting / seen / none.
local function IncomingSpell(enemyHero, now)
	if enemyHero:IsCastingAbility() or enemyHero:IsUsingAbility() then
		local active = enemyHero:GetCurrentActiveAbility()
		local name = SafeName(active)
		if name ~= nil and string.find(name, "^item_") == nil then
			return name, "casting", now
		end
	end
	local name, at = EnemySpells.LastCast(enemyHero:GetUnitName())
	if name ~= nil then
		return name, "seen", at
	end
	return nil, "none", nil
end
-- 0.5 s after Spell Steal went on cooldown: which spell arrived and its cooldown (settles whether a stolen spell
-- arrives ready, and whether the last cast the tracker had was the one he got).
function X.WatchStealResult()
	local pending = bot._stealPending
	if pending == nil then
		return
	end
	local now = DotaTime()
	if pending.castAt == nil and spellStealAbility:GetCooldownTimeRemaining() > 0 then
		pending.castAt = now
	end
	local done = pending.castAt ~= nil and now - pending.castAt >= 0.5
	-- Not cast within 5 s of the order (the target walked away, the order changed): logged with cast=no.
	if not done and (pending.castAt ~= nil or now - pending.orderAt <= 5) then
		return
	end
	bot._stealPending = nil
	local got = bot:GetAbilityInSlot(3)
	local second = bot:GetAbilityInSlot(4)
	local gotName = SafeName(got) or "none"
	local okCd, cd = pcall(function()
		return got:GetCooldownTimeRemaining()
	end)
	local okFull, fullCd = pcall(function()
		return got:GetCooldown()
	end)
	local match = "blind"
	if pending.expected ~= nil then
		match = (pending.expected == gotName) and "yes" or "no"
	end
	pcall(
		print,
		string.format(
			"[SHy-RUBICK] t=%.0f rubick steal-result from=%s expected=%s got=%s cd=%.1f fullCd=%.1f second=%s match=%s cast=%s",
			now,
			tostring(pending.from),
			tostring(pending.expected),
			gotName,
			okCd and cd or -1,
			okFull and fullCd or -1,
			SafeName(second) or "none",
			match,
			done and "yes" or "no"
		)
	)
end
-- The fields of a steal-pick / steal-skip line.
local function PickLine(pick, held, otherName, from)
	return string.format(
		"from=%s incoming=%s via=%s ago=%.0f score=%.0f kind=%s src=%s held=%s heldScore=%.1f heldKind=%s cd=%.1f"
			.. " fullCd=%.1f other=%s why=%s",
		from,
		tostring(pick.incoming),
		pick.via,
		pick.ago,
		pick.score,
		pick.kind,
		pick.source,
		tostring(held.name),
		pick.heldScore,
		held.kind,
		held.cd,
		held.fullCd,
		tostring(otherName),
		pick.why
	)
end
function X.ConsiderSpellSteal()
	if not spellStealAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local now = DotaTime()
	local hasScepter = bot:HasScepter()
	-- The old 60 s hold for a stolen ultimate that can be cast, kept (#290).
	local ultHold = now - lastSpellStealTime < SpellStealRules.HOLD_ULT
		and (
			(stolenSpell1:IsFullyCastable() and stolenSpell1:IsUltimate() and not hasScepter)
			or (stolenSpell2:IsFullyCastable() and stolenSpell2:IsUltimate())
		)
	-- With Scepter he holds two; the new spell is compared with the second slot, the one that would drop out (#290;
	-- which slot drops is unverified, the steal-result line shows both).
	local held = HeldSpell(hasScepter and stolenSpell2 or stolenSpell1)
	local otherName = hasScepter and SafeName(stolenSpell1) or nil
	local castRange = Fu.GetProperCastRange(false, bot, spellStealAbility:GetCastRange())
	local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), castRange + 300)
	local best, bestSkip = nil, nil
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnTargetAdvanced(enemyHero)
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and not Fu.IsMeepoClone(enemyHero)
		then
			local incoming, via, castAt = IncomingSpell(enemyHero, now)
			-- No known last spell: the old blind steal (a hero above level 10 has cast something), scored as a nuke.
			if incoming ~= nil or enemyHero:GetLevel() > 10 then
				local value, kind, source = 0, "unknown", "none"
				if incoming ~= nil then
					local info = nil
					if SpellStealRules.KIND[incoming] == nil then
						local okHandle, handle = pcall(function()
							return enemyHero:GetAbilityByName(incoming)
						end)
						info = StealInfo(okHandle and handle or nil)
					end
					value, kind, source = SpellStealRules.Value(incoming, info)
				end
				local steal, why, heldScore = SpellStealRules.Decide({
					incoming = incoming,
					incomingValue = value,
					incomingKind = kind,
					held = held.name,
					heldValue = held.value,
					heldCd = held.cd,
					heldDamage = held.damage,
					other = otherName,
					ultHold = ultHold,
				})
				local score = incoming ~= nil and value or SpellStealRules.BLIND_VALUE
				local pick = {
					hero = enemyHero,
					incoming = incoming,
					via = via,
					ago = castAt ~= nil and now - castAt or -1,
					score = score,
					kind = kind,
					source = source,
					heldScore = heldScore,
					why = why,
				}
				if steal then
					if best == nil or score > best.score then
						best = pick
					end
				elseif bestSkip == nil or score > bestSkip.score then
					bestSkip = pick
				end
			end
		end
	end
	local pick = best or bestSkip
	if pick == nil then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local from = ShortHero(pick.hero)
	if best ~= nil then
		bot._stealExpected = pick.incoming
		bot._stealFrom = from
		if now >= (bot._stealLogAt or -999) then
			bot._stealLogAt = now + 5
			pcall(
				print,
				string.format("[SHy-RUBICK] t=%.0f rubick steal-pick %s", now, PickLine(pick, held, otherName, from))
			)
		end
		return BOT_ACTION_DESIRE_HIGH, pick.hero
	end
	-- A skip: printed when the target, its spell, the held spell or the reason changes, at most every 3 s.
	local last = bot._stealSkip
	local changed = last == nil
		or last.from ~= from
		or last.incoming ~= pick.incoming
		or last.held ~= held.name
		or last.why ~= pick.why
	if changed and now >= (bot._stealSkipAt or -999) then
		bot._stealSkip = { from = from, incoming = pick.incoming, held = held.name, why = pick.why }
		bot._stealSkipAt = now + 3
		pcall(
			print,
			string.format("[SHy-RUBICK] t=%.0f rubick steal-skip %s", now, PickLine(pick, held, otherName, from))
		)
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
return X
