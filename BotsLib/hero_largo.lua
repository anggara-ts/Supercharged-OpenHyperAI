-- Largo: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
local Minion = require(GetScriptDirectory() .. "/FuncLib/hero/minion")
local LargoRules = require(GetScriptDirectory() .. "/FuncLib/systems/largo_rules")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
-- Talents (#198). The game file's order (7.42 npc_dota_hero_largo.txt, Ability15-22): level 10 largo_1 / largo_2,
-- 15 largo_3 / largo_4, 20 largo_8 / largo_6, 25 largo_7 / largo_5. Skill.GetTalentBuild: { 0, 10 } takes a
-- tier's first talent, { 10, 0 } its second. Taken: 10 Catchy Lick regen (largo_2), 15 Lick range and pull
-- (largo_4), 20 two Lick charges (largo_8), 25 twice the Frogstomp stomps (largo_5). The song talents (20: Groovin'
-- armor aura, 25: +30% song effects) wait until a game proves the bots play the songs on the beat.
local tTalentTree = { ["t25"] = { 10, 0 }, ["t20"] = { 0, 10 }, ["t15"] = { 10, 0 }, ["t10"] = { 10, 0 } }
-- Catchy Lick maxed first, Frogstomp second, Croak of Genius last (Dotabuff most picked order).
local nAbilityBuildList = { 1, 2, 1, 2, 1, 6, 1, 2, 2, 3, 6, 3, 3, 3, 6 }
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTree)
local sRoleItemsBuyList = {}
-- Pos 4 and 5: no Boots of Travel, Guardian Greaves are the one pair of boots.
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 7,677 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_enchanted_mango",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_holy_locket",
	"item_glimmer_cape",
	"item_mekansm",
	"item_lotus_orb",
	"item_guardian_greaves",
	"item_solar_crest",
	"item_kaya_and_sange",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 7,674 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_magic_stick",
	"item_double_branches",
	"item_enchanted_mango",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_holy_locket",
	"item_glimmer_cape",
	"item_mekansm",
	"item_lotus_orb",
	"item_guardian_greaves",
	"item_solar_crest",
	"item_kaya_and_sange",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 11,750 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_double_gauntlets",
	"item_double_branches",
	"item_bracer",
	"item_magic_wand",
	"item_soul_ring",
	"item_phase_boots",
	"item_kaya_and_sange",
	"item_ultimate_scepter",
	"item_black_king_bar",
	"item_shivas_guard",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_crellas_crozier",
	"item_sphere",
	"item_aghanims_shard",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 1,608 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_gauntlets",
	"item_quelling_blade",
	"item_magic_wand",
	"item_soul_ring",
	"item_phase_boots",
	"item_kaya_and_sange",
	"item_ultimate_scepter",
	"item_black_king_bar",
	"item_aghanims_shard",
	"item_shivas_guard",
	"item_ultimate_scepter_2",
	"item_phylactery",
	"item_bloodstone",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1 has 178 matches, built from pos 3 (11,750) (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_double_gauntlets",
	"item_double_branches",
	"item_bracer",
	"item_magic_wand",
	"item_soul_ring",
	"item_phase_boots",
	"item_kaya_and_sange",
	"item_ultimate_scepter",
	"item_black_king_bar",
	"item_shivas_guard",
	"item_travel_boots",
	"item_ultimate_scepter_2",
	"item_crellas_crozier",
	"item_sphere",
	"item_aghanims_shard",
	"item_moon_shard",
	"item_travel_boots_2",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_black_king_bar", "item_quelling_blade" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_tank" }, { "item_power_treads", "item_quelling_blade" }
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDeafaultAbility"] = false
X["bDeafaultItem"] = false
function X.MinionThink(hMinionUnit)
	Minion.MinionThink(hMinionUnit)
end
local catchyLickAbility = SafeAbility(bot:GetAbilityByName("largo_catchy_lick"), "largo_catchy_lick", "largo")
local frogstompAbility = SafeAbility(bot:GetAbilityByName("largo_frogstomp"), "largo_frogstomp", "largo")
local croakOfGeniusAbility =
	SafeAbility(bot:GetAbilityByName("largo_croak_of_genius"), "largo_croak_of_genius", "largo")
local amphibianRhapsodyAbility =
	SafeAbility(bot:GetAbilityByName("largo_amphibian_rhapsody"), "largo_amphibian_rhapsody", "largo")
local fightSongAbility = SafeAbility(bot:GetAbilityByName("largo_song_fight_song"), "largo_song_fight_song", "largo")
local doubleTimeAbility = SafeAbility(bot:GetAbilityByName("largo_song_double_time"), "largo_song_double_time", "largo")
local goodVibrationsAbility =
	SafeAbility(bot:GetAbilityByName("largo_song_good_vibrations"), "largo_song_good_vibrations", "largo")
local catchyLickDesire, catchyLickTarget, catchyLickReason
local frogstompDesire, frogstompLocation, frogstompReason, frogstompCount, frogstompTarget
local croakOfGeniusDesire, croakOfGeniusTarget, croakOfGeniusDamage, croakOfGeniusReason
local isAttacking = false
local botTarget
local nearbyAllies, nearbyEnemies
local isGoingOnSomeone

