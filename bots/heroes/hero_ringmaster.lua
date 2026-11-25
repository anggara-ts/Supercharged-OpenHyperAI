-- Ringmaster: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 10, 0 }, ["t20"] = { 0, 10 }, ["t15"] = { 0, 10 }, ["t10"] = { 10, 0 } }
local tAllAbilityBuildList = { { 3, 1, 1, 2, 1, 6, 1, 3, 3, 3, 6, 2, 2, 2, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 33,201 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_magic_stick",
	"item_double_branches",
	"item_faerie_fire",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_aether_lens",
	"item_blink",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_guardian_greaves",
	"item_ultimate_scepter_2",
	"item_aeon_disk",
	"item_sheepstick",
	"item_wind_waker",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 56,124 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_magic_stick",
	"item_double_branches",
	"item_faerie_fire",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_glimmer_cape",
	"item_aether_lens",
	"item_blink",
	"item_headdress",
	"item_aghanims_shard",
	"item_guardian_greaves",
	"item_ultimate_scepter_2",
	"item_aeon_disk",
	"item_sheepstick",
	"item_moon_shard",
}
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_double_branches",
	"item_blight_stone",
	"item_tranquil_boots",
	"item_magic_wand",
	"item_maelstrom",
	"item_force_staff",
	"item_gungir",
	"item_boots_of_bearing",
	"item_shivas_guard",
	"item_ultimate_scepter",
	"item_sheepstick",
	"item_hurricane_pike",
	"item_aghanims_shard",
	"item_ultimate_scepter_2",
	"item_greater_crit",
	"item_moon_shard",
}
sRoleItemsBuyList["pos_1"] = {
	"item_crystal_maiden_outfit",
	"item_rod_of_atos",
	"item_maelstrom",
	"item_aether_lens",
	"item_gungir",
	"item_black_king_bar",
	"item_travel_boots",
	"item_orchid",
	"item_bloodthorn",
	"item_ultimate_scepter",
	"item_moon_shard",
	"item_sheepstick",
	"item_travel_boots_2",
	"item_ultimate_scepter_2",
}
sRoleItemsBuyList["pos_2"] = sRoleItemsBuyList["pos_1"]
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_black_king_bar", "item_quelling_blade" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_antimage" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDeafaultAbility"] = false
X["bDeafaultItem"] = false
function X.MinionThink(minionUnit)
	Minion.MinionThink(minionUnit)
end
local tameTheBeastsAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_tame_the_beasts"), "ringmaster_tame_the_beasts", "ringmaster")
local tameTheBeastsCrackAbility = SafeAbility(
	bot:GetAbilityByName("ringmaster_tame_the_beasts_crack"),
	"ringmaster_tame_the_beasts_crack",
	"ringmaster"
)
local escapeActAbility = SafeAbility(bot:GetAbilityByName("ringmaster_the_box"), "ringmaster_the_box", "ringmaster")
local impalementArtsAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_impalement"), "ringmaster_impalement", "ringmaster")
local spotlightAbility = SafeAbility(bot:GetAbilityByName("ringmaster_spotlight"), "ringmaster_spotlight", "ringmaster")
local wheelOfWonderAbility = SafeAbility(bot:GetAbilityByName("ringmaster_wheel"), "ringmaster_wheel", "ringmaster")
local emptySouvenirAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_empty_souvenir"), "ringmaster_empty_souvenir", "ringmaster")
local funhouseMirrorAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_funhouse_mirror"), "ringmaster_funhouse_mirror", "ringmaster")
local strongmanTonicAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_strongman_tonic"), "ringmaster_strongman_tonic", "ringmaster")
local whoopeeCushionAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_whoopee_cushion"), "ringmaster_whoopee_cushion", "ringmaster")
local unicycleAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_summon_unicycle"), "ringmaster_summon_unicycle", "ringmaster")
local tameTheBeastsDesire, tameTheBeastsLocation, tameTheBeastsWhy, tameTheBeastsTarget
local escapeActDesire, escapeActTarget
local impalementArtsDesire, impalementArtsLocation
local spotlightDesire, spotlightLocation
local wheelOfWonderDesire, wheelOfWonderLocation
local funhouseMirrorDesire
local strongmanTonicDesire, strongmanTonicTarget
local whoopeeCushionDesire
local whoopeeCushionWhy = "fight"
local unicycleDesire
-- Weighted Pie and Crystal Ball souvenirs (#49): never cast before.
local weightedPieAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_weighted_pie"), "ringmaster_weighted_pie", "ringmaster")
local crystalBallAbility =
	SafeAbility(bot:GetAbilityByName("ringmaster_crystal_ball"), "ringmaster_crystal_ball", "ringmaster")
local botTarget
local isEngaging
local isRetreating
local isAttacking
local hpRatio
-- Diagnostic (#49): which souvenir Ringmaster holds and whether it can be cast. Game 043: he got Strongman Tonic
-- (~26:26) and Whoopee Cushion (~34:40), the engine warned "trying to unhide in a slot > 5", and no line said
-- whether either was used. Every 30s: each souvenir that is not hidden, with castable / cooldown / level.
function X.LogSouvenirState()
	if DotaTime() < (bot._souvenirStateAt or -999) then
		return
	end
	bot._souvenirStateAt = DotaTime() + 30
	local parts = {}
	for _, pair in ipairs({
		{ "tonic", strongmanTonicAbility },
		{ "cushion", whoopeeCushionAbility },
		{ "mirror", funhouseMirrorAbility },
		{ "unicycle", unicycleAbility },
		{ "pie", weightedPieAbility },
		{ "ball", crystalBallAbility },
	}) do
		local ability = pair[2]
		if ability ~= nil and not ability:IsNull() and not ability:IsHidden() and ability:GetLevel() > 0 then
			parts[#parts + 1] = string.format(
				"%s(castable=%s cd=%.0f lvl=%d)",
				pair[1],
				tostring(ability:IsFullyCastable()),
				ability:GetCooldownTimeRemaining(),
				ability:GetLevel()
			)
		end
	end
	if #parts > 0 then
		pcall(print, string.format("[SHy-RINGMASTER] t=%.0f souvenirs %s", DotaTime(), table.concat(parts, " ")))
	end
end
function X.SkillsComplement()
	pcall(X.LogSouvenirState)
	-- The Wheel and whip trackers run before the channel check: the whip is a channel, and its crack is decided here.
	pcall(X.WheelTick)
	local okW, whipBusy = pcall(X.WhipTick)
	if okW and whipBusy then
		return
	end
	if Fu.CanNotUseAbility(bot) or bot:IsCastingAbility() or bot:IsChanneling() then
		return
	end
	local abilityContext = AbilityContext.Build(bot)
	isEngaging = abilityContext.isEngaging
	isRetreating = abilityContext.isRetreating
	isAttacking = Fu.IsAttacking(bot)
	hpRatio = abilityContext.hp
	botTarget = abilityContext.target
	local okL, lastWill = pcall(X.LastWillWheel)
	if okL and lastWill then
		return
	end
	whoopeeCushionDesire = X.ConsiderWhoopeeCushion()
	if whoopeeCushionDesire > 0 then
		X.LogSouvenir("whoopee_cushion", "cast-" .. whoopeeCushionWhy)
		bot:Action_UseAbility(whoopeeCushionAbility)
		return
	end
	local okC, comboActed = pcall(X.WheelTameCombo)
	if okC and comboActed then
		return
	end
	wheelOfWonderDesire, wheelOfWonderLocation = X.ConsiderWheelOfWonder()
	if wheelOfWonderDesire > 0 then
		X.WheelOrdered("teamfight")
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(wheelOfWonderAbility, wheelOfWonderLocation)
		return
	end
	tameTheBeastsDesire, tameTheBeastsLocation, tameTheBeastsWhy, tameTheBeastsTarget = X.ConsiderTameTheBeasts()
	if tameTheBeastsDesire > 0 then
		X.WhipOrdered(tameTheBeastsWhy, tameTheBeastsLocation, tameTheBeastsTarget)
		Fu.SetQueuePtToINT(bot, true)
		bot:ActionQueue_UseAbilityOnLocation(tameTheBeastsAbility, tameTheBeastsLocation)
		return
	end
	escapeActDesire, escapeActTarget = X.ConsiderEscapeAct()
	-- return after queueing: without it a later Action_* (Tonic, Funhouse Mirror, Unicycle) in the same
	-- think replaced the queue, so the Box save or the dagger was dropped.
	if escapeActDesire > 0 then
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnEntity(escapeActAbility, escapeActTarget)
		return
	end
	impalementArtsDesire, impalementArtsLocation = X.ConsiderImpalementArts()
	if impalementArtsDesire > 0 then
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(impalementArtsAbility, impalementArtsLocation)
		return
	end
	strongmanTonicDesire, strongmanTonicTarget = X.ConsiderStrongmanTonic()
	if strongmanTonicDesire > 0 then
		X.LogSouvenir("strongman_tonic", "cast")
		bot:Action_UseAbilityOnEntity(strongmanTonicAbility, strongmanTonicTarget)
		return
	end
	spotlightDesire, spotlightLocation = X.ConsiderSpotlight()
	if spotlightDesire > 0 then
		Fu.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(spotlightAbility, spotlightLocation)
		return
	end
	funhouseMirrorDesire = X.ConsiderFunhouseMirror()
	if funhouseMirrorDesire > 0 then
		X.LogSouvenir("funhouse_mirror", "cast")
		bot:Action_UseAbility(funhouseMirrorAbility)
		return
	end
	unicycleDesire = X.ConsiderUnicycle()
	if unicycleDesire > 0 then
		X.LogSouvenir("unicycle", "cast")
		bot:Action_UseAbility(unicycleAbility)
		return
	end
	local pieTarget = X.ConsiderWeightedPie()
	if pieTarget ~= nil then
		bot:Action_UseAbilityOnEntity(weightedPieAbility, pieTarget)
		return
	end
	local ballLocation = X.ConsiderCrystalBall()
	if ballLocation ~= nil then
		bot:Action_UseAbilityOnLocation(crystalBallAbility, ballLocation)
		return
	end
end
function X.LogSouvenir(name, why)
	if DotaTime() >= (bot._souvenirLogAt or -999) then
		bot._souvenirLogAt = DotaTime() + 3
		pcall(print, string.format("[SHy-RINGMASTER] t=%.0f souvenir=%s why=%s", DotaTime(), name, why))
	end
end
-- Weighted Pie (game data: hero/creep target, 750 range, pushes 400 over 0.3s, blinds 3s, slows up to 45%):
-- on the closest chaser while retreating, or on a target escaping while engaging.
function X.ConsiderWeightedPie()
	if not Fu.CanCastAbility(weightedPieAbility) then
		return nil
	end
	local castRange = 750
	if isRetreating then
		local closest, closestDistance = nil, castRange + 1
		for _, enemyHero in pairs(bot:GetNearbyHeroes(castRange, true, BOT_MODE_NONE) or {}) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.IsChasingTarget(enemyHero, bot)
				and GetUnitToUnitDistance(bot, enemyHero) < closestDistance
			then
				closest, closestDistance = enemyHero, GetUnitToUnitDistance(bot, enemyHero)
			end
		end
		if closest ~= nil then
			X.LogSouvenir("weighted_pie", "chaser")
			return closest
		end
	end
	if
		isEngaging
		and Fu.IsValidHero(botTarget)
		and Fu.IsInRange(bot, botTarget, castRange)
		and Fu.CanCastOnNonMagicImmune(botTarget)
		and Fu.IsRunning(botTarget)
		and not botTarget:IsFacingLocation(bot:GetLocation(), 90)
	then
		X.LogSouvenir("weighted_pie", "escaping-target")
		return botTarget
	end
	return nil
end
-- Crystal Ball (game data: point AoE, radius 450, 5s true sight): on an invisible enemy hero within 1600, or on
-- an enemy hero last seen in the fog near a fight.
function X.ConsiderCrystalBall()
	if not Fu.CanCastAbility(crystalBallAbility) then
		return nil
	end
	for _, enemyHero in pairs(bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and enemyHero:IsInvisible() then
			X.LogSouvenir("crystal_ball", "invisible")
			return enemyHero:GetLocation()
		end
	end
	if Fu.IsInTeamFight(bot, 1200) then
		for _, playerId in pairs(GetTeamPlayers(GetOpposingTeam())) do
			local info = IsHeroAlive(playerId) and GetHeroLastSeenInfo(playerId) or nil
			local lastSeen = info ~= nil and info[1] or nil
			if
				lastSeen ~= nil
				and lastSeen.time_since_seen > 0.5
				and lastSeen.time_since_seen < 3
				and GetUnitToLocationDistance(bot, lastSeen.location) < 1200
			then
				X.LogSouvenir("crystal_ball", "fog")
				return lastSeen.location
			end
		end
	end
	return nil
end
-- Wheel then Tame (#49, maintainer's idea). Datafeed: Tame the Beasts makes whipped enemies "flee in fear from
-- Ringmaster" (up to 1.2s with a full 1s channel, cast range 700); the Wheel of Wonder rolls to a point (cast range
-- 1400, min range 700, speed 1200) and mesmerizes heroes who face it for 0.5s. The fear is shorter than the roll, so
-- the Wheel goes first, beyond the group on the line from Ringmaster, then the whip drives them into it.
function X.WheelTameCombo()
	local now = DotaTime()
	local combo = bot._wheelTame
	if combo ~= nil then
		-- Step 2 waits until the Wheel really went out (its cooldown started, X.WheelTick): game 084 ordered the whip
		-- in the same second as the Wheel, and a new order before the Wheel's cast point replaces the Wheel order.
		if bot._wheelPending ~= nil and now - combo.at <= 1.0 then
			return true
		end
		local wheelCastAt = bot._wheelCastAt
		if wheelCastAt == nil or wheelCastAt < combo.at or now - wheelCastAt > 1.5 then
			bot._wheelTame = nil
			pcall(
				print,
				string.format(
					"[SHy-RINGMASTER] t=%.0f ringmaster wheel-tame step=dropped wheel=%s",
					now,
					(wheelCastAt ~= nil and wheelCastAt >= combo.at) and "late" or "not-cast"
				)
			)
			return false
		end
		-- Step 2: the Wheel is out; whip the group within 1.5s. The whip keeps its full channel (X.WhipCrackDecision).
		if Fu.CanCastAbility(tameTheBeastsAbility) then
			local enemies = Fu.GetEnemiesNearLoc(combo.center, 650)
			if #enemies >= 1 and GetUnitToLocationDistance(bot, combo.center) <= 750 then
				bot._wheelTame = nil
				local whipPoint = Fu.GetCenterOfUnits(enemies)
				pcall(
					print,
					string.format(
						"[SHy-RINGMASTER] t=%.0f ringmaster wheel-tame step=tame enemies=%d after-wheel=%.2f",
						now,
						#enemies,
						now - wheelCastAt
					)
				)
				X.WhipOrdered("combo", whipPoint, nil)
				bot:Action_UseAbilityOnLocation(tameTheBeastsAbility, whipPoint)
				return true
			end
		end
		return false
	end
	-- Step 1: a group of 2+ enemy heroes close together, both spells ready, mana for both, and not about to die
	-- (game 084 t=1132: the combo started at 18% HP inside five enemies and Ringmaster died in the same second).
	if not isEngaging or not Fu.CanCastAbility(wheelOfWonderAbility) or not Fu.CanCastAbility(tameTheBeastsAbility) then
		return false
	end
	if hpRatio < 0.35 then
		return false
	end
	if bot:GetMana() < wheelOfWonderAbility:GetManaCost() + tameTheBeastsAbility:GetManaCost() then
		return false
	end
	local enemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 1000)
	if #enemies < 2 then
		return false
	end
	local center = Fu.GetCenterOfUnits(enemies)
	if #Fu.GetEnemiesNearLoc(center, 600) < 2 then
		return false
	end
	local dist = GetUnitToLocationDistance(bot, center)
	if dist > 700 then
		return false
	end
	local wheelDist = math.max(700, math.min(1400, dist + 400))
	local wheelPoint = Fu.VectorTowards(bot:GetLocation(), center, wheelDist)
	bot._wheelTame = { at = now, center = center }
	X.WheelOrdered("combo")
	-- Hold the mode Thinks and items through the Wheel's turn and cast point (released by X.WheelTick).
	bot._castHoldUntil = now + 0.6
	pcall(
		print,
		string.format(
			"[SHy-RINGMASTER] t=%.0f ringmaster wheel-tame step=wheel enemies=%d wheel-dist=%d group-dist=%d",
			now,
			#enemies,
			wheelDist,
			dist
		)
	)
	bot:Action_UseAbilityOnLocation(wheelOfWonderAbility, wheelPoint)
	return true
end
function X.ConsiderTameTheBeasts()
	if not Fu.CanCastAbility(tameTheBeastsAbility) then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, tameTheBeastsAbility:GetCastRange())
	local castPoint = tameTheBeastsAbility:GetCastPoint()
	local startWidth = tameTheBeastsAbility:GetSpecialValueInt("start_width")
	local endWidth = tameTheBeastsAbility:GetSpecialValueInt("end_width")
	local minDamage = tameTheBeastsAbility:GetSpecialValueInt("damage_min")
	local maxDamage = tameTheBeastsAbility:GetSpecialValueInt("damage_max")
	local manaCost = tameTheBeastsAbility:GetManaCost()
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.IsInRange(bot, enemyHero, castRange)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
		then
			if enemyHero:HasModifier("modifier_teleporting") then
				return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation(), "cancel", enemyHero
			end
			if
				Fu.CanKillTarget(enemyHero, maxDamage, DAMAGE_TYPE_MAGICAL)
				and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
				and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
				and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
				and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation(), "kill", enemyHero
			end
		end
	end
	if isEngaging then
		if
			Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and (not Fu.IsChasingTarget(bot, botTarget) or Fu.IsInRange(bot, botTarget, endWidth))
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and not Fu.IsDisabled(botTarget)
			and not botTarget:HasModifier("modifier_faceless_void_chronosphere_freeze")
			and not botTarget:HasModifier("modifier_legion_commander_duel")
			and #nearbyAllies < #nearbyEnemies + 3
		then
			local aoeLocation = bot:FindAoELocation(true, true, botTarget:GetLocation(), startWidth, startWidth, 0, 0)
			local targetLocation = botTarget:GetLocation()
			if aoeLocation.count > 1 then
				targetLocation = aoeLocation.targetloc
			end
			return BOT_ACTION_DESIRE_HIGH, targetLocation, "engage", botTarget
		end
	end
	if isRetreating and not Fu.IsRealInvisible(bot) then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsInRange(bot, enemyHero, startWidth)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and bot:WasRecentlyDamagedByHero(enemyHero, 3.0)
				and (hpRatio < 0.65 or Fu.IsChasingTarget(enemyHero, bot))
			then
				local aoeLocation =
					bot:FindAoELocation(true, true, enemyHero:GetLocation(), startWidth, startWidth, 0, 0)
				local targetLocation = (bot:GetLocation() + enemyHero:GetLocation()) / 2
				if aoeLocation.count > 1 then
					targetLocation = aoeLocation.targetloc
				end
				return BOT_ACTION_DESIRE_HIGH, targetLocation, "retreat", enemyHero
			end
		end
	end
	local laneCreeps = bot:GetNearbyLaneCreeps(castRange + 150, true)
	if Fu.IsPushing(bot) and Fu.GetManaAfter(manaCost) > 0.45 then
		if
			#laneCreeps >= 4
			and Fu.CanBeAttacked(laneCreeps[1])
			and not Fu.IsRunning(laneCreeps[1])
			and (Fu.IsCore(bot) or not Fu.IsThereNonSelfCoreNearby(1600))
		then
			local aoeLocation = bot:FindAoELocation(true, false, laneCreeps[1]:GetLocation(), endWidth, endWidth, 0, 0)
			local targetLocation = Fu.GetCenterOfUnits(laneCreeps)
			if aoeLocation.count >= 4 then
				targetLocation = aoeLocation.targetloc
			end
			return BOT_ACTION_DESIRE_HIGH, targetLocation, "push", nil
		end
	end
	if Fu.IsDefending(bot) then
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, endWidth, 0, 0)
		if aoeLocation.count >= 2 then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc, "defend", nil
		end
		if
			#laneCreeps >= 4
			and Fu.CanBeAttacked(laneCreeps[1])
			and not Fu.IsRunning(laneCreeps[1])
			and (Fu.IsCore(bot) or not Fu.IsThereNonSelfCoreNearby(1600))
		then
			aoeLocation = bot:FindAoELocation(true, false, laneCreeps[1]:GetLocation(), endWidth, endWidth, 0, 0)
			local targetLocation = Fu.GetCenterOfUnits(laneCreeps)
			if aoeLocation.count >= 4 then
				targetLocation = aoeLocation.targetloc
			end
			return BOT_ACTION_DESIRE_HIGH, targetLocation, "defend", nil
		end
	end
	if Fu.IsFarming(bot) and Fu.GetManaAfter(manaCost) > 0.33 then
		local nearbyCreeps = bot:GetNearbyCreeps(castRange + 150, true)
		if
			Fu.CanBeAttacked(nearbyCreeps[1])
			and not Fu.IsRunning(nearbyCreeps[1])
			and (#nearbyCreeps >= 2 or #nearbyCreeps >= 1 and nearbyCreeps[1]:IsAncientCreep())
		then
			local aoeLocation =
				bot:FindAoELocation(true, false, nearbyCreeps[1]:GetLocation(), endWidth, endWidth, 0, 0)
			local targetLocation = Fu.GetCenterOfUnits(nearbyCreeps)
			if aoeLocation.count >= 4 then
				targetLocation = aoeLocation.targetloc
			end
			return BOT_ACTION_DESIRE_HIGH, targetLocation, "farm", nil
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation(), "roshan", nil
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if
			Fu.IsTormentor(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation(), "tormentor", nil
		end
	end
	if Fu.IsCore(bot) or not Fu.IsThereNonSelfCoreNearby(1600) then
		local nearbyCreeps = bot:GetNearbyCreeps(castRange, true)
		local killableCreeps = {}
		for _, creep in pairs(nearbyCreeps) do
			if
				Fu.IsValid(creep)
				and Fu.CanBeAttacked(creep)
				and not Fu.IsRunning(creep)
				and Fu.CanKillTarget(creep, maxDamage, DAMAGE_TYPE_MAGICAL)
			then
				table.insert(killableCreeps, creep)
			end
		end
		if Fu.IsValid(killableCreeps[1]) then
			local aoeLocation =
				bot:FindAoELocation(true, false, killableCreeps[1]:GetLocation(), endWidth, endWidth, 0, 0)
			if Fu.IsLaning(bot) then
				if
					#killableCreeps >= 2
					or #killableCreeps == 1
						and Fu.GetManaAfter(manaCost) > 0.18
						and string.find(killableCreeps[1]:GetUnitName(), "ranged")
						and Fu.IsValidHero(nearbyEnemies[1])
						and Fu.IsInRange(killableCreeps[1], nearbyEnemies[1], startWidth)
				then
					return BOT_ACTION_DESIRE_HIGH, killableCreeps[1]:GetLocation(), "creeps", nil
				end
			end
			if aoeLocation.count >= 4 and #killableCreeps >= 3 then
				return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc, "creeps", nil
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
-- Tame the Beasts as a channel (#49, game 084: "tame also instant, the fear is minimum duration").
-- Game files (scripts/npc ringmaster abilities from pak01_dir.vpk, read 2026-11-21; the datafeed hero 131 read 2026-11-25
-- has the same values): POINT | AOE | CHANNELLED,
-- AbilityChannelTime 1.0, cast point 0, start_width 450 -> end_width 200 ("RADIUS START / END"), damage_min
-- 50/75/100/125 with "Real max damage is 4x damage min" (max_multiplier 4; damage_max only feeds the tooltip),
-- fear_duration_min 0.1/0.2/0.3/0.4 -> fear_duration_max 0.6/0.8/1.0/1.2, crack_duration 0.2. Tooltip: "Channel time
-- exponentially increases damage and extends the fear duration, but reduces the radius". The crack
-- (ringmaster_tame_the_beasts_crack) is IMMEDIATE | IGNORE_CHANNEL and only shown while the whip is out.
-- The curve itself is not in the game data. Estimate (unverified): damage = damage_min * max_multiplier ^ f and the
-- fear moves by the same share, (max_multiplier ^ f - 1) / (max_multiplier - 1), with f the channelled share 0..1;
-- the radius shrinks linearly from start_width to end_width.
function X.WhipShare(f, multiplier)
	f = math.max(0, math.min(1, f))
	if multiplier == nil or multiplier <= 1 then
		return f
	end
	return (multiplier ^ f - 1) / (multiplier - 1)
end
function X.WhipDamage(f, damageMin, multiplier)
	f = math.max(0, math.min(1, f))
	return damageMin * (multiplier or 4) ^ f
end
function X.WhipFear(f, fearMin, fearMax, multiplier)
	return fearMin + (fearMax - fearMin) * X.WhipShare(f, multiplier)
end
function X.WhipRadius(f, startWidth, endWidth)
	f = math.max(0, math.min(1, f))
	return startWidth - (startWidth - endWidth) * f
end
-- When to crack before the full channel; nil = keep channelling (the engine cracks at the end by itself).
-- s: why (cast reason), killNow (a hero in the area dies to the damage now), lowHp, enemyOnTop (an enemy hero within
-- end_width of Ringmaster), nearestNow / nearestLater (distance of the enemy hero nearest the whip point now and after
-- the lead time; nil = no enemy hero inside), radiusLater (the area after the lead time), margin.
-- The combo whip is never cracked early: the fear has to be long enough to drive them into the Wheel.
local WHIP_RADIUS_REASONS = { engage = true, kill = true, retreat = true }
function X.WhipCrackDecision(s)
	if s.why == "combo" then
		return nil
	end
	if s.why == "cancel" then
		return "cancel"
	end
	if s.killNow then
		return "kill"
	end
	if s.lowHp then
		return "lowhp"
	end
	if s.why == "retreat" and s.enemyOnTop then
		return "ontop"
	end
	if WHIP_RADIUS_REASONS[s.why] then
		if s.nearestNow == nil then
			return "empty"
		end
		if s.nearestLater ~= nil and s.nearestLater > s.radiusLater - (s.margin or 0) then
			return "radius"
		end
	end
	return nil
end
-- The crack button is shown while the whip is out (a missing ability is the NIL_ABILITY stub: no name).
local function WhipCrackShown()
	return tameTheBeastsCrackAbility ~= nil
		and not tameTheBeastsCrackAbility:IsNull()
		and tameTheBeastsCrackAbility:GetName() == "ringmaster_tame_the_beasts_crack"
		and not tameTheBeastsCrackAbility:IsHidden()
end
-- The modifier only counts when it was not already on at the order (its holder and lifetime are not in the game data).
local function WhipChannelOn(whip)
	return WhipCrackShown() or (not whip.modifierBefore and bot:HasModifier("modifier_ringmaster_tame_the_beasts"))
end
local function WhipDisabled()
	return not bot:IsAlive() or bot:IsStunned() or bot:IsSilenced() or bot:IsHexed() or bot:IsNightmared()
end
local function WhipNoSave(unit)
	return not unit:HasModifier("modifier_abaddon_borrowed_time")
		and not unit:HasModifier("modifier_dazzle_shallow_grave")
		and not unit:HasModifier("modifier_necrolyte_reapers_scythe")
		and not unit:HasModifier("modifier_oracle_false_promise_timer")
end
-- Every Tame order goes through here: one fresh state per cast (the old whip_to_* flags leaked from one whip to the
-- next, and a creep whip's flag blocked every later crack), and a cast hold (bot._castHoldUntil, the Puck pattern:
-- OhaCastGuard skips the mode Thinks and the item think skips items) so no move, attack or item order ends the
-- channel. Game 084 [SHy-STUCK]: during the whip the API said channel=false casting=false using=true, so the usual
-- IsChanneling guards did not hold anything.
function X.WhipOrdered(why, location, target)
	local now = DotaTime()
	local whip = bot._whip
	if whip ~= nil then
		return
	end
	bot._whip = {
		why = why or "?",
		location = location,
		target = target,
		orderAt = now,
		modifierBefore = bot:HasModifier("modifier_ringmaster_tame_the_beasts"),
	}
	bot._castHoldUntil = now + 0.8
	pcall(
		print,
		string.format(
			"[SHy-RINGMASTER] t=%.0f ringmaster tame-cast why=%s dist=%d target=%s",
			now,
			why or "?",
			location ~= nil and GetUnitToLocationDistance(bot, location) or -1,
			(target ~= nil and Fu.IsValidHero(target)) and target:GetUnitName() or "none"
		)
	)
end
function X.WhipEnd(whip, endWhy, elapsed, channelTime, extra)
	local f = channelTime > 0 and elapsed / channelTime or 1
	local level = math.max(1, tameTheBeastsAbility:GetLevel())
	local fearMin = tameTheBeastsAbility:GetSpecialValueFloat("fear_duration_min")
	local fearMax = tameTheBeastsAbility:GetSpecialValueFloat("fear_duration_max")
	local damageMin = tameTheBeastsAbility:GetSpecialValueInt("damage_min")
	local multiplier = tameTheBeastsAbility:GetSpecialValueFloat("max_multiplier")
	if multiplier <= 1 then
		multiplier = 4
	end
	pcall(
		print,
		string.format(
			"[SHy-RINGMASTER] t=%.0f ringmaster tame-crack why=%s end=%s channelled=%.2f share=%.2f fear=%.2f damage=%d level=%d chan0=%s active0=%s crackable0=%s%s",
			DotaTime(),
			whip.why,
			endWhy,
			elapsed,
			f,
			X.WhipFear(f, fearMin, fearMax, multiplier),
			X.WhipDamage(f, damageMin, multiplier),
			level,
			tostring(whip.chan0),
			tostring(whip.active0),
			tostring(whip.crackable0),
			extra or ""
		)
	)
	bot._whip = nil
	bot._castHoldUntil = nil
end
-- The whip's own tick: start, crack and end. Runs at the top of SkillsComplement and from CastHoldTick while the hold
-- is on. true = a whip is ordered or out: no other cast this frame.
function X.WhipTick()
	local whip = bot._whip
	if whip == nil then
		return false
	end
	local now = DotaTime()
	local channelTime = tameTheBeastsAbility:GetChannelTime()
	if channelTime == nil or channelTime <= 0 then
		channelTime = 1.0
	end
	local channelOn = WhipChannelOn(whip)
	if whip.startAt == nil then
		-- The clock starts when the whip is out, not at the order (turning to the point comes first). The cooldown
		-- starts with the channel too, in case neither the crack button nor the modifier shows through the API.
		if channelOn or tameTheBeastsAbility:GetCooldownTimeRemaining() > 0 then
			whip.startAt = now
			whip.seen = channelOn
			-- What the API shows on the first channel frame (game 084 [SHy-STUCK]: channel=false during the whip).
			whip.chan0 = bot:IsChanneling()
			local active = bot:GetCurrentActiveAbility()
			whip.active0 = active ~= nil and active:GetName() or "none"
			whip.crackable0 = Fu.CanCastAbility(tameTheBeastsCrackAbility)
			bot._castHoldUntil = now + channelTime + 0.15
			return true
		end
		if now - whip.orderAt > 0.8 then
			pcall(
				print,
				string.format(
					"[SHy-RINGMASTER] t=%.0f ringmaster tame-crack why=%s end=nostart channelled=0 waited=%.2f",
					now,
					whip.why,
					now - whip.orderAt
				)
			)
			bot._whip = nil
			bot._castHoldUntil = nil
			return false
		end
		return true
	end
	local elapsed = now - whip.startAt
	if channelOn then
		whip.seen = true
	end
	if not whip.seen then
		if elapsed > channelTime + 0.1 then
			-- Neither the crack button nor the modifier ever showed: no early crack was possible.
			X.WhipEnd(whip, "unseen", channelTime, channelTime)
			return false
		end
		return true
	end
	if elapsed > channelTime + 0.5 then
		-- The signal stuck: never hold longer than the channel.
		X.WhipEnd(whip, "stuck", channelTime, channelTime)
		return false
	end
	if not channelOn then
		-- The engine ended it: the full channel, a disable (stun, silence, hex, death) or an interrupt by an order.
		X.WhipEnd(
			whip,
			elapsed >= channelTime - 0.1 and "full" or (WhipDisabled() and "disabled" or "interrupted"),
			math.min(elapsed, channelTime),
			channelTime
		)
		return false
	end
	if not Fu.CanCastAbility(tameTheBeastsCrackAbility) then
		return true
	end
	local f = elapsed / channelTime
	-- Lead: the crack takes crack_duration (0.2) to land, plus a frame.
	local crackDuration = tameTheBeastsAbility:GetSpecialValueFloat("crack_duration")
	if crackDuration <= 0 then
		crackDuration = 0.2
	end
	local lead = crackDuration + 0.05
	local startWidth = tameTheBeastsAbility:GetSpecialValueInt("start_width")
	local endWidth = tameTheBeastsAbility:GetSpecialValueInt("end_width")
	local radiusNow = X.WhipRadius(f, startWidth, endWidth)
	local radiusLater = X.WhipRadius((elapsed + lead) / channelTime, startWidth, endWidth)
	local multiplier = tameTheBeastsAbility:GetSpecialValueFloat("max_multiplier")
	if multiplier <= 1 then
		multiplier = 4
	end
	local damageNow = X.WhipDamage(f, tameTheBeastsAbility:GetSpecialValueInt("damage_min"), multiplier)
	local nearestNow, nearestLater, nearestName = nil, nil, "none"
	local killNow, enemyOnTop = false, false
	for _, enemyHero in pairs(bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and Fu.CanCastOnNonMagicImmune(enemyHero) then
			if GetUnitToUnitDistance(bot, enemyHero) <= endWidth then
				enemyOnTop = true
			end
			local dist = whip.location ~= nil and GetUnitToLocationDistance(enemyHero, whip.location) or 99999
			if dist <= radiusNow then
				if Fu.CanKillTarget(enemyHero, damageNow, DAMAGE_TYPE_MAGICAL) and WhipNoSave(enemyHero) then
					killNow = true
				end
				if nearestNow == nil or dist < nearestNow then
					nearestNow = dist
					nearestLater =
						Fu.GetLocationToLocationDistance(enemyHero:GetExtrapolatedLocation(lead), whip.location)
					nearestName = enemyHero:GetUnitName()
				end
			end
		end
	end
	local crackWhy = X.WhipCrackDecision({
		why = whip.why,
		killNow = killNow,
		lowHp = bot:GetHealth() / math.max(1, bot:GetMaxHealth()) < 0.15,
		enemyOnTop = enemyOnTop,
		nearestNow = nearestNow,
		nearestLater = nearestLater,
		radiusLater = radiusLater,
		margin = 25,
	})
	if crackWhy == nil then
		return true
	end
	bot:Action_UseAbility(tameTheBeastsCrackAbility)
	X.WhipEnd(
		whip,
		crackWhy,
		elapsed,
		channelTime,
		string.format(
			" nearest=%s dist=%d later=%d radius=%d",
			nearestName,
			nearestNow or -1,
			nearestLater or -1,
			radiusLater
		)
	)
	-- Keep the hold while the crack lands (crack_duration).
	bot._castHoldUntil = now + crackDuration
	return true
end
-- Wheel casts: one line per Wheel that really went out (its cooldown started), with the rule that ordered it.
function X.WheelOrdered(why, extra)
	if bot._wheelPending == nil then
		bot._wheelPending = { why = why, at = DotaTime(), extra = extra or "" }
	end
end
-- Wheel orders that put a cast hold on (released when the Wheel is out or dropped).
local WHEEL_HOLD_REASONS = { combo = true, ["last-will"] = true }
function X.WheelTick()
	local pending = bot._wheelPending
	if pending == nil then
		return
	end
	local now = DotaTime()
	if wheelOfWonderAbility:GetCooldownTimeRemaining() > 0 then
		bot._wheelPending = nil
		bot._wheelCastAt = now
		pcall(
			print,
			string.format(
				"[SHy-RINGMASTER] t=%.0f ringmaster wheel-cast why=%s after=%.2f%s",
				now,
				pending.why,
				now - pending.at,
				pending.extra
			)
		)
		if WHEEL_HOLD_REASONS[pending.why] then
			-- The combo held the mode Thinks for the Wheel's turn and cast point; the whip comes next.
			bot._castHoldUntil = nil
		end
	elseif now - pending.at > 1.0 then
		bot._wheelPending = nil
		pcall(print, string.format("[SHy-RINGMASTER] t=%.0f ringmaster wheel-cast why=%s dropped=1", now, pending.why))
		if WHEEL_HOLD_REASONS[pending.why] then
			bot._castHoldUntil = nil
		end
	end
end
-- The cast hold pauses the item think, and with it SkillsComplement; the item think calls this instead.
function X.CastHoldTick()
	pcall(X.WheelTick)
	pcall(X.WhipTick)
end
-- Last will (maintainer, 2026-11-26: "ringmaster should still cast ult on last will before died (on low hp)").
-- About to die = below 25% HP while a hero hit him in the last 2s, or the enemies near him deal his remaining HP
-- within 2s (Fu.GetTotalEstimatedDamageToTarget estimates 5s, scaled by 2/5). Then the Wheel goes on the best
-- enemy group at once, in any mode (retreat too), with no whip after it. The combo's 35% HP gate does not apply.
function X.LastWillDue(hp, hitRecently, damage2s, health, enemiesInWheel)
	if enemiesInWheel < 1 then
		return false
	end
	return (hp < 0.25 and hitRecently) or damage2s >= health
end
function X.LastWillWheel()
	if bot._wheelPending ~= nil or not Fu.CanCastAbility(wheelOfWonderAbility) then
		return false
	end
	local castRange = Fu.GetProperCastRange(false, bot, wheelOfWonderAbility:GetCastRange())
	local nearbyEnemies = bot:GetNearbyHeroes(math.min(1600, castRange + 300), true, BOT_MODE_NONE) or {}
	if #nearbyEnemies == 0 then
		return false
	end
	local hp = bot:GetHealth() / math.max(1, bot:GetMaxHealth())
	local hitRecently = bot:WasRecentlyDamagedByAnyHero(2.0)
	if hp >= 0.25 and not hitRecently then
		return false
	end
	local damage2s = Fu.GetTotalEstimatedDamageToTarget(nearbyEnemies, bot) * 2 / 5
	local mesmerizeRadius = wheelOfWonderAbility:GetSpecialValueInt("mesmerize_radius")
	local minRange = wheelOfWonderAbility:GetSpecialValueInt("min_range")
	local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, mesmerizeRadius, 0, 0)
	local point = aoeLocation.targetloc
	if aoeLocation.count < 1 then
		local nearest = nil
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and (nearest == nil or GetUnitToUnitDistance(bot, enemyHero) < GetUnitToUnitDistance(bot, nearest))
			then
				nearest = enemyHero
			end
		end
		if nearest == nil then
			return false
		end
		point = nearest:GetLocation()
	end
	-- datafeed: the Wheel rolls at least min_range (700); a closer point ends up that far out on the same line.
	local stopPoint = point
	if GetUnitToLocationDistance(bot, point) < minRange then
		stopPoint = Fu.VectorTowards(bot:GetLocation(), point, minRange)
	end
	local enemiesInWheel = #Fu.GetEnemiesNearLoc(stopPoint, mesmerizeRadius)
	if not X.LastWillDue(hp, hitRecently, damage2s, bot:GetHealth(), enemiesInWheel) then
		return false
	end
	X.WheelOrdered("last-will", string.format(" hp=%.2f enemies=%d damage2s=%d", hp, enemiesInWheel, damage2s))
	-- Hold the mode Thinks (retreat too) through the turn and cast point; X.WheelTick releases it.
	bot._castHoldUntil = DotaTime() + 0.5
	bot:Action_UseAbilityOnLocation(wheelOfWonderAbility, stopPoint)
	return true
end
function X.ConsiderEscapeAct()
	if not Fu.CanCastAbility(escapeActAbility) then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, escapeActAbility:GetCastRange())
	local leashRadius = escapeActAbility:GetSpecialValueFloat("leash_radius")
	local invisDuration = escapeActAbility:GetSpecialValueFloat("invis_duration")
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, allyHero in pairs(nearbyAllies) do
		if
			Fu.IsValidHero(allyHero)
			and not Fu.IsRealInvisible(allyHero)
			and Fu.IsInRange(bot, allyHero, castRange + 300)
			and Fu.IsCore(allyHero)
			and not allyHero:IsIllusion()
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and Fu.CanBeAttacked(allyHero)
		then
			if
				allyHero:HasModifier("modifier_legion_commander_duel")
				or allyHero:HasModifier("modifier_enigma_black_hole_pull")
				or allyHero:HasModifier("modifier_faceless_void_chronosphere_freeze")
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero
			end
			local alliesNearAlly = allyHero:GetNearbyHeroes(900, false, BOT_MODE_NONE)
			local enemiesNearAlly = allyHero:GetNearbyHeroes(900, true, BOT_MODE_NONE)
			if
				Fu.IsValidHero(enemiesNearAlly[1])
				and not Fu.IsSuspiciousIllusion(enemiesNearAlly[1])
				and (enemiesNearAlly[1]:GetAttackTarget() == allyHero or Fu.IsChasingTarget(
					enemiesNearAlly[1],
					allyHero
				))
				and #enemiesNearAlly >= #alliesNearAlly
				and not allyHero:HasModifier("modifier_teleporting")
				and not Fu.IsInEtherealForm(allyHero)
				and Fu.GetHP(allyHero) < 0.5
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero
			end
		end
	end
	if Fu.IsRoshan(botTarget) or Fu.IsTormentor(botTarget) then
		for _, allyHero in pairs(nearbyAllies) do
			if Fu.IsValidHero(allyHero) and not allyHero:IsIllusion() then
				if
					(Fu.IsDoingRoshan(allyHero) or Fu.IsDoingTormentor(allyHero))
					and Fu.IsInRange(allyHero, botTarget, 900)
				then
					if Fu.GetHP(allyHero) < 0.15 and not allyHero:HasModifier("modifier_teleporting") then
						return BOT_ACTION_DESIRE_HIGH, allyHero
					end
				end
				if
					Fu.GetHP(allyHero) < 0.3
					and not Fu.IsInEtherealForm(allyHero)
					and Fu.CanBeAttacked(allyHero)
					and not allyHero:IsIllusion()
					and not allyHero:HasModifier("modifier_teleporting")
					and not allyHero:HasModifier("modifier_abaddon_borrowed_time")
					and not allyHero:HasModifier("modifier_dazzle_shallow_grave")
					and not allyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
					and not allyHero:HasModifier("modifier_obsidian_destroyer_astral_imprisonment_prison")
				then
					return BOT_ACTION_DESIRE_HIGH, allyHero
				end
			end
		end
	end
	if hpRatio < 0.25 and X.IsBeingAttacked(bot) and not Fu.IsRealInvisible(bot) then
		return BOT_ACTION_DESIRE_HIGH, bot
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderImpalementArts()
	if not Fu.CanCastAbility(impalementArtsAbility) then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, impalementArtsAbility:GetCastRange())
	local daggerWidth = impalementArtsAbility:GetSpecialValueInt("dagger_width")
	local castPoint = impalementArtsAbility:GetCastPoint()
	local impactDamage = impalementArtsAbility:GetSpecialValueInt("damage_impact")
	local bleedHealthPct = impalementArtsAbility:GetSpecialValueFloat("bleed_health_pct") / 100
	local bleedDuration = impalementArtsAbility:GetSpecialValueInt("bleed_duration")
	local daggerSpeed = impalementArtsAbility:GetSpecialValueInt("dagger_speed")
	local abilityLevel = impalementArtsAbility:GetLevel()
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.IsInRange(bot, enemyHero, castRange)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and not enemyHero:HasModifier("modifier_ringmaster_impalement_bleed")
		then
			local travelTime = GetUnitToUnitDistance(bot, enemyHero) / daggerSpeed + castPoint
			local targetLocation = Fu.GetCorrectLoc(enemyHero, travelTime)
			if
				not X.IsUnitBetweenMeAndLocation(bot, enemyHero, targetLocation, daggerWidth)
				and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
				and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
				and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
			then
				if
					Fu.CanKillTarget(enemyHero, impactDamage, DAMAGE_TYPE_MAGICAL)
					or Fu.CanKillTarget(
						enemyHero,
						impactDamage + enemyHero:GetMaxHealth() * bleedHealthPct * bleedDuration,
						DAMAGE_TYPE_MAGICAL
					)
				then
					return BOT_ACTION_DESIRE_HIGH, targetLocation
				end
			end
		end
	end
	if isEngaging then
		if
			Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and not botTarget:IsInvulnerable()
			and not botTarget:HasModifier("modifier_ringmaster_impalement_bleed")
		then
			local travelTime = GetUnitToUnitDistance(bot, botTarget) / daggerSpeed + castPoint
			local targetLocation = Fu.GetCorrectLoc(botTarget, travelTime)
			local aoeLocation = bot:FindAoELocation(true, true, targetLocation, daggerWidth, daggerWidth, 0, 0)
			if aoeLocation.count > 1 then
				targetLocation = aoeLocation.targetloc
			end
			if not X.IsUnitBetweenMeAndLocation(bot, botTarget, targetLocation, daggerWidth) then
				return BOT_ACTION_DESIRE_HIGH, targetLocation
			end
		end
	end
	if isRetreating and not Fu.IsRealInvisible(bot) then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsInRange(bot, enemyHero, 800)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and bot:WasRecentlyDamagedByHero(enemyHero, 3.0)
				and (hpRatio < 0.5 or Fu.IsChasingTarget(enemyHero, bot))
				and not enemyHero:HasModifier("modifier_ringmaster_impalement_bleed")
			then
				local aoeLocation =
					bot:FindAoELocation(true, true, enemyHero:GetLocation(), daggerWidth, daggerWidth, 0, 0)
				local targetLocation = enemyHero:GetLocation()
				if aoeLocation.count > 1 then
					targetLocation = aoeLocation.targetloc
				end
				if not X.IsUnitBetweenMeAndLocation(bot, enemyHero, targetLocation, daggerWidth) then
					return BOT_ACTION_DESIRE_HIGH, targetLocation
				end
			end
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanBeAttacked(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and botTarget:GetHealth() > impactDamage + botTarget:GetMaxHealth() * bleedHealthPct * bleedDuration
			and not botTarget:HasModifier("modifier_ringmaster_impalement_bleed")
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	if abilityLevel >= 3 and DotaTime() > 12 * 60 and not Fu.IsRealInvisible(bot) then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and not Fu.IsInRange(bot, enemyHero, 900)
				and Fu.IsInRange(bot, enemyHero, castRange)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and not enemyHero:HasModifier("modifier_ringmaster_impalement_bleed")
			then
				local travelTime = GetUnitToUnitDistance(bot, enemyHero) / daggerSpeed + castPoint
				if
					not X.IsUnitBetweenMeAndLocation(
						bot,
						enemyHero,
						Fu.GetCorrectLoc(enemyHero, travelTime),
						daggerWidth
					)
				then
					return BOT_ACTION_DESIRE_HIGH, Fu.GetCorrectLoc(enemyHero, travelTime)
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderSpotlight()
	if not Fu.CanCastAbility(spotlightAbility) then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, spotlightAbility:GetCastRange())
	local castPoint = spotlightAbility:GetCastPoint()
	local radius = spotlightAbility:GetSpecialValueInt("radius")
	local duration = spotlightAbility:GetSpecialValueInt("duration")
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	if Fu.IsInTeamFight(bot, 1200) then
		-- datafeed: the light makes ENEMIES miss and reveals them; this searched for a spot with 2+ allies.
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
		local enemiesInSpotlight = Fu.GetEnemiesNearLoc(aoeLocation.targetloc, radius)
		if #enemiesInSpotlight >= 2 then
			if DotaTime() >= (bot._spotlightLogAt or -999) then
				bot._spotlightLogAt = DotaTime() + 10
				pcall(
					print,
					string.format("[SHy-RINGMASTER] t=%.0f spotlight on %d enemies", DotaTime(), #enemiesInSpotlight)
				)
			end
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	for _, allyHero in pairs(nearbyAllies) do
		if
			Fu.IsValidHero(allyHero)
			and not Fu.IsRealInvisible(allyHero)
			and Fu.IsInRange(bot, allyHero, castRange + 300)
			and not allyHero:IsIllusion()
			and Fu.CanBeAttacked(allyHero)
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			if
				allyHero:HasModifier("modifier_legion_commander_duel")
				or allyHero:HasModifier("modifier_enigma_black_hole_pull")
				or allyHero:HasModifier("modifier_faceless_void_chronosphere_freeze")
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero:GetLocation()
			end
			local enemiesNearAlly = allyHero:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
			if
				Fu.IsValidHero(enemiesNearAlly[1])
				and not Fu.IsSuspiciousIllusion(enemiesNearAlly[1])
				and not Fu.IsChasingTarget(enemiesNearAlly[1], allyHero)
				and enemiesNearAlly[1]:GetAttackTarget() == allyHero
				and not Fu.IsInEtherealForm(allyHero)
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero:GetLocation()
			end
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if
			Fu.IsTormentor(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.GetHP(botTarget) > 0.5
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderWheelOfWonder()
	if not Fu.CanCastAbility(wheelOfWonderAbility) then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, wheelOfWonderAbility:GetCastRange())
	local castPoint = wheelOfWonderAbility:GetCastPoint()
	local mesmerizeRadius = wheelOfWonderAbility:GetSpecialValueInt("mesmerize_radius")
	local projectileSpeed = wheelOfWonderAbility:GetSpecialValueInt("projectile_speed")
	if Fu.IsInTeamFight(bot, 1600) then
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, mesmerizeRadius, 0, 0)
		local enemiesInWheel = Fu.GetEnemiesNearLoc(aoeLocation.targetloc, mesmerizeRadius)
		-- datafeed: Wheel has a 700 minimum range (min_range). A spot much closer than that makes the wheel
		-- stop past the group, so skip spots nearer than min_range minus most of the mesmerize radius.
		local minRange = wheelOfWonderAbility:GetSpecialValueInt("min_range")
		if
			#enemiesInWheel >= 2
			and GetUnitToLocationDistance(bot, aoeLocation.targetloc) >= minRange - mesmerizeRadius * 0.6
		then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderFunhouseMirror()
	if not Fu.CanCastAbility(funhouseMirrorAbility) or Fu.IsRealInvisible(bot) then
		return BOT_ACTION_DESIRE_NONE
	end
	if Fu.IsStunProjectileIncoming(bot, 350) or Fu.IsUnitTargetProjectileIncoming(bot, 350) then
		return BOT_ACTION_DESIRE_HIGH
	end
	if
		not bot:HasModifier("modifier_sniper_assassinate")
		and not bot:IsMagicImmune()
		and Fu.IsWillBeCastUnitTargetSpell(bot, 300)
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	if isEngaging then
		if Fu.IsValidHero(botTarget) and Fu.IsInRange(bot, botTarget, bot:GetAttackRange() + 300) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if Fu.IsDoingRoshan(bot) or Fu.IsDoingTormentor(bot) then
		-- was Fu.IsTormentor(bot) (Ringmaster himself), never true
		if
			(Fu.IsRoshan(botTarget) or Fu.IsTormentor(botTarget))
			and Fu.IsInRange(bot, botTarget, 900)
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderStrongmanTonic()
	if not Fu.CanCastAbility(strongmanTonicAbility) then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, strongmanTonicAbility:GetCastRange())
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	for _, allyHero in pairs(nearbyAllies) do
		if
			Fu.IsValidHero(allyHero)
			and Fu.IsInRange(bot, allyHero, castRange + 300)
			and not allyHero:IsIllusion()
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and Fu.CanBeAttacked(allyHero)
		then
			if
				allyHero:HasModifier("modifier_legion_commander_duel")
				or allyHero:HasModifier("modifier_enigma_black_hole_pull")
				or allyHero:HasModifier("modifier_faceless_void_chronosphere_freeze")
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero
			end
			local alliesNearAlly = allyHero:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
			local enemiesNearAlly = allyHero:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
			if
				Fu.IsValidHero(enemiesNearAlly[1])
				and Fu.IsRetreating(allyHero)
				and not Fu.IsSuspiciousIllusion(enemiesNearAlly[1])
				and Fu.IsChasingTarget(enemiesNearAlly[1], allyHero)
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero
			end
		end
	end
	if Fu.IsRoshan(botTarget) or Fu.IsTormentor(botTarget) then
		for _, allyHero in pairs(nearbyAllies) do
			if Fu.IsValidHero(allyHero) and Fu.IsInRange(bot, allyHero, castRange) and not allyHero:IsIllusion() then
				if
					(Fu.IsDoingRoshan(allyHero) or Fu.IsDoingTormentor(allyHero))
					and Fu.IsInRange(allyHero, botTarget, 900)
				then
					if Fu.GetHP(allyHero) < 0.15 then
						return BOT_ACTION_DESIRE_HIGH, allyHero
					end
				end
				if
					Fu.GetHP(allyHero) < 0.3
					and not Fu.IsInEtherealForm(allyHero)
					and Fu.CanBeAttacked(allyHero)
					and not allyHero:IsIllusion()
					and not allyHero:HasModifier("modifier_abaddon_borrowed_time")
					and not allyHero:HasModifier("modifier_dazzle_shallow_grave")
					and not allyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
					and not allyHero:HasModifier("modifier_obsidian_destroyer_astral_imprisonment_prison")
				then
					return BOT_ACTION_DESIRE_HIGH, allyHero
				end
			end
		end
	end
	if hpRatio < 0.5 and X.IsBeingAttacked(bot) and not Fu.IsRealInvisible(bot) then
		return BOT_ACTION_DESIRE_HIGH, bot
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderWhoopeeCushion()
	if not Fu.CanCastAbility(whoopeeCushionAbility) then
		return BOT_ACTION_DESIRE_NONE
	end
	whoopeeCushionWhy = "fight"
	local leapDistance = whoopeeCushionAbility:GetSpecialValueInt("leap_distance")
	local fartCloudRadius = whoopeeCushionAbility:GetSpecialValueInt("fart_cloud_radius")
	local nearbyAllies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	if isEngaging then
		if
			Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, leapDistance + fartCloudRadius)
			and not Fu.IsInRange(bot, botTarget, leapDistance)
			and Fu.CanBeAttacked(botTarget)
			and Fu.IsChasingTarget(bot, botTarget)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and #nearbyAllies >= #nearbyEnemies
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	if isRetreating and not Fu.IsRealInvisible(bot) then
		if Fu.IsValidHero(nearbyEnemies[1]) and not Fu.IsSuspiciousIllusion(nearbyEnemies[1]) then
			if #nearbyEnemies > #nearbyAllies + 1 and bot:IsFacingLocation(Fu.GetTeamFountain(), 30) then
				return BOT_ACTION_DESIRE_HIGH
			end
			if
				Fu.IsInRange(bot, nearbyEnemies[1], fartCloudRadius)
				and Fu.IsChasingTarget(nearbyEnemies[1], bot)
				and bot:IsFacingLocation(Fu.GetTeamFountain(), 45)
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	-- Free movement (#49, game 048: a held cushion blocked the next souvenirs for minutes). Game files: 0 mana, 3s
	-- cooldown, a 400 leap where he faces. Walking straight and fast with no enemy hero or enemy tower near the
	-- landing point, outside laning and attack: leap, which also frees the souvenir slot.
	local mode = bot:GetActiveMode()
	if
		#nearbyEnemies == 0
		and mode ~= BOT_MODE_LANING
		and mode ~= BOT_MODE_ATTACK
		and mode ~= BOT_MODE_EVASIVE_MANEUVERS
		and not bot:IsChanneling()
		and bot:GetMovementDirectionStability() >= 0.95
		and bot:GetCurrentMovementSpeed() > 0
		and #(bot:GetNearbyTowers(1300, true) or {}) == 0
	then
		local velocity = bot:GetVelocity()
		if velocity ~= nil and velocity.x * velocity.x + velocity.y * velocity.y >= 250 * 250 then
			whoopeeCushionWhy = "travel"
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderUnicycle()
	if not Fu.CanCastAbility(unicycleAbility) then
		return BOT_ACTION_DESIRE_NONE
	end
	if isEngaging then
		if
			Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, 2200)
			and not Fu.IsInRange(bot, botTarget, 700)
			and (hpRatio > 0.7 or Fu.IsChasingTarget(bot, botTarget))
			and Fu.CanCastOnNonMagicImmune(botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	if isRetreating and not Fu.IsRealInvisible(bot) then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsInRange(bot, enemyHero, 600)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and (hpRatio < 0.5 or Fu.IsChasingTarget(enemyHero, bot))
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
-- It checked Fu.IsValid(unit) instead of the attacker and never asked what the enemy was attacking, so any
-- visible enemy hero or tower made it true: Box on self below 25% HP and Tonic on self below 50% fired
-- anywhere on the map. Now the enemy must be attacking unit.
function X.IsBeingAttacked(unit)
	if not Fu.IsValid(unit) then
		return false
	end
	for _, enemyUnit in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
		if Fu.IsValid(enemyUnit) then
			local unitName = enemyUnit:GetUnitName()
			if
				(Fu.IsValidHero(enemyUnit) or Fu.IsValidBuilding(enemyUnit) or string.find(unitName, "warlock_golem"))
				and enemyUnit:GetAttackTarget() == unit
			then
				return true
			end
		end
	end
	return false
end
function X.IsUnitBetweenMeAndLocation(caster, target, location, width)
	local startLocation = caster:GetLocation()
	local endLocation = location
	for _, enemyUnit in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
		if
			enemyUnit ~= nil
			and enemyUnit:CanBeSeen()
			and GetUnitToUnitDistance(GetBot(), enemyUnit) <= 1600
			and not enemyUnit:IsBuilding()
			and not string.find(enemyUnit:GetUnitName(), "ward")
			and caster ~= enemyUnit
			and target ~= enemyUnit
		then
			local lineInfo = PointToLineDistance(startLocation, endLocation, enemyUnit:GetLocation())
			if lineInfo ~= nil and lineInfo.within and lineInfo.distance <= width then
				return true
			end
		end
	end
	return false
end
return X