-- Amphibian Rhapsody (#198). On: the modifier below is on Largo (not the button's toggle state). The songs:
-- Bullbelly Blitz = fight song, Island Elixir = good vibrations, Hotfeet Hustle = double time.
local RHAPSODY_MODIFIER = "modifier_largo_amphibian_rhapsody_self"
local GROOVIN_MODIFIER = "modifier_largo_groovin"
local songByKey = { fight = fightSongAbility, vibes = goodVibrationsAbility, time = doubleTimeAbility }
local rhapsody = {
	on = false,
	onAt = 0,
	anchor = 0,
	lastBeat = 0,
	lastReasonAt = 0,
	toggleOrderAt = -99,
	first = "fight",
	second = nil,
	why = "none",
	pending = nil,
	strums = 0,
	hits = 0,
	reanchors = 0,
	noCast = 0,
	missStreak = 0,
	holdOwned = false,
	holdUntil = -99,
	stacks = 0,
}

-- [OHA-LARGO] lines, at most one per `key` every `interval` seconds.
local logAt = {}
local function LogLargo(key, interval, fmt, ...)
	local now = DotaTime()
	if logAt[key] ~= nil and now - logAt[key] < interval then
		return
	end
	logAt[key] = now
	print(string.format("[OHA-LARGO] t=%.0f largo " .. fmt, now, ...))
end
local function ShortName(unit)
	if unit == nil or unit:IsNull() then
		return "none"
	end
	local name = string.gsub(unit:GetUnitName(), "^npc_dota_hero_", "")
	return (string.gsub(name, "^npc_dota_", ""))
end
local function Bool(value)
	return value and "yes" or "no"
end

function X.SkillsComplement()
	local now = DotaTime()
	local isSinging = X.TrackRhapsody(now)
	local canUseAbility = not Fu.CanNotUseAbility(bot)
	local canStrum = isSinging and X.CanStrum()
	if not canUseAbility and not canStrum then
		return
	end
	isGoingOnSomeone = Fu.IsGoingOnSomeone(bot)
	isAttacking = Fu.IsAttacking(bot)
	botTarget = Fu.GetProperTarget(bot)
	nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	-- While the song is on, the beat comes first: a Lick or Frogstomp order on the beat frame would cost a stack
	-- (and whether the basic abilities are hidden during the song is not known yet, see the rhapsody-on line).
	if canStrum and X.RhapsodyThink(now) then
		return
	end
	if not canUseAbility then
		return
	end
	croakOfGeniusDesire, croakOfGeniusTarget, croakOfGeniusDamage, croakOfGeniusReason = X.ConsiderCroakOfGenius()
	if croakOfGeniusDesire > 0 then
		LogLargo(
			"croak",
			3,
			"croak-cast target=%s why=%s dmg=%d hp=%.2f",
			ShortName(croakOfGeniusTarget),
			croakOfGeniusReason or "?",
			croakOfGeniusDamage or 0,
			Fu.GetHP(croakOfGeniusTarget)
		)
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnEntity(croakOfGeniusAbility, croakOfGeniusTarget)
		return
	end
	catchyLickDesire, catchyLickTarget, catchyLickReason = X.ConsiderCatchLick()
	if catchyLickDesire > 0 then
		LogLargo(
			"lick",
			2,
			"lick-cast target=%s why=%s dist=%d",
			ShortName(catchyLickTarget),
			catchyLickReason or "?",
			GetUnitToUnitDistance(bot, catchyLickTarget)
		)
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnEntity(catchyLickAbility, catchyLickTarget)
		return
	end
	frogstompDesire, frogstompLocation, frogstompReason, frogstompCount, frogstompTarget = X.ConsiderFrogstomp()
	if frogstompDesire > 0 then
		LogLargo(
			"frogstomp",
			3,
			"frogstomp why=%s target=%s count=%d dist=%d mp=%.2f",
			frogstompReason or "?",
			ShortName(frogstompTarget),
			frogstompCount or 0,
			GetUnitToLocationDistance(bot, frogstompLocation),
			Fu.GetMP(bot)
		)
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(frogstompAbility, frogstompLocation)
		return
	end
	if not isSinging then
		local rhapsodyDesire, rhapsodyWhy = X.ConsiderAmphibianRhapsody(now)
		if rhapsodyDesire > 0 then
			rhapsody.toggleOrderAt = now
			LogLargo(
				"toggle",
				1,
				"rhapsody-toggle on why=%s song=%s second=%s mana=%d stacks=%d",
				rhapsodyWhy,
				rhapsody.first,
				tostring(rhapsody.second),
				bot:GetMana(),
				Fu.GetModifierCount(bot, GROOVIN_MODIFIER)
			)
			bot:Action_UseAbility(amphibianRhapsodyAbility)
			return
		end
	end
end

-- A non-self core hero of ours near the location (Largo leaves such a creep to it in lane).
function X.IsOtherCoreNear(location, radius)
	for _, allyHero in pairs(Fu.GetAlliesNearLoc(location, radius)) do
		if allyHero ~= bot and Fu.IsValidHero(allyHero) and not allyHero:IsIllusion() and Fu.IsCore(allyHero) then
			return true
		end
	end
	return false
end

-- Debuffs a dispel lick takes off an ally: { modifier, when } (when: nil = always, or a check of the ally's state).
-- The stun only when the lick is a strong dispel: it is a basic dispel (strong_dispel 0 in the game KV, no talent
-- changes it) and a stun needs a strong dispel, so licking a stunned ally only moved it and wasted the cast.
local ALLY_DISPELS = {
	{ "modifier_bane_nightmare", nil },
	{ "modifier_axe_battle_hunger", "retreating" },
	{ "modifier_bristleback_viscous_nasal_goo", "running" },
	{ "modifier_earth_spirit_magnetize", "not-fighting" },
	{ "modifier_phoenix_fire_spirit_burn", "fighting" },
	{ "modifier_life_stealer_open_wounds", "retreating" },
	{ "modifier_faceless_void_time_dilation_slow", "fighting" },
	{ "modifier_warlock_fatal_bonds", nil },
	{ "modifier_arc_warden_flux", "retreating" },
	{ "modifier_venomancer_venomous_gale", "retreating" },
	{ "modifier_stunned", "strong-dispel" },
}
-- Debuffs that already stop the ally fighting: pulling it costs nothing.
local STOPS_FIGHTING = { modifier_bane_nightmare = true, modifier_stunned = true }
-- Enemy buffs a lick dispels (basic dispel). Ghost Shroud's buff is modifier_necrolyte_ghost_shroud_active since
-- 7.42 (server.dll; modifier_necrolyte_sadist_active is gone).
local ENEMY_DISPELS = {
	"modifier_earthshaker_enchant_totem",
	"modifier_legion_commander_overwhelming_odds",
	"modifier_legion_commander_press_the_attack",
	"modifier_ogre_magi_bloodlust",
	"modifier_shredder_reactive_armor_bomb",
	"modifier_ursa_overpower",
	"modifier_necrolyte_ghost_shroud_active",
	"modifier_pugna_decrepify",
	"modifier_warlock_shadow_word",
	"modifier_abaddon_aphotic_shield",
}
function X.AllyDispelModifier(allyHero, allyIsGoingOnSomeone, allyIsRetreating)
	for _, entry in ipairs(ALLY_DISPELS) do
		local name, when = entry[1], entry[2]
		if Fu.GetModifierTime(allyHero, name) > 2 then
			if
				when == nil
				or when == "retreating" and allyIsRetreating
				or when == "running" and Fu.IsRunning(allyHero)
				or when == "not-fighting" and not allyIsGoingOnSomeone
				or when == "fighting" and allyIsGoingOnSomeone
				or when == "strong-dispel" and catchyLickAbility:GetSpecialValueInt("strong_dispel") > 0
			then
				return name
			end
		end
	end
	return nil
end

-- Castable now, or (onceShown) castable once the song is off: game 071 showed Lick, Frogstomp and Croak hidden while
-- he sings (rhapsody-on lickHidden=yes stompHidden=yes croakHidden=yes), so Fu.CanCastAbility says no then.
function X.SpellReady(ability, onceShown)
	if Fu.CanCastAbility(ability) then
		return true
	end
	return onceShown == true
		and ability ~= nil
		and not ability:IsNull()
		and ability:IsTrained()
		and (
			ability:IsFullyCastable()
			or ability:GetCooldownTimeRemaining() <= 0 and bot:GetMana() >= ability:GetManaCost()
		)
end

function X.ConsiderCatchLick(onceShown)
	if not X.SpellReady(catchyLickAbility, onceShown) then
		return BOT_ACTION_DESIRE_NONE, nil, nil
	end
	local castRange = catchyLickAbility:GetCastRange()
	local pullDistance = catchyLickAbility:GetSpecialValueInt("pull_distance")
	local pullDistanceAlly = catchyLickAbility:GetSpecialValueInt("pull_distance_ally")
	local damage = catchyLickAbility:GetSpecialValueInt("damage")
	local manaCost = catchyLickAbility:GetManaCost()
	local manaAfter = Fu.GetManaAfter(manaCost)
	local manaThreshold = Fu.GetManaThreshold(bot, manaCost, { frogstompAbility, croakOfGeniusAbility })
	for _, allyHero in pairs(nearbyAllies) do
		if
			Fu.IsValidHero(allyHero)
			and bot ~= allyHero
			and Fu.IsInRange(bot, allyHero, pullDistanceAlly + 300)
			and not Fu.IsInRange(bot, allyHero, pullDistanceAlly * 0.8)
			and not Fu.IsDisabled(allyHero)
			and not Fu.IsSuspiciousIllusion(allyHero)
			and not Fu.IsRealInvisible(allyHero)
			and not allyHero:IsChanneling()
		then
			if Fu.IsGoingOnSomeone(allyHero) then
				local allyTarget = Fu.GetProperTarget(allyHero)
				if
					Fu.IsValidHero(allyTarget)
					and allyHero:IsFacingLocation(allyTarget:GetLocation(), 15)
					and GetUnitToUnitDistance(allyHero, allyTarget) > allyHero:GetAttackRange() + 50
					and GetUnitToUnitDistance(allyHero, allyTarget) < allyHero:GetAttackRange() + 700
					and not Fu.IsSuspiciousIllusion(allyTarget)
					and not allyTarget:IsFacingLocation(allyHero:GetLocation(), 40)
					and #nearbyAllies >= 3
				then
					local lineInfo =
						PointToLineDistance(allyTarget:GetLocation(), allyHero:GetLocation(), bot:GetLocation())
					if lineInfo and lineInfo.within and lineInfo.distance <= 600 then
						return BOT_ACTION_DESIRE_HIGH, allyHero, "ally-engage"
					end
					lineInfo = PointToLineDistance(bot:GetLocation(), allyHero:GetLocation(), allyTarget:GetLocation())
					if lineInfo and lineInfo.within and lineInfo.distance <= 600 then
						return BOT_ACTION_DESIRE_HIGH, allyHero, "ally-engage"
					end
				end
			end
			local enemiesNearAlly = Fu.GetEnemiesNearLoc(allyHero:GetLocation(), 900)
			if
				Fu.IsRetreating(allyHero)
				and #enemiesNearAlly > 0
				and allyHero:IsFacingLocation(Fu.GetTeamFountain(), 30)
				and allyHero:DistanceFromFountain() > 1200
				and allyHero:WasRecentlyDamagedByAnyHero(5.0)
			then
				local lineInfo = PointToLineDistance(Fu.GetTeamFountain(), allyHero:GetLocation(), bot:GetLocation())
				if lineInfo and lineInfo.within and lineInfo.distance <= 600 then
					return BOT_ACTION_DESIRE_HIGH, allyHero, "ally-save"
				end
			end
			if Fu.IsStuck(allyHero) then
				return BOT_ACTION_DESIRE_HIGH, allyHero, "ally-unstuck"
			end
		end
		if
			Fu.IsValidHero(allyHero)
			and bot ~= allyHero
			and Fu.IsInRange(bot, allyHero, castRange)
			and not allyHero:IsMagicImmune()
			and not allyHero:IsIllusion()
			and not allyHero:IsChanneling()
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and allyHero:WasRecentlyDamagedByAnyHero(2.0)
		then
			local allyIsGoingOnSomeone = Fu.IsGoingOnSomeone(allyHero)
			local debuff = X.AllyDispelModifier(allyHero, allyIsGoingOnSomeone, Fu.IsRetreating(allyHero))
			if debuff ~= nil then
				-- No dispel that drags an ally fighting in range of its target out of that range (#198).
				local allyTarget = Fu.GetProperTarget(allyHero)
				local distToTarget = Fu.IsValidHero(allyTarget) and GetUnitToUnitDistance(allyHero, allyTarget) or nil
				if
					LargoRules.DispelPullOk(
						allyIsGoingOnSomeone,
						distToTarget,
						allyHero:GetAttackRange(),
						pullDistanceAlly,
						STOPS_FIGHTING[debuff] == true
					)
				then
					return BOT_ACTION_DESIRE_HIGH, allyHero, "ally-dispel:" .. string.gsub(debuff, "^modifier_", "")
				end
				LogLargo(
					"lick-hold",
					5,
					"lick-hold ally=%s debuff=%s distToTarget=%d range=%d",
					ShortName(allyHero),
					debuff,
					distToTarget or -1,
					allyHero:GetAttackRange()
				)
			end
		end
	end
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanBeAttacked(enemyHero)
			and Fu.IsInRange(bot, enemyHero, castRange)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanCastOnTargetAdvanced(enemyHero)
			and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			if
				Fu.CanKillTarget(enemyHero, damage, DAMAGE_TYPE_MAGICAL)
				and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
				and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
				and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
				and not enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero, "kill"
			end
			-- An enemy buff is dispelled at any HP of Largo's (it used to wait until Largo was under 90% HP).
			for _, buffName in ipairs(ENEMY_DISPELS) do
				if Fu.GetModifierTime(enemyHero, buffName) > 2 then
					return BOT_ACTION_DESIRE_HIGH, enemyHero, "enemy-dispel:" .. string.gsub(buffName, "^modifier_", "")
				end
			end
		end
	end
	if isGoingOnSomeone then
		if
			Fu.IsValidHero(botTarget)
			and Fu.CanBeAttacked(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.CanCastOnTargetAdvanced(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and not Fu.IsInRange(bot, botTarget, pullDistance)
			and Fu.IsChasingTarget(bot, botTarget)
			and not Fu.IsDisabled(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, "chase"
		end
	end
	local nearbyCreeps = bot:GetNearbyCreeps(Min(castRange + 300, 1600), true)
	if Fu.IsPushing(bot) or Fu.IsDefending(bot) or Fu.IsFarming(bot) then
		if #nearbyAllies <= 2 and #nearbyEnemies == 0 and isAttacking and manaAfter > manaThreshold + 0.1 then
			local bestCreep = nil
			local bestDamageRatio = 0
			for _, creep in pairs(nearbyCreeps) do
				if
					Fu.IsValid(creep)
					and Fu.CanBeAttacked(creep)
					and not Fu.IsRoshan(creep)
					and not Fu.IsTormentor(creep)
					and not Fu.IsOtherAllysTarget(creep)
					and creep:GetHealth() > 0
				then
					local damageRatio = creep:GetActualIncomingDamage(damage, DAMAGE_TYPE_MAGICAL) / creep:GetHealth()
					if damageRatio > bestDamageRatio then
						bestCreep = creep
						bestDamageRatio = damageRatio
					end
				end
			end
			if bestCreep then
				return BOT_ACTION_DESIRE_HIGH, bestCreep, "farm"
			end
		end
	end
	if Fu.IsLaning(bot) and Fu.IsInLaningPhase() and manaAfter > manaThreshold then
		for _, creep in pairs(nearbyCreeps) do
			if
				Fu.IsValid(creep)
				and Fu.CanBeAttacked(creep)
				and Fu.CanKillTarget(creep, damage, DAMAGE_TYPE_MAGICAL)
				-- A support leaves the last hit to a core of ours near the creep (#198: this called
				-- IsThereCoreInLocation, which never existed in Fu, and stopped the whole think with a script error).
				and (Fu.IsCore(bot) or not X.IsOtherCoreNear(creep:GetLocation(), 650))
				and not Fu.IsOtherAllysTarget(creep)
			then
				local creepName = creep:GetUnitName()
				if string.find(creepName, "ranged") then
					local aoeLocation = bot:FindAoELocation(true, true, creep:GetLocation(), 0, 600, 0, 0)
					if aoeLocation.count > 0 or Fu.IsUnitTargetedByTower(creep, false) then
						return BOT_ACTION_DESIRE_HIGH, creep, "lane-lasthit"
					end
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil, nil
end

function X.ConsiderFrogstomp(onceShown)
	if not X.SpellReady(frogstompAbility, onceShown) then
		return BOT_ACTION_DESIRE_NONE, 0, nil, 0
	end
	local castRange = frogstompAbility:GetCastRange()
	local radius = frogstompAbility:GetSpecialValueInt("radius")
	-- Datafeed hero_id=155: the froglings land after delay 0.5s (cast point 0.2s) and stomp every stomp_interval 1s
	-- (4-7 stomps) with a 0.1s ministun and a 12-30% slow inside radius 350.
	local landDelay = frogstompAbility:GetCastPoint() + frogstompAbility:GetSpecialValueFloat("delay")
	local manaCost = frogstompAbility:GetManaCost()
	local manaAfter = Fu.GetManaAfter(manaCost)
	local manaThreshold = Fu.GetManaThreshold(bot, manaCost, { catchyLickAbility, croakOfGeniusAbility })
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanBeAttacked(enemyHero)
			and Fu.IsInRange(bot, enemyHero, castRange)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and enemyHero:IsChanneling()
		then
			return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation(), "channel", 1
		end
	end
	-- Fights (#198): the spot that catches two or more heroes, else Largo's target where it will be when the froglings
	-- land (it used to wait for a disabled target or one moving at 250 or slower).
	if isGoingOnSomeone or Fu.IsInTeamFight(bot, 1200) then
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius * 0.8, landDelay, 0)
		if aoeLocation.count >= 2 and GetUnitToLocationDistance(bot, aoeLocation.targetloc) <= castRange then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc, "fight-aoe", aoeLocation.count
		end
		if
			isGoingOnSomeone
			and Fu.IsValidHero(botTarget)
			and Fu.CanBeAttacked(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			local targetLocation = botTarget:GetLocation()
			if not Fu.IsDisabled(botTarget) then
				targetLocation = Fu.GetCorrectLoc(botTarget, landDelay)
			end
			if GetUnitToLocationDistance(bot, targetLocation) <= castRange then
				return BOT_ACTION_DESIRE_HIGH, targetLocation, "fight-target", 1, botTarget
			end
		end
	end
	if Fu.IsRetreating(bot) and not Fu.IsRealInvisible(bot) and Fu.IsRunning(bot) then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.CanBeAttacked(enemyHero)
				and Fu.IsInRange(bot, enemyHero, radius * 2)
				and not Fu.IsInRange(bot, enemyHero, radius * 0.8)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and bot:WasRecentlyDamagedByHero(enemyHero, 3.0)
			then
				return BOT_ACTION_DESIRE_HIGH, (bot:GetLocation() + enemyHero:GetLocation()) / 2, "retreat", 1
			end
		end
	end
	-- Lane harass (#198, game 071: no Frogstomp on the laning enemy with full mana): spare mana, an enemy hero inside
	-- the cast range (800, datafeed hero_id=155), Largo not inside an enemy tower's range and not outnumbered.
	if Fu.IsInLaningPhase() or Fu.IsLaning(bot) then
		local harassLocation, harassCount, harassTarget = X.LaneStompSpot(castRange, radius, landDelay)
		if harassLocation ~= nil then
			local laneStompOk = LargoRules.LaneStompOk({
				mpRatio = Fu.GetMP(bot),
				manaAfterOk = manaAfter > manaThreshold,
				inEnemyTowerRange = X.IsInEnemyTowerRange(150),
				enemiesNear = #Fu.GetEnemiesNearLoc(bot:GetLocation(), 1200),
				alliesNear = #Fu.GetAlliesNearLoc(bot:GetLocation(), 1200),
				retreating = Fu.IsRetreating(bot),
			})
			if laneStompOk then
				return BOT_ACTION_DESIRE_HIGH, harassLocation, "harass", harassCount, harassTarget
			end
		end
	end
	local nearbyCreeps = bot:GetNearbyCreeps(Min(castRange + 300, 1600), true)
	if
		Fu.IsPushing(bot)
		and #nearbyAllies <= 2
		and isAttacking
		and manaAfter > manaThreshold
		and #nearbyEnemies == 0
	then
		for _, creep in pairs(nearbyCreeps) do
			if Fu.IsValid(creep) and Fu.CanBeAttacked(creep) and not Fu.IsRunning(creep) then
				local aoeLocation = bot:FindAoELocation(true, false, creep:GetLocation(), 0, radius, 0, 0)
				if aoeLocation.count >= 4 then
					return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc, "push", aoeLocation.count
				end
			end
		end
	end
	if Fu.IsDefending(bot) and isAttacking and manaAfter > manaThreshold then
		for _, creep in pairs(nearbyCreeps) do
			if Fu.IsValid(creep) and Fu.CanBeAttacked(creep) and not Fu.IsRunning(creep) then
				local aoeLocation = bot:FindAoELocation(true, false, creep:GetLocation(), 0, radius, 0, 0)
				if
					aoeLocation.count >= 4
					or aoeLocation.count >= 3 and string.find(creep:GetUnitName(), "upgraded")
				then
					return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc, "defend", aoeLocation.count
				end
			end
		end
	end
	if Fu.IsFarming(bot) and isAttacking and manaAfter > manaThreshold then
		for _, creep in pairs(nearbyCreeps) do
			if Fu.IsValid(creep) and Fu.CanBeAttacked(creep) and not Fu.IsRunning(creep) then
				local aoeLocation = bot:FindAoELocation(true, false, creep:GetLocation(), 0, radius, 0, 0)
				if
					aoeLocation.count >= 3
					or aoeLocation.count >= 2 and creep:IsAncientCreep()
					or aoeLocation.count >= 1 and creep:GetHealth() >= 550
				then
					return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc, "farm", aoeLocation.count
				end
			end
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanBeAttacked(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
			and manaAfter > manaThreshold
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation(), "roshan", 1
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if
			Fu.IsTormentor(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
			and manaAfter > manaThreshold
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation(), "tormentor", 1
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0, nil, 0
end

-- Largo wants Croak of Genius on himself (#198): no buff yet, and he is singing, about to start a song, or starting a
-- Lick + Frogstomp combo on a hero. The buff cuts his mana costs by 15% for its whole 15-30s (mana_cost_reduction 15,
-- duration 15/20/25/30; "Duration is not reduced for Largo himself", datafeed hero_id=155).
function X.CroakSelfWanted()
	if bot:HasModifier("modifier_largo_croak_of_genius_buff") then
		return false
	end
	if bot:HasModifier(RHAPSODY_MODIFIER) then
		return true
	end
	if Fu.CanCastAbility(amphibianRhapsodyAbility) then
		local first = LargoRules.ChooseSongs(X.RhapsodySituation(amphibianRhapsodyAbility:GetSpecialValueInt("radius")))
		if first ~= nil then
			return true
		end
	end
	return isGoingOnSomeone
		and Fu.IsValidHero(botTarget)
		and Fu.IsInRange(bot, botTarget, 1000)
		and Fu.CanCastAbility(catchyLickAbility)
		and Fu.CanCastAbility(frogstompAbility)
end

-- Largo inside an enemy tower's attack range (+ margin): the tower's range plus both bounding radii.
function X.IsInEnemyTowerRange(margin)
	for _, tower in pairs(bot:GetNearbyTowers(1600, true)) do
		if Fu.IsValidBuilding(tower) then
			local towerRange = (tower:GetAttackRange() or 700) + tower:GetBoundingRadius() + bot:GetBoundingRadius()
			if GetUnitToUnitDistance(bot, tower) <= towerRange + margin then
				return true
			end
		end
	end
	return false
end

-- Where a lane-harass Frogstomp goes: the spot that catches two heroes, else the weakest enemy hero in range where it
-- will be when the froglings land. Returns location, count, target, or nil.
function X.LaneStompSpot(castRange, radius, landDelay)
	local target = nil
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanBeAttacked(enemyHero)
			and Fu.IsInRange(bot, enemyHero, castRange)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and (target == nil or Fu.GetHP(enemyHero) < Fu.GetHP(target))
		then
			target = enemyHero
		end
	end
	if target == nil then
		return nil, 0, nil
	end
	local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius * 0.8, landDelay, 0)
	if aoeLocation.count >= 2 and GetUnitToLocationDistance(bot, aoeLocation.targetloc) <= castRange then
		return aoeLocation.targetloc, aoeLocation.count, target
	end
	local targetLocation = Fu.IsDisabled(target) and target:GetLocation() or Fu.GetCorrectLoc(target, landDelay)
	if GetUnitToLocationDistance(bot, targetLocation) <= castRange then
		return targetLocation, 1, target
	end
	return nil, 0, nil
end

function X.ConsiderCroakOfGenius()
	if not Fu.CanCastAbility(croakOfGeniusAbility) then
		return BOT_ACTION_DESIRE_NONE, nil, 0, nil
	end
	local castRange = croakOfGeniusAbility:GetCastRange()
	local bestAlly = nil
	local bestDamage = 0
	for _, allyHero in pairs(nearbyAllies) do
		if
			Fu.IsValidHero(allyHero)
			and allyHero ~= bot
			and Fu.IsInRange(bot, allyHero, castRange + 300)
			and Fu.IsGoingOnSomeone(allyHero)
			and not allyHero:IsIllusion()
			and not allyHero:IsSilenced()
			and not allyHero:HasModifier("modifier_doom_bringer_doom_aura_enemy")
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and not allyHero:HasModifier("modifier_largo_croak_of_genius_buff")
			and not allyHero:HasModifier("modifier_silencer_curse_of_the_silent")
			and not allyHero:HasModifier("modifier_teleporting")
		then
			local allyTarget = Fu.GetProperTarget(allyHero)
			if
				Fu.IsValidHero(allyTarget)
				and Fu.CanBeAttacked(allyTarget)
				and not Fu.IsSuspiciousIllusion(allyTarget)
			then
				local estimatedDamage = allyHero:GetEstimatedDamageToTarget(true, allyTarget, 5.0, DAMAGE_TYPE_MAGICAL)
				if estimatedDamage > bestDamage then
					bestAlly = allyHero
					bestDamage = estimatedDamage
				end
			end
		end
	end
	local alone = true
	for _, allyHero in pairs(nearbyAllies) do
		if
			allyHero ~= bot
			and Fu.IsValidHero(allyHero)
			and not allyHero:IsIllusion()
			and Fu.IsInRange(bot, allyHero, 1200)
		then
			alone = false
			break
		end
	end
	local target, why = LargoRules.CroakTarget({
		hasShard = Fu.HasAghanimsShard(bot),
		allyWants = bestAlly ~= nil,
		allyIsCore = bestAlly ~= nil and Fu.IsCore(bestAlly),
		selfWants = X.CroakSelfWanted(),
		alone = alone,
	})
	if target == "ally" then
		return BOT_ACTION_DESIRE_HIGH, bestAlly, bestDamage, why
	end
	if target == "self" then
		return BOT_ACTION_DESIRE_HIGH, bot, 0, why
	end
	return BOT_ACTION_DESIRE_NONE, nil, 0, nil
end

function X.IsGoodToHeal(hero)
	return not hero:HasModifier("modifier_abaddon_borrowed_time")
		and not hero:HasModifier("modifier_doom_bringer_doom_aura_enemy")
		and not hero:HasModifier("modifier_ice_blast")
		and not hero:HasModifier("modifier_necrolyte_reapers_scythe")
		and hero:GetUnitName() ~= "npc_dota_hero_medusa"
		and hero:GetUnitName() ~= "npc_dota_hero_huskar"
end

-- Strumming needs no free action slot or finished cast (the songs are instant, DOTA_ABILITY_BEHAVIOR_IMMEDIATE in
-- the game file), only a Largo who can cast at all. Not while channeling: the songs have no IGNORE_CHANNEL, a strum
-- would break a TP.
function X.CanStrum()
	return bot:IsAlive()
		and not bot:IsChanneling()
		and not bot:IsStunned()
		and not bot:IsSilenced()
		and not bot:IsHexed()
		and not bot:IsNightmared()
end

-- Why a song can't be strummed now, or nil.
function X.SongBlockReason(song, manaNeeded)
	if song == nil or song:IsNull() then
		return "nil"
	end
	if song:GetCooldownTimeRemaining() > 0 then
		return "cooldown"
	end
	if bot:GetMana() < (manaNeeded or song:GetManaCost()) then
		return "mana"
	end
	return nil
end

-- What the songs could do now (LargoRules.ChooseSongs' input). Largo counts as an ally of his own.
function X.RhapsodySituation(radius)
	local situation = {
		enemies = 0,
		fighting = isGoingOnSomeone or Fu.IsInTeamFight(bot, 1200),
		hurtHp = 1,
		escaping = false,
		chasing = false,
		objective = false,
		double = amphibianRhapsodyAbility:GetSpecialValueInt("double_song") > 0,
	}
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.IsInRange(bot, enemyHero, radius)
			and not Fu.IsSuspiciousIllusion(enemyHero)
		then
			situation.enemies = situation.enemies + 1
		end
	end
	local allies = {}
	local hasSelf = false
	for _, allyHero in pairs(nearbyAllies) do
		allies[#allies + 1] = allyHero
		hasSelf = hasSelf or allyHero == bot
	end
	if not hasSelf then
		allies[#allies + 1] = bot
	end
	for _, allyHero in ipairs(allies) do
		if
			Fu.IsValidHero(allyHero)
			and (allyHero == bot or Fu.IsInRange(bot, allyHero, radius))
			and not allyHero:IsIllusion()
			and not allyHero:HasModifier("modifier_teleporting")
		then
			local allyHp = Fu.GetHP(allyHero)
			if
				allyHp < situation.hurtHp
				and X.IsGoodToHeal(allyHero)
				and (allyHero:WasRecentlyDamagedByAnyHero(4.0) or situation.enemies > 0)
			then
				situation.hurtHp = allyHp
			end
			local allyTarget = Fu.GetProperTarget(allyHero)
			if allyHero ~= bot and Fu.IsGoingOnSomeone(allyHero) then
				if
					Fu.IsValidHero(allyTarget)
					and not Fu.IsSuspiciousIllusion(allyTarget)
					and GetUnitToUnitDistance(allyHero, allyTarget) <= radius
				then
					situation.fighting = true
					if
						Fu.IsChasingTarget(allyHero, allyTarget)
						and not Fu.IsDisabled(allyTarget)
						and GetUnitToUnitDistance(allyHero, allyTarget) > allyHero:GetAttackRange() + 50
					then
						situation.chasing = true
					end
				end
			end
			if
				Fu.IsRetreating(allyHero)
				and allyHero:WasRecentlyDamagedByAnyHero(3.0)
				and #Fu.GetEnemiesNearLoc(allyHero:GetLocation(), 900) > 0
			then
				situation.escaping = true
			end
			if
				allyHero ~= bot
				and (Fu.IsDoingRoshan(allyHero) or Fu.IsDoingTormentor(allyHero))
				and (Fu.IsRoshan(allyTarget) or Fu.IsTormentor(allyTarget))
				and Fu.IsInRange(allyHero, allyTarget, 1200)
				and Fu.IsAttacking(allyHero)
			then
				situation.objective = true
			end
		end
	end
	return situation
end

-- Toggle the song on: a reason to sing and mana for a few beats (the songs cost 25/35/45, datafeed hero_id=155).
function X.ConsiderAmphibianRhapsody(now)
	if
		not Fu.CanCastAbility(amphibianRhapsodyAbility)
		or amphibianRhapsodyAbility:GetToggleState()
		or now - rhapsody.toggleOrderAt < 1
		or now < rhapsody.holdUntil
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local situation = X.RhapsodySituation(amphibianRhapsodyAbility:GetSpecialValueInt("radius"))
	local first, second, why = LargoRules.ChooseSongs(situation)
	if first == nil then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	if Fu.IsRealInvisible(bot) and not situation.fighting then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local song = songByKey[first]
	local songCost = math.max(song:GetManaCost(), 25)
	if not LargoRules.CanStartSong(bot:GetMana(), songCost, second and 2 or 1) then
		LogLargo("start-mana", 5, "rhapsody-skip why=mana song=%s mana=%d cost=%d", first, bot:GetMana(), songCost)
		return BOT_ACTION_DESIRE_NONE, nil
	end
	rhapsody.first, rhapsody.second, rhapsody.why = first, second, why
	return BOT_ACTION_DESIRE_HIGH, why
end

-- Every think, before any gate: notices the song starting and ending, the Groovin' stacks, and what the last
-- strum did. Returns whether the song is on.
function X.TrackRhapsody(now)
	local isOn = bot:HasModifier(RHAPSODY_MODIFIER)
	local stacks = Fu.GetModifierCount(bot, GROOVIN_MODIFIER)
	if isOn and not rhapsody.on then
		rhapsody.on = true
		rhapsody.onAt = now
		rhapsody.anchor = now
		rhapsody.lastBeat = now
		rhapsody.lastReasonAt = now
		rhapsody.pending = nil
		rhapsody.strums, rhapsody.hits, rhapsody.reanchors, rhapsody.noCast = 0, 0, 0, 0
		rhapsody.missStreak = 0
		-- Settles what the game files can't: are the basic abilities hidden during the song, are the songs
		-- unhidden, trained and castable.
		local song = songByKey[rhapsody.first] or fightSongAbility
		print(
			string.format(
				"[OHA-LARGO] t=%.0f largo rhapsody-on at=%.2f stacks=%d lickHidden=%s stompHidden=%s croakHidden=%s songHidden=%s songLevel=%d songCastable=%s songCost=%d toggle=%s",
				now,
				now,
				stacks,
				Bool(catchyLickAbility:IsHidden()),
				Bool(frogstompAbility:IsHidden()),
				Bool(croakOfGeniusAbility:IsHidden()),
				Bool(song:IsHidden()),
				song:GetLevel(),
				Bool(song:IsFullyCastable()),
				song:GetManaCost(),
				Bool(amphibianRhapsodyAbility:GetToggleState())
			)
		)
	elseif not isOn and rhapsody.on then
		rhapsody.on = false
		print(
			string.format(
				"[OHA-LARGO] t=%.0f largo rhapsody-off held=%.1f strums=%d hits=%d reanchors=%d stacks=%d",
				now,
				now - rhapsody.onAt,
				rhapsody.strums,
				rhapsody.hits,
				rhapsody.reanchors,
				stacks
			)
		)
	end
	if isOn then
		if rhapsody.pending ~= nil then
			X.CheckStrum(now, stacks)
		elseif stacks ~= rhapsody.stacks then
			-- A change with no strum of ours (a stack lost on a missed beat): when it happens shows where the beat is.
			LogLargo(
				"groovin",
				1,
				"groovin-change from=%d to=%d phase=%.2f frac=%.2f",
				rhapsody.stacks,
				stacks,
				(now - rhapsody.onAt) % 1,
				now % 1
			)
		end
	end
	rhapsody.stacks = stacks
	return isOn
end

-- What the strum in flight did: one [OHA-LARGO] strum line per strum, written once the result is known.
-- Game 071 18:00: in a retreat the strum orders were lost (cast=no) and the song was turned off. A song order is
-- held for a moment against our own mode Thinks (bot._castHoldUntil: OhaCastGuard skips every SafeCall-wrapped
-- Think, and the item think calls X.CastHoldTick instead of SkillsComplement), and pushed again while the beat's
-- window lasts. Valve's own retreat Think (mode_retreat_generic.lua has no Think) is not held: the re-push covers it.
local STRUM_HOLD = 0.12
function X.HoldForStrum(now)
	if bot._castHoldUntil == nil or bot._castHoldUntil < now or rhapsody.holdOwned then
		bot._castHoldUntil = now + STRUM_HOLD
		rhapsody.holdOwned = true
		return "push-hold"
	end
	return "push"
end
function X.ReleaseStrumHold()
	if rhapsody.holdOwned then
		bot._castHoldUntil = nil
		rhapsody.holdOwned = false
	end
end
function X.CastHoldTick()
	X.TrackRhapsody(DotaTime())
end
-- Largo runs from a fight: a lost order or a blocked beat then does not end the song (he needs the run and heal songs).
function X.IsEscaping()
	return Fu.IsRetreating(bot) or rhapsody.why ~= nil and string.find(rhapsody.why, "escape", 1, true) ~= nil
end

function X.CheckStrum(now, stacks)
	local pending = rhapsody.pending
	local since = now - pending.at
	-- The strum went out: the songs' shared cooldown runs, or the mana is gone.
	local manaSpent = pending.mana - bot:GetMana()
	if not pending.cast and (pending.song:GetCooldownTimeRemaining() > 0 or manaSpent >= pending.cost * 0.6) then
		pending.cast = true
		pending.castAt = now
		pending.cdSeen = pending.song:GetCooldownTimeRemaining()
		X.ReleaseStrumHold()
	end
	-- Not out yet: the order was lost (a mode's move replaced it). Again, while the beat's window lasts.
	if
		not pending.cast
		and X.CanStrum()
		and now - pending.lastPushAt >= 0.06
		and LargoRules.ShouldRepush(now - pending.beat, pending.attempts)
		and X.SongBlockReason(pending.song) == nil
	then
		pending.attempts = pending.attempts + 1
		pending.lastPushAt = now
		bot:ActionPush_UseAbility(pending.song)
		X.HoldForStrum(now)
		return
	end
	if pending.cost2 ~= nil and manaSpent >= (pending.cost + pending.cost2) * 0.8 then
		pending.both = true
	end
	-- Scepter: a second song that did not go out with the first (the shared 0.2s cooldown) gets another try while
	-- the beat's grace lasts.
	if
		pending.second ~= nil
		and not pending.both
		and not pending.retried
		and pending.cast
		and X.CanStrum()
		and now - pending.beat <= LargoRules.GRACE * 0.9
		and X.SongBlockReason(pending.second) == nil
	then
		pending.retried = true
		bot:ActionPush_UseAbility(pending.second)
		return
	end
	local result = LargoRules.StrumResult(pending.before, stacks, LargoRules.MAX_STACKS)
	if since < 0.15 or result == "miss" and since < 0.5 then
		return
	end
	rhapsody.strums = rhapsody.strums + 1
	if result == "hit" then
		rhapsody.hits = rhapsody.hits + 1
	end
	local castDelay = pending.cast and pending.castAt - pending.beat or -1
	-- Only a strum that went out on time says anything about the beat (a late or lost order does not, game 071).
	local castOnTime = pending.cast and castDelay <= LargoRules.GRACE
	if result == "miss" and castOnTime then
		rhapsody.missStreak = rhapsody.missStreak + 1
	elseif result ~= "miss" then
		rhapsody.missStreak = 0
	end
	if pending.cast then
		rhapsody.noCast = 0
	elseif LargoRules.CountsAsNoCast(false, nil, X.IsEscaping()) then
		if LargoRules.CountsAsNoCast(false, blocked, X.IsEscaping()) then
			rhapsody.noCast = rhapsody.noCast + 1
		end
	end
	local reanchor = "no"
	if LargoRules.MayReanchor(rhapsody.reanchors, rhapsody.hits, rhapsody.missStreak) then
		local newAnchor = LargoRules.Reanchor(rhapsody.anchor, result, castOnTime, LargoRules.REANCHOR_SHIFT)
		if newAnchor ~= rhapsody.anchor then
			rhapsody.anchor = newAnchor
			rhapsody.reanchors = rhapsody.reanchors + 1
			rhapsody.missStreak = 0
			reanchor = "yes"
			if
				not LargoRules.MayReanchor(rhapsody.reanchors, rhapsody.hits, rhapsody.missStreak)
				and rhapsody.hits == 0
			then
				-- A whole beat swept with no hit: the stacks don't tell, keep the toggle-on beat from now on.
				rhapsody.anchor = rhapsody.onAt
				reanchor = "stop"
			end
		end
	end
	print(
		string.format(
			"[OHA-LARGO] t=%.0f largo strum song=%s second=%s why=%s before=%d after=%d hit=%s cast=%s via=%s attempts=%d castDelay=%.2f cdSeen=%.2f double=%s phase=%.2f frac=%.2f late=%.2f reanchor=%s n=%d hits=%d",
			now,
			pending.key,
			tostring(pending.key2),
			rhapsody.why,
			pending.before,
			stacks,
			result,
			Bool(pending.cast),
			pending.via,
			pending.attempts,
			castDelay,
			pending.cdSeen or -1,
			pending.key2 == nil and "none" or pending.both and "both" or pending.retried and "retried" or "first-only",
			(pending.at - rhapsody.onAt) % 1,
			pending.at % 1,
			pending.at - pending.beat,
			reanchor,
			rhapsody.strums,
			rhapsody.hits
		)
	)
	rhapsody.pending = nil
end

-- The Lick or Frogstomp to end the song for, or nil: "lick" | "stomp", its target, the spell's reason.
function X.SongBreakPlay()
	local stacks = Fu.GetModifierCount(bot, GROOVIN_MODIFIER)
	local alliesNear = 0
	for _, allyHero in pairs(nearbyAllies) do
		if
			allyHero ~= bot
			and Fu.IsValidHero(allyHero)
			and not allyHero:IsIllusion()
			and Fu.IsInRange(bot, allyHero, 900)
		then
			alliesNear = alliesNear + 1
		end
	end
	local lickDesire, lickTarget, lickWhy = X.ConsiderCatchLick(true)
	if lickDesire > 0 and LargoRules.BreakSongFor(lickWhy, stacks, 1, alliesNear) then
		return "lick", lickTarget, lickWhy
	end
	local stompDesire, _, stompWhy, stompCount, stompTarget = X.ConsiderFrogstomp(true)
	if stompDesire > 0 and LargoRules.BreakSongFor(stompWhy, stacks, stompCount, alliesNear) then
		return "stomp", stompTarget, stompWhy
	end
	return nil, nil, nil
end

-- While the song is on: pick the songs, end the song when there is nothing to sing for, strum on the beat.
-- Returns whether it gave an order.
function X.RhapsodyThink(now)
	local first, second, why =
		LargoRules.ChooseSongs(X.RhapsodySituation(amphibianRhapsodyAbility:GetSpecialValueInt("radius")))
	if first ~= nil then
		rhapsody.lastReasonAt = now
		if first ~= rhapsody.first or second ~= rhapsody.second then
			LogLargo("song", 2, "song-change song=%s second=%s why=%s", first, tostring(second), why)
		end
		rhapsody.first, rhapsody.second, rhapsody.why = first, second, why
	end
	-- A Catchy Lick or Frogstomp worth more than the song (game 071, maintainer): end the song for it. The spells show
	-- again once the song is off and the normal rules cast them; the toggle-on rule starts the song again after.
	if Fu.CanCastAbility(amphibianRhapsodyAbility) and now - rhapsody.toggleOrderAt >= 0.5 then
		local play, playTarget, playWhy = X.SongBreakPlay()
		if play ~= nil then
			rhapsody.toggleOrderAt = now
			LogLargo(
				"toggle",
				1,
				"rhapsody-toggle off why=%s target=%s play=%s held=%.1f stacks=%d strums=%d hits=%d mana=%d",
				play,
				ShortName(playTarget),
				playWhy,
				now - rhapsody.onAt,
				Fu.GetModifierCount(bot, GROOVIN_MODIFIER),
				rhapsody.strums,
				rhapsody.hits,
				bot:GetMana()
			)
			bot:Action_UseAbility(amphibianRhapsodyAbility)
			return true
		end
	end
	local firstSong = songByKey[rhapsody.first] or fightSongAbility
	local offWhy = LargoRules.ToggleOffReason(
		now,
		rhapsody.lastReasonAt,
		bot:GetMana() >= firstSong:GetManaCost(),
		LargoRules.TOGGLE_OFF_AFTER,
		rhapsody.noCast
	)
	if offWhy ~= nil and Fu.CanCastAbility(amphibianRhapsodyAbility) and now - rhapsody.toggleOrderAt >= 0.5 then
		rhapsody.toggleOrderAt = now
		if offWhy == "no-cast" then
			-- The songs don't go out: no new song for a while rather than a disarmed, silent Largo.
			rhapsody.holdUntil = now + LargoRules.NO_CAST_HOLD
		end
		LogLargo(
			"toggle",
			1,
			"rhapsody-toggle off why=%s held=%.1f strums=%d hits=%d mana=%d",
			offWhy,
			now - rhapsody.onAt,
			rhapsody.strums,
			rhapsody.hits,
			bot:GetMana()
		)
		bot:Action_UseAbility(amphibianRhapsodyAbility)
		return true
	end
	if rhapsody.pending ~= nil then
		return false
	end
	-- Every beat while the song is on (also in the seconds before it ends: the Groovin' stacks are armor and
	-- cheaper songs), with the songs chosen last.
	local beatTime = LargoRules.BeatDue(now, rhapsody.anchor, rhapsody.lastBeat, LargoRules.BEAT, LargoRules.LATE)
	if beatTime == nil then
		return false
	end
	rhapsody.lastBeat = beatTime
	local blocked = X.SongBlockReason(firstSong)
	if blocked ~= nil then
		rhapsody.noCast = rhapsody.noCast + 1
		LogLargo(
			"strum-blocked",
			3,
			"strum-blocked why=%s song=%s hidden=%s level=%d castable=%s cd=%.2f mana=%d cost=%d",
			blocked,
			rhapsody.first,
			Bool(firstSong:IsHidden()),
			firstSong:GetLevel(),
			Bool(firstSong:IsFullyCastable()),
			firstSong:GetCooldownTimeRemaining(),
			bot:GetMana(),
			firstSong:GetManaCost()
		)
		return false
	end
	local secondSong = rhapsody.second and songByKey[rhapsody.second] or nil
	if
		secondSong ~= nil
		and X.SongBlockReason(secondSong, firstSong:GetManaCost() + secondSong:GetManaCost()) ~= nil
	then
		secondSong = nil
	end
	rhapsody.pending = {
		at = now,
		beat = beatTime,
		song = firstSong,
		key = rhapsody.first,
		key2 = secondSong and rhapsody.second or nil,
		second = secondSong,
		before = Fu.GetModifierCount(bot, GROOVIN_MODIFIER),
		mana = bot:GetMana(),
		cost = firstSong:GetManaCost(),
		cost2 = secondSong and secondSong:GetManaCost() or nil,
		cast = false,
		both = false,
		retried = false,
		attempts = 1,
		lastPushAt = now,
	}
	-- Push, not Action_: the instant song goes first and the walk or other order resumes after it.
	if secondSong ~= nil then
		bot:ActionPush_UseAbility(secondSong)
	end
	bot:ActionPush_UseAbility(firstSong)
	rhapsody.pending.via = X.HoldForStrum(now)
	return true
end
return X
